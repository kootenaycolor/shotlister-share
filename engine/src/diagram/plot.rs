//! **The lighting plot** (Labs, his call 2026-10-03): the Diagram rebuilt
//! after Roger Deakins's plots. A quiet plan underneath — thin grey walls,
//! furniture and props as plain outlines — and the lights as a handful of
//! marks, each kind of lamp with its own mark in the sheet's legend, the
//! information carried by written notes.
//!
//! Everything here is drawn about the origin facing east, the way the plan
//! faces things; `render` moves it into place. Marks are a fixed size on
//! the page (`MARK_PT`), like the symbols on a map; the plan, frames and a
//! camera's view are to scale.

use super::render::{arc, circle, ellipse, line, poly, rect, rrect, Geom, Ink, Seg, Shape};
use super::{fso, symbols, Diagram, El, Kind};

/// How big a lamp's mark is on the page, in points, at any zoom.
pub const MARK_PT: f64 = 20.0;

// ---------------------------------------------------------------- marks

/// The marks a plot is drawn with — Deakins's handful, and a letter for
/// anything else ("B: rigged with 2× Source 4").
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mark {
    Chevron,
    Wedge,
    Bar,
    DoubleBar,
    Ring,
    Dot,
    Arrow,
    Square,
    /// A soft panel seen from above (LiteMat, book light, overhead frame,
    /// soft box): a rectangle of its true size, `w` × `h`, whatever it is
    /// turned to. His ask, 2026-10-15.
    Mat,
    Letter(char),
}

impl Mark {
    pub fn as_str(&self) -> String {
        match self {
            Mark::Chevron => "chevron".into(),
            Mark::Wedge => "wedge".into(),
            Mark::Bar => "bar".into(),
            Mark::DoubleBar => "double-bar".into(),
            Mark::Ring => "ring".into(),
            Mark::Dot => "dot".into(),
            Mark::Arrow => "arrow".into(),
            Mark::Square => "square".into(),
            Mark::Mat => "mat".into(),
            Mark::Letter(c) => format!("letter-{c}"),
        }
    }
    pub fn parse(s: &str) -> Option<Mark> {
        Some(match s {
            "chevron" => Mark::Chevron,
            "wedge" => Mark::Wedge,
            "bar" => Mark::Bar,
            "double-bar" => Mark::DoubleBar,
            "ring" => Mark::Ring,
            "dot" => Mark::Dot,
            "arrow" => Mark::Arrow,
            "square" => Mark::Square,
            "mat" => Mark::Mat,
            other => {
                let c = other.strip_prefix("letter-")?.chars().next()?;
                Mark::Letter(c.to_ascii_uppercase())
            }
        })
    }
}

/// How one kind of lamp is marked on a sheet: the mark, its ink (`added`
/// red, `ink` black, `blue`) and whether it is drawn solid.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Look {
    pub mark: Mark,
    pub ink: &'static str,
    pub solid: bool,
}

impl Look {
    pub fn ink(&self) -> Ink {
        Ink::Role(self.ink)
    }
}

pub fn ink_word(s: &str) -> Option<&'static str> {
    match s {
        "added" | "red" => Some("added"),
        "practical" | "amber" => Some("practical"),
        "ink" | "black" => Some("ink"),
        "blue" => Some("blue"),
        _ => None,
    }
}

/// The mark a lamp starts with, from what kind of unit it is: a hard head
/// or a spot a chevron, a soft source a wedge, a tube a bar, a panel or mat
/// a double bar, a practical a ring, a lantern or space light a dot. Never
/// an arrow (his note, 2026-10-05: *"i dont think arrows should be
/// considered lighting units"*); an arrow mark a lamp already wears is kept.
pub fn family(sym: &str, w: f64, h: f64) -> Mark {
    let name = fso::find(sym).map(|a| a.name).or_else(|| symbols::find(sym).map(|s| s.name)).unwrap_or("");
    let n = name.to_lowercase();
    let has = |words: &[&str]| words.iter().any(|w| n.contains(w));
    if has(&["china ball", "spacelight", "space light", "lantern", "balloon", "chimera pancake"]) {
        Mark::Dot
    } else if has(&["bulb", "shade", "practical", "wall light", "sconce", "street", "flashlight", "torch", "candle"]) {
        Mark::Ring
    } else if has(&["ellipsoidal", "leko", "source 4", "source four", "beam", "spot"]) && !has(&["spotlight max"]) {
        Mark::Chevron
    } else if has(&["tube", "ribbon", "q-led", "titan", "helios", "pixel", "kino bare", "strip"]) {
        Mark::Bar
    } else if has(&["litemat", "skypanel", "panel", "diva", "gaffer 4", " mat", "vortex", "celeb", "astra", "dyno", "mixpanel", "kino", "flex", "s360"]) {
        Mark::DoubleBar
    } else if has(&["dome", "softbox", "pancake", "briese", "book", "lightning"]) {
        Mark::Wedge
    } else if w.max(h) / w.min(h).max(0.01) >= 3.0 {
        Mark::Bar
    } else {
        Mark::Chevron
    }
}

/// Whether a piece is a lamp the plot marks (not a frame, flag or stand).
pub fn is_lamp(e: &El) -> bool {
    e.kind == Kind::Light && !super::frame::is_frame(e) && (e.sym.is_empty() || symbols::emits(&e.sym))
}

/// A look written as one word, for the legend and the wire:
/// `chevron|added|open`.
pub fn look_key(l: &Look) -> String {
    format!("{}|{}|{}", l.mark.as_str(), l.ink, if l.solid { "solid" } else { "open" })
}

pub fn parse_key(s: &str) -> Option<Look> {
    let mut p = s.split('|');
    let mark = Mark::parse(p.next()?)?;
    let ink = ink_word(p.next().unwrap_or("added"))?;
    let solid = match p.next() {
        Some("solid") => true,
        Some("open") => false,
        _ => default_solid(mark),
    };
    Some(Look { mark, ink, solid })
}

/// The look he picked for a lamp, if he picked one. **Its Type is its
/// colour** (his call, 2026-10-04: one control per job): a film light red,
/// a practical amber, the location's own black, whatever ink was once
/// written on the mark.
pub fn chosen(e: &El) -> Option<Look> {
    let mark = Mark::parse(&e.mark)?;
    let ink = type_ink(e);
    let solid = match e.mark_fill.as_str() {
        "solid" => true,
        "open" => false,
        _ => default_solid(mark),
    };
    Some(Look { mark, ink, solid })
}

/// The ink a lamp's type starts it in: a film light red, a practical
/// amber, the location's own black.
pub fn type_ink(e: &El) -> &'static str {
    if e.existing {
        "ink"
    } else if e.practical {
        "practical"
    } else {
        "added"
    }
}

