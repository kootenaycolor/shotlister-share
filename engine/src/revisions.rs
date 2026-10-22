//! Drafts of the screenplay, and taking one in.
//!
//! A revision is not an action, it is a thing the project keeps: what it was
//! called, the file it came from, when it landed. He will import many over a
//! shoot, and the question on the Thursday one is never "what does it say" but
//! "what is different from the list I already have".
//!
//! **Nothing here decides anything.** The law of this project is *report, never
//! invent — and never destroy*, so the shape is two halves that cannot
//! disagree: [`Doc::plan_revision`] works out what would happen and changes
//! nothing, and [`Doc::take_revision`] does it from the very same plan. The
//! confirm screen a person reads is [`Plan::sentences`] — the plan's own words,
//! not a second description of it written somewhere else and liable to drift.
//!
//! **A scene that has left the script is archived, with every shot still on
//! it.** Cadrage's own import says the same thing on its last screen, having
//! presumably arrived at it the same way: a revision is not authority to throw
//! away somebody's work. Archived scenes come back with one click.
//!
//! The text of a draft is stored beside the media, addressed by its hash, for
//! the same reason media is: a screenplay is far too big to live in a change
//! log that syncs line by line. The record here is the small part — the name,
//! the file, the date — and it travels like everything else.

use crate::cast;
use crate::doc::{f, Doc};
use crate::id::Id;
use crate::pages;
use crate::screenplay::{Detection, Screenplay, Status};
use crate::store::Kind;
use crate::value::Value;

/// The column characters are offered from. A **label**, not a field: a column
/// the project makes for itself gets a generated slug, and the slug is where
/// its list of terms actually lives. Writing the cast under the word "cast"
/// would put it somewhere nothing reads.
pub const CAST_COLUMN: &str = "Cast";

/// One draft the project has taken in.
#[derive(Clone, Debug, PartialEq)]
pub struct Revision {
    pub id: Id,
    /// What it is called. Defaults to the date it arrived, and is editable.
    pub name: String,
    /// The file it was read out of, for saying where it came from.
    pub filename: String,
    /// When it landed, as the shell wrote it. The engine keeps no clock — it
    /// has no business knowing what day it is — so this arrives from outside
    /// and is stored exactly as given.
    pub imported_at: String,
    /// Where the text is, in the same store the media uses.
    pub hash: String,
}

/// What to take out of a draft. Everything is a person's choice; nothing here
/// has a default that acts on its own.
#[derive(Clone, Debug, Default)]
pub struct Taking {
    /// Which of the draft's scenes to take, by index into `Screenplay::scenes`.
    pub scenes: Vec<usize>,
    /// Which characters to add to the Cast list, by name.
    pub cast: Vec<String>,
    /// Whether scenes the draft no longer mentions should be archived. Off
    /// unless somebody says so, and archiving is as far as it ever goes.
    pub archive_omitted: bool,
    /// **Which draft scenes are being taken as a scene that moved**, by index
    /// into `Screenplay::scenes` — Ref 241.
    ///
    /// A tick here changes what taking that scene *means*: instead of making a
    /// new scene at the new number and leaving the old one behind with its
    /// shots on it, the scene the project already has is carried across and
    /// renumbered. Empty by default, like everything else here: a move is
    /// offered and never assumed.
    pub moves: Vec<usize>,
    /// The dials the cast list in front of somebody was read with. Carried so
    /// that what lands on a scene is the same set of names they ticked, spelled
    /// the same way — reading it again with different settings would put
    /// `JIMMY (V.O.)` on a scene whose list says `JIMMY`.
    pub cast_options: cast::Options,
}

/// What taking a draft would do — and, afterwards, what it did. The same value
/// answers both, which is the point: a confirm screen that is computed
/// separately from the work is a confirm screen that can be wrong.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Plan {
    /// Scenes the project already has, which this draft also has.
    pub linked: Vec<String>,
    /// Scenes the project does not have yet.
    pub created: Vec<String>,
    /// Scenes the project has that the draft no longer mentions, with how much
    /// work sits on each — which is the number somebody needs in order to
    /// decide. Empty unless archiving was asked for.
    pub archived: Vec<(String, usize)>,
    /// The same list, when archiving was *not* asked for: reported so that it
    /// is never a surprise, and acted on by nobody.
    pub left_alone: Vec<(String, usize)>,
    /// Scenes carried across to a new number, with what came with them —
    /// `("12", "14", 6)`. Ref 241.
    pub moved: Vec<(String, String, usize)>,
    pub cast_added: Vec<String>,
}

impl Plan {
    pub fn is_empty(&self) -> bool {
        self.linked.is_empty()
            && self.created.is_empty()
            && self.archived.is_empty()
            && self.moved.is_empty()
            && self.cast_added.is_empty()
    }

