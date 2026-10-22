//! Deciding what is a scene, on a script that has been through a printer.
//!
//! Off a PDF this cannot be made reliable, only adjustable, and these tests
//! are mostly about *what each dial costs*. The fixture is shaped like his own
//! `Call Her Back` draft as Cadrage read it: a numbered scene with a run of bare
//! room names under it, a page header repeating a slug, and the same rooms
//! turning up again later with numbers of their own.

use shotlister_engine::screenplay::{read, read_with, Detection, Status};

const PRINTED: &str = "\
1     INT. REMOTE MANSION (BEDROOM) - MORNING                    1

The phone rings and rings.

2     EXT. BALCONY - CONTINUOUS                                  2

Anya steps out.

3     INT. MANSION - AFTERNOON                                   3

He moves through the house.

BATHROOM.

Steam on the mirror.

BEDROOM.

The bed is made.

HALLWAY.

Nothing.

                                        CONTINUED:

3     INT. MANSION - AFTERNOON                                   3

He is still moving.

4     INT. KITCHEN - NIGHT                                       4

The kettle.
";

#[test]
fn a_page_header_is_not_a_scene_and_does_not_become_anything_else() {
    let screenplay = read_with(PRINTED, &Detection::printed());
    let anything = screenplay
        .elements
        .iter()
        .any(|element| element.text.contains("CONTINUED"));
    assert!(!anything, "the page header survived into the script");
}

#[test]
fn without_the_rule_the_page_header_would_be_read_as_something() {
    // The dial is worth having: with nothing forbidden, `CONTINUED:` reads as a
    // transition, because that is exactly what it looks like.
    let plain = read(PRINTED);
    assert!(plain
        .elements
        .iter()
        .any(|element| element.text.contains("CONTINUED")));
}

#[test]
fn a_number_already_used_does_not_open_a_second_scene() {
    let screenplay = read_with(PRINTED, &Detection::printed());
    let threes = screenplay
        .scenes
        .iter()
        .filter(|scene| scene.script.number.as_deref() == Some("3"))
        .count();
    assert_eq!(threes, 1);
    assert_eq!(screenplay.duplicates_ignored, 1);
}

#[test]
fn what_follows_a_repeated_heading_belongs_to_the_scene_already_open() {
    let screenplay = read_with(PRINTED, &Detection::printed());
    let three = screenplay.scene_numbered("3").expect("scene 3");
    let said: Vec<String> = screenplay
        .elements_in(three)
        .iter()
        .map(|element| element.text.clone())
        .collect();
    assert!(
        said.iter().any(|text| text == "He is still moving."),
        "the carried-over page was orphaned: {said:?}"
    );
}

#[test]
fn a_bare_room_name_is_lettered_under_the_scene_it_is_in() {
    let screenplay = read_with(PRINTED, &Detection::printed());
    let lettered: Vec<(&str, &str)> = screenplay
        .scenes
        .iter()
        .filter(|scene| matches!(scene.status, Status::SubSlug { .. }))
        .map(|scene| (scene.label.as_str(), scene.script.heading.as_str()))
        .collect();
    assert_eq!(
        lettered,
        vec![
            ("3A", "BATHROOM."),
            ("3B", "BEDROOM."),
            ("3C", "HALLWAY."),
        ]
    );
}

#[test]
fn a_room_lettered_under_a_scene_is_offered_and_not_taken() {
    let screenplay = read_with(PRINTED, &Detection::printed());
    for scene in &screenplay.scenes {
        let sub = matches!(scene.status, Status::SubSlug { .. });
        assert_eq!(scene.accepted, !sub, "{} was decided wrongly", scene.label);
    }
    // And so the draft comparison never sees them unless somebody ticks one.
    let taken: Vec<String> = screenplay
        .accepted()
        .into_iter()
        .filter_map(|scene| scene.number)
        .collect();
    assert_eq!(taken, vec!["1", "2", "3", "4"]);
}

#[test]
fn a_room_knows_which_scene_it_is_under() {
    let screenplay = read_with(PRINTED, &Detection::printed());
    let three = screenplay.scene_numbered("3").unwrap();
    let bathroom = screenplay
        .scenes
        .iter()
        .find(|scene| scene.label == "3A")
        .unwrap();
    assert_eq!(bathroom.status, Status::SubSlug { under: three });
}

#[test]
fn reading_plainly_finds_no_rooms_at_all() {
    // The rule that finds a bare room name is the loosest in the file, so it
    // stays off for a Fountain file or plain text, where an unnumbered heading
    // means nothing in particular.
    let screenplay = read(PRINTED);
    assert!(screenplay
        .scenes
        .iter()
        .all(|scene| scene.status == Status::Scene));
}

