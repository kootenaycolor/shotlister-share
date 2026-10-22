//! The sample plan with the sun on, for looking at north and the sun while
//! building: `cargo run --example diagram_sun -- out.html north time [rays] [paper] [dark]`.
//! Place: Los Angeles, 2026-09-22.
fn main() {
    use shotlister_engine::diagram::{render, sample, svg};
    let arg = |n: usize| std::env::args().nth(n);
    let out = arg(1).unwrap_or_else(|| "sun.html".into());
    let mut d = sample();
    d.settings.north = arg(2).and_then(|n| n.parse().ok()).unwrap_or(0.0);
    d.settings.sun = true;
    d.settings.sun_date = "2026-09-22".into();
    d.settings.sun_time = arg(3).unwrap_or_else(|| "15:30".into());
    d.settings.sun_rays = arg(4).as_deref() == Some("rays");
    let paper = arg(5).as_deref() == Some("paper");
    let ctx = render::Context { place: Some((34.05, -118.25)), utc_offset: Some(-420.0), ..Default::default() };
    let pic = svg::svg(
        &d,
        &ctx,
        &render::Options { beat: 1, tween: 0.0, sel: Vec::new(), paper, scale: 0.0, typing: String::new(), page: false },
        &svg::Frame { width: 1100.0, fades: !paper, ..Default::default() },
        "s",
    );
    // Dark: the portal's palette, the way the PDF's Dark switch sets it.
    let vars: String = if arg(6).as_deref() == Some("dark") {
        svg::DARK.iter().map(|(r, c)| format!("--dia-{r}:{c};")).collect()
    } else {
        String::new()
    };
    std::fs::write(&out, format!("<!doctype html><html><body style=\"margin:0;{vars}\">{pic}</body></html>")).unwrap();
}
