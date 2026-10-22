//! **The project's card, laid over the film** (stage 5 step 4, piece A,
//! 2026-10-14).
//!
//! One record per project, kept by the server: the card. What defines the
//! project — its name, director, producer, client, agency, icon and colour,
//! and the Type its kind follows from — is the card's, not the film's. Until
//! now the film kept a copy of each (`crate::recordfacts`, `crate::mark`),
//! copied in by the server on a clock, and a copy can go stale.
//!
//! So the shell hands the engine the card it read (or its saved copy, offline)
//! and the engine **lays it over the film in memory**. Nothing is written: no
//! log, no undo step, nothing the relay carries. Every reader that draws one
//! of those facts asks [`Doc::fact`], [`Doc::shown_title`], [`Doc::mark`] or
//! [`Doc::kind`], and gets the card's word when the card says one and the
//! film's own otherwise — which is also exactly what an older iPhone build or
//! an export made without a card reads, so nothing that reads the film alone
//! stops working.
//!
//! **A field the card leaves out is not a field the card clears.** The server
//! sends only the facts the record holds (`filmfacts.wantedFacts`); an absent
//! one leaves the film's word showing. An empty one is the record saying
//! *nobody* (or a field the project hides), and shows as empty.
//!
//! **His hand still wins on the mark.** A mark he chose in Studio by hand
//! (`mark_source` `hand`) was never written over by the mirror, and the card
//! does not draw over it either.

use crate::doc::f;
use crate::json::{self, Json};
use crate::kind::Kind;
use crate::mark::{self, Mark, Source};
use crate::Doc;

/// The card, as the engine keeps it for one session.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Card {
    pub title: Option<String>,
    pub director: Option<String>,
    pub producer: Option<String>,
    pub client: Option<String>,
    pub agency: Option<String>,
    pub mark: Option<Mark>,
    pub kind: Option<Kind>,
    /// **The project's shoots** (piece D), first to last. Empty when the card
    /// says none — an older server, or the switch off — and then nothing in
    /// the film is narrowed or counted by shoot.
    pub shoots: Vec<crate::shoots::Shoot>,
    /// **The project's spec sheet as Studio needs it** (piece E): its frames
    /// and each camera's sensor, and a shoot's own when one overrides. None
    /// when the card says nothing of it — an older server, or the switch off
    /// — and then the film's own ratio and typed sensors stand.
    pub sheet: Option<crate::frames::Sheets>,
}

/// The project-record fields a card speaks for, and the card's word for each.
const FIELDS: [(&str, &str); 4] = [
    (f::DIRECTOR, "director"),
    (f::PRODUCER, "producer"),
    (f::CLIENT, "client"),
    (f::AGENCY, "agency"),
];

/// A fact as the card said it, made safe to show: control characters to
/// spaces, trimmed, capped. A name, not a paragraph.
fn tidy(said: &str) -> String {
    let clean: String = said.chars().map(|c| if c.is_control() { ' ' } else { c }).collect();
    clean.trim().chars().take(300).collect()
}

/// **Kind follows Type** (his answer, 2026-10-14): Commercial and Music Video
/// are commercials; Narrative, Personal and anything else are films. An empty
/// Type says nothing, and the film keeps its own kind.
pub fn kind_of_type(type_: &str) -> Option<Kind> {
    match type_.trim().to_ascii_lowercase().as_str() {
        "" => None,
        "commercial" | "music video" => Some(Kind::Commercial),
        _ => Some(Kind::Film),
    }
}