#[test]
fn letters_start_again_under_each_scene() {
    let text = "\
3     INT. HOUSE - DAY                     3

He walks.

KITCHEN.

Nothing.

5     INT. OFFICE - DAY                    5

She waits.

STAIRWELL.

Nobody.
";
    let screenplay = read_with(text, &Detection::printed());
    let labels: Vec<&str> = screenplay
        .scenes
        .iter()
        .map(|scene| scene.label.as_str())
        .collect();
    assert_eq!(labels, vec!["3", "3A", "5", "5A"]);
}

#[test]
fn a_scene_with_more_rooms_than_the_alphabet_keeps_counting() {
    let mut text = String::from("3     INT. HOUSE - DAY     3\n\nHe walks.\n\n");
    for room in 0..27 {
        text.push_str(&format!("ROOM {room}.\n\nNothing.\n\n"));
    }
    let screenplay = read_with(&text, &Detection::printed());
    let last = screenplay.scenes.last().unwrap();
    assert_eq!(last.label, "3AA");
}

#[test]
fn a_slug_must_carry_one_of_the_words_when_words_are_asked_for() {
    let text = "\
1     INT. KITCHEN - DAY        1

She waits.

2     THE VOID - FOREVER        2

Nothing at all.
";
    let asking = Detection {
        must_contain: vec!["INT".to_string(), "EXT".to_string()],
        ..Detection::printed()
    };
    let screenplay = read_with(text, &asking);
    let numbers: Vec<String> = screenplay
        .accepted()
        .into_iter()
        .filter_map(|scene| scene.number)
        .collect();
    assert_eq!(numbers, vec!["1"]);
}

#[test]
fn an_unnumbered_heading_with_nothing_above_it_still_stands_as_a_scene() {
    // There is nothing to letter it under, so refusing it would lose the whole
    // opening of the film.
    //
    // **It used to stand there with an empty label**, and that turned out to be
    // the same thing as losing it: the import skips a scene with no number,
    // so a draft nobody numbered came in as nothing at all. His report,
    // 2026-08-22. A draft with no numbers anywhere is now numbered by position
    // — see `number_by_position` — so the opening of the film is scene 1.
    let screenplay = read_with("INT. KITCHEN - DAY\n\nShe waits.\n", &Detection::printed());
    assert_eq!(screenplay.scenes.len(), 1);
    assert_eq!(screenplay.scenes[0].status, Status::Scene);
    assert!(screenplay.scenes[0].accepted);
    assert_eq!(screenplay.scenes[0].label, "1");
}

/// **A whole draft with no numbers in it is numbered by where its scenes are.**
///
/// The rule that says an unnumbered heading belongs to the scene above it is
/// right for a numbered draft with a bare room name in it, and exactly wrong
/// for a script nobody numbered: the first heading became a scene with no
/// label, every one after it became a room, and the import took none of them.
#[test]
fn a_draft_nobody_numbered_is_numbered_in_order() {
    let text = "\
INT. KITCHEN - DAY

She waits.

EXT. STREET - LATER

He runs.

INT. CAR - NIGHT

Rain.
";
    let screenplay = read_with(text, &Detection::printed());
    assert_eq!(screenplay.scenes.len(), 3);
    let labels: Vec<&str> = screenplay.scenes.iter().map(|s| s.label.as_str()).collect();
    assert_eq!(labels, ["1", "2", "3"], "{screenplay:#?}");
    // Every one of them taken by default: they are scenes, not rooms.
    assert!(screenplay.scenes.iter().all(|scene| scene.accepted));
    assert!(screenplay
        .scenes
        .iter()
        .all(|scene| scene.status == Status::Scene));
    // And the number is on the scene itself, which is what the import reads.
    assert_eq!(screenplay.scenes[2].script.number.as_deref(), Some("3"));
}

/// **One number anywhere is enough to say the writer is numbering.** A draft
/// that numbers some of its scenes keeps the old rule for the rest, because
/// there an unnumbered heading really does mean a room inside the scene above.
#[test]
fn a_draft_that_numbers_even_one_scene_is_left_alone() {
    let text = "\
7     INT. CAR - NIGHT        7

Rain.

INT. GARAGE - LATER

He parks.
";
    let screenplay = read_with(text, &Detection::printed());
    assert_eq!(screenplay.scenes[0].label, "7");
    assert_eq!(screenplay.scenes[1].label, "7A");
    assert!(!screenplay.scenes[1].accepted);
}

