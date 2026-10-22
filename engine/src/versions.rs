//! **Versions** — the film as it stood at a moment, kept so it can be looked
//! at and brought back.
//!
//! His ask, 2026-09-29, on the eve of restructuring *Call Her Back*: *"I might
//! want to refer back to or pivot back to stuff that I delete and change
//! around. This would not just be for the script but the whole project… a
//! snapshot in time I can go back to."*
//!
//! **A version is not a copy.** The log already keeps every change ever made
//! — nothing is removed, not by undo, not by a delete, not by folding old
//! logs together (`storage::fold_logs` rewrites them byte for byte). So the
//! film as it stood last Tuesday is already on disk; what was missing was a
//! way to say *where* last Tuesday ends. That is all a version holds: **the
//! furthest change it had heard from each device** — the store's frontier at
//! the moment it was saved — and a name. Replaying only the changes inside
//! that cut rebuilds the whole film as it was: shots, scenes, boards,
//! locations, diagrams, the document page, the script drafts.
//!
//! A version is a record like any other, so it travels to every device the
//! film does, and costs a few dozen bytes however big the film is.
//!
//! **Going back is forward.** Nothing here rewinds the log; the law is
//! *never destroy*, and sync could not carry a rewind anyway. Bringing a
//! version back writes new changes that put each field back the way it was —
//! exactly what undo does — so it reaches the phone like any edit, is itself
//! one undoable step, and the whole-film kind saves a version of *now* first,
//! so the step away from today is a version too.
//!
//! Three kinds are saved without being asked (`Made`): one at the start of
//! each day the film is worked on, one before a new script draft is taken in,
//! and one before going back. Only the daily ones are ever thinned.

use std::collections::{BTreeMap, HashMap, HashSet};

use crate::doc::{f, Doc};
use crate::id::{now_millis, Id};
use crate::stamp::{DeviceId, Stamp};
use crate::store::{Kind, Op, Record, Store, F_DELETED};
use crate::value::Value;

/// A version's own fields. Its name is `f::LABEL`, as a column's and a
/// unit's are.
pub mod vf {
    /// Where the version stops — `crate::versions::Cut`, as text.
    pub const CUT: &str = "cut";
    /// When it was saved, in milliseconds since 1970.
    pub const TAKEN: &str = "taken";
    /// The day it was saved, as the shell said it (`2026-09-29`) — what the
    /// daily version is keyed on, so "today" means his today, not UTC's.
    pub const DAY: &str = "day";
    /// Who saved it — `Made`.
    pub const MADE: &str = "made";
}

/// Why a version exists.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Made {
    /// He saved it and named it. Never thinned, never touched.
    Hand,
    /// The film as it stood when the day's work began.
    Daily,
    /// The film just before a new script draft was taken in.
    Draft,
    /// The film just before a version was brought back over it.
    GoingBack,
}

impl Made {
    pub fn as_str(self) -> &'static str {
        match self {
            Made::Hand => "hand",
            Made::Daily => "daily",
            Made::Draft => "draft",
            Made::GoingBack => "back",
        }
    }

    pub fn parse(s: &str) -> Made {
        match s {
            "daily" => Made::Daily,
            "draft" => Made::Draft,
            "back" => Made::GoingBack,
            // Anything unknown is treated as his: the safe reading, since his
            // are the ones nothing automatic ever removes.
            _ => Made::Hand,
        }
    }

    pub fn automatic(self) -> bool {
        self != Made::Hand
    }
}

/// **Where a version stops**: the furthest change heard from each device.
///
/// A change is inside the version when its device is in the cut and it is no
/// later than that device's entry. Per device rather than one moment in time,
/// because the clocks of two devices are not one clock: a phone that was
/// offline can deliver changes stamped before the moment of saving, and they
/// were not part of the film anybody saw then.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Cut(BTreeMap<DeviceId, (u64, u32)>);

