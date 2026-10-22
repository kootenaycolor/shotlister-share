//! The portal's Script page draws the shots' marks beside a draft's lines
//! (Ref 1568, the portal's half): the engine in the browser answers which
//! shots hold which lines of a draft, and what a draft no longer has.
use shotlister_engine::json::parse;
use shotlister_engine::playties::Draft;
use shotlister_engine::screenplay::{read_with, Detection};
use shotlister_engine::{lay_out, DeviceId, Doc};
use shotlister_web::Film;

const ONE: &str = "1 INT. KITCHEN - DAY 1\n\nANNA pours tea.\n\nANNA\nMorning.\n\n2 INT. HALL - NIGHT 2\n\nBEN\nMorning.\n";

fn draft_of(text: &str) -> Draft {
    let play = read_with(text, &Detection::default());
    Draft::of(&play, &lay_out(&play))
}

#[test]
fn a_line_names_the_shots_that_hold_it_and_a_cut_line_is_reported() {
    let mut film = Film::new();
    film.doc = Doc::new(DeviceId(1));
    film.doc.create_project("Marks");
    let one = film.doc.create_scene("1");
    let two = film.doc.create_scene("2");
    let (a, _) = film.doc.add_shot_to_scene(one);
    let (b, _) = film.doc.add_shot_to_scene(two);
    let draft = draft_of(ONE);
    assert!(film.doc.tie_play_words(a, None, Some(&draft), "ANNA pours tea.", false));
    assert!(film.doc.tie_play_words(b, None, Some(&draft), "Morning.", false));

    let said = parse(&film.script_marks(ONE)).expect("JSON");
    let pages = said.get("pageList").and_then(|p| p.as_array()).unwrap();
    let mut held: Vec<(String, Vec<String>)> = Vec::new();
    for page in pages {
        for line in page.get("lines").and_then(|l| l.as_array()).unwrap() {
            let shots: Vec<String> = line
                .get("shots")
                .and_then(|s| s.as_array())
                .map(|s| s.iter().filter_map(|x| x.as_str().map(String::from)).collect())
                .unwrap_or_default();
            held.push((line.str_field("text"), shots));
        }
    }
    let of = |words: &str| held.iter().rev().find(|(t, _)| t == words).map(|(_, s)| s.clone()).unwrap();
    assert_eq!(of("ANNA pours tea.").len(), 1, "{held:?}");
    assert_eq!(of("Morning.").len(), 1, "scene 2's Morning: {held:?}");
    let first = held.iter().find(|(t, _)| t == "Morning.").unwrap();
    assert!(first.1.is_empty(), "scene 1's Morning is not tied: {held:?}");
    assert!(of("ANNA").is_empty());
    let ties = said.get("ties").and_then(|t| t.as_array()).unwrap();
    assert_eq!(ties.len(), 2);
    assert!(said.get("lost").and_then(|t| t.as_array()).unwrap().is_empty());

    // A new draft cuts scene 2's words: reported, never moved.
    let cut = ONE.replace("BEN\nMorning.", "BEN\nHello?");
    let said = parse(&film.script_marks(&cut)).unwrap();
    let lost = said.get("lost").and_then(|t| t.as_array()).unwrap();
    assert_eq!(lost.len(), 1);
    assert_eq!(lost[0].get("words").and_then(|w| w.as_array()).unwrap()[0].as_str(), Some("Morning."));
    assert_eq!(said.get("ties").and_then(|t| t.as_array()).unwrap().len(), 1);
}