/// A room found inside an unnumbered draft letters off the number the scene
/// was just given, rather than off the empty label it had a moment before.
#[test]
fn a_room_in_an_unnumbered_draft_letters_off_its_new_number() {
    let text = "\
INT. KITCHEN - DAY

She waits.

EXT. STREET - LATER

He runs.

BATHROOM.

The tap drips.
";
    let screenplay = read_with(text, &Detection::printed());
    let room = screenplay
        .scenes
        .iter()
        .find(|scene| scene.script.location == "BATHROOM")
        .expect("the room is found");
    assert_eq!(room.label, "2A", "{screenplay:#?}");
    assert!(!room.accepted);
}

#[test]
fn an_unnumbered_slug_inside_a_numbered_script_is_lettered_not_lost() {
    let text = "\
7     INT. CAR - NIGHT        7

Rain.

INT. GARAGE - LATER

He parks.
";
    let screenplay = read_with(text, &Detection::printed());
    assert_eq!(screenplay.scenes[1].label, "7A");
    assert_eq!(screenplay.scenes[1].script.location, "GARAGE");
    assert!(!screenplay.scenes[1].accepted);
}

#[test]
fn a_line_of_action_in_capitals_is_found_as_a_room_and_this_is_the_cost() {
    // Stated rather than hidden. The rule cannot tell `BATHROOM.` from
    // `A LOUD BANG.` — nothing can, from the line alone. It is why what it
    // finds arrives unticked, and why the whole rule is off by default.
    let text = "3     INT. HOUSE - DAY     3\n\nHe walks.\n\nA LOUD BANG.\n\nHe stops.\n";
    let screenplay = read_with(text, &Detection::printed());
    let found = screenplay.scenes.iter().find(|scene| scene.label == "3A");
    assert!(found.is_some(), "the rule is loose and the test says so");
    assert!(!found.unwrap().accepted, "but it is never taken by itself");
}

#[test]
fn the_dials_are_independent() {
    // Duplicates ignored, but rooms not looked for: scene 3 appears once and
    // nothing is lettered.
    let detection = Detection {
        find_sub_slugs: false,
        ..Detection::printed()
    };
    let screenplay = read_with(PRINTED, &detection);
    assert_eq!(screenplay.duplicates_ignored, 1);
    assert!(screenplay
        .scenes
        .iter()
        .all(|scene| scene.status == Status::Scene));
}

// ---------------------------------------------------------------------------
// The time of day — Ref 257.
//
// His report, 2026-08-22: CONTINUED and LATER were arriving as times of day.
// They are not times; they point back at the last scene that named one.

#[test]
fn continuous_and_later_take_the_time_from_the_scene_before() {
    let draft = "\
INT. KITCHEN - MORNING

She puts the kettle on.

INT. HALLWAY - CONTINUOUS

He is already at the door.

EXT. DRIVEWAY - LATER

The car is gone.

INT. BEDROOM - NIGHT

Dark.

INT. LANDING - CONTINUED

Darker.
";
    let read = shotlister_engine::script::parse(draft);
    let times: Vec<&str> = read.iter().map(|s| s.time_of_day.as_str()).collect();
    assert_eq!(
        times,
        vec!["DAY", "DAY", "DAY", "NIGHT", "NIGHT"],
        "a pointer takes the last real time, and keeps taking it"
    );

    // **The heading is never touched.** The slugline is the script's own and
    // the writer wrote CONTINUOUS on purpose.
    assert!(read[1].heading.contains("CONTINUOUS"));
}

