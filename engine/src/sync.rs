//! Telling a disagreement apart from ordinary work.
//!
//! Merging never loses a change and never asks a question: every change is kept
//! in the log, and for any one field the latest stamp wins. That is what makes
//! two devices that received the same changes in a different order end up
//! identical, and it is why there is no such thing here as a merge that fails.
//!
//! But "the latest stamp wins" quietly covers two different situations:
//!
//! - **You changed it after seeing my value.** Ordinary editing. Yours should
//!   win, silently, and being told about it would be noise.
//! - **We both changed it, neither of us knowing about the other.** One value is
//!   now on screen and the other is only in the log. Nothing was lost, but
//!   somebody made a decision that nobody has seen.
//!
//! Only the second is worth a word, and telling them apart is what the watermark
//! on each change is for — see `stamp::Watermark`. A winner that had already
//! seen what it beat is the first case. A winner that had not is the second.
//!
//! Two properties follow, and both matter more than they look:
//!
//! - **It is derived, not recorded.** Clashes are computed from the log, so
//!   every device reports the same ones without having to exchange anything
//!   beyond the changes it already exchanges.
//! - **It settles itself.** Writing the field again produces a change that has
//!   seen both sides, and that change is then the winner — so the clash is gone
//!   because it was actually resolved, not because a flag was cleared.

use std::collections::{HashMap, HashSet};

use crate::doc::{f, Doc};
use crate::id::Id;
use crate::stamp::{DeviceId, Stamp, Watermark};
use crate::store::{Change, Op, Store};
use crate::value::Value;

/// One field two devices decided about independently.
#[derive(Clone, Debug, PartialEq)]
pub struct Clash {
    pub record: Id,
    pub field: String,
    /// The value on screen, and the write it came from.
    pub kept: Value,
    pub kept_stamp: Stamp,
    /// The value that is only in the log.
    pub other: Value,
    pub other_stamp: Stamp,
}

impl Clash {
    pub fn kept_device(&self) -> DeviceId {
        self.kept_stamp.device
    }

    pub fn other_device(&self) -> DeviceId {
        self.other_stamp.device
    }

    /// When the losing decision was made, so it can be said in words.
    pub fn other_millis(&self) -> u64 {
        self.other_stamp.millis
    }
}

impl Store {
    /// Every field where two devices decided independently and one of them is
    /// not on screen.
    ///
    /// Silent about anything it cannot be sure of: a change written by a build
    /// that recorded no watermark makes no claim either way, and two devices
    /// that happened to write the *same* value did not disagree about anything.
    pub fn clashes(&self) -> Vec<Clash> {
        let mut by_field: HashMap<(Id, &str), Vec<&crate::store::Change>> = HashMap::new();
        for change in self.log() {
            if let Op::Set { id, field, .. } = &change.op {
                by_field.entry((*id, field.as_str())).or_default().push(change);
            }
        }

        let mut found = Vec::new();
        for ((id, field), writes) in by_field {
            let Some(winner) = writes.iter().max_by_key(|c| c.stamp) else {
                continue;
            };
            // A winner that recorded nothing about what it had seen cannot be
            // used to accuse anybody. Silence beats a guess.
            if !winner.seen.is_known() {
                continue;
            }
            let winner_value = match &winner.op {
                Op::Set { value, .. } => value,
                _ => continue,
            };

            // The most recent write the winner had not seen, from some other
            // device, that said something different.
            let loser = writes
                .iter()
                .filter(|c| c.stamp != winner.stamp)
                .filter(|c| c.stamp.device != winner.stamp.device)
                .filter(|c| !winner.seen.covers(&c.stamp, winner.stamp.device))
                .filter(|c| match &c.op {
                    Op::Set { value, .. } => value != winner_value,
                    _ => false,
                })
                .max_by_key(|c| c.stamp);

            let Some(loser) = loser else { continue };
            let Op::Set { value: other, .. } = &loser.op else {
                continue;
            };

            found.push(Clash {
                record: id,
                field: field.to_string(),
                kept: winner_value.clone(),
                kept_stamp: winner.stamp,
                other: other.clone(),
                other_stamp: loser.stamp,
            });
        }

        // A stable order, so the same list reads the same way twice.
        found.sort_by(|a, b| {
            b.kept_stamp
                .cmp(&a.kept_stamp)
                .then_with(|| a.field.cmp(&b.field))
        });
        found
    }
}

