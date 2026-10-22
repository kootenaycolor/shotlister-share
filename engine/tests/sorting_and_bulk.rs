//! Reading a list in a different order, and filling a board from a folder.

use shotlister_engine::doc::f;
use shotlister_engine::natural;
use shotlister_engine::sha256;
use shotlister_engine::{DeviceId, Doc, GroupBy, Id, MediaKind, Query, Value};

// ---- comparing the way people read ---------------------------------------

#[test]
fn numbers_inside_names_are_compared_as_numbers() {
    let mut lenses = vec![
        "100mm".to_string(),
        "27mm".to_string(),
        "37mm".to_string(),
        "9mm".to_string(),
    ];
    lenses.sort_by(|a, b| natural::compare(a, b));
    assert_eq!(lenses, vec!["9mm", "27mm", "37mm", "100mm"]);
}

#[test]
fn a_folder_reads_the_way_a_person_reads_it() {
    let files: Vec<String> = ["shot-10.png", "shot-2.png", "shot-1.png", "shot-21.png"]
        .iter()
        .map(|s| s.to_string())
        .collect();
    assert_eq!(
        natural::sorted(&files),
        vec!["shot-1.png", "shot-2.png", "shot-10.png", "shot-21.png"]
    );
}

#[test]
fn leading_zeros_do_not_change_what_a_number_is() {
    let files: Vec<String> = ["007.png", "10.png", "2.png"].iter().map(|s| s.to_string()).collect();
    assert_eq!(natural::sorted(&files), vec!["2.png", "007.png", "10.png"]);
}

#[test]
fn scene_numbers_with_letters_stay_where_they_belong() {
    let mut scenes: Vec<String> = ["34", "34A", "5", "100", "34B"]
        .iter()
        .map(|s| s.to_string())
        .collect();
    scenes.sort_by(|a, b| natural::compare(a, b));
    assert_eq!(scenes, vec!["5", "34", "34A", "34B", "100"]);
}

#[test]
fn two_different_strings_never_compare_equal() {
    use std::cmp::Ordering;
    assert_ne!(
        natural::compare("Wide", "wide"),
        Ordering::Equal,
        "ordering has to be total or a sort is unstable"
    );
    assert_eq!(natural::compare("wide", "wide"), Ordering::Equal);
}

#[test]
fn saying_the_same_thing_is_a_different_question_from_sorting_the_same() {
    // 034 and 34 are the same scene, but they cannot compare equal for
    // ordering, so matching asks its own question.
    assert!(natural::same("034", "34"));
    assert!(natural::same("Wide", "wide"));
    assert!(!natural::same("34", "35"));
    assert!(!natural::compare("034", "34").is_eq());
}

// ---- sorting a scene ------------------------------------------------------

fn a_scene() -> (Doc, Id, Vec<Id>) {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let scene = d.create_scene("34");
    let mut placements = Vec::new();
    for lens in ["100mm", "27mm", "37mm"] {
        let (shot, placement) = d.add_shot_to_scene(scene);
        // The lens belongs to the shot, not to its place in a scene.
        d.set(shot, f::LENS, lens);
        placements.push(placement);
    }
    (d, scene, placements)
}

fn read(d: &Doc, query: &Query) -> Vec<String> {
    d.run(query)
        .into_iter()
        .flat_map(|group| group.placements)
        .filter_map(|p| d.display_number(p))
        .collect()
}

#[test]
fn a_scene_can_be_read_in_a_columns_order() {
    let (d, _scene, _) = a_scene();

    let normal = Query::grouped_by(GroupBy::Scene);
    assert_eq!(read(&d, &normal), vec!["34A", "34B", "34C"]);

    let by_lens = normal.clone().sorted_by(f::LENS, false);
    assert_eq!(
        read(&d, &by_lens),
        vec!["34B", "34C", "34A"],
        "27mm, 37mm, 100mm — not 100, 27, 37"
    );

    let backwards = Query::grouped_by(GroupBy::Scene).sorted_by(f::LENS, true);
    assert_eq!(read(&d, &backwards), vec!["34A", "34C", "34B"]);
}

#[test]
fn sorting_is_a_way_of_looking_and_changes_nothing() {
    let (mut d, scene, placements) = a_scene();
    let before = d.changes().len();
    let steps = d.undo_depth();
    let letters: Vec<Option<String>> = placements.iter().map(|p| d.display_number(*p)).collect();

    let sorted = Query::grouped_by(GroupBy::Scene).sorted_by(f::LENS, false);
    let _ = d.run(&sorted);

    assert_eq!(d.changes().len(), before, "not one change was written");
    assert_eq!(d.undo_depth(), steps, "and nothing landed in undo");
    assert_eq!(
        placements.iter().map(|p| d.display_number(*p)).collect::<Vec<_>>(),
        letters,
        "no letter moved"
    );
    assert_eq!(
        d.placements_in_scene(scene),
        placements,
        "and the list is still in the order it is kept in"
    );
}

