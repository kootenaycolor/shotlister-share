//! Reading a draft, and saying what it would change.

use shotlister_engine::doc::f;
use shotlister_engine::script;
use shotlister_engine::{DeviceId, Doc};

const DRAFT: &str = "\
34    INT. JAIL CORRIDOR - DAY                                   34

Sunlight through the high window. FRANK walks the length of it.

                    FRANK
          It never gets shorter.

35    EXT. PRISON YARD - NIGHT                                   35

Floodlights. Nobody moves.
";

#[test]
fn a_slug_becomes_a_scene() {
    let scenes = script::parse(DRAFT);

    assert_eq!(scenes.len(), 2);
    assert_eq!(scenes[0].number.as_deref(), Some("34"));
    assert_eq!(scenes[0].int_ext, "INT");
    assert_eq!(scenes[0].location, "JAIL CORRIDOR");
    assert_eq!(scenes[0].time_of_day, "DAY");
    assert!(scenes[0].body.contains("FRANK walks"));
    assert!(
        !scenes[0].body.contains("PRISON YARD"),
        "a scene's body stops at the next slug"
    );

    assert_eq!(scenes[1].number.as_deref(), Some("35"));
    assert_eq!(scenes[1].int_ext, "EXT");
    assert_eq!(scenes[1].time_of_day, "NIGHT");
}

#[test]
fn the_forms_a_slug_actually_gets_printed_in() {
    let text = "\
INT./EXT. CAR - CONTINUOUS
I/E. TRAIN - DUSK
EXT DESERT HIGHWAY - DAY
1. INT. KITCHEN - MORNING
";
    let scenes = script::parse(text);
    assert_eq!(scenes.len(), 4);
    assert_eq!(scenes[0].int_ext, "INT/EXT");
    assert_eq!(scenes[1].int_ext, "INT/EXT");
    assert_eq!(scenes[1].location, "TRAIN");
    assert_eq!(scenes[2].int_ext, "EXT");
    assert_eq!(scenes[2].location, "DESERT HIGHWAY");
    assert_eq!(scenes[3].number.as_deref(), Some("1"));
    assert_eq!(scenes[3].location, "KITCHEN");
}

#[test]
fn a_line_that_merely_starts_with_int_is_not_a_slug() {
    let text = "\
34  INT. ROOM - DAY   34

INTERIOR MONOLOGUE, she thinks, is a terrible device.
INTERCUT WITH:
";
    let scenes = script::parse(text);
    assert_eq!(scenes.len(), 1, "one slug, not three");
    assert!(scenes[0].body.contains("INTERIOR MONOLOGUE"));
}

#[test]
fn a_location_may_contain_a_dash() {
    let scenes = script::parse("12  EXT. SAINT-DENIS ROOFTOP - DAWN  12\n");
    assert_eq!(scenes[0].location, "SAINT-DENIS ROOFTOP");
    assert_eq!(scenes[0].time_of_day, "SUNRISE");
}

// ---- what a draft would change -------------------------------------------

fn a_project() -> Doc {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let thirty_four = d.create_scene("34");
    d.set(thirty_four, f::INT_EXT, "INT");
    d.set(thirty_four, f::LOCATION, "JAIL CORRIDOR");
    d.set(thirty_four, f::TIME_OF_DAY, "DAY");
    d.add_shot_to_scene(thirty_four);
    d
}

#[test]
fn a_draft_that_changes_nothing_says_so() {
    let mut d = a_project();
    let thirty_five = d.create_scene("35");
    d.set(thirty_five, f::INT_EXT, "EXT");
    d.set(thirty_five, f::LOCATION, "PRISON YARD");
    d.set(thirty_five, f::TIME_OF_DAY, "NIGHT");

    let diff = d.diff_script(&script::parse(DRAFT));

    assert!(diff.is_empty());
    assert_eq!(diff.unchanged, 2);
    assert!(!diff.needs_confirming());
    assert!(diff.summary().contains("Nothing has changed"), "{}", diff.summary());
}

#[test]
fn a_new_scene_is_offered_rather_than_created() {
    let d = a_project();
    let before = d.scenes_in_order().len();

    let diff = d.diff_script(&script::parse(DRAFT));

    assert_eq!(diff.added.len(), 1);
    assert_eq!(diff.added[0].number.as_deref(), Some("35"));
    assert_eq!(
        d.scenes_in_order().len(),
        before,
        "working out what would change changes nothing"
    );
}

