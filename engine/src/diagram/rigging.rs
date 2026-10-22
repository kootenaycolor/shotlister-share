//! **Rigging, and swapping one drawing for another.**
//!
//! Scenario's rigging: a light, camera, flag or frame dropped onto a stand, a
//! track, a frame or a set piece **rides it** — its `rig_on` names the piece
//! it is on, and moving or turning that piece carries it, keeping where it
//! sits on it. Dragging the rider fully off lets go; deleting the piece it
//! rides lets go too, and never takes the rider with it (the law: never
//! destroy). Duplicating a stand duplicates its lamp, rigged to the copy.
//!
//! Nothing here is asked for by the shells. Every edit goes through
//! `diagram::apply`, which notes where everything stood (`poses`), makes the
//! edit, then calls `carry`: what the edit moved is what was moved *by hand*,
//! and whatever rides it is carried along — the way `carry_openings` takes a
//! door with its wall. A rider the edit moved itself is not carried twice:
//! a stand and its lamp dragged together are dragged, not dragged and carried.

use std::collections::{HashMap, HashSet};

use super::{fso, frame, hits, symbols, Diagram, El, Kind};

/// How near a rider's middle has to land on a piece to get on it, in metres —
/// a speed rail is six centimetres across.
const ONTO: f64 = 0.1;

/// Where each piece stood before an edit: its middle and the way it faced.
pub type Poses = HashMap<String, (f64, f64, f64)>;

pub fn poses(d: &Diagram) -> Poses {
    d.els.iter().map(|e| (e.id.clone(), pose(e))).collect()
}

/// A piece's middle and turn. A line's turn is the way it runs.
fn pose(e: &El) -> (f64, f64, f64) {
    if e.kind.is_line() {
        let (cx, cy) = e.centre();
        (cx, cy, (e.y2 - e.y).atan2(e.x2 - e.x).to_degrees())
    } else if e.kind.is_polyline() {
        let (cx, cy) = e.centre();
        (cx, cy, 0.0)
    } else {
        (e.x, e.y, e.rot)
    }
}

fn same(a: (f64, f64, f64), b: (f64, f64, f64)) -> bool {
    (a.0 - b.0).abs() < 1e-9 && (a.1 - b.1).abs() < 1e-9 && (a.2 - b.2).abs() < 1e-9
}

/// What can ride: the things that are rigged — a lamp, a camera, and the
/// grip that lives with the lamps (flags, frames).
pub fn rides(e: &El) -> bool {
    matches!(e.kind, Kind::Light | Kind::Camera)
}

/// What can be ridden: a stand, a dolly, a rail or any other set piece, a
/// track, and a frame. Not what lies on the floor or is the room itself — a
/// rug, a backdrop, a room from the pack — or every lamp in the room would
/// be riding it.
pub fn carries(e: &El) -> bool {
    match e.kind {
        Kind::Track => true,
        Kind::Set => !floor_like(&e.sym),
        Kind::Light => frame::is_frame(e),
        _ => false,
    }
}

fn floor_like(sym: &str) -> bool {
    sym.starts_with("seamless-")
        || sym.starts_with("cyc-")
        || matches!(sym, "rug" | "sidewalk" | "canopy" | "tent" | "fso-sidewalk-section" | "fso-10x10-canopy")
        || fso::find(sym).map(|a| a.group == "Rooms & Spaces").unwrap_or(false)
}

/// Whether `parent` is `e` or rides it, however many pieces up — a rig that
/// would ride itself.
fn loops(d: &Diagram, e: &str, parent: &str) -> bool {
    let mut at = parent.to_string();
    for _ in 0..=d.els.len() {
        if at == e {
            return true;
        }
        match d.get(&at) {
            Some(p) if !p.rig_on.is_empty() => at = p.rig_on.clone(),
            _ => return false,
        }
    }
    true
}

/// Still on it: any of the rider over any of the piece.
fn on(e: &El, parent: &El) -> bool {
    hits(parent, e.x, e.y, e.w.max(e.h) / 2.0 + ONTO, 1)
}

/// The piece a rider set down here gets on: the smallest one under its
/// middle — the stand, not the stage the stand is on — the topmost of equals.
fn under(d: &Diagram, e: &El) -> Option<String> {
    let area = |p: &El| if p.kind.is_line() { p.len() * p.thick.max(0.01) } else { p.w * p.h };
    let mut best: Option<(f64, usize)> = None;
    for (i, p) in d.els.iter().enumerate() {
        if p.id == e.id || p.hidden || !carries(p) || !hits(p, e.x, e.y, ONTO, 1) || loops(d, &e.id, &p.id) {
            continue;
        }
        // A camera gets on a track only when he locks it there (`ride`).
        if e.kind == Kind::Camera && is_track(p) {
            continue;
        }
        // A frame gets on a bigger frame, never the other way round.
        if rides(p) && p.w.max(p.h) < e.w.max(e.h) {
            continue;
        }
        let a = area(p);
        if best.map(|(b, _)| a <= b + 1e-9).unwrap_or(true) {
            best = Some((a, i));
        }
    }
    best.map(|(_, i)| d.els[i].id.clone())
}