/// Gives a lamp a mark of its own: its shape and whether it is solid. Its
/// ink stays its Type's.
pub fn set_look(e: &mut El, l: Look) {
    e.mark = l.mark.as_str();
    e.mark_ink.clear();
    e.mark_fill = if l.solid { "solid".into() } else { "open".into() };
}

/// Two looks are the same **symbol** when they share a shape and a fill;
/// the ink is only the lamp's Type. A symbol's name holds across Types —
/// a 2K Blonde made Existing is still a 2K Blonde, drawn black.
pub fn same_symbol(a: &Look, b: &Look) -> bool {
    a.mark == b.mark && a.solid == b.solid
}

/// What a symbol was named on a sheet saved before lights carried their own
/// Names (`own_names`), by any ink it was named in.
pub fn symbol_name(d: &Diagram, look: &Look) -> Option<String> {
    d.legend.iter().find(|n| colour_key(&n.key).is_none() && parse_key(&n.key).map(|l| same_symbol(&l, look)).unwrap_or(false)).map(|n| n.name.clone())
}

/// **A light's Name** — its label. His call, 2026-10-15: *labels are just
/// what you type*. A lamp put down has none until he types one; a plan
/// saved before keeps the unit's name it showed (`own_names` writes it on).
pub fn lamp_name(e: &El) -> String {
    e.lamp_name.trim().to_string()
}

/// **What a lamp is**, for counting gear: its label, else its unit's name
/// ("Arri M18"), else nothing — the gear list and a shared label's count.
pub fn unit_name(e: &El) -> String {
    let own = lamp_name(e);
    if !own.is_empty() || e.sym.is_empty() {
        own
    } else {
        symbols::plan_name(&e.sym)
    }
}

/// **Every lamp's look on the sheet**, by id. A lamp he marked keeps its
/// mark; one with none is marked from its unit's family. **Two units may
/// share a symbol** (his call, 2026-10-05: three kinds of panel are three
/// panels): their Names tell them apart.
pub fn looks(d: &Diagram) -> Vec<(String, Look)> {
    d.els
        .iter()
        .filter(|e| is_lamp(e) && !e.hidden)
        .map(|e| {
            let look = chosen(e).unwrap_or_else(|| {
                let mark = family(&e.sym, e.w, e.h);
                Look { mark, ink: type_ink(e), solid: default_solid(mark) }
            });
            (e.id.clone(), look)
        })
        .collect()
}

/// The looks a sheet saved before 2026-10-05 drew: where two units would
/// look alike, the second stepped to solid, then a letter. Only for
/// `own_names`, so an old plan looks as it did.
fn looks_stepped(d: &Diagram) -> Vec<(String, Look)> {
    let lamps: Vec<&El> = d.els.iter().filter(|e| is_lamp(e) && !e.hidden).collect();
    let mut taken: Vec<Look> = lamps.iter().filter_map(|e| chosen(e)).collect();
    let mut by_unit: Vec<(String, Look)> = Vec::new();
    let mut letter = b'A';
    let mut out = Vec::new();
    for e in lamps {
        if let Some(l) = chosen(e) {
            out.push((e.id.clone(), l));
            continue;
        }
        let unit = e.sym.clone();
        if let Some((_, l)) = by_unit.iter().find(|(u, _)| *u == unit) {
            out.push((e.id.clone(), *l));
            continue;
        }
        let mark = family(&e.sym, e.w, e.h);
        let ink = type_ink(e);
        let solid = default_solid(mark);
        let tries = [Look { mark, ink, solid }, Look { mark, ink, solid: !solid }];
        let look = tries.into_iter().find(|t| !taken.iter().any(|k| same_symbol(k, t))).unwrap_or_else(|| {
            let l = Look { mark: Mark::Letter(letter as char), ink, solid: false };
            letter = if letter >= b'Z' { b'A' } else { letter + 1 };
            l
        });
        taken.push(look);
        by_unit.push((unit, look));
        out.push((e.id.clone(), look));
    }
    out
}

/// **Names move onto the lights** (2026-10-05). A plan saved while names
/// lived on symbols: every light takes its symbol's name, and a light whose
/// mark was worked out keeps the mark it was drawn with — nothing on the
/// paper changes. The symbols' names are then spent; colours' meanings
/// stay. Once only: it marks the plan `lamp_names`.
pub fn own_names(d: &mut Diagram) {
    old_names(d);
    typed_labels(d);
    free_names(d);
}

/// **A plan from before every piece took a typed label** (2026-10-17, his
/// words: *"I still can't manually just label a silk"*): a frame wrote its
/// size and cloth as its name, grip its kind, a half round its diameter.
/// Those words are written on as ordinary labels he can change or clear, so
/// the paper reads as it did. Once only: it marks the plan `free_names`;
/// pieces put down after start with none.
pub fn free_names(d: &mut Diagram) {
    if d.settings.free_names {
        return;
    }
    d.settings.free_names = true;
    for e in d.els.iter_mut() {
        if e.kind == Kind::Light && super::frame::is_frame(e) {
            // Its cloth was the old default when none was picked.
            if e.material.is_empty() {
                e.material = super::frame::OLD_DEFAULT.to_string();
            }
            if e.lamp_name.trim().is_empty() {
                e.lamp_name = super::render::frame_spec(e);
            }
        } else if e.kind == Kind::Light && !is_lamp(e) {
            if e.label.trim().is_empty() {
                e.label = symbols::plan_name(&e.sym);
            }
        } else if e.kind == Kind::Set && symbols::is_half_round(e) && e.label.trim().is_empty() {
            e.label = symbols::half_round_size(e);
        }
    }
    // A shared label's own words showed only while none of its pieces had
    // a Name; now they always show. Words left on one whose pieces were
    // named since are cleared, so it says what it said.
    let named_labels: Vec<String> = d
        .els
        .iter()
        .filter(|t| t.kind == Kind::Text && !t.text.trim().is_empty())
        .filter(|t| {
            let names: Vec<String> = d.els.iter().filter(|e| e.tie_to == t.id && can_share(e)).map(|e| super::render::piece_name(e, &Default::default())).filter(|n| !n.is_empty()).collect();
            !names.is_empty() && !names.iter().all(|n| n == t.text.trim())
        })
        .map(|t| t.id.clone())
        .collect();
    for t in d.els.iter_mut().filter(|t| named_labels.contains(&t.id)) {
        t.text.clear();
    }
}

/// **A plan from before labels were typed** (2026-10-15): a lamp with no
/// Name showed its unit's; that name is written on as its label, one he can
/// change, so the paper reads as it did. Once only: it marks the plan
/// `typed_labels`, and lamps put down after start with none.
pub fn typed_labels(d: &mut Diagram) {
    if d.settings.typed_labels {
        return;
    }
    d.settings.typed_labels = true;
    for e in d.els.iter_mut().filter(|e| is_lamp(e)) {
        if e.lamp_name.trim().is_empty() && !e.sym.is_empty() {
            e.lamp_name = symbols::plan_name(&e.sym);
        }
    }
}

