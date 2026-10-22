//! **Light levels** (Scenario's light estimates, 2026-09-28): how much light
//! lands on what each lamp is aimed at, and what that exposes as.
//!
//! - A lamp's **output** is its unit's candela at its beam (`output.rs`),
//!   times its dimmer, less its gels' stops.
//! - It falls off by the **inverse square** of the distance to its target,
//!   worked out in 3-D from the two heights (`height_of`).
//! - Grip on the way changes it: a solid or a bounce stops it, a net costs
//!   its stops, and a **diffusion** becomes a soft source of its own — a lit
//!   disc that falls off slower close to and faster far away — blended with
//!   what goes straight through, by how thin the skin is.
//! - A **bounce** a lamp is aimed at gives back what lands on it, less its
//!   skin's stops, as a lit disc toward what it is aimed at (or the cast in
//!   the way it throws), more to what lies nearer the mirror angle.
//! - **Omni** units — a space light, a china ball — light anything in range
//!   (three stops under the midtone or brighter), and draw a ring where they
//!   reach the midtone on the floor.
//! - The **sun** lights the cast it can see — walls stop it — flat, at the
//!   level its preset says; the room's **ambient** adds to everything.
//!
//! Everything lit on a piece **adds up**; the plan shows it as a ring round
//! the piece, coloured under → right → over the midtone, with its level
//! written in the plan's units ("f/4 +⅓", "850 lx", "79 fc"). A picked lamp
//! shows only what it gives; otherwise every lit piece shows its total.
//!
//! The midtone is the camera's: foot-candles = 25 · N² ÷ (ISO · t), the
//! cinematographer's incident-meter rule.

use std::borrow::Cow;

use super::render::{self, arc, circle, placed, Context, Geom, Ink, Options, Shape};
use super::shade::{self, Blocker};
use super::{frame, gels, output, symbols, Diagram, El, Kind, Pose, Settings};
use crate::json::Json;

pub const LUX_PER_FC: f64 = 10.763_910_4;

/// A plan setting's number, kept to a sane range.
pub fn within(v: Option<&Json>, lo: f64, hi: f64, or: f64) -> f64 {
    v.and_then(|x| x.as_f64()).filter(|x| x.is_finite()).map(|x| x.clamp(lo, hi)).unwrap_or(or)
}

// ---------------------------------------------------------------- exposure

/// The illuminance, in lux, that exposes as the midtone at the plan's ISO,
/// shutter and stop.
pub fn midtone(s: &Settings) -> f64 {
    25.0 * s.stop * s.stop * s.shutter / s.iso * LUX_PER_FC
}

/// The f-number a level calls for, at the plan's ISO and shutter.
pub fn f_number(lux: f64, s: &Settings) -> f64 {
    (lux / LUX_PER_FC * s.iso / s.shutter / 25.0).max(0.0).sqrt()
}

/// How many stops over (+) or under (−) the midtone a level is.
pub fn stops_over(lux: f64, s: &Settings) -> f64 {
    if lux <= 0.0 {
        return -12.0;
    }
    (lux / midtone(s)).log2()
}

/// The full stops, from f/0.5, each twice the light of the last.
const FULL: &[&str] = &["0.5", "0.7", "1", "1.4", "2", "2.8", "4", "5.6", "8", "11", "16", "22", "32", "45", "64", "90", "128"];

/// A level in the plan's units: `f/4 +⅓`, `850 lx`, `79 fc`.
pub fn words(lux: f64, s: &Settings) -> String {
    match s.light_units.as_str() {
        "lux" => format!("{} lx", round_level(lux)),
        "fc" => format!("{} fc", round_level(lux / LUX_PER_FC)),
        _ => {
            let n = f_number(lux, s);
            // Stops from f/1, to the nearest third.
            let k = if n > 0.0 { (2.0 * n.log2() * 3.0).round() / 3.0 } else { -99.0 };
            let full = (k + 1e-9).floor();
            let thirds = ((k - full) * 3.0).round() as i32;
            let at = (full as i64 + 2).clamp(0, FULL.len() as i64 - 1) as usize;
            if (full as i64 + 2) < 0 {
                return format!("Under f/{}", FULL[0]);
            }
            match thirds {
                1 => format!("f/{} +⅓", FULL[at]),
                2 => format!("f/{} +⅔", FULL[at]),
                _ => format!("f/{}", FULL[at]),
            }
        }
    }
}

/// Two figures that matter, the way a meter reads out: 850, 1200, 12, 3.4.
fn round_level(v: f64) -> String {
    if !v.is_finite() || v <= 0.0 {
        return "0".into();
    }
    if v < 10.0 {
        let r = (v * 10.0).round() / 10.0;
        return if (r - r.round()).abs() < 1e-9 { format!("{}", r as i64) } else { format!("{r:.1}") };
    }
    let mag = 10f64.powi(v.log10().floor() as i32 - 1);
    format!("{}", ((v / mag).round() * mag) as i64)
}

/// The ring's colour for so many stops over or under: blue under, green
/// right, amber to red over.
pub fn ring_hex(over: f64) -> String {
    const SCALE: [(f64, (f64, f64, f64)); 7] = [
        (-3.0, (59.0, 91.0, 219.0)),
        (-2.0, (76.0, 141.0, 246.0)),
        (-1.0, (48.0, 178.0, 196.0)),
        (0.0, (46.0, 170.0, 98.0)),
        (1.0, (226.0, 178.0, 34.0)),
        (2.0, (240.0, 124.0, 42.0)),
        (3.0, (224.0, 49.0, 49.0)),
    ];
    let o = if over.is_finite() { over.clamp(-3.0, 3.0) } else { -3.0 };
    let i = SCALE.iter().rposition(|s| s.0 <= o).unwrap_or(0).min(SCALE.len() - 2);
    let (a, b) = (SCALE[i], SCALE[i + 1]);
    let t = (o - a.0) / (b.0 - a.0);
    let mix = |p: f64, q: f64| (p + (q - p) * t).round().clamp(0.0, 255.0) as u8;
    format!("#{:02X}{:02X}{:02X}", mix(a.1 .0, b.1 .0), mix(a.1 .1, b.1 .1), mix(a.1 .2, b.1 .2))
}

