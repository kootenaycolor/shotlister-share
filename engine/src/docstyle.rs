//! **How the document page is set** — the nine kinds of words on it, and the
//! size, face and case each one is drawn in.
//!
//! His ask, 2026-09-02: *"any sort of resizing of the document view needs to
//! happen in its UI in the main app, not in the exporter"*, and *"header, sub
//! header, body (and any text classes) default sizes, font, case"*.
//!
//! ## Why this is in the engine and not in the app
//!
//! Every one of these numbers existed **twice** — as Swift constants in
//! `Document.swift`'s `Page`, and again as Rust constants in
//! `export/html.rs`'s `mod doc` — with a comment on each saying "if one moves,
//! the other moves" and nothing whatever enforcing it. The moment they became
//! adjustable that arrangement was finished: two owners of a number a person
//! can change is two answers to the same question.
//!
//! So the engine owns them, the app asks, and the printed page asks the same.
//! **The old constants are still here** — they are the defaults, and a project
//! that has never been touched draws exactly what it drew before.
//!
//! ## The wire
//!
//! One string on the project record, `doc_style`, holding only what he has
//! actually changed:
//!
//! ```text
//! body=11/serif/as/17171a;shot_title=12/sans/upper/17171a
//! ```
//!
//! Encoded and decoded here and nowhere else. The app never writes this
//! string: it says `docstyle <class> <size> <face> <case> <colour>` and the engine
//! folds that into whatever is already there, which is what keeps the format
//! a private matter between this file and itself.

use crate::doc::f;
use crate::Doc;
use crate::id::Id;

/// The nine kinds of words on the page.
///
/// Taken from what it actually draws rather than invented: every one of these
/// is a place `Document.swift` reaches for a size today.
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum Class {
    /// The film's name at the head of the sheet.
    SheetTitle,
    /// The small capitals under it, and beside a scene: the credits, SHOT
    /// LIST, 5 SHOTS.
    Credits,
    SceneHeading,
    SceneNumber,
    /// The short name over a shot's sentence.
    ShotTitle,
    /// The words of a shot. The one size that decides how much fits.
    Body,
    /// Size · angle · movement · lens · equipment, under the words.
    Technical,
    Notes,
    /// The number in the margin.
    ShotNumber,
}

impl Class {
    pub const ALL: [Class; 9] = [
        Class::SheetTitle, Class::Credits, Class::SceneHeading, Class::SceneNumber,
        Class::ShotTitle, Class::Body, Class::Technical, Class::Notes, Class::ShotNumber,
    ];

    /// The name on the wire and in the app. Stable — it is stored.
    pub fn key(self) -> &'static str {
        match self {
            Class::SheetTitle => "sheet_title",
            Class::Credits => "credits",
            Class::SceneHeading => "scene_heading",
            Class::SceneNumber => "scene_number",
            Class::ShotTitle => "shot_title",
            Class::Body => "body",
            Class::Technical => "technical",
            Class::Notes => "notes",
            Class::ShotNumber => "shot_number",
        }
    }

    /// What he sees. **A label names the thing** — the app's own law.
    pub fn label(self) -> &'static str {
        match self {
            Class::SheetTitle => "Title",
            Class::Credits => "Credits",
            Class::SceneHeading => "Scene heading",
            Class::SceneNumber => "Scene number",
            Class::ShotTitle => "Shot title",
            Class::Body => "Body",
            Class::Technical => "Technical line",
            Class::Notes => "Notes",
            Class::ShotNumber => "Shot number",
        }
    }

    pub fn read(name: &str) -> Option<Class> {
        Class::ALL.into_iter().find(|c| c.key() == name)
    }

    /// **Whether a case may be forced on this class.**
    ///
    /// Not on the three he types into — the shot's title, its sentence and its
    /// note. A page that draws WHAT HE TYPED while the file holds what he
    /// typed is a page disagreeing with itself, and the moment he edits the
    /// line he is looking at letters he did not write. The five that are
    /// drawn *for* him — the credits, the scene's heading and number, the
    /// technical line, the shot number — take one happily, and always did:
    /// the credits have been upper-cased since the page was first drawn.
    pub fn takes_case(self) -> bool {
        !matches!(self, Class::ShotTitle | Class::Body | Class::Notes)
    }
}

/// **A short list, deliberately.** His choice, 2026-09-03.
///
/// Every font on the Mac was the other option and it loses quietly: a face
/// this machine has and another does not draws a different page on the other
/// one, with nothing to say why. These three are the ones the app already
/// draws with, and every platform it runs on has all of them.
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum Face {
    Serif,
    Sans,
    Mono,
}

