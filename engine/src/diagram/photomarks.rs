//! **Marks drawn on a picture on the plan** — his ask, 2026-10-15: *"annotate
//! on photos to show perspective"*, after finding shapes hard to draw and
//! keep on a photograph: they were laid in plan metres and stayed behind when
//! the photograph moved.
//!
//! A picture's marks live **on the picture** (`El::marks`), every number a
//! fraction of it, nought to one, left to right and top to bottom — the rule
//! the shot pictures' storyboard arrows already keep (`crate::arrow`). Move,
//! size or turn the picture and its marks go with it. They are drawn at full
//! strength whatever the picture's own strength is.
//!
//! ## The stored line
//!
//! Marks are separated by `;`. A mark that starts with a number is a
//! storyboard arrow, written exactly as on a shot's picture (`Arrow::parse`).
//! The others start with their kind:
//!
//! ```text
//! line,x1,y1,x2,y2[,dashed][,look:<l>][,thick:<t>]
//! box,x1,y1,x2,y2[,look:<l>][,thick:<t>]        corners
//! oval,x1,y1,x2,y2[,look:<l>][,thick:<t>]       the box it fills
//! draw,x:y,x:y,…[,look:<l>][,thick:<t>]         a hand-drawn line
//! words,x,y[,look:<l>][,size:<s>],t:<text>      text, `%`-escaped
//! ```
//!
//! `look` is the arrows' four (light, dark, red, yellow; absent is light).
//! `thick` is a multiple of the usual pen, half to three. A word's `size` is
//! its height as a fraction of the picture's height (absent 0.045). Unknown
//! tokens are ignored, and a piece that reads as nothing is dropped.
//!
//! **The perspective helper** is `El::perspective`, `<horizon y>:<vanishing
//! x>` (or `<horizon y>:` for the horizon alone): a horizon across the
//! picture and a vanishing point on it. It is drawn
//! only while he draws on the picture (the shells), never on the paper.

use super::render::{poly, Geom, Ink, Shape, Xf};
use super::El;
use crate::arrow::{Arrow, ArrowLook};

/// A word's height as a fraction of the picture's, when none is given.
pub const WORDS_SIZE: f64 = 0.045;
/// The pen's half-width at thickness 1, as a fraction of the longer side.
pub const PEN: f64 = 0.0045;
pub const THINNEST: f64 = 0.5;
pub const THICKEST: f64 = 3.0;
/// The most points a hand-drawn line keeps.
pub const MOST_POINTS: usize = 400;

#[derive(Clone, Debug, PartialEq)]
pub enum Kind {
    Line,
    Box,
    Oval,
}

impl Kind {
    pub fn name(&self) -> &'static str {
        match self {
            Kind::Line => "line",
            Kind::Box => "box",
            Kind::Oval => "oval",
        }
    }
    fn read(s: &str) -> Option<Kind> {
        match s {
            "line" => Some(Kind::Line),
            "box" => Some(Kind::Box),
            "oval" => Some(Kind::Oval),
            _ => None,
        }
    }
}

/// One mark on a picture.
#[derive(Clone, Debug, PartialEq)]
pub enum Mark {
    /// A storyboard arrow, as a shot's picture has them.
    Arrow(Arrow),
    /// A line, a box or an oval, from one corner (or end) to the other.
    Shape { kind: Kind, a: (f64, f64), b: (f64, f64), look: ArrowLook, thick: f64, dashed: bool },
    /// A hand-drawn line through its points.
    Draw { points: Vec<(f64, f64)>, look: ArrowLook, thick: f64 },
    /// Words, starting at `at` (the top left of the first line).
    Words { at: (f64, f64), text: String, look: ArrowLook, size: f64 },
}

fn frac(v: f64) -> f64 {
    if v.is_finite() { v.clamp(-0.5, 1.5) } else { 0.5 }
}

fn thick_of(t: f64) -> f64 {
    if t.is_finite() { t.clamp(THINNEST, THICKEST) } else { 1.0 }
}

/// `%`-escape what would break the line: `%`, `,`, `;` and new lines.
fn escape(t: &str) -> String {
    let mut out = String::new();
    for c in t.chars() {
        match c {
            '%' => out.push_str("%25"),
            ',' => out.push_str("%2C"),
            ';' => out.push_str("%3B"),
            '\n' => out.push_str("%0A"),
            '\r' => {}
            c => out.push(c),
        }
    }
    out
}