#[test]
fn a_scene_that_has_moved_shows_both_sides() {
    let d = a_project();
    let draft = script::parse("34  INT. JAIL CELL - NIGHT  34\n");

    let diff = d.diff_script(&draft);

    assert_eq!(diff.changed.len(), 1);
    let change = &diff.changed[0];
    assert_eq!(change.number, "34");
    let fields: Vec<&str> = change.differences.iter().map(|(f, _, _)| f.as_str()).collect();
    assert!(fields.contains(&"location") && fields.contains(&"time_of_day"));
    let location = change.differences.iter().find(|(f, _, _)| f == "location").unwrap();
    assert_eq!(location.1, "JAIL CORRIDOR", "what we have");
    assert_eq!(location.2, "JAIL CELL", "what the draft says");
    assert!(diff.needs_confirming());
}

#[test]
fn a_scene_that_has_left_the_draft_is_reported_and_never_removed() {
    let d = a_project();
    let draft = script::parse("35  EXT. PRISON YARD - NIGHT  35\n");

    let diff = d.diff_script(&draft);

    assert_eq!(diff.gone.len(), 1);
    assert_eq!(diff.gone[0].number, "34");
    assert_eq!(
        diff.gone[0].shots, 1,
        "how much work would go with it, which is the number somebody needs"
    );
    assert!(diff.needs_confirming());
    assert!(
        diff.summary().contains("no longer in the script"),
        "{}",
        diff.summary()
    );
}

#[test]
fn applying_a_draft_creates_and_updates_but_takes_nothing_away() {
    let mut d = a_project();
    let gone_before = d.scene_numbered("34").expect("34 is there");
    let draft = script::parse("35  EXT. PRISON YARD - NIGHT  35\n");
    let diff = d.diff_script(&draft);

    let touched = d.apply_script(&diff);

    assert_eq!(touched, 1);
    let created = d.scene_numbered("35").expect("35 was created");
    assert_eq!(
        d.get(created).and_then(|r| r.text(f::LOCATION)),
        Some("PRISON YARD")
    );
    assert!(
        d.get(gone_before).is_some(),
        "a script revision is not authority to throw shots away"
    );
}

#[test]
fn a_whole_draft_is_one_thing_to_take_back() {
    let mut d = a_project();
    let diff = d.diff_script(&script::parse(DRAFT));
    let depth = d.undo_depth();

    d.apply_script(&diff);
    assert_eq!(d.undo_depth(), depth + 1, "not one step per scene");

    d.undo();
    assert!(
        d.scene_numbered("35").is_none(),
        "a draft applied by mistake is one keystroke, not an afternoon"
    );
}

#[test]
fn an_updated_scene_keeps_its_shots_and_their_numbers() {
    let mut d = a_project();
    let scene = d.scene_numbered("34").unwrap();
    let placement = d.placements_in_scene(scene)[0];
    let number = d.display_number(placement);

    let diff = d.diff_script(&script::parse("34  INT. JAIL CELL - NIGHT  34\n"));
    d.apply_script(&diff);

    assert_eq!(d.placements_in_scene(scene).len(), 1);
    assert_eq!(d.display_number(placement), number);
    assert_eq!(d.get(scene).and_then(|r| r.text(f::LOCATION)), Some("JAIL CELL"));
}

#[test]
fn an_unnumbered_draft_is_said_to_be_unmatchable_rather_than_guessed_at() {
    let d = a_project();
    let draft = script::parse("INT. JAIL CORRIDOR - DAY\n\nSomething happens.\n");

    let diff = d.diff_script(&draft);

    assert_eq!(diff.unnumbered, 1);
    assert!(diff.needs_confirming());
    assert!(
        diff.summary().contains("not matched"),
        "{}",
        diff.summary()
    );
    // And scene 34 is not reported as gone on the strength of an unnumbered
    // draft that plainly describes it.
    assert_eq!(diff.gone.len(), 1, "it is reported, but only as unmatched");
}

#[test]
fn a_leading_zero_does_not_make_a_different_scene() {
    let d = a_project();
    let diff = d.diff_script(&script::parse("034  INT. JAIL CORRIDOR - DAY  034\n"));

    assert!(diff.added.is_empty(), "034 and 34 are the same scene");
    assert_eq!(diff.unchanged, 1);
}

#[test]
fn the_script_itself_lands_on_the_scene() {
    let mut d = a_project();
    let diff = d.diff_script(&script::parse(DRAFT));
    d.apply_script(&diff);

    let scene = d.scene_numbered("35").unwrap();
    let script = d.get(scene).and_then(|r| r.text(f::SCRIPT)).unwrap_or_default();
    assert!(script.contains("Floodlights"), "got {script:?}");
}
