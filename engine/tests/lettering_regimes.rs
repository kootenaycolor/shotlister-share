//! Letters move during prep and stop once the shoot starts.

use shotlister_engine::doc::f;
use shotlister_engine::lettering::Regime;
use shotlister_engine::{DeviceId, Doc, Id};

fn project() -> (Doc, Id) {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let scene = d.create_scene("34");
    (d, scene)
}

fn numbers(d: &Doc, scene: Id) -> Vec<String> {
    d.placements_in_scene(scene)
        .iter()
        .filter_map(|p| d.display_number(*p))
        .collect()
}

// ---- which regime ------------------------------------------------------

#[test]
fn a_project_with_no_dated_day_is_still_in_prep() {
    let (mut d, _) = project();
    d.create_day();
    d.set_today(Some("2026-10-30"));

    // Nothing to lock against. Locking on a guess would be worse than waiting.
    assert_eq!(d.lettering_regime(), Regime::Prep);
}

#[test]
fn scheduling_alone_does_not_lock_anything() {
    let (mut d, scene) = project();
    let day = d.create_day();
    d.set(day, f::DATE, "2026-10-30");
    d.add_shot_to_scene(scene);
    d.schedule_scene(scene, day);
    d.set_today(Some("2026-10-24"));

    // All of planning and all of scheduling happen in prep.
    assert_eq!(d.lettering_regime(), Regime::Prep);
}

#[test]
fn the_lock_falls_on_the_morning_of_the_first_day() {
    let (mut d, _) = project();
    let day = d.create_day();
    d.set(day, f::DATE, "2026-10-30");

    d.set_today(Some("2026-10-29"));
    assert_eq!(d.lettering_regime(), Regime::Prep);

    d.set_today(Some("2026-10-30"));
    assert_eq!(d.lettering_regime(), Regime::Locked);

    d.set_today(Some("2026-11-04"));
    assert_eq!(d.lettering_regime(), Regime::Locked);
}

#[test]
fn the_earliest_dated_day_is_the_one_that_counts() {
    let (mut d, _) = project();
    let first = d.create_day();
    let second = d.create_day();
    // Days are in manual order; the dates need not agree with it.
    d.set(first, f::DATE, "2026-11-02");
    d.set(second, f::DATE, "2026-10-28");

    assert_eq!(d.first_shoot_date().as_deref(), Some("2026-10-28"));
    d.set_today(Some("2026-10-29"));
    assert!(d.letters_are_locked());
}

#[test]
fn not_knowing_the_date_keeps_everything_in_prep() {
    let (mut d, _) = project();
    let day = d.create_day();
    d.set(day, f::DATE, "2020-01-01");
    d.set_today(None);

    assert_eq!(d.lettering_regime(), Regime::Prep);
}

// ---- prep: letters follow ---------------------------------------------

#[test]
fn reordering_in_prep_renumbers_to_match() {
    let (mut d, scene) = project();
    let (_, a) = d.add_shot_to_scene(scene);
    let (_, b) = d.add_shot_to_scene(scene);
    let (_, c) = d.add_shot_to_scene(scene);
    assert_eq!(numbers(&d, scene), vec!["34A", "34B", "34C"]);

    // Pull the third shot to the front while still building the list.
    d.move_in_scene_to(c, 0);

    // Story order and letters agree, which is what you want while planning.
    assert_eq!(numbers(&d, scene), vec!["34A", "34B", "34C"]);
    assert_eq!(d.get(c).unwrap().text(f::LETTER), Some("A"));
    assert_eq!(d.get(a).unwrap().text(f::LETTER), Some("B"));
    assert_eq!(d.get(b).unwrap().text(f::LETTER), Some("C"));
}

#[test]
fn a_renumber_in_prep_is_one_thing_to_take_back() {
    let (mut d, scene) = project();
    d.add_shot_to_scene(scene);
    d.add_shot_to_scene(scene);
    let (_, c) = d.add_shot_to_scene(scene);
    d.clear_history();

    d.move_in_scene_to(c, 0);
    assert_eq!(d.undo_depth(), 1);

    d.undo();
    assert_eq!(numbers(&d, scene), vec!["34A", "34B", "34C"]);
    assert_eq!(d.get(c).unwrap().text(f::LETTER), Some("C"));
}

