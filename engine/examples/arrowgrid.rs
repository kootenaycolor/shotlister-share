//! **Every kind of arrow on one sheet**, as SVG on stdout — the engine's own
//! `Arrow::svg`, which the printed page and the portal draw. For looking at a
//! change to the arrow's shape with your own eyes:
//!
//!     cargo run -q --example arrowgrid > /tmp/arrows.svg
//!     qlmanage -t -s 1480 -o /tmp /tmp/arrows.svg   # WebKit draws the outlines
//!
//! (ImageMagick's own SVG reader drops the outlines.) The sheet is square
//! because Quick Look fits the height.
use shotlister_engine::arrow::{Arrow, ArrowDepth, ArrowLook, ArrowShape, ArrowStance};
use std::fmt::Write;

const CW: f64 = 490.0;
const CH: f64 = 280.0;

fn cell(out: &mut String, col: f64, row: f64, label: &str, arrows: &[Arrow]) {
    let (x, y) = (5.0 + col * CW, 5.0 + row * CH);
    let (w, h) = (480.0, 270.0);
    write!(out, "<g transform=\"translate({x},{y})\"><rect width=\"{w}\" height=\"{h}\" fill=\"url(#g)\"/>").unwrap();
    for a in arrows {
        out.push_str(&a.svg(w, h));
    }
    write!(out, "<text x=\"8\" y=\"18\" font-family=\"Helvetica\" font-size=\"14\" fill=\"#fff\">{label}</text></g>").unwrap();
}

fn deep(points: &[(f64, f64)], depth: ArrowDepth, stance: ArrowStance) -> Arrow {
    let mut a = Arrow::through(points).unwrap();
    a.depth = depth;
    a.stance = stance;
    a
}

/// Up the frame for Away (near is lower), down it for Toward.
fn column(len: f64, depth: ArrowDepth, stance: ArrowStance, thick: f64, x: f64) -> Arrow {
    let (a, b) = (0.5 + len / 2.0, 0.5 - len / 2.0);
    let mut arrow = if depth == ArrowDepth::Toward { deep(&[(x, b), (x, a)], depth, stance) } else { deep(&[(x, a), (x, b)], depth, stance) };
    arrow.thickness = thick;
    arrow
}

