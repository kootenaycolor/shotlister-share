//! Lights, grip and support, drawn from above.
//!
//! His *Film Set Objects* pack (Evan Oliver, 2025 edition, in his Drive under
//! `cinematography/documents/previs`) is the guide: which gear, what it is
//! called, how big it is and what it looks like from overhead. The drawing is
//! ours — his ruling of 2026-09-27 was to redraw it in the plan's own hand, not
//! paste his pictures in, so a light sits beside a sofa as one family: a pale
//! housing with a grey outline, the lit face in amber, a few lines of detail.
//!
//! One `Look` per kind of thing; a named fixture is a look at its real size.
//! Everything faces east (+x): `w` runs front to back, `h` across.
//!
//! Two drawings change with their shape, the way the real thing does when
//! it is turned: a mat or a frame that is nearly square is lying flat (an
//! overhead, seen face-on), and one that is thin is standing, seen edge-on.

use super::render::{arc, circle, ellipse, line, poly, rect, rrect, smooth, Geom, Ink, Seg, Shape};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Tone {
    Tungsten,
    Hmi,
    Led,
}

/// What hangs off the front of an LED head.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Front {
    Bare,
    Reflector,
    Fresnel,
    Dome,
}

/// What a flag, a rag or a net is made of. The frame colours are the ones
/// grips paint on nets: green a single, red a double, yellow artificial silk.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Cloth {
    Solid,
    Single,
    Double,
    Silk,
    ArtSilk,
    Grid,
    Bounce,
    Muslin,
    Lcd,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Board {
    Foam,
    Shiny,
    Card,
    Neg,
    Reflector,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Look {
    /// Drawn by its name, the way the furniture is.
    Named,
    Fresnel(Tone),
    /// A finned can — Arri's M series and its kin.
    Can(Tone),
    OpenFace,
    Par,
    Beam,
    Joker,
    Softube,
    Head(Front),
    Panel,
    Kino,
    Mat,
    Tube,
    Cluster(u8, u8),
    Ellipsoidal,
    Ball,
    Spacelight,
    Parabolic,
    Softbox,
    Bulb,
    Shade,
    StreetLight,
    WallLight,
    Torch,
    Flag(Cloth),
    Rag(Cloth),
    Board(Board),
    CStand,
    Combo,
    Roller,
    Crank,
    Sticks,
    Polecat,
    Rail,
    Slider,
    Track,
    Curve,
    Circle,
    Dana,
    Doorway,
    Fisher,
    Chapman,
    Jib,
    Technocrane,
    Menace,
    Arm,
    Easyrig,
    Condor,
    Lift,
    Truss(u8),
    Distro,
    TowGen,
    Cart,
    Crafty,
    Canopy,
    Hazer,
    Fan,
    Cone,
    // ---- set pieces after the pack
    /// A couch of so many seats.
    Couch(u8),
    Chair,
    OfficeChair,
    /// A table in wood; `true` is round.
    Table(bool),
    /// A half round, skirted: its flat edge at the back.
    HalfRound,
    /// A made bed with so many people in it.
    Bed(u8),
    Car,
    Pickup,
    Tree,
    Hedge,
    Stump,
    Sidewalk,
    /// A seamless paper backdrop, by colour (see `PAPERS`).
    Seamless(u8),
    /// A cyc: `true` is green.
    Cyc(bool),
    PortableGen,
    Projector,
    Monitor,
}

/// The seamless colours a paper backdrop comes in.
pub const PAPERS: &[&str] = &["#EDEDEA", "#232325", "#8C8D90", "#3FA34D", "#23456B", "#E3BDC1", "#B99A7E"];

// ---------------------------------------------------------------- inks

fn shape(segs: Vec<Seg>, fill: Ink, stroke: Ink, line_w: f64) -> Shape {
    Shape { el: String::new(), part: "body", geom: Geom::Path(segs), fill, stroke, line: line_w, dash: "", alpha: 1.0, fade: None }
}
/// The housing: pale, outlined.
fn housing(segs: Vec<Seg>) -> Shape {
    shape(segs, Ink::Role("fixture"), Ink::Role("fixtureline"), 0.9)
}
/// The lit face — the one amber thing on a fixture.
fn face(segs: Vec<Seg>) -> Shape {
    shape(segs, Ink::Role("light"), Ink::Role("lightline"), 0.6)
}
/// A line of the fixture's own: doors, a yoke, a rib.
fn edge(segs: Vec<Seg>, w: f64) -> Shape {
    shape(segs, Ink::None, Ink::Role("fixtureline"), w)
}
/// A small solid part: a knob, a wheel, a foot.
fn knob(segs: Vec<Seg>) -> Shape {
    shape(segs, Ink::Role("fixtureline"), Ink::None, 0.0)
}
fn grip_line(segs: Vec<Seg>, w: f64) -> Shape {
    shape(segs, Ink::None, Ink::Role("grip"), w)
}
fn grip_solid(segs: Vec<Seg>) -> Shape {
    shape(segs, Ink::Role("grip"), Ink::None, 0.0)
}
fn soft(segs: Vec<Seg>) -> Shape {
    shape(segs, Ink::Role("setsoft"), Ink::Role("setline"), 0.8)
}
fn faint(mut s: Shape, a: f64) -> Shape {
    s.alpha = a;
    s
}

/// How many times a repeated part is drawn — never more than sixty.
fn repeats(n: f64, least: usize) -> usize {
    if n.is_finite() { (n.max(0.0) as usize).clamp(least, 60) } else { least }
}

// ---------------------------------------------------------------- parts

/// A yoke: the U a head hangs in, arms either side at `y = ±arm`, open to
/// the front, with the knob that locks it.
fn yoke(v: &mut Vec<Shape>, x0: f64, x1: f64, arm: f64) {
    v.push(edge(poly(&[(x1, -arm), (x0, -arm), (x0, arm), (x1, arm)], false), 1.3));
    v.push(knob(circle(x1, -arm, 0.022_f64.max(arm * 0.06))));
    v.push(knob(circle(x1, arm, 0.022_f64.max(arm * 0.06))));
}

/// Barn doors, standing open from the face at `x` either side.
fn doors(v: &mut Vec<Shape>, x: f64, half: f64, reach: f64, spread: f64) {
    v.push(edge(line(x, -half, x + reach, -half - spread), 1.5));
    v.push(edge(line(x, half, x + reach, half + spread), 1.5));
}

/// Lines across a housing: fins, vents, ribs.
fn ribs(v: &mut Vec<Shape>, x0: f64, x1: f64, y0: f64, y1: f64, n: usize, along: bool) {
    for i in 1..=n {
        let t = i as f64 / (n + 1) as f64;
        if along {
            let y = y0 + (y1 - y0) * t;
            v.push(faint(edge(line(x0, y, x1, y), 0.7), 0.8));
        } else {
            let x = x0 + (x1 - x0) * t;
            v.push(faint(edge(line(x, y0, x, y1), 0.7), 0.8));
        }
    }
}

// ---------------------------------------------------------------- drawing

pub fn draw(look: Look, w: f64, h: f64) -> Vec<Shape> {
    let (hw, hh) = (w / 2.0, h / 2.0);
    let mut v = Vec::new();
    match look {
        Look::Named => {}

        // ---- heads with a lens
        Look::Fresnel(tone) => {
            let front = hw * 0.55;
            let half = hh * 0.74;
            yoke(&mut v, -hw * 0.55, 0.0, hh * 0.9);
            v.push(housing(rrect(-hw, -half, front + hw, 2.0 * half, (h * 0.08).min(0.06))));
            match tone {
                Tone::Tungsten => ribs(&mut v, -hw * 0.85, -hw * 0.2, -half * 0.6, half * 0.6, 4, false),
                Tone::Hmi => {
                    ribs(&mut v, -hw * 0.9, front - w * 0.08, -half, half, 3, true);
                    v.push(knob(rect(-hw - w * 0.05, -hh * 0.18, w * 0.05, hh * 0.36)));
                }
                Tone::Led => v.push(soft(rrect(-hw * 0.95, -half * 0.5, w * 0.22, half, 0.02))),
            }
            v.push(face(rect(front, -half * 0.92, w * 0.1, 2.0 * half * 0.92)));
            doors(&mut v, front + w * 0.1, half, hw - front - w * 0.1, hh - half);
        }
        Look::Can(tone) => {
            // A tall finned can on a wider skirt, the lamp base behind.
            let front = hw * 0.6;
            let half = hh * 0.66;
            yoke(&mut v, -hw * 0.3, hw * 0.1, hh * 0.86);
            v.push(housing(poly(&[(-hw, -hh * 0.82), (-hw * 0.55, -half), (-hw * 0.55, half), (-hw, hh * 0.82)], true)));
            v.push(housing(rect(-hw * 0.6, -half, front + hw * 0.6, 2.0 * half)));
            ribs(&mut v, -hw * 0.55, front - w * 0.02, -half, half, 5, true);
            if tone == Tone::Hmi {
                v.push(knob(rect(-hw - w * 0.04, -hh * 0.2, w * 0.04, hh * 0.4)));
            }
            v.push(face(rect(front, -half, w * 0.08, 2.0 * half)));
            doors(&mut v, front + w * 0.08, half, hw - front - w * 0.08, hh - half);
        }
        Look::OpenFace => {
            let back = -hw * 0.2;
            yoke(&mut v, -hw * 0.75, -hw * 0.1, hh * 0.55);
            v.push(housing(rrect(-hw, -hh * 0.42, back + hw, hh * 0.84, 0.02)));
            v.push(housing(poly(&[(back, -hh * 0.42), (hw * 0.7, -hh * 0.8), (hw * 0.7, hh * 0.8), (back, hh * 0.42)], true)));
            v.push(face(rect(hw * 0.7, -hh * 0.8, w * 0.07, h * 0.8)));
            doors(&mut v, hw * 0.77, hh * 0.8, hw * 0.23, hh * 0.2);
        }
        Look::Par => {
            yoke(&mut v, -hw * 0.5, 0.0, hh * 0.92);
            v.push(housing(rrect(-hw, -hh * 0.8, w * 0.9, h * 0.8, (h * 0.12).min(0.08))));
            ribs(&mut v, -hw * 0.9, -hw * 0.3, -hh * 0.55, hh * 0.55, 3, false);
            v.push(face(rrect(hw * 0.8, -hh * 0.78, w * 0.2, h * 0.78, 0.02)));
            v.push(edge(line(hw, -hh * 0.78, hw, hh * 0.78), 1.4));
        }
        Look::Beam => {
            yoke(&mut v, -hw * 0.4, hw * 0.1, hh * 0.94);
            v.push(housing(rrect(-hw, -hh * 0.82, w * 0.88, h * 0.82, 0.03)));
            ribs(&mut v, -hw * 0.95, hw * 0.6, -hh * 0.82, hh * 0.82, 6, true);
            v.push(face(rect(hw * 0.76, -hh * 0.82, w * 0.24, h * 0.82)));
            ribs(&mut v, hw * 0.76, hw, -hh * 0.82, hh * 0.82, 4, true);
        }
        Look::Joker => {
            // The bug-a-beam: a round lamphead behind, the reflector opening
            // forward, doors on the front.
            let neck = -hw * 0.25;
            v.push(housing(rrect(-hw, -hh * 0.3, neck + hw, hh * 0.6, (hh * 0.25).min(0.04))));
            ribs(&mut v, -hw * 0.95, neck - w * 0.03, -hh * 0.3, hh * 0.3, 2, true);
            v.push(housing(poly(&[(neck, -hh * 0.32), (hw * 0.78, -hh * 0.82), (hw * 0.78, hh * 0.82), (neck, hh * 0.32)], true)));
            v.push(face(rect(hw * 0.78, -hh * 0.82, w * 0.06, h * 0.82)));
            doors(&mut v, hw * 0.84, hh * 0.82, hw * 0.16, hh * 0.18);
        }
        Look::Softube => {
            // A Joker with its tube: the head behind, the glowing tube ahead.
            let head = -hw + w * 0.18;
            v.push(housing(rrect(-hw, -hh * 0.7, head + hw, h * 0.7, 0.02)));
            v.push(face(rrect(head, -hh * 0.55, hw - head, h * 0.55, (hh * 0.5).min(0.05))));
            v.push(edge(line(head + w * 0.02, 0.0, hw - w * 0.03, 0.0), 0.6));
        }
        Look::Head(front) => {
            // An LED point source: the body with its heat sink, the yoke,
            // and whatever it wears on the front.
            let body_front = match front {
                Front::Bare => hw * 0.55,
                Front::Reflector => -hw * 0.05,
                Front::Fresnel => -hw * 0.15,
                Front::Dome => -hw * 0.45,
            };
            let half = hh * if front == Front::Dome { 0.3 } else { 0.62 };
            yoke(&mut v, -hw * 0.95, body_front - w * 0.08, half + hh * 0.14);
            v.push(housing(rrect(-hw, -half, body_front + hw, 2.0 * half, (half * 0.25).min(0.04))));
            let rows = 3;
            for r in 0..rows {
                let y = -half * 0.6 + half * 1.2 * r as f64 / (rows - 1) as f64;
                v.push(faint(edge(line(-hw * 0.9, y, body_front - w * 0.06, y), 0.6), 0.8));
            }
            match front {
                Front::Bare => v.push(face(rect(body_front, -half * 0.8, w * 0.07, half * 1.6))),
                Front::Reflector => {
                    v.push(housing(poly(&[(body_front, -half * 0.75), (hw * 0.92, -hh * 0.95), (hw * 0.92, hh * 0.95), (body_front, half * 0.75)], true)));
                    v.push(face(rect(hw * 0.92, -hh * 0.95, w * 0.08, h * 0.95)));
                }
                Front::Fresnel => {
                    v.push(housing(rrect(body_front, -hh * 0.8, hw * 0.8 - body_front, h * 0.8, 0.02)));
                    ribs(&mut v, body_front, hw * 0.8, -hh * 0.8, hh * 0.8, 2, false);
                    v.push(face(rect(hw * 0.8, -hh * 0.78, w * 0.07, h * 0.78)));
                    doors(&mut v, hw * 0.87, hh * 0.78, hw * 0.13, hh * 0.2);
                }
                Front::Dome => {
                    // A parabolic dome, much bigger than the head behind it.
                    let rim = hw;
                    let mut bowl = vec![Seg::M(rim, -hh)];
                    bowl.push(Seg::C(body_front + w * 0.1, -hh, body_front, -hh * 0.5, body_front, 0.0));
                    bowl.push(Seg::C(body_front, hh * 0.5, body_front + w * 0.1, hh, rim, hh));
                    bowl.push(Seg::Z);
                    v.push(housing(bowl));
                    for i in 0..5 {
                        let y = -hh + h * (i as f64 + 0.5) / 5.0;
                        v.push(faint(edge(line(body_front + w * 0.05, y * 0.35, rim, y), 0.6), 0.7));
                    }
                    v.push(face(rect(rim - w * 0.04, -hh, w * 0.04, h)));
                }
            }
        }
        Look::Panel => {
            // Standing, seen from above: a slab, its face ahead, the yoke
            // round it and the handles on its back.
            let back = -hw * 0.35;
            let front = hw * 0.55;
            v.push(edge(poly(&[(0.0, -hh), (-hw, -hh), (-hw, hh), (0.0, hh)], false), 1.3));
            v.push(knob(rect(-hw - w * 0.12, -0.03, w * 0.12, 0.06)));
            v.push(housing(rect(back, -hh * 0.94, front - back, h * 0.94)));
            v.push(face(rect(front, -hh * 0.92, hw - front, h * 0.92)));
            if h > 0.5 {
                for y in [-hh * 0.45, hh * 0.45] {
                    v.push(knob(rect(back - w * 0.08, y - 0.04, w * 0.08, 0.08)));
                }
            }
        }
        Look::Kino => {
            let back = -hw * 0.45;
            v.push(edge(poly(&[(0.0, -hh * 0.98), (-hw, -hh * 0.98), (-hw, hh * 0.98), (0.0, hh * 0.98)], false), 1.2));
            v.push(housing(rect(back, -hh * 0.9, hw * 0.5 - back, h * 0.9)));
            v.push(face(rect(hw * 0.5, -hh * 0.9, w * 0.12, h * 0.9)));
            ribs(&mut v, hw * 0.5, hw * 0.62, -hh * 0.9, hh * 0.9, 3, false);
            doors(&mut v, hw * 0.62, hh * 0.9, hw * 0.38, hh * 0.08);
        }
        Look::Mat => {
            if w < h * 0.3 || h < w * 0.3 {
                // Standing, seen edge-on: the thin frame, the lit side ahead.
                v.push(housing(rect(-hw, -hh, w * 0.5, h)));
                v.push(face(rect(0.0, -hh, hw, h)));
                v.push(knob(rect(-hw - 0.08, -0.04, 0.08, 0.08)));
            } else {
                // Lying flat overhead: the face and its rows of LEDs.
                v.push(housing(rect(-hw, -hh, w, h)));
                v.push(faint(face(rect(-hw + w * 0.05, -hh + h * 0.05, w * 0.9, h * 0.9)), 0.55));
                // Every LED in one shape: a mat is one thing to draw, not hundreds.
                let (nx, ny) = (repeats(w / 0.15, 2).min(20), repeats(h / 0.15, 2).min(20));
                let r = (w.min(h) * 0.9 / nx.max(ny) as f64 * 0.22).min(0.025);
                let mut dots = Vec::new();
                for i in 0..nx {
                    for j in 0..ny {
                        let x = -hw + w * 0.05 + w * 0.9 * (i as f64 + 0.5) / nx as f64;
                        let y = -hh + h * 0.05 + h * 0.9 * (j as f64 + 0.5) / ny as f64;
                        dots.extend(circle(x, y, r));
                    }
                }
                v.push(shape(dots, Ink::Role("light"), Ink::None, 0.0));
            }
        }
        Look::Tube => {
            let cap = (h.max(w) * 0.05).min(0.05);
            if h >= w {
                v.push(face(rrect(-hw, -hh + cap, w, h - 2.0 * cap, hw)));
                v.push(knob(rrect(-hw, -hh, w, cap, 0.01)));
                v.push(knob(rrect(-hw, hh - cap, w, cap, 0.01)));
            } else {
                v.push(face(rrect(-hw + cap, -hh, w - 2.0 * cap, h, hh)));
                v.push(knob(rrect(-hw, -hh, cap, h, 0.01)));
                v.push(knob(rrect(hw - cap, -hh, cap, h, 0.01)));
            }
        }
        Look::Cluster(cols, _rows) => {
            // A Maxi-Brute or a Molefay from above: the frame, and its top
            // row of lamps looking out of the front.
            let cols = cols.max(1) as usize;
            yoke(&mut v, -hw * 0.9, -hw * 0.2, hh * 0.98);
            v.push(housing(rect(-hw * 0.8, -hh * 0.9, w * 0.9, h * 0.9)));
            let cell = h * 0.9 / cols as f64;
            for i in 0..cols {
                let y = -hh * 0.9 + cell * (i as f64 + 0.5);
                v.push(housing(rrect(-hw * 0.2, y - cell * 0.42, hw * 0.9, cell * 0.84, cell * 0.2)));
                v.push(face(rect(hw * 0.7, y - cell * 0.38, w * 0.15, cell * 0.76)));
            }
        }
        Look::Ellipsoidal => {
            v.push(housing(rrect(-hw, -hh * 0.9, w * 0.42, h * 0.9, 0.03)));
            v.push(housing(rect(-hw + w * 0.42, -hh * 0.5, w * 0.5, h * 0.5)));
            for i in 0..3 {
                let x = -hw + w * (0.5 + i as f64 * 0.12);
                v.push(knob(rect(x, -hh * 0.7, w * 0.04, h * 0.7)));
            }
            v.push(face(rect(hw - w * 0.08, -hh * 0.55, w * 0.08, h * 0.55)));
        }

        // ---- soft sources
        Look::Ball => {
            v.push(shape(ellipse(0.0, 0.0, hw, hh), Ink::Role("silk"), Ink::Role("fixtureline"), 0.9));
            for k in [0.72, 0.45] {
                v.push(faint(edge(ellipse(0.0, 0.0, hw * k, hh * k), 0.6), 0.7));
            }
            v.push(face(ellipse(0.0, 0.0, hw * 0.16, hh * 0.16)));
        }
        Look::Spacelight => {
            v.push(shape(ellipse(0.0, 0.0, hw, hh), Ink::Role("silk"), Ink::Role("fixtureline"), 0.9));
            v.push(housing(ellipse(0.0, 0.0, hw * 0.5, hh * 0.5)));
            for i in 0..6 {
                let a = (i as f64 * 60.0f64).to_radians();
                v.push(face(ellipse(a.cos() * hw * 0.3, a.sin() * hh * 0.3, hw * 0.08, hh * 0.08)));
            }
            v.push(knob(ellipse(0.0, 0.0, hw * 0.08, hh * 0.08)));
        }
        Look::Parabolic => {
            // Briese, a Light Dome, a para: the bowl opening ahead, its ribs
            // running back to the lamp.
            let back = -hw;
            let mut bowl = vec![Seg::M(hw, -hh)];
            bowl.push(Seg::C(back + w * 0.35, -hh, back, -hh * 0.55, back, 0.0));
            bowl.push(Seg::C(back, hh * 0.55, back + w * 0.35, hh, hw, hh));
            bowl.push(Seg::Z);
            v.push(housing(bowl));
            let n = 8;
            for i in 0..=n {
                let y = -hh + h * i as f64 / n as f64;
                v.push(faint(edge(line(back + w * 0.12, y * 0.12, hw, y), 0.6), 0.75));
            }
            v.push(face(rect(hw - w * 0.035, -hh, w * 0.035, h)));
            v.push(knob(ellipse(back + w * 0.12, 0.0, w * 0.05, hh * 0.08)));
        }
        Look::Softbox => {
            let ring = -hw + w * 0.15;
            v.push(knob(rect(-hw, -hh * 0.18, ring + hw, hh * 0.36)));
            v.push(housing(poly(&[(ring, -hh * 0.22), (hw, -hh), (hw, hh), (ring, hh * 0.22)], true)));
            v.push(faint(edge(line(ring, -hh * 0.22, hw, -hh * 0.33), 0.6), 0.7));
            v.push(faint(edge(line(ring, hh * 0.22, hw, hh * 0.33), 0.6), 0.7));
            v.push(shape(rect(hw - w * 0.04, -hh, w * 0.04, h), Ink::Role("silk"), Ink::Role("lightline"), 0.8));
        }

        // ---- practicals
        Look::Bulb => {
            v.push(face(ellipse(0.0, 0.0, hw, hh)));
            v.push(shape(ellipse(0.0, 0.0, hw * 0.45, hh * 0.45), Ink::Role("lightface"), Ink::None, 0.0));
        }
        Look::Shade => {
            v.push(shape(ellipse(0.0, 0.0, hw, hh), Ink::Role("silk"), Ink::Role("fixtureline"), 1.0));
            v.push(faint(edge(ellipse(0.0, 0.0, hw * 0.55, hh * 0.55), 0.6), 0.7));
            v.push(face(ellipse(0.0, 0.0, hw * 0.25, hh * 0.25)));
        }
        Look::StreetLight => {
            v.push(knob(ellipse(-hw * 0.85, 0.0, w * 0.1, w * 0.1)));
            v.push(edge(line(-hw * 0.85, 0.0, hw * 0.3, 0.0), 2.0));
            v.push(housing(rrect(hw * 0.2, -hh, hw * 0.8, h, hh * 0.9)));
            v.push(face(ellipse(hw * 0.6, 0.0, hw * 0.28, hh * 0.6)));
        }
        Look::WallLight => {
            v.push(knob(rect(-hw, -hh, w * 0.15, h)));
            v.push(housing(rrect(-hw + w * 0.15, -hh * 0.85, w * 0.7, h * 0.85, 0.02)));
            v.push(face(rect(hw * 0.7, -hh * 0.8, w * 0.15, h * 0.8)));
        }
        Look::Torch => {
            v.push(housing(rrect(-hw, -hh * 0.6, w * 0.75, h * 0.6, hh * 0.5)));
            v.push(housing(poly(&[(hw * 0.5, -hh * 0.6), (hw * 0.85, -hh), (hw * 0.85, hh), (hw * 0.5, hh * 0.6)], true)));
            v.push(face(rect(hw * 0.85, -hh, w * 0.15, h)));
        }

        // ---- grip
        Look::Flag(cloth) => {
            let standing = w < h * 0.3 || h < w * 0.3;
            if standing {
                // Seen edge-on from above: the frame, the arm back to its
                // stand and the knuckle.
                let long_y = h >= w;
                let (len, thick) = if long_y { (h, w) } else { (w, h) };
                let bar = rect(-hw, -hh, w, h);
                v.push(shape(bar, cloth_fill(cloth), frame_ink(cloth), 1.4));
                let arm = (len * 0.5).clamp(0.25, 0.9);
                if long_y {
                    v.push(grip_line(line(-hw, 0.0, -hw - arm, 0.0), 1.3));
                    v.push(grip_solid(circle(-hw - arm, 0.0, (thick * 0.6).max(0.035))));
                } else {
                    v.push(grip_line(line(0.0, hh, 0.0, hh + arm), 1.3));
                    v.push(grip_solid(circle(0.0, hh + arm, (thick * 0.6).max(0.035))));
                }
            } else {
                // Face-on: the cloth in its frame, and the pin it hangs from.
                v.push(shape(rect(-hw, -hh, w, h), cloth_fill(cloth), frame_ink(cloth), 2.0));
                cloth_detail(&mut v, cloth, w, h);
                v.push(grip_line(line(-hw, 0.0, -hw - (w * 0.2).min(0.2), 0.0), 1.3));
                v.push(grip_line(line(-hw - (w * 0.2).min(0.2), -hh * 0.2, -hw - (w * 0.2).min(0.2), hh * 0.2), 1.3));
            }
        }
        Look::Rag(cloth) => {
            let standing = w < h * 0.3 || h < w * 0.3;
            if standing {
                // A frame on two stands, seen edge-on.
                v.push(shape(rect(-hw, -hh, w, h), cloth_fill(cloth), frame_ink(cloth), 1.6));
                let r = (w.min(h) * 0.9).clamp(0.05, 0.12);
                let long_y = h >= w;
                for s in [-1.0, 1.0] {
                    let (x, y) = if long_y { (0.0, s * hh) } else { (s * hw, 0.0) };
                    v.push(grip_solid(circle(x, y, r)));
                }
            } else {
                v.push(shape(rect(-hw, -hh, w, h), cloth_fill(cloth), frame_ink(cloth), 2.0));
                cloth_detail(&mut v, cloth, w, h);
                // The corner ears a rag is tied off at.
                let k = (w.min(h) * 0.07).clamp(0.08, 0.3);
                for (sx, sy) in [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)] {
                    let (cx, cy) = (sx * hw, sy * hh);
                    v.push(grip_solid(poly(&[(cx, cy), (cx - sx * k, cy), (cx, cy - sy * k)], true)));
                }
            }
        }
        Look::Board(board) => {
            let (fill, stroke, lw): (Ink, Ink, f64) = match board {
                Board::Foam | Board::Card => (Ink::Role("silk"), Ink::Role("grip"), 1.0),
                Board::Shiny => (Ink::Role("fixture"), Ink::hex("#E07A2E"), 2.0),
                Board::Neg => (Ink::Role("screen"), Ink::Role("grip"), 1.0),
                Board::Reflector => (Ink::Role("fixture"), Ink::Role("fixtureline"), 1.2),
            };
            let r = if board == Board::Reflector { (w.min(h) * 0.12).min(0.08) } else { 0.0 };
            v.push(shape(rrect(-hw, -hh, w, h, r), fill, stroke, lw));
            if board == Board::Shiny && w > h * 0.3 && h > w * 0.3 {
                let n = repeats(w.min(h) / 0.12, 3).min(14);
                let mut dots = Vec::new();
                for i in 0..n {
                    for j in 0..n {
                        let x = -hw + w * (i as f64 + 0.5) / n as f64;
                        let y = -hh + h * (j as f64 + 0.5) / n as f64;
                        dots.extend(circle(x, y, w.min(h) * 0.018));
                    }
                }
                v.push(faint(knob(dots), 0.6));
            }
            if board == Board::Reflector {
                v.push(faint(edge(rrect(-hw * 0.8, -hh * 0.8, w * 0.8, h * 0.8, r * 0.7), 0.6), 0.7));
            }
        }

        // ---- stands
        Look::CStand => {
            // The turtle base: three legs, one long, and the gobo arm.
            let legs = [(-90.0, 1.0), (30.0, 0.82), (150.0, 0.64)];
            for (a, k) in legs {
                let a = f64::to_radians(a);
                v.push(grip_line(line(0.0, 0.0, a.cos() * hw * k, a.sin() * hh * k), 1.6));
            }
            v.push(grip_solid(circle(0.0, 0.0, 0.05)));
            v.push(grip_line(line(0.0, 0.0, hw * 0.95, hh * 0.3), 1.1));
            v.push(grip_solid(circle(hw * 0.35, hh * 0.105, 0.035)));
        }
        Look::Combo | Look::Roller | Look::Crank => {
            let reach = if look == Look::Crank { 1.0 } else { 0.95 };
            for i in 0..3 {
                let a = (i as f64 * 120.0 - 90.0f64).to_radians();
                let (x, y) = (a.cos() * hw * reach, a.sin() * hh * reach);
                v.push(grip_line(line(0.0, 0.0, x, y), if look == Look::Crank { 2.2 } else { 1.7 }));
                if look == Look::Roller {
                    v.push(grip_solid(circle(x, y, (w * 0.06).max(0.04))));
                }
            }
            if look == Look::Crank {
                let pts: Vec<(f64, f64)> = (0..3)
                    .map(|i| {
                        let a = (i as f64 * 120.0 - 90.0f64).to_radians();
                        (a.cos() * hw * 0.55, a.sin() * hh * 0.55)
                    })
                    .collect();
                v.push(grip_line(poly(&pts, true), 1.0));
            }
            v.push(grip_solid(circle(0.0, 0.0, (w * 0.08).max(0.05))));
        }
        Look::Sticks => {
            for i in 0..3 {
                let a = (i as f64 * 120.0 + 90.0f64).to_radians();
                let (x, y) = (a.cos() * hw, a.sin() * hh);
                v.push(grip_line(line(0.0, 0.0, x, y), 2.4));
                v.push(grip_solid(circle(x, y, 0.03)));
            }
            let spread: Vec<(f64, f64)> = (0..3)
                .map(|i| {
                    let a = (i as f64 * 120.0 + 90.0f64).to_radians();
                    (a.cos() * hw * 0.5, a.sin() * hh * 0.5)
                })
                .collect();
            v.push(faint(grip_line(poly(&spread, true), 0.8), 0.7));
            v.push(shape(circle(0.0, 0.0, w.min(h) * 0.13), Ink::Role("fixture"), Ink::Role("grip"), 1.0));
        }
        Look::Polecat | Look::Rail => {
            let thick = h.min(0.06);
            v.push(shape(rrect(-hw, -thick / 2.0, w, thick, thick / 2.0), Ink::Role("fixture"), Ink::Role("grip"), 1.0));
            if look == Look::Polecat {
                for x in [-hw, hw - 0.06] {
                    v.push(grip_solid(rrect(x, -thick, 0.06, thick * 2.0, 0.01)));
                }
            }
        }
        Look::Slider => {
            for y in [-hh * 0.55, hh * 0.55] {
                v.push(grip_line(line(-hw, y, hw, y), 1.6));
            }
            for x in [-hw, hw - w * 0.05] {
                v.push(grip_solid(rrect(x, -hh, w * 0.05, h, 0.01)));
            }
            v.push(shape(rrect(-w * 0.08, -hh * 0.9, w * 0.16, h * 0.9, 0.01), Ink::Role("fixture"), Ink::Role("grip"), 1.0));
        }
        Look::Track => {
            let every = (w / 60.0).max(0.3);
            let mut x = -hw + every / 2.0;
            while x < hw {
                v.push(faint(grip_line(line(x, -hh, x, hh), 1.2), 0.8));
                x += every;
            }
            for y in [-hh * 0.75, hh * 0.75] {
                v.push(grip_line(line(-hw, y, hw, y), 2.0));
            }
        }
        Look::Curve | Look::Circle => {
            // Track on a radius: two rails, ties across. A circle is the whole
            // ring; a curve is a quarter of one, its centre off to the west.
            let (cx, r, a0, a1) = if look == Look::Circle { (0.0, hw, 0.0, 360.0) } else { (-hw * 2.0, (hw * 3.0).max(0.1), -25.0, 25.0) };
            let gauge = 0.3_f64.min(r * 0.2);
            for rr in [r - gauge, r + gauge] {
                v.push(grip_line(arc(cx, 0.0, rr, a0, a1, false), 2.0));
            }
            let ties = if look == Look::Circle { 16 } else { 6 };
            for i in 0..=ties {
                let a = (a0 + (a1 - a0) * i as f64 / ties as f64).to_radians();
                v.push(faint(
                    grip_line(line(cx + (r - gauge * 1.3) * a.cos(), (r - gauge * 1.3) * a.sin(), cx + (r + gauge * 1.3) * a.cos(), (r + gauge * 1.3) * a.sin()), 1.2),
                    0.8,
                ));
            }
        }

        // ---- dollies and cranes
        Look::Dana => {
            for y in [-hh * 0.6, hh * 0.6] {
                v.push(grip_line(line(-hw, y, hw, y), 1.8));
            }
            for x in [-hw, hw - 0.06] {
                v.push(grip_solid(rect(x, -hh, 0.06, h)));
            }
            v.push(shape(rrect(-w * 0.06, -hh * 0.8, w * 0.12, h * 0.8, 0.02), Ink::Role("fixture"), Ink::Role("grip"), 1.0));
            v.push(shape(circle(0.0, 0.0, h * 0.22), Ink::Role("setsoft"), Ink::Role("grip"), 1.0));
        }
        Look::Doorway => {
            for (x, y) in [(-hw * 0.7, -hh), (hw * 0.7, -hh), (-hw * 0.7, hh), (hw * 0.7, hh)] {
                v.push(grip_solid(rrect(x - w * 0.09, y - h * 0.06, w * 0.18, h * 0.12, 0.02)));
            }
            v.push(shape(rrect(-hw * 0.95, -hh * 0.9, w * 0.95, h * 0.9, 0.04), Ink::Role("setsoft"), Ink::Role("setline"), 1.0));
            v.push(grip_line(poly(&[(-hw * 0.95, -hh * 0.4), (-hw - 0.25, -hh * 0.4), (-hw - 0.25, hh * 0.4), (-hw * 0.95, hh * 0.4)], false), 1.4));
            v.push(faint(edge(circle(hw * 0.2, 0.0, h * 0.2), 0.8), 0.8));
        }
        Look::Fisher | Look::Chapman => {
            // A studio dolly: its wheels at the corners, the body, and the
            // arm or column the camera rides on.
            for (x, y) in [(-hw * 0.75, -hh), (hw * 0.75, -hh), (-hw * 0.75, hh), (hw * 0.75, hh)] {
                v.push(grip_solid(ellipse(x, y, w * 0.12, h * 0.12)));
            }
            v.push(shape(rrect(-hw * 0.9, -hh * 0.82, w * 0.9, h * 0.82, 0.06), Ink::Role("setsoft"), Ink::Role("setline"), 1.0));
            if look == Look::Fisher {
                v.push(housing(rrect(-hw * 0.6, -hh * 0.18, w * 0.95, h * 0.18, h * 0.09)));
                v.push(housing(circle(hw * 0.75, 0.0, h * 0.2)));
                v.push(soft(circle(-hw * 0.6, -hh * 0.55, h * 0.16)));
            } else {
                v.push(housing(circle(0.0, 0.0, h * 0.26)));
                v.push(housing(circle(hw * 0.55, 0.0, h * 0.16)));
            }
        }
        Look::Jib | Look::Menace | Look::Technocrane => {
            // The arm: counterweight behind the pivot, the head at the tip.
            let pivot = -hw + w * 0.25;
            if look == Look::Technocrane {
                for (x, y) in [(-hw, -hh), (-hw, hh), (pivot + w * 0.05, -hh), (pivot + w * 0.05, hh)] {
                    v.push(grip_solid(ellipse(x + w * 0.04, y, w * 0.04, h * 0.12)));
                }
                v.push(shape(rrect(-hw, -hh * 0.8, w * 0.33, h * 0.8, 0.05), Ink::Role("setsoft"), Ink::Role("setline"), 1.0));
                let mut x = pivot;
                let mut t = h * 0.3;
                for _ in 0..3 {
                    let len = (hw - x) / 2.2;
                    v.push(housing(rect(x, -t / 2.0, len * 1.2, t)));
                    x += len;
                    t *= 0.75;
                }
            } else {
                for i in 0..3 {
                    let a = (i as f64 * 120.0 - 90.0f64).to_radians();
                    v.push(grip_line(line(pivot, 0.0, pivot + a.cos() * h * 0.5, a.sin() * hh), 1.6));
                }
                v.push(housing(poly(&[(-hw + w * 0.08, -h * 0.12), (hw - w * 0.05, -h * 0.05), (hw - w * 0.05, h * 0.05), (-hw + w * 0.08, h * 0.12)], true)));
            }
            v.push(knob(rrect(-hw, -h * 0.2, w * 0.1, h * 0.4, 0.02)));
            v.push(grip_solid(circle(pivot, 0.0, h * 0.1)));
            v.push(shape(circle(hw - w * 0.03, 0.0, h * 0.12), Ink::Role("fixture"), Ink::Role("grip"), 1.2));
        }
        Look::Arm => {
            // A Russian arm: the car, and the arm reaching off its roof.
            v.push(shape(rrect(-hw, -hh * 0.6, w * 0.62, h * 0.6, h * 0.12), Ink::Role("vehicle"), Ink::Role("setline"), 1.0));
            v.push(soft(rrect(-hw + w * 0.12, -hh * 0.45, w * 0.3, h * 0.45, 0.06)));
            v.push(housing(poly(&[(-hw + w * 0.3, -h * 0.05), (hw - w * 0.08, -h * 0.03), (hw - w * 0.08, h * 0.03), (-hw + w * 0.3, h * 0.05)], true)));
            v.push(grip_solid(circle(-hw + w * 0.3, 0.0, h * 0.08)));
            v.push(shape(circle(hw - w * 0.05, 0.0, h * 0.09), Ink::Role("fixture"), Ink::Role("grip"), 1.2));
        }
        Look::Easyrig => {
            // The operator from above: shoulders in the vest, the head, the
            // rod over the head and the camera hanging out front.
            let body = -hw * 0.35;
            v.push(shape(ellipse(body, 0.0, w * 0.16, hh * 0.9), Ink::Role("setsoft"), Ink::Role("setline"), 1.0));
            v.push(shape(ellipse(body + w * 0.04, 0.0, w * 0.1, hh * 0.32), Ink::Role("set"), Ink::Role("setline"), 1.0));
            v.push(grip_line(line(-hw, 0.0, hw * 0.55, 0.0), 2.0));
            v.push(grip_line(line(hw * 0.55, 0.0, hw * 0.55, hh * 0.25), 1.0));
            v.push(camera_block(hw * 0.55, hh * 0.25, w * 0.35, h * 0.3));
        }
        Look::Condor => {
            v.push(shape(rrect(-hw, -hh * 0.5, w * 0.55, h * 0.5, 0.1), Ink::Role("vehicle"), Ink::Role("setline"), 1.0));
            for x in [-hw * 0.8, -hw * 0.2] {
                for y in [-hh * 0.55, hh * 0.55] {
                    v.push(grip_solid(rrect(x, y - h * 0.05, w * 0.08, h * 0.1, 0.02)));
                }
            }
            v.push(housing(poly(&[(-hw * 0.5, -h * 0.05), (hw * 0.75, -h * 0.03), (hw * 0.75, h * 0.03), (-hw * 0.5, h * 0.05)], true)));
            v.push(shape(rect(hw * 0.72, -hh * 0.3, w * 0.14, h * 0.3), Ink::Role("setsoft"), Ink::Role("setline"), 1.2));
        }
        Look::Lift => {
            v.push(shape(rect(-hw, -hh, w, h), Ink::Role("setsoft"), Ink::Role("setline"), 1.2));
            let n = repeats(w / 0.2, 2).min(20);
            for i in 1..n {
                let x = -hw + w * i as f64 / n as f64;
                v.push(faint(edge(line(x, -hh, x, hh), 0.5), 0.6));
            }
            v.push(edge(rect(-hw + w * 0.05, -hh + h * 0.05, w * 0.9, h * 0.9), 1.4));
        }
        Look::Truss(chords) => {
            let ys: Vec<f64> = if chords >= 3 { vec![-hh, 0.0, hh] } else { vec![-hh, hh] };
            for y in &ys {
                v.push(grip_line(line(-hw, *y, hw, *y), 1.6));
            }
            let bay = (h * 1.2).max(0.2);
            let n = repeats(w / bay, 1);
            for i in 0..n {
                let x0 = -hw + w * i as f64 / n as f64;
                let x1 = -hw + w * (i + 1) as f64 / n as f64;
                let (ya, yb) = if i % 2 == 0 { (-hh, hh) } else { (hh, -hh) };
                v.push(faint(grip_line(line(x0, ya, x1, yb), 1.0), 0.85));
                v.push(faint(grip_line(line(x0, -hh, x0, hh), 0.8), 0.7));
            }
            v.push(faint(grip_line(line(hw, -hh, hw, hh), 0.8), 0.7));
        }

        // ---- base camp
        Look::Distro => {
            v.push(shape(rrect(-hw, -hh, w, h, 0.03), Ink::Role("setsoft"), Ink::Role("setline"), 1.0));
            let n = repeats(w / 0.14, 2).min(10);
            for i in 0..n {
                let x = -hw + w * (i as f64 + 0.5) / n as f64;
                v.push(knob(circle(x, hh * 0.45, (w / n as f64 * 0.28).min(h * 0.18))));
            }
            v.push(faint(edge(line(-hw, -hh * 0.1, hw, -hh * 0.1), 0.7), 0.8));
        }
        Look::TowGen => {
            v.push(grip_line(line(-hw, 0.0, -hw + w * 0.18, 0.0), 1.6));
            v.push(grip_solid(circle(-hw, 0.0, 0.05)));
            v.push(shape(rrect(-hw + w * 0.18, -hh, w * 0.82, h, 0.06), Ink::Role("setsoft"), Ink::Role("setline"), 1.0));
            for i in 1..8 {
                let x = -hw + w * 0.25 + w * 0.45 * i as f64 / 8.0;
                v.push(faint(edge(line(x, -hh * 0.7, x, hh * 0.7), 0.6), 0.8));
            }
            for y in [-hh - 0.04, hh - 0.08] {
                v.push(grip_solid(rrect(w * 0.1, y, w * 0.18, 0.12, 0.03)));
            }
        }
        Look::Cart => {
            v.push(shape(rrect(-hw, -hh, w, h, 0.03), Ink::Role("setsoft"), Ink::Role("setline"), 1.0));
            v.push(shape(rect(-hw * 0.7, -hh * 0.85, w * 0.7, h * 0.12), Ink::Role("screen"), Ink::None, 0.0));
            v.push(shape(rect(-hw * 0.5, -hh * 0.3, w * 0.5, h * 0.4), Ink::Role("set"), Ink::Role("setline"), 0.8));
            for (x, y) in [(-hw, -hh), (hw, -hh), (-hw, hh), (hw, hh)] {
                v.push(grip_solid(circle(x, y, 0.035)));
            }
        }
        Look::Crafty => {
            v.push(shape(rect(-hw, -hh, w, h), Ink::Role("set"), Ink::Role("setline"), 1.0));
            let n = repeats(w / 0.35, 2).min(10);
            for i in 0..n {
                let x = -hw + w * (i as f64 + 0.5) / n as f64;
                v.push(soft(circle(x, -hh * 0.2, (h * 0.16).min(w / n as f64 * 0.35))));
            }
        }
        Look::Canopy => {
            v.push(shape(rect(-hw, -hh, w, h), Ink::Role("silk"), Ink::Role("setline"), 1.0));
            v.push(faint(edge(line(-hw, -hh, hw, hh), 0.7), 0.8));
            v.push(faint(edge(line(hw, -hh, -hw, hh), 0.7), 0.8));
            for (x, y) in [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)] {
                v.push(grip_solid(circle(x, y, 0.05)));
            }
        }
        Look::Hazer => {
            v.push(shape(rrect(-hw, -hh, w * 0.8, h, 0.03), Ink::Role("setsoft"), Ink::Role("setline"), 1.0));
            v.push(housing(rect(hw * 0.6, -hh * 0.3, w * 0.2, h * 0.3)));
            v.push(faint(shape(circle(hw * 0.95, 0.0, hh * 0.35), Ink::Role("silk"), Ink::None, 0.0), 0.8));
        }
        Look::Fan => {
            v.push(shape(ellipse(0.0, 0.0, hw, hh), Ink::Role("setsoft"), Ink::Role("setline"), 1.2));
            for i in 0..4 {
                let a = (i as f64 * 90.0 + 20.0f64).to_radians();
                let b = a + 0.7;
                v.push(housing(poly(&[(0.0, 0.0), (a.cos() * hw * 0.85, a.sin() * hh * 0.85), (b.cos() * hw * 0.85, b.sin() * hh * 0.85)], true)));
            }
            v.push(knob(ellipse(0.0, 0.0, hw * 0.14, hh * 0.14)));
        }
        Look::Cone => {
            v.push(shape(rect(-hw, -hh, w, h), Ink::Role("tyre"), Ink::None, 0.0));
            v.push(shape(ellipse(0.0, 0.0, hw * 0.7, hh * 0.7), Ink::hex("#E8743B"), Ink::None, 0.0));
            v.push(shape(ellipse(0.0, 0.0, hw * 0.35, hh * 0.35), Ink::hex("#F4F4F4"), Ink::None, 0.0));
            v.push(shape(ellipse(0.0, 0.0, hw * 0.18, hh * 0.18), Ink::hex("#E8743B"), Ink::None, 0.0));
        }

        // ---- set pieces after the pack: back at the top, front below
        Look::Couch(seats) => {
            let seats = seats.max(1) as usize;
            let arm = (w * 0.1).clamp(0.14, 0.22);
            let back = h * 0.26;
            v.push(soft(rrect(-hw, -hh, w, h, 0.06)));
            v.push(soft(rrect(-hw, -hh, arm, h, 0.06)));
            v.push(soft(rrect(hw - arm, -hh, arm, h, 0.06)));
            let inner = w - 2.0 * arm;
            let cw = inner / seats as f64;
            for i in 0..seats {
                let x = -hw + arm + cw * i as f64;
                v.push(body(rrect(x + 0.015, -hh + back, cw - 0.03, h - back - 0.02, 0.05)));
                let mut tufts = Vec::new();
                for (tx, ty) in [(0.3, 0.35), (0.7, 0.35), (0.5, 0.68)] {
                    tufts.extend(circle(x + cw * tx, -hh + back + (h - back) * ty, 0.012));
                }
                v.push(shape(tufts, Ink::Role("setink"), Ink::None, 0.0));
            }
        }
        Look::Chair | Look::OfficeChair => {
            let office = look == Look::OfficeChair;
            if office {
                v.push(soft(rrect(-hw, -hh * 0.3, w * 0.12, h * 0.9, 0.03)));
                v.push(soft(rrect(hw - w * 0.12, -hh * 0.3, w * 0.12, h * 0.9, 0.03)));
            }
            let sw = if office { w * 0.7 } else { w };
            v.push(body(rrect(-sw / 2.0, -hh + h * 0.18, sw, h * 0.82, sw * 0.35)));
            v.push(soft(rrect(-sw * 0.55, -hh, sw * 1.1, h * 0.16, h * 0.08)));
        }
        Look::Table(round) => {
            if round {
                v.push(wood(ellipse(0.0, 0.0, hw, hh)));
                v.push(faint(set_detail(ellipse(0.0, 0.0, hw * 0.9, hh * 0.9)), 0.5));
            } else {
                v.push(wood(rrect(-hw, -hh, w, h, 0.03)));
                v.push(faint(set_detail(rrect(-hw + 0.04, -hh + 0.04, w - 0.08, h - 0.08, 0.02)), 0.5));
            }
        }
        Look::HalfRound => {
            v.push(shape(skirted_half(w, h), Ink::Role("muslin"), Ink::Role("setline"), 1.0));
        }
        Look::Bed(people) => {
            v.push(body(rrect(-hw, -hh, w, h, 0.04)));
            v.push(soft(rect(-hw, -hh, w, h * 0.06)));
            let pillows = if w > 1.2 { 2 } else { 1 };
            let pw = (w - 0.2) / pillows as f64 - 0.06;
            for i in 0..pillows {
                let x = -hw + 0.1 + i as f64 * (pw + 0.12);
                v.push(body(rrect(x, -hh + h * 0.09, pw, h * 0.15, 0.08)));
            }
            // The covers, turned down at the top, and whoever is under them.
            v.push(soft(rrect(-hw, -hh + h * 0.33, w, h * 0.67, 0.03)));
            v.push(set_detail(line(-hw, -hh + h * 0.41, hw, -hh + h * 0.41)));
            sleepers(&mut v, people.min(2), w, h);
        }
        Look::Car | Look::Pickup => {
            // Facing east: bonnet, windscreen, roof, rear window — and for a
            // pickup, the bed behind the cab.
            let pickup = look == Look::Pickup;
            let mut car = body(rrect(-hw, -hh, w, h, h * 0.22));
            car.fill = Ink::Role("vehicle");
            v.push(car);
            for y in [-hh - 0.07, hh - 0.03] {
                v.push(shape(rrect(hw - w * 0.36, y, 0.12, 0.1, 0.03), Ink::Role("vehicle"), Ink::Role("setline"), 0.8));
            }
            let screen_at = if pickup { hw - w * 0.3 } else { hw - w * 0.32 };
            let roof_back = if pickup { -hw + w * 0.46 } else { -hw + w * 0.22 };
            v.push(faint(set_detail(line(hw - w * 0.08, -hh * 0.5, screen_at, -hh * 0.62)), 0.7));
            v.push(faint(set_detail(line(hw - w * 0.08, hh * 0.5, screen_at, hh * 0.62)), 0.7));
            v.push(faint(shape(poly(&[(screen_at, -hh * 0.78), (screen_at - w * 0.12, -hh * 0.86), (screen_at - w * 0.12, hh * 0.86), (screen_at, hh * 0.78)], true), Ink::Role("screen"), Ink::None, 0.0), 0.75));
            v.push(body(rrect(roof_back, -hh * 0.84, screen_at - w * 0.12 - roof_back, h * 0.84, 0.1)));
            if pickup {
                let bed_w = roof_back - w * 0.03 + hw - 0.08;
                v.push(shape(rect(-hw + 0.08, -hh * 0.82, bed_w, h * 0.82), Ink::Role("setsoft"), Ink::Role("setline"), 1.0));
                let n = repeats(bed_w / 0.25, 3).min(12);
                for i in 1..n {
                    let x = -hw + 0.08 + bed_w * i as f64 / n as f64;
                    v.push(faint(set_detail(line(x, -hh * 0.82, x, hh * 0.82)), 0.6));
                }
            } else {
                v.push(faint(shape(poly(&[(roof_back, -hh * 0.8), (roof_back - w * 0.08, -hh * 0.72), (roof_back - w * 0.08, hh * 0.72), (roof_back, hh * 0.8)], true), Ink::Role("screen"), Ink::None, 0.0), 0.75));
            }
        }
        Look::Tree => {
            v.push(faint(shape(lumpy(0.0, 0.0, hw * 0.92, hh * 0.92, 9.0, 0.07), Ink::Role("plant"), Ink::Role("setline"), 0.8), 0.6));
            v.push(faint(shape(lumpy(-hw * 0.1, -hh * 0.08, hw * 0.55, hh * 0.55, 7.0, 0.1), Ink::None, Ink::Role("setline"), 0.6), 0.5));
            v.push(shape(circle(0.0, 0.0, w.min(h) * 0.05), Ink::Role("trunk"), Ink::None, 0.0));
        }
        Look::Hedge => {
            v.push(faint(shape(lumpy(0.0, 0.0, hw * 0.97, hh * 0.85, 22.0, 0.05), Ink::Role("plant"), Ink::Role("setline"), 0.8), 0.6));
        }
        Look::Stump => {
            v.push(shape(lumpy(0.0, 0.0, hw * 0.95, hh * 0.95, 11.0, 0.06), Ink::Role("wood"), Ink::Role("trunk"), 1.2));
            for k in [0.7, 0.45, 0.22] {
                v.push(faint(shape(lumpy(0.0, 0.0, hw * k, hh * k, 9.0, 0.05), Ink::None, Ink::Role("trunk"), 0.7), 0.7));
            }
        }
        Look::Sidewalk => {
            v.push(shape(rect(-hw, -hh, w, h), Ink::Role("road"), Ink::Role("setline"), 0.8));
            let n = repeats(w / 1.5, 1);
            for i in 1..n {
                let x = -hw + w * i as f64 / n as f64;
                v.push(faint(set_detail(line(x, -hh, x, hh)), 0.8));
            }
        }
        Look::Seamless(c) => {
            // The roll up top, the paper swept forward and out to the floor.
            let ink = Ink::hex(PAPERS[(c as usize).min(PAPERS.len() - 1)]);
            let top = -hh + h * 0.12;
            let sweep = vec![
                Seg::M(-hw * 0.96, top),
                Seg::L(hw * 0.96, top),
                Seg::C(hw * 0.88, 0.0, hw * 0.88, hh * 0.4, hw, hh),
                Seg::L(-hw, hh),
                Seg::C(-hw * 0.88, hh * 0.4, -hw * 0.88, 0.0, -hw * 0.96, top),
                Seg::Z,
            ];
            v.push(shape(sweep, ink.clone(), Ink::Role("setline"), 0.8));
            v.push(shape(rrect(-hw, -hh, w, h * 0.12, h * 0.05), ink, Ink::Role("setline"), 1.0));
        }
        Look::Cyc(green) => {
            // A U of curved wall, open to the front: the curve drawn as a
            // band around the floor it wraps.
            let ink = if green { Ink::hex("#3FA34D") } else { Ink::hex("#EDEDEA") };
            let t = (w.min(h) * 0.22).max(0.4);
            let mut u = vec![Seg::M(-hw, hh), Seg::L(-hw, -hh + t)];
            u.extend(arc(-hw + t, -hh + t, t, 180.0, 270.0, true));
            u.push(Seg::L(hw - t, -hh));
            u.extend(arc(hw - t, -hh + t, t, 270.0, 360.0, true));
            u.push(Seg::L(hw, hh));
            u.push(Seg::L(hw - t, hh));
            u.push(Seg::L(hw - t, -hh + t * 1.6));
            u.extend(arc(hw - t * 1.6, -hh + t * 1.6, t * 0.6, 0.0, -90.0, true));
            u.push(Seg::L(-hw + t * 1.6, -hh + t));
            u.extend(arc(-hw + t * 1.6, -hh + t * 1.6, t * 0.6, 270.0, 180.0, true));
            u.push(Seg::L(-hw + t, hh));
            u.push(Seg::Z);
            v.push(shape(u, ink, Ink::Role("setline"), 1.0));
        }
        Look::PortableGen => {
            v.push(shape(rrect(-hw, -hh, w, h, 0.04), Ink::hex("#B5463C"), Ink::Role("setline"), 1.0));
            v.push(shape(rrect(-hw + w * 0.1, -hh + h * 0.05, w * 0.8, h * 0.22, 0.03), Ink::Role("set"), Ink::Role("setline"), 0.8));
            v.push(knob(circle(0.0, -hh + h * 0.16, w * 0.06)));
            for i in 1..6 {
                let y = -hh + h * 0.35 + h * 0.55 * i as f64 / 6.0;
                v.push(faint(edge(line(-hw + w * 0.12, y, hw - w * 0.12, y), 0.6), 0.7));
            }
        }
        Look::Projector => {
            v.push(shape(rrect(-hw, -hh, w * 0.92, h, 0.03), Ink::Role("setsoft"), Ink::Role("setline"), 1.0));
            v.push(face(circle(hw - w * 0.18, 0.0, h * 0.2)));
            for i in 1..5 {
                let y = -hh + h * i as f64 / 5.0;
                v.push(faint(edge(line(-hw + w * 0.08, y, -hw + w * 0.3, y), 0.6), 0.7));
            }
        }
        Look::Monitor => {
            // A production monitor on its stand: the screen, and the legs.
            for a in [-35.0f64, 35.0, 180.0] {
                let a = a.to_radians();
                v.push(grip_line(line(0.0, hh * 0.2, a.sin() * hw * 0.8, hh * 0.2 + a.cos() * hh * 0.8), 1.4));
            }
            v.push(shape(rrect(-hw, -hh, w, h * 0.35, 0.02), Ink::Role("screen"), Ink::Role("setline"), 1.0));
        }
    }
    v
}

