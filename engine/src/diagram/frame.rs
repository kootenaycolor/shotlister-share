//! **Frames**, Scenario's way (2026-09-28): a rag on its pipe, any size, of
//! any skin, standing or lying or anywhere between, that does something to
//! the light that meets it.
//!
//! A frame is a light-kind piece whose drawing is `frame` (grip lives with
//! the lights; `symbols.rs`). Its own fields:
//!
//! - `h` — its width, across the way it faces;
//! - `tall` — its height, the edge that tilts (nought reads as square);
//! - `tilt` — 0 lying flat (an overhead) to 90 standing, the default;
//! - `material`, `pipe`, `grid` — the skin, the frame round it, and the
//!   egg crate on its face;
//! - `gels`, as a light has.
//!
//! On the plan it takes up its width across and its height foreshortened by
//! the tilt along — `w` is worked out from `tall` and `tilt` (`settle`), so
//! a hand never has to.
//!
//! **What it does to a beam** (`Effect`): a solid cuts it, a net dims what
//! passes, a diffusion turns into a soft source of its own past it, a bounce
//! stops it and — when a light is aimed at it — throws a soft beam back
//! along the mirror angle. The other grip in the library does the same by
//! what it is made of (`effect`): a flag cuts, a single dims, a silk softens,
//! a foam core bounces.

use super::gear::{self, Cloth};
use super::gels;
use super::render::{circle, line, rect, Geom, Ink, Seg, Shape};
use super::{fso, symbols, El, FOOT};

pub const SYM: &str = "frame";

/// What happens to light that meets it.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Effect {
    /// Stops it.
    Cut,
    /// Lets it through, this many stops down.
    Dim(f64),
    /// Lets it through as a soft source: this many stops down, spread this
    /// many degrees.
    Diffuse(f64, f64),
    /// Stops it and — when a light is aimed at it — throws it back: stops
    /// lost, spread, and how much it warms (mireds).
    Bounce(f64, f64, f64),
}

impl Effect {
    pub fn passes(self) -> bool {
        matches!(self, Effect::Dim(_) | Effect::Diffuse(..))
    }
}

/// The skins, in the order the picker shows them: id, name, what it does.
/// Scenario's thirty (2026-09-30, his ask: "as good as that one"), with our
/// three diffusion weights and Grid Cloth, which it lacks.
pub const MATERIALS: &[(&str, &str, Effect)] = &[
    // **Not decided yet** (his words, 2026-10-17: *"A lot of the items, I
    // don't know what diffusion I want"*): a frame drawn as a plain frame,
    // no cloth named or patterned.
    ("undecided", "Not Decided", Effect::Dim(0.0)),
    ("diff-light", "Light Diffusion", Effect::Diffuse(0.35, 50.0)),
    ("diff-medium", "Medium Diffusion", Effect::Diffuse(0.8, 80.0)),
    ("diff-heavy", "Heavy Diffusion", Effect::Diffuse(1.5, 120.0)),
    ("silk", "Silk", Effect::Diffuse(1.0, 90.0)),
    ("art-silk", "Artificial Silk", Effect::Diffuse(0.75, 80.0)),
    ("grid-cloth", "Grid Cloth", Effect::Diffuse(1.3, 110.0)),
    ("single-net", "Single Net", Effect::Dim(0.5)),
    ("double-net", "Double Net", Effect::Dim(1.0)),
    ("solid", "Solid", Effect::Cut),
    ("bounce-white", "White Bounce", Effect::Bounce(1.5, 110.0, 0.0)),
    ("ultra-bounce", "Ultra Bounce", Effect::Bounce(1.5, 110.0, 0.0)),
    ("bleached-muslin", "Bleached Muslin", Effect::Bounce(1.8, 130.0, 0.0)),
    ("muslin", "Unbleached Muslin", Effect::Bounce(2.0, 130.0, 30.0)),
    ("day-grey", "Day Grey", Effect::Bounce(2.5, 130.0, 0.0)),
    ("day-blue", "Day Blue", Effect::Bounce(2.2, 130.0, -40.0)),
    ("bounce-silver", "Silver Bounce", Effect::Bounce(0.5, 40.0, 0.0)),
    ("bounce-gold", "Gold Bounce", Effect::Bounce(0.8, 55.0, 80.0)),
    ("silver-lame", "Silver Lamé", Effect::Bounce(0.7, 60.0, 0.0)),
    ("gold-lame", "Gold Lamé", Effect::Bounce(0.9, 65.0, 80.0)),
    ("soft-silver", "Soft Silver", Effect::Bounce(0.6, 50.0, 0.0)),
    ("soft-mirror", "Soft Mirror", Effect::Bounce(0.3, 20.0, 0.0)),
    ("hard-mirror", "Hard Mirror", Effect::Bounce(0.1, 8.0, 0.0)),
    ("natural-2-1", "Natural Bounce 2:1", Effect::Bounce(1.0, 80.0, 0.0)),
    ("natural-1-1", "Natural Bounce 1:1", Effect::Bounce(1.2, 95.0, 0.0)),
    ("natural-1-2", "Natural Bounce 1:2", Effect::Bounce(1.4, 110.0, 0.0)),
    ("check-bleached", "Bleached/Unbleached Checkerboard", Effect::Bounce(1.9, 130.0, 15.0)),
    ("check-natural", "Natural Checkerboard", Effect::Bounce(1.1, 90.0, 0.0)),
    ("check-muslin", "Muslin Checkerboard", Effect::Bounce(1.9, 130.0, 30.0)),
    ("check-silver-white", "Silver/White Checkerboard", Effect::Bounce(1.0, 80.0, 0.0)),
    ("check-gold-white", "Gold/White Checkerboard", Effect::Bounce(1.1, 85.0, 40.0)),
    ("check-silver-gold", "Silver/Gold Checkerboard", Effect::Bounce(0.7, 60.0, 40.0)),
    ("blue-screen", "Blue Screen", Effect::Cut),
    ("green-screen", "Green Screen", Effect::Cut),
    ("custom", "Custom Colour", Effect::Bounce(2.0, 130.0, 0.0)),
    ("gel", "Gel", Effect::Dim(0.0)),
    ("none", "No Material", Effect::Dim(0.0)),
];