impl Face {
    pub fn key(self) -> &'static str {
        match self {
            Face::Serif => "serif",
            Face::Sans => "sans",
            Face::Mono => "mono",
        }
    }

    pub fn read(name: &str) -> Option<Face> {
        match name {
            "serif" => Some(Face::Serif),
            "sans" => Some(Face::Sans),
            "mono" => Some(Face::Mono),
            _ => None,
        }
    }

    /// The stylesheet variable this face is written as.
    pub fn css(self) -> &'static str {
        match self {
            Face::Serif => "var(--serif)",
            Face::Sans => "var(--sans)",
            Face::Mono => "var(--mono)",
        }
    }
}

#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum Case {
    /// However it is typed. The only one that can lose nothing.
    AsTyped,
    Upper,
    Lower,
}

impl Case {
    pub fn key(self) -> &'static str {
        match self {
            Case::AsTyped => "as",
            Case::Upper => "upper",
            Case::Lower => "lower",
        }
    }

    pub fn read(name: &str) -> Option<Case> {
        match name {
            "as" => Some(Case::AsTyped),
            "upper" => Some(Case::Upper),
            "lower" => Some(Case::Lower),
            _ => None,
        }
    }

    pub fn css(self) -> &'static str {
        match self {
            Case::AsTyped => "none",
            Case::Upper => "uppercase",
            Case::Lower => "lowercase",
        }
    }
}

/// **The ink a kind of words is drawn in.**
///
/// His ask, 2026-09-03: *"we should include font color as an option across the
/// board"*. It sits beside the size, the face and the case because it is the
/// same kind of fact — a decision about how one kind of words is set, made
/// once for the whole page rather than word by word.
///
/// Stored as six hex digits and nothing else. No names, no palette on disk: a
/// name is a promise that the list it came from will not change, and the app
/// offering ten swatches today may offer twelve tomorrow.
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub struct Colour {
    pub r: u8,
    pub g: u8,
    pub b: u8,
}

impl Colour {
    pub const fn new(r: u8, g: u8, b: u8) -> Colour {
        Colour { r, g, b }
    }

    /// `17171a`, `#17171A`, either. Anything else is nobody's colour.
    pub fn read(said: &str) -> Option<Colour> {
        let hex = said.trim().trim_start_matches('#');
        if hex.len() != 6 || !hex.chars().all(|c| c.is_ascii_hexdigit()) {
            return None;
        }
        let byte = |at: usize| u8::from_str_radix(&hex[at..at + 2], 16).ok();
        Some(Colour::new(byte(0)?, byte(2)?, byte(4)?))
    }

    /// Six lower-case digits, which is what goes on the wire.
    pub fn hex(self) -> String {
        format!("{:02x}{:02x}{:02x}", self.r, self.g, self.b)
    }

    /// What the stylesheet writes.
    pub fn css(self) -> String {
        format!("#{}", self.hex())
    }
}

/// **The page's own black**, neutral rather than the app's green. The export
/// drew `#16201b` and the app drew `#17171A`, which is two answers to one
/// question and exactly the kind of drift this module exists to end.
pub const INK: Colour = Colour::new(0x17, 0x17, 0x1a);
/// The grey the quieter lines have always been: the credits, the technical
/// line, a note.
pub const MUTED: Colour = Colour::new(0x5c, 0x5c, 0x63);

#[derive(Copy, Clone, PartialEq, Debug)]
pub struct Setting {
    pub size: f64,
    pub face: Face,
    pub case: Case,
    pub colour: Colour,
}

/// **What the page has always looked like.** Every number here is the one the
/// old constant held, and every face and case is what the old stylesheet and
/// the old view drew — so a project nobody has touched is unchanged.
pub fn standard(class: Class) -> Setting {
    use Case::*;
    use Face::*;
    let one = |size, face, case, colour| Setting { size, face, case, colour };
    match class {
        Class::SheetTitle => one(13.0, Sans, AsTyped, INK),
        Class::Credits => one(8.0, Mono, Upper, MUTED),
        Class::SceneHeading => one(11.0, Sans, AsTyped, INK),
        Class::SceneNumber => one(10.5, Mono, AsTyped, INK),
        Class::ShotTitle => one(11.5, Serif, AsTyped, INK),
        Class::Body => one(10.5, Serif, AsTyped, INK),
        Class::Technical => one(8.5, Mono, AsTyped, MUTED),
        Class::Notes => one(11.5, Serif, AsTyped, MUTED),
        Class::ShotNumber => one(9.0, Mono, AsTyped, INK),
    }
}

