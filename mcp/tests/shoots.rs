//! One shoot of a project that shoots more than once (stage 5 step 5):
//! `shoot` narrows scenes, shots, schedule, locations and kit; with one
//! shoot it is ignored; a shoot nobody has is refused, naming the ones there.

mod common;
use common::*;
use shotlister_mcp::Films;

fn numbers(said: &str, key: &str) -> Vec<String> {
    match json::parse(said).expect("json") {
        Json::Array(rows) => rows.iter().map(|r| r.str_field(key)).collect(),
        other => panic!("not a list: {}", other.encode()),
    }
}

#[test]
fn one_shoot_narrows_what_is_read() {
    let (_x, mut s) = opened("shoots");
    ok(&mut s, "add_section", &[("title", "Shoot 1 — July 9")]);
    ok(&mut s, "add_scene", &[("number", "1"), ("section", "Shoot 1 — July 9")]);
    ok(&mut s, "add_scene", &[("number", "2"), ("section", "Shoot 1 — July 9")]);
    ok(&mut s, "add_shot", &[("scene", "1")]);
    ok(&mut s, "add_shot", &[("scene", "2")]);
    ok(&mut s, "add_shot", &[("scene", "2")]);
    ok(&mut s, "add_location", &[("name", "Kitchen")]);
    ok(&mut s, "set_scene_locations", &[("scene", "1"), ("add", "Kitchen")]);
    ok(&mut s, "add_day", &[("date", "2026-07-09"), ("name", "Shoot 1")]);
    ok(&mut s, "schedule_shot", &[("shots", "1A, 2A, 2B"), ("day", "Day 1")]);

    // One shoot: `shoot` is ignored, and summary names no shoots.
    assert_eq!(numbers(&ok(&mut s, "scenes", &[("shoot", "2")]), "number"), ["1", "2"]);
    assert!(!ok(&mut s, "summary", &[]).contains("\"shoots\""));

    // Shoot 2, as New Shoot makes it: a section, a day named after it, 2B picked up.
    ok(&mut s, "update_shot", &[("shot", "2A"), ("shot_done", "true")]);
    ok(&mut s, "new_shoot", &[("date", "2026-10-06"), ("name", "Shoot 2"), ("pickups", "2")]);
    ok(&mut s, "add_scene", &[("number", "3"), ("section", "Shoot 2 · October 6")]);
    ok(&mut s, "add_shot", &[("scene", "3")]);

    assert!(ok(&mut s, "summary", &[]).contains(r#""shoots":["Shoot 1","Shoot 2"]"#));
    assert_eq!(numbers(&ok(&mut s, "scenes", &[("shoot", "Shoot 1")]), "number"), ["1", "2"]);
    assert_eq!(numbers(&ok(&mut s, "scenes", &[("shoot", "2")]), "number"), ["2", "3"], "a pickup scene is in the shoot that picks it up");
    assert_eq!(numbers(&ok(&mut s, "shots", &[("shoot", "shoot-2")]), "number"), ["2B", "3A"], "only the pickup's shots on Shoot 2's day");
    assert_eq!(numbers(&ok(&mut s, "shots", &[("shoot", "2"), ("scene", "2")]), "number"), ["2B"]);
    assert_eq!(numbers(&ok(&mut s, "shots", &[]), "number").len(), 4, "no shoot, every shot");

    let day1 = ok(&mut s, "schedule", &[("shoot", "1")]);
    assert!(day1.contains(r#""name":"Shoot 1""#) && !day1.contains(r#""name":"Shoot 2""#), "{day1}");
    let day2 = ok(&mut s, "schedule", &[("shoot", "Shoot 2")]);
    assert!(day2.contains(r#""name":"Shoot 2""#) && !day2.contains(r#""name":"Shoot 1""#), "{day2}");
    assert!(day2.contains(r#""waiting":[{"scene":"3""#), "scene 3's shot waits for a day in Shoot 2: {day2}");

    assert_eq!(numbers(&ok(&mut s, "locations", &[("shoot", "1")]), "name"), ["Kitchen"]);
    assert!(numbers(&ok(&mut s, "locations", &[("shoot", "2")]), "name").is_empty());

    let refused = no(&mut s, "scenes", &[("shoot", "Malibu")]);
    assert_eq!(refused, "No shoot called Malibu. This project's shoots: Shoot 1, Shoot 2.");
}

#[test]
fn a_shoot_named_its_own_way_counts_when_a_section_and_a_day_carry_it() {
    let (_x, mut s) = opened("shootnamed");
    ok(&mut s, "add_section", &[("title", "Shoot 1")]);
    ok(&mut s, "add_scene", &[("number", "1"), ("section", "Shoot 1")]);
    ok(&mut s, "add_shot", &[("scene", "1")]);
    ok(&mut s, "add_day", &[("date", "2026-07-09"), ("name", "Shoot 1")]);
    ok(&mut s, "schedule_shot", &[("shots", "1A"), ("day", "Day 1")]);
    ok(&mut s, "new_shoot", &[("date", "2026-10-06"), ("name", "Malibu Pickup")]);
    // A day called Pickups with no section is not a shoot.
    ok(&mut s, "add_day", &[("date", "2026-10-07"), ("name", "Pickups")]);
    assert!(ok(&mut s, "summary", &[]).contains(r#""shoots":["Shoot 1","Malibu Pickup"]"#));
    assert!(ok(&mut s, "schedule", &[("shoot", "malibu pickup")]).contains(r#""name":"Malibu Pickup""#));
}

/// Piece D: once the film's scenes and days name their shoot and the card
/// lists the shoots, `shoot` follows those fields (Studio's picker's rule),
/// not the section headings. A scene moved to Shoot 2 is Shoot 2's even
/// though its section still says Shoot 1.
#[test]
fn shoot_fields_win_over_sections_once_the_film_has_them() {
    const S1: &str = "b211a308026286ea6fba6436ae9b4891";
    const S2: &str = "4acab7b3b555897c7c58dce7762aca55";
    let (_x, mut s) = opened("shootfields");
    ok(&mut s, "add_section", &[("title", "Shoot 1 — July 9")]);
    ok(&mut s, "add_section", &[("title", "Shoot 2 - Style Server")]);
    for n in ["1", "2"] {
        ok(&mut s, "add_scene", &[("number", n), ("section", "Shoot 1 — July 9")]);
        ok(&mut s, "add_shot", &[("scene", n)]);
    }
    ok(&mut s, "add_scene", &[("number", "3"), ("section", "Shoot 2 - Style Server")]);
    ok(&mut s, "add_shot", &[("scene", "3")]);
    ok(&mut s, "add_day", &[("date", "2026-07-09")]);
    ok(&mut s, "add_day", &[("date", "2026-10-06")]);
    ok(&mut s, "schedule_shot", &[("shots", "1A, 2A"), ("day", "Day 1")]);
    ok(&mut s, "schedule_shot", &[("shots", "3A"), ("day", "Day 2")]);

    // No fields yet: the section rule.
    assert_eq!(numbers(&ok(&mut s, "scenes", &[("shoot", "2")]), "number"), ["3"]);

    {
        let doc = s.films_mut().doc_mut().unwrap();
        doc.set_card(shotlister_engine::card::Card::read(&format!(
            r#"{{"facts":{{}},"shoots":[{{"id":"{S1}","label":"Shoot 1","kind":"Shoot 1","n":1,"start":"2026-07-09","state":"Wrapped"}},{{"id":"{S2}","label":"Style Server","kind":"Shoot 2","n":2,"start":"2026-10-06","end":"2026-10-07","state":"Next"}}]}}"#
        )));
        let plan = doc.shoots_from_sections();
        assert!(doc.apply_shoot_plan(&plan) > 0);
        let two = doc.scenes_in_order()[1];
        assert_eq!(doc.move_scenes_to_shoot(&[two], S2), 1);
        // Its shot left Shoot 1's day for Unscheduled.
        assert!(doc.days_of_scene(two).is_empty());
    }

    // Fields now: scene 2 is Shoot 2's although its section says Shoot 1.
    assert!(ok(&mut s, "summary", &[]).contains(r#""shoots":["Shoot 1","Shoot 2"]"#));
    assert_eq!(numbers(&ok(&mut s, "scenes", &[("shoot", "1")]), "number"), ["1"]);
    assert_eq!(numbers(&ok(&mut s, "scenes", &[("shoot", "Shoot 2")]), "number"), ["2", "3"]);
    assert_eq!(numbers(&ok(&mut s, "scenes", &[("shoot", "style server")]), "number"), ["2", "3"], "its own name finds it too");
    assert_eq!(numbers(&ok(&mut s, "shots", &[("shoot", "shoot-2")]), "number"), ["2A", "3A"]);
    let sched = ok(&mut s, "schedule", &[("shoot", "2")]);
    assert!(sched.contains("2026-10-06") && !sched.contains("2026-07-09"), "{sched}");
    assert_eq!(no(&mut s, "scenes", &[("shoot", "Malibu")]), "No shoot called Malibu. This project's shoots: Shoot 1, Shoot 2.");
}