impl Doc {
    /// Clashes worth showing: the record still exists, and the field is one a
    /// person put there rather than one the app keeps for itself.
    pub fn clashes(&self) -> Vec<Clash> {
        self.store()
            .clashes()
            .into_iter()
            .filter(|clash| self.get(clash.record).is_some())
            .filter(|clash| !is_bookkeeping(&clash.field))
            .collect()
    }

    pub fn clash_count(&self) -> usize {
        self.clashes().len()
    }

    /// The clashes on one record, for a panel or an inspector.
    pub fn clashes_on(&self, record: Id) -> Vec<Clash> {
        self.clashes()
            .into_iter()
            .filter(|clash| clash.record == record)
            .collect()
    }

    /// Whether one cell is in disagreement — what a table needs in order to mark
    /// it, asked cheaply enough to ask per cell.
    pub fn field_has_clash(&self, record: Id, field: &str) -> bool {
        self.clashes()
            .iter()
            .any(|clash| clash.record == record && clash.field == field)
    }

    /// Take a side, and in doing so end the disagreement.
    ///
    /// There is no separate dismissal, because there should not be one: this
    /// writes the value with full knowledge of both sides, which makes it the
    /// winner and makes the clash genuinely resolved. It is one undoable step
    /// like any other edit.
    pub fn resolve_clash(&mut self, clash: &Clash, value: Value) {
        let label = format!("Settle {}", clash.field);
        self.transact(&label, |doc| {
            doc.set(clash.record, &clash.field, value);
        });
    }

    /// Keep what is on screen. The clash goes because the decision was made,
    /// not because it was hidden.
    pub fn keep_mine(&mut self, clash: &Clash) {
        self.resolve_clash(clash, clash.kept.clone());
    }

    pub fn take_theirs(&mut self, clash: &Clash) {
        self.resolve_clash(clash, clash.other.clone());
    }

    /// Said the way it should appear on screen. The engine knows the shot, the
    /// field and both values; it does not know what the devices are called, so
    /// the shell hands over a way to name one.
    ///
    /// A lookup rather than two names in a row on purpose: which side won is
    /// decided by the merge, not by the caller, so a message built from two
    /// positional names is one refactor away from naming the wrong machine.
    pub fn clash_message(&self, clash: &Clash, name_of: impl Fn(DeviceId) -> String) -> String {
        let what = self.describe_record(clash.record);
        let field = clash.field.replace('_', " ");
        format!(
            "{what} — {field} says {}, from {}. {} set it to {} at about the same time, without \
             either knowing about the other. Nothing was lost.",
            shown(&clash.kept),
            name_of(clash.kept_device()),
            name_of(clash.other_device()),
            shown(&clash.other),
        )
    }

    /// A name for a record that a person would recognise — a shot by its number,
    /// a scene by its heading — falling back to the kind when there is nothing
    /// better to say.
    fn describe_record(&self, id: Id) -> String {
        if let Some(number) = self.display_number(id) {
            return format!("Shot {number}");
        }
        // The technical fields live on the shot rather than on its place in a
        // scene, and a shot has no number of its own — the number belongs to the
        // placement. So the most common disagreement of all, two people on one
        // lens, would otherwise be announced about "shot" rather than about 34A.
        let mut numbers: Vec<String> = self
            .placements_of_shot(id)
            .into_iter()
            .filter_map(|placement| self.display_number(placement))
            .collect();
        if !numbers.is_empty() {
            numbers.sort_by(|a, b| crate::natural::compare(a, b));
            // A shot used twice is named by both, because saying only one of
            // them would send somebody to the wrong scene.
            return format!("Shot {}", numbers.join(" / "));
        }
        if let Some(record) = self.get(id) {
            if let Some(title) = record.text(f::TITLE) {
                return title.to_string();
            }
            if let Some(number) = record.text(f::NUMBER) {
                return format!("Scene {number}");
            }
            return record.kind.as_str().replace('_', " ");
        }
        "Something".to_string()
    }
}

/// Fields the app maintains rather than the person editing. Two devices
/// disagreeing about a sort position is not news; disagreeing about a lens is.
///
/// The letter is in here because nobody types one — it is assigned, and during
/// prep it moves on its own every time a scene is reordered. Two devices tidying
/// the same scene would otherwise raise a disagreement about every shot in it,
/// which is exactly the kind of warning people learn to click through. The risk
/// that *is* real when letters merge — two shots ending up on the same one — is
/// caught by `letter_collisions`, which looks at the result rather than at who
/// wrote what.
fn is_bookkeeping(field: &str) -> bool {
    field.starts_with("order")
        || field.starts_with("sort")
        || field.starts_with("column")
        || matches!(field, "letter" | "position" | "updated_at")
}