fn body(segs: Vec<Seg>) -> Shape {
    shape(segs, Ink::Role("set"), Ink::Role("setline"), 1.0)
}
fn set_detail(segs: Vec<Seg>) -> Shape {
    shape(segs, Ink::None, Ink::Role("setink"), 0.8)
}
fn wood(segs: Vec<Seg>) -> Shape {
    shape(segs, Ink::Role("wood"), Ink::Role("setline"), 1.0)
}

/// An outline that is not quite round — a tree's canopy, a hedge, a stump —
/// the same bumps every time for the same size.
fn lumpy(cx: f64, cy: f64, rx: f64, ry: f64, bumps: f64, depth: f64) -> Vec<Seg> {
    let n = 48;
    let mut pts: Vec<(f64, f64)> = (0..n)
        .map(|i| {
            let a = i as f64 / n as f64 * std::f64::consts::TAU;
            let k = 1.0 + depth * (bumps * a).sin() * 0.6 + depth * ((bumps * 0.6 + 1.0) * a + 1.3).sin() * 0.4;
            (cx + a.cos() * rx * k, cy + a.sin() * ry * k)
        })
        .collect();
    pts.push(pts[0]);
    pts.push(pts[1]);
    let mut segs = smooth(&pts);
    segs.push(Seg::Z);
    segs
}

