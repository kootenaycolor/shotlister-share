//! The record store and its change log.
//!
//! Two ideas do all the work here:
//!
//! 1. **State is derived from changes.** The log is the truth; the record map is
//!    a cache you could throw away and rebuild. History and undo fall out of this
//!    rather than being bolted on.
//!
//! 2. **Every field is last-writer-wins, on a total order.** Applying the same
//!    set of changes in any order lands on the same state, so two devices that
//!    sync in different sequences agree. Only writes to *the same field* can
//!    conflict; different fields simply both land.
//!
//! A record is a bag of named values, not a fixed struct. That is what makes the
//! forward-compatibility rule free: a build that has never heard of a field still
//! holds it, and still passes it on.

use std::collections::{BTreeMap, HashMap, HashSet};

use crate::id::Id;
use crate::stamp::{DeviceId, Stamp, Watermark};
use crate::value::Value;

/// Field name used for tombstones. Deletion is an ordinary last-writer-wins
/// field, so undelete is just writing `false` and needs no special machinery.
pub const F_DELETED: &str = "deleted";

#[derive(Clone, PartialEq, Eq, Hash, Debug)]
pub enum Kind {
    Project,
    Scene,
    Shot,
    Placement,
    Sequence,
    ShootDay,
    Unit,
    /// One moment covered by more than one camera. A record of its own so that
    /// membership is a fact about the setup rather than about whichever shot
    /// happened to be named first.
    Setup,
    /// A file, identified by its contents. Shared by everything that uses it.
    Media,
    /// One *use* of a file, by a shot or a scene. Carries the caption and the
    /// position, because those belong to the use rather than to the file.
    MediaRef,
    /// A column the project made for itself — label, field slug, and kind.
    /// Schema, not data: it says what a shot *can* carry, project-wide.
    Column,
    /// One draft of the screenplay, as imported. Holds what it was called, the
    /// file it came from and when it landed; the text itself lives beside the
    /// media, addressed by its hash, because a screenplay is far too big to
    /// belong in a change log.
    Revision,
    /// **A real place**, with an address, a pin on a map, photographs and — from
    /// the phone — a LiDAR scan of the room. Scenes point at one.
    ///
    /// Its field names are the phone's JSON field names on purpose: the phone
    /// has been writing `locations/<id>/location.json` beside the project while
    /// waiting for this, and matching them makes reading those in a copy rather
    /// than a translation. See `handoff/from-phone.md`.
    Location,
    /// **A wall of references** — a name and an ordered set of pictures, and
    /// nothing else. Not tied to a scene, because a mood board is usually
    /// about a look rather than about a moment: *Night Exteriors*, *Anya*,
    /// *The Diner*.
    ///
    /// Its photographs are `Kind::Media` reached through `Kind::MediaRef`,
    /// exactly as a shot's frames and a location's photographs are — which is
    /// why a board needed no media machinery of its own. A board that invented
    /// its own way to hold a picture would be a second answer to a question
    /// already answered, the same argument the location record made.
    MoodBoard,
    /// **One beat of an AV script** — a label, what we see, what we hear —
    /// in order, in a section. His ruling, 2026-09-19: the AV script is a
    /// shot-level thing; a shot is tied to one beat. Scenes stay for places
    /// and setups and carry no script of their own.
    Beat,
    /// **One thing on a scene's diagram** — a wall, a camera, a person, a
    /// light. Its whole description is one small JSON text (`body`), written
    /// by `diagram::stored`; the scene it belongs to and where it sits in the
    /// stack are fields beside it. One record per element rather than one
    /// per diagram, because every change is logged and relayed for ever: a
    /// camera dragged a foot should cost that camera, not the whole plan.
    DiagramItem,
    /// **A version** — the film as it stood at one moment, kept by name so it
    /// can be looked at and brought back. Not a copy: the log already holds
    /// every change ever made, so a version is only the point in it to stop
    /// at. See `crate::versions`.
    Version,
    /// **A loose plan** — a diagram that belongs to no scene. A name and a
    /// place in the list; its pieces are `DiagramItem`s pointing at it just
    /// as a scene's point at the scene. See `diagram::plans`.
    Plan,
    /// **An edit reference** (the Edit Reference mod, 2026-10-17): a clip, a
    /// run of stills or an animatic showing how several shots cut together.
    /// A name, the shots in cut order and where each starts in the clip; the
    /// clip itself is `Kind::Media` through `Kind::MediaRef`, as a board's
    /// pictures are. See `crate::editref`. An older build keeps it as
    /// `Other("edit_ref")`, intact.
    EditRef,
    /// A record referenced before its `Create` arrived. Resolves on merge.
    Unresolved,
    /// A record type written by a newer build. Held intact, never dropped.
    Other(String),
}