impl Card {
    /// Read the card the server hands out (`hub/src/studiocards.js`): its
    /// `facts` (title, director, producer, client, agency — each present only
    /// when the record holds it), `mark` (`{path, colour}`) and `kind`
    /// (`film`/`commercial`, else read from `type`). Fields it does not know
    /// are ignored, so the server can grow the card without the shells
    /// refusing it. `None` for anything that is not an object.
    pub fn read(text: &str) -> Option<Card> {
        let top = json::parse(text)?;
        if !matches!(top, Json::Object(_)) {
            return None;
        }
        // The facts may sit at the top or under `facts`; both read the same.
        let facts = match top.get("facts") {
            Some(inner @ Json::Object(_)) => inner,
            _ => &top,
        };
        let said = |key: &str| facts.get(key).and_then(Json::as_str).map(tidy);
        let mark = top.get("mark").and_then(|m| {
            let path = mark::outline(m.get("path").and_then(Json::as_str).unwrap_or(""))?;
            let colour = mark::colour(m.get("colour").and_then(Json::as_str).unwrap_or(""))?;
            Some(Mark { path, colour })
        });
        let kind = match top.get("kind").and_then(Json::as_str).map(str::trim) {
            Some("commercial") => Some(Kind::Commercial),
            Some("film") => Some(Kind::Film),
            _ => top.get("type").and_then(Json::as_str).and_then(kind_of_type),
        };
        Some(Card {
            title: said("title"),
            director: said("director"),
            producer: said("producer"),
            client: said("client"),
            agency: said("agency"),
            mark,
            kind,
            shoots: top
                .get("shoots")
                .and_then(Json::as_array)
                .map(crate::shoots::Shoot::read_all)
                .unwrap_or_default(),
            sheet: top.get("sheet").and_then(crate::frames::Sheets::read),
        })
    }

    fn field(&self, field: &str) -> Option<&str> {
        let word = FIELDS.iter().find(|(f, _)| *f == field).map(|(_, w)| *w)?;
        match word {
            "director" => self.director.as_deref(),
            "producer" => self.producer.as_deref(),
            "client" => self.client.as_deref(),
            "agency" => self.agency.as_deref(),
            _ => None,
        }
    }
}

impl Doc {
    /// Lay a card over the film, or take it off (`None`). Writes nothing.
    pub fn set_card(&mut self, card: Option<Card>) {
        self.card = card;
    }

    /// The card laid over this film, if any.
    pub fn card(&self) -> Option<&Card> {
        self.card.as_ref()
    }

    /// **One of the project's facts as it is shown**: the card's word when the
    /// card says one, the film's own otherwise. For `director`, `producer`,
    /// `client` and `agency`; any other field reads the film.
    pub fn fact(&self, field: &str) -> String {
        if let Some(said) = self.card.as_ref().and_then(|c| c.field(field)) {
            return said.to_string();
        }
        self.project_id()
            .and_then(|p| self.get(p))
            .and_then(|r| r.text(field))
            .unwrap_or("")
            .to_string()
    }

    /// The card's title, when a card is laid on and says one.
    pub(crate) fn card_title(&self) -> Option<&str> {
        self.card.as_ref().and_then(|c| c.title.as_deref()).filter(|t| !t.is_empty())
    }

    /// The card's mark, unless his own hand chose the film's.
    pub(crate) fn card_mark(&self) -> Option<&Mark> {
        let mark = self.card.as_ref()?.mark.as_ref()?;
        if self.mark_source() == Source::Hand && self.stored_mark().is_some() {
            return None;
        }
        Some(mark)
    }

