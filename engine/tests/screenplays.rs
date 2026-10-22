//! Reading a screenplay as a screenplay: what each line turns out to be.
//!
//! The cases here are the ones that go wrong in real drafts, not the ones that
//! are easy to write: a shout in the middle of an action paragraph that is not
//! a character, a character whose name has a full stop in it, a writer's note
//! that must never reach the page, and a slug the writer had to force because
//! the film has a scene called MEMORY.

use shotlister_engine::screenplay::{read, Kind};

fn kinds(text: &str) -> Vec<(Kind, String)> {
    read(text)
        .elements
        .into_iter()
        .map(|element| (element.kind, element.text))
        .collect()
}

const DAYBREAK: &str = "\
INT. KITCHEN - DAY

Melissa stands at the window. The kettle boils.

MELISSA
(quietly)
You're up early.

JIMMY (O.S.)
Couldn't sleep.

CUT TO:

EXT. DRIVEWAY - CONTINUOUS

The car is gone.
";

#[test]
fn a_screenplay_becomes_the_lines_it_is_made_of() {
    let found = kinds(DAYBREAK);
    let expected = [
        (Kind::SceneHeading, "INT. KITCHEN - DAY"),
        (Kind::Action, "Melissa stands at the window. The kettle boils."),
        (Kind::Character, "MELISSA"),
        (Kind::Parenthetical, "(quietly)"),
        (Kind::Dialogue, "You're up early."),
        (Kind::Character, "JIMMY (O.S.)"),
        (Kind::Dialogue, "Couldn't sleep."),
        (Kind::Transition, "CUT TO:"),
        (Kind::SceneHeading, "EXT. DRIVEWAY - CONTINUOUS"),
        (Kind::Action, "The car is gone."),
    ];
    assert_eq!(found.len(), expected.len(), "got {found:#?}");
    for (got, want) in found.iter().zip(expected) {
        assert_eq!((got.0, got.1.as_str()), want);
    }
}

#[test]
fn every_element_knows_which_scene_it_is_in() {
    let screenplay = read(DAYBREAK);
    assert_eq!(screenplay.scenes.len(), 2);
    // Eight, because the transition out of a scene belongs to the scene it
    // leaves, which is where an editor looks for it.
    assert_eq!(screenplay.elements_in(0).len(), 8);
    assert_eq!(screenplay.elements_in(1).len(), 2);
}

#[test]
fn a_shout_in_the_action_is_not_somebody_speaking() {
    // Capitals with nothing under them, and capitals ending in a full stop, are
    // both how action gets written — and both would become silent characters
    // under a rule that only looked at the case.
    let found = kinds("INT. HALL - NIGHT\n\nThe door slams.\n\nA LOUD BANG.\n\nNobody moves.\n");
    assert_eq!(
        found
            .iter()
            .filter(|(kind, _)| *kind == Kind::Character)
            .count(),
        0,
        "got {found:#?}"
    );
}

#[test]
fn a_name_is_still_a_name_with_a_full_stop_inside_its_extension() {
    let found = kinds("INT. CAR - DAY\n\nMRS. O'HARA (V.O.)\nWe were young.\n");
    assert!(found.contains(&(Kind::Character, "MRS. O'HARA (V.O.)".to_string())));
}

#[test]
fn the_writers_private_matter_never_reaches_the_page() {
    let text = "INT. KITCHEN - DAY\n\nShe waits. [[check this against the book]]\n\n\
                /*\nEXT. BEACH - DAY\n\nThe whole scene we cut.\n*/\n\nHe leaves.\n";
    let screenplay = read(text);
    assert_eq!(screenplay.scenes.len(), 1, "the cut scene is not a scene");
    let all = screenplay
        .elements
        .iter()
        .map(|e| e.text.clone())
        .collect::<Vec<_>>()
        .join(" ");
    assert!(!all.contains("check this"), "a note reached the page: {all}");
    assert!(!all.contains("BEACH"), "the boneyard reached the page: {all}");
}

#[test]
fn a_forced_heading_makes_a_scene_that_no_rule_would_have_found() {
    let screenplay = read("INT. KITCHEN - DAY\n\nShe waits.\n\n.MEMORY\n\nA beach, once.\n");
    assert_eq!(screenplay.scenes.len(), 2);
    assert_eq!(screenplay.scenes[1].script.heading, "MEMORY");
    assert_eq!(screenplay.elements[2].kind, Kind::SceneHeading);
}

#[test]
fn an_ellipsis_at_the_start_of_a_line_is_not_a_scene() {
    let screenplay = read("INT. KITCHEN - DAY\n\n...and then nothing.\n");
    assert_eq!(screenplay.scenes.len(), 1);
    assert_eq!(screenplay.elements[1].kind, Kind::Action);
}

#[test]
fn a_writer_can_force_what_the_rules_would_get_wrong() {
    let found = kinds("INT. HALL - DAY\n\n!A LOUD BANG.\n\n@McCLANE\nYippee.\n\n>THE END<\n");
    assert!(found.contains(&(Kind::Action, "A LOUD BANG.".to_string())));
    assert!(found.contains(&(Kind::Character, "McCLANE".to_string())));
    assert!(found.contains(&(Kind::Centered, "THE END".to_string())));
}