    /// The confirm screen, in sentences. One per consequence, in plain words,
    /// counted from what is actually ticked rather than from what was found.
    pub fn sentences(&self) -> Vec<String> {
        let mut said = Vec::new();
        if !self.linked.is_empty() {
            said.push(format!(
                "{} existing {} will be linked to the new revision.",
                self.linked.len(),
                thing(self.linked.len(), "scene", "scenes")
            ));
        }
        if !self.created.is_empty() {
            said.push(format!(
                "{} new {} will be created.",
                self.created.len(),
                thing(self.created.len(), "scene", "scenes")
            ));
        }
        // **Said before the archiving line**, because a move is the reason a
        // scene is *not* in it — reading "12 is no longer in the script" and
        // then "12 became 14" in that order is alarming for no reason.
        if !self.moved.is_empty() {
            let shots: usize = self.moved.iter().map(|(_, _, shots)| shots).sum();
            let each: Vec<String> = self
                .moved
                .iter()
                .map(|(from, to, _)| format!("{from} → {to}"))
                .collect();
            said.push(format!(
                "{} {} moved to a new number ({}), carrying {} {} across.",
                self.moved.len(),
                thing(self.moved.len(), "scene has", "scenes have"),
                each.join(", "),
                shots,
                thing(shots, "shot", "shots"),
            ));
        }
        if !self.archived.is_empty() {
            let shots: usize = self.archived.iter().map(|(_, shots)| shots).sum();
            said.push(format!(
                "{} existing {} no longer in the script and will be moved to archived scenes, keeping {} {} on {}.",
                self.archived.len(),
                thing(self.archived.len(), "scene is", "scenes are"),
                shots,
                thing(shots, "shot", "shots"),
                thing(self.archived.len(), "it", "them"),
            ));
        }
        if !self.left_alone.is_empty() {
            said.push(format!(
                "{} existing {} no longer in the script. Nothing will happen to {}.",
                self.left_alone.len(),
                thing(self.left_alone.len(), "scene is", "scenes are"),
                thing(self.left_alone.len(), "it", "them"),
            ));
        }
        if !self.cast_added.is_empty() {
            said.push(format!(
                "{} {} will be created as {} in the Cast column of your shot lists.",
                self.cast_added.len(),
                thing(self.cast_added.len(), "character", "characters"),
                thing(self.cast_added.len(), "an option", "options"),
            ));
        }
        if said.is_empty() {
            said.push("Nothing would change.".to_string());
        }
        said
    }
}

fn thing<'a>(count: usize, one: &'a str, many: &'a str) -> &'a str {
    if count == 1 {
        one
    } else {
        many
    }
}

/// Where the detection dials live on the project record.
mod kept {
    pub const NUMBER: &str = "detect_number";
    pub const DUPLICATES: &str = "detect_duplicates";
    pub const ROOMS: &str = "detect_rooms";
    pub const CONTAINS: &str = "detect_contains";
    pub const FORBIDS: &str = "detect_forbids";
}

impl Doc {
    /// The detection dials this project reads scripts with.
    ///
    /// A film that prints `CONTINUED:` in some particular way prints it that
    /// way in every revision, so tuning the rules once should survive to the
    /// next draft of the same film. Falls back to the settings for a printed
    /// script, which is what a PDF is and what these dials exist for.
    pub fn detection(&self) -> Detection {
        let Some(project) = self.project_id() else {
            return Detection::printed();
        };
        let Some(record) = self.get(project) else {
            return Detection::printed();
        };
        let standard = Detection::printed();
        let flag = |key: &str, fallback: bool| {
            record
                .get(key)
                .and_then(|value| value.as_bool())
                .unwrap_or(fallback)
        };
        let words = |key: &str, fallback: Vec<String>| match record.get(key) {
            Some(value) => match value.as_list() {
                Some(items) => items
                    .iter()
                    .filter_map(|item| item.as_text().map(str::to_string))
                    .collect(),
                None => fallback,
            },
            None => fallback,
        };
        Detection {
            must_have_a_number: flag(kept::NUMBER, standard.must_have_a_number),
            ignore_duplicate_numbers: flag(kept::DUPLICATES, standard.ignore_duplicate_numbers),
            find_sub_slugs: flag(kept::ROOMS, standard.find_sub_slugs),
            must_contain: words(kept::CONTAINS, standard.must_contain.clone()),
            never_contains: words(kept::FORBIDS, standard.never_contains.clone()),
        }
    }