/// Which part of the picker a skin sits in.
pub fn material_group(id: &str) -> &'static str {
    match id {
        "undecided" | "diff-light" | "diff-medium" | "diff-heavy" | "silk" | "art-silk" | "grid-cloth" => "Diffusion",
        "single-net" | "double-net" | "solid" => "Nets & Solids",
        _ if id.starts_with("check-") => "Checkerboards",
        "blue-screen" | "green-screen" | "custom" | "gel" | "none" => "Screens & Colour",
        _ => "Bounce",
    }
}

/// A skin as a swatch shows it: its colour, a second colour for a
/// checkerboard, and the colour its edge is bound in — a single net green,
/// a double red, a silk gold, the way grips' rags are.
pub fn swatch(id: &str) -> (&'static str, &'static str, &'static str) {
    match id {
        "diff-light" => ("#F7F7F5", "", ""),
        "diff-medium" => ("#EFEFEC", "", ""),
        "diff-heavy" => ("#E4E4E0", "", ""),
        "silk" => ("#F3F1EA", "", GOLD),
        "art-silk" => ("#F6F4EE", "", YELLOW),
        "grid-cloth" => ("#E9E9E6", "", ""),
        "single-net" => ("#9A9EA3", "", GREEN),
        "double-net" => ("#6E7378", "", RED),
        "solid" => ("#2B2B2D", "", ""),
        "bounce-white" => ("#FFFFFF", "", ""),
        "ultra-bounce" => ("#FBFBFA", "", ""),
        "bleached-muslin" => ("#F6F3EA", "", ""),
        "muslin" => ("#E9DFC8", "", ""),
        "day-grey" => ("#A7AAAD", "", ""),
        "day-blue" => ("#8EA8C8", "", ""),
        "bounce-silver" => ("#BFC5CC", "", ""),
        "bounce-gold" => ("#D9B24A", "", ""),
        "silver-lame" => ("#C9CDD3", "", ""),
        "gold-lame" => ("#D8B65A", "", ""),
        "soft-silver" => ("#D3D7DC", "", ""),
        "soft-mirror" => ("#DCE5EB", "", ""),
        "hard-mirror" => ("#EAF2F7", "", ""),
        "natural-2-1" => ("#ECE6D6", "", ""),
        "natural-1-1" => ("#E5DCC6", "", ""),
        "natural-1-2" => ("#DED2B6", "", ""),
        "check-bleached" => ("#F6F3EA", "#E9DFC8", ""),
        "check-natural" => ("#FFFFFF", "#E5DCC6", ""),
        "check-muslin" => ("#E9DFC8", "#FFFFFF", ""),
        "check-silver-white" => ("#BFC5CC", "#FFFFFF", ""),
        "check-gold-white" => ("#D9B24A", "#FFFFFF", ""),
        "check-silver-gold" => ("#BFC5CC", "#D9B24A", ""),
        "blue-screen" => ("#2D5BD3", "", ""),
        "green-screen" => ("#2FA24A", "", ""),
        "custom" => ("#B07ACC", "", ""),
        "gel" => ("", "", ""),
        "none" | "undecided" => ("", "", ""),
        _ => ("#EFEFEC", "", ""),
    }
}