    /// The card's kind, when a card is laid on and its Type says one.
    pub(crate) fn card_kind(&self) -> Option<Kind> {
        self.card.as_ref().and_then(|c| c.kind)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::stamp::DeviceId;

    fn film() -> Doc {
        let mut d = Doc::new(DeviceId(1));
        let p = d.create_project("Lets Bake");
        d.set(p, f::DIRECTOR, "Owen Fairweather");
        d.set(p, f::PRODUCER, "Ollie Hart-Brodman");
        d.set(p, f::CLIENT, "Acme");
        d.clear_history();
        d
    }

    const CARD: &str = r##"{"id":"feedface000040008000000000000006","facts":{"title":"Let's Bake","director":"Ollie Hart Brennan","producer":"Marta Delgado","agency":""},"mark":{"path":"M1 1 L2 2 Z","colour":"#d44c47"},"type":"Commercial","extra":[1,2]}"##;

    #[test]
    fn the_card_is_laid_over_and_nothing_is_written() {
        let mut d = film();
        let before = d.changes().len();
        d.set_card(Card::read(CARD));
        assert_eq!(d.changes().len(), before, "laying a card on writes no change");
        assert!(!d.can_undo(), "and makes no undo step");
        assert_eq!(d.shown_title(), "Let's Bake");
        assert_eq!(d.fact(f::DIRECTOR), "Ollie Hart Brennan");
        assert_eq!(d.fact(f::PRODUCER), "Marta Delgado");
        // Absent from the card: the film's own word still shows.
        assert_eq!(d.fact(f::CLIENT), "Acme");
        // Empty on the card: nobody.
        assert_eq!(d.fact(f::AGENCY), "");
        assert_eq!(d.kind(), Kind::Commercial, "kind follows Type");
        assert_eq!(d.mark().map(|m| m.colour), Some("#D44C47".to_string()));
        // The film's own words are still there underneath.
        let p = d.project_id().unwrap();
        assert_eq!(d.get(p).unwrap().text(f::DIRECTOR), Some("Owen Fairweather"));
    }

    #[test]
    fn taking_the_card_off_shows_the_films_own_again() {
        let mut d = film();
        d.set_card(Card::read(CARD));
        d.set_card(None);
        assert_eq!(d.shown_title(), "Lets Bake");
        assert_eq!(d.fact(f::DIRECTOR), "Owen Fairweather");
        assert_eq!(d.kind(), Kind::Film);
        assert!(d.mark().is_none());
    }

    #[test]
    fn music_video_is_a_commercial_and_narrative_a_film() {
        assert_eq!(kind_of_type("Music Video"), Some(Kind::Commercial));
        assert_eq!(kind_of_type("Commercial"), Some(Kind::Commercial));
        assert_eq!(kind_of_type("Narrative"), Some(Kind::Film));
        assert_eq!(kind_of_type("Personal"), Some(Kind::Film));
        assert_eq!(kind_of_type(""), None);
        let mut d = film();
        d.set_kind(Kind::Commercial);
        d.set_card(Card::read(r#"{"type":"Narrative"}"#));
        assert_eq!(d.kind(), Kind::Film);
        d.set_card(Card::read(r#"{"type":""}"#));
        assert_eq!(d.kind(), Kind::Commercial, "no Type: the film's own kind");
    }

    #[test]
    fn his_hand_mark_wins_over_the_card() {
        let mut d = film();
        let own = Mark { path: "M5 5 Z".into(), colour: "#00FF00".into() };
        d.set_mark(Some(&own), Source::Hand);
        d.set_card(Card::read(CARD));
        assert_eq!(d.mark().map(|m| m.colour), Some("#00FF00".to_string()));
    }

    #[test]
    fn a_bad_card_is_no_card() {
        assert!(Card::read("not json").is_none());
        assert!(Card::read("[1]").is_none());
        let half = Card::read(r##"{"mark":{"path":"","colour":"#123456"}}"##).unwrap();
        assert!(half.mark.is_none(), "half a mark is no mark");
        let card = Card::read(r#"{"title":"Top\tLevel"}"#).unwrap();
        assert_eq!(card.title.as_deref(), Some("Top Level"));
    }

    #[test]
    fn the_view_says_the_cards_words() {
        let mut d = film();
        d.set_card(Card::read(CARD));
        let asked = crate::view::Asked::default();
        let standing = crate::view::Standing { read_only: false, unsaved: 0, device_clash: None };
        let v = crate::view::describe(&d, &asked.looking(), &standing);
        let j = json::parse(&v).unwrap();
        let p = j.get("project").unwrap();
        assert_eq!(p.str_field("displayTitle"), "Let's Bake");
        assert_eq!(p.str_field("title"), "Lets Bake", "the film's own title stays (its file name)");
        assert_eq!(p.str_field("director"), "Ollie Hart Brennan");
        assert_eq!(p.str_field("kind"), "commercial");
        assert_eq!(p.str_field("factsSource"), "console");
        assert_eq!(p.get("card").and_then(Json::as_bool), Some(true));
    }
}