// ---- two shots on one letter -------------------------------------------

/// A letter held by more than one shot in the same scene.
#[derive(Clone, Debug, PartialEq)]
pub struct Collision {
    pub scene: Id,
    pub letter: String,
    /// The placements holding it, oldest claim first.
    pub placements: Vec<Id>,
}

impl Doc {
    /// Scenes where a merge has left two shots answering to the same number.
    ///
    /// Last-writer-wins settles every *field* on its own, which is right, and
    /// cannot see that two settled fields now say the same thing. Two devices
    /// inserting a shot into scene 34 while out of range will both reach for the
    /// next free letter and both find the same one. Nothing is lost and the two
    /// devices agree — they just agree on something wrong.
    pub fn letter_collisions(&self) -> Vec<Collision> {
        let mut found = Vec::new();
        for scene in self.scenes_in_order() {
            let mut by_letter: HashMap<String, Vec<Id>> = HashMap::new();
            for placement in self.placements_in_scene(scene) {
                if let Some(letter) = self.get(placement).and_then(|r| r.text(f::LETTER)) {
                    by_letter
                        .entry(letter.to_string())
                        .or_default()
                        .push(placement);
                }
            }
            let mut clashing: Vec<Collision> = by_letter
                .into_iter()
                .filter(|(_, placements)| placements.len() > 1)
                .map(|(letter, mut placements)| {
                    // Oldest claim first: whoever has been carrying that number
                    // longest is the one other people may have written down.
                    placements.sort_by_key(|id| {
                        self.get(*id)
                            .and_then(|r| r.stamp_of(f::LETTER))
                            .map(|stamp| (stamp.millis, stamp.counter, stamp.device.0))
                    });
                    Collision {
                        scene,
                        letter,
                        placements,
                    }
                })
                .collect();
            clashing.sort_by(|a, b| a.letter.cmp(&b.letter));
            found.append(&mut clashing);
        }
        found
    }

    /// Give every shot in a scene a letter of its own again.
    ///
    /// In prep this is just a reflow — letters follow position anyway. Once
    /// letters are locked the first claim keeps its letter and the later ones
    /// take the next free letters, because the point of locking is that a number
    /// somebody has already written on a callsheet does not move.
    pub fn resolve_letter_collisions(&mut self, scene: Id) -> usize {
        if !self.letters_are_locked() {
            return self.reflow_letters(scene);
        }

        let collisions: Vec<Collision> = self
            .letter_collisions()
            .into_iter()
            .filter(|collision| collision.scene == scene)
            .collect();
        if collisions.is_empty() {
            return 0;
        }

        let mut used: HashSet<String> = self
            .placements_in_scene(scene)
            .iter()
            .filter_map(|id| self.get(*id).and_then(|r| r.text(f::LETTER)))
            .map(|letter| letter.to_string())
            .collect();

        let mut moved = 0;
        let tx = self.begin("Renumber shots");
        for collision in collisions {
            // Skip the first: it keeps what it had.
            for placement in collision.placements.iter().skip(1) {
                let letter = self.letters().next_free(&used);
                used.insert(letter.clone());
                self.set(*placement, f::LETTER, Value::text(&letter));
                moved += 1;
            }
        }
        self.end(tx);
        moved
    }
}

/// A value in words, for a sentence or for a button. Public so a shell can
/// label "Use 47mm" without inventing its own spelling of a value — Ref 231.
pub fn shown(value: &Value) -> String {
    match value {
        Value::Null => "nothing".to_string(),
        Value::Text(text) if text.is_empty() => "nothing".to_string(),
        Value::Text(text) => format!("\u{201c}{text}\u{201d}"),
        Value::Bool(true) => "yes".to_string(),
        Value::Bool(false) => "no".to_string(),
        Value::List(items) if items.is_empty() => "nothing".to_string(),
        Value::List(items) => items.iter().map(shown).collect::<Vec<_>>().join(", "),
        Value::Int(n) => n.to_string(),
        Value::Float(n) => format!("{n}"),
        Value::Ref(id) => id.to_hex(),
    }
}

// ---- what every device has certainly seen -------------------------------

