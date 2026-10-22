//! A day whose every shot is in an archived scene is shot out and put away.

use shotlister_engine::{DeviceId, Doc};

#[test]
fn a_day_is_wrapped_once_all_its_scenes_are_archived() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Let's Bake");
    let one = d.create_scene("1");
    let two = d.create_scene("2");
    d.add_shot_to_scene(one);
    d.add_shot_to_scene(two);
    let day1 = d.create_day();
    let day2 = d.create_day();
    let empty = d.create_day();
    d.schedule_scene(one, day1);
    d.schedule_scene(two, day2);

    assert!(!d.day_wrapped(day1), "its scene is still live");

    d.archive_scene(one, true);
    assert!(d.day_wrapped(day1), "every shot on it is in an archived scene");
    assert!(!d.day_wrapped(day2), "Day 2 still has a live scene");
    assert!(!d.day_wrapped(empty), "a day with nothing on it is new, not wrapped");

    d.archive_scene(one, false);
    assert!(!d.day_wrapped(day1), "bringing the scene back brings the day back");
}
