//! How long a big plan takes to draw and to send: `cargo run --release --example diagram_speed`.
fn main() {
    use shotlister_engine::diagram::{render, wire, Diagram, El, Kind};
    let mut d = Diagram::default();
    let kinds = [Kind::Wall, Kind::Set, Kind::Camera, Kind::Cast, Kind::Light, Kind::Text, Kind::Arrow];
    for i in 0..400 {
        let k = kinds[i % kinds.len()];
        let mut e = El::new(k, &format!("e{i}"));
        e.x = (i % 20) as f64;
        e.y = (i / 20) as f64;
        e.x2 = e.x + 1.5;
        e.y2 = e.y;
        e.sym = if k == Kind::Light { "fresnel".into() } else { "sofa".into() };
        e.text = "Words".into();
        if k == Kind::Cast { e.steps.push(shotlister_engine::diagram::Step { x: e.x + 1.0, y: e.y, rot: 0.0, pose: Default::default(), turn: false, beat: 2 }); }
        d.els.push(e);
    }
    let ctx = render::Context::default();
    let t = std::time::Instant::now();
    let mut shapes = 0;
    for _ in 0..20 {
        shapes = render::render(&d, &ctx, &render::Options::default()).len();
    }
    let draw = t.elapsed() / 20;
    let t = std::time::Instant::now();
    let mut bytes = 0;
    for _ in 0..20 {
        bytes = wire::payload(&d, &ctx, &render::Options::default()).len();
    }
    let send = t.elapsed() / 20;
    println!("400 elements: {shapes} shapes, drawn in {draw:?}, sent as {bytes} bytes in {send:?}");
}
