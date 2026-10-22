//! **Every picture a film holds, in one list.** His ask, 2026-10-10 (Notion
//! SL-1687, mockup `design/44-media.html`): see every picture and clip, where
//! each is used and which are not, how big each is; delete one for real; and
//! one button for everything nothing uses.
//!
//! Until this, taking a picture off a shot took away the *use* and left the
//! file to a sweep that waits for every device that ever opened the film to
//! catch up (`settled_orphans`). One device that never checks in and the file
//! stays for ever: on 2026-10-10 that was 79 pictures, 54 MB, in Call Her Back.
//! Deleting here does not wait. It is his decision, made on purpose.
//!
//! **A deleted picture leaves its name behind.** His words: *"maybe it could
//! remember the name of that photo so that if I wanted to go back I could
//! find it and upload again."* So the record stays, with its name, size and
//! the moment it went (`f::GONE_ON`), and only the bytes go. Going back to a
//! version that showed it brings the use back pointing at that record, which
//! draws as a gap with the name on it; going back never clears `GONE_ON`
//! (`versions::kept_as_is`). Dropping the same file in again brings the
//! record back to life (`add_media`), so every version that showed it shows
//! it again.

use std::collections::HashMap;

use crate::doc::{f, Doc};
use crate::id::{now_millis, Id};
use crate::media::MediaKind;
use crate::store::Kind;
use crate::value::Value;

/// One picture or clip, and everywhere it is used.
#[derive(Clone, Debug, PartialEq)]
pub struct Shelved {
    pub media: Id,
    pub hash: String,
    pub filename: String,
    pub kind: MediaKind,
    pub bytes: u64,
    pub width: i64,
    pub height: i64,
    pub seconds: f64,
    pub uses: Vec<Use>,
    /// How many saved versions show it.
    pub versions: usize,
}

impl Shelved {
    pub fn used(&self) -> bool {
        !self.uses.is_empty()
    }
}

/// One place a picture is used.
#[derive(Clone, Debug, PartialEq)]
pub struct Use {
    pub media_ref: Id,
    pub owner: Id,
    /// `shot`, `scene`, `location`, `board` or `diagram`.
    pub kind: &'static str,
    /// `Shot 12B`, `Ellis House`, `Mood Board · Night`, `Diagram · Scene 4`.
    pub label: String,
    /// What it sits in, when that helps: a shot's scene.
    pub detail: String,
    /// The scene to go to for it, for a shot, a scene or a scene's diagram.
    pub scene: Option<Id>,
}

/// A picture deleted here: what is left of it.
#[derive(Clone, Debug, PartialEq)]
pub struct Gone {
    pub media: Id,
    pub hash: String,
    pub filename: String,
    pub bytes: u64,
    /// Milliseconds since 1970.
    pub on: i64,
}

impl Doc {
    /// Whether this file was deleted here and only its name is left.
    pub fn media_is_gone(&self, media: Id) -> bool {
        self.store()
            .get_raw(media)
            .map(|r| r.get(f::GONE_ON).map(|v| !v.is_null()).unwrap_or(false))
            .unwrap_or(false)
    }

    /// **Every picture and clip, biggest first.** Deleted ones are not here;
    /// they are `gone_media`.
    pub fn shelf(&self) -> Vec<Shelved> {
        let shown = self.media_shown_by_versions();
        let mut uses: HashMap<Id, Vec<Use>> = HashMap::new();
        for r in self.store().of_kind(&Kind::MediaRef) {
            let Some(media) = r.ref_id(f::MEDIA) else { continue };
            if let Some(use_) = self.describe_use(r.id) {
                uses.entry(media).or_default().push(use_);
            }
        }
        let mut all: Vec<Shelved> = self
            .store()
            .of_kind(&Kind::Media)
            .iter()
            .filter(|r| !self.media_is_gone(r.id))
            .map(|r| {
                let mut u = uses.remove(&r.id).unwrap_or_default();
                u.sort_by(|a, b| a.label.cmp(&b.label));
                Shelved {
                    media: r.id,
                    hash: r.text(f::HASH).unwrap_or_default().to_string(),
                    filename: r.text(f::FILENAME).unwrap_or_default().to_string(),
                    kind: MediaKind::parse(r.text(f::MEDIA_KIND).unwrap_or("")),
                    bytes: int(r.get(f::BYTES)).max(0) as u64,
                    width: int(r.get(f::WIDTH)),
                    height: int(r.get(f::HEIGHT)),
                    seconds: r.get(f::DURATION).and_then(|v| v.as_float()).unwrap_or(0.0),
                    uses: u,
                    versions: shown.get(&r.id).copied().unwrap_or(0),
                }
            })
            .collect();
        all.sort_by(|a, b| b.bytes.cmp(&a.bytes).then(a.filename.cmp(&b.filename)));
        all
    }

    /// Deleted pictures, newest first. Name, size and when.
    pub fn gone_media(&self) -> Vec<Gone> {
        let mut gone: Vec<Gone> = self
            .store()
            .of_kind(&Kind::Media)
            .iter()
            .filter_map(|r| {
                let on = int(r.get(f::GONE_ON));
                (on > 0).then(|| Gone {
                    media: r.id,
                    hash: r.text(f::HASH).unwrap_or_default().to_string(),
                    filename: r.text(f::FILENAME).unwrap_or_default().to_string(),
                    bytes: int(r.get(f::BYTES)).max(0) as u64,
                    on,
                })
            })
            .collect();
        gone.sort_by(|a, b| b.on.cmp(&a.on).then(a.filename.cmp(&b.filename)));
        gone
    }