// ---------------------------------------------------------------- heights

/// A height as typed or picked: a camera's words (`Eye Level`), or a length
/// (`7 ft`, `7' 6"`, `2.1 m`, `90 cm`). A bare number is in the plan's units.
pub fn parse_height(s: &str, metric: bool) -> Option<f64> {
    let t = s.trim().to_lowercase();
    if t.is_empty() {
        return None;
    }
    let named = [("ground", 0.15), ("low", 0.6), ("knee", 0.5), ("waist", 1.0), ("chest", 1.3), ("eye level", 1.6), ("high", 2.2), ("overhead", 3.0)];
    if let Some((_, h)) = named.iter().find(|(k, _)| *k == t) {
        return Some(*h);
    }
    let chars: Vec<char> = t.replace(',', ".").chars().collect();
    let (mut i, mut total, mut last): (usize, f64, Option<f64>) = (0, 0.0, None);
    let mut any = false;
    while i < chars.len() {
        if !(chars[i].is_ascii_digit() || chars[i] == '.') {
            i += 1;
            continue;
        }
        let start = i;
        while i < chars.len() && (chars[i].is_ascii_digit() || chars[i] == '.') {
            i += 1;
        }
        let v: f64 = chars[start..i].iter().collect::<String>().parse().ok()?;
        while i < chars.len() && chars[i] == ' ' {
            i += 1;
        }
        let rest: String = chars[i..].iter().collect();
        let units: [(&str, f64); 10] = [("mm", 0.001), ("cm", 0.01), ("m", 1.0), ("feet", 0.3048), ("foot", 0.3048), ("ft", 0.3048), ("'", 0.3048), ("inch", 0.0254), ("in", 0.0254), ("\"", 0.0254)];
        let unit = units.iter().find(|(u, _)| rest.starts_with(u));
        let each = match unit {
            Some((u, k)) => {
                i += u.chars().count();
                *k
            }
            None => match last {
                Some(k) if (k - 1.0).abs() < 1e-9 => 0.01,
                Some(k) if (k - 0.3048).abs() < 1e-9 => 0.0254,
                _ => {
                    if metric {
                        1.0
                    } else {
                        0.3048
                    }
                }
            },
        };
        total += v * each;
        last = Some(each);
        any = true;
    }
    (any && total.is_finite()).then(|| total.clamp(0.0, 100.0))
}

/// Where a piece's light is taken, in metres off the floor: its own height
/// if it has one, otherwise a lamp on a stand, a person's face, a set
/// piece's top, a frame's middle.
pub fn height_of(e: &El, metric: bool) -> f64 {
    if let Some(h) = parse_height(&e.height, metric) {
        return h;
    }
    match e.kind {
        Kind::Light if frame::effect(e).is_some() => 1.5,
        Kind::Light => 2.1,
        Kind::Cast => match Pose::parse(&e.pose) {
            Pose::Seated => 1.1,
            Pose::Lying => 0.4,
            _ => 1.5,
        },
        Kind::Camera => 1.6,
        Kind::Set => 0.9,
        _ => 1.0,
    }
}

// ---------------------------------------------------------------- a lamp

fn is_omni(e: &El) -> bool {
    symbols::omni(&e.sym)
}

/// What a lamp puts out now, in candela: its unit at its beam, its dimmer,
/// its own gels.
pub fn intensity(e: &El) -> f64 {
    let own = gels::sum(&e.gels);
    output::candela(e) * (e.dim / 100.0).clamp(0.0, 1.0) * 2f64.powf(-own.stops)
}

/// **A beam drawn to where it reaches the midtone** — at a person's height,
/// or for an omni unit on the floor — when levels are on. The drawing
/// shortens a beam for its gels itself (`gels::reach`), so what is handed
/// back is the reach before them.
pub fn reached<'a>(e: &'a El, d: &Diagram) -> Cow<'a, El> {
    if !super::render::levels_on(d) || e.kind != Kind::Light || !symbols::emits(&e.sym) {
        return Cow::Borrowed(e);
    }
    let r = midtone_reach(e, d);
    let own = gels::sum(&e.gels);
    let before = if own.stops > 0.0 { r / gels::reach(1.0, own.stops) } else { r };
    let mut owned = e.clone();
    owned.reach = before;
    Cow::Owned(owned)
}

/// How far across the floor a lamp still lights at the midtone.
pub fn midtone_reach(e: &El, d: &Diagram) -> f64 {
    let i = intensity(e);
    if i <= 0.0 {
        return 0.0;
    }
    let h = height_of(e, d.settings.units == "m");
    let drop = if is_omni(e) { h } else { h - 1.5 };
    let r2 = i / midtone(&d.settings) - drop * drop;
    if r2 <= 0.0 {
        0.15
    } else {
        r2.sqrt().clamp(0.15, 80.0)
    }
}

// ---------------------------------------------------------------- the light

/// One lamp's light on one piece.
#[derive(Clone, Debug, PartialEq)]
pub struct Lit {
    pub target: String,
    /// The lamp, the bounce, or `sun`.
    pub from: String,
    pub lux: f64,
    /// Which way the light comes from, seen from the piece: degrees
    /// clockwise from east.
    pub toward: f64,
    /// Through a diffusion or off a bounce: a soft source, which wraps.
    pub soft: bool,
}