    /// Remember the dials, so the next draft of this film reads the same way.
    pub fn set_detection(&mut self, detection: &Detection) {
        let Some(project) = self.project_id() else {
            return;
        };
        let tx = self.begin("Script detection settings");
        self.set(project, kept::NUMBER, Value::Bool(detection.must_have_a_number));
        self.set(
            project,
            kept::DUPLICATES,
            Value::Bool(detection.ignore_duplicate_numbers),
        );
        self.set(project, kept::ROOMS, Value::Bool(detection.find_sub_slugs));
        let list = |words: &[String]| {
            Value::List(words.iter().map(|word| Value::text(word)).collect())
        };
        self.set(project, kept::CONTAINS, list(&detection.must_contain));
        self.set(project, kept::FORBIDS, list(&detection.never_contains));
        self.end(tx);
    }

    /// Every draft the project has taken in, newest first.
    pub fn revisions(&self) -> Vec<Revision> {
        let mut found: Vec<Revision> = self
            .store()
            .of_kind(&Kind::Revision)
            .into_iter()
            .map(|record| Revision {
                id: record.id,
                name: record.text(f::LABEL).unwrap_or_default().to_string(),
                filename: record.text(f::FILENAME).unwrap_or_default().to_string(),
                imported_at: record.text(f::IMPORTED_AT).unwrap_or_default().to_string(),
                hash: record.text(f::HASH).unwrap_or_default().to_string(),
            })
            // A revision with no date is not one anybody made: undo restores a
            // record's fields rather than removing the record, so an import
            // taken back would otherwise leave a nameless ghost in the list.
            .filter(|revision| !revision.imported_at.is_empty())
            .collect();
        // Newest first, and by when it landed rather than by when the record
        // happens to sit in the log — two machines importing on the same day
        // must still agree about which is latest.
        found.sort_by(|a, b| b.imported_at.cmp(&a.imported_at));
        found
    }

    /// The newest draft, which is the one the app means by "the script".
    pub fn latest_revision(&self) -> Option<Revision> {
        self.revisions().into_iter().next()
    }

    pub fn revision(&self, id: Id) -> Option<Revision> {
        self.revisions().into_iter().find(|r| r.id == id)
    }

    /// Rename a draft. The only thing about a revision anybody edits.
    pub fn rename_revision(&mut self, revision: Id, name: &str) {
        let tx = self.begin("Rename a revision");
        self.set(revision, f::LABEL, Value::text(name));
        self.end(tx);
    }

    /// The field the Cast column keeps its terms under, if the project has a
    /// Cast column at all. Found by its label, because that is the only stable
    /// thing about a column the project made for itself — the slug is generated
    /// and differs from project to project.
    pub fn cast_field(&self) -> Option<String> {
        self.custom_columns()
            .into_iter()
            .find(|column| column.label.eq_ignore_ascii_case(CAST_COLUMN))
            .map(|column| column.field)
    }

    /// Everybody the Cast column offers.
    pub fn cast_list(&self) -> Vec<String> {
        match self.cast_field() {
            Some(field) => self.vocabulary(&field),
            None => Vec::new(),
        }
    }

    /// The revision a scene was last seen in.
    pub fn revision_of(&self, scene: Id) -> Option<Id> {
        self.get(scene)
            .and_then(|record| record.get(f::REVISION).cloned())
            .and_then(|value| value.as_text().and_then(crate::id::Id::from_hex))
    }

    /// What taking this draft would do. Changes nothing at all.
    /// **A scene that moved to a new number** — Ref 241.
    ///
    /// The import compares drafts *by number*, so a scene that moved from 12
    /// to 14 reads as one scene gone and one scene new: the old one keeps six
    /// shots nobody will ever look at again, and the new one starts empty.
    /// This finds the pairs, and **finds is all it does** — what to do about
    /// one is a tick on the import sheet.
    ///
    /// The rule is deliberately dull rather than clever:
    ///
    /// - Both scenes must be at the **same location** and the same
    ///   interior/exterior. A scene that moved house is a different scene.
    /// - Both must have **words under them**, and those words must overlap by
    ///   at least four fifths. Two scenes at one location with nothing written
    ///   under either would match everything, which is worse than matching
    ///   nothing.
    /// - Each project scene and each draft scene is used **at most once**, best
    ///   pair first, so a scene split into two cannot claim both.
    ///
    /// Conservative on purpose: two scenes in the same kitchen on the same day
    /// can read almost identically, and the cost of a wrong guess is somebody's
    /// shot list attached to the wrong scene. Missing a move costs a tick.
    pub fn moved_scenes(&self, screenplay: &Screenplay, taking: &Taking) -> Vec<Moved> {
        let here = self.scenes_as_they_stand();
        let there = draft_side(screenplay, taking);
        let mut found: Vec<Moved> = Vec::new();
        for (a, b) in align(&here, &there) {
            let mine = &here[a];
            let theirs = &there[b];
            // Same number, same scene: nothing moved, and the ordinary link
            // takes it.
            if crate::natural::same(&mine.number, &theirs.number) {
                continue;
            }
            found.push(Moved {
                scene: mine.scene,
                index: theirs.index,
                from: mine.number.clone(),
                to: theirs.number.clone(),
                // The project's own heading, and the draft's when it has
                // none. A scene that came in from a spreadsheet rather than a
                // script has no heading stored at all, and a row reading
                // "54 → 60 … 8 shots" with a hole in the middle tells you
                // nothing about which scene you are about to move.
                heading: if mine.heading.is_empty() {
                    theirs.heading.clone()
                } else {
                    mine.heading.clone()
                },
                shots: self.placements_in_scene(mine.scene).len(),
            });
        }
        found.sort_by(|x, y| crate::natural::compare(&x.to, &y.to));
        found
    }