fn main() {
    let sheet = std::env::args().nth(1).unwrap_or_default();
    let mut out = String::new();
    let side = if sheet == "floor" || sheet == "standing" { 8.0 * CH + 10.0 } else { 3.0 * CW + 10.0 };
    write!(out, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{side}\" height=\"{side}\"><defs><linearGradient id=\"g\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"#56606b\"/><stop offset=\"1\" stop-color=\"#2b2f33\"/></linearGradient></defs><rect width=\"100%\" height=\"100%\" fill=\"#111\"/>").unwrap();
    let lens = [0.08, 0.16, 0.3, 0.55, 0.85];
    match sheet.as_str() {
        // `cargo run --example arrowgrid floor` / `standing`: short to long,
        // Away then Toward, at thickness 0.6, 1 and 2.
        "floor" | "standing" => {
            let stance = if sheet == "floor" { ArrowStance::Floor } else { ArrowStance::Standing };
            for (r, d) in [ArrowDepth::Away, ArrowDepth::Toward].iter().enumerate() {
                for (c, t) in [0.6, 1.0, 2.0].iter().enumerate() {
                    let v: Vec<Arrow> = lens.iter().enumerate().map(|(i, l)| column(*l, *d, stance, *t, 0.1 + i as f64 * 0.2)).collect();
                    cell(&mut out, c as f64, r as f64, &format!("{} {} · thickness {t}", stance.name(), d.name()), &v);
                }
            }
            // Hand-set widths at each thickness: thin shaft and wide head,
            // fat shaft and small head.
            for (c, t) in [0.6, 1.0, 2.0].iter().enumerate() {
                let mut v = Vec::new();
                for (i, (d, wd)) in [(ArrowDepth::Away, [0.008, 0.05]), (ArrowDepth::Away, [0.03, 0.04]), (ArrowDepth::Toward, [0.008, 0.05]), (ArrowDepth::Toward, [0.03, 0.04])].iter().enumerate() {
                    let mut a = column(if i % 2 == 0 { 0.7 } else { 0.25 }, *d, stance, *t, 0.14 + i as f64 * 0.24);
                    a.widths = Some(*wd);
                    v.push(a);
                }
                cell(&mut out, c as f64, 2.0, &format!("{} hand-set widths · thickness {t}", stance.name()), &v);
            }
            // Wide tails: the back widest, the shaft narrowing to a neck, the head
            // with shoulders. One arrow per cell so thickness 2 has room: Away
            // (long), Away (short), Toward, Flat, each at 0.6, 1 and 2.
            for (r, (d, l, wd)) in [(ArrowDepth::Away, 0.8, [0.09, 0.06]), (ArrowDepth::Away, 0.45, [0.09, 0.09]), (ArrowDepth::Toward, 0.8, [0.09, 0.06]), (ArrowDepth::Flat, 0.8, [0.09, 0.05])].iter().enumerate() {
                for (c, t) in [0.6, 1.0, 2.0].iter().enumerate() {
                    let mut a = column(*l, *d, stance, *t, 0.5);
                    a.widths = Some(*wd);
                    cell(&mut out, c as f64, 4.0 + r as f64, &format!("{} {} WIDE TAIL · thickness {t}", stance.name(), d.name()), &[a]);
                }
            }
            // Diagonals, curves, dashes, heads, looks.
            let mut v = Vec::new();
            v.push(deep(&[(0.12, 0.9), (0.36, 0.3)], ArrowDepth::Away, stance));
            v.push(deep(&[(0.88, 0.28), (0.62, 0.9)], ArrowDepth::Toward, stance));
            let mut c = deep(&[(0.42, 0.92), (0.56, 0.6), (0.48, 0.22)], ArrowDepth::Away, stance);
            c.dashed = true;
            c.look = ArrowLook::Red;
            v.push(c);
            let mut two = deep(&[(0.62, 0.2), (0.8, 0.1)], ArrowDepth::Away, stance);
            two.heads = 2;
            two.look = ArrowLook::Yellow;
            v.push(two);
            cell(&mut out, 0.0, 3.0, &format!("{} diagonals, curve dashed, two heads", stance.name()), &v);
            let mut v = Vec::new();
            v.push(deep(&[(0.1, 0.3), (0.45, 0.3)], ArrowDepth::Away, stance));
            v.push(deep(&[(0.9, 0.3), (0.55, 0.3)], ArrowDepth::Toward, stance));
            let mut corner = deep(&[(0.1, 0.92), (0.1, 0.6), (0.35, 0.6), (0.35, 0.45)], ArrowDepth::Away, stance);
            corner.shape = ArrowShape::Corner;
            v.push(corner);
            let mut none = deep(&[(0.55, 0.92), (0.6, 0.5)], ArrowDepth::Away, stance);
            none.heads = 0;
            v.push(none);
            let mut dark = deep(&[(0.75, 0.5), (0.85, 0.95)], ArrowDepth::Toward, stance);
            dark.look = ArrowLook::Dark;
            v.push(dark);
            cell(&mut out, 1.0, 3.0, &format!("{} across, corner, no head, dark", stance.name()), &v);
            let mut v = Vec::new();
            let mut dolly_in = deep(&[(0.3, 0.9), (0.3, 0.2)], ArrowDepth::Away, stance);
            dolly_in.depth_strength = 0.6;
            dolly_in.thickness = 1.6;
            v.push(dolly_in);
            let mut toward_camera = deep(&[(0.7, 0.16), (0.7, 0.88)], ArrowDepth::Toward, stance);
            toward_camera.dashed = true;
            toward_camera.look = ArrowLook::Red;
            v.push(toward_camera);
            cell(&mut out, 2.0, 3.0, &format!("{} Dolly In, Toward Camera", stance.name()), &v);
        }
        // The default sheet: flat arrows, which must not change at all.
        _ => {
            let mut flats: Vec<Arrow> = Vec::new();
            for (i, l) in lens.iter().enumerate() {
                flats.push(column(*l, ArrowDepth::Flat, ArrowStance::Floor, 1.0, 0.1 + i as f64 * 0.2));
            }
            cell(&mut out, 0.0, 0.0, "Flat", &flats);
            let mut dashed: Vec<Arrow> = Vec::new();
            for (i, l) in lens.iter().enumerate() {
                let mut a = column(*l, ArrowDepth::Flat, ArrowStance::Floor, 1.0, 0.1 + i as f64 * 0.2);
                a.dashed = true;
                a.heads = if i % 2 == 0 { 2 } else { 1 };
                dashed.push(a);
            }
            cell(&mut out, 1.0, 0.0, "Flat dashed", &dashed);
            let mut a = Arrow::straight(0.2, 0.85, 0.2, 0.15);
            a.widths = Some([0.012, 0.06]);
            let mut b = Arrow::straight(0.5, 0.85, 0.5, 0.15);
            b.widths = Some([0.03, 0.05]);
            let mut c = Arrow::straight(0.8, 0.85, 0.8, 0.15);
            c.widths = Some([0.02, 0.03]);
            c.dashed = true;
            cell(&mut out, 2.0, 0.0, "Flat, hand-set widths", &[a, b, c]);
        }
    }
    out.push_str("</svg>");
    println!("{out}");
}