fn unescape(t: &str) -> String {
    t.replace("%0A", "\n").replace("%3B", ";").replace("%2C", ",").replace("%25", "%")
}

fn look_token(look: ArrowLook, thick: f64, out: &mut String) {
    if look != ArrowLook::Light {
        out.push_str(&format!(",look:{}", look.name()));
    }
    if (thick - 1.0).abs() > 0.005 {
        out.push_str(&format!(",thick:{:.2}", thick));
    }
}

impl Mark {
    fn encode_one(&self) -> String {
        match self {
            Mark::Arrow(a) => Arrow::encode(std::slice::from_ref(a)),
            Mark::Shape { kind, a, b, look, thick, dashed } => {
                let mut out = format!("{},{:.4},{:.4},{:.4},{:.4}", kind.name(), a.0, a.1, b.0, b.1);
                if *dashed {
                    out.push_str(",dashed");
                }
                look_token(*look, *thick, &mut out);
                out
            }
            Mark::Draw { points, look, thick } => {
                let mut out = String::from("draw");
                for (x, y) in points {
                    out.push_str(&format!(",{:.4}:{:.4}", x, y));
                }
                look_token(*look, *thick, &mut out);
                out
            }
            Mark::Words { at, text, look, size } => {
                let mut out = format!("words,{:.4},{:.4}", at.0, at.1);
                if *look != ArrowLook::Light {
                    out.push_str(&format!(",look:{}", look.name()));
                }
                if (size - WORDS_SIZE).abs() > 0.0005 {
                    out.push_str(&format!(",size:{:.4}", size));
                }
                out.push_str(&format!(",t:{}", escape(text)));
                out
            }
        }
    }

    fn parse_one(piece: &str) -> Option<Mark> {
        let piece = piece.trim();
        if piece.is_empty() {
            return None;
        }
        let tokens: Vec<&str> = piece.split(',').map(str::trim).collect();
        let head = tokens[0];
        let mut look = ArrowLook::Light;
        let mut thick = 1.0;
        let mut dashed = false;
        let mut size = WORDS_SIZE;
        let mut text = String::new();
        let mut nums: Vec<f64> = Vec::new();
        let mut points: Vec<(f64, f64)> = Vec::new();
        for t in &tokens[1..] {
            if let Some(v) = t.strip_prefix("look:") {
                look = ArrowLook::read(v).unwrap_or(look);
            } else if let Some(v) = t.strip_prefix("thick:") {
                thick = thick_of(v.parse().unwrap_or(1.0));
            } else if let Some(v) = t.strip_prefix("size:") {
                size = v.parse::<f64>().ok().filter(|s| s.is_finite()).unwrap_or(WORDS_SIZE).clamp(0.01, 0.4);
            } else if let Some(v) = t.strip_prefix("t:") {
                text = unescape(v);
            } else if *t == "dashed" {
                dashed = true;
            } else if let Some((x, y)) = t.split_once(':') {
                if let (Ok(x), Ok(y)) = (x.parse::<f64>(), y.parse::<f64>()) {
                    points.push((frac(x), frac(y)));
                }
            } else if let Ok(v) = t.parse::<f64>() {
                nums.push(frac(v));
            }
        }
        if let Some(kind) = Kind::read(head) {
            if nums.len() < 4 {
                return None;
            }
            return Some(Mark::Shape { kind, a: (nums[0], nums[1]), b: (nums[2], nums[3]), look, thick, dashed });
        }
        match head {
            "draw" => {
                points.truncate(MOST_POINTS);
                (points.len() >= 2).then_some(Mark::Draw { points, look, thick })
            }
            "words" => {
                if nums.len() < 2 || text.trim().is_empty() {
                    return None;
                }
                Some(Mark::Words { at: (nums[0], nums[1]), text, look, size })
            }
            _ => Arrow::parse(piece).into_iter().next().map(Mark::Arrow),
        }
    }

    /// Every mark in a stored line, in order — the last drawn on top.
    pub fn parse(line: &str) -> Vec<Mark> {
        line.split(';').filter_map(Mark::parse_one).collect()
    }

    pub fn encode(marks: &[Mark]) -> String {
        marks.iter().map(Mark::encode_one).collect::<Vec<_>>().join(";")
    }
}

/// **The perspective helper**: a horizon `horizon` down the picture and, when
/// shown, a vanishing point on it `vanish` across — fractions. Stored as
/// `<horizon>:<vanish>`, or `<horizon>:` for the horizon alone.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Perspective {
    pub horizon: f64,
    pub vanish: Option<f64>,
}

