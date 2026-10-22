//! The schedule, from a chat: days, and what is shot on each.

mod common;
use common::*;

/// Three scenes with shots, none scheduled.
fn film(name: &str) -> (Scratch, Open) {
    let (scratch, mut s) = opened(name);
    for scene in ["1", "2", "3"] {
        ok(&mut s, "add_scene", &[("number", scene)]);
        ok(&mut s, "add_shot", &[("scene", scene)]);
        ok(&mut s, "add_shot", &[("scene", scene)]);
    }
    ok(&mut s, "add_scene", &[("number", "4")]);
    (scratch, s)
}

#[test]
fn days_are_made_named_dated_and_moved() {
    let (_x, mut s) = film("days");
    assert!(ok(&mut s, "add_day", &[("date", "2026-10-03")]).contains("Day 1 (2026-10-03)"));
    let said = ok(&mut s, "add_day", &[("name", "Pickups"), ("position", "1")]);
    assert!(said.contains("Day 1 (Pickups)"), "{said}");
    assert!(no(&mut s, "add_day", &[("date", "Oct 3")]).contains("YYYY-MM-DD"));

    // The dated day is Day 2 now; move it back to the front.
    let said = ok(&mut s, "update_day", &[("day", "2026-10-03"), ("position", "1")]);
    assert!(said.contains("Day 1 (2026-10-03)"), "{said}");
    ok(&mut s, "update_day", &[("day", "Pickups"), ("date", "2026-10-01")]);
    let said = ok(&mut s, "order_days", &[("sort", "date")]);
    assert!(said.starts_with("The days: Day 1 (2026-10-01, Pickups); Day 2 (2026-10-03)"), "{said}");
    ok(&mut s, "update_day", &[("day", "1"), ("name", "")]);
    assert!(ok(&mut s, "schedule", &[]).contains(r#""name":"""#));
    assert!(no(&mut s, "update_day", &[("day", "Day 9"), ("name", "x")]).contains("The days are Day 1"));
}

#[test]
fn scenes_go_on_a_day_in_order_and_come_off() {
    let (_x, mut s) = film("scenes");
    ok(&mut s, "add_day", &[]);
    ok(&mut s, "add_day", &[]);
    let said = ok(&mut s, "schedule_scene", &[("scenes", "3, 1"), ("day", "Day 1")]);
    assert_eq!(said, "Day 1: scenes 3, 1.");
    let said = ok(&mut s, "schedule_scene", &[("scenes", "2"), ("day", "1"), ("before", "1")]);
    assert_eq!(said, "Day 1: scenes 3, 2, 1.");
    // Moving within the day is the same call.
    assert_eq!(ok(&mut s, "schedule_scene", &[("scenes", "1"), ("day", "1"), ("before", "3")]), "Day 1: scenes 1, 3, 2.");

    let refused = no(&mut s, "schedule_scene", &[("scenes", "4"), ("day", "1")]);
    assert!(refused.contains("has no shots"), "{refused}");

    let undone = ok(&mut s, "undo", &[]);
    assert!(undone.contains("Schedule scenes"), "one undo per call: {undone}");

    ok(&mut s, "schedule_scene", &[("scenes", "2"), ("day", "")]);
    let schedule = ok(&mut s, "schedule", &[]);
    let parsed = json::parse(&schedule).unwrap();
    let waiting = parsed.get("waiting").unwrap().as_array().unwrap();
    assert_eq!(waiting.len(), 1, "{schedule}");
    assert!(schedule.contains(r#""run":["3A","3B","1A","1B"]"#), "{schedule}");
}

#[test]
fn a_scene_splits_across_days_by_its_shots() {
    let (_x, mut s) = film("split");
    ok(&mut s, "add_day", &[]);
    ok(&mut s, "add_day", &[]);
    ok(&mut s, "schedule_scene", &[("scenes", "1"), ("day", "1")]);
    let said = ok(&mut s, "schedule_shot", &[("shots", "1B"), ("day", "2")]);
    assert_eq!(said, "Day 2 runs: 1B.");
    let schedule = ok(&mut s, "schedule", &[]);
    assert!(schedule.contains(r#""also_on":["Day 2"]"#), "{schedule}");

    ok(&mut s, "schedule_shot", &[("shots", "2A"), ("day", "2")]);
    let said = ok(&mut s, "schedule_shot", &[("shots", "2A"), ("day", "2"), ("position", "1")]);
    assert_eq!(said, "Day 2 runs: 2A, 1B.");

    // Only the part on Day 2 moves when `from` says so.
    ok(&mut s, "schedule_scene", &[("scenes", "1"), ("day", "1"), ("from", "2")]);
    assert!(ok(&mut s, "schedule", &[]).contains(r#""run":["2A"]"#));

    ok(&mut s, "schedule_shot", &[("shots", "2A"), ("day", "")]);
}

#[test]
fn a_day_with_shots_is_not_removed_without_asking() {
    let (_x, mut s) = film("delete");
    ok(&mut s, "add_day", &[]);
    ok(&mut s, "add_day", &[("name", "Spare")]);
    ok(&mut s, "schedule_scene", &[("scenes", "1"), ("day", "1")]);
    let refused = no(&mut s, "delete_day", &[("day", "1")]);
    assert!(refused.contains("has 2 shots on it"), "{refused}");
    assert_eq!(ok(&mut s, "delete_day", &[("day", "Spare")]), "Removed Day 2 (Spare).");
    let said = ok(&mut s, "delete_day", &[("day", "1"), ("even_with_shots", "true")]);
    assert!(said.contains("its 2 shots are waiting"), "{said}");
    assert!(ok(&mut s, "schedule", &[]).contains(r#""days":[]"#));
}

// ------------------------------------------------------------- a new shoot
// SL-1402: Projects Console's New Shoot, through the hub's console door.

/// Shoot 1 is over: Day 1 on 2026-07-09 ran scenes 1 and 2, and 1A was got.
fn shot_once(name: &str) -> (Scratch, Open) {
    let (scratch, mut s) = film(name);
    ok(&mut s, "add_day", &[("date", "2026-07-09"), ("name", "Shoot 1")]);
    ok(&mut s, "schedule_scene", &[("scenes", "1, 2"), ("day", "1")]);
    ok(&mut s, "update_shot", &[("shot", "1A"), ("shot_done", "true")]);
    (scratch, s)
}

fn parsed(said: &str) -> Json {
    json::parse(said).unwrap_or_else(|| panic!("not JSON: {said}"))
}

fn steps(said: &Json) -> Vec<String> {
    said.get("steps").unwrap().as_array().unwrap().iter().map(|s| s.as_str().unwrap().to_string()).collect()
}

fn count(s: &mut Open, tool: &str) -> usize {
    let said = ok(s, tool, &[]);
    match parsed(&said) {
        Json::Array(all) => all.len(),
        other => other.get("days").and_then(|d| d.as_array()).map(|d| d.len()).unwrap_or(0),
    }
}

#[test]
fn a_new_shoot_previews_without_writing_anything() {
    let (_x, mut s) = shot_once("shoot-preview");
    let before = ok(&mut s, "schedule", &[]);
    let said = parsed(&ok(
        &mut s,
        "new_shoot",
        &[("date", "2026-11-03"), ("name", "Shoot 3"), ("pickups", "1"), ("preview", "true")],
    ));
    assert_eq!(
        steps(&said),
        vec![
            "Save version \u{201c}Before Shoot 3 setup\u{201d}.",
            "Add section \u{201c}Shoot 3 \u{00b7} November 3\u{201d}.",
            "Add Day 2: 2026-11-03, Shoot 3.",
            "Put scene 1 on Day 2: 1B. 1A is marked Shot and stays where it was got.",
        ]
    );
    assert_eq!(said.get("preview"), Some(&Json::Bool(true)));
    assert_eq!(ok(&mut s, "schedule", &[]), before, "a preview changes nothing");
    assert_eq!(count(&mut s, "sections"), 0);
    assert_eq!(count(&mut s, "versions"), 0);
}

#[test]
fn a_new_shoot_saves_a_version_then_adds_its_section_day_and_pickups() {
    let (_x, mut s) = shot_once("shoot-make");
    let said = parsed(&ok(&mut s, "new_shoot", &[("date", "2026-11-03"), ("name", "Shoot 3"), ("pickups", "1")]));
    assert_eq!(
        steps(&said),
        vec![
            "Saved version \u{201c}Before Shoot 3 setup\u{201d}.",
            "Added section \u{201c}Shoot 3 \u{00b7} November 3\u{201d}.",
            "Day 2 is 2026-11-03, Shoot 3.",
            "Scene 1 is on Day 2: 1B. 1A is marked Shot and stayed where it was got.",
        ]
    );
    assert_eq!(said.get("preview"), Some(&Json::Bool(false)));
    let schedule = ok(&mut s, "schedule", &[]);
    assert!(schedule.contains(r#""day":"Day 2","date":"2026-11-03","name":"Shoot 3""#), "{schedule}");
    assert!(schedule.contains(r#""run":["1A","2A","2B"]"#), "Shoot 1 keeps what it got: {schedule}");
    assert!(schedule.contains(r#""run":["1B"]"#), "{schedule}");
    assert!(ok(&mut s, "sections", &[]).contains("Shoot 3 \u{00b7} November 3"));
    assert!(ok(&mut s, "versions", &[]).contains("Before Shoot 3 setup"));

    // Pressed again, it finds everything there and saves nothing.
    let again = parsed(&ok(&mut s, "new_shoot", &[("date", "2026-11-03"), ("name", "shoot 3"), ("pickups", "1")]));
    assert_eq!(again.get("changes"), Some(&Json::Bool(false)));
    assert_eq!(again.get("version"), Some(&Json::Null));
    assert_eq!(steps(&again)[0], "Nothing to do: the section, the day and the pickups are already there.");
    assert_eq!(count(&mut s, "versions"), 1);
    assert_eq!(count(&mut s, "sections"), 1);
    assert_eq!(count(&mut s, "schedule"), 2);

    // Undo takes the shoot back in one step and leaves the version.
    assert!(ok(&mut s, "undo", &[]).contains("New Shoot"));
    assert_eq!(count(&mut s, "schedule"), 1);
    assert_eq!(count(&mut s, "versions"), 1);
}

#[test]
fn a_new_shoot_uses_the_section_already_there_whatever_its_dash() {
    let (_x, mut s) = shot_once("shoot-reuse");
    ok(&mut s, "add_section", &[("title", "Shoot 2 \u{2013} October 6")]);
    ok(&mut s, "add_section", &[("title", "shoot 2 - october  6")]);
    let said = parsed(&ok(&mut s, "new_shoot", &[("date", "2026-10-06"), ("name", "Shoot 2")]));
    assert_eq!(
        steps(&said)[1],
        "Section \u{201c}Shoot 2 \u{2013} October 6\u{201d} is already there. 2 sections have that title; this is the first."
    );
    assert_eq!(count(&mut s, "sections"), 2, "never a third");
    let section = said.get("section").unwrap();
    assert_eq!(section.get("new"), Some(&Json::Bool(false)));
    // A section named outright is matched the same way.
    let said = parsed(&ok(
        &mut s,
        "new_shoot",
        &[("date", "2026-10-06"), ("name", "Shoot 2"), ("section", "SHOOT 2 \u{2014} OCTOBER 6"), ("preview", "true")],
    ));
    assert_eq!(said.get("changes"), Some(&Json::Bool(false)));
}

#[test]
fn a_new_shoot_refuses_whole_and_changes_nothing() {
    let (_x, mut s) = shot_once("shoot-refuse");
    let before = ok(&mut s, "schedule", &[]);
    let cases: &[(&[(&str, &str)], &str)] = &[
        (&[("date", "2026-11-03"), ("name", "Shoot 3"), ("pickups", "1, 9")], "There is no scene 9"),
        (&[("date", "2026-11-03"), ("name", "Shoot 3"), ("pickups", "4")], "Scene 4 has no shots"),
        (&[("date", "Nov 3"), ("name", "Shoot 3")], "YYYY-MM-DD"),
        (&[("date", "2026-13-03"), ("name", "Shoot 3")], "is not a date"),
        (&[("date", "2026-11-03")], "Say the shoot's name"),
        (&[("name", "Shoot 3")], "Say the shoot's date"),
    ];
    for (asked, why) in cases {
        let refused = no(&mut s, "new_shoot", asked);
        assert!(refused.contains(why) && refused.ends_with("Nothing was changed."), "{refused}");
    }
    ok(&mut s, "update_shot", &[("shot", "2A"), ("shot_done", "true")]);
    ok(&mut s, "update_shot", &[("shot", "2B"), ("shot_done", "true")]);
    let refused = no(&mut s, "new_shoot", &[("date", "2026-11-03"), ("name", "Shoot 3"), ("pickups", "2")]);
    assert!(refused.contains("Every shot in scene 2 is marked Shot"), "{refused}");
    assert_eq!(ok(&mut s, "schedule", &[]), before);
    assert_eq!(count(&mut s, "versions"), 0);
    assert_eq!(count(&mut s, "sections"), 0);
}

#[test]
fn a_new_shoot_dated_before_a_later_day_says_so() {
    let (_x, mut s) = shot_once("shoot-order");
    ok(&mut s, "add_day", &[("date", "2026-12-01"), ("name", "Shoot 3")]);
    let said = parsed(&ok(&mut s, "new_shoot", &[("date", "2026-11-03"), ("name", "Shoot 2"), ("preview", "yes")]));
    assert!(
        steps(&said).contains(&"Day 2 is dated later (2026-12-01) but runs before it. Sort the days by date in Shotlister to put them in order.".to_string()),
        "{said:?}"
    );
}

#[test]
fn a_day_is_put_in_shooting_order_in_one_call() {
    let (_x, mut s) = film("orderday");
    ok(&mut s, "add_day", &[]);
    ok(&mut s, "add_day", &[]);
    ok(&mut s, "schedule_scene", &[("scenes", "1, 2"), ("day", "1")]);
    ok(&mut s, "schedule_scene", &[("scenes", "3"), ("day", "2")]);
    // Named shots lead, in the order given; 3A comes over from Day 2; the
    // rest of Day 1 follows as it was.
    let said = ok(&mut s, "order_day", &[("day", "1"), ("shots", "2B, 3A, 1B")]);
    assert_eq!(said, "Day 1 runs: 2B, 3A, 1B, 1A, 2A.");
    assert!(ok(&mut s, "schedule", &[]).contains(r#""run":["3B"]"#));
    let undone = ok(&mut s, "undo", &[]);
    assert!(undone.contains("Order day"), "one undo per call: {undone}");
    assert!(no(&mut s, "order_day", &[("day", "1"), ("shots", "9Z")]).contains("no shot 9Z"));
}

/// **Days written once, belonging to a shoot** (stage 5 step 4, piece E):
/// New Shoot with the shoot's id makes its day the shoot's own, following
/// its dates, and adds no section (sections are his own).
#[test]
fn a_new_shoot_with_its_id_makes_a_day_that_belongs_to_it() {
    let (_x, mut s) = shot_once("shoot-owned");
    let id = "aaaaaaaabbbbbbbbccccccccdddddddd";
    let said = parsed(&ok(&mut s, "new_shoot", &[("date", "2026-11-03"), ("name", "Shoot 3"), ("shoot", id)]));
    assert_eq!(
        steps(&said),
        vec![
            "Saved version \u{201c}Before Shoot 3 setup\u{201d}.",
            "Day 2 is 2026-11-03, Shoot 3.",
            "It belongs to Shoot 3 and follows its dates.",
        ]
    );
    assert_eq!(count(&mut s, "sections"), 0, "no section: sections are his own");
    let again = parsed(&ok(&mut s, "new_shoot", &[("date", "2026-11-04"), ("name", "Shoot 3"), ("shoot", id)]));
    assert_eq!(again.get("changes"), Some(&Json::Bool(false)), "the shoot's day is found by the shoot, whatever its date");
    assert!(no(&mut s, "new_shoot", &[("date", "2026-11-03"), ("name", "Shoot 3"), ("shoot", "nope")]).contains("not a shoot's id"));
}