#[test]
fn a_written_time_is_snapped_to_one_the_app_actually_offers() {
    use shotlister_engine::script::time_of_day_meaning;

    // The synonyms that turn up in real drafts.
    assert_eq!(time_of_day_meaning("MAGIC HOUR"), Some("SUNSET"));
    assert_eq!(time_of_day_meaning("SUNSET"), Some("SUNSET"));
    assert_eq!(time_of_day_meaning("SUNRISE"), Some("SUNRISE"));
    assert_eq!(time_of_day_meaning("PRE-DAWN"), Some("SUNRISE"));
    assert_eq!(time_of_day_meaning("DAWN"), Some("SUNRISE"));
    assert_eq!(time_of_day_meaning("MIDNIGHT"), Some("NIGHT"));
    assert_eq!(time_of_day_meaning("NOON"), Some("DAY"));

    // **The words that stopped being answers of their own**, his instruction
    // of 2026-09-02 — the app holds four times of day and no more. None of
    // them is lost: everything lit is the day, and each edge of the day keeps
    // one word. All of them still print in the slug line, which is the
    // script's.
    assert_eq!(time_of_day_meaning("MORNING"), Some("DAY"));
    assert_eq!(time_of_day_meaning("AFTERNOON"), Some("DAY"));
    assert_eq!(time_of_day_meaning("EVENING"), Some("SUNSET"));
    assert_eq!(time_of_day_meaning("DUSK"), Some("SUNSET"));
    assert_eq!(time_of_day_meaning("TWILIGHT"), Some("SUNSET"));
    assert_eq!(time_of_day_meaning("NIGHTFALL"), Some("SUNSET"));

    // Longest first, and whole words — the two ways this goes wrong.
    assert_eq!(time_of_day_meaning("LATE NIGHT"), Some("NIGHT"));
    assert_eq!(time_of_day_meaning("LATER THAT NIGHT"), Some("NIGHT"));
    assert_eq!(time_of_day_meaning("THE NEXT MORNING"), Some("DAY"));
    assert_eq!(
        time_of_day_meaning("YESTERDAY"),
        None,
        "DAY inside another word is not a time of day"
    );
    assert_eq!(time_of_day_meaning("SUNDAY"), None);

    // Something nobody can read stays out of the field, and the heading keeps
    // it — a word in a column that no filter can match is worse than a blank.
    assert_eq!(time_of_day_meaning("THE HOUR OF THE WOLF"), None);
}

#[test]
fn a_pointer_with_nothing_to_point_at_is_left_blank_rather_than_guessed() {
    let draft = "\
INT. KITCHEN - CONTINUOUS

The first scene of the film cannot be the same as the one before it.

INT. HALL - DAY

Light.
";
    let read = shotlister_engine::script::parse(draft);
    assert_eq!(read[0].time_of_day, "");
    assert_eq!(read[1].time_of_day, "DAY");
}

/// **His script's own words survive being conformed.** Ref 257's follow-up.
///
/// He reported it on 2026-08-22: *"Sc 13 is EXT. Pool -- Later in the script
/// but in the shot list it was conformed to EVENING."* Nothing had been lost —
/// the heading was on the record the whole time — but the app was rebuilding
/// the slug out of its parts rather than reading it, so as soon as a time of
/// day was conformed the script's own line was gone from the screen.
#[test]
fn conforming_a_time_of_day_leaves_the_printed_slug_alone() {
    use shotlister_engine::doc::f;
    use shotlister_engine::{DeviceId, Doc, Value};

    let mut doc = Doc::new(DeviceId(1));
    doc.create_project("Call Her Back");
    // Scene 12 arrived written EVENING and has already been conformed —
    // EVENING stopped being a time of day on 2026-09-02 and now means SUNSET.
    // The word it printed is still on its heading, untouched, which is the
    // whole point of this test.
    let earlier = doc.create_scene("12");
    doc.set(earlier, f::HEADING, Value::text("EXT. POOL - EVENING"));
    doc.set(earlier, f::INT_EXT, Value::text("EXT"));
    doc.set(earlier, f::LOCATION, Value::text("POOL"));
    doc.set(earlier, f::TIME_OF_DAY, Value::text("SUNSET"));

    let thirteen = doc.create_scene("13");
    doc.set(thirteen, f::HEADING, Value::text("EXT. POOL - LATER"));
    doc.set(thirteen, f::INT_EXT, Value::text("EXT"));
    doc.set(thirteen, f::LOCATION, Value::text("POOL"));
    doc.set(thirteen, f::TIME_OF_DAY, Value::text("LATER"));

    assert_eq!(doc.settle_scene_times(), 1);

    // The data point conformed…
    assert_eq!(
        doc.get(thirteen).unwrap().text(f::TIME_OF_DAY),
        Some("SUNSET")
    );
    // …and the words he wrote did not move.
    assert_eq!(
        doc.scene_heading(thirteen).as_deref(),
        Some("EXT. POOL - LATER"),
        "the slug line belongs to the script"
    );
}

/// A scene that names no time takes the last one — his ruling of the same day.
#[test]
fn a_slug_with_no_time_of_day_takes_the_last_one() {
    let read = shotlister_engine::script::parse(
        "1    INT. KITCHEN - MORNING\n\nShe waits.\n\n2    INT. HALLWAY\n\nHe does not.\n",
    );
    assert_eq!(read[1].time_of_day, "DAY");
    // And the slug that printed no time still prints none.
    assert_eq!(read[1].heading, "INT. HALLWAY");
}