impl Perspective {
    pub fn parse(s: &str) -> Option<Perspective> {
        let (h, v) = s.trim().split_once(':')?;
        let h = h.trim().parse::<f64>().ok().filter(|h| h.is_finite())?;
        let v = v.trim().parse::<f64>().ok().filter(|v| v.is_finite()).map(|v| v.clamp(-2.0, 3.0));
        Some(Perspective { horizon: h.clamp(-1.0, 2.0), vanish: v })
    }
    pub fn encode(&self) -> String {
        match self.vanish {
            Some(v) => format!("{:.4}:{:.4}", self.horizon, v),
            None => format!("{:.4}:", self.horizon),
        }
    }
}

/// A ribbon round a run of points, `half` either side: one closed outline.
fn ribbon(points: &[(f64, f64)], half: f64) -> Vec<(f64, f64)> {
    let n = points.len();
    if n < 2 {
        return Vec::new();
    }
    let normal = |i: usize| -> (f64, f64) {
        let a = points[i.saturating_sub(1)];
        let b = points[(i + 1).min(n - 1)];
        let (dx, dy) = (b.0 - a.0, b.1 - a.1);
        let l = dx.hypot(dy);
        if l < 1e-12 { (0.0, 0.0) } else { (-dy / l, dx / l) }
    };
    let mut left = Vec::with_capacity(n);
    let mut right = Vec::with_capacity(n);
    for (i, p) in points.iter().enumerate() {
        let (nx, ny) = normal(i);
        left.push((p.0 + nx * half, p.1 + ny * half));
        right.push((p.0 - nx * half, p.1 - ny * half));
    }
    right.reverse();
    left.extend(right);
    left
}

/// An oval's edge as points: `steps` round it.
fn oval_points(cx: f64, cy: f64, rx: f64, ry: f64, steps: usize) -> Vec<(f64, f64)> {
    (0..steps)
        .map(|i| {
            let t = i as f64 / steps as f64 * std::f64::consts::TAU;
            (cx + rx * t.cos(), cy + ry * t.sin())
        })
        .collect()
}

/// A closed band between an outer and an inner outline: the outer one way
/// round, the inner the other, so the middle is left empty (non-zero fill).
fn band(outer: &[(f64, f64)], inner: &[(f64, f64)]) -> Vec<super::render::Seg> {
    let mut segs = poly(outer, true);
    let mut back: Vec<(f64, f64)> = inner.to_vec();
    back.reverse();
    segs.extend(poly(&back, true));
    segs
}