    /// Every live numbered scene the project holds, in the order it holds them.
    fn scenes_as_they_stand(&self) -> Vec<Side> {
        let mut out = Vec::new();
        for scene in self.scenes_in_order() {
            let Some(record) = self.get(scene) else { continue };
            let number = record.text(f::NUMBER).unwrap_or_default().to_string();
            if number.is_empty() || self.is_archived(scene) {
                continue;
            }
            out.push(Side {
                scene,
                index: 0,
                number,
                heading: record.text(f::HEADING).unwrap_or_default().to_string(),
                location: record.text(f::LOCATION).unwrap_or_default().to_string(),
                int_ext: record.text(f::INT_EXT).unwrap_or_default().to_string(),
                words: body_words(record.text(f::SCRIPT).unwrap_or_default()),
            });
        }
        out
    }

    /// The scenes the project has that this draft does not account for, with
    /// the work sitting on each.
    ///
    /// **By record, not by number.** `plan_revision` only needs the numbers to
    /// print, but `take_revision` archives *after* it has renumbered scenes, and
    /// by then a number can be worn by a different record than the one that was
    /// meant. Looking the scene up by its number at that point archives the
    /// wrong one — silently, with somebody's shots on it.
    fn omitted_scenes(&self, screenplay: &Screenplay, taking: &Taking) -> Vec<(Id, String, usize)> {
        let moving: Vec<Moved> = self
            .moved_scenes(screenplay, taking)
            .into_iter()
            .filter(|m| taking.moves.contains(&m.index))
            .collect();
        let mut spoken_for: Vec<String> = Vec::new();
        for index in &taking.scenes {
            let Some(scene) = screenplay.scenes.get(*index) else {
                continue;
            };
            let number = numbering(scene);
            if number.is_empty() {
                continue;
            }
            spoken_for.push(number.clone());
            if let Some(m) = moving.iter().find(|m| m.index == *index) {
                spoken_for.push(m.from.clone());
            }
        }
        let mut missing = Vec::new();
        for scene in self.scenes_in_order() {
            let Some(record) = self.get(scene) else { continue };
            let number = record.text(f::NUMBER).unwrap_or_default().to_string();
            // A scene with no number was never in a numbered draft, so a
            // numbered draft not mentioning it says nothing about it.
            if number.is_empty() || self.is_archived(scene) {
                continue;
            }
            if spoken_for
                .iter()
                .any(|got| crate::natural::same(got, &number))
            {
                continue;
            }
            missing.push((scene, number, self.placements_in_scene(scene).len()));
        }
        missing
    }

    pub fn plan_revision(&self, screenplay: &Screenplay, taking: &Taking) -> Plan {
        let mut plan = Plan::default();
        let mut taken: Vec<String> = Vec::new();

        // The moves that were actually ticked — Ref 241. Found for everything,
        // acted on only where somebody said so.
        let moving: Vec<Moved> = self
            .moved_scenes(screenplay, taking)
            .into_iter()
            .filter(|m| taking.moves.contains(&m.index))
            .collect();

        for index in &taking.scenes {
            let Some(scene) = screenplay.scenes.get(*index) else {
                continue;
            };
            let number = numbering(scene);
            if number.is_empty() {
                continue;
            }
            taken.push(number.clone());
            // A ticked move is neither a new scene nor a link: the scene the
            // project has is carried across, so **both** numbers are spoken
            // for and neither belongs in the other lists.
            if let Some(m) = moving.iter().find(|m| m.index == *index) {
                taken.push(m.from.clone());
                plan.moved.push((m.from.clone(), m.to.clone(), m.shots));
                continue;
            }
            // **A record that is moving away cannot also be linked to.** If
            // the project's scene 21 is being carried to 22, then the draft's
            // own new 21 is a different scene and needs a record of its own —
            // otherwise both would be written into the same one and the move
            // would eat the scene that replaced it.
            match self
                .scene_numbered(&number)
                .filter(|id| !moving.iter().any(|m| m.scene == *id))
            {
                Some(_) => plan.linked.push(number),
                None => plan.created.push(number),
            }
        }

        // What the project has that this draft does not mention.
        let missing: Vec<(String, usize)> = self
            .omitted_scenes(screenplay, taking)
            .into_iter()
            .map(|(_, number, shots)| (number, shots))
            .collect();
        if taking.archive_omitted {
            plan.archived = missing;
        } else {
            plan.left_alone = missing;
        }

        let known = match self.cast_field() {
            Some(field) => self.vocabulary(&field),
            None => Vec::new(),
        };
        for name in &taking.cast {
            if known.iter().any(|got| got.eq_ignore_ascii_case(name)) {
                continue;
            }
            if !plan.cast_added.iter().any(|got| got.eq_ignore_ascii_case(name)) {
                plan.cast_added.push(name.clone());
            }
        }

        plan
    }

