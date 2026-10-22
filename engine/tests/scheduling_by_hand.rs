//! What a drag on the Schedule does when it lets go — `put_scenes_on_day`
//! and `put_shot_on_day`. His report, 2026-09-29: dragging scenes into the
//! schedule and reordering them "just get stuck, won't come over". The Mac's
//! half is in `studio/Sources/ScheduleHands.swift`; this is the engine's.

use shotlister_engine::doc::f;
use shotlister_engine::{DeviceId, Doc, Id};

fn project() -> Doc {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    d
}

/// A scene with `shots` shots, none of them on a day.
fn scene(d: &mut Doc, number: &str, shots: usize) -> Id {
    let s = d.create_scene(number);
    for _ in 0..shots {
        d.add_shot_to_scene(s);
    }
    s
}

/// The scenes on a day, in the order the day runs them — what the strips say.
fn strips(d: &Doc, day: Id) -> Vec<Id> {
    let mut seen = Vec::new();
    for p in d.placements_on_day(day) {
        let s = d.get(p).and_then(|r| r.ref_id(f::SCENE)).unwrap();
        if !seen.contains(&s) {
            seen.push(s);
        }
    }
    seen
}

#[test]
fn a_scene_from_the_list_lands_where_it_was_let_go() {
    let mut d = project();
    let day = d.create_day();
    let (a, b, c) = (scene(&mut d, "1", 2), scene(&mut d, "2", 1), scene(&mut d, "3", 3));
    d.put_scenes_on_day(&[a], None, Some(day), None);
    d.put_scenes_on_day(&[b], None, Some(day), None);
    assert_eq!(strips(&d, day), vec![a, b]);

    // Between the two, not at the end.
    d.put_scenes_on_day(&[c], None, Some(day), Some(b));
    assert_eq!(strips(&d, day), vec![a, c, b]);
    assert_eq!(d.placements_on_day(day).len(), 6);
}

#[test]
fn a_drop_is_one_undo_however_much_travelled() {
    let mut d = project();
    let day = d.create_day();
    let a = scene(&mut d, "1", 1);
    let (b, c) = (scene(&mut d, "2", 4), scene(&mut d, "3", 2));
    d.put_scenes_on_day(&[a], None, Some(day), None);
    let steps = d.undo_labels().len();

    // Two scenes, six shots, put ahead of the one already there.
    d.put_scenes_on_day(&[b, c], None, Some(day), Some(a));
    assert_eq!(strips(&d, day), vec![b, c, a]);
    assert_eq!(d.undo_labels().len(), steps + 1);

    d.undo();
    assert_eq!(strips(&d, day), vec![a]);
}

#[test]
fn a_strip_reorders_within_its_day() {
    let mut d = project();
    let day = d.create_day();
    let (a, b, c) = (scene(&mut d, "1", 1), scene(&mut d, "2", 2), scene(&mut d, "3", 1));
    d.put_scenes_on_day(&[a, b, c], None, Some(day), None);
    assert_eq!(strips(&d, day), vec![a, b, c]);

    d.put_scenes_on_day(&[c], Some(day), Some(day), Some(a));
    assert_eq!(strips(&d, day), vec![c, a, b]);
    d.put_scenes_on_day(&[c], Some(day), Some(day), None);
    assert_eq!(strips(&d, day), vec![a, b, c]);
    // Let go on itself: nothing moves.
    d.put_scenes_on_day(&[b], Some(day), Some(day), Some(b));
    assert_eq!(strips(&d, day), vec![a, b, c]);
}