impl Kind {
    pub fn as_str(&self) -> &str {
        match self {
            Kind::Project => "project",
            Kind::Scene => "scene",
            Kind::Shot => "shot",
            Kind::Placement => "placement",
            Kind::Sequence => "sequence",
            Kind::ShootDay => "shoot_day",
            Kind::Unit => "unit",
            Kind::Setup => "setup",
            Kind::Media => "media",
            Kind::MediaRef => "media_ref",
            Kind::Column => "column",
            Kind::Revision => "revision",
            Kind::Location => "location",
            Kind::MoodBoard => "mood_board",
            Kind::Beat => "beat",
            Kind::DiagramItem => "diagram_item",
            Kind::Version => "version",
            Kind::Plan => "plan",
            Kind::EditRef => "edit_ref",
            Kind::Unresolved => "?",
            Kind::Other(s) => s,
        }
    }

    pub fn parse(s: &str) -> Kind {
        match s {
            "project" => Kind::Project,
            "scene" => Kind::Scene,
            "shot" => Kind::Shot,
            "placement" => Kind::Placement,
            "sequence" => Kind::Sequence,
            "shoot_day" => Kind::ShootDay,
            "unit" => Kind::Unit,
            "setup" => Kind::Setup,
            "media" => Kind::Media,
            "media_ref" => Kind::MediaRef,
            "column" => Kind::Column,
            "revision" => Kind::Revision,
            "location" => Kind::Location,
            "mood_board" => Kind::MoodBoard,
            "beat" => Kind::Beat,
            "diagram_item" => Kind::DiagramItem,
            "version" => Kind::Version,
            "plan" => Kind::Plan,
            "edit_ref" => Kind::EditRef,
            "?" => Kind::Unresolved,
            other => Kind::Other(other.to_string()),
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum Op {
    Create { kind: Kind, id: Id },
    Set { id: Id, field: String, value: Value },
}

#[derive(Clone, Debug, PartialEq)]
pub struct Change {
    pub stamp: Stamp,
    /// How caught-up the writing device was. Carries no weight in the merge —
    /// the stamp alone decides that — and exists so a disagreement can be told
    /// apart from an ordinary sequence of edits. See `sync`.
    pub seen: Watermark,
    pub op: Op,
}

impl Change {
    /// A change from a build or a log that recorded no watermark.
    pub fn new(stamp: Stamp, op: Op) -> Change {
        Change {
            stamp,
            seen: Watermark::Unknown,
            op,
        }
    }
}

#[derive(Clone, Debug)]
pub struct Record {
    pub id: Id,
    pub kind: Kind,
    fields: HashMap<String, (Value, Stamp)>,
}

impl Record {
    fn new(id: Id, kind: Kind) -> Record {
        Record {
            id,
            kind,
            fields: HashMap::new(),
        }
    }

    pub fn get(&self, field: &str) -> Option<&Value> {
        self.fields.get(field).map(|(v, _)| v)
    }

    pub fn stamp_of(&self, field: &str) -> Option<Stamp> {
        self.fields.get(field).map(|(_, s)| *s)
    }

    pub fn text(&self, field: &str) -> Option<&str> {
        self.get(field).and_then(|v| v.as_text())
    }

    pub fn float(&self, field: &str) -> Option<f64> {
        self.get(field).and_then(|v| v.as_float())
    }

    pub fn bool(&self, field: &str) -> bool {
        self.get(field).and_then(|v| v.as_bool()).unwrap_or(false)
    }

    pub fn ref_id(&self, field: &str) -> Option<Id> {
        self.get(field).and_then(|v| v.as_ref_id())
    }

    pub fn is_deleted(&self) -> bool {
        self.bool(F_DELETED)
    }

    /// Every field name present, including ones this build does not understand.
    pub fn field_names(&self) -> Vec<&str> {
        self.fields.keys().map(|s| s.as_str()).collect()
    }

    /// Every field with the stamp of the write that set it — what a snapshot
    /// saves, so a restored record settles a later merge exactly as the
    /// replayed one would.
    pub fn fields_with_stamps(&self) -> impl Iterator<Item = (&str, &Value, Stamp)> {
        self.fields
            .iter()
            .map(|(name, (value, stamp))| (name.as_str(), value, *stamp))
    }
}

#[derive(Clone, Debug, Default)]
pub struct Store {
    records: HashMap<Id, Record>,
    log: Vec<Change>,
    /// Where each stamp already sits in `log`, so a change the log has is not
    /// written into it a second time.
    ///
    /// **A `Vec` per stamp, not a single index.** A stamp is unique only while
    /// device ids are, and his *Call Her Back* proved on 2026-09-08 that they are
    /// not always: one machine had worn two device names. Two installations
    /// sharing an id could mint one stamp for two different changes, and
    /// throwing the second away on the strength of the stamp alone would lose
    /// somebody's work. So the stamp narrows the search and the change itself
    /// settles it.
    logged: HashMap<Stamp, Vec<usize>>,
    /// The furthest stamp seen from each device, over everything ever applied
    /// or restored — winners and losers alike.
    ///
    /// **This is what a snapshot has to carry for the clock**, and it cannot be
    /// read back off the records: a device whose every write was later beaten
    /// leaves no stamp on any field, and a reader that restored the records
    /// alone would then write changes claiming never to have heard from it.
    /// That is Ref 339's bug from the other side — every one of its writes
    /// would read as a clash on the Mac. So the frontier is kept as it goes.
    frontier: BTreeMap<DeviceId, (u64, u32)>,
}

impl Store {
    pub fn new() -> Store {
        Store::default()
    }

    /// Rebuild state from a log. Order of `changes` does not matter.
    pub fn from_changes(changes: impl IntoIterator<Item = Change>) -> Store {
        let mut store = Store::new();
        for change in changes {
            store.apply(change);
        }
        store
    }

    pub fn log(&self) -> &[Change] {
        &self.log
    }

    /// Apply a change. Idempotent and commutative: replaying, reordering, or
    /// duplicating changes cannot alter the result.
    pub fn apply(&mut self, change: Change) {
        self.advance(change.stamp);
        let accepted = match &change.op {
            Op::Create { kind, id } => {
                let entry = self
                    .records
                    .entry(*id)
                    .or_insert_with(|| Record::new(*id, kind.clone()));
                // A record can be referenced before its Create arrives; when it
                // does, it upgrades the placeholder rather than replacing it and
                // losing whatever fields already landed.
                if entry.kind == Kind::Unresolved && *kind != Kind::Unresolved {
                    entry.kind = kind.clone();
                }
                true
            }
            Op::Set { id, field, value } => {
                let entry = self
                    .records
                    .entry(*id)
                    .or_insert_with(|| Record::new(*id, Kind::Unresolved));
                match entry.fields.get(field) {
                    Some((_, existing)) if *existing >= change.stamp => false,
                    _ => {
                        entry
                            .fields
                            .insert(field.clone(), (value.clone(), change.stamp));
                        true
                    }
                }
            }
        };
        // The log keeps everything, including changes that lost. They are what a
        // merge from a third device needs in order to reach the same state, and
        // what history is read from.
        //
        // **Everything, but each thing once.** This pushed unconditionally, so
        // merging a log the document already held duplicated every change in
        // it. The state was never wrong — `apply` settles records by stamp and
        // a repeat changes nothing — but the *log* is what gets written to disk
        // and sent to the relay, and it grew every time.
        //
        // It ran away on his own film, 2026-09-08: one change file reached
        // 732,702 bytes holding 649 distinct changes, the same set about eleven
        // times over. `Project::save` wrote the surplus out, the bigger file was
        // merged again on the next open, and the relay ended up refusing that
        // name for ever because its copy no longer matched. See
        // `merging_the_same_log_twice_adds_nothing`.
        let _ = accepted;
        if let Some(at) = self.logged.get(&change.stamp) {
            if at.iter().any(|&index| self.log[index] == change) {
                return;
            }
        }
        let index = self.log.len();
        self.logged.entry(change.stamp).or_default().push(index);
        self.log.push(change);
    }

    pub fn merge(&mut self, changes: impl IntoIterator<Item = Change>) {
        for change in changes {
            self.apply(change);
        }
    }

    fn advance(&mut self, stamp: Stamp) {
        let held = self.frontier.entry(stamp.device).or_insert((0, 0));
        if (stamp.millis, stamp.counter) > *held {
            *held = (stamp.millis, stamp.counter);
        }
    }

    /// The furthest stamp seen from each device, in device order.
    pub fn frontier(&self) -> Vec<Stamp> {
        self.frontier
            .iter()
            .map(|(device, (millis, counter))| Stamp {
                millis: *millis,
                counter: *counter,
                device: *device,
            })
            .collect()
    }

    /// Every record, tombstones included, in id order — the whole of the
    /// state, for saving it.
    pub fn all_records(&self) -> Vec<&Record> {
        let mut all: Vec<&Record> = self.records.values().collect();
        all.sort_by_key(|r| r.id);
        all
    }

    /// Put a record back exactly as a snapshot saved it: its kind and every
    /// field with the stamp it was written under. **No change is applied and
    /// nothing reaches the log** — that is the whole point of restoring. A
    /// field already held keeps whichever stamp is later, so restoring over a
    /// store that has taken changes cannot move it backwards.
    pub(crate) fn restore_record(
        &mut self,
        id: Id,
        kind: Kind,
        fields: impl IntoIterator<Item = (String, Value, Stamp)>,
    ) {
        let entry = self
            .records
            .entry(id)
            .or_insert_with(|| Record::new(id, kind.clone()));
        if entry.kind == Kind::Unresolved && kind != Kind::Unresolved {
            entry.kind = kind;
        }
        for (field, value, stamp) in fields {
            let held = self.frontier.entry(stamp.device).or_insert((0, 0));
            if (stamp.millis, stamp.counter) > *held {
                *held = (stamp.millis, stamp.counter);
            }
            match entry.fields.get(&field) {
                Some((_, existing)) if *existing >= stamp => {}
                _ => {
                    entry.fields.insert(field, (value, stamp));
                }
            }
        }
    }

    /// A stamp the store is to count as heard without any change behind it —
    /// how a snapshot hands on the writes that lost, whose stamps are on no
    /// record.
    pub(crate) fn hear(&mut self, stamp: Stamp) {
        self.advance(stamp);
    }

    pub fn get(&self, id: Id) -> Option<&Record> {
        self.records.get(&id).filter(|r| !r.is_deleted())
    }

    /// Including tombstones — needed by history and by merge bookkeeping.
    pub fn get_raw(&self, id: Id) -> Option<&Record> {
        self.records.get(&id)
    }

    pub fn exists(&self, id: Id) -> bool {
        self.get(id).is_some()
    }

    /// Live records of a kind, in no particular order.
    /// Live records of a kind, **in the order they were created**.
    ///
    /// The sort is not decoration. Records live in a `HashMap`, so without it
    /// this hands back a different order every time the program runs — and it
    /// did: opening the same film twice listed his cameras FX6, FX3 one time
    /// and FX3, FX6 the next, with nothing changed in between. Found
    /// 2026-09-01, while proving that moving the view model changed nothing;
    /// two of three films failed that comparison and the *code* was identical.
    ///
    /// Ids are roughly time-ordered by construction, so sorting by id is
    /// creation order, which is the order a person expects a list they built to
    /// be in. Thirty-odd callers read this, including the one that picks the
    /// project record by taking the first of its kind.
    pub fn of_kind(&self, kind: &Kind) -> Vec<&Record> {
        let mut found: Vec<&Record> = self
            .records
            .values()
            .filter(|r| &r.kind == kind && !r.is_deleted())
            .collect();
        found.sort_by_key(|r| r.id);
        found
    }

    /// **Deleted** records of a kind, oldest first — the tombstones.
    ///
    /// A deleted record keeps every field it had, and one program needs
    /// that: the Drive bridge, which has to tell a folder somebody made in
    /// Drive from the folder of a location somebody deleted in the app. The
    /// two are identical on disk. Only the tombstone knows the difference.
    pub fn tombstones_of_kind(&self, kind: &Kind) -> Vec<&Record> {
        let mut found: Vec<&Record> = self
            .records
            .values()
            .filter(|r| &r.kind == kind && r.is_deleted())
            .collect();
        found.sort_by_key(|r| r.id);
        found
    }

    /// Live records of a kind whose `field` points at `target`.
    pub fn referring_to(&self, kind: &Kind, field: &str, target: Id) -> Vec<&Record> {
        self.records
            .values()
            .filter(|r| &r.kind == kind && !r.is_deleted() && r.ref_id(field) == Some(target))
            .collect()
    }

    pub fn count_of_kind(&self, kind: &Kind) -> usize {
        self.of_kind(kind).len()
    }

    /// A canonical rendering of everything the store holds, for comparing two
    /// stores that should agree. Sorted, so it does not depend on insertion
    /// order or on how a hash map felt that day.
    pub fn fingerprint(&self) -> String {
        let mut lines: Vec<String> = Vec::new();
        for record in self.records.values() {
            for (field, (value, _)) in record.fields.iter() {
                lines.push(format!(
                    "{}\t{}\t{}\t{:?}",
                    record.id.to_hex(),
                    record.kind.as_str(),
                    field,
                    value
                ));
            }
        }
        lines.sort();
        lines.join("\n")
    }

    /// Field names in use across a kind, understood or not. Lets an export list
    /// columns a newer build introduced instead of silently dropping them.
    pub fn known_fields(&self, kind: &Kind) -> HashSet<String> {
        let mut out = HashSet::new();
        for record in self.records.values().filter(|r| &r.kind == kind) {
            for name in record.fields.keys() {
                out.insert(name.clone());
            }
        }
        out
    }
}