/// The whole page's type: one setting per class, defaults already applied.
#[derive(Clone, Debug)]
pub struct Style {
    settings: Vec<(Class, Setting)>,
}

impl Style {
    pub fn get(&self, class: Class) -> Setting {
        self.settings
            .iter()
            .find(|(c, _)| *c == class)
            .map(|(_, s)| *s)
            .unwrap_or_else(|| standard(class))
    }

    /// Everything, in the order the page reads.
    pub fn all(&self) -> Vec<(Class, Setting)> {
        Class::ALL.into_iter().map(|c| (c, self.get(c))).collect()
    }

    /// **Only what differs from standard.** A project he has never set foot in
    /// stores nothing at all, so "never touched" and "touched back to the
    /// default" are the same thing on disk, and a later change to the standard
    /// reaches both.
    pub fn encode(&self) -> String {
        Class::ALL
            .into_iter()
            .filter_map(|class| {
                let one = self.get(class);
                if one == standard(class) {
                    return None;
                }
                Some(format!(
                    "{}={}/{}/{}/{}",
                    class.key(),
                    trim(one.size),
                    one.face.key(),
                    one.case.key(),
                    one.colour.hex()
                ))
            })
            .collect::<Vec<_>>()
            .join(";")
    }

    /// **Anything unreadable is skipped, never fatal.** An older engine meeting
    /// a newer app's class should draw the page it can rather than refuse the
    /// whole document over one word it does not know — the same bargain the
    /// export options already strike.
    pub fn decode(text: &str) -> Style {
        let mut settings = Vec::new();
        for part in text.split(';') {
            let part = part.trim();
            if part.is_empty() {
                continue;
            }
            let Some((name, rest)) = part.split_once('=') else { continue };
            let Some(class) = Class::read(name.trim()) else { continue };
            let bits: Vec<&str> = rest.split('/').collect();
            // **Three parts or four.** Four is size/face/case/colour; three is
            // a page written before a colour could be chosen, and it keeps the
            // ink the class has always had rather than being thrown away.
            if bits.len() != 3 && bits.len() != 4 {
                continue;
            }
            let Ok(size) = bits[0].trim().parse::<f64>() else { continue };
            let Some(face) = Face::read(bits[1].trim()) else { continue };
            let Some(mut case) = Case::read(bits[2].trim()) else { continue };
            let colour = match bits.get(3) {
                Some(said) => match Colour::read(said) {
                    Some(c) => c,
                    None => continue,
                },
                None => standard(class).colour,
            };
            // A case stored against a class that cannot take one is dropped
            // rather than honoured — an older app, or a newer one, must not be
            // able to make the page shout words he typed himself.
            if !class.takes_case() {
                case = Case::AsTyped;
            }
            if !(4.0..=48.0).contains(&size) {
                continue;
            }
            settings.retain(|(c, _)| *c != class);
            settings.push((class, Setting { size, face, case, colour }));
        }
        Style { settings }
    }

    pub fn standard_style() -> Style {
        Style { settings: Vec::new() }
    }

    /// Fold one class's setting in, leaving the rest alone.
    pub fn with(&self, class: Class, one: Setting) -> Style {
        let mut settings = self.settings.clone();
        settings.retain(|(c, _)| *c != class);
        settings.push((class, one));
        Style { settings }
    }
}

/// What this project's page is set in.
pub fn of(d: &Doc, project: Id) -> Style {
    match d.get(project).and_then(|r| r.get(f::DOC_STYLE)).and_then(|v| v.as_text()) {
        Some(text) => Style::decode(text),
        None => Style::standard_style(),
    }
}