#[test]
fn a_strip_dragged_to_another_day_moves_only_the_half_that_was_dragged() {
    let mut d = project();
    let (monday, tuesday) = (d.create_day(), d.create_day());
    let a = scene(&mut d, "1", 1);
    let split = d.create_scene("2");
    let (_, first) = d.add_shot_to_scene(split);
    let (_, second) = d.add_shot_to_scene(split);
    d.put_scenes_on_day(&[a], None, Some(tuesday), None);
    d.schedule(first, monday);
    d.schedule(second, tuesday);

    // Monday's half goes onto Tuesday, ahead of scene 1; the half already
    // on Tuesday joins it rather than being left behind.
    d.put_scenes_on_day(&[split], Some(monday), Some(tuesday), Some(a));
    assert!(d.placements_on_day(monday).is_empty());
    assert_eq!(strips(&d, tuesday), vec![split, a]);
    assert_eq!(d.placements_on_day(tuesday).len(), 3);
}

#[test]
fn a_strip_from_one_day_leaves_its_other_day_alone() {
    let mut d = project();
    let (monday, tuesday, wednesday) = (d.create_day(), d.create_day(), d.create_day());
    let split = d.create_scene("2");
    let (_, first) = d.add_shot_to_scene(split);
    let (_, second) = d.add_shot_to_scene(split);
    d.schedule(first, monday);
    d.schedule(second, tuesday);

    d.put_scenes_on_day(&[split], Some(monday), Some(wednesday), None);
    assert!(d.placements_on_day(monday).is_empty());
    assert_eq!(d.placements_on_day(tuesday), vec![second]);
    assert_eq!(d.placements_on_day(wednesday), vec![first]);
}

#[test]
fn a_strip_dropped_on_the_scene_list_comes_off_that_day_only() {
    let mut d = project();
    let (monday, tuesday) = (d.create_day(), d.create_day());
    let split = d.create_scene("2");
    let (_, first) = d.add_shot_to_scene(split);
    let (_, second) = d.add_shot_to_scene(split);
    d.schedule(first, monday);
    d.schedule(second, tuesday);

    d.put_scenes_on_day(&[split], Some(monday), None, None);
    assert!(d.placements_on_day(monday).is_empty());
    assert_eq!(d.placements_on_day(tuesday), vec![second]);

    // With no day named, the whole scene comes off.
    d.put_scenes_on_day(&[split], None, None, None);
    assert!(d.placements_on_day(tuesday).is_empty());
}

#[test]
fn one_shot_stands_where_it_was_let_go_or_joins_its_scene() {
    let mut d = project();
    let (monday, tuesday) = (d.create_day(), d.create_day());
    let (a, b) = (scene(&mut d, "1", 1), scene(&mut d, "2", 1));
    let split = d.create_scene("3");
    let (_, first) = d.add_shot_to_scene(split);
    let (_, second) = d.add_shot_to_scene(split);
    d.put_scenes_on_day(&[split], None, Some(monday), None);
    d.put_scenes_on_day(&[a, b], None, Some(tuesday), None);

    // Scene 3 has no strip on Tuesday: its shot stands between 1 and 2.
    d.put_shot_on_day(second, tuesday, Some(b));
    assert_eq!(strips(&d, tuesday), vec![a, split, b]);
    assert_eq!(d.placements_on_day(monday), vec![first]);

    // Now it has one, so the other shot joins it wherever it was let go.
    d.put_shot_on_day(first, tuesday, None);
    assert_eq!(strips(&d, tuesday), vec![a, split, b]);
    assert!(d.placements_on_day(monday).is_empty());
}

