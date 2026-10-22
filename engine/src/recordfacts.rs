//! **The film's facts, read from his project record.**
//!
//! The one-record plan, step 4 (2026-10-05): what defines a project — its
//! name, director, producer, client and agency — has one home, the project
//! record the Projects Console keeps on the portal's server. A film used to
//! carry its own copy of each, typed in Project Settings, and the copies went
//! stale: Let's Bake's film said *Owen Fairweather* and *Ollie Hart-Brodman*
//! long after the project's producer was Marta Delgado and the director's
//! name had been put right.
//!
//! So the film now **mirrors** them, the way it already mirrors its icon and
//! colour (`crate::mark`): the console hands the record's words to Shotlister
//! through its own command-line door, this module writes them onto the
//! project record, and `facts_source` says `console`. From then on every
//! shell shows them and none lets anyone type over them — the place to change
//! one is the console.
//!
//! ## What it touches, and what it never does
//!
//! Five fields on the project record and the source beside them. Nothing
//! else: never a scene, a shot, a day, a board, a location. A test holds it
//! to that.
//!
//! The film's own `title` is left exactly as it is. The package, the
//! console's film list, the name the sync knows the film by — all of those
//! read it, and a record that renames a film should not quietly move one of
//! them. The record's name is kept beside it (`record_title`) and shown
//! wherever the film's name is drawn (`Doc::shown_title`).
//!
//! **The mirror makes no undo step**, like the mark's: writing down what the
//! record already says is not something he did here, and an undo offered for
//! it would undo something invisible.

use crate::doc::f;
use crate::value::Value;
use crate::Doc;

/// The facts the record gives a film: the word the console sends, and the
/// field on the project record it lands in. In the order Project Settings
/// shows them.
pub const FACTS: [(&str, &str); 5] = [
    ("title", f::RECORD_TITLE),
    ("director", f::DIRECTOR),
    ("producer", f::PRODUCER),
    ("client", f::CLIENT),
    ("agency", f::AGENCY),
];

/// The source word that means *these come from the record*.
pub const FROM_CONSOLE: &str = "console";

/// The longest a fact may be. A name, not a paragraph — a pasted file
/// arriving here would be a mistake, not a producer.
const LONGEST: usize = 300;

/// **Between the names of one credit**, when the record sends them as a list
/// (2026-10-05, more than one person per credit): the Unit Separator, a
/// character no name contains. The shell's door turns a JSON list into names
/// joined by it; this module makes the credit's one line. A plain line
/// ("Ivy Sterling & Robin Vale Arden") still arrives as it always has.
pub const NAMES: char = '\u{1f}';

/// **Names as a credit reads them** — "A", "A & B", "A, B & C" — the
/// console's `credits.line`, the same rule. Blank names are skipped.
pub fn credit_line<S: AsRef<str>>(names: &[S]) -> String {
    let names: Vec<String> = names
        .iter()
        .map(|n| n.as_ref().split_whitespace().collect::<Vec<_>>().join(" "))
        .filter(|n| !n.is_empty())
        .collect();
    match names.len() {
        0 => String::new(),
        1 | 2 => names.join(" & "),
        n => format!("{} & {}", names[..n - 1].join(", "), names[n - 1]),
    }
}

/// The project-record field a sent word names, or nothing for a word that is
/// not one of the five.
pub fn field_for(word: &str) -> Option<&'static str> {
    FACTS.iter().find(|(w, _)| *w == word).map(|(_, field)| *field)
}

/// Whether a project-record field is one the record owns once a film takes
/// its facts from it. `title` is not: see the module's note.
pub fn owned(field: &str) -> bool {
    FACTS.iter().any(|(_, f)| *f == field)
}

/// A fact as the record said it, made safe to keep: trimmed, any control
/// character (a tab, a line break) turned into a space, and capped.
fn tidy(said: &str) -> Result<String, String> {
    let joined;
    let said = if said.contains(NAMES) {
        joined = credit_line(&said.split(NAMES).collect::<Vec<_>>());
        joined.as_str()
    } else {
        said
    };
    let clean: String = said
        .chars()
        .map(|c| if c.is_control() { ' ' } else { c })
        .collect::<String>()
        .trim()
        .to_string();
    if clean.chars().count() > LONGEST {
        return Err(format!("a fact is a name, not {} characters", clean.chars().count()));
    }
    Ok(clean)
}

impl Doc {
    /// **Whether this film takes its facts from the project record.**
    pub fn facts_from_record(&self) -> bool {
        let Some(project) = self.project_id() else {
            return false;
        };
        self.get(project).and_then(|r| r.text(f::FACTS_SOURCE)).map(str::trim)
            == Some(FROM_CONSOLE)
    }