impl Doc {
    /// **The point past which a change is known everywhere.** Ref 192.
    ///
    /// The append-only log is what makes deleting anything a decision rather
    /// than an accident: a change never stops existing, so nothing can quietly
    /// come back. Reclaiming the bytes behind a deleted picture is the one
    /// place that has to be broken on purpose, and the question it has to
    /// answer first is *has every device heard about the deletion yet*.
    /// Deleting a file another machine's records still point at makes a hollow
    /// frame on that machine, which is the fault [Ref 223] is about.
    ///
    /// Nothing new has to be exchanged to answer it. Every change already
    /// carries how far its writer had caught up — see `stamp::Watermark` —
    /// so the last thing each device wrote says what that device had seen.
    /// A change is settled when every *other* device's latest word covers it.
    ///
    /// Returns the last word from each device, ready to ask `covers` of. Empty
    /// when any device is at `Unknown` — a build from before watermarks were
    /// recorded makes no claim in either direction, and nothing is inferred on
    /// its behalf, so nothing is settled at all.
    pub fn last_word_per_device(&self) -> Vec<(DeviceId, &Watermark)> {
        let mut latest: HashMap<DeviceId, &Change> = HashMap::new();
        for change in self.changes() {
            latest
                .entry(change.stamp.device)
                .and_modify(|held| {
                    if change.stamp > held.stamp {
                        *held = change;
                    }
                })
                .or_insert(change);
        }
        if latest.values().any(|change| !change.seen.is_known()) {
            return Vec::new();
        }
        let mut words: Vec<(DeviceId, &Watermark)> = latest
            .into_iter()
            .map(|(device, change)| (device, &change.seen))
            .collect();
        words.sort_by_key(|(device, _)| *device);
        words
    }

    /// Whether every device has heard about `stamp`.
    ///
    /// A device that has not written since is taken at its last word, which is
    /// the conservative reading: it holds the line until it comes back and
    /// says otherwise. One machine that never opens the project again means
    /// nothing is ever settled — which is the right way round for a rule whose
    /// only use is deciding what may be destroyed.
    pub fn settled(&self, stamp: &Stamp, words: &[(DeviceId, &Watermark)]) -> bool {
        !words.is_empty()
            && words
                .iter()
                .all(|(device, word)| word.covers(stamp, *device))
    }

    /// **Pictures nothing points at any more, and every device knows it.**
    ///
    /// The ones `orphaned_media` names, narrowed to the ones whose last word
    /// on the subject is settled everywhere. `newest` is the most recent
    /// change touching the picture's record or any use of it — the moment it
    /// became an orphan, at the latest.
    pub fn settled_orphans(&self) -> Vec<Id> {
        let orphans = self.orphaned_media();
        if orphans.is_empty() {
            return Vec::new();
        }
        let words = self.last_word_per_device();
        if words.is_empty() {
            return Vec::new();
        }

        // **Every use ever made of each orphan, taken from the log rather
        // than from the records.** This is the whole of it, and reading the
        // records instead is the bug I wrote first: a use that has been struck
        // off is a deleted record, deleted records are not in `of_kind`, and
        // so the very change that has to have travelled — the one that removed
        // the frame — was the one change being ignored. Everything then looked
        // settled the instant it was orphaned, which is the opposite of the
        // question being asked. The log keeps deleted and living alike.
        let mut watching: HashMap<Id, Id> = HashMap::new();
        for change in self.changes() {
            if let Op::Set { id, field, value } = &change.op {
                if field == f::MEDIA {
                    if let Some(media) = value.as_ref_id() {
                        watching.insert(*id, media);
                    }
                }
            }
        }

        let mut newest: HashMap<Id, Stamp> = HashMap::new();
        for change in self.changes() {
            let target = match &change.op {
                Op::Create { id, .. } => *id,
                Op::Set { id, .. } => *id,
            };
            let media = if orphans.contains(&target) {
                target
            } else {
                match watching.get(&target) {
                    Some(media) => *media,
                    None => continue,
                }
            };
            newest
                .entry(media)
                .and_modify(|held| {
                    if change.stamp > *held {
                        *held = change.stamp;
                    }
                })
                .or_insert(change.stamp);
        }

        orphans
            .into_iter()
            .filter(|media| match newest.get(media) {
                Some(stamp) => self.settled(stamp, &words),
                // Nothing in the log mentions it at all, which cannot happen
                // for a record that exists. Refusing is the safe answer.
                None => false,
            })
            .collect()
    }
}