/// A half round in its cloth: the flat back along the top, the round toward
/// the front, scalloped where the skirt falls — a scallop about every ten
/// centimetres of edge, so a bigger table has more of them, not bigger ones.
fn skirted_half(w: f64, h: f64) -> Vec<Seg> {
    let (hw, hh) = (w / 2.0, h / 2.0);
    let r = hw.max(h).max(0.05);
    let scallops = ((std::f64::consts::PI * r / 0.1).round() as usize).clamp(6, 90);
    let depth = (0.02 / r).min(0.1);
    let n = scallops * 6;
    let pts: Vec<(f64, f64)> = (0..=n)
        .map(|i| {
            let a = i as f64 / n as f64 * std::f64::consts::PI;
            // The tips on the edge, the dips a little inside it.
            let k = 1.0 - depth + depth * (scallops as f64 * a).sin().abs();
            (a.cos() * hw * k, -hh + a.sin() * h * k)
        })
        .collect();
    let mut segs = smooth(&pts);
    segs.push(Seg::Z);
    segs
}

/// Whoever is in a bed, after the pack: a head on the pillow, shoulders and
/// arms out over the covers, the rest a shape under them. Sized from the
/// bed, so a stretched bed keeps its sleepers in proportion.
fn sleepers(v: &mut Vec<Shape>, n: u8, w: f64, h: f64) {
    let (hw, hh) = (w / 2.0, h / 2.0);
    let double = w > 1.2;
    let s = if double { w * 0.3 } else { w * 0.5 };
    for i in 0..n as usize {
        let cx = match (n, double) {
            (1, true) => -hw * 0.45,
            (1, false) => 0.0,
            _ => if i == 0 { -hw * 0.45 } else { hw * 0.45 },
        };
        let skin = Ink::Role("cast");
        v.push(faint(shape(ellipse(cx, -hh + h * 0.66, s * 0.42, h * 0.3), Ink::None, Ink::Role("setline"), 0.7), 0.6));
        v.push(faint(shape(rrect(cx - s / 2.0, -hh + h * 0.27, s, s * 0.3, s * 0.12), skin.clone(), Ink::Role("setline"), 0.8), 0.6));
        for side in [-1.0, 1.0] {
            v.push(faint(shape(rrect(cx + side * s * 0.44 - s * 0.08, -hh + h * 0.29, s * 0.16, s * 1.05, s * 0.08), skin.clone(), Ink::Role("setline"), 0.8), 0.6));
        }
        v.push(shape(circle(cx, -hh + h * 0.2, s * 0.22), Ink::Role("paper"), Ink::Role("setline"), 1.1));
    }
}