/// His report, 2026-10-17, on Call Her Back: scene 16 read "Day 3 · 3 left",
/// and dragging it out of the scene list onto another day took its two Day 3
/// shots along too. From the list, only what is still on no day travels.
#[test]
fn a_part_scheduled_scene_from_the_list_brings_only_its_remainder() {
    let mut d = project();
    let (day2, day3) = (d.create_day(), d.create_day());
    let other = scene(&mut d, "15", 1);
    let s = d.create_scene("16");
    let shots: Vec<Id> = (0..5).map(|_| d.add_shot_to_scene(s).1).collect();
    d.put_scenes_on_day(&[other], None, Some(day2), None);
    d.schedule(shots[1], day3);
    d.schedule(shots[2], day3);
    let steps = d.undo_labels().len();

    d.put_scenes_on_day(&[s], None, Some(day2), Some(other));
    assert_eq!(d.placements_on_day(day3), vec![shots[1], shots[2]]);
    assert_eq!(d.placements_on_day(day2).len(), 4);
    assert_eq!(strips(&d, day2), vec![s, other]);
    assert_eq!(d.undo_labels().len(), steps + 1);

    // One ⌘Z puts all three back on no day.
    d.undo();
    assert_eq!(strips(&d, day2), vec![other]);
    assert_eq!(d.placements_on_day(day3), vec![shots[1], shots[2]]);
}

#[test]
fn a_remainder_let_go_on_its_own_strip_joins_it_there() {
    let mut d = project();
    let day = d.create_day();
    let (a, b) = (scene(&mut d, "1", 1), scene(&mut d, "3", 1));
    let s = d.create_scene("2");
    let (_, first) = d.add_shot_to_scene(s);
    let (_, _second) = d.add_shot_to_scene(s);
    d.put_scenes_on_day(&[a], None, Some(day), None);
    d.schedule(first, day);
    d.put_scenes_on_day(&[b], None, Some(day), None);
    assert_eq!(strips(&d, day), vec![a, s, b]);

    // Ahead of its own strip: the strip stays put and the shot joins it.
    d.put_scenes_on_day(&[s], None, Some(day), Some(s));
    assert_eq!(d.placements_on_day(day).len(), 4);
    assert_eq!(strips(&d, day), vec![a, s, b]);
    let order: Vec<Id> = d.placements_on_day(day);
    let scene_of = |p: &Id| d.get(*p).and_then(|r| r.ref_id(f::SCENE)).unwrap();
    assert_eq!(order.iter().map(scene_of).collect::<Vec<_>>(), vec![a, s, s, b]);
}

#[test]
fn a_whole_unscheduled_scene_still_comes_whole_and_a_settled_one_moves() {
    let mut d = project();
    let (monday, tuesday) = (d.create_day(), d.create_day());
    let s = scene(&mut d, "4", 3);
    d.put_scenes_on_day(&[s], None, Some(monday), None);
    assert_eq!(d.placements_on_day(monday).len(), 3);

    // Nothing left to place: from the list it moves whole, as before.
    d.put_scenes_on_day(&[s], None, Some(tuesday), None);
    assert!(d.placements_on_day(monday).is_empty());
    assert_eq!(d.placements_on_day(tuesday).len(), 3);
}

#[test]
fn shots_picked_from_a_remainder_land_together_in_one_step() {
    let mut d = project();
    let (day2, day3) = (d.create_day(), d.create_day());
    let (a, b) = (scene(&mut d, "18", 1), scene(&mut d, "19", 1));
    let s = d.create_scene("16");
    let shots: Vec<Id> = (0..5).map(|_| d.add_shot_to_scene(s).1).collect();
    d.put_scenes_on_day(&[a, b], None, Some(day2), None);
    d.schedule(shots[1], day3);
    let steps = d.undo_labels().len();

    // Two of the remainder, between 18 and 19 on Day 2.
    d.put_shots_on_day(&[shots[0], shots[3]], day2, Some(b));
    assert_eq!(strips(&d, day2), vec![a, s, b]);
    assert_eq!(d.placements_on_day(day3), vec![shots[1]]);
    assert_eq!(d.undo_labels().len(), steps + 1);

    // One more joins the strip already there, wherever it was let go.
    d.put_shots_on_day(&[shots[4]], day2, None);
    assert_eq!(strips(&d, day2), vec![a, s, b]);
    assert_eq!(d.placements_on_day(day2).len(), 5);

    d.undo();
    d.undo();
    assert_eq!(strips(&d, day2), vec![a, b]);
}