impl Cut {
    pub fn of(frontier: &[Stamp]) -> Cut {
        Cut(frontier
            .iter()
            .map(|s| (s.device, (s.millis, s.counter)))
            .collect())
    }

    pub fn holds(&self, stamp: &Stamp) -> bool {
        self.0
            .get(&stamp.device)
            .map(|held| (stamp.millis, stamp.counter) <= *held)
            .unwrap_or(false)
    }

    /// `device.millis.counter`, space separated, in device order.
    pub fn encode(&self) -> String {
        self.0
            .iter()
            .map(|(d, (m, c))| format!("{}.{}.{}", d.0, m, c))
            .collect::<Vec<_>>()
            .join(" ")
    }

    pub fn decode(text: &str) -> Option<Cut> {
        let mut held = BTreeMap::new();
        for part in text.split_whitespace() {
            let mut bits = part.split('.');
            let device = bits.next()?.parse().ok()?;
            let millis = bits.next()?.parse().ok()?;
            let counter = bits.next()?.parse().ok()?;
            if bits.next().is_some() {
                return None;
            }
            held.insert(DeviceId(device), (millis, counter));
        }
        Some(Cut(held))
    }
}

/// One saved version, as the shell lists it.
#[derive(Clone, Debug, PartialEq)]
pub struct Version {
    pub id: Id,
    /// What he called it. Empty on a daily one, which the shell names by its
    /// date.
    pub name: String,
    pub taken: u64,
    pub day: String,
    pub made: Made,
    pub cut: Cut,
}

/// What has happened to one kind of thing since a version.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Counts {
    pub added: usize,
    pub removed: usize,
    pub changed: usize,
}

/// **What is different now from a version**, kind by kind, in the order a
/// person thinks of a film.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Since {
    pub kinds: Vec<(&'static str, &'static str, Counts)>,
}

impl Since {
    pub fn is_empty(&self) -> bool {
        self.kinds
            .iter()
            .all(|(_, _, c)| c.added + c.removed + c.changed == 0)
    }

    /// `12 shots removed`, `3 scenes added`, `1 board changed` — counts, in
    /// order, nothing else. What the Versions list shows under each name.
    pub fn words(&self) -> Vec<String> {
        let mut said = Vec::new();
        for (one, many, c) in &self.kinds {
            for (n, what) in [(c.added, "added"), (c.removed, "removed"), (c.changed, "changed")] {
                if n > 0 {
                    said.push(format!("{n} {} {what}", if n == 1 { one } else { many }));
                }
            }
        }
        said
    }
}

/// What bringing a version back did.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Brought {
    /// Records that came back, went away, or were put back as they were.
    pub records: usize,
    /// Fields written to do it.
    pub fields: usize,
    /// The version of *now* saved first, when going back over the whole film.
    pub saved: Option<Id>,
}

/// The kinds the Versions list counts, and what to call them.
const COUNTED: [(Kind, &str, &str); 7] = [
    (Kind::Scene, "scene", "scenes"),
    (Kind::Shot, "shot", "shots"),
    (Kind::MediaRef, "picture", "pictures"),
    (Kind::MoodBoard, "board", "boards"),
    (Kind::Location, "location", "locations"),
    (Kind::DiagramItem, "diagram item", "diagram items"),
    (Kind::ShootDay, "shoot day", "shoot days"),
];

/// **Fields a version never puts back**, because they are not the film's
/// content but its identity, or somebody else's bookkeeping:
///
/// - the Drive folder a location is paired with belongs to the bridge, which
///   moves a deleted location's folder aside and then forgets it. Putting the
///   old name back would point a location at a folder that has gone; left
///   alone, a location that comes back gets a folder of its own, fresh.
/// - on the film's own record, its title and its icon — what the film is
///   called on every device and in Notion, not what it contains.
fn kept_as_is(kind: &Kind, field: &str) -> bool {
    field == f::DRIVE_FOLDER
        // A picture deleted from the Media window stays deleted: going back
        // brings its uses back as gaps with its name, never the picture.
        || (*kind == Kind::Media && field == f::GONE_ON)
        || (*kind == Kind::Project
            && matches!(field, f::TITLE | f::MARK_PATH | f::MARK_COLOUR | f::MARK_SOURCE))
}

