//! Zoom marks on one sheet, as SVG on stdout: In and Out, a few sizes and
//! looks, an off-centre one.
//!
//!     cargo run -q --example zoomgrid > /tmp/zoom.svg && magick /tmp/zoom.svg /tmp/zoom.png
use shotlister_engine::arrow::{Arrow, ArrowLook, ZoomDir};
use std::fmt::Write;

fn cell(out: &mut String, x: f64, y: f64, label: &str, a: Arrow) {
    let (w, h) = (480.0, 270.0);
    write!(out, "<g transform=\"translate({x},{y})\"><rect width=\"{w}\" height=\"{h}\" fill=\"#4a525b\"/>").unwrap();
    out.push_str(&a.svg(w, h));
    write!(out, "<text x=\"8\" y=\"18\" font-family=\"Helvetica\" font-size=\"14\" fill=\"#fff\">{label}</text></g>").unwrap();
}

fn main() {
    let mut out = String::new();
    let (cw, ch) = (490.0, 280.0);
    let (tw, th) = (3.0 * cw + 10.0, 2.0 * ch + 10.0);
    write!(out, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{tw}\" height=\"{th}\" viewBox=\"0 0 {tw} {th}\"><rect width=\"100%\" height=\"100%\" fill=\"#111\"/>").unwrap();
    let mut cells: Vec<(String, Arrow)> = Vec::new();
    for dir in [ZoomDir::In, ZoomDir::Out] {
        cells.push((format!("Zoom {}", dir.name()), Arrow::zoom_mark(dir)));
    }
    let mut dark = Arrow::zoom_mark(ZoomDir::In); dark.look = ArrowLook::Dark; dark.thickness = 1.5;
    cells.push(("In, dark, thickness 1.5".into(), dark));
    let mut red = Arrow::zoom_mark(ZoomDir::Out); red.look = ArrowLook::Red; red.thickness = 0.6;
    cells.push(("Out, red, thickness 0.6".into(), red));
    let mut big = Arrow::zoom_mark(ZoomDir::In); big.x1 = 0.08; big.y1 = 0.08; big.x2 = 0.92; big.y2 = 0.92; big.thickness = 2.0;
    cells.push(("In, large frame, thickness 2".into(), big.held()));
    let mut off = Arrow::zoom_mark(ZoomDir::Out); off.x1 = 0.5; off.y1 = 0.45; off.x2 = 0.8; off.y2 = 0.75;
    cells.push(("Out, small, off-centre".into(), off.held()));
    for (i, (label, a)) in cells.iter().enumerate() {
        cell(&mut out, 5.0 + (i % 3) as f64 * cw, 5.0 + (i / 3) as f64 * ch, label, a.clone());
    }
    out.push_str("</svg>");
    println!("{out}");
}