const GREEN: &str = "#2F9E5A";
const RED: &str = "#D6453D";
const GOLD: &str = "#C9A227";
const YELLOW: &str = "#E3CF3A";

/// What a new frame is skinned with: nothing decided (2026-10-17). Before,
/// Scenario's white diffusion — `OLD_DEFAULT`, which an older plan's frames
/// with no skin of their own are given when it is first read
/// (`plot::free_names`).
pub const DEFAULT_MATERIAL: &str = "undecided";
pub const OLD_DEFAULT: &str = "diff-medium";

/// The pipe round it, in Scenario's order and words.
pub const PIPES: &[(&str, &str)] = &[
    ("none", "No Pipe"),
    ("open", "Open Frame"),
    ("butterfly", "Butterfly"),
    ("speed-rail", "Speed Rail"),
    ("black-pipe", "Black Pipe"),
];

/// The egg crates a face can carry, in degrees; nought is none.
pub const GRIDS: &[f64] = &[20.0, 30.0, 40.0, 45.0, 50.0, 60.0];

/// The largest frame, either way: a hundred feet.
pub const LARGEST: f64 = 30.48;
/// How thin a standing frame is drawn and clicked: its pipe.
pub const EDGE: f64 = 0.12;

pub fn is_frame(e: &El) -> bool {
    e.sym == SYM
}

pub fn material_id(e: &El) -> &str {
    if e.material.is_empty() { DEFAULT_MATERIAL } else { e.material.as_str() }
}

pub fn material_name(id: &str) -> &'static str {
    MATERIALS.iter().find(|m| m.0 == id).map(|m| m.1).unwrap_or("Frame")
}

/// Its height: the edge that tilts, square unless told.
pub fn tall(e: &El) -> f64 {
    if e.tall > 0.0 { e.tall } else { e.h }
}

/// Kept to a real frame, and its footprint worked out: after every edit and
/// every read (`El::tame`).
pub fn settle(e: &mut El) {
    e.h = e.h.clamp(0.05, LARGEST);
    e.tall = if e.tall.is_finite() { e.tall.clamp(0.0, LARGEST) } else { 0.0 };
    let t = tall(e);
    let along = t * e.tilt.to_radians().cos();
    e.w = (along.max(EDGE) * 10_000.0).round() / 10_000.0;
    if !GRIDS.contains(&e.grid) {
        e.grid = 0.0;
    }
}

/// What a piece of grip does to light, if anything: a frame by its skin,
/// the library's flags, rags and boards by what they are made of, the
/// pack's by their names. A lamp does nothing to another lamp's beam.
pub fn effect(e: &El) -> Option<Effect> {
    let base = if is_frame(e) {
        // A bare pipe does nothing to light.
        if material_id(e) == "none" {
            return None;
        }
        MATERIALS.iter().find(|m| m.0 == material_id(e)).map(|m| m.2)
    } else if let Some(s) = symbols::find(&e.sym) {
        if s.light && s.beam <= 0.0 { by_look(s.look) } else { None }
    } else if let Some(a) = fso::find(&e.sym) {
        if a.role == "grip" { by_name(a.name) } else { None }
    } else {
        None
    }?;
    // An egg crate narrows what goes through or bounces off, for a stop's
    // worth of the light.
    Some(match (base, e.grid > 0.0) {
        (Effect::Diffuse(s, spread), true) => Effect::Diffuse(s + 0.5, spread.min(e.grid)),
        (Effect::Bounce(s, spread, warm), true) => Effect::Bounce(s + 0.5, spread.min(e.grid), warm),
        (other, _) => other,
    })
}