fn old_names(d: &mut Diagram) {
    if d.settings.lamp_names {
        return;
    }
    d.settings.lamp_names = true;
    let old = looks_stepped(d);
    let named: Vec<(String, Look, Option<String>)> = old.iter().map(|(id, l)| (id.clone(), *l, symbol_name(d, l))).collect();
    for e in d.els.iter_mut() {
        let Some((_, look, name)) = named.iter().find(|(id, _, _)| *id == e.id) else { continue };
        if chosen(e).is_none() {
            set_look(e, *look);
        }
        if e.lamp_name.trim().is_empty() {
            if let Some(n) = name {
                e.lamp_name = n.clone();
            }
        }
    }
    d.legend.retain(|x| colour_key(&x.key).is_some());
}

/// One line of a sheet's legend: a mark, and one Name drawn with it.
#[derive(Clone, Debug, PartialEq)]
pub struct Entry {
    /// Its look, then its Name: `double-bar|added|solid|SkyPanel S60`; the
    /// look alone for lamps not named yet.
    pub key: String,
    pub look: Look,
    /// The lamps' Name; empty when they have none yet.
    pub name: String,
    /// He named them himself (not their unit's name).
    pub named: bool,
    /// How many units — counts summed.
    pub count: u32,
    /// The lamps on this line, by id — what a click on it picks.
    pub ids: Vec<String>,
}

/// A legend line's key: the look, and the Name when there is one.
pub fn entry_key(look: &Look, name: &str) -> String {
    if name.trim().is_empty() {
        look_key(look)
    } else {
        format!("{}|{}", look_key(look), name.trim())
    }
}

/// **The sheet's legend** (his pick, 2026-10-15): a line per label, each
/// with its symbol — "SkyPanel S60 ×2", "LiteMat 4 ×1" — labels of one
/// symbol together, symbols in the order they first appear, then the lamps
/// with no label, a line per symbol.
pub fn legend(d: &Diagram) -> Vec<Entry> {
    let looks = looks(d);
    let mut out: Vec<Entry> = Vec::new();
    let mut order: Vec<String> = Vec::new();
    for (id, look) in &looks {
        let Some(e) = d.get(id) else { continue };
        let name = lamp_name(e);
        let key = entry_key(look, &name);
        let lk = look_key(look);
        if !order.contains(&lk) {
            order.push(lk);
        }
        let n = e.count.max(1);
        let own = !e.lamp_name.trim().is_empty();
        match out.iter_mut().find(|x| x.key == key) {
            Some(x) => {
                x.count += n;
                x.ids.push(e.id.clone());
                x.named |= own;
            }
            None => out.push(Entry { key, look: *look, name, named: own, count: n, ids: vec![e.id.clone()] }),
        }
    }
    // Labelled lines first, by symbol; lamps with no label after them
    // (his pick, 2026-10-15: one line per label, the unlabelled faint).
    out.sort_by_key(|x| (x.name.trim().is_empty(), order.iter().position(|k| *k == look_key(&x.look)).unwrap_or(usize::MAX)));
    out
}

fn default_solid(m: Mark) -> bool {
    matches!(m, Mark::Wedge | Mark::Bar | Mark::DoubleBar | Mark::Dot)
}

/// Nothing at all — an area to pick a thing by that draws nothing.
pub fn clear() -> Ink {
    Ink::Hex("#000000".into(), 0.0)
}

fn shape(segs: Vec<Seg>, fill: Ink, stroke: Ink, line: f64) -> Shape {
    let mut s = Shape::new("", "body", Geom::Path(segs));
    s.fill = fill;
    s.stroke = stroke;
    s.line = line;
    s
}

/// A mark `s` metres across, facing east. `long` is how long a tube or a
/// panel is on the plan: a bar is drawn at its true length when that is
/// longer than the mark. `ink` is what to draw it in.
pub fn mark(look: Look, s: f64, long: f64, ink: Ink) -> Vec<Shape> {
    let paper = Ink::Role("paper");
    let solid = look.solid;
    let fill = |segs: Vec<Seg>| shape(segs, ink.clone(), Ink::None, 0.0);
    let outline = |segs: Vec<Seg>, w: f64| shape(segs, clear(), ink.clone(), w);
    let mut v = Vec::new();
    match look.mark {
        Mark::Chevron => {
            let pts = [(s / 2.0, -s * 0.42), (-s / 2.0, 0.0), (s / 2.0, s * 0.42)];
            if solid {
                let inner = [(s / 2.0, -s * 0.42), (-s / 2.0, 0.0), (s / 2.0, s * 0.42), (s * 0.18, 0.0)];
                v.push(fill(poly(&inner, true)));
            } else {
                v.push(shape(poly(&pts, true), clear(), Ink::None, 0.0));
                v.push(shape(poly(&pts, false), Ink::None, ink.clone(), 2.2));
            }
        }
        Mark::Wedge => {
            let pts = [(-s / 2.0, 0.0), (s / 2.0, -s * 0.45), (s / 2.0, s * 0.45)];
            v.push(if solid { fill(poly(&pts, true)) } else { outline(poly(&pts, true), 1.8) });
        }
        Mark::Bar => {
            // Across the way it faces, as long as the unit is.
            let len = long.max(s);
            let t = s * 0.2;
            let segs = rect(-t / 2.0, -len / 2.0, t, len);
            v.push(if solid { fill(segs) } else { outline(segs, 1.4) });
        }
        Mark::DoubleBar => {
            // A panel: a box with a heavy front edge, so it never reads as
            // a tube's thin bar. Solid is the whole box; open is its
            // outline with the lit face filled.
            let len = long.max(s);
            let d = s * 0.5;
            let face = s * 0.16;
            if solid {
                v.push(fill(rect(-d / 2.0, -len / 2.0, d, len)));
            } else {
                v.push(outline(rect(-d / 2.0, -len / 2.0, d, len), 1.4));
                v.push(fill(rect(d / 2.0 - face, -len / 2.0, face, len)));
            }
        }
        Mark::Ring => {
            let r = s * 0.36;
            if solid {
                v.push(fill(circle(0.0, 0.0, r)));
                v.push(shape(circle(0.0, 0.0, r * 0.38), paper.clone(), Ink::None, 0.0));
            } else {
                v.push(shape(circle(0.0, 0.0, r), paper.clone(), ink.clone(), 1.8));
                v.push(fill(circle(0.0, 0.0, r * 0.36)));
            }
        }
        Mark::Dot => {
            let r = s * 0.3;
            v.push(if solid { fill(circle(0.0, 0.0, r)) } else { shape(circle(0.0, 0.0, r), paper.clone(), ink.clone(), 1.8) });
        }
        Mark::Arrow => {
            let head = [(s * 0.1, -s * 0.3), (s / 2.0, 0.0), (s * 0.1, s * 0.3)];
            v.push(shape(line(-s / 2.0, 0.0, s * 0.42, 0.0), Ink::None, ink.clone(), 2.0));
            v.push(if solid { fill(poly(&head, true)) } else { shape(poly(&head, false), Ink::None, ink.clone(), 2.0) });
        }
        Mark::Square => {
            let a = s * 0.66;
            let segs = rect(-a / 2.0, -a / 2.0, a, a);
            v.push(if solid { fill(segs) } else { outline(segs, 1.8) });
        }
        Mark::Letter(_) => {
            v.push(shape(circle(0.0, 0.0, s * 0.45), paper.clone(), ink.clone(), 1.6));
        }
        // Its legend picture and the stand-in on a string: the same soft
        // rectangle, small. On the plan it is drawn at size (`mat`).
        Mark::Mat => v.extend(mat(s * 0.84, s * 0.54, solid, ink)),
    }
    v
}

