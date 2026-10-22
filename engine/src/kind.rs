//! **A film's Kind — Film or Commercial — and what a commercial scene is.**
//!
//! His brief, 2026-09-14: *"a separate shotlister project 'mode' that is
//! better formatted for commercials, where you have less standard screenplays
//! and 'scenes'… Oftentimes, commercials won't even have a script. You just
//! have different scenes you want to get, and you just need to write them
//! down somewhere."* Argued out in `design/22-commercial.html`.
//!
//! ## Not a second record
//!
//! A commercial scene is the same `Kind::Scene` record. What fights a
//! commercial is not the record but what the engine *insists on*: that a
//! scene is made from a number, that its heading is a slugline, that an empty
//! slug reads `INT. LOCATION - DAY`. So the film carries one more fact — its
//! **Kind** — and that fact changes three things, here, and nothing else:
//!
//! 1. **What a scene needs to exist.** A film scene needs a number; a
//!    commercial scene needs a *title* and is given the next whole number.
//! 2. **What its heading is.** The title, when it has one. A slugline is a
//!    separate, optional fact underneath — *"sometimes you'll have scene
//!    headers, sometimes you won't"* — and an empty one reads as empty.
//! 3. **What its body is.** *Video* and *Audio* — the two columns of an AV
//!    script. Video reuses the scene's `script` field, which already holds
//!    "what the scene is"; Audio is the one field a commercial adds.
//!
//! ## The numbers law, and how it survives
//!
//! *Scene numbers belong to the script; we never renumber.* The law exists
//! because the crew shares those numbers. A commercial has no script — but
//! the moment its shot list goes out, the list *is* the shared reference and
//! `3B` had better still be `3B` on the day. So the owner changes and the law
//! holds: a commercial scene gets its number once, when it is made, and
//! moving it never changes it. `renumber_in_order` exists as a **person's
//! decision**, offered only to a commercial, and the shell says what it
//! costs before it runs.
//!
//! ## What the engine does not do
//!
//! It never decides what a *label* says. *Section* for a sequence, *Video*
//! for the script field, the fold the slugline hides in — those are the
//! shells' to draw off the Kind. The engine stores the Kind, reads it, and
//! answers the three questions above.

use crate::doc::{f, Doc};
use crate::id::Id;
use crate::order;
use crate::store::Kind as RecordKind;
use crate::value::Value;

/// What sort of film this is.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    /// A screenplay: scenes have numbers the script owns and slugline
    /// headings. Everything built before 2026-09-14 is this.
    Film,
    /// No screenplay: scenes are titled things to get, numbered by us.
    Commercial,
}

impl Kind {
    pub fn as_str(self) -> &'static str {
        match self {
            Kind::Film => "film",
            Kind::Commercial => "commercial",
        }
    }

    /// Anything that is not plainly `commercial` is a film — every project
    /// written before the field existed says nothing, and is a film.
    pub fn read(said: &str) -> Kind {
        match said.trim().to_ascii_lowercase().as_str() {
            "commercial" => Kind::Commercial,
            _ => Kind::Film,
        }
    }
}

/// How many characters of a scene's video line stand in for a missing title.
const STAND_IN_LENGTH: usize = 60;

impl Doc {
    /// The film's Kind. A film with no project record is a film.
    pub fn kind(&self) -> Kind {
        // Kind follows the card's Type when a card is laid on (`crate::card`).
        if let Some(kind) = self.card_kind() {
            return kind;
        }
        self.project_id()
            .and_then(|p| self.get(p))
            .and_then(|r| r.text(f::KIND))
            .map(Kind::read)
            .unwrap_or(Kind::Film)
    }

    /// **Set the film's Kind.** Undoable, and it changes no other record:
    /// switching a film to a commercial and back leaves every scene exactly
    /// as it was. Only what the shells insist on and draw changes.
    pub fn set_kind(&mut self, kind: Kind) {
        let Some(project) = self.project_id() else {
            return;
        };
        let tx = self.begin("Set kind");
        self.set(project, f::KIND, kind.as_str());
        self.end(tx);
    }