fn by_look(look: gear::Look) -> Option<Effect> {
    use gear::{Board, Look};
    let m = |id: &str| MATERIALS.iter().find(|m| m.0 == id).map(|m| m.2);
    match look {
        Look::Flag(c) | Look::Rag(c) => match c {
            Cloth::Solid => m("solid"),
            Cloth::Single => m("single-net"),
            Cloth::Double => m("double-net"),
            Cloth::Silk => m("silk"),
            Cloth::ArtSilk => m("art-silk"),
            Cloth::Grid => m("grid-cloth"),
            Cloth::Bounce => m("ultra-bounce"),
            Cloth::Muslin => m("muslin"),
            Cloth::Lcd => m("diff-medium"),
        },
        Look::Board(b) => match b {
            Board::Foam | Board::Card => m("bounce-white"),
            Board::Shiny | Board::Reflector => m("bounce-silver"),
            Board::Neg => m("solid"),
        },
        _ => None,
    }
}

fn by_name(name: &str) -> Option<Effect> {
    let n = name.to_lowercase();
    let m = |id: &str| MATERIALS.iter().find(|m| m.0 == id).map(|m| m.2);
    let has = |w: &str| n.contains(w);
    if has("double") {
        m("double-net")
    } else if has("single") || has("scrim") {
        m("single-net")
    } else if has("artificial silk") {
        m("art-silk")
    } else if has("silk") {
        m("silk")
    } else if has("grid cloth") {
        m("grid-cloth")
    } else if has("lcd") {
        m("diff-medium")
    } else if has("shiny") || has("mirror") || has("crls") {
        m("bounce-silver")
    } else if has("ultra bounce") {
        m("ultra-bounce")
    } else if has("bounce") || has("foam") {
        m("bounce-white")
    } else if has("muslin") {
        m("muslin")
    } else if has("solid") || has("flag") || has("neg") || has("duvetyne") {
        m("solid")
    } else {
        None
    }
}

/// A frame dressed as one of the pack's rags or flags: its skin, pipe,
/// egg crate, width, height and tilt. `None` where the Frame cannot be that
/// picture. The library hides a pack picture only where this answers, so
/// nothing is offered less than the Frame can make (his rule, 2026-10-01:
/// "make sure that the frame tool can replicate all the things that we are
/// cutting").
#[derive(Clone, Debug, PartialEq)]
pub struct StandIn {
    pub material: &'static str,
    pub pipe: &'static str,
    pub grid: f64,
    pub width: f64,
    pub tall: f64,
    pub tilt: f64,
}

pub fn stand_in(a: &fso::Art) -> Option<StandIn> {
    if a.group != "Rags" && a.group != "Frames & Boards" {
        return None;
    }
    let n = a.name.to_lowercase();
    let has = |w: &str| n.contains(w);
    // The skin, and the egg crate an LCD is.
    let (material, grid) = if has("artificial silk") {
        ("art-silk", 0.0)
    } else if has("white silk") {
        ("silk", 0.0)
    } else if has("double black scrim") {
        ("double-net", 0.0)
    } else if has("single black scrim") {
        ("single-net", 0.0)
    } else if has("solid") || has("flag") {
        ("solid", 0.0)
    } else if has("grid cloth") {
        ("grid-cloth", 0.0)
    } else if has("ultra bounce") {
        ("ultra-bounce", 0.0)
    } else if has("unbleached muslin") {
        ("muslin", 0.0)
    } else if has("lcd") {
        ("none", 40.0)
    } else {
        return None; // foam core, shiny boards, Lightbridge: not a rag on a pipe
    };
    // Its size: "18x24" in inches, "6x6" … "20x20" in feet.
    let size = n.split_whitespace().next()?;
    let (x, y) = size.split_once('x')?;
    let (x, y): (f64, f64) = (x.parse().ok()?, y.parse().ok()?);
    let unit = if x.max(y) > 20.0 { FOOT / 12.0 } else { FOOT };
    // The long side across, the way the pack draws a 12×20 and an 18×24.
    let (width, tall) = (x.max(y) * unit, x.min(y) * unit);
    let tilt = if has("angled") { 45.0 } else { 90.0 };
    let pipe = if has("free hanging") { "none" } else { "open" };
    Some(StandIn { material, pipe, grid, width, tall, tilt })
}

