//! **The film's own icon and colour, kept with the film.**
//!
//! His call, 2026-09-11, after his other Mac drew every film with no icon and
//! the program's plain blue: *"that information should be stored on a server
//! level - not local level… and then distributed out from there"*, and then
//! *"why can't it be part of the project file data that syncs?"*
//!
//! It used to be read, on the Mac only, out of a cache file that a **different
//! app** — his Projects Console — writes into his home folder. A Mac that had
//! never run that app had no file, so every film fell back to no icon and the
//! default blue with no error and nothing to act on. The fix he chose is not a
//! second place to fetch from: the pair belongs to the *film*.
//!
//! ## What is stored, and why it is the outline rather than the picture
//!
//! Two strings on the project record — the icon as SVG **path data** in a
//! twenty-by-twenty box, and the colour as `#RRGGBB`. Not a picture: a picture
//! cannot be re-coloured, cannot stay sharp at thirteen points in a top bar and
//! at forty in a list, and AppKit cannot open an SVG at all. It is also exactly
//! the pair the website already keeps for the same films (`hub/refresh.py`), so
//! the browser and the app cannot come to disagree.
//!
//! ## And a third string, which is the whole of the rule
//!
//! `mark_source` says **who is allowed to write the other two**:
//!
//! - `console` — mirrored off his Notion row by the Mac, and rewritten whenever
//!   that row changes, so a film linked to the larger system stays current.
//! - `hand` — he set it here, for a film that is not in that system. **Nothing
//!   automatic ever overwrites it again.** Without this the mirror would find a
//!   film of the same name in the console cache and quietly undo his choice.
//! - empty — nobody has said, and the mirror is free to fill it in.
//!
//! ## What the engine does not do
//!
//! It never draws, never parses the path, never asks anything of the network,
//! and never goes looking for a console. It stores three strings, refuses a
//! colour that is not a colour, and hands them back. The shells draw.

use crate::doc::f;
use crate::id::Id;
use crate::value::Value;
use crate::Doc;

/// **The two facts about a film's mark**, and the only two anybody needs: the
/// outline to draw, and the colour to draw it in.
#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct Mark {
    /// SVG path data, in the icon's own twenty-by-twenty space.
    pub path: String,
    /// `#RRGGBB`, uppercase.
    pub colour: String,
}

/// Who wrote the mark, which decides who may write it next.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Source {
    /// Mirrored off his Notion row. Refreshed automatically.
    Console,
    /// He chose it. Left alone by everything automatic.
    Hand,
    /// Nobody has said.
    Unsaid,
}

impl Source {
    /// The word on the wire and in the file. Stable — it is stored.
    pub fn key(self) -> &'static str {
        match self {
            Source::Console => "console",
            Source::Hand => "hand",
            Source::Unsaid => "",
        }
    }

    pub fn read(word: &str) -> Source {
        match word.trim() {
            "console" => Source::Console,
            "hand" => Source::Hand,
            _ => Source::Unsaid,
        }
    }

    /// **Whether the mirror may write over what is there.** Only his own hand
    /// stops it.
    pub fn mirrorable(self) -> bool {
        self != Source::Hand
    }
}

/// A colour, or nothing. **`#RRGGBB` and no other spelling**, uppercased on the
/// way in so two devices writing the same colour write the same eight bytes and
/// a merge has nothing to resolve.
///
/// Three characters (`#f00`), eight (an alpha), a bare `f00000` and a colour
/// name are all refused rather than guessed at: this string is handed straight
/// to a drawing routine on three platforms, and the one thing worse than no
/// icon is an icon in a colour nobody chose.
pub fn colour(said: &str) -> Option<String> {
    let said = said.trim();
    if said.len() != 7 || !said.starts_with('#') {
        return None;
    }
    if !said[1..].chars().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    Some(said.to_uppercase())
}

/// The outline, tidied, or nothing. Path data is somebody else's format and
/// this does not pretend to understand it — it only refuses what is plainly not
/// a drawing, and caps the length so a pasted file cannot become a field.
pub fn outline(said: &str) -> Option<String> {
    let said = said.trim();
    if said.is_empty() || said.chars().count() > 20_000 {
        return None;
    }
    // Every path begins with a move. Anything else is not path data, whatever
    // else it might be.
    let first = said.chars().next()?;
    if first != 'M' && first != 'm' {
        return None;
    }
    Some(said.to_string())
}

impl Doc {
    /// **The film's mark**, or nothing when it has none.
    ///
    /// Nothing for a film with only half a pair, too — an outline with no
    /// colour cannot be drawn and a colour with no outline is not an icon. A
    /// caller gets a whole answer or no answer.
    pub fn mark(&self) -> Option<Mark> {
        // The card's, laid over the film (`crate::card`), unless his hand
        // chose this film's own.
        if let Some(card) = self.card_mark() {
            return Some(card.clone());
        }
        self.stored_mark()
    }

    /// The mark the film itself holds, card or no card.
    pub fn stored_mark(&self) -> Option<Mark> {
        let project = self.project_id()?;
        self.mark_of(project)
    }

    pub fn mark_of(&self, project: Id) -> Option<Mark> {
        let record = self.get(project)?;
        let path = record.get(f::MARK_PATH).and_then(|v| v.as_text())?.trim().to_string();
        let colour = record.get(f::MARK_COLOUR).and_then(|v| v.as_text())?.trim().to_string();
        if path.is_empty() || colour.is_empty() {
            return None;
        }
        Some(Mark { path, colour })
    }

    /// Where the mark came from.
    pub fn mark_source(&self) -> Source {
        let Some(project) = self.project_id() else {
            return Source::Unsaid;
        };
        Source::read(
            self.get(project)
                .and_then(|r| r.get(f::MARK_SOURCE))
                .and_then(|v| v.as_text())
                .unwrap_or(""),
        )
    }