#[test]
fn only_the_letters_that_change_are_written() {
    let (mut d, scene) = project();
    for _ in 0..6 {
        d.add_shot_to_scene(scene);
    }
    let placements = d.placements_in_scene(scene);
    let before = d.changes().len();

    // Swapping the last two touches two letters, not six.
    d.move_in_scene_to(placements[5], 4);

    let written = d.changes().len() - before;
    assert!(written < 8, "wrote {written} changes for a two-letter swap");
    assert_eq!(numbers(&d, scene), vec!["34A", "34B", "34C", "34D", "34E", "34F"]);
}

// ---- locked: letters are names ----------------------------------------

#[test]
fn reordering_once_shooting_leaves_letters_alone() {
    let (mut d, scene) = project();
    let day = d.create_day();
    d.set(day, f::DATE, "2026-10-30");
    let (_, a) = d.add_shot_to_scene(scene);
    let (_, b) = d.add_shot_to_scene(scene);
    let (_, c) = d.add_shot_to_scene(scene);
    d.set_today(Some("2026-10-30"));

    d.move_in_scene_to(c, 0);

    // The order changed; the names did not, because somebody is reading them
    // off a printed page.
    assert_eq!(numbers(&d, scene), vec!["34C", "34A", "34B"]);
    assert_eq!(d.get(a).unwrap().text(f::LETTER), Some("A"));
    assert_eq!(d.get(b).unwrap().text(f::LETTER), Some("B"));
}

#[test]
fn reordering_once_shooting_still_costs_one_change() {
    let (mut d, scene) = project();
    let day = d.create_day();
    d.set(day, f::DATE, "2026-10-30");
    for _ in 0..20 {
        d.add_shot_to_scene(scene);
    }
    d.set_today(Some("2026-10-30"));
    let placements = d.placements_in_scene(scene);
    let before = d.changes().len();

    d.move_in_scene_to(placements[19], 0);

    // The property from §04 holds where it matters most — on the day.
    assert_eq!(d.changes().len() - before, 1);
}

#[test]
fn reflowing_by_hand_does_nothing_once_locked() {
    let (mut d, scene) = project();
    let day = d.create_day();
    d.set(day, f::DATE, "2026-10-30");
    let (_, a) = d.add_shot_to_scene(scene);
    let (_, b) = d.add_shot_to_scene(scene);
    d.set_today(Some("2026-10-30"));
    d.move_in_scene(b, None, Some(-1.0));

    assert_eq!(d.reflow_letters(scene), 0);
    assert_eq!(d.get(a).unwrap().text(f::LETTER), Some("A"));
}

#[test]
fn a_freed_letter_still_returns_while_in_prep() {
    // Prep reflows on reorder, but adding after a delete should still land on
    // the gap rather than skipping it.
    let (mut d, scene) = project();
    d.add_shot_to_scene(scene);
    let (_, b) = d.add_shot_to_scene(scene);
    d.add_shot_to_scene(scene);

    d.delete(b);
    let (_, fresh) = d.add_shot_to_scene(scene);

    assert_eq!(d.display_number(fresh).unwrap(), "34B");
}

// ---- deleting closes the gap in prep ------------------------------------

#[test]
fn deleting_a_shot_in_prep_closes_the_gap() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let scene = d.create_scene("34");
    let (_a, first) = d.add_shot_to_scene(scene);
    let (_b, second) = d.add_shot_to_scene(scene);
    let (_c, third) = d.add_shot_to_scene(scene);
    assert_eq!(numbers(&d, scene), vec!["34A", "34B", "34C"]);

    d.delete_placement(second);

    assert_eq!(
        numbers(&d, scene),
        vec!["34A", "34B"],
        "what was 34C is now 34B"
    );
    assert!(d.get(second).is_none());
    assert!(d.get(first).is_some() && d.get(third).is_some());
}

#[test]
fn a_shot_moved_out_in_prep_closes_the_letters_behind_it() {
    let (mut d, scene) = project();
    let elsewhere = d.create_scene("40");
    d.add_shot_to_scene(scene);
    let (_b, second) = d.add_shot_to_scene(scene);
    d.add_shot_to_scene(scene);

    d.move_placement_to_scene(second, elsewhere);

    assert_eq!(
        numbers(&d, scene),
        vec!["34A", "34B"],
        "in prep, what was 34C closes up into 34B"
    );
}