    /// A scene's own title — the thing a commercial scene is called.
    pub fn scene_title(&self, scene: Id) -> String {
        self.get(scene)
            .and_then(|r| r.text(f::TITLE))
            .unwrap_or_default()
            .trim()
            .to_string()
    }

    /// **A scene's slugline, or nothing.** The written one when the script
    /// printed one; otherwise built from the parts a person filled in, and
    /// only when at least one part is filled in. Never `INT. LOCATION - DAY`
    /// for a scene nobody has said anything about — that fallback belongs to
    /// `scene_heading` on a film, where a scene *is* a slug.
    pub fn scene_slug(&self, scene: Id) -> Option<String> {
        let record = self.get(scene)?;
        if let Some(written) = record.text(f::HEADING).filter(|t| !t.trim().is_empty()) {
            return Some(written.trim().to_string());
        }
        let int_ext = record.text(f::INT_EXT).map(str::trim).filter(|t| !t.is_empty());
        let location = record.text(f::LOCATION).map(str::trim).filter(|t| !t.is_empty());
        let tod = record.text(f::TIME_OF_DAY).map(str::trim).filter(|t| !t.is_empty());
        if int_ext.is_none() && location.is_none() && tod.is_none() {
            return None;
        }
        let mut slug = String::new();
        if let Some(ie) = int_ext {
            // The stored word carries no full stop — `EXT`, `INT/EXT` — and a
            // typed one may or may not. One printed form either way.
            slug.push_str(&crate::insideout::printed(ie));
        }
        if let Some(loc) = location {
            if !slug.is_empty() {
                slug.push(' ');
            }
            slug.push_str(&loc.to_uppercase());
        }
        if let Some(t) = tod {
            if !slug.is_empty() {
                slug.push_str(" - ");
            }
            slug.push_str(&t.to_uppercase());
        }
        Some(slug)
    }

    /// **A commercial scene's heading.** The title; failing that the
    /// slugline; failing that the first line of its video, cut short, so a
    /// scene pasted in from an AV script with no label still reads as what it
    /// is; failing everything, its number — `Scene 4` — which names the thing
    /// without inventing anything about it.
    pub fn commercial_heading(&self, scene: Id) -> String {
        let title = self.scene_title(scene);
        if !title.is_empty() {
            return title;
        }
        if let Some(slug) = self.scene_slug(scene) {
            return slug;
        }
        let video = self
            .get(scene)
            .and_then(|r| r.text(f::SCRIPT))
            .unwrap_or_default()
            .lines()
            .map(str::trim)
            .find(|l| !l.is_empty())
            .unwrap_or_default()
            .to_string();
        if !video.is_empty() {
            if video.chars().count() <= STAND_IN_LENGTH {
                return video;
            }
            let cut: String = video.chars().take(STAND_IN_LENGTH).collect();
            let at = cut.rfind(' ').unwrap_or(cut.len());
            return format!("{}…", cut[..at].trim_end());
        }
        let number = self
            .get(scene)
            .and_then(|r| r.text(f::NUMBER))
            .unwrap_or_default()
            .to_string();
        if number.is_empty() {
            "Scene".to_string()
        } else {
            format!("Scene {number}")
        }
    }

    /// **The next whole number the film has not used.** One more than the
    /// largest whole number any scene carries — `1` on an empty film. A
    /// scene numbered `12A` counts as twelve; a scene with no number, or a
    /// number that is not a number, counts as nothing.
    pub fn next_scene_number(&self) -> String {
        let largest = self
            .store()
            .of_kind(&RecordKind::Scene)
            .iter()
            .filter_map(|r| r.text(f::NUMBER))
            .filter_map(leading_whole)
            .max()
            .unwrap_or(0);
        (largest + 1).to_string()
    }