/// Daily versions kept whole for this long…
const EVERY_DAY_FOR: u64 = 14 * 24 * 60 * 60 * 1000;
/// …then one a week until this old, then one a month.
const EVERY_WEEK_FOR: u64 = 90 * 24 * 60 * 60 * 1000;

impl Doc {
    // ---- saving ----------------------------------------------------------

    /// Save the film as it stands now, under a name he chose.
    pub fn save_version(&mut self, name: &str) -> Id {
        self.save_version_made(name, Made::Hand)
    }

    /// Save a version of any kind. **Never undoable**: ⌘Z taking back the act
    /// of remembering would lose the one thing it exists to keep, and would
    /// sit on top of the edit he actually meant to undo.
    pub fn save_version_made(&mut self, name: &str, made: Made) -> Id {
        self.save_version_on(name, made, None)
    }

    /// Save a version, saying what day it is where he is. The engine has no
    /// clock of its own worth trusting for that — without it the day is
    /// UTC's, and on the west coast of Canada UTC's tomorrow starts at five
    /// in the afternoon.
    pub fn save_version_on(&mut self, name: &str, made: Made, day: Option<&str>) -> Id {
        let cut = Cut::of(&self.store().frontier());
        let taken = now_millis();
        let day = day
            .map(str::trim)
            .filter(|d| !d.is_empty())
            .map(str::to_string)
            .unwrap_or_else(|| self.today_or(taken));
        let id = self.create_quietly(Kind::Version);
        self.write_without_recording(id, f::LABEL, Value::Text(name.trim().to_string()));
        self.write_without_recording(id, vf::CUT, Value::Text(cut.encode()));
        self.write_without_recording(id, vf::TAKEN, Value::Int(taken as i64));
        self.write_without_recording(id, vf::DAY, Value::Text(day));
        self.write_without_recording(id, vf::MADE, Value::Text(made.as_str().to_string()));
        id
    }

    /// Rename one. Quiet, like saving.
    pub fn rename_version(&mut self, id: Id, name: &str) -> bool {
        if self.version(id).is_none() {
            return false;
        }
        self.write_without_recording(id, f::LABEL, Value::Text(name.trim().to_string()));
        true
    }

    /// Put one away. Only the bookmark goes — the film's history is untouched,
    /// and nothing it pointed at is lost; it simply stops being listed, and
    /// stops holding on to pictures nothing else uses.
    pub fn delete_version(&mut self, id: Id) -> bool {
        if self.version(id).is_none() {
            return false;
        }
        self.write_without_recording(id, F_DELETED, Value::Bool(true));
        true
    }

    /// **The start-of-day version**, if one is due: the film has changed since
    /// the newest version, and no daily one has been saved today. Called by
    /// the shell when a film opens, before any of the day's work lands on it,
    /// so it is the film as the day found it.
    ///
    /// Also thins the older daily ones — every one from the last fortnight,
    /// then one a week to three months, then one a month. His own, and the
    /// ones saved before a draft or before going back, are never thinned.
    pub fn daily_version(&mut self) -> Option<Id> {
        self.daily_version_on(None)
    }

    /// The daily version, keyed on his day rather than the engine's guess.
    pub fn daily_version_on(&mut self, day: Option<&str>) -> Option<Id> {
        let now = now_millis();
        let today = day
            .map(str::trim)
            .filter(|d| !d.is_empty())
            .map(str::to_string)
            .unwrap_or_else(|| self.today_or(now));
        let versions = self.versions();
        let made = if versions.iter().any(|v| v.made == Made::Daily && v.day == today) {
            None
        } else {
            let changed = match versions.first() {
                Some(newest) => self.changed_since(&newest.cut),
                None => !self.changes().is_empty(),
            };
            changed.then(|| self.save_version_on("", Made::Daily, Some(&today)))
        };
        self.thin_daily_versions(now);
        made
    }