/// A camera body hung off a rig, facing east.
fn camera_block(x: f64, y: f64, w: f64, h: f64) -> Shape {
    shape(rrect(x - w / 2.0, y - h / 2.0 + h * 0.2, w, h * 0.6, h * 0.1), Ink::Role("fixture"), Ink::Role("grip"), 1.0)
}

fn cloth_fill(c: Cloth) -> Ink {
    match c {
        Cloth::Solid => Ink::Role("screen"),
        Cloth::Single | Cloth::Double | Cloth::Lcd => Ink::None,
        Cloth::Silk | Cloth::ArtSilk | Cloth::Bounce => Ink::Role("silk"),
        Cloth::Grid => Ink::Role("setsoft"),
        Cloth::Muslin => Ink::Role("muslin"),
    }
}

fn frame_ink(c: Cloth) -> Ink {
    match c {
        Cloth::Single => Ink::hex("#2F9E5A"),
        Cloth::Double => Ink::hex("#D6453D"),
        Cloth::ArtSilk => Ink::hex("#E3BC1E"),
        _ => Ink::Role("grip"),
    }
}

/// What a cloth looks like inside its frame: a net's weave, grid cloth's
/// lines, an LCD's fine dark grid.
pub(super) fn cloth_detail(v: &mut Vec<Shape>, c: Cloth, w: f64, h: f64) {
    let (hw, hh) = (w / 2.0, h / 2.0);
    match c {
        Cloth::Single | Cloth::Double | Cloth::Lcd => {
            let step = if c == Cloth::Lcd { 0.25 } else { 0.18 };
            let alpha = match c {
                Cloth::Single => 0.35,
                Cloth::Double => 0.6,
                _ => 0.5,
            };
            let (nx, ny) = (repeats(w / step, 2).min(40), repeats(h / step, 2).min(40));
            for i in 1..nx {
                let x = -hw + w * i as f64 / nx as f64;
                v.push(faint(shape(line(x, -hh, x, hh), Ink::None, Ink::Role("grip"), 0.5), alpha));
            }
            for j in 1..ny {
                let y = -hh + h * j as f64 / ny as f64;
                v.push(faint(shape(line(-hw, y, hw, y), Ink::None, Ink::Role("grip"), 0.5), alpha));
            }
        }
        Cloth::Grid => {
            let n = repeats(w.max(h) / 0.6, 3).min(16);
            for i in 1..n {
                let x = -hw + w * i as f64 / n as f64;
                let y = -hh + h * i as f64 / n as f64;
                v.push(faint(shape(line(x, -hh, x, hh), Ink::None, Ink::Role("setline"), 0.5), 0.5));
                v.push(faint(shape(line(-hw, y, hw, y), Ink::None, Ink::Role("setline"), 0.5), 0.5));
            }
        }
        Cloth::Silk | Cloth::ArtSilk => {
            v.push(faint(shape(rect(-hw * 0.88, -hh * 0.88, w * 0.88, h * 0.88), Ink::None, Ink::Role("setline"), 0.5), 0.4));
        }
        _ => {}
    }
}