    /// **A scene made from a title**, the commercial way: it takes the next
    /// whole number and lands at the end of the list. Nothing already in the
    /// list moves. One transaction, so ⌘Z takes back the whole gesture.
    pub fn create_scene_titled(&mut self, title: &str) -> Id {
        let tx = self.begin("Add scene");
        let number = self.next_scene_number();
        let existing: Vec<f64> = self
            .store()
            .of_kind(&RecordKind::Scene)
            .iter()
            .filter_map(|r| r.float(f::ORDER))
            .collect();
        let id = self.create(RecordKind::Scene);
        self.set(id, f::NUMBER, number);
        self.set(id, f::ORDER, order::after_last(&existing));
        let title = title.trim();
        if !title.is_empty() {
            self.set(id, f::TITLE, title);
        }
        self.end(tx);
        id
    }

    /// **Renumber every scene by its place in the list**, `1` to `n`. A
    /// person's decision, undoable as one step. Returns how many numbers
    /// actually changed — a film already in order changes nothing and makes
    /// no undo step. Shot IDs follow, because `34A` is never stored: it is the
    /// scene's number plus the placement's letter, read fresh every time.
    pub fn renumber_in_order(&mut self) -> usize {
        let scenes = self.scenes_in_order();
        let changes: Vec<(Id, String)> = scenes
            .iter()
            .enumerate()
            .filter_map(|(at, id)| {
                let wanted = (at + 1).to_string();
                let has = self.get(*id).and_then(|r| r.text(f::NUMBER)).unwrap_or_default();
                (has != wanted).then(|| (*id, wanted))
            })
            .collect();
        if changes.is_empty() {
            return 0;
        }
        let tx = self.begin("Renumber scenes");
        for (id, number) in &changes {
            self.set(*id, f::NUMBER, Value::text(number));
        }
        self.end(tx);
        changes.len()
    }
}