/// After an edit: carry every rider whose piece the edit moved or turned,
/// then settle who rides what — a rider set down on a piece gets on, one
/// dragged fully off gets off, one whose piece has gone stands on its own.
/// `made` is what the edit added, which counts as set down.
pub fn carry(d: &mut Diagram, before: &Poses, made: &[String]) {
    let moved: HashSet<String> = d
        .els
        .iter()
        .filter(|e| made.contains(&e.id) || before.get(&e.id).map(|p| !same(*p, pose(e))).unwrap_or(true))
        .map(|e| e.id.clone())
        .collect();
    if d.els.iter().any(|e| !e.rig_on.is_empty()) {
        let mut carried: HashSet<String> = HashSet::new();
        let mut queue: Vec<String> = moved.iter().cloned().collect();
        queue.sort();
        while let Some(pid) = queue.pop() {
            let (Some(p), Some(&was)) = (d.get(&pid), before.get(&pid)) else { continue };
            let now = pose(p);
            if same(was, now) {
                continue;
            }
            let turn = now.2 - was.2;
            let (dx, dy) = (now.0 - was.0, now.1 - was.1);
            for e in d.els.iter_mut() {
                if e.rig_on != pid || moved.contains(&e.id) || carried.contains(&e.id) {
                    continue;
                }
                if turn.abs() > 1e-9 {
                    e.rotate_about(turn, was.0, was.1);
                }
                e.translate(dx, dy);
                carried.insert(e.id.clone());
                queue.push(e.id.clone());
            }
        }
    }
    settle(d, &moved);
}

/// Who rides what, made true: a rig on nothing, on itself, round in a loop
/// or on something that cannot be ridden lets go; a rider the edit set
/// down gets on what it landed on — while Snap is on, as in Scenario, so a
/// lamp can be set over a table without riding it — and one moved fully
/// off gets off.
pub fn settle(d: &mut Diagram, moved: &HashSet<String>) {
    for i in 0..d.els.len() {
        let e = &d.els[i];
        if e.rig_on.is_empty() {
            continue;
        }
        let good = rides(e)
            && e.rig_on != e.id
            && d.get(&e.rig_on).map(carries).unwrap_or(false)
            && !loops(d, &e.id, &e.rig_on);
        if !good {
            d.els[i].rig_on.clear();
        }
    }
    for i in 0..d.els.len() {
        let e = &d.els[i];
        if !moved.contains(&e.id) || !rides(e) {
            continue;
        }
        // **Locked to a track** (his ask, 2026-10-03): wherever it is put,
        // it stays on the track's line — it slides along it, never off.
        if let Some(p) = d.get(&e.rig_on).filter(|p| is_track(p)) {
            if let Some((x, y)) = on_track(p, (e.x, e.y)) {
                d.els[i].x = x;
                d.els[i].y = y;
            }
            continue;
        }
        if let Some(p) = d.get(&e.rig_on) {
            if on(e, p) {
                continue;
            }
        }
        let next = if d.settings.snap { under(d, e).unwrap_or_default() } else { String::new() };
        d.els[i].rig_on = next;
    }
}

/// These pieces, and everything riding them, however many deep.
pub fn with_riders(d: &Diagram, ids: &[String]) -> Vec<String> {
    let mut out: Vec<String> = ids.to_vec();
    loop {
        let more: Vec<String> = d
            .els
            .iter()
            .filter(|e| !e.rig_on.is_empty() && out.contains(&e.rig_on) && !out.contains(&e.id))
            .map(|e| e.id.clone())
            .collect();
        if more.is_empty() {
            return out;
        }
        out.extend(more);
    }
}

/// Copies made by a duplicate ride the copies of what their originals rode.
/// `made` is in the order the originals stand in the stack.
pub fn rerig_copies(d: &mut Diagram, targets: &[String], made: &[String]) {
    let originals: Vec<String> = d.els.iter().filter(|e| targets.contains(&e.id)).map(|e| e.id.clone()).collect();
    let map: HashMap<&str, &str> = originals.iter().map(String::as_str).zip(made.iter().map(String::as_str)).collect();
    for e in d.els.iter_mut().filter(|e| made.contains(&e.id)) {
        if let Some(to) = map.get(e.rig_on.as_str()) {
            e.rig_on = to.to_string();
        }
    }
}

/// A library entry, as a swap needs it.
struct Item {
    light: bool,
    w: f64,
    h: f64,
    beam: f64,
    reach: f64,
    kelvin: f64,
}

