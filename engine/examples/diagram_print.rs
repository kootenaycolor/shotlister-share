//! The diagram page as printed, for looking at: `cargo run --example diagram_print -- out.html [dark]`.
fn main() {
    use shotlister_engine::{diagram::print, json, DeviceId, Doc};
    let out = std::env::args().nth(1).unwrap_or_else(|| "print.html".into());
    let dark = std::env::args().nth(2).as_deref() == Some("dark");
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Call Her Back");
    let scene = d.create_scene("12");
    let plan = shotlister_engine::diagram::sample();
    let els: Vec<_> = plan.els.iter().map(|e| e.to_json()).collect();
    d.diagram_edit(scene, &json::Json::object(vec![("op", json::Json::text("add")), ("els", json::Json::Array(els))])).unwrap();
    let page = print::page(&d, &[scene], print::Show { dark, ..Default::default() }, "Call Her Back", &|_| None);
    std::fs::write(&out, page).unwrap();
}