    /// Where one use sits, in words. `None` when its owner is gone — a use
    /// left behind by a shot deleted elsewhere, which counts as no use at all.
    pub fn describe_use(&self, media_ref: Id) -> Option<Use> {
        let owner = self.get(media_ref)?.ref_id(f::OWNER)?;
        let record = self.get(owner)?;
        let (kind, label, detail, scene) = match record.kind {
            Kind::Shot => {
                let placement = *self.placements_of_shot(owner).first()?;
                let number = self.display_number(placement).unwrap_or_default();
                let scene = self.get(placement).and_then(|p| p.ref_id(f::SCENE));
                let said = scene
                    .and_then(|s| self.get(s))
                    .and_then(|s| s.text(f::NUMBER).map(str::to_string))
                    .unwrap_or_default();
                let detail = if said.is_empty() { String::new() } else { format!("Scene {said}") };
                ("shot", format!("Shot {number}"), detail, scene)
            }
            Kind::Scene => {
                let number = record.text(f::NUMBER).unwrap_or_default();
                ("scene", format!("Scene {number}"), String::new(), Some(owner))
            }
            Kind::Location => ("location", self.location_full_name(owner), String::new(), None),
            Kind::MoodBoard => {
                ("board", format!("Mood Board \u{b7} {}", self.board_name(owner)), String::new(), None)
            }
            Kind::EditRef => (
                "edit",
                format!("Edit Reference \u{b7} {}", record.text(f::LABEL).unwrap_or_default()),
                String::new(),
                None,
            ),
            Kind::DiagramItem => {
                let on = record.ref_id(f::SCENE).and_then(|s| self.get(s))?;
                let (label, scene) = match on.kind {
                    Kind::Scene => (format!("Scene {}", on.text(f::NUMBER).unwrap_or_default()), Some(on.id)),
                    _ => (self.plan_name(on.id), None),
                };
                ("diagram", format!("Diagram \u{b7} {label}"), String::new(), scene)
            }
            _ => ("other", String::new(), String::new(), None),
        };
        Some(Use { media_ref, owner, kind, label, detail, scene })
    }

    /// **Delete pictures for real.** Every use goes, the bytes are the
    /// caller's to remove (it gets the hashes back), and the record stays as
    /// a name. Not undoable: the bytes are gone, so an undo could only put
    /// back a hole. Returns the hashes whose files should go.
    pub fn delete_media(&mut self, media: &[Id]) -> Vec<String> {
        let mut hashes = Vec::new();
        let tx = self.begin("Delete Media");
        for &m in media {
            let Some(record) = self.get(m) else { continue };
            if record.kind != Kind::Media || self.media_is_gone(m) {
                continue;
            }
            let hash = record.text(f::HASH).unwrap_or_default().to_string();
            let refs: Vec<Id> = self
                .store()
                .referring_to(&Kind::MediaRef, f::MEDIA, m)
                .iter()
                .map(|r| r.id)
                .collect();
            for media_ref in refs {
                self.drop_use(media_ref);
            }
            self.set(m, f::GONE_ON, Value::Int(now_millis() as i64));
            if !hash.is_empty() {
                hashes.push(hash);
            }
        }
        self.end(tx);
        self.clear_history();
        hashes
    }

    /// Everything nothing uses, as `delete_media` takes it.
    pub fn unused_media(&self) -> Vec<Id> {
        self.shelf().into_iter().filter(|s| !s.used()).map(|s| s.media).collect()
    }

    /// A use taken away, and the owner's key frame moved on if it was this.
    /// The file is left alone: `delete_media` is deciding about that.
    fn drop_use(&mut self, media_ref: Id) {
        let owner = self.get(media_ref).and_then(|r| r.ref_id(f::OWNER));
        self.delete(media_ref);
        let Some(owner) = owner else { return };
        let stale = self
            .get(owner)
            .and_then(|r| r.ref_id(f::KEY_MEDIA))
            .map(|k| k == media_ref)
            .unwrap_or(false);
        if stale {
            match self.media_refs(owner).first().copied() {
                Some(next) => self.set(owner, f::KEY_MEDIA, next),
                None => self.set(owner, f::KEY_MEDIA, Value::Null),
            }
            self.set(owner, f::KEY_CHOSEN, Value::Null);
        }
    }

    /// The same picture dropped in again after it was deleted: it is itself
    /// again, and every version that showed it shows it again.
    pub(crate) fn revive_media(&mut self, media: Id) {
        if self.media_is_gone(media) {
            self.set(media, f::GONE_ON, Value::Null);
        }
    }

    /// Per picture, how many saved versions show it.
    pub fn media_shown_by_versions(&self) -> HashMap<Id, usize> {
        let mut count: HashMap<Id, usize> = HashMap::new();
        for set in self.media_by_version() {
            for m in set {
                *count.entry(m).or_insert(0) += 1;
            }
        }
        count
    }
}

fn int(v: Option<&Value>) -> i64 {
    match v {
        Some(Value::Int(n)) => *n,
        Some(Value::Float(n)) => *n as i64,
        _ => 0,
    }
}