    /// **The film's name as it is shown** — the record's, when the record has
    /// said one, and the film's own title otherwise.
    pub fn shown_title(&self) -> String {
        let Some(project) = self.project_id() else {
            return String::new();
        };
        // The card's, laid over the film, first (`crate::card`).
        if let Some(title) = self.card_title() {
            return title.to_string();
        }
        let record = self.get(project);
        let said = |field: &str| record.and_then(|r| r.text(field)).unwrap_or("").trim().to_string();
        let from_record = said(f::RECORD_TITLE);
        if self.facts_from_record() && !from_record.is_empty() {
            return from_record;
        }
        said(f::TITLE)
    }

    /// **Take the record's facts.** `given` is (word, value) pairs — `title`,
    /// `director`, `producer`, `client`, `agency` — and only the facts given
    /// are written: a fact the record does not hold leaves the film's own
    /// word where it is. An empty value is the record saying *nobody*, and
    /// clears it.
    ///
    /// The whole set is checked before anything is written, so a word that
    /// is not one of the five, or a value that is not a name, refuses the lot.
    ///
    /// Returns the words that changed (`source` among them when the film
    /// first comes to take its facts from the record). Nothing changed is an
    /// empty list, which is what stops a mirror that runs often from filing a
    /// change every time.
    pub fn take_record_facts(&mut self, given: &[(String, String)]) -> Result<Vec<&'static str>, String> {
        let project = self.project_id().ok_or("this film has no project record")?;
        let mut plan: Vec<(&'static str, &'static str, String)> = Vec::new();
        for (word, value) in given {
            let field = field_for(word.trim())
                .ok_or_else(|| format!("{word} is not a fact the record gives a film"))?;
            let word = FACTS.iter().find(|(_, f)| *f == field).map(|(w, _)| *w).unwrap_or("");
            // The last one said wins, the way a form with a field twice would.
            plan.retain(|(_, f, _)| *f != field);
            plan.push((word, field, tidy(value)?));
        }
        let mut changed = Vec::new();
        for (word, field, value) in plan {
            let held = self.get(project).and_then(|r| r.text(field)).unwrap_or("").to_string();
            if held == value {
                continue;
            }
            self.write_without_recording(project, field, Value::Text(value));
            changed.push(word);
        }
        if !self.facts_from_record() {
            self.write_without_recording(project, f::FACTS_SOURCE, Value::Text(FROM_CONSOLE.to_string()));
            changed.push("source");
        }
        Ok(changed)
    }

    /// **Let go of the record** — the film keeps the words it has and owns
    /// them again; its shown name goes back to its own title. For a film
    /// unlinked from its project. Returns whether anything changed.
    pub fn let_go_of_record_facts(&mut self) -> bool {
        let Some(project) = self.project_id() else {
            return false;
        };
        if !self.facts_from_record() {
            return false;
        }
        self.write_without_recording(project, f::FACTS_SOURCE, Value::Text(String::new()));
        self.write_without_recording(project, f::RECORD_TITLE, Value::Text(String::new()));
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::stamp::DeviceId;
    use crate::store::Op;

    fn film() -> Doc {
        let mut d = Doc::new(DeviceId(1));
        let project = d.create_project("Lets Bake");
        d.set(project, f::DIRECTOR, "Ollie Hart-Brodman");
        d.set(project, f::PRODUCER, "Owen Fairweather");
        d.set(project, f::CLIENT, "Acme Express");
        d.set(project, f::AGENCY, "Fabrica");
        let scene = d.create_scene("7");
        d.set(scene, f::TITLE, "Style Server: Plated Portions");
        d.add_shot_to_scene(scene);
        d.clear_history();
        d
    }

    fn pairs(list: &[(&str, &str)]) -> Vec<(String, String)> {
        list.iter().map(|(a, b)| (a.to_string(), b.to_string())).collect()
    }

    fn said(d: &Doc, field: &str) -> String {
        let project = d.project_id().unwrap();
        d.get(project).and_then(|r| r.text(field)).unwrap_or("").to_string()
    }

    fn lets_bake() -> Vec<(String, String)> {
        pairs(&[
            ("title", "Let's Bake"),
            ("director", "Ollie Hart Brennan"),
            ("producer", "Marta Delgado"),
            ("client", "Acme Express"),
            ("agency", "Fabrica"),
        ])
    }

    #[test]
    fn a_film_starts_keeping_its_own_facts() {
        let d = film();
        assert!(!d.facts_from_record());
        assert_eq!(d.shown_title(), "Lets Bake");
    }

    #[test]
    fn the_records_facts_land_and_the_film_says_where_they_came_from() {
        let mut d = film();
        let changed = d.take_record_facts(&lets_bake()).unwrap();
        assert_eq!(changed, vec!["title", "director", "producer", "source"]);
        assert!(d.facts_from_record());
        assert_eq!(d.shown_title(), "Let's Bake");
        assert_eq!(said(&d, f::DIRECTOR), "Ollie Hart Brennan");
        assert_eq!(said(&d, f::PRODUCER), "Marta Delgado");
        assert_eq!(said(&d, f::CLIENT), "Acme Express");
        assert_eq!(said(&d, f::AGENCY), "Fabrica");
    }

    /// The film's own title is what its package, the console's list and the
    /// sync know it by. The record's name is shown; the title is not moved.
    #[test]
    fn the_films_own_title_is_never_moved() {
        let mut d = film();
        d.take_record_facts(&lets_bake()).unwrap();
        assert_eq!(said(&d, f::TITLE), "Lets Bake");
    }

    #[test]
    fn only_the_project_record_is_written_never_a_scene_or_a_shot() {
        let mut d = film();
        let project = d.project_id().unwrap();
        let before = d.changes().len();
        d.take_record_facts(&lets_bake()).unwrap();
        let written = &d.changes()[before..];
        assert!(!written.is_empty());
        for change in written {
            match &change.op {
                Op::Set { id, field, .. } => {
                    assert_eq!(*id, project, "{field} written somewhere other than the project");
                    assert!(owned(field) || field == f::FACTS_SOURCE, "{field} is not a record fact");
                }
                Op::Create { .. } => panic!("the mirror made a record"),
            }
        }
    }

    #[test]
    fn saying_the_same_thing_again_writes_nothing() {
        let mut d = film();
        d.take_record_facts(&lets_bake()).unwrap();
        let written = d.changes().len();
        assert_eq!(d.take_record_facts(&lets_bake()).unwrap(), Vec::<&str>::new());
        assert_eq!(d.changes().len(), written);
    }

    #[test]
    fn a_fact_the_record_does_not_hold_leaves_the_films_word() {
        let mut d = film();
        d.take_record_facts(&pairs(&[("director", "Ollie Hart Brennan")])).unwrap();
        assert_eq!(said(&d, f::PRODUCER), "Owen Fairweather");
        assert_eq!(d.shown_title(), "Lets Bake", "no record name, so the title shows");
    }

    #[test]
    fn an_empty_fact_is_the_record_saying_nobody() {
        let mut d = film();
        d.take_record_facts(&pairs(&[("agency", "")])).unwrap();
        assert_eq!(said(&d, f::AGENCY), "");
    }

    #[test]
    fn a_word_that_is_not_a_fact_refuses_the_lot() {
        let mut d = film();
        let before = d.changes().len();
        let got = d.take_record_facts(&pairs(&[("director", "Someone"), ("scene", "7")]));
        assert!(got.is_err());
        assert_eq!(d.changes().len(), before, "nothing half-written");
        assert!(!d.facts_from_record());
    }

    #[test]
    fn a_fact_is_a_name_not_a_file() {
        let mut d = film();
        let long = "x".repeat(LONGEST + 1);
        assert!(d.take_record_facts(&pairs(&[("director", &long)])).is_err());
        d.take_record_facts(&pairs(&[("producer", "Marta\tDelgado\n")])).unwrap();
        assert_eq!(said(&d, f::PRODUCER), "Marta Delgado");
    }

    #[test]
    fn a_credit_sent_as_names_becomes_its_one_line() {
        let mut d = film();
        let oddity = format!("Ivy Sterling{NAMES}Robin Vale Arden");
        d.take_record_facts(&pairs(&[("director", &oddity)])).unwrap();
        assert_eq!(said(&d, f::DIRECTOR), "Ivy Sterling & Robin Vale Arden");
        let three = format!("Marta Delgado{NAMES} Ned  Paul Kestrel {NAMES}{NAMES}Dan");
        d.take_record_facts(&pairs(&[("producer", &three)])).unwrap();
        assert_eq!(said(&d, f::PRODUCER), "Marta Delgado, Ned Paul Kestrel & Dan");
    }

    #[test]
    fn a_line_already_joined_is_taken_as_it_is() {
        let mut d = film();
        d.take_record_facts(&pairs(&[("director", "Ivy Sterling & Robin Vale Arden")])).unwrap();
        assert_eq!(said(&d, f::DIRECTOR), "Ivy Sterling & Robin Vale Arden");
        assert_eq!(credit_line(&["A", "", "B"]), "A & B");
        assert_eq!(credit_line::<&str>(&[]), "");
    }

    #[test]
    fn the_mirror_leaves_nothing_to_undo() {
        let mut d = film();
        d.take_record_facts(&lets_bake()).unwrap();
        assert_eq!(d.undo_label(), None);
    }

    #[test]
    fn letting_go_keeps_the_words_and_shows_the_title_again() {
        let mut d = film();
        d.take_record_facts(&lets_bake()).unwrap();
        assert!(d.let_go_of_record_facts());
        assert!(!d.facts_from_record());
        assert_eq!(said(&d, f::PRODUCER), "Marta Delgado");
        assert_eq!(d.shown_title(), "Lets Bake");
        assert!(!d.let_go_of_record_facts(), "nothing to let go of twice");
    }

    #[test]
    fn title_itself_is_not_a_field_the_record_owns() {
        assert!(!owned(f::TITLE));
        assert!(owned(f::DIRECTOR) && owned(f::RECORD_TITLE));
        assert_eq!(field_for("title"), Some(f::RECORD_TITLE));
        assert_eq!(field_for("kind"), None);
    }
}