/// Laid over a location's lamp that is turned off: a cross, as Deakins
/// marks a street lamp.
pub fn crossed(s: f64, ink: Ink) -> Vec<Shape> {
    let r = s * 0.42;
    vec![shape(line(-r, -r, r, r), Ink::None, ink.clone(), 1.8), shape(line(-r, r, r, -r), Ink::None, ink, 1.8)]
}

/// **What can share a label** (his ask, 2026-10-05: *"frames and any
/// object can share the 'same label' function"*): any piece that stands on
/// the plan — a lamp, a frame, grip, a set piece, a camera, a person,
/// track, a road, a shape, a picture. Not words, walls and their openings,
/// or the lines drawn to measure and point.
pub fn can_share(e: &El) -> bool {
    matches!(e.kind, Kind::Light | Kind::Set | Kind::Camera | Kind::Cast | Kind::Track | Kind::Road | Kind::Shape | Kind::Image)
}

/// **A lamp hung pointing straight down** (his ask, 2026-10-05: a LiteMat
/// 8 over the set): its Lean at nought, as a frame lying flat is.
pub fn points_down(e: &El) -> bool {
    is_lamp(e) && e.tilt < 1.0
}

/// **A soft panel from above** (his ask, 2026-10-15: *"a rectangle light
/// that is a top-down mat-type light that's resizable to whatever I want"*):
/// its true `w` × `h` about the origin, in the lamp's heavy edge, a faint
/// wash over it and a fine inner line — the diffusion — which is what says
/// it is a soft panel and never a grip frame (dashed, thin) or a ceiling
/// light (crossed). Solid deepens the wash. It has no front: it lies flat.
pub fn mat(w: f64, h: f64, solid: bool, ink: Ink) -> Vec<Shape> {
    let (hw, hh) = (w / 2.0, h / 2.0);
    let mut v = Vec::new();
    let mut wash = shape(rect(-hw, -hh, w, h), ink.clone(), Ink::None, 0.0);
    wash.alpha = if solid { 0.42 } else { 0.13 };
    v.push(wash);
    v.push(shape(rect(-hw, -hh, w, h), clear(), ink.clone(), 2.6));
    let inset = (w.min(h) * 0.17).min(0.2);
    if w > inset * 3.0 && h > inset * 3.0 {
        let mut fine = shape(rect(-hw + inset, -hh + inset, w - 2.0 * inset, h - 2.0 * inset), Ink::None, ink, 0.8);
        fine.alpha = 0.75;
        v.push(fine);
    }
    v
}

/// How big a mat is drawn, metres: its own size, but never less than a
/// third of a mark, so a small one can still be seen and picked.
pub fn mat_size(e: &El, m: f64) -> (f64, f64) {
    (e.w.max(m * 0.3), e.h.max(m * 0.3))
}

/// A lamp pointing straight down, facing no way on the plan: its true size
/// from above (a mark across at least), a thin cross corner to corner — the
/// sign for a thing on the ceiling — heavy edges, and no front edge. `cross` false for a
/// lettered mark, whose letter sits in the box instead.
pub fn down(w: f64, h: f64, solid: bool, cross: bool, ink: Ink) -> Vec<Shape> {
    let (hw, hh) = (w / 2.0, h / 2.0);
    let mut v = Vec::new();
    if solid {
        let mut f = shape(rect(-hw, -hh, w, h), ink.clone(), Ink::None, 0.0);
        f.alpha = 0.16;
        v.push(f);
    }
    // **Heavy edges** (his note, 2026-10-05: *"thick edges so the overhead
    // square doesnt look like a grip frame"*): a lamp's housing, not a
    // frame's thin dashed line.
    v.push(shape(rect(-hw, -hh, w, h), clear(), ink.clone(), 3.6));
    if cross {
        v.push(shape(line(-hw, -hh, hw, hh), Ink::None, ink.clone(), 0.8));
        v.push(shape(line(-hw, hh, hw, -hh), Ink::None, ink, 0.8));
    }
    v
}

// ---------------------------------------------------------------- frames