    /// Take the draft in, exactly as the plan said. One undoable step however
    /// many scenes it touches: a draft applied by mistake is one ⌘Z rather than
    /// an afternoon.
    pub fn take_revision(
        &mut self,
        screenplay: &Screenplay,
        taking: &Taking,
        revision: &Revision,
    ) -> Plan {
        // **The film as it stood before this draft, kept.** A draft can move,
        // rename and archive dozens of scenes in one go — the exact moment he
        // will later want to look back past. (`crate::versions`)
        let before = if revision.name.trim().is_empty() {
            "Before new draft".to_string()
        } else {
            format!("Before draft \u{201c}{}\u{201d}", revision.name.trim())
        };
        self.save_version_made(&before, crate::versions::Made::Draft);
        let plan = self.plan_revision(screenplay, taking);
        // The same list the plan was computed from, so what happens and what
        // was promised cannot drift — Ref 241.
        let moving: Vec<Moved> = self
            .moved_scenes(screenplay, taking)
            .into_iter()
            .filter(|m| taking.moves.contains(&m.index))
            .collect();
        // **Which record each draft scene lands on, decided before a single
        // thing is written.**
        //
        // A renumbering draft moves several scenes at once, and while that is
        // happening two records can wear the same number. Looking a scene up by
        // number *during* the loop finds whichever one holds it at that
        // instant — so a scene could be written over by the wrong draft scene,
        // which is the very failure this change exists to end. Everything is
        // resolved against the project as it stands, and then acted on.
        let targets: Vec<(usize, Option<Id>)> = taking
            .scenes
            .iter()
            .filter_map(|index| {
                let scene = screenplay.scenes.get(*index)?;
                if numbering(scene).is_empty() {
                    return None;
                }
                let landing = match moving.iter().find(|m| m.index == *index) {
                    Some(m) => Some(m.scene),
                    None => self
                        .scene_numbered(&numbering(scene))
                        .filter(|id| !moving.iter().any(|m| m.scene == *id)),
                };
                Some((*index, landing))
            })
            .collect();
        // And what is being archived, **by record rather than by number** — by
        // the time this runs a number can be worn by a different scene than the
        // one that was meant, and archiving that one buries somebody's shots.
        let doomed: Vec<Id> = if taking.archive_omitted {
            self.omitted_scenes(screenplay, taking)
                .into_iter()
                .map(|(scene, _, _)| scene)
                .collect()
        } else {
            Vec::new()
        };

        let tx = self.begin("Take in a new draft");

        let id = self.create(Kind::Revision);
        self.set(id, f::LABEL, Value::text(&revision.name));
        self.set(id, f::FILENAME, Value::text(&revision.filename));
        self.set(id, f::IMPORTED_AT, Value::text(&revision.imported_at));
        self.set(id, f::HASH, Value::text(&revision.hash));

        // Two facts the reader works out and would otherwise drop on the
        // floor. Both are cheap here and expensive later: the length means
        // laying the whole screenplay out again, and who speaks in a scene
        // means reading the whole script again.
        let laid = pages::lay_out(screenplay);
        let speakers = cast::read(screenplay, taking.cast_options);

        for (index, landing) in &targets {
            let index = *index;
            let Some(scene) = screenplay.scenes.get(index) else {
                continue;
            };
            let number = numbering(scene);
            // **A ticked move renumbers the scene the project already has**,
            // rather than making a new one beside it — Ref 241. The number
            // still comes from the script; what changed is which of our
            // records wears it, which is the whole point of the tick.
            let target = match landing {
                Some(existing) => {
                    if self
                        .get(*existing)
                        .and_then(|r| r.text(f::NUMBER).map(str::to_string))
                        .is_none_or(|held| !crate::natural::same(&held, &number))
                    {
                        self.set(*existing, f::NUMBER, Value::text(&number));
                    }
                    *existing
                }
                None => self.create_scene(&number),
            };
            self.write_scene(target, &scene.script);
            self.set(target, f::REVISION, Value::text(&id.to_hex()));

            if let Some(extent) = laid.extent_of(index) {
                self.set(target, f::EIGHTHS, Value::Int(extent.eighths as i64));
                self.set(
                    target,
                    f::SCRIPT_PAGE,
                    Value::Int(extent.starts_on as i64),
                );
            }

            // Only people who were actually ticked. A cast list somebody pruned
            // must not come back scene by scene through another door.
            let here: Vec<Value> = speakers
                .iter()
                .filter(|member| member.scenes.contains(&index))
                .filter(|member| {
                    taking
                        .cast
                        .iter()
                        .any(|ticked| ticked.eq_ignore_ascii_case(&member.name))
                })
                .map(|member| Value::text(&member.name))
                .collect();
            if !here.is_empty() {
                self.set(target, f::CAST, Value::List(here));
            }
        }

        for scene in &doomed {
            self.archive_scene(*scene, true);
        }

        if !plan.cast_added.is_empty() {
            // The column first: without one there is no field to keep the list
            // under, and the terms would go somewhere nothing reads.
            let field = match self.cast_field() {
                Some(field) => field,
                None => {
                    self.add_column(CAST_COLUMN, "multi");
                    self.cast_field().unwrap_or_default()
                }
            };
            if !field.is_empty() {
                let mut list = self.vocabulary(&field);
                list.extend(plan.cast_added.iter().cloned());
                let terms: Vec<&str> = list.iter().map(String::as_str).collect();
                self.set_vocabulary(&field, &terms);
            }
        }

        self.end(tx);
        plan
    }