    fn thin_daily_versions(&mut self, now: u64) {
        // Newest first; the first of each week or month met is the one kept.
        let mut seen_week: Option<u64> = None;
        let mut seen_month: Option<String> = None;
        let mut going = Vec::new();
        for v in self.versions().into_iter().filter(|v| v.made == Made::Daily) {
            let age = now.saturating_sub(v.taken);
            if age <= EVERY_DAY_FOR {
                continue;
            }
            if age <= EVERY_WEEK_FOR {
                let week = v.taken / (7 * 24 * 60 * 60 * 1000);
                if seen_week == Some(week) {
                    going.push(v.id);
                } else {
                    seen_week = Some(week);
                }
            } else {
                let month: String = v.day.chars().take(7).collect();
                if seen_month.as_deref() == Some(month.as_str()) {
                    going.push(v.id);
                } else {
                    seen_month = Some(month);
                }
            }
        }
        for id in going {
            self.delete_version(id);
        }
    }

    /// Whether anything but versions themselves has been written since a
    /// cut. Saving a version is itself a handful of changes, so comparing
    /// the frontier would call every film changed the moment it was saved.
    fn changed_since(&self, cut: &Cut) -> bool {
        let bookmarks: HashSet<Id> = self
            .changes()
            .iter()
            .filter_map(|c| match &c.op {
                Op::Create { kind: Kind::Version, id } => Some(*id),
                _ => None,
            })
            .collect();
        self.changes().iter().any(|c| {
            let target = match &c.op {
                Op::Create { id, .. } | Op::Set { id, .. } => *id,
            };
            !bookmarks.contains(&target) && !cut.holds(&c.stamp)
        })
    }

    fn today_or(&self, millis: u64) -> String {
        self.today
            .clone()
            .filter(|d| !d.trim().is_empty())
            .unwrap_or_else(|| utc_day(millis))
    }

    // ---- reading ---------------------------------------------------------

    /// Every version, newest first.
    pub fn versions(&self) -> Vec<Version> {
        let mut all: Vec<Version> = self
            .store()
            .of_kind(&Kind::Version)
            .into_iter()
            .filter_map(read_version)
            .collect();
        all.sort_by(|a, b| b.taken.cmp(&a.taken).then(b.id.cmp(&a.id)));
        all
    }

    pub fn version(&self, id: Id) -> Option<Version> {
        let record = self.store().get(id)?;
        if record.kind != Kind::Version {
            return None;
        }
        read_version(record)
    }

    /// **The film as it stood at a version**, rebuilt from the changes inside
    /// its cut. A document of its own, for looking at: nothing written to it
    /// goes anywhere, and the shell must never save it.
    pub fn as_of(&self, id: Id) -> Option<Doc> {
        let version = self.version(id)?;
        Some(self.as_of_cut(&version.cut))
    }

    pub fn as_of_cut(&self, cut: &Cut) -> Doc {
        let mut then = Doc::with_letter_scheme(self.device(), self.letters().clone());
        then.today = self.today.clone();
        then.merge(
            self.changes()
                .iter()
                .filter(|c| cut.holds(&c.stamp))
                .cloned(),
        );
        then.clear_history();
        then
    }

    /// What is different now from a version, kind by kind.
    pub fn since(&self, id: Id) -> Option<Since> {
        let then = self.as_of(id)?;
        Some(compare(then.store(), self.store()))
    }

    // ---- bringing back ---------------------------------------------------