/// Grip where it stands now.
struct Grip<'a> {
    el: &'a El,
    effect: frame::Effect,
    corners: [(f64, f64); 4],
    stops: f64,
    radius: f64,
}

fn grip_on<'a>(d: &'a Diagram, opt: &Options) -> Vec<Grip<'a>> {
    d.els
        .iter()
        .filter(|e| e.kind == Kind::Light && !e.hidden)
        .filter_map(|e| {
            let effect = frame::effect(e)?;
            let (x, y, rot) = placed(e, opt);
            let (w, h) = e.footprint(opt.beat);
            let face = e.h * frame::tall(e);
            Some(Grip {
                el: e,
                effect,
                corners: super::corners(x, y, w, h, rot),
                stops: gels::sum(&e.gels).stops,
                radius: (face / std::f64::consts::PI).sqrt().max(0.05),
            })
        })
        .collect()
}

fn inside(p: (f64, f64), c: &[(f64, f64); 4]) -> bool {
    let side = |a: (f64, f64), b: (f64, f64)| (b.0 - a.0) * (p.1 - a.1) - (b.1 - a.1) * (p.0 - a.0);
    let s: Vec<f64> = (0..4).map(|i| side(c[i], c[(i + 1) % 4])).collect();
    s.iter().all(|v| *v >= 0.0) || s.iter().all(|v| *v <= 0.0)
}

/// Light as it travels: from a point (a lamp) or a lit disc (a diffusion,
/// a bounce), placed so far along the way.
#[derive(Clone, Copy, Debug)]
enum Src {
    Point { cd: f64, at: f64 },
    Disc { exit: f64, r: f64, at: f64 },
}

impl Src {
    fn at(&self, s: f64) -> f64 {
        match *self {
            Src::Point { cd, at } => cd / (s - at).max(0.1).powi(2),
            Src::Disc { exit, r, at } => {
                let d = (s - at).max(0.0);
                exit * r * r / (r * r + d * d)
            }
        }
    }
    fn dim(&mut self, k: f64) {
        match self {
            Src::Point { cd, .. } => *cd *= k,
            Src::Disc { exit, .. } => *exit *= k,
        }
    }
}

/// The light that reaches `b` from `a` — 3-D, `a` and `b` carrying their
/// heights — leaving as `start`: walls stop it, grip changes it on the way.
/// `None` when something stops it. `beam` is the lamp's spread, for how big
/// a patch it lights on a diffusion. And whether it arrives soft.
#[allow(clippy::too_many_arguments)]
fn travel(a: (f64, f64, f64), b: (f64, f64, f64), start: Src, beam: f64, walls: &[Blocker], grip: &[Grip], skip: &[&str]) -> Option<(f64, bool)> {
    let (dx, dy) = (b.0 - a.0, b.1 - a.1);
    let flat = dx.hypot(dy);
    let whole = flat.hypot(b.2 - a.2);
    if whole < 1e-6 {
        return Some((start.at(0.1), false));
    }
    let soft = matches!(start, Src::Disc { .. });
    let crossed = crossings((a.0, a.1), (b.0, b.1), whole, walls, grip, skip)?;
    let mut soft = soft;
    let mut mix = vec![start];
    for (s, g) in crossed {
        match g.effect {
            frame::Effect::Cut | frame::Effect::Bounce(..) => return None,
            frame::Effect::Dim(stops) => {
                let k = 2f64.powf(-(stops + g.stops));
                mix.iter_mut().for_each(|m| m.dim(k));
            }
            frame::Effect::Diffuse(stops, _) => {
                let k = 2f64.powf(-(stops + g.stops));
                // How much goes straight through: most of a light skin,
                // little of a heavy one.
                let straight = 2f64.powf(-2.0 * stops).clamp(0.0, 1.0);
                let here: f64 = mix.iter().map(|m| m.at(s)).sum();
                let patch = mix
                    .iter()
                    .map(|m| match *m {
                        Src::Point { at, .. } => (s - at).max(0.1) * (beam.clamp(2.0, 170.0) / 2.0).to_radians().tan(),
                        Src::Disc { r, at, .. } => r + (s - at) * 1.2,
                    })
                    .fold(0.0, f64::max);
                mix.iter_mut().for_each(|m| m.dim(k * straight));
                mix.push(Src::Disc { exit: here * k * (1.0 - straight), r: patch.min(g.radius).max(0.05), at: s });
                soft = true;
            }
        }
    }
    Some((mix.iter().map(|m| m.at(whole)).sum(), soft))
}

/// What stands between `a` and `b` on the floor: `None` when a wall does;
/// otherwise the grip crossed, in order, each at its distance along a way
/// `whole` long.
fn crossings<'g, 'e>(a: (f64, f64), b: (f64, f64), whole: f64, walls: &[Blocker], grip: &'g [Grip<'e>], skip: &[&str]) -> Option<Vec<(f64, &'g Grip<'e>)>> {
    let (dx, dy) = (b.0 - a.0, b.1 - a.1);
    let flat = dx.hypot(dy);
    let mut crossed = Vec::new();
    if flat <= 1e-6 {
        return Some(crossed);
    }
    let dir = (dx / flat, dy / flat);
    let hits = |p: (f64, f64), q: (f64, f64)| shade::ray_hits(a, dir, p, q).filter(|t| *t > 1e-3 && *t < flat - 0.05);
    if walls.iter().any(|(p, q)| hits(*p, *q).is_some()) {
        return None;
    }
    for g in grip.iter().filter(|g| !skip.contains(&g.el.id.as_str()) && !inside(a, &g.corners)) {
        let c = &g.corners;
        let first = (0..4).filter_map(|i| hits(c[i], c[(i + 1) % 4])).fold(f64::MAX, f64::min);
        if first < f64::MAX {
            crossed.push((first / flat * whole, g));
        }
    }
    crossed.sort_by(|p, q| p.0.partial_cmp(&q.0).unwrap_or(std::cmp::Ordering::Equal));
    Some(crossed)
}

