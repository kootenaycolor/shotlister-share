//! The portal's Diagram keeps up with the Mac's (2026-10-01): its library
//! reads whole, a wall drawn corner by corner and its corner edits are kept
//! and taken back, a snap answers the line-ups it found, and the plan's
//! Wall Lengths setting comes back with the rest.
use shotlister_engine::json::{parse, Json};
use shotlister_engine::{DeviceId, Doc};
use shotlister_web::{plan_edit_in, plan_library_json, plan_view, plan_where_in};

fn edit(doc: &mut Doc, scene: &str, op: &str) -> Json {
    let said = plan_edit_in(doc, &format!(r#"{{"scene":"{scene}","op":{op}}}"#));
    let got = parse(&said).unwrap();
    assert!(got.get("error").is_none(), "{op}: {said}");
    got
}

fn undo(doc: &mut Doc, scene: &str, got: &Json) {
    for op in got.get("undo").unwrap().as_array().unwrap() {
        edit(doc, scene, &op.encode());
    }
}

#[test]
fn the_library_reads_as_one_object() {
    // It once ended `}}` and both braces were trimmed: the page could not
    // read it and every library tile was blank.
    let lib = parse(&plan_library_json()).expect("the library is JSON");
    assert!(lib.get("symbols").and_then(|s| s.as_array()).map(|s| !s.is_empty()).unwrap_or(false));
    assert!(lib.get("frames").and_then(|f| f.get("materials")).is_some(), "a frame's skins");
    assert!(lib.get("cameras").and_then(|c| c.as_array()).map(|c| !c.is_empty()).unwrap_or(false), "camera bodies");
    assert!(lib.get("kinds").and_then(|k| k.get("grip")).is_some(), "the Grip library's sections");
    assert!(lib.get("gels").is_some() && lib.get("frame").is_some());
    let grip = lib.get("symbols").unwrap().as_array().unwrap().iter().filter(|s| s.str_field("lib") == "grip").count();
    assert!(grip > 0, "grip pieces under Grip");
}

#[test]
fn a_wall_drawn_corner_by_corner_is_one_wall_and_comes_back() {
    let mut doc = Doc::new(DeviceId(7));
    doc.create_project("Test");
    let id = doc.create_scene("1");
    let s = id.0.to_string();
    let made = edit(&mut doc, &s, r#"{"op":"add","els":[{"kind":"wall","x":0,"y":0,"x2":4,"y2":0}]}"#);
    let w = made.get("made").unwrap().as_array().unwrap()[0].as_str().unwrap().to_string();
    let start = doc.diagram(id).to_json().encode();
    let mut steps = Vec::new();
    for op in [
        format!(r#"{{"op":"wall_extend","id":"{w}","end":"end","x":4,"y":3}}"#),
        format!(r#"{{"op":"wall_extend","id":"{w}","end":"end","x":0,"y":3}}"#),
        format!(r#"{{"op":"update","ids":["{w}"],"set":{{"closed":true}}}}"#),
        format!(r#"{{"op":"wall_insert","id":"{w}","stretch":0}}"#),
        format!(r#"{{"op":"wall_corner","id":"{w}","corner":1,"x":2,"y":-1}}"#),
        format!(r#"{{"op":"wall_round","id":"{w}","corner":1,"round":true}}"#),
        format!(r#"{{"op":"wall_break","id":"{w}","corner":3}}"#),
    ] {
        steps.push(edit(&mut doc, &s, &op));
    }
    let plan = doc.diagram(id);
    assert_eq!(plan.els.len(), 1, "one wall, not a stick per stretch");
    assert!(!plan.els[0].closed, "broken open");
    for got in steps.iter().rev() {
        undo(&mut doc, &s, got);
    }
    assert_eq!(doc.diagram(id).to_json().encode(), start, "every step taken back");
}

#[test]
fn a_snap_answers_its_line_ups_and_the_page_draws_its_own_grid() {
    let mut doc = Doc::new(DeviceId(7));
    doc.create_project("Test");
    let id = doc.create_scene("1");
    let s = id.0.to_string();
    edit(&mut doc, &s, r#"{"op":"add","els":[{"kind":"wall","x":0,"y":0,"x2":4,"y2":0}]}"#);
    // Near x = 4 but well off the wall: lined up with its corner, a guide to it.
    let said = parse(&plan_where_in(&doc, &format!(r#"{{"scene":"{s}","what":"snap","x":4.05,"y":2.6,"reach":0.2,"step":0.3048}}"#))).unwrap();
    assert!((said.get("sx").unwrap().as_f64().unwrap() - 4.0).abs() < 1e-9, "lined up across");
    assert!(!said.get("guides").unwrap().as_array().unwrap().is_empty(), "the line-up is said");
    // With no corner near, the grid of the step asked for.
    let free = parse(&plan_where_in(&doc, &format!(r#"{{"scene":"{s}","what":"snap","x":1.9,"y":2.6,"reach":0.05,"step":0.5}}"#))).unwrap();
    assert!((free.get("sx").unwrap().as_f64().unwrap() - 2.0).abs() < 1e-9);
    // A door near the wall lands in it, how far from the corner said.
    let door = parse(&plan_where_in(&doc, &format!(r#"{{"scene":"{s}","what":"wall","x":1.2,"y":0.1,"reach":0.4,"w":0.9,"step":0.3048}}"#))).unwrap();
    assert!(door.get("from").and_then(|f| f.as_f64()).is_some());
    // Wall Lengths: All comes back among the settings, so an undo can put it back.
    edit(&mut doc, &s, r#"{"op":"settings","set":{"all_lengths":true}}"#);
    let view = parse(&plan_view(&doc, &format!(r#"{{"scene":"{s}","width":800,"height":600,"grid_step":0.0762}}"#))).unwrap();
    assert_eq!(view.get("settings").unwrap().get("all_lengths").and_then(|b| b.as_bool()), Some(true));
    assert!((view.get("settings").unwrap().get("step").unwrap().as_f64().unwrap() - 0.3048).abs() < 1e-9, "the plan keeps its own step");
}