/// **A frame on a plot**: its true footprint, plainly, with a pattern
/// that says what kind of frame it is (his ask, 2026-10-03). Standing
/// upright, a double line at its width; lying flat, its dashed outline;
/// leaning, the floor it covers in perspective — its raised back edge
/// heavy and full width, its front edge narrower (a third at upright) —
/// so it reads as tilted
/// and which way. `w` along (already the lean's footprint), `h`
/// across; facing east, so the raised edge is the west one.
///
/// **Quiet unless `full`** (Back to Paper, his call 2026-10-04: no
/// hatching, no perspective): a frame in plan is a line or a double line —
/// standing, the double line; leaning, its raised edge as one line; lying
/// flat, its dashed outline, its cloth quietly across it while `fabric`
/// (View › Frame Fabric). `full` is the picked frame on screen, which shows
/// its lean and its cloth at full strength.
pub fn frame(w: f64, h: f64, standing: bool, tilt: f64, material: &str, ink: Ink, full: bool, fabric: bool) -> Vec<Shape> {
    let (hw, hh) = (w / 2.0, h / 2.0);
    let mut v = Vec::new();
    if standing {
        for x in [-0.035, 0.035] {
            v.push(shape(line(x, -hh, x, hh), Ink::None, ink.clone(), 1.2));
        }
        v.push(shape(rect(-0.08, -hh, 0.16, h), clear(), Ink::None, 0.0));
        return v;
    }
    if !full {
        // Picked anywhere on the floor it covers.
        v.push(shape(rect(-hw, -hh, w, h), clear(), Ink::None, 0.0));
        // **Its cloth stays on** (his note, 2026-10-05: *"the texture of the
        // frame dissapears after I select off of it"*): quieter than while
        // picked, on paper too, unless View › Frame Fabric is off.
        if fabric {
            v.extend(cloth(w, h, material, &ink, true));
        }
        if tilt > 1.0 {
            v.push(shape(line(-hw, -hh, -hw, hh), Ink::None, ink, 1.4));
        } else {
            let mut s = shape(rect(-hw, -hh, w, h), Ink::None, ink, 1.2);
            s.dash = "dash";
            v.push(s);
        }
        return v;
    }
    v.extend(cloth(w, h, material, &ink, false));
    let mut edge = |a: (f64, f64), b: (f64, f64), heavy: bool| {
        let mut s = shape(line(a.0, a.1, b.0, b.1), Ink::None, ink.clone(), if heavy { 2.2 } else { 1.2 });
        if !heavy {
            s.dash = "dash";
        }
        v.push(s);
    };
    let leaning = tilt > 1.0;
    edge((-hw, -hh), (-hw, hh), leaning);
    edge((hw, -hh), (hw, hh), false);
    edge((-hw, -hh), (hw, -hh), false);
    edge((-hw, hh), (hw, hh), false);
    // **In perspective** (his ask, 2026-10-03: the old Diagram's lean,
    // without its stands and pipe): the raised back edge keeps its width,
    // the front edge narrows (`frame::taper`), and the pattern leans with
    // it, so a leaning frame reads as one swinging up toward you.
    if leaning {
        // Stronger than the picture's eased lean, which only shows near
        // upright: on a plot the narrowing is plain from a few degrees.
        let k = 1.0 - 0.32 * tilt.to_radians().sin().clamp(0.0, 1.0);
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

/// **A frame's cloth**: a wash and the pattern its kind is drawn with,
/// across a `w` × `h` box about the origin. `quiet`, as it lies on the plan
/// unpicked: fainter and finer, so a big frame does not shout.
fn cloth(w: f64, h: f64, material: &str, ink: &Ink, quiet: bool) -> Vec<Shape> {
    let (hw, hh) = (w / 2.0, h / 2.0);
    let mut v = Vec::new();
    let mut wash = shape(rect(-hw, -hh, w, h), ink.clone(), Ink::None, 0.0);
    wash.alpha = match (material == "solid", quiet) {
        (true, false) => 0.55,
        (true, true) => 0.3,
        (false, false) => 0.06,
        (false, true) => 0.03,
    };
    v.push(wash);
    // The kind of frame, as a pattern across it.
    let step = (w.max(h) / 9.0).clamp(0.1, 0.35);
    let (line_w, line_a, dot_a) = if quiet { (0.45, 0.4, 0.45) } else { (0.6, 0.75, 0.8) };
    let thin = |segs: Vec<Seg>| {
        let mut s = shape(segs, Ink::None, ink.clone(), line_w);
        s.alpha = line_a;
        s
    };
    match pattern(material) {
        Pattern::Dots(k) => {
            let gap = step * k;
            let mut y = -hh + gap / 2.0;
            let mut row = 0;
            while y < hh {
                let mut x = -hw + gap / 2.0 + if row % 2 == 1 { gap / 2.0 } else { 0.0 };
                while x < hw {
                    let mut d = shape(circle(x, y, (step * 0.06).max(0.012)), ink.clone(), Ink::None, 0.0);
                    d.alpha = dot_a;
                    v.push(d);
                    x += gap;
                }
                y += gap * 0.87;
                row += 1;
            }
        }
        Pattern::Lines(angles, k) => {
            for a in angles {
                for seg in hatch(w, h, *a, step * k) {
                    v.push(thin(seg));
                }
            }
        }
        Pattern::Plain => {}
    }
    v
}

enum Pattern {
    /// A stipple, its spacing in steps: diffusion and silk.
    Dots(f64),
    /// Lines at these angles, their spacing in steps.
    Lines(&'static [f64], f64),
    Plain,
}

/// The pattern a kind of frame is drawn with: diffusion stippled, lighter
/// to heavier; grid cloth cross-hatched; nets fine diagonals, a double
/// net closer; bounces broad diagonals; a solid filled; screens, colour,
/// gel and none plain.
fn pattern(material: &str) -> Pattern {
    match material {
        "diff-light" | "art-silk" => Pattern::Dots(1.6),
        "diff-medium" | "silk" => Pattern::Dots(1.1),
        "diff-heavy" => Pattern::Dots(0.75),
        "grid-cloth" => Pattern::Lines(&[45.0, -45.0], 1.4),
        "single-net" => Pattern::Lines(&[45.0], 1.4),
        "double-net" => Pattern::Lines(&[45.0], 0.8),
        "solid" | "blue-screen" | "green-screen" | "custom" | "gel" | "none" | "undecided" => Pattern::Plain,
        m if m.starts_with("check-") => Pattern::Lines(&[0.0, 90.0], 1.5),
        _ => Pattern::Lines(&[-45.0], 1.0),
    }
}

/// Parallel lines at `deg` across a `w` × `h` box about the origin, `gap`
/// apart, cut to the box.
fn hatch(w: f64, h: f64, deg: f64, gap: f64) -> Vec<Vec<Seg>> {
    let (hw, hh) = (w / 2.0, h / 2.0);
    let (dx, dy) = (deg.to_radians().cos(), deg.to_radians().sin());
    let (nx, ny) = (-dy, dx);
    let span = hw.hypot(hh);
    let n = (span / gap.max(0.02)).ceil() as i64;
    let mut out = Vec::new();
    for k in -n..=n {
        let c = (k as f64 * gap + gap / 2.0, 0.0);
        let o = (nx * c.0, ny * c.0);
        // Clip the line o + t·d to the box (Liang–Barsky).
        let (mut t0, mut t1) = (-1e9f64, 1e9f64);
        let mut keep = true;
        for (p, q) in [(-dx, o.0 + hw), (dx, hw - o.0), (-dy, o.1 + hh), (dy, hh - o.1)] {
            if p.abs() < 1e-12 {
                if q < 0.0 {
                    keep = false;
                }
            } else {
                let r = q / p;
                if p < 0.0 { t0 = t0.max(r) } else { t1 = t1.min(r) }
            }
        }
        if keep && t1 > t0 + 1e-6 {
            out.push(line(o.0 + dx * t0, o.1 + dy * t0, o.0 + dx * t1, o.1 + dy * t1));
        }
    }
    out
}

// ---------------------------------------------------------------- objects

/// **Furniture and props, drawn simply** (his ask, 2026-10-03: *"make
/// better drawing for simple objects"*): a line drawing anyone reads at a
/// glance — a bed with its pillows, a couch with its back and arms, a car
/// with its glass — in one light ink, nothing filled but paper. `w` along
/// the way it faces (east), `h` across.
pub fn object(sym: &str, w: f64, h: f64) -> Vec<Shape> {
    let name = fso::find(sym).map(|a| a.name).or_else(|| symbols::find(sym).map(|s| s.name)).unwrap_or(sym);
    let n = format!("{} {}", sym, name).to_lowercase();
    let has = |words: &[&str]| words.iter().any(|w| n.contains(w));
    let ink = Ink::Role("prop");
    let paper = Ink::Role("paper");
    let (hw, hh) = (w / 2.0, h / 2.0);
    let body = |segs: Vec<Seg>| shape(segs, paper.clone(), ink.clone(), 1.2);
    let line_of = |segs: Vec<Seg>| shape(segs, Ink::None, ink.clone(), 0.9);
    let r = (w.min(h) * 0.08).min(0.06);
    let mut v = Vec::new();
    if sym == "building" {
        // A footprint in the walls' ink, heavier than furniture: the block
        // a plot names "709" or "BANK".
        v.push(shape(rect(-hw, -hh, w, h), paper.clone(), Ink::Role("plan"), 2.0));
        return v;
    }
    if sym == "stairs-l" || sym == "stairs-u" {
        // **Stairs that turn**, as plans draw them: each flight's treads
        // across it, a square landing at the turn, and one arrow walking up
        // the whole way. An L climbs the left side and turns right along
        // the top; a U climbs the left, crosses the landing, and comes down
        // the right.
        let u = sym == "stairs-u";
        let f = if u { (w * 0.45).min(h * 0.45) } else { (w.min(h) * 0.4).max(0.6).min(w.min(h)) };
        let body = |segs: Vec<Seg>| shape(segs, paper.clone(), ink.clone(), 1.2);
        let line_of = |segs: Vec<Seg>| shape(segs, Ink::None, ink.clone(), 0.9);
        let tread = 0.28;
        let (l, r, t, b) = (-hw, hw, -hh, hh);
        // The outline.
        let outline: Vec<(f64, f64)> = if u {
            vec![(l, t), (r, t), (r, b), (r - f, b), (r - f, t + f), (l + f, t + f), (l + f, b), (l, b)]
        } else {
            vec![(l, t), (r, t), (r, t + f), (l + f, t + f), (l + f, b), (l, b)]
        };
        v.push(body(poly(&outline, true)));
        // The landing's edge.
        v.push(line_of(line(l, t + f, l + f, t + f)));
        if u {
            v.push(line_of(line(r - f, t + f, r, t + f)));
        } else {
            v.push(line_of(line(l + f, t, l + f, t + f)));
        }
        // Treads up the left flight.
        let up = |x0: f64, x1: f64, v: &mut Vec<Shape>| {
            let run = b - (t + f);
            let n = (run / tread).round().clamp(2.0, 30.0) as usize;
            for i in 1..n {
                let y = t + f + run * i as f64 / n as f64;
                v.push(line_of(line(x0, y, x1, y)));
            }
        };
        up(l, l + f, &mut v);
        if u {
            up(r - f, r, &mut v);
        } else {
            // Treads along the top flight.
            let run = r - (l + f);
            let n = (run / tread).round().clamp(2.0, 30.0) as usize;
            for i in 1..n {
                let x = l + f + run * i as f64 / n as f64;
                v.push(line_of(line(x, t, x, t + f)));
            }
        }
        // The arrow, walking up.
        let (mx, my) = (l + f / 2.0, t + f / 2.0);
        let path: Vec<(f64, f64)> = if u {
            vec![(mx, b - 0.2), (mx, my), (r - f / 2.0, my), (r - f / 2.0, b - 0.25)]
        } else {
            vec![(mx, b - 0.2), (mx, my), (r - 0.25, my)]
        };
        v.push(line_of(poly(&path, false)));
        let (tip, from) = (path[path.len() - 1], path[path.len() - 2]);
        let (dx, dy) = (tip.0 - from.0, tip.1 - from.1);
        let len = dx.hypot(dy).max(1e-9);
        let (ux, uy) = (dx / len, dy / len);
        let a = 0.18;
        v.push(line_of(poly(&[(tip.0 - ux * a - uy * a * 0.7, tip.1 - uy * a + ux * a * 0.7), tip, (tip.0 - ux * a + uy * a * 0.7, tip.1 - uy * a - ux * a * 0.7)], false)));
        return v;
    }
    if sym == "area" {
        // A patch shaded with fine diagonals and a thin dashed edge, light
        // enough to draw lamps over.
        let mut edge = shape(rect(-hw, -hh, w, h), Ink::None, Ink::Role("plan"), 0.8);
        edge.dash = "dash";
        // At most about sixty lines, however big the area is stretched.
        for segs in hatch(w, h, 45.0, (w.max(h) / 60.0).max(0.6)) {
            v.push(shape(segs, Ink::None, Ink::Role("prop"), 0.5));
        }
        v.push(edge);
        return v;
    }
    if has(&["bed"]) {
        // Head at the top of its footprint (north when unturned).
        v.push(body(rrect(-hw, -hh, w, h, r)));
        let pw = if w > 1.2 { w * 0.4 } else { w * 0.78 };
        let ph = h * 0.13;
        let pillows: Vec<f64> = if w > 1.2 { vec![-w * 0.22, w * 0.22] } else { vec![0.0] };
        for cx in pillows {
            v.push(body(rrect(cx - pw / 2.0, -hh + h * 0.05, pw, ph, ph * 0.35)));
        }
        v.push(line_of(line(-hw, -hh + h * 0.3, hw, -hh + h * 0.3)));
    } else if has(&["couch", "sofa", "loveseat", "armchair", "gray chair"]) {
        // Back along the top, an arm each end, cushions between.
        let back = h * 0.24;
        let arm = (w * 0.1).min(0.2).max(0.08);
        v.push(body(rrect(-hw, -hh, w, h, r)));
        v.push(line_of(line(-hw + arm, -hh + back, hw - arm, -hh + back)));
        v.push(line_of(line(-hw + arm, -hh + back, -hw + arm, hh)));
        v.push(line_of(line(hw - arm, -hh + back, hw - arm, hh)));
        let seats = ((w - 2.0 * arm) / 0.65).round().clamp(1.0, 4.0) as usize;
        let step = (w - 2.0 * arm) / seats as f64;
        for i in 1..seats {
            let x = -hw + arm + step * i as f64;
            v.push(line_of(line(x, -hh + back, x, hh)));
        }
    } else if has(&["office chair", "stool", "director"]) {
        let rr = w.min(h) / 2.0;
        v.push(body(circle(0.0, 0.0, rr * 0.8)));
        v.push(line_of(arc(0.0, 0.0, rr, 200.0, 340.0, false)));
    } else if has(&["chair"]) {
        v.push(body(rrect(-hw, -hh, w, h, r)));
        v.push(line_of(line(-hw, -hh + h * 0.22, hw, -hh + h * 0.22)));
    } else if has(&["circular", "round", "umbrella"]) {
        v.push(body(ellipse(0.0, 0.0, hw, hh)));
        if has(&["umbrella"]) {
            for k in 0..4 {
                let a = (k as f64 * 45.0f64).to_radians();
                v.push(line_of(line(-hw * a.cos(), -hh * a.sin(), hw * a.cos(), hh * a.sin())));
            }
        }
    } else if has(&["car", "truck", "bus", "van", "vehicle"]) && !has(&["cart", "card"]) {
        // Nose at the top; windscreen and rear glass as lines.
        let rr = w.min(h) * 0.25;
        v.push(body(rrect(-hw, -hh, w, h, rr)));
        let screen = if has(&["truck", "bus"]) { 0.12 } else { 0.28 };
        v.push(line_of(line(-hw + w * 0.12, -hh + h * screen, hw - w * 0.12, -hh + h * screen)));
        v.push(line_of(line(-hw + w * 0.12, -hh + h * (screen + 0.12), hw - w * 0.12, -hh + h * (screen + 0.12))));
        if !has(&["truck", "bus"]) {
            v.push(line_of(line(-hw + w * 0.14, hh - h * 0.2, hw - w * 0.14, hh - h * 0.2)));
        }
    } else if has(&["tree", "plant", "hedge", "bush", "shrub"]) && !has(&["trunk", "stump"]) {
        v.push(shape(cloud(w, h), clear(), ink.clone(), 1.2));
        if has(&["tree"]) {
            v.push(shape(circle(0.0, 0.0, w.min(h) * 0.04), ink.clone(), Ink::None, 0.0));
        }
    } else if has(&["trunk", "stump", "column", "cone"]) {
        let rr = w.min(h) / 2.0;
        v.push(body(circle(0.0, 0.0, rr)));
        if has(&["trunk", "stump"]) {
            v.push(line_of(circle(0.0, 0.0, rr * 0.55)));
        }
    } else if has(&["bathtub", "tub"]) {
        v.push(body(rrect(-hw, -hh, w, h, r)));
        v.push(line_of(rrect(-hw + w * 0.08, -hh + h * 0.12, w * 0.84, h * 0.76, h * 0.3)));
    } else if has(&["toilet"]) {
        v.push(body(rect(-hw, -hh, w, h * 0.3)));
        v.push(body(ellipse(0.0, hh * 0.3, hw * 0.8, hh * 0.65)));
    } else if has(&["sink"]) {
        v.push(body(rect(-hw, -hh, w, h)));
        v.push(line_of(ellipse(0.0, 0.0, hw * 0.65, hh * 0.6)));
    } else if has(&["stove"]) {
        v.push(body(rect(-hw, -hh, w, h)));
        for (x, y) in [(-0.25, -0.25), (0.25, -0.25), (-0.25, 0.25), (0.25, 0.25)] {
            v.push(line_of(circle(x * w, y * h, w.min(h) * 0.15)));
        }
    } else if has(&["stairs"]) {
        v.push(body(rect(-hw, -hh, w, h)));
        let steps = (h / 0.28).round().clamp(2.0, 30.0) as usize;
        for i in 1..steps {
            let y = -hh + h * i as f64 / steps as f64;
            v.push(line_of(line(-hw, y, hw, y)));
        }
        v.push(line_of(line(0.0, hh - h * 0.1, 0.0, -hh + h * 0.1)));
        v.push(line_of(poly(&[(-w * 0.12, -hh + h * 0.2), (0.0, -hh + h * 0.1), (w * 0.12, -hh + h * 0.2)], false)));
    } else if has(&["rug"]) {
        let mut s = shape(rect(-hw, -hh, w, h), Ink::None, ink.clone(), 0.9);
        s.dash = "dash";
        v.push(s);
    } else if has(&["canopy", "tent"]) {
        v.push(body(rect(-hw, -hh, w, h)));
        v.push(line_of(line(-hw, -hh, hw, hh)));
        v.push(line_of(line(-hw, hh, hw, -hh)));
    } else if has(&["fence", "speed rail", "polecat", "sidewalk"]) {
        v.push(line_of(rect(-hw, -hh, w, h)));
    } else if has(&["circle track", "circle-track"]) {
        let rr = w.min(h) / 2.0;
        for k in [rr * 0.8, rr * 0.96] {
            v.push(line_of(circle(0.0, 0.0, k)));
        }
    } else if has(&["track", "rail", "slider"]) {
        for y in [-hh * 0.7, hh * 0.7] {
            v.push(line_of(line(-hw, y, hw, y)));
        }
    } else if has(&["truss"]) {
        v.push(line_of(rect(-hw, -hh, w, h)));
        let n = (w / h.max(0.05)).round().clamp(1.0, 40.0) as usize;
        let mut zig = Vec::new();
        for i in 0..=n {
            zig.push((-hw + w * i as f64 / n as f64, if i % 2 == 0 { -hh } else { hh }));
        }
        v.push(line_of(poly(&zig, false)));
    } else if has(&["tv", "screen", "monitor"]) {
        v.push(body(rect(-hw, -hh, w, h)));
        v.push(shape(line(-hw, hh, hw, hh), Ink::None, ink.clone(), 2.0));
    } else if has(&["piano"]) {
        v.push(body(rrect(-hw, -hh, w, h, r)));
        v.push(line_of(line(-hw, hh - h * 0.18, hw, hh - h * 0.18)));
    } else if has(&["fireplace"]) {
        v.push(body(rect(-hw, -hh, w, h)));
        v.push(line_of(rect(-hw * 0.6, -hh + h * 0.35, w * 0.6, h * 0.65)));
    } else if has(&["generator", "distro", "lunch box", "gang box"]) {
        v.push(body(rect(-hw, -hh, w, h)));
        v.push(line_of(line(-hw, -hh, hw, hh)));
    } else {
        v.push(body(rrect(-hw, -hh, w, h, r)));
    }
    v
}

/// A tree or a hedge seen from above: a loose scalloped edge round its
/// footprint, as the backyard chase sheets draw them.
fn cloud(w: f64, h: f64) -> Vec<Seg> {
    let (rx, ry) = (w / 2.0 * 0.86, h / 2.0 * 0.86);
    let around = std::f64::consts::PI * (rx + ry);
    let n = ((around / 0.5).round() as usize).clamp(7, 30);
    let pt = |i: usize| {
        let a = i as f64 / n as f64 * std::f64::consts::TAU;
        (rx * a.cos(), ry * a.sin())
    };
    let first = pt(0);
    let mut segs = vec![Seg::M(first.0, first.1)];
    for i in 0..n {
        let (a, b) = (pt(i), pt(i + 1));
        // A round lobe pushed out from the chord between two points.
        let (dx, dy) = (b.0 - a.0, b.1 - a.1);
        let len = dx.hypot(dy).max(1e-9);
        let (nx, ny) = (dy / len, -dx / len);
        let mid = ((a.0 + b.0) / 2.0, (a.1 + b.1) / 2.0);
        let out = if nx * mid.0 + ny * mid.1 >= 0.0 { 1.0 } else { -1.0 };
        let k = len * 0.6 * out;
        segs.push(Seg::C(a.0 + nx * k, a.1 + ny * k, b.0 + nx * k, b.1 + ny * k, b.0, b.1));
    }
    segs.push(Seg::Z);
    segs
}

// ---------------------------------------------------------------- camera

/// A camera on a plot: a small box with its lens toward where it looks,
/// `s` metres across — a symbol, not to scale (his note, 2026-10-03).
pub fn camera(s: f64, ink: Ink) -> Vec<Shape> {
    let b = s * 0.62;
    let paper = Ink::Role("paper");
    vec![
        shape(rrect(-b * 0.75, -b / 2.0, b, b, b * 0.14), paper.clone(), ink.clone(), 1.8),
        shape(poly(&[(b * 0.25, -b * 0.28), (s * 0.55, -b * 0.45), (s * 0.55, b * 0.45), (b * 0.25, b * 0.28)], true), paper, ink, 1.8),
    ]
}

/// Its view, to scale: two thin dashed lines from the lens at the true
/// angle for its lens and sensor, out to `reach`.
pub fn view(tip: (f64, f64), rot: f64, aov: f64, reach: f64, ink: Ink) -> Vec<Shape> {
    let half = aov / 2.0;
    [rot - half, rot + half]
        .iter()
        .map(|a| {
            let r = a.to_radians();
            let mut s = shape(line(tip.0, tip.1, tip.0 + reach * r.cos(), tip.1 + reach * r.sin()), Ink::None, ink.clone(), 1.0);
            s.dash = "dash";
            s.part = "cone";
            s
        })
        .collect()
}

/// A person on a plot: their shoulders as an ellipse with a small tick
/// for the way they face.
pub fn person(w: f64, h: f64, ink: Ink) -> Vec<Shape> {
    // **A person from above, facing plainly** (his ask, 2026-10-17: improve
    // the cast icon): shoulders as a soft oval in the person's colour,
    // the head a solid disc set a little forward, and a nose pointing the
    // way they face — the one mark that still reads when the plan is small.
    // Facing is +x; `w` is chest to back, `h` across the shoulders.
    let (rx, ry) = (w.max(0.2) / 2.0, h.max(0.3) / 2.0);
    let r = (ry * 0.46).min(rx * 0.95);
    let hx = rx * 0.2;
    let soft = match &ink {
        Ink::Hex(c, _) => Ink::Hex(c.clone(), 0.28),
        other => other.clone(),
    };
    let nose = poly(&[(hx + r * 0.5, -r * 0.72), (hx + r * 2.2, 0.0), (hx + r * 0.5, r * 0.72)], true);
    vec![
        // Under the colour, paper, so the oval reads on any floor.
        shape(ellipse(0.0, 0.0, rx, ry), Ink::Role("paper"), Ink::None, 0.0),
        shape(ellipse(0.0, 0.0, rx, ry), soft, ink.clone(), 1.4),
        shape(nose, ink.clone(), ink.clone(), 0.6),
        shape(circle(hx, 0.0, r), ink, Ink::Role("paper"), 1.2),
    ]
}

/// **The sections a run of dolly track takes**: eights, then a four or a
/// two to make up the rest, rounded up to the next two feet —
/// "3 × 8' + 4'".
pub fn track_sections(metres: f64) -> String {
    let feet = (metres / super::FOOT / 2.0).ceil() * 2.0;
    let mut left = feet.max(2.0) as i64;
    let eights = left / 8;
    left -= eights * 8;
    let mut parts: Vec<String> = Vec::new();
    if eights > 0 {
        parts.push(if eights == 1 { "8'".into() } else { format!("{eights} × 8'") });
    }
    if left >= 4 {
        parts.push("4'".into());
        left -= 4;
    }
    if left > 0 {
        parts.push("2'".into());
    }
    parts.join(" + ")
}

/// **The colours a sheet uses, and what each means** (his ask, 2026-10-03:
/// *"legend needs to carry colors as well as lights"*): every category's
/// ink that something on the plan is drawn in, in a fixed order, with its
/// meaning — his words, else the category's own. The third ink has no
/// meaning until he gives it one.
pub fn colour_rows(d: &Diagram) -> Vec<(String, String, bool)> {
    let looks = looks(d);
    let used = |role: &str| -> bool {
        match role {
            "added" | "blue" | "practical" => looks.iter().any(|(_, l)| l.ink == role),
            "existing" => looks.iter().any(|(_, l)| l.ink == "ink"),
            "gripink" => d.els.iter().any(|e| !e.hidden && super::frame::is_frame(e)),
            "camink" => d.els.iter().any(|e| !e.hidden && (e.kind == Kind::Camera || e.kind == Kind::Track)),
            _ => false,
        }
    };
    let own = |role: &str| match role {
        "added" => "Film Lights",
        "practical" => "Practicals",
        "existing" => "Existing Lights",
        "gripink" => "Grip",
        "camink" => "Camera",
        _ => "",
    };
    ["added", "practical", "existing", "blue", "gripink", "camink"]
        .iter()
        .filter(|r| used(r))
        .map(|r| {
            let key = format!("colour:{r}");
            match d.legend.iter().find(|n| n.key == key) {
                Some(n) => (r.to_string(), n.name.clone(), true),
                None => (r.to_string(), own(r).to_string(), false),
            }
        })
        .collect()
}

/// **Three inks by default** (Back to Paper, his call 2026-10-04): red for
/// what we bring — film lights, frames and grip — blue for the camera and
/// its move, grey for the set and what is already there. **Practicals are
/// amber** (his calls, 2026-10-05: *"lets make them yellow"*, then *"should
/// be more amber"*), their own ink. A category he
/// has given no colour of its own (View › Colours) is drawn in its family's
/// ink. Each category keeps its own name, so Colours still sets any one of
/// them apart.
pub const THREE_INKS: &[(&str, &str)] = &[("gripink", "added"), ("existing", "plan")];

/// The role a category is drawn in when he has not coloured it: its
/// family's, or its own.
pub fn three_inks(role: &'static str) -> &'static str {
    THREE_INKS.iter().find(|(r, _)| *r == role).map(|(_, to)| *to).unwrap_or(role)
}

/// A colour's line in the legend: `colour:added`.
pub fn colour_key(s: &str) -> Option<&str> {
    s.strip_prefix("colour:").filter(|r| super::PLOT_COLOURS.contains(r))
}
