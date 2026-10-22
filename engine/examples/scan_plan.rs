//! Lay a room scan on an empty plan and write it as a picture, for checking
//! what Room from Scan makes of a real room without opening a film:
//! `cargo run --example scan_plan -- RoomScan.json out.svg [ft|m]`.
fn main() {
    use shotlister_engine::diagram::{import_room, render, svg, Diagram};
    let scan = std::env::args().nth(1).expect("a RoomScan .json");
    let out = std::env::args().nth(2).unwrap_or_else(|| "scan.svg".into());
    let units = std::env::args().nth(3).unwrap_or_else(|| "ft".into());
    let plan = shotlister_engine::room::read(&std::fs::read_to_string(&scan).unwrap()).expect("a room in it");
    let mut d = Diagram::parse(&format!(r#"{{"settings":{{"units":"{units}"}},"els":[]}}"#));
    import_room(&mut d, &plan, "scan");
    let pic = svg::svg(
        &d,
        &render::Context::default(),
        &render::Options { beat: 1, tween: 0.0, sel: vec![], paper: true, scale: 0.0, typing: String::new(), page: false },
        &svg::Frame { width: 1400.0, ..Default::default() },
        "s",
    );
    // The inks by name, filled in, so any picture program reads it.
    let mut pic = pic;
    for (role, hex) in svg::PAPER.iter() {
        pic = pic.replace(&format!("var(--d-{role})"), hex);
    }
    std::fs::write(&out, pic).unwrap();
    eprintln!("{} pieces", d.els.len());
    for e in &d.els {
        eprintln!("  {} {} w={:.2} slide={} hinge={} label={:?}", e.kind.as_str(), e.sym, e.w, e.slide, e.hinge, e.label);
    }
}
