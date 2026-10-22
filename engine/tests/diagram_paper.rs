//! Back to Paper, Batch 1 (his calls, 2026-10-04): a plan not begun starts
//! with its measurements off, and a plan stored before keeps every value it
//! was left with.

use shotlister_engine::diagram::render;
use shotlister_engine::json;
use shotlister_engine::{f, DeviceId, Doc, Id, Value};

fn edit(doc: &mut Doc, scene: Id, op: &str) {
    doc.diagram_edit(scene, &json::parse(op).unwrap()).unwrap();
}

fn stored(doc: &Doc, scene: Id) -> Option<String> {
    doc.get(scene).and_then(|r| r.text(f::DIAGRAM)).map(|t| t.to_string())
}

#[test]
fn a_new_plan_starts_with_its_measurements_off_and_keeps_them_off() {
    let mut doc = Doc::new(DeviceId(1));
    doc.create_project("Let's Bake");
    let scene = doc.create_scene("8");
    assert!(!doc.diagram(scene).settings.dims, "a plan not begun is quiet");
    edit(&mut doc, scene, r#"{"op":"add","els":[{"kind":"wall","x":0,"y":0,"x2":3,"y2":0}]}"#);
    assert!(!doc.diagram(scene).settings.dims, "drawn on, it stays quiet");
    assert!(stored(&doc, scene).unwrap_or_default().contains(r#""dims":false"#), "written with its first edit");
    // Undone, the plan is not begun again — and still quiet.
    doc.undo();
    assert!(doc.diagram(scene).els.is_empty());
    assert!(!doc.diagram(scene).settings.dims);
    // Turned on, it stays on.
    edit(&mut doc, scene, r#"{"op":"add","els":[{"kind":"wall","x":0,"y":0,"x2":3,"y2":0}]}"#);
    edit(&mut doc, scene, r#"{"op":"settings","set":{"dims":true}}"#);
    assert!(doc.diagram(scene).settings.dims);
    // A loose plan starts the same way.
    let plan = doc.add_plan("Floor", None);
    assert!(!doc.diagram(plan).settings.dims);
}

#[test]
fn a_plan_stored_before_opens_as_it_was_left() {
    let mut doc = Doc::new(DeviceId(1));
    doc.create_project("Let's Bake");
    let scene = doc.create_scene("8");
    edit(
        &mut doc,
        scene,
        r##"{"op":"add","els":[{"kind":"wall","x":0,"y":0,"x2":3,"y2":0},{"kind":"light","sym":"fso-litemat-8","x":1,"y":1,"w":1.6,"h":1.6,"label":"Soft Overhead Source on Menace Arm","label_size":14,"label_bold":false,"opacity":0.38,"color":"#E5484D"}]}"##,
    );
    // As a plan made before Back to Paper was stored: pieces, and no
    // settings of its own — its lengths were on.
    doc.set(scene, f::DIAGRAM, Value::Null);
    assert!(stored(&doc, scene).is_none());
    assert!(doc.diagram(scene).settings.dims, "an old plan keeps its lengths");
    // Edited, it writes no settings it did not change — only the marks
    // that its lights now carry their own names (2026-10-05), that a
    // unit's name is written on as a label (2026-10-15) and that every
    // piece's words are typed ones (2026-10-17).
    let wall = doc.diagram(scene).els[0].id.clone();
    edit(&mut doc, scene, &format!(r#"{{"op":"move","ids":["{wall}"],"dx":1,"dy":0}}"#));
    assert_eq!(stored(&doc, scene).as_deref(), Some(r#"{"settings":{"lamp_names":true,"typed_labels":true,"free_names":true}}"#));
    assert!(doc.diagram(scene).settings.dims);
    // Its own settings, as stored, as they were.
    doc.set(scene, f::DIAGRAM, r##"{"settings":{"colours":{"plan":"#1A1A1A"}}}"##);
    let plan = doc.diagram(scene);
    assert!(plan.settings.dims);
    assert_eq!(plan.settings.colours, vec![("plan".to_string(), "#1A1A1A".to_string())]);
    // Every value on its lamp kept, though it is drawn in ink, one size.
    let lamp = plan.els.iter().find(|e| e.sym == "fso-litemat-8").unwrap();
    assert_eq!((lamp.label_size, lamp.label_bold, lamp.opacity, lamp.color.as_str()), (14.0, false, 0.38, "#E5484D"));
    let shapes = render::render(&plan, &doc.diagram_context(scene), &render::Options::default());
    assert!(shapes.iter().any(|s| s.el == lamp.id && s.part == "label"));
    assert!(shapes.iter().any(|s| s.el == wall && s.stroke == render::Ink::hex("#1A1A1A")), "his walls' colour still wins");
}

#[test]
fn a_days_diagram_page_holds_only_that_days_scenes() {
    // Ref 1503: a per-day export gave every day every scene's plan.
    use shotlister_engine::diagram::print::{self, Show};
    let mut doc = Doc::new(DeviceId(1));
    doc.create_project("Let's Bake");
    let (monday, tuesday, loose) = (doc.create_day(), doc.create_day(), doc.create_day());
    let mut scenes = Vec::new();
    for n in ["7", "8", "9"] {
        let scene = doc.create_scene(n);
        doc.add_shot_to_scene(scene);
        edit(&mut doc, scene, r#"{"op":"add","els":[{"kind":"wall","x":0,"y":0,"x2":3,"y2":0}]}"#);
        scenes.push(scene);
    }
    let on = |doc: &Doc, scene: Id| doc.placements_in_scene(scene)[0];
    let (p7, p8) = (on(&doc, scenes[0]), on(&doc, scenes[1]));
    doc.schedule(p7, monday);
    doc.schedule(p8, tuesday);
    // Scene 9's shot is on no day.
    assert_eq!(print::scenes_for_day(&doc, Some(monday)), vec![scenes[0]]);
    assert_eq!(print::scenes_for_day(&doc, Some(tuesday)), vec![scenes[1]]);
    assert_eq!(print::scenes_for_day(&doc, None), vec![scenes[2]]);
    let sheets = |html: &str| html.matches("class=\"sheet fresh-page\"").count();
    let none = |_: &str| None;
    assert_eq!(sheets(&print::page_for_day(&doc, Some(monday), Show::default(), &none)), 1);
    assert_eq!(sheets(&print::page(&doc, &[], Show::default(), "", &none)), 3, "no ask is every scene");
    // A day with nothing planned is an empty page, not every scene.
    let empty = print::page_for_day(&doc, Some(loose), Show::default(), &none);
    assert_eq!(sheets(&empty), 0);
    assert!(empty.contains("No diagrams yet"));
}

#[test]
fn export_carries_the_clock_the_screen_draws_the_sun_by() {
    // Ref 1576: Export sent no zone, so a place the longitude does not give
    // (the mountains, Mountain) read its sun an hour off the screen's.
    use shotlister_engine::diagram::{print::Show, sheet};
    let mut doc = Doc::new(DeviceId(1));
    doc.create_project("Let's Bake");
    let scene = doc.create_scene("8");
    let said = Show { tz: Some(-420.0), ..Default::default() }.ask();
    assert_eq!(said.tz, Some(-420.0));
    assert_eq!(sheet::plan_for(&doc, scene, &said).1.utc_offset, Some(-420.0));
    assert_eq!(sheet::plan_for(&doc, scene, &Show::default().ask()).1.utc_offset, None, "no zone sent, none made up");
}
