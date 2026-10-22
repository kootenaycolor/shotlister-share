//! The diagram, kept in the film.
//!
//! One record per element, so a drag writes one field; one undo step per
//! edit; two devices drawing at once keep both hands' work.

use shotlister_engine::diagram::{render, Kind};
use shotlister_engine::doc::f;
use shotlister_engine::json;
use shotlister_engine::{DeviceId, Doc};

fn doc() -> Doc {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Call Her Back");
    d
}

fn edit(d: &mut Doc, scene: shotlister_engine::Id, op: &str) -> Vec<String> {
    d.diagram_edit(scene, &json::parse(op).expect("op parses")).expect("edit applies")
}

#[test]
fn an_element_added_is_there_on_reading_back_with_a_record_for_an_id() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let made = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"camera","x":1,"y":2,"lens":50}]}"#);
    assert_eq!(made.len(), 1);
    let plan = d.diagram(scene);
    assert_eq!(plan.els.len(), 1);
    let cam = &plan.els[0];
    assert_eq!(cam.id, made[0]);
    assert!(cam.id.parse::<u128>().is_ok(), "a record's id, not a made-up one: {}", cam.id);
    assert_eq!((cam.kind, cam.x, cam.lens), (Kind::Camera, 1.0, 50.0));
    assert_eq!(d.diagram_count(scene), 1);
    assert_eq!(d.scenes_with_diagrams(), vec![scene]);
}