    /// How long a scene is, as it was measured when its draft was taken in.
    pub fn scene_eighths(&self, scene: Id) -> Option<usize> {
        self.get(scene)
            .and_then(|record| record.get(f::EIGHTHS).cloned())
            .and_then(|value| value.as_int())
            .map(|number| number.max(0) as usize)
    }

    /// The same, written the way an AD writes it: `2 3/8`.
    pub fn scene_length(&self, scene: Id) -> Option<String> {
        self.scene_eighths(scene).map(|eighths| {
            pages::Extent {
                scene: 0,
                label: String::new(),
                starts_on: 0,
                lines: 0,
                eighths,
            }
            .length()
        })
    }

    /// Who the script says speaks in this scene.
    pub fn scene_cast(&self, scene: Id) -> Vec<String> {
        self.get(scene)
            .and_then(|record| record.get(f::CAST).cloned())
            .and_then(|value| value.as_list().map(|items| {
                items
                    .iter()
                    .filter_map(|item| item.as_text().map(str::to_string))
                    .collect()
            }))
            .unwrap_or_default()
    }
}

/// What a scene would be numbered if it were taken.
///
/// A numbered scene keeps the script's number, which is law. A room lettered
/// under its parent — `3A` — has no number of its own, and its label is the
/// only thing it could sensibly be called; taking one is always a deliberate
/// tick, never something that happens by itself.
/// One scene the draft appears to have renumbered — Ref 241.
#[derive(Clone, Debug, PartialEq)]
pub struct Moved {
    /// The scene the project already has, with the shots on it.
    pub scene: Id,
    /// Where it is in the draft, so a tick can name it the same way the other
    /// lists do.
    pub index: usize,
    pub from: String,
    pub to: String,
    pub heading: String,
    /// How much work would move with it — the number somebody needs in order
    /// to decide.
    pub shots: usize,
}

/// The words under a scene, lowercased, with punctuation thrown away.
///
/// Deliberately not the slugline: the heading is checked separately and
/// exactly, and including it here would let two scenes match on their heading
/// alone when neither has anything written under it.
/// One scene on either side of the comparison, reduced to what deciding needs.
#[derive(Clone, Debug)]
struct Side {
    /// The project's record. Meaningless on the draft's side.
    scene: Id,
    /// Where it sits in `Screenplay::scenes`. Meaningless on the project's side.
    index: usize,
    number: String,
    heading: String,
    location: String,
    int_ext: String,
    /// The words under it, sorted and de-duplicated, ready for `overlap`.
    words: Vec<String>,
}