fn item(sym: &str) -> Option<Item> {
    if let Some(a) = fso::find(sym) {
        if matches!(a.role, "camera" | "person") {
            return None;
        }
        let (w, h) = symbols::art_size(a);
        return Some(Item { light: matches!(a.role, "light" | "fixture" | "grip"), w, h, beam: a.beam, reach: a.reach, kelvin: a.kelvin });
    }
    symbols::find(sym).map(|s| Item { light: s.light, w: s.w, h: s.h, beam: s.beam, reach: s.reach, kelvin: s.kelvin })
}

/// **Swap**: another drawing in a set piece's or a light's place. It keeps
/// where it stands and how it is turned, its name, colour, aim, beats, move,
/// gels and rig; it takes the new unit's size and, for a lamp, its beam,
/// reach and colour temperature. A lamp swapped for a sofa becomes a set
/// piece, and the other way round.
pub fn swap(d: &mut Diagram, ids: &[String], sym: &str) {
    // **A camera's body** (SL-1217): one of the pack's cameras, at its own
    // size; everything else about the camera stays.
    if let Some(a) = fso::find(sym).filter(|a| a.role == "camera") {
        let (w, h) = symbols::art_size(a);
        for e in d.els.iter_mut().filter(|e| ids.contains(&e.id) && e.kind == Kind::Camera && !e.locked) {
            e.sym = sym.to_string();
            (e.w, e.h) = (w, h);
        }
        return;
    }
    let Some(item) = item(sym) else { return };
    let kind = if item.light { Kind::Light } else { Kind::Set };
    for e in d.els.iter_mut().filter(|e| ids.contains(&e.id)) {
        if !matches!(e.kind, Kind::Set | Kind::Light) || e.locked {
            continue;
        }
        if e.kind != kind {
            let mut n = El::new(kind, &e.id);
            n.x = e.x;
            n.y = e.y;
            n.rot = e.rot;
            n.label = e.label.clone();
            n.color = e.color.clone();
            n.note = e.note.clone();
            n.group = e.group.clone();
            n.hidden = e.hidden;
            n.opacity = e.opacity;
            n.steps = e.steps.clone();
            n.lead = e.lead;
            n.beat = e.beat;
            n.gels = e.gels.clone();
            n.rig_on = e.rig_on.clone();
            if super::aims(kind) {
                n.aim = e.aim.clone();
            }
            *e = n;
        }
        e.sym = sym.to_string();
        e.w = item.w;
        e.h = item.h;
        if kind == Kind::Light {
            e.beam = item.beam;
            e.reach = item.reach;
            e.kelvin = item.kelvin;
            e.beam_on = item.beam > 0.0;
        }
    }
}

/// **Dolly track**: a laid Track, or a circle track from the library.
pub fn is_track(p: &El) -> bool {
    p.kind == Kind::Track || (p.kind == Kind::Set && p.sym.contains("circle-track"))
}

/// The point on a track's line nearest a spot: along a laid track's middle,
/// or round a circle track's rail.
pub fn on_track(p: &El, at: (f64, f64)) -> Option<(f64, f64)> {
    if p.kind == Kind::Set {
        let r = p.w.min(p.h) / 2.0 * 0.88;
        let (dx, dy) = (at.0 - p.x, at.1 - p.y);
        let len = dx.hypot(dy);
        return Some(if len < 1e-9 { (p.x + r, p.y) } else { (p.x + dx / len * r, p.y + dy / len * r) });
    }
    let pts = super::render::line_points(p);
    let mut best: Option<((f64, f64), f64)> = None;
    for w in pts.windows(2) {
        let (a, b) = (w[0], w[1]);
        let (vx, vy) = (b.0 - a.0, b.1 - a.1);
        let l2 = vx * vx + vy * vy;
        let t = if l2 < 1e-12 { 0.0 } else { (((at.0 - a.0) * vx + (at.1 - a.1) * vy) / l2).clamp(0.0, 1.0) };
        let q = (a.0 + vx * t, a.1 + vy * t);
        let dist = (q.0 - at.0).hypot(q.1 - at.1);
        if best.map(|(_, b)| dist < b).unwrap_or(true) {
            best = Some((q, dist));
        }
    }
    best.map(|(q, _)| q)
}

/// **Locks a camera to the nearest track** and puts it on the track's
/// line. Nothing happens with no track on the plan.
pub fn ride(d: &mut Diagram, id: &str) -> bool {
    let Some(cam) = d.get(id).filter(|e| rides(e)) else { return false };
    let at = (cam.x, cam.y);
    let best = d
        .els
        .iter()
        .filter(|p| p.id != id && !p.hidden && is_track(p))
        .filter_map(|p| on_track(p, at).map(|q| (p.id.clone(), q, (q.0 - at.0).hypot(q.1 - at.1))))
        .min_by(|a, b| a.2.partial_cmp(&b.2).unwrap_or(std::cmp::Ordering::Equal));
    let Some((track, q, _)) = best else { return false };
    if let Some(e) = d.els.iter_mut().find(|e| e.id == id) {
        e.rig_on = track;
        e.x = q.0;
        e.y = q.1;
    }
    true
}