#[test]
fn a_shot_moved_out_once_locked_leaves_its_gap() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let day = d.create_day();
    d.set(day, f::DATE, "2026-09-12");
    d.set_today(Some("2026-09-12"));

    let scene = d.create_scene("34");
    let elsewhere = d.create_scene("40");
    d.add_shot_to_scene(scene);
    let (_b, second) = d.add_shot_to_scene(scene);
    d.add_shot_to_scene(scene);
    assert!(d.letters_are_locked());

    d.move_placement_to_scene(second, elsewhere);

    assert_eq!(
        numbers(&d, scene),
        vec!["34A", "34C"],
        "34C is on a callsheet somewhere and does not move because a shot left"
    );
}

#[test]
fn once_letters_are_locked_the_gap_stays_open() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let day = d.create_day();
    d.set(day, f::DATE, "2026-09-12");
    d.set_today(Some("2026-09-12"));

    let scene = d.create_scene("34");
    d.add_shot_to_scene(scene);
    let (_b, second) = d.add_shot_to_scene(scene);
    d.add_shot_to_scene(scene);
    assert!(d.letters_are_locked());

    d.delete_placement(second);

    assert_eq!(
        numbers(&d, scene),
        vec!["34A", "34C"],
        "34C is on a callsheet somewhere and does not move"
    );

    // And the freed letter comes back into play, as it always did.
    let (_new, added) = d.add_shot_to_scene(scene);
    assert_eq!(d.display_number(added).as_deref(), Some("34B"));
}

#[test]
fn deleting_a_shot_is_one_thing_to_take_back_however_many_letters_move() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let scene = d.create_scene("34");
    let (_a, first) = d.add_shot_to_scene(scene);
    d.add_shot_to_scene(scene);
    d.add_shot_to_scene(scene);
    d.add_shot_to_scene(scene);

    let depth = d.undo_depth();
    d.delete_placement(first);
    assert_eq!(d.undo_depth(), depth + 1, "not one step per renumbered shot");
    assert_eq!(numbers(&d, scene), vec!["34A", "34B", "34C"]);

    d.undo();
    assert_eq!(
        numbers(&d, scene),
        vec!["34A", "34B", "34C", "34D"],
        "everything comes back, letters included"
    );
}

#[test]
fn a_shot_that_also_lives_in_another_scene_survives_losing_this_one() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let here = d.create_scene("54");
    let there = d.create_scene("61");
    let (shot, in_54) = d.add_shot_to_scene(here);
    let also = d.place(shot, there);

    d.delete_placement(in_54);

    assert!(d.get(in_54).is_none(), "its place here is gone");
    assert!(d.get(shot).is_some(), "but the shot is not");
    assert!(d.get(also).is_some());
    assert_eq!(d.display_number(also).as_deref(), Some("61A"));
}

#[test]
fn a_shot_placed_nowhere_else_goes_with_its_placement() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let scene = d.create_scene("34");
    let (shot, only) = d.add_shot_to_scene(scene);

    d.delete_placement(only);

    assert!(
        d.get(shot).is_none(),
        "a shot that appears in no scene is not a shot anybody can find"
    );
}

#[test]
fn deleting_a_scene_takes_its_shots_but_not_the_ones_that_live_elsewhere_too() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let here = d.create_scene("54");
    let there = d.create_scene("61");
    let (kept_shot, _) = d.add_shot_to_scene(here);
    let elsewhere = d.place(kept_shot, there);
    let (lost_shot, _) = d.add_shot_to_scene(here);

    let taken = d.delete_scene(here);

    assert_eq!(taken, 2);
    assert!(d.get(here).is_none());
    assert!(d.get(lost_shot).is_none(), "it lived only here");
    assert!(d.get(kept_shot).is_some(), "it also lives in 61");
    assert_eq!(d.display_number(elsewhere).as_deref(), Some("61A"));
}

#[test]
fn deleting_a_scene_is_one_thing_to_take_back() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let scene = d.create_scene("34");
    d.add_shot_to_scene(scene);
    d.add_shot_to_scene(scene);
    d.add_shot_to_scene(scene);

    let depth = d.undo_depth();
    d.delete_scene(scene);
    assert_eq!(d.undo_depth(), depth + 1);

    d.undo();
    assert!(d.get(scene).is_some());
    assert_eq!(numbers(&d, scene), vec!["34A", "34B", "34C"]);
}
