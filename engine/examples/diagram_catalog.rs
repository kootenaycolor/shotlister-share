//! Every library drawing as a tile with its name, the way the library panel
//! shows them: `cargo run --example diagram_catalog -- out.html [dark] [group-word]`.
fn main() {
    use shotlister_engine::diagram::{render, svg, symbols, Diagram, El, Kind};
    let out = std::env::args().nth(1).unwrap_or_else(|| "catalog.html".into());
    let dark = std::env::args().nth(2).as_deref() == Some("dark");
    let only = std::env::args().nth(3).unwrap_or_default().to_lowercase();
    let vars = if dark { svg::DARK.iter().map(|(r, c)| format!("--dia-{r}:{c};")).collect::<String>() } else { String::new() };
    let mut tiles = String::new();
    for s in symbols::CATALOG.iter().filter(|s| only.is_empty() || s.group.to_lowercase().contains(&only)) {
        let mut d = Diagram::default();
        let mut e = El::new(if s.light { Kind::Light } else { Kind::Set }, "a");
        e.sym = s.id.into();
        // Blown up to fill the tile: the plan frames at least two metres.
        let k = 4.0 / s.w.max(s.h);
        e.w = s.w * k;
        e.h = s.h * k;
        e.beam_on = false;
        if s.light {
            e.rot = 270.0;
        }
        d.els.push(e);
        d.settings.grid = false;
        d.settings.labels = false;
        let pic = svg::svg(&d, &render::Context::default(), &render::Options::default(), &svg::Frame { width: 150.0, margin: 12.0, scale_bar: false, max_scale: 2000.0, max_height: Some(120.0), ..Default::default() }, "t");
        tiles.push_str(&format!("<div class=t><div class=p>{pic}</div><div class=n>{}</div><div class=g>{}</div></div>", s.name, s.group));
    }
    let bg = if dark { "#141414" } else { "#fff" };
    let fg = if dark { "#ddd" } else { "#222" };
    std::fs::write(&out, format!("<!doctype html><html><head><style>body{{margin:0;background:{bg};color:{fg};font:11px -apple-system,sans-serif;{vars}}}.w{{display:flex;flex-wrap:wrap;gap:6px;padding:10px}}.t{{width:150px}}.p{{height:120px;display:flex;align-items:center;justify-content:center}}.p svg{{max-width:150px;max-height:120px}}.n{{text-align:center;margin-top:2px}}.g{{text-align:center;opacity:.5;font-size:9px}}</style></head><body><div class=w>{tiles}</div></body></html>")).unwrap();
}