/// A frame's name on the plan: its size in feet, the way grips say it, and
/// its skin — "8×8 Silk".
pub fn plan_name(e: &El) -> String {
    let skin = match material_id(e) {
        // A bare pipe is a frame; with an egg crate on it, an egg crate (the
        // pack's LCD).
        "none" if e.grid > 0.0 => "Egg Crate",
        "none" | "undecided" => "Frame",
        id => material_name(id),
    };
    match size_name(e) {
        size if size.is_empty() => skin.to_string(),
        size => format!("{size} {skin}"),
    }
}

/// A frame's size the way grips say it — "12×12", a flag under four feet
/// in inches, "18×24" — or nothing when it is no whole size. The legend
/// counts frames by it.
pub fn size_name(e: &El) -> String {
    let whole = |m: f64, unit: f64| {
        let f = m / unit;
        ((f - f.round()).abs() < 0.05 && f.round() >= 1.0).then(|| f.round() as i64)
    };
    match (whole(e.h, FOOT), whole(tall(e), FOOT)) {
        (Some(a), Some(b)) => format!("{a}×{b}"),
        _ => match (whole(e.h, FOOT / 12.0), whole(tall(e), FOOT / 12.0)) {
            (Some(a), Some(b)) if a <= 48 && b <= 48 => format!("{}×{}", a.min(b), a.max(b)),
            _ => String::new(),
        },
    }
}

// ---------------------------------------------------------------- drawing

fn shape(segs: Vec<Seg>, fill: Ink, stroke: Ink, line_w: f64, alpha: f64) -> Shape {
    Shape { el: String::new(), part: "body", geom: Geom::Path(segs), fill, stroke, line: line_w, dash: "", alpha, fade: None }
}

/// The skin's look: fill, how solid it is, and the cloth it is drawn as.
fn skin(id: &str) -> (Ink, f64, Option<Cloth>) {
    match id {
        "diff-light" => (Ink::Role("silk"), 0.45, None),
        "diff-medium" => (Ink::Role("silk"), 0.7, None),
        "diff-heavy" => (Ink::Role("silk"), 0.95, None),
        "silk" => (Ink::Role("silk"), 1.0, Some(Cloth::Silk)),
        "grid-cloth" => (Ink::Role("setsoft"), 1.0, Some(Cloth::Grid)),
        "bounce-white" => (Ink::Role("silk"), 1.0, None),
        "bounce-silver" => (Ink::hex("#BFC5CC"), 1.0, None),
        "bounce-gold" => (Ink::hex("#D9B24A"), 1.0, None),
        "muslin" => (Ink::Role("muslin"), 1.0, None),
        "single-net" => (Ink::None, 1.0, Some(Cloth::Single)),
        "double-net" => (Ink::None, 1.0, Some(Cloth::Double)),
        "solid" => (Ink::Role("screen"), 1.0, None),
        // A gel is clear but for its colour (drawn from its gels); no
        // material is no skin at all.
        "gel" | "none" => (Ink::None, 1.0, None),
        _ => match swatch(id).0 {
            "" => (Ink::Role("silk"), 0.7, None),
            hex => (Ink::hex(hex), 1.0, None),
        },
    }
}

/// A checkerboard's second colour, where the skin is one.
fn checks(id: &str) -> Option<&'static str> {
    Some(swatch(id).1).filter(|c| !c.is_empty())
}

/// The frame round the skin: the colour grips paint a net's, else the
/// grip's own.
fn pipe_ink(id: &str, pipe: &str) -> Ink {
    match (id, pipe) {
        (_, "black-pipe") => Ink::Role("screen"),
        ("single-net", _) => Ink::hex(GREEN),
        ("double-net", _) => Ink::hex(RED),
        ("silk", _) => Ink::hex(GOLD),
        _ => Ink::Role("grip"),
    }
}

/// How wide the low, front edge of a leaning frame is drawn against its
/// raised back edge — Scenario's lean (studied 2026-10-01): nothing lying
/// flat, a fifth narrower standing, eased in so the taper comes late, the
/// way a frame swinging up toward you looks.
pub fn taper(tilt: f64) -> f64 {
    let a = (tilt / 90.0).clamp(0.0, 1.0);
    1.0 - 0.2 * a * a * a
}