    /// **Bring some things back as they were** — a scene, a shot, a board, a
    /// location — each with what belongs to it: a scene's shots and their
    /// places in it, its pictures and its diagram; a shot's pictures; a
    /// board's wall. Whatever of those came along since is taken away, so the
    /// piece is as it was, not a mixture.
    ///
    /// One undoable step. Nothing outside the pieces is touched.
    pub fn bring_back(&mut self, version: Id, roots: &[Id]) -> Option<Brought> {
        let v = self.version(version)?;
        let then = self.as_of_cut(&v.cut);
        let mut ids: HashSet<Id> = HashSet::new();
        for root in roots {
            ids.extend(piece(then.store(), *root));
            ids.extend(piece(self.store(), *root));
        }
        let label = format!("Bring Back from {}", said_name(&v));
        let tx = self.begin(&label);
        let brought = self.put_back(&then, ids);
        self.end(tx);
        Some(brought)
    }

    /// **Put the whole film back as it was at a version.** Saves a version of
    /// the film as it stands first, so today is never more than one click
    /// away either; then one undoable step puts every record back — the
    /// things made since go, the things removed since return, the things
    /// changed since change back. Versions themselves are left alone, every
    /// one of them.
    pub fn go_back_to(&mut self, version: Id) -> Option<Brought> {
        self.go_back_to_on(version, None)
    }

    /// Going back, saying what day it is — for the version of now it saves.
    pub fn go_back_to_on(&mut self, version: Id, day: Option<&str>) -> Option<Brought> {
        let v = self.version(version)?;
        let then = self.as_of_cut(&v.cut);
        let saved = self.save_version_on(
            &format!("Before going back to {}", said_name(&v)),
            Made::GoingBack,
            day,
        );
        let mut ids: HashSet<Id> = HashSet::new();
        for r in then.store().all_records() {
            ids.insert(r.id);
        }
        for r in self.store().all_records() {
            ids.insert(r.id);
        }
        let label = format!("Go Back to {}", said_name(&v));
        let tx = self.begin(&label);
        let mut brought = self.put_back(&then, ids);
        self.end(tx);
        brought.saved = Some(saved);
        Some(brought)
    }

    fn put_back(&mut self, then: &Doc, ids: HashSet<Id>) -> Brought {
        let mut ids: Vec<Id> = ids.into_iter().collect();
        ids.sort();
        let mut brought = Brought::default();
        for id in ids {
            let Some(now) = self.store().get_raw(id).cloned() else { continue };
            if now.kind == Kind::Version {
                continue;
            }
            let writes: Vec<(String, Value)> = match then.store().get_raw(id) {
                // Made since: it goes, if it is still here.
                None => {
                    if now.is_deleted() {
                        Vec::new()
                    } else {
                        vec![(F_DELETED.to_string(), Value::Bool(true))]
                    }
                }
                Some(was) => {
                    let mut names: Vec<&str> = was.field_names();
                    for n in now.field_names() {
                        if !names.contains(&n) {
                            names.push(n);
                        }
                    }
                    names.sort();
                    names
                        .into_iter()
                        .filter(|n| !kept_as_is(&now.kind, n))
                        .filter_map(|n| {
                            let old = held(was, n);
                            (held(&now, n) != old).then(|| (n.to_string(), old))
                        })
                        .collect()
                }
            };
            if writes.is_empty() {
                continue;
            }
            brought.records += 1;
            brought.fields += writes.len();
            for (field, value) in writes {
                self.set(id, &field, value);
            }
        }
        brought
    }

    // ---- a copy of its own -------------------------------------------------