fn heading(from: (f64, f64), to: (f64, f64)) -> f64 {
    super::norm_deg((to.1 - from.1).atan2(to.0 - from.0).to_degrees())
}

/// **Every lamp's light on every piece it lights**, one entry a lamp a
/// piece. Ambient is not in it; it is added to totals.
pub fn contributions(d: &Diagram, ctx: &Context, opt: &Options, walls: &[Blocker]) -> Vec<Lit> {
    let metric = d.settings.units == "m";
    let mid = midtone(&d.settings);
    let grip = grip_on(d, opt);
    let mut out: Vec<Lit> = Vec::new();
    let at = |e: &El| -> (f64, f64, f64) {
        let (x, y) = if e.kind.is_line() {
            e.centre()
        } else {
            let p = placed(e, opt);
            (p.0, p.1)
        };
        (x, y, height_of(e, metric))
    };
    // What lands on each bounce: (lamp's light there, the way it comes in).
    let mut on_bounce: Vec<(&El, f64, (f64, f64), f64)> = Vec::new();

    for l in d.els.iter().filter(|l| l.kind == Kind::Light && !l.hidden && symbols::emits(&l.sym)) {
        let cd = intensity(l);
        if cd <= 0.0 {
            continue;
        }
        let (x, y, rot) = placed(l, opt);
        let h = height_of(l, metric);
        if is_omni(l) {
            // Everything in range: three stops under the midtone or more.
            for t in d.els.iter().filter(|t| matches!(t.kind, Kind::Cast | Kind::Set) && !t.hidden) {
                let p = at(t);
                if let Some((lux, soft)) = travel((x, y, h), p, Src::Point { cd, at: 0.0 }, 360.0, walls, &grip, &[&l.id, &t.id]) {
                    if lux >= mid / 8.0 {
                        out.push(Lit { target: t.id.clone(), from: l.id.clone(), lux, toward: heading((p.0, p.1), (x, y)), soft });
                    }
                }
            }
            continue;
        }
        let Some(t) = d.els.iter().find(|t| t.id == l.aim && !t.hidden) else { continue };
        let tip = render::Xf::new(x, y, rot).p(l.w / 2.0, 0.0);
        let p = at(t);
        let Some((lux, soft)) = travel((tip.0, tip.1, h), p, Src::Point { cd, at: 0.0 }, l.beam, walls, &grip, &[&l.id, &t.id]) else { continue };
        out.push(Lit { target: t.id.clone(), from: l.id.clone(), lux, toward: heading((p.0, p.1), (x, y)), soft });
        if let Some(frame::Effect::Bounce(..)) = frame::effect(t) {
            let dist = (p.0 - tip.0).hypot(p.1 - tip.1);
            let spot = dist * (l.beam.clamp(2.0, 170.0) / 2.0).to_radians().tan();
            on_bounce.push((t, lux, (p.0 - tip.0, p.1 - tip.1), spot));
        }
    }

    // Each bounce gives back what landed on it.
    let mut bounces: Vec<&El> = on_bounce.iter().map(|b| b.0).collect();
    bounces.dedup_by(|a, b| a.id == b.id);
    let mut seen: Vec<&str> = Vec::new();
    for f in bounces {
        if seen.contains(&f.id.as_str()) {
            continue;
        }
        seen.push(&f.id);
        let Some(frame::Effect::Bounce(stops, spread, _)) = frame::effect(f) else { continue };
        let lamps: Vec<_> = on_bounce.iter().filter(|b| b.0.id == f.id).collect();
        let landed: f64 = lamps.iter().map(|b| b.1).sum();
        let own = gels::sum(&f.gels).stops;
        let exit = landed * 2f64.powf(-(stops + own));
        let (fx, fy, frot) = placed(f, opt);
        let fh = height_of(f, metric);
        let g = grip.iter().find(|g| g.el.id == f.id);
        let r = lamps.iter().map(|b| b.3).fold(0.0, f64::max).min(g.map(|g| g.radius).unwrap_or(0.6)).max(0.05);
        // The face the light lands on, and the mirror angle — the lamps'
        // incoming directions, weighed by what each brings.
        let mut n = (frot.to_radians().cos(), frot.to_radians().sin());
        let (mut ix, mut iy) = (0.0, 0.0);
        for b in &lamps {
            let len = b.2 .0.hypot(b.2 .1).max(1e-6);
            ix += b.2 .0 / len * b.1;
            iy += b.2 .1 / len * b.1;
        }
        if ix * n.0 + iy * n.1 > 0.0 {
            n = (-n.0, -n.1);
        }
        let len = ix.hypot(iy).max(1e-9);
        let d_in = (ix / len, iy / len);
        let dn = d_in.0 * n.0 + d_in.1 * n.1;
        let mirror = (d_in.0 - 2.0 * dn * n.0, d_in.1 - 2.0 * dn * n.1);
        let mirror_deg = mirror.1.atan2(mirror.0).to_degrees();
        let aimed = !f.aim.is_empty();
        let targets: Vec<&El> = if aimed {
            d.els.iter().filter(|t| t.id == f.aim && !t.hidden).collect()
        } else {
            d.els.iter().filter(|t| t.kind == Kind::Cast && !t.hidden).collect()
        };
        for t in targets {
            let p = at(t);
            let (vx, vy) = (p.0 - fx, p.1 - fy);
            if vx * n.0 + vy * n.1 <= 0.0 {
                continue; // behind the face
            }
            let off = super::norm_deg(vy.atan2(vx).to_degrees() - mirror_deg);
            let off = if off > 180.0 { 360.0 - off } else { off };
            let u = off / (spread / 2.0).max(1.0);
            if !aimed && u > 1.0 {
                continue;
            }
            let k = (1.0 - (u / 2.0).powi(2)).clamp(0.2, 1.0);
            let start = Src::Disc { exit: exit * k, r, at: 0.0 };
            if let Some((lux, _)) = travel((fx, fy, fh), p, start, spread, walls, &grip, &[&f.id, &t.id]) {
                if lux > 0.0 {
                    out.push(Lit { target: t.id.clone(), from: f.id.clone(), lux, toward: heading((p.0, p.1), (fx, fy)), soft: true });
                }
            }
        }
    }

    // The sun, flat, on the cast it can see — and on anything a lamp is aimed at.
    if d.settings.sun {
        if let Ok((sun, _)) = render::sun_now(d, ctx) {
            if sun.altitude > 0.0 {
                let lux = if d.settings.sun_lux > 0.0 { d.settings.sun_lux } else { sun_by_height(sun.altitude) };
                // A compass bearing from wherever north lies on the plan.
                let toward = super::norm_deg(-90.0 + sun.azimuth + d.settings.north);
                let dir = (toward.to_radians().cos(), toward.to_radians().sin());
                let lit_ids: Vec<String> = out.iter().map(|l| l.target.clone()).collect();
                for t in d.els.iter().filter(|t| !t.hidden && (t.kind == Kind::Cast || lit_ids.contains(&t.id))) {
                    let p = at(t);
                    // From a great way off: no falloff, only what stands in
                    // the way — a wall stops it, a net or a silk costs stops.
                    let far = (p.0 + dir.0 * 60.0, p.1 + dir.1 * 60.0);
                    let Some(crossed) = crossings(far, (p.0, p.1), 60.0, walls, &grip, &[&t.id]) else { continue };
                    let mut k = 1.0;
                    let mut soft = false;
                    for (_, g) in crossed {
                        match g.effect {
                            frame::Effect::Cut | frame::Effect::Bounce(..) => k = 0.0,
                            frame::Effect::Dim(st) => k *= 2f64.powf(-(st + g.stops)),
                            frame::Effect::Diffuse(st, _) => {
                                k *= 2f64.powf(-(st + g.stops));
                                soft = true;
                            }
                        }
                    }
                    if k > 0.0 {
                        out.push(Lit { target: t.id.clone(), from: "sun".into(), lux: lux * k, toward, soft });
                    }
                }
            }
        }
    }
    out
}

