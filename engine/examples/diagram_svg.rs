//! Write the sample diagram as a page, for looking at while building:
//! `cargo run --example diagram_svg -- out.html [beat] [plan.json] [picked-id] [x1,y1,x2,y2] [width]`
//! — the last, metres, to show just that box (a symbol sheet's cells).
fn main() {
    use shotlister_engine::diagram::{render, sample, svg};
    let out = std::env::args().nth(1).unwrap_or_else(|| "diagram.html".into());
    let beat: u32 = std::env::args().nth(2).and_then(|b| b.parse().ok()).unwrap_or(1);
    // A plan of one's own instead of the sample, and what is picked on it.
    let d = match std::env::args().nth(3) {
        Some(p) => shotlister_engine::diagram::Diagram::parse(&std::fs::read_to_string(p).unwrap()),
        None => sample(),
    };
    let pick = std::env::args().nth(4).unwrap_or_else(|| "cA".into());
    let area = std::env::args().nth(5).and_then(|a| {
        let v: Vec<f64> = a.split(',').filter_map(|n| n.trim().parse().ok()).collect();
        (v.len() == 4).then(|| shotlister_engine::diagram::Aabb { x1: v[0], y1: v[1], x2: v[2], y2: v[3] })
    });
    let width: f64 = std::env::args().nth(6).and_then(|w| w.parse().ok()).unwrap_or(1100.0);
    let pic = svg::svg(
        &d,
        &render::Context::default(),
        &render::Options { beat, tween: 0.0, sel: vec![pick], paper: false, scale: 0.0, typing: String::new(), page: false },
        &svg::Frame { width, area, max_scale: if area.is_some() { 1e6 } else { svg::Frame::default().max_scale }, scale_bar: area.is_none(), margin: if area.is_some() { 4.0 } else { svg::Frame::default().margin }, ..Default::default() },
        "s",
    );
    std::fs::write(&out, format!("<!doctype html><html><body style=\"margin:0\">{pic}</body></html>")).unwrap();
}