    /// **Make this document a film of its own** — for a version copied out
    /// as a new film, so an old direction can be taken up beside the current
    /// one. It keeps everything it was; what changes is what would tie it to
    /// the film it came from:
    ///
    /// - its title, which is its name everywhere;
    /// - every location's and board's pairing with Google Drive. Left alone,
    ///   the bridge would carry the copy's photographs into the original's
    ///   folders, and — worse — a location deleted in the copy would have the
    ///   original's folder moved aside. Off, and unpaired, on every one,
    ///   deleted ones included.
    ///
    /// Its link to the relay is not in the document at all (`remote.json`);
    /// the shell simply does not copy it, and the first sync makes a new one.
    pub fn become_a_copy(&mut self, title: &str) {
        let tx = self.begin("Make a copy");
        if let Some(project) = self.store().of_kind(&Kind::Project).first().map(|r| r.id) {
            self.set(project, f::TITLE, Value::Text(title.trim().to_string()));
        }
        let paired: Vec<(Id, Kind)> = self
            .store()
            .all_records()
            .into_iter()
            .filter(|r| r.kind == Kind::Location || r.kind == Kind::MoodBoard)
            .map(|r| (r.id, r.kind.clone()))
            .collect();
        for (id, kind) in paired {
            let record = self.store().get_raw(id).cloned();
            let Some(record) = record else { continue };
            if record.text(f::DRIVE_FOLDER).map(|t| !t.is_empty()).unwrap_or(false) {
                self.set(id, f::DRIVE_FOLDER, Value::Text(String::new()));
            }
            if kind == Kind::Location || record.text(f::SYNC_WITH_DRIVE) == Some("1") {
                self.set(id, f::SYNC_WITH_DRIVE, Value::Text("0".to_string()));
            }
        }
        self.end(tx);
        self.clear_history();
    }

    // ---- keeping what a version needs --------------------------------------

    /// **Every picture some version still shows.** A picture removed today may
    /// be on a shot in last Tuesday's version, and the tidy-up that gives back
    /// the room a removed picture took (`storage::reclaim_orphans`) must not
    /// take it — or last Tuesday comes back with a hole where the frame was.
    pub fn media_kept_by_versions(&self) -> HashSet<Id> {
        self.media_by_version().into_iter().flatten().collect()
    }

    /// The pictures each saved version shows, one set per version.
    pub(crate) fn media_by_version(&self) -> Vec<HashSet<Id>> {
        let versions = self.versions();
        let mut each = Vec::new();
        if versions.is_empty() {
            return each;
        }
        let uses: HashSet<Id> = self
            .changes()
            .iter()
            .filter_map(|c| match &c.op {
                Op::Create { kind: Kind::MediaRef, id } => Some(*id),
                _ => None,
            })
            .collect();
        for v in versions {
            let mut points: HashMap<Id, (Option<Id>, Stamp)> = HashMap::new();
            let mut gone: HashMap<Id, (bool, Stamp)> = HashMap::new();
            for c in self.changes() {
                let Op::Set { id, field, value } = &c.op else { continue };
                if !uses.contains(id) || !v.cut.holds(&c.stamp) {
                    continue;
                }
                if field == f::MEDIA {
                    let newer = points.get(id).map(|(_, s)| c.stamp > *s).unwrap_or(true);
                    if newer {
                        points.insert(*id, (value.as_ref_id(), c.stamp));
                    }
                } else if field == F_DELETED {
                    let newer = gone.get(id).map(|(_, s)| c.stamp > *s).unwrap_or(true);
                    if newer {
                        gone.insert(*id, (value.as_bool().unwrap_or(false), c.stamp));
                    }
                }
            }
            let mut kept = HashSet::new();
            for (use_, (media, _)) in points {
                let deleted = gone.get(&use_).map(|(d, _)| *d).unwrap_or(false);
                if let (Some(media), false) = (media, deleted) {
                    kept.insert(media);
                }
            }
            each.push(kept);
        }
        each
    }
}

fn read_version(record: &Record) -> Option<Version> {
    let cut = Cut::decode(record.text(vf::CUT)?)?;
    let taken = match record.get(vf::TAKEN)? {
        Value::Int(n) => *n as u64,
        Value::Float(n) => *n as u64,
        _ => return None,
    };
    Some(Version {
        id: record.id,
        name: record.text(f::LABEL).unwrap_or("").to_string(),
        taken,
        day: record.text(vf::DAY).unwrap_or("").to_string(),
        made: Made::parse(record.text(vf::MADE).unwrap_or("")),
        cut,
    })
}