#[test]
fn a_plan_belongs_to_its_scene() {
    let mut d = doc();
    let one = d.create_scene("1");
    let two = d.create_scene("2");
    edit(&mut d, one, r#"{"op":"add","els":[{"kind":"wall","x2":3}]}"#);
    assert!(d.diagram(two).is_empty());
}

#[test]
fn moving_one_thing_writes_one_thing() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let made = edit(
        &mut d,
        scene,
        r#"{"op":"add","els":[{"kind":"wall","x2":3},{"kind":"set","sym":"bed"},{"kind":"camera"}]}"#,
    );
    let before = d.changes().len();
    edit(&mut d, scene, &format!(r#"{{"op":"move","ids":["{}"],"dx":0.5,"dy":0}}"#, made[2]));
    assert_eq!(d.changes().len() - before, 1, "one field, not the plan");
}

#[test]
fn one_edit_is_one_undo_and_redo_puts_it_back() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let made = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"set","sym":"sofa","x":1},{"kind":"set","sym":"chair","x":2}]}"#);
    edit(&mut d, scene, &format!(r#"{{"op":"move","ids":["{}","{}"],"dx":1,"dy":1}}"#, made[0], made[1]));
    assert_eq!(d.undo_label(), Some("Move"));
    d.undo();
    let plan = d.diagram(scene);
    assert_eq!(plan.get(&made[0]).unwrap().x, 1.0);
    assert_eq!(plan.get(&made[1]).unwrap().x, 2.0);
    d.undo();
    assert!(d.diagram(scene).is_empty(), "undoing the add removes both");
    d.redo();
    assert_eq!(d.diagram(scene).els.len(), 2);
    d.redo();
    assert_eq!(d.diagram(scene).get(&made[0]).unwrap().x, 2.0);
}

#[test]
fn deleting_and_undoing_brings_it_back_where_it_was_in_the_stack() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let made = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"set","x":1},{"kind":"set","x":2},{"kind":"set","x":3}]}"#);
    edit(&mut d, scene, &format!(r#"{{"op":"remove","ids":["{}"]}}"#, made[1]));
    assert_eq!(d.diagram(scene).els.len(), 2);
    d.undo();
    let ids: Vec<String> = d.diagram(scene).els.iter().map(|e| e.id.clone()).collect();
    assert_eq!(ids, made);
}

#[test]
fn restacking_keeps_its_order_after_reading_back() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let made = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"set","x":1},{"kind":"set","x":2},{"kind":"set","x":3}]}"#);
    edit(&mut d, scene, &format!(r#"{{"op":"order","ids":["{}"],"to":"back"}}"#, made[2]));
    let ids: Vec<String> = d.diagram(scene).els.iter().map(|e| e.id.clone()).collect();
    assert_eq!(ids, vec![made[2].clone(), made[0].clone(), made[1].clone()]);
    edit(&mut d, scene, &format!(r#"{{"op":"order","ids":["{}"],"to":"front"}}"#, made[2]));
    let ids: Vec<String> = d.diagram(scene).els.iter().map(|e| e.id.clone()).collect();
    assert_eq!(ids, made);
}

#[test]
fn a_duplicate_says_what_it_made_by_its_real_id() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let made = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"set","x":1}]}"#);
    let copies = edit(&mut d, scene, &format!(r#"{{"op":"duplicate","ids":["{}"]}}"#, made[0]));
    assert_eq!(copies.len(), 1);
    assert!(d.diagram(scene).get(&copies[0]).is_some());
}

#[test]
fn settings_are_kept_on_the_scene() {
    let mut d = doc();
    let scene = d.create_scene("1");
    edit(&mut d, scene, r#"{"op":"settings","set":{"units":"m","dims":false}}"#);
    let plan = d.diagram(scene);
    assert_eq!(plan.settings.units, "m");
    assert!(!plan.settings.dims);
    assert!(d.get(scene).unwrap().text(f::DIAGRAM).is_some());
}

#[test]
fn two_devices_drawing_at_once_keep_both_hands() {
    let mut mac = Doc::new(DeviceId(1));
    mac.create_project("Call Her Back");
    let scene = mac.create_scene("1");
    let made = edit(&mut mac, scene, r#"{"op":"add","els":[{"kind":"camera","x":1},{"kind":"cast","x":2}]}"#);
    let mut other = Doc::new(DeviceId(2));
    other.merge(mac.changes().to_vec());

    edit(&mut mac, scene, &format!(r#"{{"op":"move","ids":["{}"],"dx":1,"dy":0}}"#, made[0]));
    edit(&mut other, scene, &format!(r#"{{"op":"move","ids":["{}"],"dx":0,"dy":1}}"#, made[1]));
    edit(&mut other, scene, r#"{"op":"add","els":[{"kind":"light"}]}"#);

    let (a, b) = (mac.changes().to_vec(), other.changes().to_vec());
    mac.merge(b);
    other.merge(a);
    let (p, q) = (mac.diagram(scene), other.diagram(scene));
    assert_eq!(p, q, "both land in one place");
    assert_eq!(p.get(&made[0]).unwrap().x, 2.0);
    assert_eq!(p.get(&made[1]).unwrap().y, 1.0);
    assert_eq!(p.els.len(), 3);
}

#[test]
fn a_camera_reads_its_shots_number_and_lens() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let (shot, _placement) = d.add_shot_to_scene(scene);
    d.set(shot, f::LENS, "85mm");
    edit(&mut d, scene, &format!(r#"{{"op":"add","els":[{{"kind":"camera","shot":"{}"}}]}}"#, shot.0));
    let ctx = d.diagram_context(scene);
    let plan = d.diagram(scene);
    let cam = &plan.els[0];
    assert_eq!(render::camera_focal(cam, &ctx), 85.0);
    let name = render::camera_name(cam, &ctx);
    assert!(name.starts_with('1'), "{name}");
}

#[test]
fn a_cameras_size_and_movement_are_its_shots_and_one_undo_takes_them_back() {
    // His ask, 2026-10-02: the portal's Edit sets a shot's Size and Movement
    // from its camera, as the Mac's shot card does.
    let mut d = doc();
    let scene = d.create_scene("1");
    let made = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"camera","x":1,"y":1,"new_shot":true}]}"#);
    let cam = d.diagram(scene).get(&made[0]).unwrap().clone();
    let shot = cam.shot.parse::<u128>().map(shotlister_engine::Id).unwrap();
    let said = d.described_by(shot);
    edit(&mut d, scene, &format!(r#"{{"op":"camera_shot","id":"{}","set":{{"size":"MCU","movement":"Push In"}}}}"#, cam.id));
    assert_eq!(d.get(said).and_then(|r| r.text(f::SIZE)), Some("MCU"));
    assert_eq!(d.get(said).and_then(|r| r.text(f::MOVEMENT)), Some("Push In"));
    assert!(d.vocabulary(f::SIZE).iter().any(|t| t == "MCU"), "a new term joins the list");
    d.undo();
    assert_ne!(d.get(said).and_then(|r| r.text(f::SIZE)), Some("MCU"), "one undo takes both back");
    assert_ne!(d.get(said).and_then(|r| r.text(f::MOVEMENT)), Some("Push In"));
    // Off a locked list, a term does not land; clearing always does.
    d.set_vocabulary_locked(f::SIZE, true);
    edit(&mut d, scene, &format!(r#"{{"op":"camera_shot","id":"{}","set":{{"size":"Extreme Wide"}}}}"#, cam.id));
    assert_ne!(d.get(said).and_then(|r| r.text(f::SIZE)), Some("Extreme Wide"));
    // A camera with no shot has no Size to set, and writes nothing.
    let loose = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"camera","x":3,"y":1}]}"#);
    let before = d.changes().len();
    edit(&mut d, scene, &format!(r#"{{"op":"camera_shot","id":"{}","set":{{"size":"MCU"}}}}"#, loose[0]));
    assert_eq!(d.changes().len(), before);
}

#[test]
fn a_cameras_title_words_angle_and_equipment_are_its_shots() {
    // The Mac's Details for a camera with a shot, on the portal (2026-10-09):
    // Title, Description, Shot Angle, Equipment, through its camera.
    let mut d = doc();
    let scene = d.create_scene("1");
    let made = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"camera","x":1,"y":1,"new_shot":true}]}"#);
    let cam = d.diagram(scene).get(&made[0]).unwrap().clone();
    let shot = cam.shot.parse::<u128>().map(shotlister_engine::Id).unwrap();
    let said = d.described_by(shot);
    edit(&mut d, scene, &format!(r#"{{"op":"camera_shot","id":"{}","set":{{"title":"Hero Wide","description":"Gio places the cake","angle":"High, Dutch","support":"Dolly"}}}}"#, cam.id));
    let r = d.get(said).unwrap();
    assert_eq!(r.text(f::TITLE), Some("Hero Wide"));
    assert_eq!(r.text(f::DESCRIPTION), Some("Gio places the cake"));
    assert_eq!(r.text(f::SUPPORT), Some("Dolly"));
    assert!(d.vocabulary(f::ANGLE).iter().any(|t| t == "Dutch"), "both angles join the list");
    d.undo();
    assert_ne!(d.get(said).and_then(|r| r.text(f::TITLE)), Some("Hero Wide"), "one undo takes them all back");
}

#[test]
fn an_edit_that_cannot_happen_writes_nothing() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let before = d.changes().len();
    let r = d.diagram_edit(scene, &json::parse(r#"{"op":"update","id":"999","set":{"x":1}}"#).unwrap());
    assert!(r.is_err());
    assert_eq!(d.changes().len(), before);
}

#[test]
fn a_record_that_is_not_a_diagram_item_is_never_touched_by_a_plan() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let (shot, _) = d.add_shot_to_scene(scene);
    // A plan edit naming a shot's id as if it were an element does nothing
    // to the shot.
    let r = d.diagram_edit(scene, &json::parse(&format!(r#"{{"op":"remove","ids":["{}"]}}"#, shot.0)).unwrap());
    assert!(r.is_ok());
    assert!(d.get(shot).is_some());
}

#[test]
fn a_camera_can_bring_its_shot_with_it_in_one_step() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let shots_before = d.placements_in_scene(scene).len();
    let made = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"camera","x":1,"y":1,"new_shot":true}]}"#);
    assert_eq!(d.placements_in_scene(scene).len(), shots_before + 1);
    let cam = d.diagram(scene).get(&made[0]).unwrap().clone();
    assert!(!cam.shot.is_empty());
    let ctx = d.diagram_context(scene);
    assert!(ctx.shot(&cam.shot).is_some(), "the camera stands for the new shot");
    d.undo();
    assert_eq!(d.placements_in_scene(scene).len(), shots_before, "one undo takes both");
    assert!(d.diagram(scene).is_empty());
}

#[test]
fn a_batch_is_one_step() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let made = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"cast","x":0},{"kind":"cast","x":1}]}"#);
    edit(&mut d, scene, &format!(
        r#"{{"op":"batch","ops":[{{"op":"beat","id":"{}","beat":2,"x":5,"y":0}},{{"op":"beat","id":"{}","beat":2,"x":6,"y":0}}]}}"#,
        made[0], made[1]
    ));
    assert_eq!(d.diagram(scene).last_beat(), 2);
    d.undo();
    assert_eq!(d.diagram(scene).last_beat(), 1);
}

#[test]
fn a_scenes_plan_prints_with_its_shot_key() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let (shot, _) = d.add_shot_to_scene(scene);
    d.set(shot, f::LENS, "85mm");
    d.set(shot, f::DESCRIPTION, "Push in on <Anya>");
    edit(&mut d, scene, &format!(r#"{{"op":"add","els":[{{"kind":"camera","shot":"{}"}},{{"kind":"wall","x2":3}}]}}"#, shot.0));
    let page = shotlister_engine::diagram::print::page(&d, &[], Default::default(), "Call Her Back", &|_| None);
    assert!(page.contains("fresh-page"));
    assert!(page.contains("<svg"));
    // The Shots key on the sheet, as typed (capitals only with All Caps, 2026-10-17).
    assert!(page.contains("Shots"));
    assert!(page.contains("85mm"));
    assert!(page.contains("Push in on &lt;Anya&gt;"));
    let other = d.create_scene("2");
    let none = shotlister_engine::diagram::print::page(&d, &[other], Default::default(), "X", &|_| None);
    assert!(none.contains("No diagrams yet"));
}

#[test]
fn the_shot_list_can_be_left_off_the_page_and_a_loose_plan_prints_under_its_name() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let (shot, _) = d.add_shot_to_scene(scene);
    d.set(shot, f::LENS, "85mm");
    edit(&mut d, scene, &format!(r#"{{"op":"add","els":[{{"kind":"camera","shot":"{}"}},{{"kind":"wall","x2":3}}]}}"#, shot.0));
    let bare = shotlister_engine::diagram::print::Show { key: false, ..Default::default() };
    let page = shotlister_engine::diagram::print::page(&d, &[scene], bare, "Film", &|_| None);
    assert!(page.contains("<svg"));
    assert!(!page.contains(">Shots<") && !page.contains("85mm"), "no shot list");
    let plan = d.add_plan("Recce Kitchen", None);
    edit(&mut d, plan, r#"{"op":"add","els":[{"kind":"wall","x2":3}]}"#);
    let page = shotlister_engine::diagram::print::page(&d, &[plan], Default::default(), "Film", &|_| None);
    assert!(page.contains("Recce Kitchen"));
    assert!(!page.contains("INT."), "a plan has no slug");
}

#[test]
fn a_deleted_or_set_aside_scene_does_not_count_as_having_a_plan() {
    let mut d = doc();
    let kept = d.create_scene("1");
    let gone = d.create_scene("2");
    edit(&mut d, kept, r#"{"op":"add","els":[{"kind":"wall","x2":3}]}"#);
    edit(&mut d, gone, r#"{"op":"add","els":[{"kind":"wall","x2":3}]}"#);
    assert_eq!(d.scenes_with_diagrams().len(), 2);
    d.delete(gone);
    assert_eq!(d.scenes_with_diagrams(), vec![kept]);
}

#[test]
fn a_camera_whose_shot_moved_scene_still_says_which_shot_it_is() {
    let mut d = doc();
    let one = d.create_scene("1");
    let two = d.create_scene("2");
    let (shot, placement) = d.add_shot_to_scene(one);
    edit(&mut d, one, &format!(r#"{{"op":"add","els":[{{"kind":"camera","x":0,"y":0,"shot":"{}"}}]}}"#, shot.0));
    assert_eq!(render::camera_name(&d.diagram(one).els[0], &d.diagram_context(one)), "1A");
    d.move_placement_to_scene(placement, two);
    assert_eq!(render::camera_name(&d.diagram(one).els[0], &d.diagram_context(one)), "2A");
}

#[test]
fn a_picture_lets_go_of_its_file_only_when_nothing_on_the_plan_still_shows_it() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let hash = shotlister_engine::hash::sha256(b"a floor plan");
    let pic = d.diagram_add_image(scene, hash, "jpg", (400, 300), 1000, "plan.jpg", (0.0, 0.0), 4.0, false).unwrap();
    assert!(d.media_with_hash(hash).is_some(), "the picture holds its file");
    let copy = edit(&mut d, scene, &format!(r#"{{"op":"duplicate","ids":["{pic}"]}}"#));
    edit(&mut d, scene, &format!(r#"{{"op":"remove","ids":["{pic}"]}}"#));
    assert!(d.media_with_hash(hash).is_some(), "the copy still holds it");
    edit(&mut d, scene, &format!(r#"{{"op":"remove","ids":["{}"]}}"#, copy[0]));
    assert!(d.media_with_hash(hash).is_none(), "nothing shows it now");
    d.undo();
    assert!(d.media_with_hash(hash).is_some(), "undo gives the copy its file back");
}

#[test]
fn a_deleted_scene_takes_its_plan_and_undo_brings_both_back() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let hash = shotlister_engine::hash::sha256(b"a photo from above");
    d.diagram_add_image(scene, hash, "jpg", (400, 300), 1000, "above.jpg", (0.0, 0.0), 4.0, false).unwrap();
    edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"wall","x":0,"y":0,"x2":3,"y2":0}]}"#);
    d.delete_scene(scene);
    assert_eq!(d.diagram(scene).els.len(), 0);
    assert!(d.media_with_hash(hash).is_none());
    d.undo();
    assert_eq!(d.diagram(scene).els.len(), 2);
    assert!(d.media_with_hash(hash).is_some());
    assert!(d.orphaned_media().is_empty());
}

#[test]
fn new_shot_asked_once_for_a_whole_add_gives_each_camera_its_shot() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let before = d.placements_in_scene(scene).len();
    edit(&mut d, scene, r#"{"op":"add","new_shot":true,"els":[{"kind":"wall","x2":3},{"kind":"camera","x":1},{"kind":"camera","x":2}]}"#);
    let plan = d.diagram(scene);
    let cams: Vec<_> = plan.els.iter().filter(|e| e.kind == Kind::Camera).collect();
    assert!(cams.iter().all(|c| !c.shot.is_empty()), "every camera stands for a shot");
    assert_ne!(cams[0].shot, cams[1].shot);
    assert_eq!(d.placements_in_scene(scene).len(), before + 2, "two shots, not three: a wall makes none");
}

#[test]
fn a_background_lies_under_the_walls_and_a_photo_sits_over_them_in_a_frame() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let back = d
        .diagram_add_image(scene, shotlister_engine::hash::sha256(b"plan"), "jpg", (400, 300), 1000, "plan.jpg", (0.0, 0.0), 4.0, false)
        .unwrap();
    edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"wall","x":-2,"y":0,"x2":2,"y2":0}]}"#);
    let photo = d
        .diagram_add_image(scene, shotlister_engine::hash::sha256(b"lookalike"), "jpg", (400, 300), 1000, "look.jpg", (1.0, 1.0), 2.0, true)
        .unwrap();
    // The photo is added last, then sent to the back: its role still keeps it on top.
    edit(&mut d, scene, &format!(r#"{{"op":"order","ids":["{photo}"],"to":"back"}}"#));
    let plan = d.diagram(scene);
    let shapes = render::render(&plan, &d.diagram_context(scene), &render::Options { beat: 1, tween: 0.0, sel: Vec::new(), paper: true, scale: 0.0, typing: String::new(), page: false });
    let at = |el: &str, part: &str| shapes.iter().position(|s| s.el == el && s.part == part).unwrap();
    let wall = plan.els.iter().find(|e| e.kind == Kind::Wall).unwrap().id.clone();
    let wall_at = shapes.iter().position(|s| s.el == wall).unwrap();
    assert!(at(&back, "body") < wall_at, "a background is under the walls");
    assert!(at(&photo, "body") > wall_at, "a photo is over them");
    assert!(at(&photo, "frame") > at(&photo, "body"), "in a frame");
    assert!(shapes.iter().all(|s| !(s.el == back && s.part == "frame")), "a background has no frame");
    let p = plan.els.iter().find(|e| e.id == photo).unwrap();
    assert_eq!((p.role.as_str(), p.opacity), ("photo", 1.0));
}

#[test]
fn an_aimed_light_keeps_facing_what_it_is_aimed_at_and_lets_go_when_it_is_gone() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let made = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"light","sym":"generic-fresnel","x":0,"y":0},{"kind":"cast","x":3,"y":0}]}"#);
    let (lamp, actor) = (made[0].clone(), made[1].clone());
    edit(&mut d, scene, &format!(r#"{{"op":"update","ids":["{lamp}"],"set":{{"aim":"{actor}"}}}}"#));
    let rot = |d: &Doc| d.diagram(scene).els.iter().find(|e| e.id == lamp).unwrap().rot;
    assert!(rot(&d).abs() < 0.01, "faces east, where they stand: {}", rot(&d));
    edit(&mut d, scene, &format!(r#"{{"op":"update","ids":["{actor}"],"set":{{"x":0,"y":3}}}}"#));
    assert!((rot(&d) - 90.0).abs() < 0.01, "turns when they move: {}", rot(&d));
    edit(&mut d, scene, &format!(r#"{{"op":"update","ids":["{lamp}"],"set":{{"x":0,"y":6}}}}"#));
    assert!((rot(&d) - 270.0).abs() < 0.01, "and when it moves: {}", rot(&d));
    // Read back from the file: the aim is kept by the real id.
    assert_eq!(d.diagram(scene).els.iter().find(|e| e.id == lamp).unwrap().aim, actor);
    edit(&mut d, scene, &format!(r#"{{"op":"remove","ids":["{actor}"]}}"#));
    assert!(d.diagram(scene).els.iter().find(|e| e.id == lamp).unwrap().aim.is_empty(), "lets go");
}

#[test]
fn a_copied_plan_keeps_its_aims_on_the_copies() {
    let mut d = doc();
    let (one, two) = (d.create_scene("1"), d.create_scene("2"));
    let made = edit(&mut d, one, r#"{"op":"add","els":[{"kind":"camera","x":0,"y":0},{"kind":"cast","x":0,"y":2}]}"#);
    edit(&mut d, one, &format!(r#"{{"op":"update","ids":["{}"],"set":{{"aim":"{}"}}}}"#, made[0], made[1]));
    d.diagram_copy_from(two, one);
    let plan = d.diagram(two);
    let cam = plan.els.iter().find(|e| e.kind == Kind::Camera).unwrap();
    let who = plan.els.iter().find(|e| e.kind == Kind::Cast).unwrap();
    assert_eq!(cam.aim, who.id, "aimed at the copy, by its real id");
    assert!((cam.rot - 90.0).abs() < 0.01);
}

#[test]
fn a_piece_dragged_in_the_layers_lands_just_over_or_under_another() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let made = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"cast","x":0},{"kind":"cast","x":1},{"kind":"cast","x":2},{"kind":"cast","x":3}]}"#);
    let order = |d: &Doc| d.diagram(scene).els.iter().map(|e| made.iter().position(|m| *m == e.id).unwrap()).collect::<Vec<_>>();
    edit(&mut d, scene, &format!(r#"{{"op":"order","ids":["{}"],"to":"above","next":"{}"}}"#, made[0], made[2]));
    assert_eq!(order(&d), vec![1, 2, 0, 3]);
    edit(&mut d, scene, &format!(r#"{{"op":"order","ids":["{}"],"to":"below","next":"{}"}}"#, made[3], made[1]));
    assert_eq!(order(&d), vec![3, 1, 2, 0], "and it stays so on reading back");
}

// ---------------------------------------------------------------- frames and gels (Lane B, 2026-09-28)

use shotlister_engine::diagram::render::{Geom, Ink, Seg, Shape};
use shotlister_engine::diagram::Diagram;

fn drawn(plan: &str) -> Vec<Shape> {
    // Beams are off by default (2026-09-28); these are about beams.
    let mut d = Diagram::parse(&format!(r#"{{"els":{plan}}}"#));
    d.settings.beams = true;
    render::render(&d, &render::Context::default(), &render::Options::default())
}

fn points(s: &Shape) -> Vec<(f64, f64)> {
    let Geom::Path(segs) = &s.geom else { panic!("a beam is a path") };
    segs.iter()
        .filter_map(|s| match s {
            Seg::M(x, y) | Seg::L(x, y) | Seg::C(_, _, _, _, x, y) => Some((*x, *y)),
            Seg::Z => None,
        })
        .collect()
}

fn beams<'a>(shapes: &'a [Shape], id: &str) -> Vec<&'a Shape> {
    shapes.iter().filter(|s| s.el == id && s.part == "beam").collect()
}

fn alpha(s: &Shape) -> f64 {
    match &s.fill {
        Ink::Hex(_, a) => *a,
        _ => 1.0,
    }
}

fn hex(s: &Shape) -> String {
    match &s.fill {
        Ink::Hex(h, _) => h.clone(),
        _ => String::new(),
    }
}

fn farthest_x(s: &Shape) -> f64 {
    points(s).iter().map(|p| p.0).fold(f64::MIN, f64::max)
}

/// A lamp at the origin facing east, forty degrees wide, reaching four
/// metres, its face at x = 0; and whatever stands in front of it.
const LAMP: &str = r#"{"kind":"light","id":"l","sym":"generic-fresnel","x":-0.2,"y":0,"rot":0,"w":0.4,"h":0.4,"beam":40,"reach":4,"kelvin":5600}"#;

fn frame_at(x: f64, material: &str) -> String {
    format!(r#"{{"kind":"light","id":"f","sym":"frame","x":{x},"y":0,"rot":0,"h":2.44,"material":"{material}"}}"#)
}

#[test]
#[ignore = "lamp beams and light levels are off for now (render::LAMP_BEAMS, his call 2026-10-01)"]
fn a_solid_frame_cuts_a_beam_like_a_wall() {
    let shapes = drawn(&format!("[{LAMP},{}]", frame_at(1.0, "solid")));
    let b = beams(&shapes, "l");
    assert_eq!(b.len(), 1, "one beam, cut short");
    assert!(farthest_x(b[0]) <= 1.0, "nothing past the solid: {}", farthest_x(b[0]));
    assert!(farthest_x(b[0]) > 0.9, "it reaches the solid");
    let open = drawn(&format!("[{LAMP}]"));
    assert!(farthest_x(beams(&open, "l")[0]) > 3.7, "without it, the whole reach");
}

#[test]
#[ignore = "lamp beams and light levels are off for now (render::LAMP_BEAMS, his call 2026-10-01)"]
fn a_net_dims_what_passes_and_a_double_more_than_a_single() {
    let past = |m: &str| {
        let shapes = drawn(&format!("[{LAMP},{}]", frame_at(1.0, m)));
        let b = beams(&shapes, "l");
        assert_eq!(b.len(), 2, "{m}: the beam to the net and the beam past it");
        assert!(farthest_x(b[0]) <= 1.0, "{m}: the first stops at the net");
        (alpha(b[1]), farthest_x(b[1]), alpha(b[0]))
    };
    let (single, single_far, full) = past("single-net");
    let (double, double_far, _) = past("double-net");
    assert!(single < full && double < single, "fainter past it: {full} {single} {double}");
    assert!(single_far > 3.0 && single_far < 3.9, "a single loses half a stop of reach: {single_far}");
    assert!(double_far < single_far, "a double loses more: {double_far}");
}

#[test]
#[ignore = "lamp beams and light levels are off for now (render::LAMP_BEAMS, his call 2026-10-01)"]
fn a_diffusion_turns_the_beam_past_it_into_a_wider_softer_one() {
    let shapes = drawn(&format!("[{LAMP},{}]", frame_at(1.0, "diff-heavy")));
    let b = beams(&shapes, "l");
    assert_eq!(b.len(), 2);
    let spread = |s: &Shape| points(s).iter().map(|p| p.1.abs()).fold(0.0, f64::max);
    let open = drawn(&format!("[{LAMP}]"));
    assert!(spread(b[1]) > spread(beams(&open, "l")[0]) * 1.2, "wider past it: {} vs {}", spread(b[1]), spread(beams(&open, "l")[0]));
    assert!(alpha(b[1]) < alpha(b[0]), "and softer");
    assert!(points(b[1]).iter().all(|p| p.0 >= 0.9), "all of it past the frame");
    // An egg crate holds it in.
    let gridded = drawn(&format!("[{LAMP},{}]", frame_at(1.0, "diff-heavy").replace("\"material\"", "\"grid\":20,\"material\"")));
    assert!(spread(beams(&gridded, "l")[1]) < spread(b[1]), "a grid narrows it");
}

#[test]
#[ignore = "lamp beams and light levels are off for now (render::LAMP_BEAMS, his call 2026-10-01)"]
fn a_bounce_throws_back_what_is_aimed_at_it_along_the_mirror_angle() {
    // Lamp up-left of a white bounce lying face-down the page; the light
    // comes in heading south-east, so it goes out heading north-east.
    let lamp = r#"{"kind":"light","id":"l","sym":"generic-fresnel","x":0,"y":0,"rot":45,"beam":40,"reach":6,"aim":"b"}"#;
    let board = r#"{"kind":"light","id":"b","sym":"frame","x":2,"y":2,"rot":90,"h":2.44,"material":"bounce-white"}"#;
    let shapes = drawn(&format!("[{lamp},{board}]"));
    let thrown = beams(&shapes, "b");
    assert_eq!(thrown.len(), 1, "the bounce throws one soft beam");
    let pts = points(thrown[0]);
    let (mx, my) = pts.iter().fold((0.0, 0.0), |a, p| (a.0 + p.0, a.1 + p.1));
    let (mx, my) = (mx / pts.len() as f64, my / pts.len() as f64);
    assert!(mx > 2.3 && my < 1.7, "up and to the right of the board: {mx},{my}");
    // Not aimed, nothing thrown; and a solid never throws.
    let loose = drawn(&format!("[{},{board}]", lamp.replace(r#","aim":"b""#, "")));
    assert!(beams(&loose, "b").is_empty());
    let solid = drawn(&format!("[{lamp},{}]", board.replace("bounce-white", "solid")));
    assert!(beams(&solid, "b").is_empty());
    // Silver keeps it tighter than white.
    let silver = drawn(&format!("[{lamp},{}]", board.replace("bounce-white", "bounce-silver")));
    let width = |s: &Shape| {
        let p = points(s);
        let far = p.iter().map(|q| (q.0 - 2.0).hypot(q.1 - 2.0)).fold(0.0, f64::max);
        far
    };
    assert!(beams(&silver, "b").len() == 1 && width(beams(&silver, "b")[0]) > 0.5);
}

#[test]
#[ignore = "lamp beams and light levels are off for now (render::LAMP_BEAMS, his call 2026-10-01)"]
fn the_librarys_flags_and_nets_shape_light_by_what_they_are() {
    let flag = r#"{"kind":"light","id":"f","sym":"flag-4x4","x":1,"y":0,"rot":0,"w":0.06,"h":1.22}"#;
    let shapes = drawn(&format!("[{LAMP},{flag}]"));
    let b = beams(&shapes, "l");
    assert!(b.iter().all(|s| farthest_x(s) <= 1.0), "a floppy cuts");
    let net = r#"{"kind":"light","id":"f","sym":"fso-4x4-single-black-scrim","x":1,"y":0,"rot":0,"w":0.06,"h":1.22}"#;
    assert_eq!(beams(&drawn(&format!("[{LAMP},{net}]")), "l").len(), 2, "the pack's single scrim dims");
}

#[test]
#[ignore = "lamp beams and light levels are off for now (render::LAMP_BEAMS, his call 2026-10-01)"]
fn gels_warm_cool_and_dim_the_beam_and_ride_in_its_name() {
    let with = |gels: &str| drawn(&format!("[{}]", LAMP.replace(r#""kelvin":5600"#, &format!(r#""kelvin":5600,"gels":[{gels}]"#))));
    let plain = drawn(&format!("[{LAMP}]"));
    let cto = with(r#""cto-full""#);
    assert_ne!(hex(beams(&cto, "l")[0]), hex(beams(&plain, "l")[0]), "CTO warms daylight");
    assert_eq!(hex(beams(&cto, "l")[0]), render::kelvin_hex(3000.0), "to about tungsten");
    let label = |s: &[Shape]| {
        s.iter()
            .find(|x| x.el == "l" && x.part == "label")
            .and_then(|x| match &x.geom {
                Geom::Text { text, .. } => Some(text.clone()),
                _ => None,
            })
            .unwrap_or_default()
    };
    // On a line of their own under the name, as Scenario sets them.
    assert_eq!(label(&cto), "Fresnel\nFull CTO");
    let two = with(r#""cto-half","nd6""#);
    assert_eq!(label(&two), "Fresnel\n½ CTO · ND .6");
    let nd = with(r#""nd6""#);
    let (b, p) = (beams(&nd, "l")[0], beams(&plain, "l")[0]);
    assert!(alpha(b) < alpha(p), "ND draws it fainter");
    assert!(farthest_x(b) < farthest_x(p) * 0.6, "and shorter: two stops is half the reach");
    assert_eq!(hex(b), hex(p), "ND does not tint");
    // CTB cools a tungsten lamp.
    let tung = drawn(&format!("[{}]", LAMP.replace("5600", r#"3200,"gels":["ctb-full"]"#)));
    assert_eq!(hex(beams(&tung, "l")[0]), render::kelvin_hex(5600.0));
    // A gel in a frame tints what passes through it.
    let warm = drawn(&format!("[{LAMP},{}]", frame_at(1.0, "single-net").replace("\"material\"", r#""gels":["cto-full"],"material""#)));
    let b = beams(&warm, "l");
    assert_ne!(hex(b[1]), hex(b[0]), "warmer past the frame");
}

#[test]
fn a_frame_keeps_its_skin_size_and_lean_in_the_film() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let made = edit(
        &mut d,
        scene,
        r#"{"op":"add","els":[{"kind":"light","sym":"frame","x":1,"y":1,"h":3.66,"tall":6.1,"tilt":60,"material":"bounce-gold","pipe":"speed-rail","grid":40,"gels":["cto-half","nd3"]}]}"#,
    );
    let plan = d.diagram(scene);
    let f = plan.els.iter().find(|e| e.id == made[0]).unwrap();
    assert_eq!((f.material.as_str(), f.pipe.as_str(), f.grid, f.tilt, f.tall), ("bounce-gold", "speed-rail", 40.0, 60.0, 6.1));
    assert_eq!(f.gels, vec!["cto-half".to_string(), "nd3".to_string()]);
    assert!((f.w - 3.05).abs() < 1e-3, "twenty feet leaning sixty degrees is ten along the floor: {}", f.w);
    edit(&mut d, scene, &format!(r#"{{"op":"update","ids":["{}"],"set":{{"tilt":90,"gels":[]}}}}"#, made[0]));
    let f = d.diagram(scene).els.into_iter().find(|e| e.id == made[0]).unwrap();
    assert!((f.w - 0.12).abs() < 1e-9, "standing, it is its pipe: {}", f.w);
    assert!(f.gels.is_empty());
    // A grid that is not one of the four is none; a lean past standing is standing.
    edit(&mut d, scene, &format!(r#"{{"op":"update","ids":["{}"],"set":{{"grid":35,"tilt":400}}}}"#, made[0]));
    let f = d.diagram(scene).els.into_iter().find(|e| e.id == made[0]).unwrap();
    assert_eq!((f.grid, f.tilt), (0.0, 90.0));
}

#[test]
fn frames_in_beams_keep_a_busy_plan_quick() {
    // Sixty pieces: twelve lamps, twelve frames of every skin in their
    // beams, walls round them, cast and cameras.
    let skins = ["solid", "single-net", "double-net", "diff-light", "diff-heavy", "silk", "bounce-white", "bounce-silver", "grid-cloth", "muslin", "diff-medium", "bounce-gold"];
    let mut els = Vec::new();
    for i in 0..12 {
        let y = i as f64 * 1.5;
        els.push(format!(r#"{{"kind":"light","id":"l{i}","sym":"generic-hmi","x":0,"y":{y},"rot":0,"beam":50,"reach":8,"aim":"{}","gels":["cto-half"]}}"#, if i % 3 == 0 { format!("f{i}") } else { String::new() }));
        els.push(format!(r#"{{"kind":"light","id":"f{i}","sym":"frame","x":2.5,"y":{y},"rot":{},"h":2.44,"material":"{}"}}"#, 160 + i, skins[i]));
        els.push(format!(r#"{{"kind":"cast","id":"p{i}","x":5,"y":{y}}}"#));
        els.push(format!(r#"{{"kind":"camera","id":"c{i}","x":7,"y":{y},"rot":180}}"#));
        els.push(format!(r#"{{"kind":"wall","id":"w{i}","x":-1,"y":{},"x2":9,"y2":{}}}"#, y + 0.7, y + 0.9));
    }
    let plan = format!("[{}]", els.join(","));
    let d = Diagram::parse(&format!(r#"{{"els":{plan}}}"#));
    assert_eq!(d.els.len(), 60);
    let start = std::time::Instant::now();
    let n = 20;
    for _ in 0..n {
        std::hint::black_box(render::render(&d, &render::Context::default(), &render::Options::default()));
    }
    let each = start.elapsed().as_secs_f64() * 1000.0 / n as f64;
    eprintln!("render with frames in beams: {each:.3} ms a plan of 60");
    // Generous for a debug build; the release figure is in the report.
    assert!(each < 40.0, "{each} ms");
}

#[test]
fn beams_are_off_until_asked_for_and_then_on_for_the_whole_film_in_one_step() {
    let mut d = doc();
    let (one, two) = (d.create_scene("1"), d.create_scene("2"));
    assert!(!d.diagram(one).settings.beams, "off by default");
    let n = d.diagram_setting_everywhere("beams", json::parse("true").unwrap());
    assert_eq!(n, 2);
    assert!(d.diagram(one).settings.beams && d.diagram(two).settings.beams);
    d.undo();
    assert!(!d.diagram(one).settings.beams && !d.diagram(two).settings.beams, "one undo takes it off everywhere");
}

// ---- names moved and styled; a camera's frame laid on the plan (Lane D) ----

#[test]
fn a_name_moves_sizes_and_hides_on_its_own() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let made = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"set","sym":"sofa","x":2,"y":3,"label":"Couch"}]}"#);
    let id = made[0].clone();
    let label_of = |d: &Doc| {
        let plan = d.diagram(scene);
        let shapes = render::render(&plan, &d.diagram_context(scene), &render::Options::default());
        shapes.into_iter().find(|s| s.el == id && s.part == "label").map(|s| s.geom)
    };
    // Under the piece, centred, like every name (2026-10-01).
    let Some(render::Geom::Text { x, y, size, bold, .. }) = label_of(&d) else { panic!("a label") };
    let sofa_h = d.diagram(scene).get(&id).unwrap().h;
    // One size, regular weight, for every name (Back to Paper, 2026-10-04).
    assert_eq!((x, size, bold), (2.0, 10.0, false));
    assert!(y > 3.0 + sofa_h / 2.0 && y < 3.0 + sofa_h / 2.0 + 0.3, "just under it: {y}");
    let (x0, y0) = (x, y);
    edit(&mut d, scene, &format!(r#"{{"op":"update","ids":["{id}"],"set":{{"label_dx":0.5,"label_dy":-1,"label_size":14,"label_bold":false}}}}"#));
    let Some(render::Geom::Text { x, y, size, bold, .. }) = label_of(&d) else { panic!("a label") };
    assert!((x - x0 - 0.5).abs() < 1e-9 && (y - y0 + 1.0).abs() < 0.05, "moved by its offset: {x},{y}");
    // A size and weight set on it are kept in the film, and not drawn.
    assert_eq!((size, bold), (10.0, false));
    let e = d.diagram(scene).get(&id).cloned().unwrap();
    assert_eq!((e.label_size, e.label_bold), (14.0, false));
    // The piece moved: the name goes with it, the offset kept.
    let (x1, y1) = (x, y);
    edit(&mut d, scene, &format!(r#"{{"op":"move","ids":["{id}"],"dx":1,"dy":1}}"#));
    let Some(render::Geom::Text { x, y, .. }) = label_of(&d) else { panic!("a label") };
    assert!((x - x1 - 1.0).abs() < 1e-9 && (y - y1 - 1.0).abs() < 1e-9, "{x},{y}");
    // Hidden: gone from the plan, and the offset kept for when it comes back.
    edit(&mut d, scene, &format!(r#"{{"op":"update","ids":["{id}"],"set":{{"label_hidden":true}}}}"#));
    assert!(label_of(&d).is_none());
    let e = d.diagram(scene).get(&id).cloned().unwrap();
    assert_eq!((e.label_dx, e.label_dy, e.label_hidden), (0.5, -1.0, true));
    d.undo();
    assert!(label_of(&d).is_some(), "Show Name is one undo away");
}

#[test]
fn a_name_is_moved_on_the_page_as_shown_whichever_way_north_is() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let made = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"set","sym":"sofa","label":"Couch","label_dx":1}]}"#);
    edit(&mut d, scene, r#"{"op":"settings","set":{"north":90}}"#);
    let plan = d.diagram(scene);
    let mut shapes = render::render(&plan, &d.diagram_context(scene), &render::Options::default());
    render::turn_shapes(&mut shapes, render::view_turn(&plan));
    let Some(render::Geom::Text { x, y, .. }) = shapes.iter().find(|s| s.el == made[0] && s.part == "label").map(|s| s.geom.clone()) else {
        panic!("a label")
    };
    assert!((x - 1.0).abs() < 1e-6 && y > 0.0, "right of its spot under the piece, on the page: {x},{y}");
}

#[test]
fn a_cameras_tag_moves_and_hides_like_any_name() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let made = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"camera","label":"A","label_size":16,"label_hidden":false}]}"#);
    let plan = d.diagram(scene);
    let shapes = render::render(&plan, &d.diagram_context(scene), &render::Options::default());
    let tag = shapes.iter().find(|s| s.el == made[0] && s.part == "label").expect("a name");
    // Drawn the plan's one size; its own kept in the film.
    assert!(matches!(tag.geom, render::Geom::Text { size, .. } if size == render::NAME_PT));
    assert_eq!(d.diagram(scene).get(&made[0]).unwrap().label_size, 16.0);
    edit(&mut d, scene, &format!(r#"{{"op":"update","ids":["{}"],"set":{{"label_hidden":true}}}}"#, made[0]));
    let plan = d.diagram(scene);
    let shapes = render::render(&plan, &d.diagram_context(scene), &render::Options::default());
    assert!(!shapes.iter().any(|s| s.el == made[0] && s.part == "label"));
}

fn with_frame(d: &mut Doc, scene: shotlister_engine::Id) -> shotlister_engine::Id {
    use shotlister_engine::hash::sha256;
    use shotlister_engine::media::MediaKind;
    let (shot, _placement) = d.add_shot_to_scene(scene);
    let hash = sha256(b"a frame");
    let media = d.add_media(hash, MediaKind::Image, 1920, 800, 7, "frame.JPG");
    d.attach_media(shot, media, "");
    shot
}

#[test]
fn the_context_carries_each_cameras_shot_frame_named_as_pictures_are() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let shot = with_frame(&mut d, scene);
    edit(&mut d, scene, &format!(r#"{{"op":"add","els":[{{"kind":"camera","shot":"{}"}}]}}"#, shot.0));
    let ctx = d.diagram_context(scene);
    let (media, aspect) = ctx.frame(&shot.0.to_string()).expect("the frame");
    let hex = shotlister_engine::hash::sha256(b"a frame").to_hex();
    assert_eq!(media, format!("{}.jpg", &hex[..32]));
    assert!((aspect - 800.0 / 1920.0).abs() < 1e-9);
}

#[test]
fn a_clips_frame_on_the_plan_is_its_poster() {
    // His note, 2026-09-28: "videos are still not showing up in plan".
    use shotlister_engine::hash::sha256;
    use shotlister_engine::media::MediaKind;
    let mut d = doc();
    let scene = d.create_scene("1");
    let (shot, _) = d.add_shot_to_scene(scene);
    let media = d.add_media(sha256(b"a clip"), MediaKind::Video, 1280, 720, 9, "take.MOV");
    d.attach_media(shot, media, "");
    edit(&mut d, scene, &format!(r#"{{"op":"add","els":[{{"kind":"camera","shot":"{}","frame_on":true}}]}}"#, shot.0));
    let (name, aspect) = d.diagram_frame(shot).expect("a clip has a frame on the plan");
    let hex = sha256(b"a clip").to_hex();
    assert_eq!(name, format!("{}.jpg", &hex[..32]), "named by its poster, not the movie");
    assert!((aspect - 720.0 / 1280.0).abs() < 1e-9);
    let shapes = render::render(&d.diagram(scene), &d.diagram_context(scene), &render::Options::default());
    assert!(shapes.iter().any(|s| s.part == "shotframe" && matches!(&s.geom, render::Geom::Image { media, .. } if *media == name)));
    assert!(!shapes.iter().any(|s| matches!(&s.geom, render::Geom::Text { text, .. } if text.eq_ignore_ascii_case("No Frame"))), "says so — in capitals on a plot");
}

#[test]
fn a_cameras_frame_is_laid_on_the_plan_and_goes_where_the_camera_goes() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let shot = with_frame(&mut d, scene);
    let made = edit(&mut d, scene, &format!(r#"{{"op":"add","els":[{{"kind":"camera","x":1,"y":1,"shot":"{}"}}]}}"#, shot.0));
    let cam = made[0].clone();
    let frame_of = |d: &Doc| {
        let plan = d.diagram(scene);
        let shapes = render::render(&plan, &d.diagram_context(scene), &render::Options { paper: true, ..Default::default() });
        shapes.into_iter().filter(|s| s.el == cam && s.part == "shotframe").collect::<Vec<_>>()
    };
    assert!(frame_of(&d).is_empty(), "off until he lays it on");
    edit(&mut d, scene, &format!(r#"{{"op":"update","ids":["{cam}"],"set":{{"frame_on":true,"frame_dx":3,"frame_dy":0,"frame_w":2.4}}}}"#));
    let parts = frame_of(&d);
    let img = parts.iter().find_map(|s| match &s.geom {
        render::Geom::Image { media, x, y, w, h, .. } => Some((media.clone(), *x, *y, *w, *h)),
        _ => None,
    });
    let (media, x, y, w, h) = img.expect("the frame's picture");
    assert!(media.ends_with(".jpg"));
    assert!((x - 4.0).abs() < 1e-9 && (y - 1.0).abs() < 1e-9, "{x},{y}");
    assert!((w - 2.4).abs() < 1e-9 && (h - 1.0).abs() < 1e-9, "at the picture's own shape: {w}x{h}");
    assert!(parts.iter().filter(|s| matches!(s.geom, render::Geom::Path(_))).count() >= 2, "a border and a line to the camera");
    edit(&mut d, scene, &format!(r#"{{"op":"move","ids":["{cam}"],"dx":-1,"dy":2}}"#));
    let moved = frame_of(&d).into_iter().find_map(|s| match s.geom {
        render::Geom::Image { x, y, .. } => Some((x, y)),
        _ => None,
    });
    assert_eq!(moved, Some((3.0, 3.0)), "the frame goes with the camera");
    // Printed and on the portal: the same picture, by the same name.
    let svg = shotlister_engine::diagram::svg::svg(
        &d.diagram(scene),
        &d.diagram_context(scene),
        &render::Options::default(),
        &shotlister_engine::diagram::svg::Frame { media: "media/{hash}".into(), ..Default::default() },
        "t",
    );
    assert!(svg.contains(&format!("media/{media}")), "the portal fetches it from beside the page");
}

#[test]
fn a_frame_on_a_camera_with_no_picture_says_so_and_is_kept_to_cameras() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let made = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"camera","frame_on":true},{"kind":"set","sym":"sofa","frame_on":true}]}"#);
    let plan = d.diagram(scene);
    assert!(!plan.get(&made[1]).unwrap().frame_on, "only a camera lays a frame");
    let shapes = render::render(&plan, &d.diagram_context(scene), &render::Options::default());
    assert!(shapes.iter().any(|s| s.el == made[0] && s.part == "shotframe" && matches!(&s.geom, render::Geom::Text { text, .. } if text.eq_ignore_ascii_case("No Frame"))), "says so — in capitals on a plot");
}

#[test]
fn a_cameras_frame_on_the_plan_prints() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let shot = with_frame(&mut d, scene);
    edit(&mut d, scene, &format!(r#"{{"op":"add","els":[{{"kind":"camera","shot":"{}","frame_on":true}}]}}"#, shot.0));
    let (media, _) = d.diagram_frame(shot).expect("a frame");
    let page = shotlister_engine::diagram::print::page(&d, &[scene], Default::default(), "Film", &|m: &str| Some(format!("data:x/{m}")));
    assert!(page.contains(&format!("data:x/{media}")), "the frame travels inside the printed page");
}

fn light_levels_are_kept_with_the_plan_and_drawn_only_when_on() {
    let mut d = doc();
    let scene = d.create_scene("1");
    edit(
        &mut d,
        scene,
        r#"{"op":"add","els":[{"kind":"light","sym":"fresnel-2k","x":0,"y":0,"beam":56,"height":"7 ft"},{"kind":"cast","x":3,"y":0}]}"#,
    );
    let plan = d.diagram(scene);
    let (lamp, person) = (plan.els[0].id.clone(), plan.els[1].id.clone());
    edit(&mut d, scene, &format!(r#"{{"op":"update","ids":["{lamp}"],"set":{{"aim":"{person}"}}}}"#));
    let levels = |d: &Doc| render::render(&d.diagram(scene), &render::Context::default(), &render::Options::default()).into_iter().filter(|s| s.part == "level").count();
    assert_eq!(levels(&d), 0, "off unless asked for");
    edit(&mut d, scene, r#"{"op":"settings","set":{"levels":true,"light_units":"lux","iso":1600,"shutter":50,"stop":4,"ambient":20}}"#);
    let s = d.diagram(scene).settings;
    assert!(s.levels && s.light_units == "lux" && s.iso == 1600.0 && s.shutter == 50.0 && s.stop == 4.0 && s.ambient == 20.0);
    assert!(levels(&d) >= 2, "a ring and its level on the person");
    let shapes = render::render(&d.diagram(scene), &render::Context::default(), &render::Options::default());
    let words: Vec<String> = shapes
        .iter()
        .filter(|s| s.part == "level")
        .filter_map(|s| match &s.geom {
            render::Geom::Text { text, .. } => Some(text.clone()),
            _ => None,
        })
        .collect();
    assert_eq!(words.len(), 1);
    assert!(words[0].ends_with(" lx"), "{words:?}");
    d.undo();
    assert!(!d.diagram(scene).settings.levels, "one undo step");
}

#[test]
#[ignore = "lamp beams and light levels are off for now (render::LAMP_BEAMS, his call 2026-10-01)"]
fn light_levels_keep_a_busy_plan_quick() {
    let skins = ["solid", "single-net", "double-net", "diff-light", "diff-heavy", "silk", "bounce-white", "bounce-silver", "grid-cloth", "muslin", "diff-medium", "bounce-gold"];
    let mut els = Vec::new();
    for i in 0..12 {
        let y = i as f64 * 1.5;
        let aim = if i % 3 == 0 { format!("f{i}") } else { format!("p{i}") };
        els.push(format!(r#"{{"kind":"light","id":"l{i}","sym":"generic-hmi","x":0,"y":{y},"rot":0,"beam":50,"reach":8,"aim":"{aim}","gels":["cto-half"]}}"#));
        els.push(format!(r#"{{"kind":"light","id":"f{i}","sym":"frame","x":2.5,"y":{y},"rot":{},"h":2.44,"material":"{}","aim":"p{i}"}}"#, 160 + i, skins[i]));
        els.push(format!(r#"{{"kind":"cast","id":"p{i}","x":5,"y":{y}}}"#));
        els.push(format!(r#"{{"kind":"camera","id":"c{i}","x":7,"y":{y},"rot":180}}"#));
        els.push(format!(r#"{{"kind":"wall","id":"w{i}","x":-1,"y":{},"x2":9,"y2":{}}}"#, y + 0.7, y + 0.9));
    }
    els.push(r#"{"kind":"light","id":"s","sym":"spacelight","x":3,"y":8,"beam":180,"height":"4 m"}"#.to_string());
    let plan = format!("[{}]", els.join(","));
    let d = Diagram::parse(&format!(r#"{{"els":{plan},"settings":{{"levels":true,"ambient":30}}}}"#));
    let start = std::time::Instant::now();
    let n = 20;
    let mut rings = 0;
    for _ in 0..n {
        rings = std::hint::black_box(render::render(&d, &render::Context::default(), &render::Options::default())).iter().filter(|s| s.part == "level").count();
    }
    let each = start.elapsed().as_secs_f64() * 1000.0 / n as f64;
    eprintln!("render with light levels: {each:.3} ms a plan of 61, {rings} level shapes");
    assert!(rings > 12);
    assert!(each < 40.0, "{each} ms");
}

// ---------------------------------------------------------------- Lane C: speed

fn el(d: &Doc, scene: shotlister_engine::Id, id: &str) -> shotlister_engine::diagram::El {
    d.diagram(scene).get(id).cloned().unwrap_or_else(|| panic!("no {id}"))
}

#[test]
fn a_lamp_set_down_on_a_stand_rides_it_when_the_stand_moves_and_turns() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let made = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"set","sym":"c-stand","x":2,"y":2,"w":0.9,"h":0.9}]}"#);
    let stand = made[0].clone();
    // Put down on it: it gets on, with the stand's real id.
    let lamp = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"light","sym":"generic-fresnel","x":2.2,"y":2,"rot":0}]}"#)[0].clone();
    assert_eq!(el(&d, scene, &lamp).rig_on, stand);
    // Put down on the floor: it stands on its own.
    let loose = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"light","sym":"generic-fresnel","x":6,"y":6}]}"#)[0].clone();
    assert_eq!(el(&d, scene, &loose).rig_on, "");
    // The stand moves: the lamp comes, the loose one does not — one step.
    let depth = d.undo_depth();
    edit(&mut d, scene, &format!(r#"{{"op":"move","ids":["{stand}"],"dx":1,"dy":0.5}}"#));
    assert_eq!(d.undo_depth(), depth + 1);
    let l = el(&d, scene, &lamp);
    assert!(((l.x, l.y) == (3.2, 2.5)), "carried: {} {}", l.x, l.y);
    assert_eq!((el(&d, scene, &loose).x, el(&d, scene, &loose).y), (6.0, 6.0));
    // The stand turns a quarter: the lamp swings round it and turns with it.
    edit(&mut d, scene, &format!(r#"{{"op":"update","ids":["{stand}"],"set":{{"rot":90}}}}"#));
    let l = el(&d, scene, &lamp);
    assert!((l.x - 3.0).abs() < 1e-3 && (l.y - 2.7).abs() < 1e-3 && (l.rot - 90.0).abs() < 1e-3, "{} {} {}", l.x, l.y, l.rot);
    // Undo takes the turn back, lamp and all.
    d.undo().unwrap();
    let l = el(&d, scene, &lamp);
    assert!(((l.x, l.y, l.rot) == (3.2, 2.5, 0.0)), "{} {} {}", l.x, l.y, l.rot);
}

#[test]
fn a_rider_dragged_fully_off_gets_off_and_one_moved_with_its_stand_stays_on() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let made = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"set","sym":"c-stand","x":2,"y":2,"w":0.9,"h":0.9},{"kind":"camera","x":2,"y":2}]}"#);
    let (stand, cam) = (made[0].clone(), made[1].clone());
    assert_eq!(el(&d, scene, &cam).rig_on, stand);
    // Both dragged together: moved, not carried twice, still on.
    edit(&mut d, scene, &format!(r#"{{"op":"move","ids":["{stand}","{cam}"],"dx":1,"dy":0}}"#));
    assert_eq!((el(&d, scene, &cam).x, el(&d, scene, &cam).rig_on.clone()), (3.0, stand.clone()));
    // A little way across it: still on.
    edit(&mut d, scene, &format!(r#"{{"op":"move","ids":["{cam}"],"dx":0.3,"dy":0}}"#));
    assert_eq!(el(&d, scene, &cam).rig_on, stand);
    // Fully off: off.
    edit(&mut d, scene, &format!(r#"{{"op":"move","ids":["{cam}"],"dx":3,"dy":0}}"#));
    assert_eq!(el(&d, scene, &cam).rig_on, "");
    edit(&mut d, scene, &format!(r#"{{"op":"move","ids":["{stand}"],"dx":1,"dy":0}}"#));
    assert_eq!(el(&d, scene, &cam).x, 6.3, "left where it was");
}

#[test]
fn deleting_the_stand_lets_the_lamp_go_and_never_deletes_it() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let made = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"set","sym":"table","x":1,"y":1,"w":1.2,"h":0.8},{"kind":"light","sym":"generic-fresnel","x":1,"y":1}]}"#);
    let (table, lamp) = (made[0].clone(), made[1].clone());
    assert_eq!(el(&d, scene, &lamp).rig_on, table);
    edit(&mut d, scene, &format!(r#"{{"op":"remove","ids":["{table}"]}}"#));
    let plan = d.diagram(scene);
    assert_eq!(plan.els.len(), 1);
    assert_eq!(plan.els[0].rig_on, "");
    // One step: undo brings the table back and the lamp riding it.
    d.undo().unwrap();
    assert_eq!(el(&d, scene, &lamp).rig_on, table);
}

#[test]
fn duplicating_a_stand_duplicates_its_lamp_rigged_to_the_copy() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let made = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"set","sym":"c-stand","x":2,"y":2,"w":0.9,"h":0.9},{"kind":"light","sym":"frame","x":2,"y":2,"h":1.2,"tilt":90},{"kind":"light","sym":"generic-fresnel","x":2,"y":2.1}]}"#);
    let (stand, frame, lamp) = (made[0].clone(), made[1].clone(), made[2].clone());
    // The frame is on the stand; the lamp on the frame — the smallest under it.
    assert_eq!(el(&d, scene, &frame).rig_on, stand);
    assert_eq!(el(&d, scene, &lamp).rig_on, frame);
    let copies = edit(&mut d, scene, &format!(r#"{{"op":"duplicate","ids":["{stand}"],"dx":3,"dy":0}}"#));
    assert_eq!(copies.len(), 3, "the stand and everything on it");
    let plan = d.diagram(scene);
    let kinds: Vec<(String, String)> = copies.iter().map(|id| (plan.get(id).unwrap().sym.clone(), plan.get(id).unwrap().rig_on.clone())).collect();
    assert_eq!(kinds[0], ("c-stand".into(), "".into()));
    assert_eq!(kinds[1], ("frame".into(), copies[0].clone()), "the copy of the frame rides the copy of the stand, by its real id");
    assert_eq!(kinds[2], ("generic-fresnel".into(), copies[1].clone()));
    // The originals stay as they were.
    assert_eq!(el(&d, scene, &frame).rig_on, stand);
    // Moving the copy of the stand takes both copies, three deep.
    edit(&mut d, scene, &format!(r#"{{"op":"move","ids":["{}"],"dx":0,"dy":1}}"#, copies[0]));
    let plan = d.diagram(scene);
    assert_eq!(plan.get(&copies[2]).unwrap().y, 3.1);
    assert_eq!(plan.get(&lamp).unwrap().y, 2.1);
}

#[test]
fn a_rig_can_never_ride_itself_and_a_rug_or_a_person_carries_nothing() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let made = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"set","sym":"rug","x":0,"y":0,"w":3,"h":2},{"kind":"cast","x":1,"y":0},{"kind":"light","sym":"generic-fresnel","x":0,"y":0},{"kind":"camera","x":1,"y":0}]}"#);
    let plan = d.diagram(scene);
    assert!(plan.els.iter().all(|e| e.rig_on.is_empty()), "nothing rides a rug or a person");
    // Told by hand to ride itself, or a lamp: refused.
    edit(&mut d, scene, &format!(r#"{{"op":"update","ids":["{}"],"set":{{"rig_on":"{}"}}}}"#, made[2], made[2]));
    edit(&mut d, scene, &format!(r#"{{"op":"update","ids":["{}"],"set":{{"rig_on":"{}"}}}}"#, made[3], made[2]));
    let plan = d.diagram(scene);
    assert!(plan.els.iter().all(|e| e.rig_on.is_empty()));
    // Two frames told to ride each other: the loop is broken.
    let f = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"light","sym":"frame","x":8,"y":8,"h":2},{"kind":"light","sym":"frame","x":8,"y":8,"h":1}]}"#);
    let plan = d.diagram(scene);
    assert_eq!(plan.get(&f[1]).unwrap().rig_on, f[0]);
    edit(&mut d, scene, &format!(r#"{{"op":"update","ids":["{}"],"set":{{"rig_on":"{}"}}}}"#, f[0], f[1]));
    let plan = d.diagram(scene);
    assert!(plan.get(&f[0]).unwrap().rig_on.is_empty() || plan.get(&f[1]).unwrap().rig_on.is_empty());
}

#[test]
fn a_swap_changes_the_drawing_and_keeps_everything_that_is_his() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let made = edit(&mut d, scene, r##"{"op":"add","els":[{"kind":"cast","x":5,"y":0},{"kind":"light","sym":"generic-fresnel","x":1,"y":1,"rot":30,"label":"Key","color":"#FF0000","gels":["cto-half"],"path":[{"beat":2,"x":2,"y":2,"rot":40}]}]}"##);
    let (who, lamp) = (made[0].clone(), made[1].clone());
    edit(&mut d, scene, &format!(r#"{{"op":"update","ids":["{lamp}"],"set":{{"aim":"{who}"}}}}"#));
    let depth = d.undo_depth();
    edit(&mut d, scene, &format!(r#"{{"op":"swap","ids":["{lamp}"],"sym":"hmi-18k"}}"#));
    assert_eq!(d.undo_depth(), depth + 1, "one step");
    let l = el(&d, scene, &lamp);
    assert_eq!(l.sym, "hmi-18k");
    let want = shotlister_engine::diagram::symbols::find("hmi-18k").unwrap();
    assert_eq!((l.w, l.h, l.beam, l.kelvin), (want.w, want.h, want.beam, want.kelvin));
    assert_eq!((l.x, l.y, l.label.as_str(), l.color.as_str(), l.aim.as_str()), (1.0, 1.0, "Key", "#FF0000", who.as_str()));
    assert_eq!(l.gels, vec!["cto-half".to_string()]);
    assert_eq!(l.steps.len(), 1);
    // A lamp swapped for a sofa is a set piece now, where the lamp stood.
    edit(&mut d, scene, &format!(r#"{{"op":"swap","ids":["{lamp}"],"sym":"sofa"}}"#));
    let s = el(&d, scene, &lamp);
    assert_eq!((s.kind, s.sym.as_str(), s.x, s.label.as_str()), (Kind::Set, "sofa", 1.0, "Key"));
    // Undo, twice: the lamp as it was.
    d.undo().unwrap();
    d.undo().unwrap();
    let l = el(&d, scene, &lamp);
    assert_eq!((l.kind, l.sym.as_str()), (Kind::Light, "generic-fresnel"));
    // Something not in the library, or a camera: left alone.
    edit(&mut d, scene, &format!(r#"{{"op":"swap","ids":["{lamp}","{who}"],"sym":"no-such-thing"}}"#));
    assert_eq!(el(&d, scene, &lamp).sym, "generic-fresnel");
    edit(&mut d, scene, &format!(r#"{{"op":"swap","ids":["{who}"],"sym":"sofa"}}"#));
    assert_eq!(el(&d, scene, &who).kind, Kind::Cast);
}

#[test]
fn favorites_are_nine_slots_kept_with_the_film_and_put_down_anywhere() {
    use shotlister_engine::diagram::favorites;
    let mut d = doc();
    let one = d.create_scene("1");
    let two = d.create_scene("2");
    let made = edit(&mut d, one, r#"{"op":"add","els":[{"kind":"light","sym":"frame","x":4,"y":4,"rot":30,"h":3.6,"material":"silk","tilt":45,"gels":["cto-full"],"label":"Big Silk","path":[{"beat":2,"x":5,"y":5}]},{"kind":"arrow","x":1,"y":1,"x2":3,"y2":1}]}"#);
    assert_eq!(d.diagram_favorites().len(), 9);
    assert!(d.diagram_favorites().iter().all(|s| s.is_none()));
    let silk = el(&d, one, &made[0]);
    let depth = d.undo_depth();
    assert!(d.set_diagram_favorite(2, Some(&silk)));
    assert!(d.set_diagram_favorite(0, Some(&el(&d, one, &made[1]))));
    assert_eq!(d.undo_depth(), depth + 2);
    assert!(!d.set_diagram_favorite(9, Some(&silk)), "there are nine");
    let slots = d.diagram_favorites();
    let kept = slots[2].clone().expect("kept");
    assert_eq!(favorites::name(&kept), "Big Silk");
    for gone in ["\"x\"", "\"path\"", "\"rot\"", "\"id\""] {
        assert!(!kept.encode().contains(gone), "{gone} is not the slot's: {}", kept.encode());
    }
    // Put down on another scene's plan, where the pointer is.
    let el_json = favorites::placed(&kept, 10.0, -2.0).unwrap();
    let put = d.diagram_edit(two, &json::Json::object(vec![("op", json::Json::text("add")), ("els", json::Json::Array(vec![el_json]))])).unwrap();
    let p = el(&d, two, &put[0]);
    assert_eq!((p.x, p.y, p.h, p.material.as_str(), p.tilt), (10.0, -2.0, 3.6, "silk", 45.0));
    assert_eq!((p.gels.clone(), p.label.as_str(), p.steps.len()), (vec!["cto-full".to_string()], "Big Silk", 0));
    // A line comes centred on the pointer, as long as it was.
    let arrow = favorites::placed(slots[0].as_ref().unwrap(), 0.0, 0.0).unwrap();
    assert_eq!((arrow.get("x").and_then(|v| v.as_f64()), arrow.get("x2").and_then(|v| v.as_f64())), (Some(-1.0), Some(1.0)));
    // Kept in the film: another device sees them.
    let mut other = Doc::new(DeviceId(2));
    other.merge(d.changes().to_vec());
    assert_eq!(other.diagram_favorites()[2].as_ref().map(|j| j.encode()), Some(kept.encode()));
    // Emptied, and undone.
    d.set_diagram_favorite(2, None);
    assert!(d.diagram_favorites()[2].is_none());
    d.undo().unwrap();
    assert!(d.diagram_favorites()[2].is_some());
}

#[test]
fn a_camera_from_a_favorite_brings_its_own_shot() {
    use shotlister_engine::diagram::favorites;
    let mut d = doc();
    let scene = d.create_scene("1");
    let cam = edit(&mut d, scene, r##"{"op":"add","els":[{"kind":"camera","x":0,"y":0,"color":"#3D7BD9","lens":35,"shot":"123"}]}"##)[0].clone();
    let kept = favorites::keep(&el(&d, scene, &cam));
    assert!(!kept.encode().contains("123"), "not its shot");
    let op = json::Json::object(vec![("op", json::Json::text("add")), ("els", json::Json::Array(vec![favorites::placed(&kept, 2.0, 2.0).unwrap()]))]);
    let made = d.diagram_edit(scene, &op).unwrap();
    let c = el(&d, scene, &made[0]);
    assert!(!c.shot.is_empty() && c.shot != "123", "a shot of its own: {}", c.shot);
    assert_eq!((c.color.as_str(), c.lens), ("#3D7BD9", 35.0));
}

#[test]
fn with_snap_off_a_lamp_set_over_a_table_does_not_get_on() {
    let mut d = doc();
    let scene = d.create_scene("1");
    edit(&mut d, scene, r#"{"op":"settings","set":{"snap":false}}"#);
    let made = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"set","sym":"table","x":1,"y":1,"w":1.2,"h":0.8},{"kind":"light","sym":"generic-fresnel","x":1,"y":1}]}"#);
    assert_eq!(el(&d, scene, &made[1]).rig_on, "");
    // Snap back on, and set down again: on.
    edit(&mut d, scene, r#"{"op":"settings","set":{"snap":true}}"#);
    edit(&mut d, scene, &format!(r#"{{"op":"move","ids":["{}"],"dx":0.1,"dy":0}}"#, made[1]));
    assert_eq!(el(&d, scene, &made[1]).rig_on, made[0]);
}

// ---- groups carry a name (2026-09-28: groups as folders in Layers) ----

#[test]
fn a_group_is_named_renamed_and_forgotten() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let made = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"set","sym":"sofa","x":0,"y":0},{"kind":"set","sym":"sofa","x":2,"y":0},{"kind":"set","sym":"sofa","x":4,"y":0},{"kind":"set","sym":"sofa","x":6,"y":0}]}"#);
    let names = |d: &Doc| d.diagram(scene).els.iter().map(|e| e.group_name.clone()).collect::<Vec<_>>();
    edit(&mut d, scene, &format!(r#"{{"op":"group","ids":["{}","{}"]}}"#, made[0], made[1]));
    edit(&mut d, scene, &format!(r#"{{"op":"group","ids":["{}","{}"]}}"#, made[2], made[3]));
    assert_eq!(names(&d), vec!["Group 1", "Group 1", "Group 2", "Group 2"]);
    edit(&mut d, scene, &format!(r#"{{"op":"update","ids":["{}","{}"],"set":{{"group_name":"Dolly"}}}}"#, made[0], made[1]));
    assert_eq!(names(&d)[..2], ["Dolly", "Dolly"]);
    edit(&mut d, scene, &format!(r#"{{"op":"ungroup","ids":["{}"]}}"#, made[0]));
    assert_eq!(names(&d), vec!["", "", "Group 2", "Group 2"], "ungroup takes the whole group and its name");
    assert!(d.diagram(scene).els[..2].iter().all(|e| e.group.is_empty()));
}

#[test]
fn two_steps_joined_are_one_undo() {
    // A burst of arrow presses, or an ⌥-drag's copy and its move: the shell
    // asks for the second edit to join the first.
    let mut d = doc();
    let scene = d.create_scene("1");
    let made = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"set","sym":"sofa","x":1}]}"#);
    let depth = d.undo_depth();
    for _ in 0..3 {
        edit(&mut d, scene, &format!(r#"{{"op":"move","ids":["{}"],"dx":0.1,"dy":0}}"#, made[0]));
    }
    assert!(d.join_last_steps());
    assert!(d.join_last_steps());
    assert_eq!(d.undo_depth(), depth + 1, "three nudges, one step");
    assert!((d.diagram(scene).get(&made[0]).unwrap().x - 1.3).abs() < 1e-9);
    d.undo();
    assert_eq!(d.diagram(scene).get(&made[0]).unwrap().x, 1.0, "one undo takes all three back");
    d.redo();
    assert!((d.diagram(scene).get(&made[0]).unwrap().x - 1.3).abs() < 1e-9);
}

#[test]
fn a_room_added_as_a_group_is_one_group_named_room() {
    let mut d = doc();
    let scene = d.create_scene("1");
    edit(
        &mut d,
        scene,
        r#"{"op":"add","group_name":"Room","els":[{"kind":"wall","x2":3},{"kind":"wall","x":3,"x2":3,"y2":3},{"kind":"wall","x":3,"y":3,"y2":3},{"kind":"wall","y":3}]}"#,
    );
    let plan = d.diagram(scene);
    let g = &plan.els[0].group;
    assert!(!g.is_empty());
    assert!(plan.els.iter().all(|e| &e.group == g && e.group_name == "Room"), "{:?}", plan.els);
}

#[test]
fn undo_says_what_it_undid() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let made = edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"light","sym":"generic-fresnel","x":1}]}"#);
    assert_eq!(d.undo_label(), Some("Add Light"));
    let l = &made[0];
    edit(&mut d, scene, &format!(r#"{{"op":"update","ids":["{l}"],"set":{{"w":1,"h":1,"x":1,"y":0}}}}"#));
    assert_eq!(d.undo_label(), Some("Resize"));
    edit(&mut d, scene, &format!(r#"{{"op":"update","ids":["{l}"],"set":{{"rot":90}}}}"#));
    assert_eq!(d.undo_label(), Some("Turn"));
    // A turn that lets go of an aim is still a Turn.
    edit(&mut d, scene, &format!(r#"{{"op":"batch","ops":[{{"op":"update","ids":["{l}"],"set":{{"aim":""}}}},{{"op":"update","ids":["{l}"],"set":{{"rot":45}}}}]}}"#));
    assert_eq!(d.undo_label(), Some("Turn"));
    edit(&mut d, scene, &format!(r#"{{"op":"update","ids":["{l}"],"set":{{"locked":true}}}}"#));
    assert_eq!(d.undo_label(), Some("Lock"));
    edit(&mut d, scene, &format!(r#"{{"op":"update","ids":["{l}"],"set":{{"kelvin":5600}}}}"#));
    assert_eq!(d.undo_label(), Some("Change Light"));
    edit(&mut d, scene, r#"{"op":"add","els":[{"kind":"light","sym":"generic-flag"}]}"#);
    assert_eq!(d.undo_label(), Some("Add Grip"));
    let outcome = d.undo().expect("something to undo");
    assert_eq!(outcome.label, "Add Grip");
}