/// The sun's light on the ground for its height in the sky, in lux: a
/// hundred thousand overhead, a few thousand low.
pub fn sun_by_height(altitude: f64) -> f64 {
    (110_000.0 * altitude.to_radians().sin()).max(400.0)
}

/// The sun's presets, in the order the panel lists them: name, lux
/// (nought: by its height). The Mac's panel names the same list
/// (`DiagramLevels.swift`); keep the two in step.
pub const SUN_PRESETS: &[(&str, f64)] = &[
    ("Auto", 0.0),
    ("Midday Sun", 100_000.0),
    ("Afternoon Sun", 50_000.0),
    ("Overcast", 10_000.0),
    ("Golden Hour", 5_000.0),
    ("Heavy Overcast", 2_000.0),
    ("Twilight", 100.0),
];

// ---------------------------------------------------------------- drawing

/// A piece's total: every light on it, and the room's ambient.
pub fn total(lits: &[Lit], target: &str, s: &Settings) -> f64 {
    s.ambient + lits.iter().filter(|l| l.target == target).map(|l| l.lux).sum::<f64>()
}

fn text(el: &str, x: f64, y: f64, words: String, ink: Ink) -> Shape {
    let mut s = bare(el, Geom::Text { x, y, text: words, size: 9.0, anchor: "middle", bold: true, rot: 0.0, fixed: true, halo: true, patch: false, shift: (0.0, 0.0), under: Ink::None, lead: 1 });
    s.fill = ink;
    s
}

fn bare(el: &str, geom: Geom) -> Shape {
    Shape { el: el.to_string(), part: "level", geom, fill: Ink::None, stroke: Ink::None, line: 1.0, dash: "", alpha: 1.0, fade: None }
}

fn ring(el: &str, segs: Vec<render::Seg>, hex: &str, line: f64, dash: &'static str, alpha: f64) -> Shape {
    let mut s = bare(el, Geom::Path(segs));
    s.stroke = Ink::hex(hex);
    s.line = line;
    s.dash = dash;
    s.alpha = alpha;
    s
}