#[test]
fn an_empty_cell_sinks_whichever_way_the_column_points() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let scene = d.create_scene("34");
    let (first, _a) = d.add_shot_to_scene(scene);
    let (_b, _second) = d.add_shot_to_scene(scene); // no lens at all
    let (third, _c) = d.add_shot_to_scene(scene);
    d.set(first, f::LENS, "37mm");
    d.set(third, f::LENS, "27mm");

    let up = Query::grouped_by(GroupBy::Scene).sorted_by(f::LENS, false);
    assert_eq!(read(&d, &up), vec!["34C", "34A", "34B"]);

    let down = Query::grouped_by(GroupBy::Scene).sorted_by(f::LENS, true);
    assert_eq!(
        read(&d, &down),
        vec!["34A", "34C", "34B"],
        "the shot with no lens stays at the bottom rather than heading the list"
    );
}

#[test]
fn sorting_by_camera_sorts_by_what_the_camera_is_called() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let scene = d.create_scene("34");
    let a_cam = d.create_unit("A", "Alexa 35");
    let b_cam = d.create_unit("B", "Alexa 35");

    let (shot_one, _) = d.add_shot_to_scene(scene);
    let (shot_two, _) = d.add_shot_to_scene(scene);
    d.set(shot_one, f::UNIT, Value::Ref(b_cam));
    d.set(shot_two, f::UNIT, Value::Ref(a_cam));

    let by_camera = Query::grouped_by(GroupBy::Scene).sorted_by("camera", false);
    assert_eq!(read(&d, &by_camera), vec!["34B", "34A"]);
}

#[test]
fn sorting_by_image_gathers_the_shots_still_missing_one() {
    let (mut d, scene, placements) = a_scene();
    let media = d.add_media(sha256(b"a frame"), MediaKind::Image, 1920, 1080, 10, "a.png");
    d.attach_media(placements[2], media, "");

    let by_image = Query::grouped_by(GroupBy::Scene).sorted_by("image", false);
    let order = read(&d, &by_image);
    assert_eq!(order[0], "34C", "the one with a frame comes first");
    assert_eq!(d.placements_in_scene(scene).len(), 3);
}

#[test]
fn sorting_applies_inside_each_group_not_across_them() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let first = d.create_scene("34");
    let second = d.create_scene("35");
    let (in_34, _a) = d.add_shot_to_scene(first);
    let (in_35, _b) = d.add_shot_to_scene(second);
    d.set(in_34, f::LENS, "100mm");
    d.set(in_35, f::LENS, "27mm");

    let sorted = Query::grouped_by(GroupBy::Scene).sorted_by(f::LENS, false);
    let groups = d.run(&sorted);

    assert_eq!(groups.len(), 2);
    assert_eq!(groups[0].label, "Scene 34", "scene order is not what is being sorted");
    assert_eq!(groups[1].label, "Scene 35");
}

// ---- filling a board from a folder ---------------------------------------

#[test]
fn a_folder_lands_on_the_shots_in_the_order_they_are_being_read() {
    let (d, scene, placements) = a_scene();
    let files: Vec<String> = ["10.png", "2.png", "1.png"].iter().map(|s| s.to_string()).collect();

    let plan = d.plan_bulk_media(&files, &d.placements_in_scene(scene));

    assert_eq!(plan.pairings.len(), 3);
    assert_eq!(plan.pairings[0].filename, "1.png");
    assert_eq!(plan.pairings[0].placement, placements[0]);
    assert_eq!(plan.pairings[1].filename, "2.png");
    assert_eq!(plan.pairings[2].filename, "10.png");
    assert_eq!(plan.pairings[2].number, "34C");
    assert!(plan.spare_files.is_empty());
    assert_eq!(plan.shots_left_over, 0);
    assert!(
        !plan.needs_confirming(),
        "a folder that matches exactly should simply happen"
    );
}

#[test]
fn more_files_than_shots_is_reported_rather_than_quietly_dropped() {
    let (d, scene, _) = a_scene();
    let files: Vec<String> = ["1.png", "2.png", "3.png", "4.png", "5.png"]
        .iter()
        .map(|s| s.to_string())
        .collect();

    let plan = d.plan_bulk_media(&files, &d.placements_in_scene(scene));

    assert_eq!(plan.pairings.len(), 3);
    assert_eq!(plan.spare_files, vec!["4.png", "5.png"]);
    assert!(plan.needs_confirming());
    assert!(plan.summary().contains("2 files have no shot"), "{}", plan.summary());
}

#[test]
fn fewer_files_than_shots_says_how_many_are_left_without() {
    let (d, scene, _) = a_scene();
    let files = vec!["1.png".to_string()];

    let plan = d.plan_bulk_media(&files, &d.placements_in_scene(scene));

    assert_eq!(plan.pairings.len(), 1);
    assert_eq!(plan.shots_left_over, 2);
    assert!(plan.needs_confirming());
    assert!(plan.summary().contains("2 shots"), "{}", plan.summary());
}

#[test]
fn a_shot_that_already_has_a_frame_is_flagged_but_not_refused() {
    let (mut d, scene, placements) = a_scene();
    let media = d.add_media(sha256(b"a frame"), MediaKind::Image, 1920, 1080, 10, "a.png");
    d.attach_media(placements[0], media, "");

    let files: Vec<String> = ["1.png", "2.png", "3.png"].iter().map(|s| s.to_string()).collect();
    let plan = d.plan_bulk_media(&files, &d.placements_in_scene(scene));

    assert!(plan.pairings[0].already_has_frames);
    assert!(!plan.pairings[1].already_has_frames);
    assert!(plan.needs_confirming());
    assert!(
        plan.summary().contains("gain another rather than lose it"),
        "{}",
        plan.summary()
    );
}