#[test]
fn two_people_talking_at_once_is_marked_and_not_lost() {
    let screenplay = read("INT. KITCHEN - DAY\n\nMELISSA\nGo.\n\nJIMMY ^\nI'm going.\n");
    let jimmy = screenplay
        .elements
        .iter()
        .find(|e| e.text == "JIMMY")
        .expect("the second speaker survives the caret");
    assert!(jimmy.dual);
    let melissa = screenplay.elements.iter().find(|e| e.text == "MELISSA").unwrap();
    assert!(!melissa.dual, "only the right-hand column is marked");
}

#[test]
fn sections_and_synopses_are_the_writers_scaffolding_and_are_not_printed() {
    let screenplay = read("# Act One\n\n= She finally says it.\n\nINT. KITCHEN - DAY\n\nShe says it.\n");
    let section = &screenplay.elements[0];
    assert_eq!(section.kind, Kind::Section);
    assert_eq!(section.text, "Act One");
    assert!(!section.kind.is_printed());
    assert_eq!(screenplay.elements[1].kind, Kind::Synopsis);
    // And neither ends up in the scene's text.
    assert_eq!(screenplay.scenes[0].script.body, "She says it.");
}

#[test]
fn a_page_break_the_writer_asked_for_is_kept() {
    let found = kinds("INT. KITCHEN - DAY\n\nShe waits.\n\n===\n\nHe leaves.\n");
    assert!(found.iter().any(|(kind, _)| *kind == Kind::PageBreak));
}

#[test]
fn a_title_page_is_read_and_does_not_become_the_first_scene() {
    let screenplay = read(
        "Title:\n    DAYBREAK\nCredit: Written by\nAuthor: Nathaniel Regier\nDraft date: 20/08/26\n\n\
         INT. KITCHEN - DAY\n\nShe waits.\n",
    );
    assert_eq!(screenplay.titled("Title"), Some("DAYBREAK"));
    assert_eq!(screenplay.titled("author"), Some("Nathaniel Regier"));
    assert_eq!(screenplay.scenes.len(), 1);
    assert_eq!(screenplay.elements[0].kind, Kind::SceneHeading);
}

#[test]
fn a_screenplay_that_opens_on_a_slug_has_no_title_page() {
    let screenplay = read(DAYBREAK);
    assert!(screenplay.title.is_empty());
}

#[test]
fn a_colon_in_a_line_of_dialogue_does_not_start_a_title_page() {
    let screenplay = read("INT. KITCHEN - DAY\n\nMELISSA\nHere's the thing: I'm leaving.\n");
    assert!(screenplay.title.is_empty());
    assert_eq!(screenplay.elements.last().unwrap().kind, Kind::Dialogue);
}

#[test]
fn an_action_paragraph_the_writer_broke_by_hand_stays_broken() {
    let screenplay = read("INT. KITCHEN - DAY\n\nShe waits.\nAnd waits.\n");
    assert_eq!(screenplay.elements[1].text, "She waits.\nAnd waits.");
}

#[test]
fn a_scene_carries_its_number_through_from_the_draft() {
    let screenplay = read("34  INT. KITCHEN - DAY  34\n\nShe waits.\n");
    assert_eq!(screenplay.scenes[0].script.number.as_deref(), Some("34"));
    assert_eq!(screenplay.scene_numbered("034"), Some(0));
}

#[test]
fn what_the_reader_finds_is_what_the_draft_comparison_reads() {
    // The point of `scenes`: a screenplay read here goes straight into the
    // existing diff without a second opinion about what a scene is.
    use shotlister_engine::doc::f;
    use shotlister_engine::{DeviceId, Doc, Value};

    let mut doc = Doc::new(DeviceId(1));
    let scene = doc.create_scene("34");
    doc.set(scene, f::LOCATION, Value::text("KITCHEN"));
    doc.set(scene, f::TIME_OF_DAY, Value::text("NIGHT"));
    doc.set(scene, f::INT_EXT, Value::text("INT"));

    let screenplay = read("34  INT. KITCHEN - DAY  34\n\nShe waits.\n");
    let diff = doc.diff_script(&screenplay.accepted());
    assert_eq!(diff.changed.len(), 1, "the day/night change is seen");
    assert!(diff.added.is_empty());
    assert!(diff.gone.is_empty());
}

#[test]
fn plain_text_needs_no_marks_at_all() {
    // A screenplay typed normally, with nothing Fountain about it, reads
    // correctly — which is the whole reason there is no separate plain path.
    let found = kinds("EXT. FIELD - DUSK\n\nWind.\n\nJIMMY\nIt's late.\n\nFADE OUT:\n");
    assert_eq!(found[0].0, Kind::SceneHeading);
    assert_eq!(found[1].0, Kind::Action);
    assert_eq!(found[2].0, Kind::Character);
    assert_eq!(found[3].0, Kind::Dialogue);
    assert_eq!(found[4].0, Kind::Transition);
}