fn draft_side(screenplay: &Screenplay, taking: &Taking) -> Vec<Side> {
    let mut out = Vec::new();
    for index in &taking.scenes {
        let Some(scene) = screenplay.scenes.get(*index) else {
            continue;
        };
        let number = numbering(scene);
        if number.is_empty() {
            continue;
        }
        out.push(Side {
            scene: Id::default(),
            index: *index,
            number,
            heading: scene.script.heading.clone(),
            location: scene.script.location.clone(),
            int_ext: scene.script.int_ext.clone(),
            words: body_words(&scene.script.body),
        });
    }
    out
}

/// Whether these two are the same scene, and how sure that is — `None` when
/// they are not a candidate at all.
///
/// **Nothing written under either one falls back to the number**, which is
/// exactly what the import has always gone on. Many of his projects have scenes
/// that never came from a script and have no body at all; guessing at those
/// from a heading alone would be inventing.
fn likeness(mine: &Side, theirs: &Side, bar: f64) -> Option<f64> {
    let same_number = crate::natural::same(&mine.number, &theirs.number);
    if mine.words.is_empty() || theirs.words.is_empty() {
        return if same_number { Some(1.0) } else { None };
    }
    // **A scene that moved house is a different scene** — his rule, and the
    // reason the bar here is high: two scenes in the same kitchen on the same
    // day read almost identically, and the cost of a wrong guess is somebody's
    // shot list hanging off the wrong scene.
    //
    // It is weighed rather than gated, though, and that distinction is the
    // whole of Ref 488. Demanding the location match *exactly* meant a slug that
    // had merely gained a parenthetical — `REMOTE MANSION` becoming `REMOTE
    // MANSION (BEDROOM)` — was a different scene, under two thousand seven
    // hundred identical characters of action. Compared word for word instead, a
    // slug that grew still reads as the same room, and `PIER` against `CAR PARK`
    // still reads as a different one.
    let body = overlap(&mine.words, &theirs.words);
    let place = if mine.location.trim().is_empty() && theirs.location.trim().is_empty() {
        1.0
    } else {
        overlap(&body_words(&mine.location), &body_words(&theirs.location))
    };
    let inside = if crate::insideout::canonical(&mine.int_ext)
        .eq_ignore_ascii_case(&crate::insideout::canonical(&theirs.int_ext))
    {
        1.0
    } else {
        0.0
    };
    let mut score = 0.6 * body + 0.3 * place + 0.1 * inside;
    // A scene still wearing its old number gets the benefit of the doubt over an
    // equally good match elsewhere, so an unchanged draft moves nothing.
    if same_number {
        score = (score + 0.05).min(1.0);
    }
    // High on purpose. The same words at a different address score 0.7 and are
    // refused, which is what `it_will_not_guess_when_the_scene_is_not_plainly_
    // the_same` has demanded since Ref 241; the same address with different
    // words scores 0.4 and is refused too.
    if score >= bar {
        Some(score)
    } else {
        None
    }
}

/// Line the project's scenes up against the draft's, **in order**.
///
/// This replaced a greedy best-pair search, and the reason is the whole of Ref
/// 488. The old rule could only consider a project scene whose number the draft
/// did *not* bring, on the reasoning that a scene still at its own number has
/// not moved. That is true of a locked script and false of every rewrite: a
/// white draft renumbers from the top, so the draft brings 1–22 and the project
/// holds 1–22, every scene is disqualified, and **not one move is ever found**.
/// The import then stamped draft 20 onto the project's scene 20 — a different
/// scene — leaving his synopses and his shots a slot behind, all the way to the
/// end of the film.
///
/// Order-preserving is the point, not a detail. Scenes do not shuffle; a draft
/// inserts, cuts, merges and renumbers, and every one of those shifts what
/// *follows* rather than re-pointing it. A best-pair search has no notion of
/// that and will happily cross two matches over. So this is the standard
/// alignment: walk both lists, and at each step either pair the two heads, drop
/// the project's (a scene that has gone), or drop the draft's (a scene that is
/// new), whichever leads to the best total.
///
/// Ties resolve match first, then the project's side, so two machines reading
/// one draft always agree.
fn align(here: &[Side], there: &[Side]) -> Vec<(usize, usize)> {
    // **The sure ones first, then the ones they vouch for.**
    //
    // A draft rewrites as it renumbers, so the tail of a film is often both:
    // the scene is the same scene, and half its action is new. Judged on its own
    // it clears no honest bar. Judged *between two scenes that have already been
    // matched*, its position is evidence in its own right — it is where that
    // scene would have to be. So the strong matches are found first and used as
    // anchors, and only the runs between them are read again at a lower bar,
    // where order is corroborating rather than assumed.
    let anchors = align_within(here, there, SURE);
    // **Nothing anchored means nothing is vouching.** With no sure pair anywhere
    // in the draft, a run of scenes is not "between" anything and its order says
    // nothing, so the lower bar would be a guess wearing a method's clothes.
    if anchors.is_empty() {
        return anchors;
    }
    let mut out: Vec<(usize, usize)> = Vec::new();
    let (mut i, mut j) = (0usize, 0usize);
    let end = (here.len(), there.len());
    for &(a, b) in anchors.iter().chain(std::iter::once(&end)) {
        if a > i && b > j {
            for (x, y) in align_within(&here[i..a], &there[j..b], VOUCHED) {
                out.push((i + x, j + y));
            }
        }
        if (a, b) != end {
            out.push((a, b));
        }
        i = a.saturating_add(1);
        j = b.saturating_add(1);
    }
    out.sort_unstable();
    out
}