/// `10.5` rather than `10.5000`, and `11` rather than `11.0` — the string is
/// read by people in a change log.
fn trim(size: f64) -> String {
    if (size - size.round()).abs() < 0.001 {
        format!("{}", size.round() as i64)
    } else {
        format!("{:.2}", size).trim_end_matches('0').trim_end_matches('.').to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_untouched_project_stores_nothing_and_draws_the_standard() {
        let style = Style::standard_style();
        assert_eq!(style.encode(), "");
        assert_eq!(style.get(Class::Body).size, 10.5);
        assert_eq!(style.get(Class::Body).face, Face::Serif);
        // Setting a class to exactly what it already was leaves the record
        // empty — which is what keeps "never touched" and "touched back"
        // the same thing, so a later change to the standard reaches both.
        let same = style.with(Class::Body, standard(Class::Body));
        assert_eq!(same.encode(), "");
    }

    #[test]
    fn one_class_changes_and_the_others_do_not() {
        let style = Style::standard_style()
            .with(Class::Body,
                  Setting { size: 12.0, face: Face::Sans, case: Case::AsTyped, colour: INK });
        assert_eq!(style.encode(), "body=12/sans/as/17171a");
        assert_eq!(style.get(Class::Body).size, 12.0);
        assert_eq!(style.get(Class::Notes), standard(Class::Notes));
        let back = Style::decode(&style.encode());
        assert_eq!(back.get(Class::Body).size, 12.0);
        assert_eq!(back.get(Class::Notes), standard(Class::Notes));
    }

    #[test]
    fn nonsense_is_skipped_and_never_fatal() {
        // A class this engine does not know, a face it does not know, a size
        // that is not a number, and a size no page could want.
        let style = Style::decode(
            "footer=9/serif/as;body=11/comic/as;notes=big/serif/as;\
             technical=900/mono/as;shot_title=13/sans/upper",
        );
        assert_eq!(style.get(Class::Body), standard(Class::Body));
        assert_eq!(style.get(Class::Notes), standard(Class::Notes));
        assert_eq!(style.get(Class::Technical), standard(Class::Technical));
        assert_eq!(style.get(Class::ShotTitle).size, 13.0);
        // The size lands and the case does not: a shot title is words he
        // types, and those are never shouted back at him.
        assert_eq!(style.get(Class::ShotTitle).case, Case::AsTyped);
    }

    #[test]
    fn a_case_cannot_be_forced_on_words_he_types() {
        // The three he edits refuse one, however it arrives — from an older
        // app, a newer one, or a hand-edited file.
        let style = Style::decode("body=11/serif/upper;credits=8/mono/lower");
        assert_eq!(style.get(Class::Body).case, Case::AsTyped);
        assert_eq!(style.get(Class::Body).size, 11.0, "the size still lands");
        assert_eq!(style.get(Class::Credits).case, Case::Lower, "a drawn class takes one");
        assert!(!Class::Body.takes_case());
        assert!(!Class::ShotTitle.takes_case());
        assert!(!Class::Notes.takes_case());
        assert!(Class::Credits.takes_case());
        assert!(Class::Technical.takes_case());
    }

    #[test]
    fn sizes_read_back_the_way_a_person_wrote_them() {
        let style = Style::standard_style()
            .with(Class::Body,
                  Setting { size: 11.0, face: Face::Serif, case: Case::AsTyped, colour: INK })
            .with(Class::Notes,
                  Setting { size: 9.25, face: Face::Serif, case: Case::AsTyped, colour: MUTED });
        assert!(style.encode().contains("body=11/serif/as/17171a"));
        assert!(style.encode().contains("notes=9.25/serif/as/5c5c63"));
    }

    #[test]
    fn a_page_written_before_colours_keeps_the_ink_it_had() {
        // Three parts, which is every project on disk today. The size and the
        // face land; the colour is the one the class has always been drawn in,
        // not black by accident.
        let style = Style::decode("body=12/sans/as;notes=9/serif/as");
        assert_eq!(style.get(Class::Body).size, 12.0);
        assert_eq!(style.get(Class::Body).colour, INK);
        assert_eq!(style.get(Class::Notes).colour, MUTED, "a quiet class stays quiet");
    }

    #[test]
    fn a_colour_survives_the_round_trip_and_nonsense_does_not() {
        let red = Colour::read("#B3261E").expect("a hex colour reads");
        let style = Style::standard_style().with(
            Class::Notes,
            Setting { size: 11.5, face: Face::Serif, case: Case::AsTyped, colour: red },
        );
        assert_eq!(style.encode(), "notes=11.5/serif/as/b3261e");
        assert_eq!(Style::decode(&style.encode()).get(Class::Notes).colour, red);
        // Not a colour: the class is skipped whole rather than drawn in
        // something nobody chose.
        assert_eq!(
            Style::decode("notes=11.5/serif/as/mauve").get(Class::Notes),
            standard(Class::Notes)
        );
        assert!(Colour::read("fff").is_none(), "three digits is not the wire format");
    }
}
