//! The Labs lighting plot's links kept through the film: a label made in the
//! same edit that ties lamps to it must keep them tied once saved, when the
//! label's temporary id becomes its record id.

use shotlister_engine::diagram::{render, Kind};
use shotlister_engine::json;
use shotlister_engine::{DeviceId, Doc};

#[test]
fn a_shared_label_keeps_its_lamps_once_saved() {
    let mut doc = Doc::new(DeviceId(1));
    doc.create_project("Call Her Back");
    let scene = doc.create_scene("1");
    doc.diagram_edit(
        scene,
        &json::parse(r#"{"op":"add","els":[{"kind":"light","sym":"","mark":"chevron","x":0,"y":0},{"kind":"light","sym":"","mark":"chevron","x":6,"y":0}]}"#).unwrap(),
    )
    .unwrap();
    let lamps: Vec<String> = doc.diagram(scene).els.iter().map(|e| e.id.clone()).collect();
    let made = doc
        .diagram_edit(scene, &json::parse(&format!(r#"{{"op":"share_label","ids":["{}","{}"]}}"#, lamps[0], lamps[1])).unwrap())
        .unwrap();
    let plan = doc.diagram(scene);
    let label = plan.els.iter().find(|e| e.kind == Kind::Text).expect("a label").id.clone();
    assert_eq!(made, vec![label.clone()], "the edit answers the label's real id");
    assert!(plan.els.iter().filter(|e| e.kind == Kind::Light).all(|e| e.tie_to == label), "both lamps tied to the saved label");
    let shapes = render::render(&plan, &doc.diagram_context(scene), &render::Options::default());
    // A trunk to one junction, then a line to each lamp, a dot on each end
    // (2026-10-17): two ends, besides the junction's dot.
    let dots = shapes.iter().filter(|s| s.el == label && s.part == "tie" && s.fill != render::Ink::None).count();
    assert_eq!(dots, 3);
}