/// How heavy the raised edge's line is against the pipe's: the edge that
/// has come up toward you darkens as the frame stands.
pub fn raised(tilt: f64) -> f64 {
    let a = (tilt / 90.0).clamp(0.0, 1.0);
    1.0 + 0.9 * a * a
}

/// A frame drawn in its footprint, facing east: `w` along (the tilt's
/// foreshortening), `h` across. Leaning, it reads as a frame in space, not
/// a squashed one: its back edge — the one raised toward you — keeps its
/// width and is drawn heavier, its front edge narrows (`taper`), and the
/// skin, the cloth, the checks and the egg crate all lean with it. The
/// footprint it stands in is still the plan's honest `w` × `h`.
pub fn draw(e: &El, w: f64, h: f64) -> Vec<Shape> {
    let mut v = flat(e, w, h);
    let k = taper(e.tilt);
    // Standing, it is its pipe seen end-on: one straight line.
    if k < 1.0 && !standing(w, h) {
        let hw = w / 2.0;
        // Across shrinks toward the front: every edge across stays a line,
        // every edge along leans in, as Scenario's grid does.
        let warp = |x: f64, y: f64| {
            let t = ((x + hw) / w.max(1e-9)).clamp(0.0, 1.0);
            (x, y * (1.0 - (1.0 - k) * t))
        };
        for s in &mut v {
            if let Geom::Path(segs) = &mut s.geom {
                for seg in segs.iter_mut() {
                    *seg = match *seg {
                        Seg::M(x, y) => { let p = warp(x, y); Seg::M(p.0, p.1) }
                        Seg::L(x, y) => { let p = warp(x, y); Seg::L(p.0, p.1) }
                        Seg::C(a, b, c, d, x, y) => {
                            let (p, q, r) = (warp(a, b), warp(c, d), warp(x, y));
                            Seg::C(p.0, p.1, q.0, q.1, r.0, r.1)
                        }
                        Seg::Z => Seg::Z,
                    };
                }
            }
        }
    }
    v
}

/// Whether it stands near enough upright to be drawn as its pipe: within a
/// few degrees of it. Scenario keeps the lean right up to upright, and a
/// 12' frame at 80° is still well over a foot deep on the plan.
fn standing(w: f64, h: f64) -> bool {
    w <= EDGE + 1e-6 || w < h * 0.06
}