/// **The levels on the plan**: a ring round each lit piece and its level;
/// a ring round each omni unit where it reaches the midtone. Nothing when
/// levels are off. Every shape's part is `level`.
pub fn shapes(d: &Diagram, ctx: &Context, opt: &Options, walls: &[Blocker]) -> Vec<Shape> {
    if !super::render::levels_on(d) {
        return Vec::new();
    }
    let s = &d.settings;
    let lits = contributions(d, ctx, opt, walls);
    let mut out = Vec::new();
    // A picked lamp or bounce shows only its own light.
    let focus: Vec<&str> = opt.sel.iter().map(|x| x.as_str()).filter(|id| lits.iter().any(|l| l.from == *id)).collect();
    let mut targets: Vec<&str> = Vec::new();
    for l in &lits {
        if (focus.is_empty() || focus.contains(&l.from.as_str())) && !targets.contains(&l.target.as_str()) {
            targets.push(&l.target);
        }
    }
    let turn = render::view_turn(d);
    for id in targets {
        let Some(t) = d.get(id) else { continue };
        let mine: Vec<&Lit> = lits.iter().filter(|l| l.target == id && (focus.is_empty() || focus.contains(&l.from.as_str()))).collect();
        let lux = if focus.is_empty() { total(&lits, id, s) } else { mine.iter().map(|l| l.lux).sum() };
        let (x, y) = if t.kind.is_line() {
            t.centre()
        } else {
            let p = placed(t, opt);
            (p.0, p.1)
        };
        let (w, h) = t.footprint(opt.beat);
        // Round a person, just clear of them; round a big frame or a set
        // piece, no bigger than it takes to read.
        let r = (w.max(h) / 2.0 + 0.12).min(0.6);
        let hex = ring_hex(stops_over(lux, s));
        out.push(ring(id, circle(x, y, r), &hex, 2.5, "", 0.95));
        // Where each light comes in, in its own colour: a key and its fill
        // read at a glance; a soft source wraps further round.
        for l in &mine {
            let half = if l.soft { 70.0 } else { 35.0 };
            let own = ring_hex(stops_over(l.lux, s));
            out.push(ring(id, arc(x, y, r + 0.07, l.toward - half, l.toward + half, false), &own, 4.0, "", 0.9));
        }
        // Its level, over it as the page is shown.
        let up = (-(90.0 + turn)).to_radians();
        let above = r + 0.22;
        out.push(text(id, x + up.cos() * above, y + up.sin() * above, words(lux, s), Ink::Role("ink")));
    }
    // Omni units: where they reach the midtone on the floor.
    for l in d.els.iter().filter(|l| l.kind == Kind::Light && !l.hidden && symbols::emits(&l.sym) && is_omni(l)) {
        if !focus.is_empty() && !opt.sel.contains(&l.id) {
            continue;
        }
        let i = intensity(l);
        let hgt = height_of(l, s.units == "m");
        let r2 = i / midtone(s) - hgt * hgt;
        if r2 > 0.0 {
            let (x, y, _) = placed(l, opt);
            out.push(ring(&l.id, circle(x, y, r2.sqrt().min(80.0)), &ring_hex(0.0), 1.4, "dash", 0.9));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::json;

    fn plan(els: &str, settings: &str) -> Diagram {
        Diagram::parse(&format!(r#"{{"els":{els},"settings":{{"levels":true{settings}}}}}"#))
    }

    fn lit_on(d: &Diagram, target: &str) -> f64 {
        let walls = shade::blockers(d);
        let lits = contributions(d, &Context::default(), &Options::default(), &walls);
        total(&lits, target, &d.settings)
    }

    // A 2K Fresnel at full flood, 2 m up — its candela there — aimed at a
    // person 1.5 m up.
    const PERSON: &str = r#"{"kind":"cast","id":"p","x":4,"y":0}"#;
    fn lamp(id: &str, x: f64, extra: &str) -> String {
        format!(r#"{{"kind":"light","id":"{id}","sym":"fresnel-2k","x":{x},"y":0,"rot":0,"w":0.0,"beam":56,"height":"1.5 m","aim":"p"{extra}}}"#)
    }

    #[test]
    fn light_falls_off_by_the_inverse_square_in_three_dimensions() {
        let near = lit_on(&plan(&format!("[{},{PERSON}]", lamp("l", 2.0, "")), ""), "p");
        let far = lit_on(&plan(&format!("[{},{PERSON}]", lamp("l", 0.0, "")), ""), "p");
        // The light leaves the lamp's front, half a centimetre ahead of it.
        let (n, f) = (2.0 - 0.005, 4.0 - 0.005);
        assert!((near - 18_000.0 / (n * n)).abs() < 0.01, "2 m: {near}");
        assert!((near / far - (f * f) / (n * n)).abs() < 1e-9, "twice as far, a quarter: {near} {far}");
        // Lifted 3 m above the face, four across: five metres off.
        let high = lit_on(&plan(&format!("[{},{PERSON}]", lamp("l", 0.0, "").replace("1.5 m", "4.5 m")), ""), "p");
        assert!((high - 18_000.0 / (f * f + 9.0)).abs() < 0.01, "{high}");
    }

    #[test]
    fn light_adds_up_with_the_ambient() {
        let one = lit_on(&plan(&format!("[{},{PERSON}]", lamp("a", 2.0, "")), ""), "p");
        let both = lit_on(&plan(&format!("[{},{},{PERSON}]", lamp("a", 2.0, ""), lamp("b", 2.0, "")), r#","ambient":100"#), "p");
        assert!((both - (2.0 * one + 100.0)).abs() < 1e-6, "{one} {both}");
    }

    #[test]
    fn the_dimmer_gels_and_a_net_all_cost_light() {
        let open = lit_on(&plan(&format!("[{},{PERSON}]", lamp("l", 0.0, "")), ""), "p");
        let half = lit_on(&plan(&format!("[{},{PERSON}]", lamp("l", 0.0, r#","dim":50"#)), ""), "p");
        assert!((half / open - 0.5).abs() < 1e-9);
        let nd = lit_on(&plan(&format!("[{},{PERSON}]", lamp("l", 0.0, r#","gels":["nd6"]"#)), ""), "p");
        assert!((nd / open - 0.25).abs() < 1e-9, "two stops: {}", nd / open);
        let net = r#"{"kind":"light","id":"n","sym":"frame","x":2,"y":0,"rot":0,"h":2.44,"material":"double-net"}"#;
        let netted = lit_on(&plan(&format!("[{},{net},{PERSON}]", lamp("l", 0.0, "")), ""), "p");
        assert!((netted / open - 0.5).abs() < 1e-9, "a double is a stop: {}", netted / open);
        let solid = net.replace("double-net", "solid");
        assert_eq!(lit_on(&plan(&format!("[{},{solid},{PERSON}]", lamp("l", 0.0, "")), ""), "p"), 0.0);
        // A wall stops it too.
        let wall = r#"{"kind":"wall","id":"w","x":1,"y":-3,"x2":1,"y2":3}"#;
        assert_eq!(lit_on(&plan(&format!("[{},{wall},{PERSON}]", lamp("l", 0.0, "")), ""), "p"), 0.0);
    }

    #[test]
    fn a_diffusion_softens_and_wraps_more_the_closer_it_is() {
        let open = lit_on(&plan(&format!("[{},{PERSON}]", lamp("l", 0.0, "")), ""), "p");
        let diff = |x: f64| {
            let f = format!(r#"{{"kind":"light","id":"d","sym":"frame","x":{x},"y":0,"rot":0,"h":2.44,"material":"diff-heavy"}}"#);
            let d = plan(&format!("[{},{f},{PERSON}]", lamp("l", 0.0, "")), "");
            let walls = shade::blockers(&d);
            let lits = contributions(&d, &Context::default(), &Options::default(), &walls);
            (lits[0].lux, lits[0].soft)
        };
        let (near_lamp, soft) = diff(0.5);
        let (near_face, _) = diff(3.4);
        assert!(soft, "through a diffusion is soft");
        assert!(near_lamp < open && near_face < open, "it costs light: {open} {near_lamp} {near_face}");
        assert!(near_face > near_lamp, "close to the face it keeps more: {near_lamp} {near_face}");
    }

    #[test]
    fn a_bounce_gives_back_what_lands_on_it() {
        // The lamp lights a white bounce; the bounce is aimed at the person.
        let l = r#"{"kind":"light","id":"l","sym":"fresnel-2k","x":0,"y":0,"rot":0,"w":0.0,"beam":56,"height":"1.5 m","aim":"b"}"#;
        let b = r#"{"kind":"light","id":"b","sym":"frame","x":2,"y":0,"rot":0,"h":2.44,"material":"bounce-white","aim":"p"}"#;
        let p = r#"{"kind":"cast","id":"p","x":1,"y":1.5}"#;
        let d = plan(&format!("[{l},{b},{p}]"), "");
        let walls = shade::blockers(&d);
        let lits = contributions(&d, &Context::default(), &Options::default(), &walls);
        let on_board = lits.iter().find(|x| x.target == "b").expect("the lamp lights the board").lux;
        let back = lits.iter().find(|x| x.target == "p" && x.from == "b").expect("the board lights the person");
        assert!(back.lux > 0.0 && back.lux < on_board * 0.4, "less a stop and a half, and falling off: {on_board} {}", back.lux);
        assert!(back.soft);
    }

    /// SL-1272: diagram.sh 14's own layout — a 600D into the Frame tool's
    /// white bounce, standing or lying flat, aimed at someone or no one —
    /// writes a level on the bounce.
    #[test]
    #[ignore = "light levels are off for now (render::LAMP_BEAMS, his call 2026-10-01)"]
    fn a_frame_tools_white_bounce_wears_what_lands_on_it() {
        for (tilt, aim) in [(90.0, r#","aim":"p""#), (0.0, r#","aim":"p""#), (90.0, ""), (0.0, "")] {
            let p = r#"{"kind":"cast","id":"p","x":0.61,"y":1.52}"#;
            let lamp = r#"{"kind":"light","id":"l","sym":"fso-aputure-600d","x":1.22,"y":5.49,"rot":214,"w":0.39,"h":0.2,"beam":55,"reach":3,"aim":"b"}"#;
            let b = format!(r#"{{"kind":"light","id":"b","sym":"frame","x":-1.52,"y":3.66,"rot":315,"h":2.44,"tilt":{tilt},"material":"bounce-white"{aim}}}"#);
            let mut d = plan(&format!("[{p},{lamp},{b}]"), r#","light_units":"lux""#);
            // Settled the way an edit leaves it: aimed, and the frame sized.
            super::super::apply(&mut d, &json::parse(r#"{"op":"settings","set":{}}"#).unwrap()).unwrap();
            let walls = shade::blockers(&d);
            let shapes = shapes(&d, &Context::default(), &Options::default(), &walls);
            let words = shapes.iter().find_map(|s| match &s.geom {
                render::Geom::Text { text, .. } if s.el == "b" => Some(text.clone()),
                _ => None,
            });
            assert!(words.as_deref().is_some_and(|w| w.ends_with("lx") && !w.starts_with('0')), "tilt {tilt} aim {aim:?}: {words:?}");
        }
    }

    #[test]
    #[ignore = "light levels are off for now (render::LAMP_BEAMS, his call 2026-10-01)"]
    fn an_omni_lights_what_is_in_range_and_rings_the_midtone() {
        let space = r#"{"kind":"light","id":"s","sym":"spacelight","x":0,"y":0,"beam":180,"height":"3 m"}"#;
        let near = r#"{"kind":"cast","id":"p","x":1,"y":0}"#;
        let far = r#"{"kind":"cast","id":"q","x":30,"y":0}"#;
        let d = plan(&format!("[{space},{near},{far}]"), "");
        let walls = shade::blockers(&d);
        let lits = contributions(&d, &Context::default(), &Options::default(), &walls);
        assert!(lits.iter().any(|l| l.target == "p"), "in range");
        assert!(!lits.iter().any(|l| l.target == "q"), "thirty metres off is not");
        let shapes = shapes(&d, &Context::default(), &Options::default(), &walls);
        let ring = shapes.iter().find(|x| x.el == "s" && x.dash == "dash").expect("an omni ring");
        // 4000 cd at the default midtone (f/2.8, ISO 800, 1/48 ≈ 127 lx):
        // √(4000/127 − 9) ≈ 4.7 m.
        let want = (4000.0 / midtone(&d.settings) - 9.0).sqrt();
        let Geom::Path(segs) = &ring.geom else { panic!() };
        let far_pt = segs.iter().filter_map(|s| match s { render::Seg::M(x, y) | render::Seg::L(x, y) => Some(x.hypot(*y)), render::Seg::C(_, _, _, _, x, y) => Some(x.hypot(*y)), _ => None }).fold(0.0, f64::max);
        assert!((far_pt - want).abs() < 0.05, "{far_pt} vs {want}");
    }

    #[test]
    fn the_sun_lights_the_cast_it_can_see_flat_at_its_preset() {
        // Midsummer noon in the mountains: the sun due south, down the page.
        let ctx = Context { place: Some((49.3, -117.7)), date: "2026-06-21".into(), utc_offset: Some(-420.0), ..Default::default() };
        let out = r#"{"kind":"cast","id":"p","x":0,"y":0}"#;
        let shaded = r#"{"kind":"cast","id":"q","x":10,"y":0}"#;
        let wall = r#"{"kind":"wall","id":"w","x":8,"y":2,"x2":12,"y2":2}"#;
        let d = plan(&format!("[{out},{shaded},{wall}]"), r#","sun":true,"sun_time":"13:00","sun_tz":-420,"sun_lux":50000"#);
        let lits = contributions(&d, &ctx, &Options::default(), &shade::blockers(&d));
        let on = |id: &str| lits.iter().filter(|l| l.target == id && l.from == "sun").map(|l| l.lux).sum::<f64>();
        assert_eq!(on("p"), 50_000.0, "no falloff: {lits:?}");
        assert_eq!(on("q"), 0.0, "the wall to the south shades her");
        // Auto: by its height.
        let auto = plan(&format!("[{out}]"), r#","sun":true,"sun_time":"13:00","sun_tz":-420"#);
        let lits = contributions(&auto, &ctx, &Options::default(), &[]);
        assert!(lits[0].lux > 80_000.0, "high summer sun: {}", lits[0].lux);
    }

    #[test]
    fn a_level_reads_in_stops_lux_or_foot_candles() {
        let mut s = Settings::default();
        let mid = midtone(&s);
        assert!((mid / LUX_PER_FC - 11.76).abs() < 0.01, "f/2.8 at ISO 800, 1/48 is about 12 fc: {}", mid / LUX_PER_FC);
        assert_eq!(words(mid, &s), "f/2.8");
        assert_eq!(words(mid * 2.0, &s), "f/4");
        assert_eq!(words(mid * 2f64.powf(2.0 + 1.0 / 3.0), &s), "f/5.6 +⅓");
        assert_eq!(words(mid * 2f64.powf(-1.0 / 3.0), &s), "f/2 +⅔");
        s.light_units = "lux".into();
        assert_eq!(words(851.0, &s), "850 lx");
        assert_eq!(words(1234.0, &s), "1200 lx");
        s.light_units = "fc".into();
        assert_eq!(words(79.0 * LUX_PER_FC, &s), "79 fc");
        assert_eq!(ring_hex(0.0), "#2EAA62");
        assert_ne!(ring_hex(-2.0), ring_hex(2.0));
    }

    #[test]
    fn heights_read_as_words_or_lengths() {
        assert_eq!(parse_height("Eye Level", false), Some(1.6));
        assert!((parse_height("7 ft", false).unwrap() - 2.1336).abs() < 1e-9);
        assert!((parse_height("7' 6\"", false).unwrap() - 2.286).abs() < 1e-9);
        assert!((parse_height("2.1 m", false).unwrap() - 2.1).abs() < 1e-9);
        assert!((parse_height("2", true).unwrap() - 2.0).abs() < 1e-9);
        assert!((parse_height("6", false).unwrap() - 1.8288).abs() < 1e-9);
        assert_eq!(parse_height("", false), None);
    }

    #[test]
    fn the_settings_round_trip_and_default_to_off() {
        let d = Diagram::default();
        assert!(!d.settings.levels);
        assert!(!d.to_json().encode().contains("levels"), "a plan with levels off writes nothing new");
        let mut d = plan("[]", r#","light_units":"fc","iso":1600,"shutter":50,"stop":4,"ambient":30,"sun_lux":5000"#);
        let back = Diagram::parse(&d.encode());
        assert_eq!(back.settings, d.settings);
        assert_eq!((back.settings.light_units.as_str(), back.settings.iso, back.settings.stop), ("fc", 1600.0, 4.0));
        super::super::apply(&mut d, &json::parse(r#"{"op":"settings","set":{"iso":-5,"light_units":"candles"}}"#).unwrap()).unwrap();
        assert_eq!((d.settings.iso, d.settings.light_units.as_str()), (3.0, "stops"));
    }

    #[test]
    fn with_levels_on_a_beam_runs_to_the_midtone() {
        let d = plan(&format!("[{},{PERSON}]", lamp("l", 0.0, "")), "");
        let r = midtone_reach(&d.els[0], &d);
        assert!((r - (18_000.0 / midtone(&d.settings)).sqrt()).abs() < 1e-6, "{r}");
        let off = Diagram::parse(&format!(r#"{{"els":[{}]}}"#, lamp("l", 0.0, "")));
        assert_eq!(reached(&off.els[0], &off).reach, off.els[0].reach, "off: left as it was");
    }
}