/// How alike two scenes must be to be called the same one with nothing else
/// going for them — and how alike, once the scenes on either side of them have
/// already been matched.
const SURE: f64 = 0.85;
const VOUCHED: f64 = 0.6;

fn align_within(here: &[Side], there: &[Side], bar: f64) -> Vec<(usize, usize)> {
    let (n, m) = (here.len(), there.len());
    if n == 0 || m == 0 {
        return Vec::new();
    }
    // How good the best alignment of the first `i` and first `j` is, and which
    // step it took to get there.
    #[derive(Clone, Copy, PartialEq)]
    enum Step {
        Pair,
        SkipHere,
        SkipThere,
    }
    let mut best = vec![vec![0f64; m + 1]; n + 1];
    let mut took = vec![vec![Step::SkipHere; m + 1]; n + 1];
    for j in 1..=m {
        took[0][j] = Step::SkipThere;
    }
    for i in 1..=n {
        for j in 1..=m {
            let skip_here = best[i - 1][j];
            let skip_there = best[i][j - 1];
            let paired =
                likeness(&here[i - 1], &there[j - 1], bar).map(|score| best[i - 1][j - 1] + score);

            let mut winner = (skip_here, Step::SkipHere);
            if skip_there > winner.0 {
                winner = (skip_there, Step::SkipThere);
            }
            if let Some(score) = paired {
                // `>=` so a pairing wins a tie: leaving two scenes that match
                // unmatched is never the more useful reading.
                if score >= winner.0 {
                    winner = (score, Step::Pair);
                }
            }
            best[i][j] = winner.0;
            took[i][j] = winner.1;
        }
    }

    let mut pairs = Vec::new();
    let (mut i, mut j) = (n, m);
    while i > 0 && j > 0 {
        match took[i][j] {
            Step::Pair => {
                pairs.push((i - 1, j - 1));
                i -= 1;
                j -= 1;
            }
            Step::SkipHere => i -= 1,
            Step::SkipThere => j -= 1,
        }
    }
    pairs.reverse();
    pairs
}

/// How much two scene bodies share, 0 to 1, judged on their words.
///
/// Public to the crate so the script diff and the move finder answer the same
/// question the same way. Two figures for "is this the same scene" that could
/// drift apart is how a report and the import it describes stop agreeing.
pub(crate) fn body_overlap(mine: &str, theirs: &str) -> f64 {
    overlap(&body_words(mine), &body_words(theirs))
}

fn body_words(body: &str) -> Vec<String> {
    let mut words: Vec<String> = body
        .split(|c: char| !c.is_alphanumeric())
        .filter(|w| !w.is_empty())
        .map(|w| w.to_lowercase())
        .collect();
    words.sort();
    words.dedup();
    words
}

/// How much two word lists share, 0 to 1 — the size of the overlap over the
/// size of everything either one has.
///
/// Both lists arrive sorted and de-duplicated, so this is a merge rather than a
/// search: a draft with three hundred scenes would otherwise be comparing
/// against every scene in the film, word by word.
fn overlap(mine: &[String], theirs: &[String]) -> f64 {
    if mine.is_empty() || theirs.is_empty() {
        return 0.0;
    }
    let (mut a, mut b, mut shared) = (0, 0, 0usize);
    while a < mine.len() && b < theirs.len() {
        match mine[a].cmp(&theirs[b]) {
            std::cmp::Ordering::Equal => {
                shared += 1;
                a += 1;
                b += 1;
            }
            std::cmp::Ordering::Less => a += 1,
            std::cmp::Ordering::Greater => b += 1,
        }
    }
    let total = mine.len() + theirs.len() - shared;
    if total == 0 {
        0.0
    } else {
        shared as f64 / total as f64
    }
}

fn numbering(scene: &crate::screenplay::Scene) -> String {
    match (&scene.script.number, &scene.status) {
        (Some(number), _) => number.clone(),
        (None, Status::SubSlug { .. }) => scene.label.clone(),
        (None, Status::Scene) => scene.label.clone(),
    }
}