    /// **Set the film's mark, or clear it.** The single writer of all three
    /// fields — nothing else in the engine writes them, and the shells reach it
    /// through one command, so there is one place a bad colour can be refused.
    ///
    /// `None` clears the pair and the source with it: a film with no mark is
    /// back to being a film nobody has said anything about, which is the state
    /// the mirror is allowed to fill.
    ///
    /// **The mirror does not make an undoable step.** Writing down what his
    /// Notion row already says is not an action he took, and an undo offered
    /// the moment a film opens — undoing something invisible — reads as a fault.
    /// What he sets by hand undoes like every other edit.
    ///
    /// Returns whether anything was written. `false` means the film already
    /// said exactly this, which is what stops a mirror that runs on every edit
    /// from filing a change on every edit.
    pub fn set_mark(&mut self, mark: Option<&Mark>, source: Source) -> bool {
        let Some(project) = self.project_id() else {
            return false;
        };
        let (path, colour) = match mark {
            Some(m) => match (outline(&m.path), colour(&m.colour)) {
                (Some(path), Some(colour)) => (path, colour),
                // Half a mark is no mark. Refused rather than half-written.
                _ => return false,
            },
            None => (String::new(), String::new()),
        };
        let source = source.key().to_string();

        let held = self.mark_of(project).unwrap_or_default();
        let held_source = self.mark_source().key().to_string();
        if held.path == path && held.colour == colour && held_source == source {
            return false;
        }

        if source == "hand" {
            self.transact("Set icon", |d| {
                d.set(project, f::MARK_PATH, path.as_str());
                d.set(project, f::MARK_COLOUR, colour.as_str());
                d.set(project, f::MARK_SOURCE, source.as_str());
            });
        } else {
            for (field, value) in [
                (f::MARK_PATH, path),
                (f::MARK_COLOUR, colour),
                (f::MARK_SOURCE, source),
            ] {
                self.write_without_recording(project, field, Value::Text(value));
            }
        }
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::stamp::DeviceId;

    fn film() -> Doc {
        let mut d = Doc::new(DeviceId(1));
        d.create_project("Call Her Back");
        d.clear_history();
        d
    }

    fn red() -> Mark {
        Mark {
            path: "M10 2 L18 18 L2 18 Z".to_string(),
            colour: "#d44c47".to_string(),
        }
    }

    #[test]
    fn a_film_starts_with_no_mark() {
        let d = film();
        assert_eq!(d.mark(), None);
        assert_eq!(d.mark_source(), Source::Unsaid);
    }

    #[test]
    fn a_mark_is_kept_and_handed_back_uppercase() {
        let mut d = film();
        assert!(d.set_mark(Some(&red()), Source::Console));
        let held = d.mark().expect("the film wears its mark");
        assert_eq!(held.colour, "#D44C47");
        assert_eq!(held.path, "M10 2 L18 18 L2 18 Z");
        assert_eq!(d.mark_source(), Source::Console);
    }

    #[test]
    fn saying_the_same_thing_twice_writes_nothing() {
        let mut d = film();
        assert!(d.set_mark(Some(&red()), Source::Console));
        let written = d.changes().len();
        assert!(!d.set_mark(Some(&red()), Source::Console));
        assert_eq!(d.changes().len(), written);
    }

    #[test]
    fn a_colour_that_is_not_a_colour_is_refused() {
        let mut d = film();
        for bad in ["#f00", "d44c47", "#d44c4", "rebeccapurple", ""] {
            let mark = Mark { path: red().path, colour: bad.to_string() };
            assert!(!d.set_mark(Some(&mark), Source::Hand), "{bad} should be refused");
        }
        assert_eq!(d.mark(), None);
    }

    #[test]
    fn something_that_is_not_a_drawing_is_refused() {
        let mut d = film();
        let mark = Mark {
            path: "<svg viewBox=\"0 0 20 20\">".to_string(),
            colour: "#D44C47".to_string(),
        };
        assert!(!d.set_mark(Some(&mark), Source::Hand));
        assert_eq!(d.mark(), None);
    }

    #[test]
    fn half_a_mark_is_no_mark() {
        let mut d = film();
        let project = d.project_id().expect("a film has a project record");
        d.set(project, f::MARK_PATH, "M10 2 L18 18 L2 18 Z");
        assert_eq!(d.mark(), None, "an outline with no colour cannot be drawn");
    }

    #[test]
    fn clearing_puts_the_film_back_to_having_said_nothing() {
        let mut d = film();
        d.set_mark(Some(&red()), Source::Hand);
        assert!(d.set_mark(None, Source::Unsaid));
        assert_eq!(d.mark(), None);
        assert_eq!(d.mark_source(), Source::Unsaid);
    }

    #[test]
    fn his_own_choice_is_not_the_mirrors_to_overwrite() {
        assert!(!Source::Hand.mirrorable());
        assert!(Source::Console.mirrorable());
        assert!(Source::Unsaid.mirrorable(), "nobody has said, so the mirror may");
    }

    /// The mirror runs whenever a film is opened. An undo step offered for
    /// something that happened before he touched anything is a fault.
    #[test]
    fn the_mirror_leaves_nothing_to_undo_and_his_own_hand_does() {
        let mut d = film();
        d.set_mark(Some(&red()), Source::Console);
        assert_eq!(d.undo_label(), None);

        let blue = Mark { path: red().path, colour: "#0A6CE8".to_string() };
        d.set_mark(Some(&blue), Source::Hand);
        assert_eq!(d.undo_label(), Some("Set icon"));
        d.undo();
        assert_eq!(d.mark().map(|m| m.colour), Some("#D44C47".to_string()));
    }
}