/// `12A` → 12, `7` → 7, `A` → nothing.
fn leading_whole(number: &str) -> Option<u64> {
    let digits: String = number.trim().chars().take_while(|c| c.is_ascii_digit()).collect();
    digits.parse().ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::stamp::DeviceId;

    fn film() -> Doc {
        let mut d = Doc::new(DeviceId(1));
        d.create_project("Instant");
        d.clear_history();
        d
    }

    fn commercial() -> Doc {
        let mut d = film();
        d.set_kind(Kind::Commercial);
        d.clear_history();
        d
    }

    #[test]
    fn a_film_that_says_nothing_is_a_film() {
        let d = film();
        assert_eq!(d.kind(), Kind::Film);
        assert_eq!(Kind::read(""), Kind::Film);
        assert_eq!(Kind::read("Commercial "), Kind::Commercial);
        assert_eq!(Kind::read("music video"), Kind::Film);
    }

    #[test]
    fn the_kind_is_set_undone_and_touches_nothing_else() {
        let mut d = film();
        let scene = d.create_scene("34");
        d.set(scene, f::HEADING, "INT. CAR - DAY");
        d.clear_history();
        d.set_kind(Kind::Commercial);
        assert_eq!(d.kind(), Kind::Commercial);
        assert_eq!(d.scene_heading(scene).as_deref(), Some("INT. CAR - DAY"));
        d.undo();
        assert_eq!(d.kind(), Kind::Film);
    }

    #[test]
    fn a_titled_scene_takes_the_next_whole_number_and_lands_last() {
        let mut d = commercial();
        assert_eq!(d.next_scene_number(), "1");
        let a = d.create_scene_titled("Hero Unboxes the Camera");
        let b = d.create_scene_titled("  Party Montage ");
        assert_eq!(d.get(a).unwrap().text(f::NUMBER), Some("1"));
        assert_eq!(d.get(b).unwrap().text(f::NUMBER), Some("2"));
        assert_eq!(d.scene_title(b), "Party Montage");
        assert_eq!(d.scenes_in_order(), vec![a, b]);
        assert_eq!(d.scene_heading(a).as_deref(), Some("Hero Unboxes the Camera"));
    }

    #[test]
    fn the_next_number_skips_past_lettered_and_wordy_numbers() {
        let mut d = commercial();
        d.create_scene("12A");
        d.create_scene("A");
        d.create_scene("");
        assert_eq!(d.next_scene_number(), "13");
    }

    #[test]
    fn an_empty_slug_reads_as_empty_on_a_commercial() {
        let mut d = commercial();
        let scene = d.create_scene_titled("Macro on the Turntable");
        assert_eq!(d.scene_slug(scene), None);
        d.set_scene_field(scene, f::TIME_OF_DAY, "Night");
        assert_eq!(d.scene_slug(scene).as_deref(), Some("NIGHT"));
        d.set_scene_field(scene, f::INT_EXT, "EXT");
        d.set_scene_field(scene, f::LOCATION, "Motel");
        assert_eq!(d.scene_slug(scene).as_deref(), Some("EXT. MOTEL - NIGHT"));
        // the panel's choice carries its own full stop; never two
        d.set_scene_field(scene, f::INT_EXT, "INT./EXT.");
        assert_eq!(d.scene_slug(scene).as_deref(), Some("INT./EXT. MOTEL - NIGHT"));
        // the title still leads the heading; the slug is the fact underneath
        assert_eq!(d.scene_heading(scene).as_deref(), Some("Macro on the Turntable"));
    }

    #[test]
    fn a_film_still_reads_the_old_fallback() {
        let mut d = film();
        let scene = d.create_scene("3");
        assert_eq!(d.scene_heading(scene).as_deref(), Some("INT. LOCATION - DAY"));
        assert_eq!(d.scene_slug(scene), None);
    }

    #[test]
    fn a_scene_with_no_title_stands_in_with_its_video_then_its_number() {
        let mut d = commercial();
        let scene = d.create_scene_titled("");
        assert_eq!(d.scene_heading(scene).as_deref(), Some("Scene 1"));
        d.set(scene, f::SCRIPT, "The camera on black, turning. Light rakes the shutter button.");
        assert_eq!(
            d.scene_heading(scene).as_deref(),
            Some("The camera on black, turning. Light rakes the shutter…")
        );
        d.set(scene, f::SCRIPT, "End card.");
        assert_eq!(d.scene_heading(scene).as_deref(), Some("End card."));
        d.set_scene_field(scene, f::LOCATION, "Stage B");
        assert_eq!(d.scene_heading(scene).as_deref(), Some("STAGE B"));
    }

    #[test]
    fn renumbering_follows_the_list_and_undoes_as_one_step() {
        let mut d = commercial();
        let a = d.create_scene_titled("A");
        let b = d.create_scene_titled("B");
        let c = d.create_scene_titled("C");
        d.set(a, f::NUMBER, "7");
        d.set(c, f::NUMBER, "2");
        d.clear_history();
        assert_eq!(d.renumber_in_order(), 2);
        let numbers = |d: &Doc| -> Vec<String> {
            [a, b, c]
                .iter()
                .map(|id| d.get(*id).unwrap().text(f::NUMBER).unwrap_or_default().to_string())
                .collect()
        };
        assert_eq!(numbers(&d), vec!["1", "2", "3"]);
        assert_eq!(d.renumber_in_order(), 0);
        d.undo();
        assert_eq!(numbers(&d), vec!["7", "2", "2"]);
    }

    #[test]
    fn shot_ids_follow_a_renumber() {
        let mut d = commercial();
        let a = d.create_scene_titled("A");
        let b = d.create_scene_titled("B");
        d.set(b, f::NUMBER, "9");
        let (_, placement) = d.add_shot_to_scene_after(b, None);
        assert_eq!(d.display_number(placement).as_deref(), Some("9A"));
        d.renumber_in_order();
        assert_eq!(d.display_number(placement).as_deref(), Some("2A"));
        let _ = a;
    }
}