/// The frame as it would be drawn square-on, before it leans.
fn flat(e: &El, w: f64, h: f64) -> Vec<Shape> {
    let (hw, hh) = (w / 2.0, h / 2.0);
    let id = material_id(e);
    let (mut fill, solidity, cloth) = skin(id);
    // Custom Colour wears the piece's own colour.
    if id == "custom" && e.color.starts_with('#') {
        fill = Ink::hex(&e.color);
    }
    let pipe = if e.pipe.is_empty() { "open" } else { e.pipe.as_str() };
    let standing = standing(w, h);
    let mut v = Vec::new();
    // The skin.
    if fill != Ink::None {
        v.push(shape(rect(-hw, -hh, w, h), fill, Ink::None, 0.0, solidity));
    }
    if let Some(c) = cloth {
        if !standing {
            gear::cloth_detail(&mut v, c, w, h);
        }
    }
    // A checkerboard: its second colour in squares about a foot across.
    if let (Some(alt), false) = (checks(id), standing) {
        let n = ((w.max(h) / FOOT).round() as usize).clamp(2, 24);
        let (sw, sh) = (w / n as f64, h / n as f64);
        let mut segs = Vec::new();
        for i in 0..n {
            for j in 0..n {
                if (i + j) % 2 == 1 {
                    segs.extend(rect(-hw + i as f64 * sw, -hh + j as f64 * sh, sw, sh));
                }
            }
        }
        v.push(shape(segs, Ink::hex(alt), Ink::None, 0.0, 1.0));
    }
    // Gels clipped in it show as its colour, and let the skin through.
    for g in &e.gels {
        if let Some(hex) = gels::swatch(g) {
            v.push(shape(rect(-hw, -hh, w, h), Ink::hex(hex), Ink::None, 0.0, 0.4));
        }
    }
    // A bounce's shine: a diagonal across its face.
    if matches!(
        id,
        "bounce-white" | "bounce-silver" | "bounce-gold" | "silver-lame" | "gold-lame" | "soft-silver" | "soft-mirror" | "hard-mirror"
    ) && !standing
    {
        v.push(shape(line(-hw * 0.7, hh * 0.7, hw * 0.7, -hh * 0.7), Ink::None, Ink::Role("setline"), 0.5, 0.45));
    }
    // The pipe.
    let ink = pipe_ink(id, pipe);
    match pipe {
        "none" => v.push(shape(rect(-hw, -hh, w, h), Ink::None, Ink::Role("setline"), 0.5, 0.7)),
        "speed-rail" => {
            v.push(shape(rect(-hw, -hh, w, h), Ink::None, ink.clone(), 2.6, 1.0));
            let k = (h.min(w.max(EDGE)) * 0.06).clamp(0.05, 0.14);
            for (sx, sy) in [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)] {
                let (cx, cy) = (sx * hw, sy * hh);
                v.push(shape(rect(cx - k / 2.0, cy - k / 2.0, k, k), ink.clone(), Ink::None, 0.0, 1.0));
            }
        }
        "butterfly" => {
            v.push(shape(rect(-hw, -hh, w, h), Ink::None, ink.clone(), 2.0, 1.0));
            // The ears it hangs from, at the middle of each side.
            let r = (h * 0.03).clamp(0.04, 0.1);
            v.push(shape(circle(0.0, -hh, r), ink.clone(), Ink::None, 0.0, 1.0));
            v.push(shape(circle(0.0, hh, r), ink.clone(), Ink::None, 0.0, 1.0));
        }
        _ => v.push(shape(rect(-hw, -hh, w, h), Ink::None, ink.clone(), 2.0, 1.0)),
    }
    // Its raised edge, heavier the more it stands — the pipe across the
    // top, as Scenario marks it.
    if e.tilt > 0.0 && !standing {
        let base = if pipe == "none" { 0.5 } else { 2.0 };
        let edge = if pipe == "none" { Ink::Role("setline") } else { ink.clone() };
        v.push(shape(line(-hw, -hh, -hw, hh), Ink::None, edge, base * raised(e.tilt), 1.0));
    }
    // Standing, it rides two stands, one at each end.
    if standing {
        let r = (w * 0.45).clamp(0.035, 0.06);
        for s in [-1.0, 1.0] {
            v.push(shape(circle(-hw - r * 0.4, s * hh * 0.92, r), Ink::Role("grip"), Ink::None, 0.0, 1.0));
        }
    }
    // An egg crate on its face: a comb along the front, finer for a
    // tighter grid.
    if e.grid > 0.0 {
        let step = (0.06 + e.grid / 400.0).min(0.25);
        let n = ((h / step) as usize).clamp(2, 120);
        let depth = (0.05 + e.grid / 1200.0).min(0.12);
        let mut segs = Vec::new();
        if standing {
            for i in 0..=n {
                let y = -hh + h * i as f64 / n as f64;
                segs.extend(line(hw, y, hw + depth, y));
            }
            segs.extend(line(hw + depth, -hh, hw + depth, hh));
        } else {
            let m = ((w / step) as usize).clamp(2, 120);
            for i in 1..n {
                let y = -hh + h * i as f64 / n as f64;
                segs.extend(line(-hw, y, hw, y));
            }
            for i in 1..m {
                let x = -hw + w * i as f64 / m as f64;
                segs.extend(line(x, -hh, x, hh));
            }
        }
        v.push(shape(segs, Ink::None, Ink::Role("grip"), 0.5, 0.55));
    }
    v
}

#[cfg(test)]
mod stand_in_tests {
    use super::*;
    use crate::diagram::{render, Diagram, Kind};