/// **What a picture's marks draw**, in the plan's metres: every shape
/// already moved and turned onto the picture, part `mark`.
pub fn shapes(e: &El) -> Vec<Shape> {
    if e.marks.trim().is_empty() || e.w <= 0.0 || e.h <= 0.0 {
        return Vec::new();
    }
    // Arrows are drawn in a picture's pixels: lay it out 1000 across its
    // longer side, then bring it back to metres.
    let k = 1000.0 / e.w.max(e.h);
    let (pw, ph) = (e.w * k, e.h * k);
    let xf = Xf::new(e.x, e.y, e.rot);
    let to_plan = |(px, py): (f64, f64)| xf.p(px / k - e.w / 2.0, py / k - e.h / 2.0);
    let at = |(fx, fy): (f64, f64)| (fx * pw, fy * ph);
    let big = pw.max(ph);
    let mut out: Vec<Shape> = Vec::new();
    let piece = |segs: Vec<super::render::Seg>, fill: &str, look: ArrowLook| -> Shape {
        let mut s = Shape::new(&e.id, "mark", Geom::Path(segs));
        s.fill = Ink::hex(fill);
        s.stroke = Ink::hex(look.line());
        s.line = 0.6;
        s
    };
    let put = |out: &mut Vec<Shape>, pts: Vec<(f64, f64)>, look: ArrowLook, fill: &str| {
        if pts.len() >= 3 {
            let plan: Vec<(f64, f64)> = pts.into_iter().map(to_plan).collect();
            out.push(piece(poly(&plan, true), fill, look));
        }
    };
    for m in Mark::parse(&e.marks) {
        match m {
            Mark::Arrow(a) => {
                if let Some(z) = a.zoom_shapes(pw, ph) {
                    let outer: Vec<(f64, f64)> = z.ring[0].iter().copied().map(to_plan).collect();
                    let inner: Vec<(f64, f64)> = z.ring[1].iter().copied().map(to_plan).collect();
                    out.push(piece(band(&outer, &inner), a.look.fill(), a.look));
                }
                for f in a.faces(pw, ph) {
                    put(&mut out, f.points, a.look, if f.side { a.look.shade() } else { a.look.fill() });
                }
            }
            Mark::Shape { kind, a: p, b: q, look, thick, dashed } => {
                let half = PEN * big * thick;
                let (a, b) = (at(p), at(q));
                match kind {
                    Kind::Line => {
                        if dashed {
                            let len = (b.0 - a.0).hypot(b.1 - a.1);
                            let dash = (half * 7.0).max(1.0);
                            let mut s = 0.0;
                            while s < len {
                                let e2 = (s + dash).min(len);
                                let t0 = s / len.max(1e-9);
                                let t1 = e2 / len.max(1e-9);
                                let p0 = (a.0 + (b.0 - a.0) * t0, a.1 + (b.1 - a.1) * t0);
                                let p1 = (a.0 + (b.0 - a.0) * t1, a.1 + (b.1 - a.1) * t1);
                                put(&mut out, ribbon(&[p0, p1], half), look, look.fill());
                                s += dash * 1.8;
                            }
                        } else {
                            put(&mut out, ribbon(&[a, b], half), look, look.fill());
                        }
                    }
                    Kind::Box => {
                        let (x1, x2) = (a.0.min(b.0), a.0.max(b.0));
                        let (y1, y2) = (a.1.min(b.1), a.1.max(b.1));
                        let outer = [(x1 - half, y1 - half), (x2 + half, y1 - half), (x2 + half, y2 + half), (x1 - half, y2 + half)];
                        let ih = |v: f64, w: f64| if w > 2.0 * half { v } else { 0.0 };
                        let inner = [
                            (x1 + ih(half, x2 - x1), y1 + ih(half, y2 - y1)),
                            (x2 - ih(half, x2 - x1), y1 + ih(half, y2 - y1)),
                            (x2 - ih(half, x2 - x1), y2 - ih(half, y2 - y1)),
                            (x1 + ih(half, x2 - x1), y2 - ih(half, y2 - y1)),
                        ];
                        let o: Vec<(f64, f64)> = outer.iter().copied().map(to_plan).collect();
                        let i: Vec<(f64, f64)> = inner.iter().copied().map(to_plan).collect();
                        out.push(piece(band(&o, &i), look.fill(), look));
                    }
                    Kind::Oval => {
                        let (cx, cy) = ((a.0 + b.0) / 2.0, (a.1 + b.1) / 2.0);
                        let (rx, ry) = (((b.0 - a.0) / 2.0).abs(), ((b.1 - a.1) / 2.0).abs());
                        let o: Vec<(f64, f64)> = oval_points(cx, cy, rx + half, ry + half, 72).into_iter().map(to_plan).collect();
                        let i: Vec<(f64, f64)> =
                            oval_points(cx, cy, (rx - half).max(0.0), (ry - half).max(0.0), 72).into_iter().map(to_plan).collect();
                        out.push(piece(band(&o, &i), look.fill(), look));
                    }
                }
            }
            Mark::Draw { points, look, thick } => {
                let half = PEN * big * thick;
                let pts: Vec<(f64, f64)> = smoothed(&points.into_iter().map(at).collect::<Vec<_>>());
                put(&mut out, ribbon(&pts, half), look, look.fill());
            }
            Mark::Words { at: p, text, look, size } => {
                let (x, y) = at(p);
                let h = size * ph;
                // The top left of the first line: words are placed by their
                // baseline, about 0.8 of their height down.
                let (px, py) = to_plan((x, y + h * 0.8));
                let mut s = Shape::new(
                    &e.id,
                    "mark",
                    Geom::Text {
                        x: px,
                        y: py,
                        text,
                        size: h / k,
                        anchor: "start",
                        bold: true,
                        rot: e.rot,
                        fixed: false,
                        halo: false,
                        patch: false,
                        shift: (0.0, 0.0),
                        under: Ink::None,
                        lead: 1,
                    },
                );
                s.fill = Ink::hex(look.fill());
                out.push(s);
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_kind_of_mark_reads_back_as_it_was_written() {
        let marks = vec![
            Mark::Arrow(Arrow::straight(0.1, 0.2, 0.6, 0.7)),
            Mark::Shape { kind: Kind::Line, a: (0.1, 0.1), b: (0.9, 0.2), look: ArrowLook::Yellow, thick: 1.5, dashed: true },
            Mark::Shape { kind: Kind::Box, a: (0.2, 0.3), b: (0.4, 0.5), look: ArrowLook::Light, thick: 1.0, dashed: false },
            Mark::Shape { kind: Kind::Oval, a: (0.5, 0.3), b: (0.6, 0.8), look: ArrowLook::Red, thick: 2.0, dashed: false },
            Mark::Draw { points: vec![(0.1, 0.1), (0.2, 0.15), (0.3, 0.1)], look: ArrowLook::Dark, thick: 1.0 },
            Mark::Words { at: (0.25, 0.6), text: "Maya, to window; 50%\nthen out".into(), look: ArrowLook::Yellow, size: 0.06 },
        ];
        let line = Mark::encode(&marks);
        let back = Mark::parse(&line);
        assert_eq!(back.len(), marks.len(), "{line}");
        assert_eq!(back[1..], marks[1..], "{line}");
        let Mark::Arrow(a) = &back[0] else { panic!("an arrow") };
        assert_eq!((a.x1, a.y1, a.x2, a.y2), (0.1, 0.2, 0.6, 0.7));
        // The shot pictures' own arrow line reads here too.
        let shot = Arrow::encode(&[Arrow::straight(0.1, 0.1, 0.5, 0.5)]);
        assert!(matches!(Mark::parse(&shot)[0], Mark::Arrow(_)));
        // Rubbish is dropped, not guessed at.
        assert!(Mark::parse("box,0.1;words,0.2,0.2;draw,0.1:0.1;;").is_empty());
    }

    #[test]
    fn the_perspective_helper_reads_back() {
        let p = Perspective { horizon: 0.42, vanish: Some(0.55) };
        assert_eq!(Perspective::parse(&p.encode()), Some(p));
        let h = Perspective { horizon: 0.3, vanish: None };
        assert_eq!(Perspective::parse(&h.encode()), Some(h), "the horizon alone");
        assert_eq!(Perspective::parse(""), None);
        assert_eq!(Perspective::parse("nan:0.5"), None);
    }
}

/// The look nearest a plan piece's colour: its own ink (empty) is Dark.
fn look_of(colour: &str) -> ArrowLook {
    let h = colour.trim().trim_start_matches('#');
    if h.len() < 6 {
        return ArrowLook::Dark;
    }
    let v = |i: usize| u8::from_str_radix(&h[i..i + 2], 16).unwrap_or(0) as f64;
    let (r, g, b) = (v(0), v(2), v(4));
    if r > 200.0 && g > 200.0 && b > 200.0 {
        ArrowLook::Light
    } else if r > 180.0 && g > 150.0 && b < 120.0 {
        ArrowLook::Yellow
    } else if r > 150.0 && g < 110.0 && b < 110.0 {
        ArrowLook::Red
    } else {
        ArrowLook::Dark
    }
}

/// **Attach to Photo** (his pick, 2026-10-15): the arrows, lines, boxes,
/// ovals, drawing and words lying on a picture — laid on the plan before its
/// marks were its own — moved onto it, so from now on they go where it goes.
/// Only what lies wholly on it; anything else stays on the plan. Answers how
/// many came across.
pub fn attach(d: &mut super::Diagram, id: &str) -> usize {
    use super::Kind as K;
    let Some(photo) = d.get(id).filter(|e| e.kind == K::Image && e.w > 0.0 && e.h > 0.0).cloned() else {
        return 0;
    };
    let (c, s) = (photo.rot.to_radians().cos(), photo.rot.to_radians().sin());
    let frac_of = |(x, y): (f64, f64)| -> (f64, f64) {
        let (dx, dy) = (x - photo.x, y - photo.y);
        let (lx, ly) = (dx * c + dy * s, -dx * s + dy * c);
        ((lx + photo.w / 2.0) / photo.w, (ly + photo.h / 2.0) / photo.h)
    };
    let inside = |p: (f64, f64)| (-0.001..=1.001).contains(&p.0) && (-0.001..=1.001).contains(&p.1);
    let mut marks = Mark::parse(&photo.marks);
    let mut taken: Vec<String> = Vec::new();
    for e in d.els.iter().filter(|e| e.id != id && !e.hidden && !e.locked) {
        let thick = thick_of(if e.weight > 0.0 { e.weight / 2.0 } else { 1.0 });
        let look = look_of(&e.color);
        let mark = match e.kind {
            K::Arrow => {
                let run = super::walls::bent((e.x, e.y), (e.x2, e.y2), e.curve);
                let pts = [(e.x, e.y), run[run.len() / 2], (e.x2, e.y2)];
                let f: Vec<(f64, f64)> = pts.iter().copied().map(frac_of).collect();
                if !f.iter().all(|p| inside(*p)) {
                    continue;
                }
                if e.head == "none" {
                    if e.curve.abs() > 1e-9 {
                        Mark::Draw { points: f, look, thick }
                    } else {
                        Mark::Shape { kind: Kind::Line, a: f[0], b: f[2], look, thick, dashed: !e.dash.is_empty() }
                    }
                } else {
                    let mut a = if e.curve.abs() > 1e-9 { Arrow::through(&f).unwrap_or_else(|| Arrow::straight(f[0].0, f[0].1, f[2].0, f[2].1)) } else { Arrow::straight(f[0].0, f[0].1, f[2].0, f[2].1) };
                    a.heads = if e.head == "both" { 2 } else { 1 };
                    a.dashed = !e.dash.is_empty();
                    a.look = look;
                    Mark::Arrow(a)
                }
            }
            K::Shape if matches!(e.sym.as_str(), "ellipse" | "circle" | "line" | "" | "rect" | "square" | "rounded") => {
                let xf = Xf::new(e.x, e.y, e.rot);
                if e.sym == "line" {
                    let (a, b) = (frac_of(xf.p(-e.w / 2.0, 0.0)), frac_of(xf.p(e.w / 2.0, 0.0)));
                    if !inside(a) || !inside(b) {
                        continue;
                    }
                    Mark::Shape { kind: Kind::Line, a, b, look, thick, dashed: !e.dash.is_empty() }
                } else {
                    let corners: Vec<(f64, f64)> = [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)]
                        .iter()
                        .map(|(sx, sy)| frac_of(xf.p(sx * e.w / 2.0, sy * e.h / 2.0)))
                        .collect();
                    if !corners.iter().all(|p| inside(*p)) {
                        continue;
                    }
                    let (x1, x2) = corners.iter().fold((f64::MAX, f64::MIN), |m, p| (m.0.min(p.0), m.1.max(p.0)));
                    let (y1, y2) = corners.iter().fold((f64::MAX, f64::MIN), |m, p| (m.0.min(p.1), m.1.max(p.1)));
                    let kind = if matches!(e.sym.as_str(), "ellipse" | "circle") { Kind::Oval } else { Kind::Box };
                    Mark::Shape { kind, a: (x1, y1), b: (x2, y2), look, thick, dashed: false }
                }
            }
            K::Stroke if e.points.len() >= 2 => {
                let f: Vec<(f64, f64)> = e.points.iter().copied().map(frac_of).collect();
                if !f.iter().all(|p| inside(*p)) {
                    continue;
                }
                Mark::Draw { points: f.into_iter().take(MOST_POINTS).collect(), look, thick }
            }
            K::Text if !e.text.trim().is_empty() && super::render::shared_label_words(d, e).is_none() => {
                let p = frac_of((e.x, e.y));
                if !inside(p) {
                    continue;
                }
                Mark::Words { at: (p.0, (p.1 - WORDS_SIZE * 0.8).max(0.0)), text: e.text.clone(), look, size: WORDS_SIZE }
            }
            _ => continue,
        };
        marks.push(mark);
        taken.push(e.id.clone());
    }
    if taken.is_empty() {
        return 0;
    }
    d.els.retain(|e| !taken.contains(&e.id));
    if let Some(p) = d.get_mut(id) {
        p.marks = Mark::encode(&marks);
    }
    taken.len()
}


/// **A hand's line, smoothed** (2026-10-17): Chaikin's corner cutting,
/// twice, its two ends kept — the same rounding the Mac and the phone draw.
pub fn smoothed(pts: &[(f64, f64)]) -> Vec<(f64, f64)> {
    if pts.len() <= 2 {
        return pts.to_vec();
    }
    let mut cur = pts.to_vec();
    for _ in 0..2 {
        let mut next = vec![cur[0]];
        for w in cur.windows(2) {
            let (a, b) = (w[0], w[1]);
            next.push((a.0 * 0.75 + b.0 * 0.25, a.1 * 0.75 + b.1 * 0.25));
            next.push((a.0 * 0.25 + b.0 * 0.75, a.1 * 0.25 + b.1 * 0.75));
        }
        next.push(cur[cur.len() - 1]);
        cur = next;
    }
    cur
}