/// A field as it stands, with "never written" and "written empty" read the
/// same — which is how every getter already reads them.
fn held(record: &Record, field: &str) -> Value {
    record.get(field).cloned().unwrap_or(Value::Null)
}

/// How a version is named in an undo label — his name for it, or its day.
fn said_name(v: &Version) -> String {
    if v.name.trim().is_empty() {
        v.day.clone()
    } else {
        format!("\u{201c}{}\u{201d}", v.name.trim())
    }
}

/// **A thing and what belongs to it**, read off one store, tombstones and
/// all — a scene removed since still has its shots pointing at it.
fn piece(store: &Store, root: Id) -> HashSet<Id> {
    let mut ids = HashSet::new();
    let Some(record) = store.get_raw(root) else {
        return ids;
    };
    ids.insert(root);
    let all = store.all_records();
    let pointing = |kind: Kind, field: &str, at: &HashSet<Id>| -> Vec<Id> {
        all.iter()
            .filter(|r| r.kind == kind && r.ref_id(field).map(|t| at.contains(&t)).unwrap_or(false))
            .map(|r| r.id)
            .collect()
    };
    let mut owners: HashSet<Id> = HashSet::from([root]);
    match record.kind {
        Kind::Scene => {
            let placements = pointing(Kind::Placement, f::SCENE, &owners);
            for p in &placements {
                if let Some(shot) = store.get_raw(*p).and_then(|r| r.ref_id(f::SHOT)) {
                    owners.insert(shot);
                }
            }
            ids.extend(placements);
            ids.extend(pointing(Kind::DiagramItem, f::SCENE, &HashSet::from([root])));
        }
        Kind::Shot => {
            ids.extend(pointing(Kind::Placement, f::SHOT, &owners));
        }
        Kind::Location => {
            owners.extend(pointing(Kind::Location, f::PARENT, &HashSet::from([root])));
        }
        _ => {}
    }
    ids.extend(owners.iter().copied());
    let uses = pointing(Kind::MediaRef, f::OWNER, &owners);
    for u in &uses {
        if let Some(media) = store.get_raw(*u).and_then(|r| r.ref_id(f::MEDIA)) {
            ids.insert(media);
        }
    }
    ids.extend(uses);
    ids
}

/// Kind by kind, what is live in one store and not the other, and what is
/// live in both but no longer the same.
fn compare(then: &Store, now: &Store) -> Since {
    let mut since = Since::default();
    for (kind, one, many) in COUNTED {
        let before: HashMap<Id, &Record> = then.of_kind(&kind).into_iter().map(|r| (r.id, r)).collect();
        let after: HashMap<Id, &Record> = now.of_kind(&kind).into_iter().map(|r| (r.id, r)).collect();
        let mut c = Counts::default();
        for (id, a) in &after {
            match before.get(id) {
                None => c.added += 1,
                Some(b) => {
                    if !same(b, a) {
                        c.changed += 1
                    }
                }
            }
        }
        c.removed = before.keys().filter(|id| !after.contains_key(id)).count();
        since.kinds.push((one, many, c));
    }
    since
}

fn same(a: &Record, b: &Record) -> bool {
    let mut names: Vec<&str> = a.field_names();
    for n in b.field_names() {
        if !names.contains(&n) {
            names.push(n);
        }
    }
    names.into_iter().all(|n| held(a, n) == held(b, n))
}

/// `2026-09-29`, in UTC — only for a shell that has not said what day it is.
fn utc_day(millis: u64) -> String {
    let days = (millis / 86_400_000) as i64;
    // Howard Hinnant's civil-from-days.
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    format!("{y:04}-{m:02}-{d:02}")
}