    /// Every rag and flag the library hides can be built as a Frame: a real
    /// skin, pipe and egg crate, at the picture's size, standing, angled or
    /// hanging free, and it draws.
    #[test]
    fn the_frame_makes_every_rag_and_flag_the_library_hides() {
        let hidden: Vec<_> = fso::ART.iter().filter_map(|a| stand_in(a).map(|s| (a, s))).collect();
        let rags = fso::ART.iter().filter(|a| a.group == "Rags").count();
        let flags = fso::ART
            .iter()
            .filter(|a| a.group == "Frames & Boards" && ["silk", "scrim", "solid"].iter().any(|w| a.name.to_lowercase().contains(w)))
            .count();
        assert_eq!(hidden.len(), rags + flags, "every rag and every flag, nothing else");
        for (a, s) in &hidden {
            assert!(MATERIALS.iter().any(|m| m.0 == s.material), "{}: skin {}", a.name, s.material);
            assert!(PIPES.iter().any(|p| p.0 == s.pipe), "{}: pipe {}", a.name, s.pipe);
            assert!(s.grid == 0.0 || GRIDS.contains(&s.grid), "{}: egg crate {}", a.name, s.grid);
            assert!((s.width - a.w).abs() < 0.02, "{}: {} wide, the picture {}", a.name, s.width, a.w);
            let mut e = El::new(Kind::Light, "f");
            e.sym = SYM.into();
            e.material = s.material.into();
            e.pipe = s.pipe.into();
            e.grid = s.grid;
            e.h = s.width;
            e.tall = s.tall;
            e.tilt = s.tilt;
            settle(&mut e);
            assert_eq!(e.material, s.material, "{}: the skin stays", a.name);
            assert!(e.grid == s.grid, "{}: the egg crate stays", a.name);
            let mut d = Diagram::default();
            d.els.push(e);
            let shapes = render::render(&d, &render::Context::default(), &render::Options::default());
            assert!(shapes.iter().any(|sh| sh.el == "f"), "{}: draws", a.name);
        }
        // Boards and cards are not rags on a pipe: they stay in the library.
        for id in ["fso-4x4-foam-core", "fso-4x4-shiny-board-smooth", "fso-lightbridge-crls-c-100", "fso-mirror"] {
            assert!(stand_in(fso::find(id).unwrap()).is_none(), "{id} stays");
        }
    }

    /// Whatever the library offers sits in a section its library shows.
    #[test]
    fn every_offered_piece_sits_in_a_shown_section() {
        use crate::diagram::library;
        for (id, _, _, _, _, p) in symbols::offered() {
            let kinds = match p.lib {
                library::LIGHT => library::LIGHT_KINDS,
                library::GRIP => library::GRIP_KINDS,
                _ => library::SET_KINDS,
            };
            assert!(kinds.contains(&p.kind), "{id}: {} is not a {} section", p.kind, p.lib);
        }
    }

    /// The rags' skins by name, the way a grip says them.
    #[test]
    fn a_rag_is_named_by_its_size_and_skin() {
        let s = stand_in(fso::find("fso-12x12-ultra-bounce-with-frame").unwrap()).unwrap();
        assert_eq!((s.material, s.pipe, s.tilt), ("ultra-bounce", "open", 90.0));
        let s = stand_in(fso::find("fso-8x8-lcd-angled").unwrap()).unwrap();
        assert_eq!((s.material, s.grid, s.tilt), ("none", 40.0, 45.0));
        let s = stand_in(fso::find("fso-6x6-flag-free-hanging").unwrap()).unwrap();
        assert_eq!((s.material, s.pipe), ("solid", "none"));
        let s = stand_in(fso::find("fso-18x24-artificial-silk").unwrap()).unwrap();
        assert_eq!(s.material, "art-silk");
        assert!((s.width - 0.6096).abs() < 1e-6 && (s.tall - 0.4572).abs() < 1e-6, "18×24 inches");
        let mut e = El::new(Kind::Light, "f");
        e.sym = SYM.into();
        e.material = "ultra-bounce".into();
        e.h = 12.0 * FOOT;
        settle(&mut e);
        assert_eq!(plan_name(&e), "12×12 Ultra Bounce");
        e.material = "art-silk".into();
        e.h = 24.0 * FOOT / 12.0;
        e.tall = 18.0 * FOOT / 12.0;
        settle(&mut e);
        assert_eq!(plan_name(&e), "18×24 Artificial Silk");
        e.material = "none".into();
        e.grid = 40.0;
        e.h = 8.0 * FOOT;
        e.tall = 8.0 * FOOT;
        settle(&mut e);
        assert_eq!(plan_name(&e), "8×8 Egg Crate");
    }
}
