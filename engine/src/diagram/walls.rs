//! **A wall is one continuous line with corners** (his master list, section 3,
//! from Scenario tried by hand on 2026-09-30). Not a stick per stretch: one
//! piece, open or closed, any number of corners. Picked, every stretch shows
//! its length; a corner is dragged on its own and the stretches either side
//! follow; a corner can be broken open (a doorway), rounded, or taken out; a
//! stretch can be given a length.
//!
//! **How it is kept.** A wall's corners are its `points` once it has more
//! than two, or is closed, or has a rounded corner; a plain two-corner wall
//! stays `x,y → x2,y2`, the way every wall was written before — so every plan
//! already drawn reads exactly as it did. `x,y` and `x2,y2` are always kept
//! on the first and last corner, so whatever reads only those still finds the
//! wall's ends.
//!
//! **Joins are where things lie, not records.** A corner that sits on another
//! wall's corner, or on the middle of one of its stretches (a T), is joined
//! to it; when that wall moves, the corner goes with it (`carry_joins`). A
//! door works the same way (`carry_openings`). Nothing is written down that
//! could go stale.

use super::{norm_deg, seg_dist, Diagram, EditError, El, Kind, FOOT};
use crate::json::Json;

pub type P = (f64, f64);

/// Closer than this is the same spot: a corner on a corner, a corner on a
/// wall's line.
pub const TOUCH: f64 = 0.01;

fn dist(a: P, b: P) -> f64 {
    ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2)).sqrt()
}

fn lerp(a: P, b: P, t: f64) -> P {
    (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t)
}

fn mid(a: P, b: P) -> P {
    lerp(a, b, 0.5)
}

// ---------------------------------------------------------------- reading

/// Every corner, in order.
pub fn corners(e: &El) -> Vec<P> {
    if e.points.len() >= 2 {
        e.points.clone()
    } else {
        vec![(e.x, e.y), (e.x2, e.y2)]
    }
}

/// Closed on itself: the last corner runs back to the first.
pub fn closed(e: &El) -> bool {
    e.closed && corners(e).len() >= 3
}

/// How many stretches: one between each pair of corners, and one more back
/// to the start when closed.
pub fn stretch_count(e: &El) -> usize {
    let n = corners(e).len();
    if closed(e) {
        n
    } else {
        n.saturating_sub(1)
    }
}

/// Each stretch, corner to corner, straight.
pub fn stretches(e: &El) -> Vec<(P, P)> {
    let c = corners(e);
    let n = c.len();
    (0..stretch_count(e)).map(|i| (c[i], c[(i + 1) % n])).collect()
}

/// Whether a corner is rounded — only one with a stretch either side can be.
fn is_round(e: &El, i: usize, n: usize, closed: bool) -> bool {
    (closed || (i > 0 && i + 1 < n)) && e.round.contains(&i)
}

const NONE: [f64; 4] = [0.0; 4];

/// Corner `i`'s two curve handles, `[in_dx, in_dy, out_dx, out_dy]`.
pub fn handle(e: &El, i: usize) -> [f64; 4] {
    e.handles.get(i).copied().unwrap_or(NONE)
}

fn drawn(h: [f64; 4]) -> bool {
    h.iter().any(|v| v.abs() > 1e-9)
}

/// Whether any corner is smooth — the line is then drawn through its curves.
pub fn curved(e: &El) -> bool {
    e.handles.iter().any(|h| drawn(*h))
}

/// Whether stretch `i` (corner `i` to the next) bends: a handle at either end.
pub fn stretch_curved(e: &El, i: usize) -> bool {
    let n = corners(e).len().max(1);
    let (a, b) = (handle(e, i), handle(e, (i + 1) % n));
    a[2].abs() > 1e-9 || a[3].abs() > 1e-9 || b[0].abs() > 1e-9 || b[1].abs() > 1e-9
}

/// The four points of stretch `i` as a cubic curve.
pub fn stretch_cubic(e: &El, c: &[P], i: usize) -> (P, P, P, P) {
    let j = (i + 1) % c.len();
    let (a, b, ha, hb) = (c[i], c[j], handle(e, i), handle(e, j));
    (a, (a.0 + ha[2], a.1 + ha[3]), (b.0 + hb[0], b.1 + hb[1]), b)
}

pub fn cubic(p: (P, P, P, P), t: f64) -> P {
    let u = 1.0 - t;
    let (w0, w1, w2, w3) = (u * u * u, 3.0 * u * u * t, 3.0 * u * t * t, t * t * t);
    (
        w0 * p.0 .0 + w1 * p.1 .0 + w2 * p.2 .0 + w3 * p.3 .0,
        w0 * p.0 .1 + w1 * p.1 .1 + w2 * p.2 .1 + w3 * p.3 .1,
    )
}

/// A curved stretch as points close enough to draw along, the ends left out.
fn samples(p: (P, P, P, P)) -> Vec<P> {
    let len = dist(p.0, p.1) + dist(p.1, p.2) + dist(p.2, p.3);
    let n = ((len / 0.04).ceil() as usize).clamp(8, 120);
    (1..n).map(|k| cubic(p, k as f64 / n as f64)).collect()
}

/// A rounded corner is a fillet only between two straight stretches; a smooth
/// stretch beside it keeps the corner as it is.
fn rounded(e: &El, i: usize, n: usize, shut: bool) -> bool {
    if !is_round(e, i, n, shut) {
        return false;
    }
    let before = if i > 0 { i - 1 } else { n - 1 };
    !stretch_curved(e, before) && !stretch_curved(e, i)
}

/// What a line drawn as a path is made of: its corners, or — smooth or
/// closed — the curve through them.
pub fn path_points(e: &El) -> Vec<P> {
    if e.kind == Kind::Stroke && e.points.len() >= 2 && (curved(e) || closed(e)) {
        run(e)
    } else {
        e.points.iter().copied().collect()
    }
}

/// Whether a point is inside a closed run of points.
pub fn inside(pts: &[P], p: P) -> bool {
    let mut yes = false;
    let n = pts.len();
    let mut j = n.wrapping_sub(1);
    for i in 0..n {
        let (a, b) = (pts[i], pts[j]);
        if (a.1 > p.1) != (b.1 > p.1) && p.0 < (b.0 - a.0) * (p.1 - a.1) / (b.1 - a.1) + a.0 {
            yes = !yes;
        }
        j = i;
    }
    yes
}

/// A two-corner line bent by its curve, as points close enough to draw along.
pub fn bent(a: P, b: P, curve: f64) -> Vec<P> {
    if curve.abs() < 1e-6 {
        return vec![a, b];
    }
    let m = mid(a, b);
    let (dx, dy) = (b.0 - a.0, b.1 - a.1);
    let len = (dx * dx + dy * dy).sqrt().max(1e-9);
    let (nx, ny) = (-dy / len, dx / len);
    // The control point that puts the curve's middle `curve` metres out.
    let c = (m.0 + nx * curve * 2.0, m.1 + ny * curve * 2.0);
    (0..=24).map(|i| quad(a, c, b, i as f64 / 24.0)).collect()
}

fn quad(a: P, c: P, b: P, t: f64) -> P {
    let u = 1.0 - t;
    (u * u * a.0 + 2.0 * u * t * c.0 + t * t * b.0, u * u * a.1 + 2.0 * u * t * c.1 + t * t * b.1)
}

/// **The wall's centre line as drawn**: its corners, a rounded corner as a
/// curve from the middle of the stretch before it to the middle of the one
/// after, and — closed — back to where it began (the first point repeated).
pub fn run(e: &El) -> Vec<P> {
    let c = corners(e);
    let n = c.len();
    if n == 2 && !e.closed && !curved(e) {
        return bent(c[0], c[1], e.curve);
    }
    let shut = closed(e);
    let mut out: Vec<P> = Vec::new();
    let push = |out: &mut Vec<P>, p: P| {
        if out.last().map(|q| dist(*q, p) > 1e-9).unwrap_or(true) {
            out.push(p);
        }
    };
    let round_at = |out: &mut Vec<P>, before: P, at: P, after: P| {
        let (a, b) = (mid(before, at), mid(at, after));
        for k in 0..=12 {
            push(out, quad(a, at, b, k as f64 / 12.0));
        }
    };
    // A smooth stretch is the curve between its two corners, laid in after
    // the first of them.
    let between = |out: &mut Vec<P>, i: usize| {
        if stretch_curved(e, i) {
            for p in samples(stretch_cubic(e, &c, i)) {
                push(out, p);
            }
        }
    };
    if !shut {
        push(&mut out, c[0]);
        between(&mut out, 0);
        for i in 1..n.saturating_sub(1) {
            if rounded(e, i, n, false) {
                round_at(&mut out, c[i - 1], c[i], c[i + 1]);
            } else {
                push(&mut out, c[i]);
            }
            between(&mut out, i);
        }
        if n > 1 {
            push(&mut out, c[n - 1]);
        }
    } else {
        for i in 0..n {
            if rounded(e, i, n, true) {
                round_at(&mut out, c[(i + n - 1) % n], c[i], c[(i + 1) % n]);
            } else {
                push(&mut out, c[i]);
            }
            between(&mut out, i);
        }
        let first = out[0];
        out.push(first);
    }
    out
}

/// The whole length of the centre line.
pub fn length(e: &El) -> f64 {
    run(e).windows(2).map(|w| dist(w[0], w[1])).sum()
}

/// The box round its corners' middle.
pub fn centre(e: &El) -> P {
    let c = run(e);
    let (mut x1, mut y1, mut x2, mut y2) = (f64::MAX, f64::MAX, f64::MIN, f64::MIN);
    for p in &c {
        x1 = x1.min(p.0);
        y1 = y1.min(p.1);
        x2 = x2.max(p.0);
        y2 = y2.max(p.1);
    }
    ((x1 + x2) / 2.0, (y1 + y2) / 2.0)
}

/// Twice the area a closed line holds, signed: positive when its corners go
/// round clockwise on the page (y grows down), which puts the inside on
/// each stretch's right.
fn twice_area(c: &[P]) -> f64 {
    let n = c.len();
    (0..n).map(|i| c[i].0 * c[(i + 1) % n].1 - c[(i + 1) % n].0 * c[i].1).sum()
}

/// Which side of travel the room is: `1.0` the right (the side a positive
/// offset goes), `-1.0` the left. Only a closed line has an inside.
pub fn inside_side(e: &El) -> Option<f64> {
    closed(e).then(|| if twice_area(&corners(e)) >= 0.0 { 1.0 } else { -1.0 })
}

// ---------------------------------------------------------------- faces

/// The sideways normal of travel from `a` to `b`: a positive offset goes
/// this way.
fn normal(a: P, b: P) -> P {
    let (dx, dy) = (b.0 - a.0, b.1 - a.1);
    let l = (dx * dx + dy * dy).sqrt().max(1e-12);
    (-dy / l, dx / l)
}

/// How far a mitre may reach before the corner is cut square instead, as a
/// multiple of half the thickness — a very sharp corner would otherwise
/// throw a spike across the room.
const MITRE: f64 = 4.0;

/// One side of a line, offset `s * half` and joined **mitred** at every
/// point: the two offset lines meet where they cross, so a corner at any
/// angle is clean — no spike, no notch. Past the mitre limit, cut square.
/// `before` / `after`: another wall's next point beyond an open end, so two
/// walls that meet end to end are mitred into each other.
pub fn side(pts: &[P], half: f64, s: f64, ring: bool, before: Option<P>, after: Option<P>) -> Vec<P> {
    let n = pts.len();
    let mut out = Vec::with_capacity(n + 4);
    for i in 0..n {
        let prev = if i > 0 {
            Some(pts[i - 1])
        } else if ring {
            Some(pts[n - 1])
        } else {
            before
        };
        let next = if i + 1 < n {
            Some(pts[i + 1])
        } else if ring {
            Some(pts[0])
        } else {
            after
        };
        let b = pts[i];
        match (prev, next) {
            (Some(a), Some(c)) if dist(a, b) > 1e-9 && dist(b, c) > 1e-9 => {
                let (n1, n2) = (normal(a, b), normal(b, c));
                let k = 1.0 + n1.0 * n2.0 + n1.1 * n2.1;
                if k * MITRE * MITRE < 2.0 {
                    out.push((b.0 + s * half * n1.0, b.1 + s * half * n1.1));
                    out.push((b.0 + s * half * n2.0, b.1 + s * half * n2.1));
                } else {
                    let m = ((n1.0 + n2.0) / k, (n1.1 + n2.1) / k);
                    out.push((b.0 + s * half * m.0, b.1 + s * half * m.1));
                }
            }
            (Some(a), _) if dist(a, b) > 1e-9 => {
                let nn = normal(a, b);
                out.push((b.0 + s * half * nn.0, b.1 + s * half * nn.1));
            }
            (_, Some(c)) if dist(b, c) > 1e-9 => {
                let nn = normal(b, c);
                out.push((b.0 + s * half * nn.0, b.1 + s * half * nn.1));
            }
            _ => out.push(b),
        }
    }
    out
}

/// The faces of each stretch, on one side, corner to corner — mitred at the
/// corners, never cut square, so a face's length is the length a tape
/// measure would read along it.
pub fn stretch_faces(e: &El, s: f64) -> Vec<(P, P)> {
    let c = corners(e);
    let half = e.thick.max(0.0) / 2.0;
    let shut = closed(e);
    let n = c.len();
    let at = |i: usize| -> P {
        let prev = if i > 0 { Some(c[i - 1]) } else if shut { Some(c[n - 1]) } else { None };
        let next = if i + 1 < n { Some(c[i + 1]) } else if shut { Some(c[0]) } else { None };
        let b = c[i];
        match (prev, next) {
            (Some(a), Some(d)) if dist(a, b) > 1e-9 && dist(b, d) > 1e-9 => {
                let (n1, n2) = (normal(a, b), normal(b, d));
                let k = (1.0 + n1.0 * n2.0 + n1.1 * n2.1).max(1e-6);
                (b.0 + s * half * (n1.0 + n2.0) / k, b.1 + s * half * (n1.1 + n2.1) / k)
            }
            (Some(a), _) => {
                let nn = normal(a, b);
                (b.0 + s * half * nn.0, b.1 + s * half * nn.1)
            }
            (_, Some(d)) => {
                let nn = normal(b, d);
                (b.0 + s * half * nn.0, b.1 + s * half * nn.1)
            }
            _ => b,
        }
    };
    let faced: Vec<P> = (0..n).map(at).collect();
    (0..stretch_count(e)).map(|i| (faced[i], faced[(i + 1) % n])).collect()
}

/// **What a stretch measures, as the plan writes it**: a closed room's
/// stretch along its inside face — the room as a tape measures it inside —
/// and any other wall's along its centre line.
pub fn shown_length(e: &El, i: usize) -> f64 {
    match inside_side(e) {
        Some(s) => stretch_faces(e, s).get(i).map(|(a, b)| dist(*a, *b)).unwrap_or(0.0),
        None => stretches(e).get(i).map(|(a, b)| dist(*a, *b)).unwrap_or(0.0),
    }
}

// ---------------------------------------------------------------- writing

/// Put a wall's corners back, kept the way `corners` reads them: a plain
/// two-corner wall as `x,y → x2,y2`, anything more as `points`.
pub fn set_corners(e: &mut El, pts: Vec<P>) {
    if pts.len() < 2 {
        return;
    }
    if pts.len() < 3 {
        e.closed = false;
    }
    (e.x, e.y) = pts[0];
    (e.x2, e.y2) = pts[pts.len() - 1];
    // A drawn path is its points, however few.
    if e.kind == Kind::Stroke {
        e.points = pts;
        return;
    }
    if pts.len() == 2 && !e.closed && e.round.is_empty() && e.handles.is_empty() {
        e.points.clear();
    } else {
        // A bend is a two-corner wall's alone; with more corners, a curve is
        // a rounded corner.
        e.curve = 0.0;
        e.points = pts;
    }
}

/// Kept tidy after every edit and every read: ends on the first and last
/// corner, rounded corners only where there are corners to round.
pub fn settle(e: &mut El) {
    if e.kind == Kind::Stroke {
        // A drawn path may close on itself, and may be smooth.
        e.closed = e.closed && e.points.len() >= 3;
        e.round.clear();
        tidy_handles(e);
        return;
    }
    if e.kind != Kind::Wall {
        e.closed = false;
        e.round.clear();
        e.handles.clear();
        return;
    }
    let c = corners(e);
    let n = c.len();
    if n < 3 {
        e.closed = false;
    }
    let shut = e.closed;
    e.round.retain(|&i| i < n && (shut || (i > 0 && i + 1 < n)));
    e.round.sort_unstable();
    e.round.dedup();
    tidy_handles(e);
    // A smooth corner is not also rounded.
    let smooth: Vec<usize> = (0..n).filter(|&i| drawn(handle(e, i))).collect();
    e.round.retain(|i| !smooth.contains(i));
    set_corners(e, c);
}

/// One handle pair to a corner, none to a path that is all sharp, nothing
/// past an open end, and none that is absurdly far.
fn tidy_handles(e: &mut El) {
    if e.handles.is_empty() {
        return;
    }
    let n = corners(e).len();
    let shut = closed(e);
    e.handles.resize(n, NONE);
    for h in &mut e.handles {
        for v in h.iter_mut() {
            *v = v.clamp(-1.0e5, 1.0e5);
        }
    }
    if !shut && n > 0 {
        e.handles[0][0] = 0.0;
        e.handles[0][1] = 0.0;
        e.handles[n - 1][2] = 0.0;
        e.handles[n - 1][3] = 0.0;
    }
    // A wall with no smooth corner has no handles; a drawn path keeps its
    // (nought) handles, which is how it is told from a freehand line.
    if e.kind != Kind::Stroke && !e.handles.iter().any(|h| drawn(*h)) {
        e.handles.clear();
    }
}

/// A gap a Break opens: a door's width.
fn gap(d: &Diagram) -> f64 {
    if d.settings.units == "ft" {
        3.0 * FOOT
    } else {
        0.9
    }
}

/// The wall edits, each one step to take back:
///
/// - `wall_corner` `{id, corner, x, y, free?}` — one corner moved; the
///   stretches either side follow, and whatever was joined at that corner
///   comes too unless `free`.
/// - `wall_insert` `{id, stretch, x?, y?}` — a corner added in a stretch, at
///   its middle unless told; it becomes corner `stretch + 1`.
/// - `wall_extend` `{id, end: "start"|"end", x, y}` — an open wall grown on
///   from one end.
/// - `wall_break` `{id, corner, gap?}` — opened at a corner: a gap a door wide
///   (or `gap` metres) centred on it. A closed wall opens there; an open one
///   becomes two (the second is made).
/// - `wall_round` `{id, corner, round}` — a corner made a curve, or a corner
///   again.
/// - `wall_remove_corner` `{id, corner}` — a corner taken out; its two
///   stretches become one. Under two corners, the wall goes.
/// - `wall_length` `{id, stretch, length}` — a stretch given a length, as the
///   plan shows it (a closed room's inside face). Its far corner moves along
///   it: an open wall's corners beyond it ride along; a closed room's next
///   corner too, so the stretch after keeps its line.
/// - `wall_join` `{ids, gap?}` — walls that meet end to end made one, the
///   gap a Break left bridged (ends within a door's width and a bit, or `gap`
///   metres' worth); a chain that comes back to its start is closed, and one
///   open wall named alone closes on itself.
pub fn edit(d: &mut Diagram, name: &str, op: &Json) -> Result<Vec<String>, EditError> {
    let num = |k: &str| op.get(k).and_then(|x| x.as_f64()).filter(|x| x.is_finite());
    let index = |k: &str| num(k).map(|v| v.max(0.0) as usize);
    if name == "wall_join" {
        let ids: Vec<String> = op
            .get("ids")
            .and_then(|x| x.as_array())
            .map(|a| a.iter().filter_map(|i| i.as_str().map(String::from)).collect())
            .unwrap_or_default();
        // Ends up to a door and a bit apart still meet: what a Break opened
        // closes again. A `gap` says how wide the break was.
        let reach = num("gap").filter(|g| *g > 0.0).unwrap_or_else(|| gap(d)) * 1.7;
        join(d, &ids, reach);
        return Ok(Vec::new());
    }
    let id = op.get("id").and_then(|x| x.as_str()).ok_or(EditError::Unreadable)?.to_string();
    if name == "path_as" {
        return as_path(d, &id, op);
    }
    // **A ruler's markers are corners too** (his ask, 2026-10-01): moved,
    // added and taken away by the same edits, each with its lock (`pins`).
    let ruler = d.get(&id).map(|e| e.kind == Kind::Measure) == Some(true);
    if ruler && !matches!(name, "wall_corner" | "wall_insert" | "wall_extend" | "wall_remove_corner" | "wall_length") {
        return Err(EditError::Unknown(name.into()));
    }
    // A drawn path takes the edits that move, add and take away points, and
    // those that make a point smooth; the rest are a wall's own.
    let path_edit = matches!(name, "wall_corner" | "wall_insert" | "wall_extend" | "wall_remove_corner" | "wall_smooth" | "wall_handle");
    let e = d
        .get(&id)
        .filter(|e| e.kind == Kind::Wall || ruler || (e.kind == Kind::Stroke && path_edit))
        .ok_or_else(|| EditError::Missing(id.clone()))?
        .clone();
    if e.locked {
        return Ok(Vec::new());
    }
    // A marker's lock: the piece named `on`, or none — a marker moved or
    // put down by hand is free unless the edit says what it is locked to.
    let on = op.get("on").and_then(|x| x.as_str()).unwrap_or("").trim().to_string();
    let mut pins = e.pins.clone();
    pins.resize(corners(&e).len(), String::new());
    let mut c = corners(&e);
    let n = c.len();
    let shut = closed(&e);
    let mut hs = e.handles.clone();
    hs.resize(n, NONE);
    let mut w = e.clone();
    let mut made = Vec::new();
    match name {
        "wall_corner" => {
            let i = index("corner").filter(|i| *i < n).ok_or(EditError::Unreadable)?;
            let (x, y) = (num("x").ok_or(EditError::Unreadable)?, num("y").ok_or(EditError::Unreadable)?);
            c[i] = (x, y);
            pins[i] = on.clone();
            set_corners(&mut w, c);
        }
        "wall_insert" => {
            let s = index("stretch").filter(|s| *s < stretch_count(&e)).ok_or(EditError::Unreadable)?;
            let (a, b) = (c[s], c[(s + 1) % n]);
            // A smooth stretch is cut where it stands: both halves keep the curve.
            let split = (num("x").is_none() && num("y").is_none() && stretch_curved(&e, s)).then(|| stretch_cubic(&e, &c, s));
            let at = match (num("x"), num("y")) {
                _ if split.is_some() => cubic(split.unwrap(), 0.5),
                (Some(x), Some(y)) => (x, y),
                // A bent wall's middle is on its bend.
                _ if n == 2 && e.curve.abs() > 1e-6 => bent(a, b, e.curve)[12],
                _ => mid(a, b),
            };
            match split {
                Some((p0, p1, p2, p3)) => {
                    let (q0, q1, q2) = (mid(p0, p1), mid(p1, p2), mid(p2, p3));
                    let (r0, r1) = (mid(q0, q1), mid(q1, q2));
                    let far = (s + 1) % n;
                    hs[s][2] = q0.0 - p0.0;
                    hs[s][3] = q0.1 - p0.1;
                    hs[far][0] = q2.0 - p3.0;
                    hs[far][1] = q2.1 - p3.1;
                    hs.insert(s + 1, [r0.0 - at.0, r0.1 - at.1, r1.0 - at.0, r1.1 - at.1]);
                }
                None => hs.insert(s + 1, NONE),
            }
            c.insert(s + 1, at);
            pins.insert(s + 1, on.clone());
            for r in w.round.iter_mut() {
                if *r > s {
                    *r += 1;
                }
            }
            set_corners(&mut w, c);
        }
        "wall_extend" => {
            if shut {
                return Ok(Vec::new());
            }
            let at = (num("x").ok_or(EditError::Unreadable)?, num("y").ok_or(EditError::Unreadable)?);
            let start = matches!(op.get("end").and_then(|x| x.as_str()), Some("start" | "0"))
                || op.get("end").and_then(|x| x.as_f64()) == Some(0.0);
            if start {
                c.insert(0, at);
                hs.insert(0, NONE);
                pins.insert(0, on.clone());
                for r in w.round.iter_mut() {
                    *r += 1;
                }
            } else {
                c.push(at);
                hs.push(NONE);
                pins.push(on.clone());
            }
            // A bend belongs to a two-corner wall: grown on, it straightens.
            w.curve = 0.0;
            set_corners(&mut w, c);
        }
        "wall_break" => {
            let i = index("corner").filter(|i| *i < n).ok_or(EditError::Unreadable)?;
            let half_gap = num("gap").filter(|g| *g > 0.0).unwrap_or_else(|| gap(d)) / 2.0;
            // Back from a corner toward a neighbour by half the gap — never
            // past most of the stretch.
            let back = |from: P, toward: P| {
                let l = dist(from, toward);
                if l < 1e-9 {
                    return from;
                }
                lerp(from, toward, (half_gap.min(l * 0.8)) / l)
            };
            if shut {
                // Opened at corner i: one open line from just past it, round
                // the room, to just before it.
                let mut pts = vec![back(c[i], c[(i + 1) % n])];
                for k in 1..n {
                    pts.push(c[(i + k) % n]);
                }
                pts.push(back(c[i], c[(i + n - 1) % n]));
                let mut nh = vec![NONE];
                nh.extend((1..n).map(|k| hs[(i + k) % n]));
                nh.push(NONE);
                hs = nh;
                let rounds: Vec<usize> = w.round.iter().filter(|&&r| r != i).map(|&r| (r + n - i) % n).collect();
                w.closed = false;
                w.round = rounds;
                set_corners(&mut w, pts);
            } else {
                if i == 0 || i + 1 >= n {
                    return Ok(Vec::new());
                }
                let first: Vec<P> = c[..i].iter().copied().chain([back(c[i], c[i - 1])]).collect();
                let second: Vec<P> = [back(c[i], c[i + 1])].into_iter().chain(c[i + 1..].iter().copied()).collect();
                let mut other = e.clone();
                other.id = d.fresh_id(Kind::Wall);
                other.round = w.round.iter().filter(|&&r| r > i).map(|&r| r - i).collect();
                other.points.clear();
                other.handles = std::iter::once(NONE).chain(hs[i + 1..].iter().copied()).collect();
                hs.truncate(i);
                hs.push(NONE);
                set_corners(&mut other, second);
                w.round.retain(|&r| r < i);
                set_corners(&mut w, first);
                made.push(other.id.clone());
                let at = d.els.iter().position(|x| x.id == id).map(|p| p + 1).unwrap_or(d.els.len());
                d.els.insert(at, other);
            }
        }
        "wall_round" => {
            let i = index("corner").filter(|i| *i < n).ok_or(EditError::Unreadable)?;
            let on = op.get("round").and_then(|x| x.as_bool()).unwrap_or(true);
            w.round.retain(|&r| r != i);
            if on {
                w.round.push(i);
                hs[i] = NONE;
            }
            w.handles = hs.clone();
            settle(&mut w);
        }
        "wall_remove_corner" => {
            let i = index("corner").filter(|i| *i < n).ok_or(EditError::Unreadable)?;
            if n <= 2 {
                d.els.retain(|x| x.id != id);
                return Ok(Vec::new());
            }
            c.remove(i);
            hs.remove(i);
            pins.remove(i);
            w.round = w.round.iter().filter(|&&r| r != i).map(|&r| if r > i { r - 1 } else { r }).collect();
            if c.len() < 3 {
                w.closed = false;
            }
            set_corners(&mut w, c);
        }
        "wall_length" => {
            let s = index("stretch").filter(|s| *s < stretch_count(&e)).ok_or(EditError::Unreadable)?;
            let want = num("length").filter(|l| *l > 0.01).ok_or(EditError::Unreadable)?;
            let (a, b) = (c[s], c[(s + 1) % n]);
            let now = dist(a, b);
            if now < 1e-9 {
                return Ok(Vec::new());
            }
            // What the plan shows for it may be its inside face: the
            // difference stays the same as the stretch moves along its line.
            let centre_want = want + (now - shown_length(&e, s));
            let k = (centre_want - now) / now;
            let delta = ((b.0 - a.0) * k, (b.1 - a.1) * k);
            let mut shift = |j: usize| c[j] = (c[j].0 + delta.0, c[j].1 + delta.1);
            if shut {
                let far = (s + 1) % n;
                let next = (s + 2) % n;
                shift(far);
                if next != s {
                    shift(next);
                }
            } else {
                for j in s + 1..n {
                    shift(j);
                }
            }
            set_corners(&mut w, c);
        }
        // A corner made smooth, its handles worked out from its neighbours, or
        // made sharp again.
        "wall_smooth" => {
            let i = index("corner").filter(|i| *i < n).ok_or(EditError::Unreadable)?;
            let on = op.get("smooth").and_then(|x| x.as_bool()).unwrap_or(true);
            hs[i] = if on { auto_handle(&c, i, shut) } else { NONE };
            if on {
                w.round.retain(|&r| r != i);
            }
        }
        // One handle dragged to a place. Smooth corners keep their two handles
        // in line, unless `free`.
        "wall_handle" => {
            let i = index("corner").filter(|i| *i < n).ok_or(EditError::Unreadable)?;
            let (x, y) = (num("x").ok_or(EditError::Unreadable)?, num("y").ok_or(EditError::Unreadable)?);
            let inward = op.get("side").and_then(|x| x.as_str()) == Some("in");
            let free = op.get("free").and_then(|x| x.as_bool()).unwrap_or(false);
            let v = (x - c[i].0, y - c[i].1);
            let h = hs[i];
            let (mine, other) = if inward { ((h[0], h[1]), (h[2], h[3])) } else { ((h[2], h[3]), (h[0], h[1])) };
            let (lm, lo) = (mine.0.hypot(mine.1), other.0.hypot(other.1));
            let linked = !free && lm > 1e-9 && lo > 1e-9 && (mine.0 * other.1 - mine.1 * other.0).abs() < 0.03 * lm * lo && mine.0 * other.0 + mine.1 * other.1 < 0.0;
            let lv = v.0.hypot(v.1);
            let opposite = if linked && lv > 1e-9 { (-v.0 / lv * lo, -v.1 / lv * lo) } else { other };
            hs[i] = if inward { [v.0, v.1, opposite.0, opposite.1] } else { [opposite.0, opposite.1, v.0, v.1] };
        }
        other => return Err(EditError::Unknown(other.into())),
    }
    if ruler {
        w.pins = if pins.iter().any(|p| !p.is_empty()) { pins } else { Vec::new() };
    } else {
        w.handles = hs;
    }
    settle(&mut w);
    if let Some(slot) = d.get_mut(&id) {
        *slot = w;
    }
    Ok(made)
}

/// Walls that meet end to end, made one. The first keeps its id, colour and
/// thickness; a chain that comes back to its start closes.
/// The handles a corner is given when it is made smooth: along the line from
/// the corner before it to the corner after, a third of the way to each.
fn auto_handle(c: &[P], i: usize, shut: bool) -> [f64; 4] {
    let n = c.len();
    let prev = if i > 0 { Some(c[i - 1]) } else if shut { Some(c[n - 1]) } else { None };
    let next = if i + 1 < n { Some(c[i + 1]) } else if shut { Some(c[0]) } else { None };
    let at = c[i];
    let (from, to) = (prev.unwrap_or(at), next.unwrap_or(at));
    let dir = (to.0 - from.0, to.1 - from.1);
    let len = dir.0.hypot(dir.1);
    if len < 1e-9 {
        return NONE;
    }
    let t = (dir.0 / len, dir.1 / len);
    let (lin, lout) = (dist(from, at) / 3.0, dist(at, to) / 3.0);
    [-t.0 * lin, -t.1 * lin, t.0 * lout, t.1 * lout]
}

/// **A path made a wall, an object or a line** (`path_as`): the same points and
/// curves, drawn another way. A wall has a thickness and takes doors; an
/// object is a closed shape, filled; a line is only its outline.
fn as_path(d: &mut Diagram, id: &str, op: &Json) -> Result<Vec<String>, EditError> {
    let what = op.get("as").and_then(|x| x.as_str()).ok_or(EditError::Unreadable)?;
    let units_ft = d.settings.units == "ft";
    let e = d.get_mut(id).filter(|e| matches!(e.kind, Kind::Wall | Kind::Stroke)).ok_or_else(|| EditError::Missing(id.to_string()))?;
    if e.locked {
        return Ok(Vec::new());
    }
    let c = corners(e);
    match what {
        "wall" => {
            if e.kind != Kind::Wall {
                // A filled shape made a wall keeps its fill, as a floor.
                if e.fill && closed(e) && e.fill_color.is_empty() {
                    e.fill_color = "auto".into();
                }
                e.kind = Kind::Wall;
                e.thick = if units_ft { 0.5 * FOOT } else { super::WALL };
                e.fill = false;
                e.label.clear();
                e.weight = 1.0;
            }
        }
        "object" | "line" => {
            if e.kind == Kind::Wall {
                e.kind = Kind::Stroke;
                e.thick = 0.0;
                e.points = c.clone();
                e.weight = 2.0;
            }
            // A path, not a freehand line: its corners are exact.
            if e.handles.is_empty() {
                e.handles = vec![NONE; corners(e).len()];
            }
            e.fill = what == "object" && closed(e);
            if what == "line" {
                e.fill_color.clear();
            }
        }
        _ => return Err(EditError::Unreadable),
    }
    settle(e);
    Ok(Vec::new())
}

/// Where two ends a gap apart would meet if each ran on: the corner a Break
/// took out. `a` is the end of a wall coming from `a_from`, `b` the end of
/// another coming from `b_from`. None if they run side by side (a break in
/// the middle of a straight wall) or the meeting is not just beyond both.
fn meet(a_from: P, a: P, b_from: P, b: P, reach: f64) -> Option<P> {
    let (da, db) = ((a.0 - a_from.0, a.1 - a_from.1), (b.0 - b_from.0, b.1 - b_from.1));
    let cross = da.0 * db.1 - da.1 * db.0;
    let (la, lb) = (da.0.hypot(da.1), db.0.hypot(db.1));
    if la < 1e-9 || lb < 1e-9 || cross.abs() < 0.1 * la * lb {
        return None;
    }
    // a + s·da = b + t·db
    let (ex, ey) = (b.0 - a.0, b.1 - a.1);
    let s = (ex * db.1 - ey * db.0) / cross;
    let t = (ex * da.1 - ey * da.0) / cross;
    if s < 0.0 || t < 0.0 {
        return None;
    }
    let x = (a.0 + s * da.0, a.1 + s * da.1);
    (dist(x, a) <= reach && dist(x, b) <= reach).then_some(x)
}

/// Walls that meet end to end made one, ends within `reach` bridged — what
/// `wall_join` does, for a room laid from a scan.
pub fn join_walls(d: &mut Diagram, ids: &[String], reach: f64) {
    join(d, ids, reach);
}

fn join(d: &mut Diagram, ids: &[String], reach: f64) {
    let mut pool: Vec<El> = d
        .els
        .iter()
        .filter(|e| e.kind == Kind::Wall && ids.contains(&e.id) && !closed(e) && !e.locked)
        .cloned()
        .collect();
    // A wall's handles, one pair to a corner, laid the way its corners are.
    let handles_of = |w: &El| -> Vec<[f64; 4]> {
        let mut h = w.handles.clone();
        h.resize(corners(w).len(), NONE);
        h
    };
    while let Some(first) = (!pool.is_empty()).then(|| pool.remove(0)) {
        let mut line = corners(&first);
        let mut hl = handles_of(&first);
        let mut rounds: Vec<P> = first.round.iter().map(|&r| line[r]).collect();
        let mut taken: Vec<String> = Vec::new();
        loop {
            let tail = *line.last().unwrap();
            let head = line[0];
            // The nearest pair of ends within reach: walls that touch win
            // outright, and a gap a Break left is bridged.
            let mut best: Option<(usize, bool, bool, f64)> = None;
            for (k, w) in pool.iter().enumerate() {
                let c = corners(w);
                for (w_end, w_at) in [(false, c[0]), (true, c[c.len() - 1])] {
                    for (to_tail, at) in [(true, tail), (false, head)] {
                        let g = dist(w_at, at);
                        if g <= reach && best.map_or(true, |b| g < b.3) {
                            best = Some((k, w_end, to_tail, g));
                        }
                    }
                }
            }
            let Some((k, w_end, to_tail, gap)) = best else { break };
            let w = pool.remove(k);
            let mut c = corners(&w);
            let mut ch = handles_of(&w);
            rounds.extend(w.round.iter().map(|&r| c[r]));
            // Laid the other way round, a wall's in and out handles change places.
            let flip = |c: &mut Vec<P>, ch: &mut Vec<[f64; 4]>| {
                c.reverse();
                ch.reverse();
                for h in ch.iter_mut() {
                    *h = [h[2], h[3], h[0], h[1]];
                }
            };
            if to_tail {
                // `c` laid so its first corner is the one beside the line's last.
                if w_end {
                    flip(&mut c, &mut ch);
                }
                if gap < TOUCH {
                    // One corner: it comes in on the line's side and goes out on the wall's.
                    let n = hl.len();
                    hl[n - 1][2] = ch[0][2];
                    hl[n - 1][3] = ch[0][3];
                    c.remove(0);
                    ch.remove(0);
                } else if line.len() >= 2 && c.len() >= 2 {
                    if let Some(x) = meet(line[line.len() - 2], tail, c[1], c[0], reach) {
                        line.pop();
                        hl.pop();
                        c[0] = x;
                        ch[0] = NONE;
                    }
                }
                line.extend(c);
                hl.extend(ch);
            } else {
                // `c` laid so its last corner is the one beside the line's first.
                if !w_end {
                    flip(&mut c, &mut ch);
                }
                let end = c.len() - 1;
                if gap < TOUCH {
                    hl[0][0] = ch[end][0];
                    hl[0][1] = ch[end][1];
                    c.pop();
                    ch.pop();
                } else if line.len() >= 2 && c.len() >= 2 {
                    if let Some(x) = meet(c[end - 1], c[end], line[1], head, reach) {
                        line.remove(0);
                        hl.remove(0);
                        c[end] = x;
                        ch[end] = NONE;
                    }
                }
                c.extend(line.drain(..));
                ch.extend(hl.drain(..));
                line = c;
                hl = ch;
            }
            taken.push(w.id.clone());
        }
        // A wall that is the only one named closes on itself if its two ends
        // are a gap apart; so does a chain that took in every wall named.
        let whole = pool.is_empty() && (taken.is_empty() && ids.len() == 1 || !taken.is_empty());
        if taken.is_empty() && !(whole && line.len() >= 3 && dist(line[0], line[line.len() - 1]) <= reach) {
            continue;
        }
        let mut shut = false;
        let ends = dist(line[0], line[line.len() - 1]);
        if line.len() >= 4 && ends < TOUCH {
            let last = hl.len() - 1;
            hl[0][0] = hl[last][0];
            hl[0][1] = hl[last][1];
            line.pop();
            hl.pop();
            shut = true;
        } else if whole && line.len() >= 3 && ends <= reach {
            // Closing across the gap: the two ends run on to the corner a
            // Break took out, if there was one.
            let n = line.len();
            if n >= 4 {
                if let Some(x) = meet(line[n - 2], line[n - 1], line[1], line[0], reach) {
                    line.pop();
                    hl.pop();
                    line[0] = x;
                    hl[0] = NONE;
                }
            }
            shut = true;
        }
        d.els.retain(|e| !taken.contains(&e.id));
        if let Some(e) = d.get_mut(&first.id) {
            e.closed = shut;
            e.round = line
                .iter()
                .enumerate()
                .filter(|(_, p)| rounds.iter().any(|r| dist(*r, **p) < 1e-9))
                .map(|(i, _)| i)
                .collect();
            e.handles = hl;
            set_corners(e, line);
            settle(e);
        }
        // A group left with one piece is no group.
        let group = d.get(&first.id).map(|e| e.group.clone()).unwrap_or_default();
        if !group.is_empty() && d.els.iter().filter(|e| e.group == group).count() < 2 {
            for e in d.els.iter_mut().filter(|e| e.group == group) {
                e.group.clear();
                e.group_name.clear();
            }
        }
    }
}

// ---------------------------------------------------------------- joins

/// What a corner sits on.
#[derive(Clone, Debug)]
enum On {
    /// Another wall's corner.
    Corner(usize),
    /// Somewhere along another wall's stretch, this far along it.
    Stretch(usize, f64),
}

#[derive(Clone, Debug)]
struct Join {
    wall: String,
    corner: usize,
    host: String,
    on: On,
}

/// Every wall's corners as they were before an edit, and what each corner
/// was sitting on — read before the edit, used after (`carry`).
#[derive(Clone, Debug, Default)]
pub struct Before {
    walls: Vec<(String, Vec<P>, f64, bool)>,
    joins: Vec<Join>,
    openings: Vec<(String, f64, f64, f64)>,
}

pub fn before(d: &Diagram) -> Before {
    let walls: Vec<&El> = d.els.iter().filter(|e| e.kind == Kind::Wall).collect();
    let mut joins = Vec::new();
    for w in &walls {
        for (k, p) in corners(w).into_iter().enumerate() {
            for h in walls.iter().filter(|h| h.id != w.id) {
                let hc = corners(h);
                if let Some(j) = hc.iter().position(|q| dist(*q, p) < TOUCH) {
                    joins.push(Join { wall: w.id.clone(), corner: k, host: h.id.clone(), on: On::Corner(j) });
                    break;
                }
                // A bent wall's line is its bend, not a stretch: no T on it.
                if hc.len() == 2 && h.curve.abs() > 1e-6 {
                    continue;
                }
                let found = stretches(h).iter().enumerate().find_map(|(s, (a, b))| {
                    (seg_dist(p.0, p.1, *a, *b) < TOUCH).then(|| {
                        let (dx, dy) = (b.0 - a.0, b.1 - a.1);
                        let l2 = (dx * dx + dy * dy).max(1e-12);
                        (s, (((p.0 - a.0) * dx + (p.1 - a.1) * dy) / l2).clamp(0.0, 1.0))
                    })
                });
                if let Some((s, t)) = found {
                    joins.push(Join { wall: w.id.clone(), corner: k, host: h.id.clone(), on: On::Stretch(s, t) });
                    break;
                }
            }
        }
    }
    Before {
        walls: walls.iter().map(|w| (w.id.clone(), corners(w), w.thick, closed(w))).collect(),
        joins,
        openings: d.els.iter().filter(|e| e.kind.is_opening()).map(|e| (e.id.clone(), e.x, e.y, e.rot)).collect(),
    }
}

/// **Joined corners go where they are joined.** After an edit: a corner
/// that sat on another wall's corner, or on the middle of one of its
/// stretches, follows that wall if the edit moved it and not the corner's
/// own wall. Then every door goes where its wall went. `free`: the edit was
/// a corner pulled loose on purpose (⌥), and nothing follows it.
pub fn carry(d: &mut Diagram, was: &Before, free: bool) {
    let then = |id: &str| was.walls.iter().find(|w| w.0 == id);
    let moved = |d: &Diagram, id: &str| -> bool {
        match (d.get(id), then(id)) {
            (Some(now), Some(old)) => corners(now) != old.1 || closed(now) != old.3,
            _ => false,
        }
    };
    // Moved by the edit itself — left exactly where the edit put it.
    let edited: Vec<String> = was.walls.iter().filter(|w| moved(d, &w.0)).map(|w| w.0.clone()).collect();
    if !free {
        let mut carried: Vec<(String, usize)> = Vec::new();
        for _ in 0..4 {
            let mut any = false;
            for j in &was.joins {
                if edited.contains(&j.wall) || carried.iter().any(|c| c.0 == j.wall && c.1 == j.corner) {
                    continue;
                }
                if !moved(d, &j.host) {
                    continue;
                }
                let (Some(host), Some(old)) = (d.get(&j.host), then(&j.host)) else { continue };
                let hc = corners(host);
                let to = if hc.len() == old.1.len() {
                    match j.on {
                        On::Corner(k) => hc[k],
                        On::Stretch(s, t) => match stretches(host).get(s) {
                            Some((a, b)) => lerp(*a, *b, t),
                            None => continue,
                        },
                    }
                } else {
                    // A corner added or taken out of the wall it sits on:
                    // still on it, stays; otherwise to the nearest of it.
                    let Some(me) = d.get(&j.wall) else { continue };
                    let p = corners(me)[j.corner.min(corners(me).len() - 1)];
                    match nearest_on(host, p) {
                        Some((q, gap)) if gap >= TOUCH => q,
                        _ => continue,
                    }
                };
                if let Some(me) = d.get_mut(&j.wall) {
                    let mut c = corners(me);
                    if j.corner < c.len() && dist(c[j.corner], to) > 1e-9 {
                        c[j.corner] = to;
                        set_corners(me, c);
                        any = true;
                    }
                }
                carried.push((j.wall.clone(), j.corner));
            }
            if !any {
                break;
            }
        }
    }
    carry_openings(d, was);
}

/// The nearest point to `p` on a wall's centre line, and how far.
pub fn nearest_on(e: &El, p: P) -> Option<(P, f64)> {
    let r = run(e);
    let mut best: Option<(P, f64)> = None;
    for w in r.windows(2) {
        let (a, b) = (w[0], w[1]);
        let (dx, dy) = (b.0 - a.0, b.1 - a.1);
        let l2 = dx * dx + dy * dy;
        let t = if l2 < 1e-12 { 0.0 } else { (((p.0 - a.0) * dx + (p.1 - a.1) * dy) / l2).clamp(0.0, 1.0) };
        let q = lerp(a, b, t);
        let g = dist(p, q);
        if best.map(|b| g < b.1).unwrap_or(true) {
            best = Some((q, g));
        }
    }
    best
}

/// **A door goes where its wall goes.** Every opening that sat in a stretch
/// of a wall the edit changed — and that the edit did not move itself:
/// the stretch moved whole, the door moves with it; the stretch only grew
/// or shrank along its own line, the door stays where it is; the stretch
/// swung round, the door keeps its place along it, and turns with it. A
/// corner added or taken away: the door stays in the wall, at the nearest
/// spot of it. Nothing records which wall holds a door: lying on its line is
/// what holding is, here as on paper.
fn carry_openings(d: &mut Diagram, was: &Before) {
    let mut moves: Vec<(String, f64, f64, f64)> = Vec::new();
    for (oid, ox, oy, orot) in &was.openings {
        let Some(o) = d.get(oid) else { continue };
        // Moved by the edit itself — a drag of the wall and its door together.
        if (o.x, o.y, o.rot) != (*ox, *oy, *orot) {
            continue;
        }
        let p = (*ox, *oy);
        // The wall and stretch it was in.
        let held = was.walls.iter().find_map(|(wid, c, thick, shut)| {
            let n = c.len();
            let count = if *shut { n } else { n.saturating_sub(1) };
            (0..count).find_map(|s| {
                let (a, b) = (c[s], c[(s + 1) % n]);
                (seg_dist(p.0, p.1, a, b) <= thick / 2.0 + 0.02).then(|| (wid.clone(), c.clone(), s, a, b))
            })
        });
        let Some((wid, old, s, a, b)) = held else { continue };
        let Some(now) = d.get(&wid).filter(|e| e.kind == Kind::Wall) else { continue };
        let nc = corners(now);
        if nc == old {
            continue;
        }
        if nc.len() != old.len() {
            if let Some((q, gap)) = nearest_on(now, p) {
                if gap > TOUCH {
                    moves.push((oid.clone(), q.0, q.1, *orot));
                }
            }
            continue;
        }
        let Some(&(na, nb)) = stretches(now).get(s) else { continue };
        let (da, db) = ((na.0 - a.0, na.1 - a.1), (nb.0 - b.0, nb.1 - b.1));
        let (dx, dy) = (b.0 - a.0, b.1 - a.1);
        let len2 = (dx * dx + dy * dy).max(1e-12);
        let t = (((p.0 - a.0) * dx + (p.1 - a.1) * dy) / len2).clamp(0.0, 1.0);
        if dist(da, db) < 1e-9 {
            if da.0.abs() + da.1.abs() > 1e-12 {
                moves.push((oid.clone(), p.0 + da.0, p.1 + da.1, *orot));
            }
            continue;
        }
        let (ndx, ndy) = (nb.0 - na.0, nb.1 - na.1);
        let nlen2 = (ndx * ndx + ndy * ndy).max(1e-12);
        let same_way = (dx * ndy - dy * ndx).abs() / (len2.sqrt() * nlen2.sqrt()) < 1e-6 && dx * ndx + dy * ndy > 0.0;
        if same_way && seg_dist(p.0, p.1, na, nb) < 1e-6 {
            // Only grew or shrank along its line: it stays.
            continue;
        }
        let turn = ndy.atan2(ndx).to_degrees() - dy.atan2(dx).to_degrees();
        let q = lerp(na, nb, t);
        moves.push((oid.clone(), q.0, q.1, norm_deg(orot + turn)));
    }
    for (id, x, y, rot) in moves {
        if let Some(e) = d.els.iter_mut().find(|e| e.id == id) {
            (e.x, e.y, e.rot) = (x, y, rot);
        }
    }
}

// ---------------------------------------------------------------- snapping

/// Where a corner being drawn or dragged lands, and the guide lines that say
/// why. `x`/`y` are where the hand is; `guides` are lines on the plan.
#[derive(Clone, Debug, PartialEq)]
pub struct Snapped {
    pub at: P,
    /// Caught on a corner or a wall's line, rather than the grid.
    pub caught: bool,
    pub guides: Vec<(P, P)>,
}

/// **Where a corner wants to be**, in order:
///
/// 1. on another corner within reach — a room closes exactly;
/// 2. on a wall's line within reach — a T, dead on the line;
/// 3. **lined up square with another corner** across or down from it — with
///    its own neighbours first among them — each way on its own, a guide
///    drawn to the corner it lines up with;
/// 4. the grid, each way not lined up.
///
/// `own`: the wall and corner being dragged — that corner is not a target,
/// nor the two stretches that run from it. `skip`: whole walls left out.
pub fn snap(d: &Diagram, x: f64, y: f64, reach: f64, step: f64, skip: &[String], own: Option<(&str, usize)>) -> Snapped {
    let p = (x, y);
    let walls: Vec<&El> = d.els.iter().filter(|e| e.kind == Kind::Wall && !e.hidden && !skip.contains(&e.id)).collect();
    // Every corner a point may land on or line up with.
    let mut targets: Vec<P> = Vec::new();
    for w in &walls {
        for (k, q) in corners(w).into_iter().enumerate() {
            if own.map(|(id, i)| id == w.id && i == k).unwrap_or(false) {
                continue;
            }
            targets.push(q);
        }
    }
    // **Everything else joins too** (his ask, 2026-10-04: "how lines connect
    // with anything ... smooth and properly drawn and not janky"): the ends
    // and straight runs of every other line — a road, track, ruler, arrow,
    // cable, a drawn line — and the corners, side middles and sides of every
    // box: a set piece, a building, a shape.
    // Caught when landed on, never lined up with: a chair's corner must not
    // pull a wall across the room.
    let mut ends: Vec<P> = Vec::new();
    let mut sides: Vec<(P, P)> = Vec::new();
    //
    // **Only with Snap on** (his report, 2026-10-06: measuring from a table's
    // edge, "with snap off there's nothing I can do to get it to unsnap"): Snap
    // off is the plain hand, so a point lands where it is put and nothing but
    // a wall's own corners and lines pulls it.
    for o in d.els.iter().filter(|o| d.settings.snap && !o.hidden && o.kind != Kind::Wall && !skip.contains(&o.id)) {
        if o.kind.is_line() || matches!(o.kind, Kind::Stroke | Kind::Cable) {
            let pts: Vec<P> = if o.points.len() >= 2 { o.points.clone() } else { vec![(o.x, o.y), (o.x2, o.y2)] };
            if let (Some(a), Some(b)) = (pts.first(), pts.last()) {
                ends.push(*a);
                ends.push(*b);
            }
            if o.curve.abs() < 1e-6 {
                sides.extend(pts.windows(2).map(|w| (w[0], w[1])));
            }
        } else if matches!(o.kind, Kind::Set | Kind::Shape) && o.w > 1e-6 && o.h > 1e-6 {
            let r = o.rot.to_radians();
            let at = |lx: f64, ly: f64| (o.x + lx * r.cos() - ly * r.sin(), o.y + lx * r.sin() + ly * r.cos());
            let (hw, hh) = (o.w / 2.0, o.h / 2.0);
            let box_corners = [at(-hw, -hh), at(hw, -hh), at(hw, hh), at(-hw, hh)];
            for i in 0..4 {
                let (a, b) = (box_corners[i], box_corners[(i + 1) % 4]);
                ends.push(a);
                ends.push(((a.0 + b.0) / 2.0, (a.1 + b.1) / 2.0));
                sides.push((a, b));
            }
        }
    }
    // 1. a corner
    if let Some(q) = targets.iter().chain(ends.iter()).filter(|q| dist(**q, p) <= reach).min_by(|a, b| dist(**a, p).total_cmp(&dist(**b, p))) {
        return Snapped { at: *q, caught: true, guides: Vec::new() };
    }
    // 2. a wall's line
    let mut best: Option<(P, f64)> = None;
    for w in &walls {
        let c = corners(w);
        let n = c.len();
        for (s, (a, b)) in stretches(w).into_iter().enumerate() {
            if let Some((id, i)) = own {
                // A corner being added past the end (`i` = the corner count)
                // never lands back on the stretch it grows from.
                let mine = if i >= n { s + 2 == n } else { s == i || (s + 1) % n == i };
                if id == w.id && mine {
                    continue;
                }
            }
            if n == 2 && w.curve.abs() > 1e-6 {
                continue;
            }
            let (dx, dy) = (b.0 - a.0, b.1 - a.1);
            let l2 = dx * dx + dy * dy;
            if l2 < 1e-12 {
                continue;
            }
            let t = ((p.0 - a.0) * dx + (p.1 - a.1) * dy) / l2;
            if !(0.0..=1.0).contains(&t) {
                continue;
            }
            let g = dist(p, lerp(a, b, t));
            // Dead on the line, and with Snap on still on the grid along it:
            // a level or upright stretch keeps the grid's other way, any
            // other is stepped from its first corner.
            let mut q = lerp(a, b, t);
            if d.settings.snap && step > 1e-6 {
                let l = l2.sqrt();
                if dx.abs() < 1e-9 {
                    q.1 = ((p.1 / step).round() * step).clamp(a.1.min(b.1), a.1.max(b.1));
                } else if dy.abs() < 1e-9 {
                    q.0 = ((p.0 / step).round() * step).clamp(a.0.min(b.0), a.0.max(b.0));
                } else {
                    q = lerp(a, b, (((t * l) / step).round() * step / l).clamp(0.0, 1.0));
                }
            }
            if g <= reach && best.map(|b| g < b.1).unwrap_or(true) {
                best = Some((q, g));
            }
        }
    }
    // …and onto any other line's run or any box's side.
    for (a, b) in &sides {
        let (dx, dy) = (b.0 - a.0, b.1 - a.1);
        let l2 = dx * dx + dy * dy;
        if l2 < 1e-12 {
            continue;
        }
        let t = ((p.0 - a.0) * dx + (p.1 - a.1) * dy) / l2;
        if !(0.0..=1.0).contains(&t) {
            continue;
        }
        let q = lerp(*a, *b, t);
        let g = dist(p, q);
        if g <= reach && best.map(|b| g < b.1).unwrap_or(true) {
            best = Some((q, g));
        }
    }
    if let Some((q, _)) = best {
        return Snapped { at: q, caught: true, guides: Vec::new() };
    }
    // 3. lined up with a corner, each way; 4. the grid otherwise.
    let grid = |v: f64| if d.settings.snap && step > 1e-6 { (v / step).round() * step } else { v };
    let near = |x_way: bool| -> Option<P> {
        targets
            .iter()
            .filter(|q| (if x_way { q.0 - p.0 } else { q.1 - p.1 }).abs() <= reach)
            .min_by(|a, b| {
                let ga = if x_way { (a.0 - p.0).abs() } else { (a.1 - p.1).abs() };
                let gb = if x_way { (b.0 - p.0).abs() } else { (b.1 - p.1).abs() };
                ga.total_cmp(&gb).then(dist(**a, p).total_cmp(&dist(**b, p)))
            })
            .copied()
    };
    let (ax, ay) = (near(true), near(false));
    let at = (ax.map(|q| q.0).unwrap_or_else(|| grid(x)), ay.map(|q| q.1).unwrap_or_else(|| grid(y)));
    let mut guides = Vec::new();
    if let Some(q) = ax {
        guides.push((q, at));
    }
    if let Some(q) = ay {
        guides.push((q, at));
    }
    Snapped { at, caught: false, guides }
}

// ---------------------------------------------------------------- openings

/// Where an opening sits in a wall: its middle on the stretch's line, the
/// stretch's way, the wall's thickness — and how far its near edge is from
/// the nearer corner (to that corner's face, where another stretch meets it),
/// with the two points that distance runs between.
#[derive(Clone, Debug, PartialEq)]
pub struct InWall {
    pub x: f64,
    pub y: f64,
    pub rot: f64,
    pub thick: f64,
    pub wall: String,
    pub stretch: usize,
    pub from: f64,
    pub face: P,
    pub edge: P,
}

/// An opening `w` wide near `(x, y)`, onto the nearest wall within reach —
/// slid along it so its distance from the nearer corner is a whole number of
/// `step`s (none: where it was put).
pub fn in_wall(d: &Diagram, x: f64, y: f64, reach: f64, w: f64, step: f64) -> Option<InWall> {
    let p = (x, y);
    let mut best: Option<(InWall, f64)> = None;
    for e in d.els.iter().filter(|e| e.kind == Kind::Wall && !e.hidden) {
        let c = corners(e);
        let n = c.len();
        let shut = closed(e);
        let curved = n == 2 && e.curve.abs() > 1e-6;
        let half = e.thick / 2.0;
        // A bent wall slides along its bend's little straight pieces.
        let pieces: Vec<(usize, P, P)> = if curved {
            run(e).windows(2).map(|w| (0, w[0], w[1])).collect()
        } else {
            stretches(e).into_iter().enumerate().map(|(s, (a, b))| (s, a, b)).collect()
        };
        for (s, a, b) in pieces {
            let g = seg_dist(x, y, a, b);
            if g > reach + half {
                continue;
            }
            let l = dist(a, b);
            if l < 1e-9 {
                continue;
            }
            let dir = ((b.0 - a.0) / l, (b.1 - a.1) / l);
            let mut u = ((p.0 - a.0) * dir.0 + (p.1 - a.1) * dir.1).clamp(0.0, l);
            // The face of whatever meets each end of the stretch: its own
            // next stretch, or another wall's end there.
            let meets = |q: P, inner: bool| -> f64 {
                if inner {
                    return half;
                }
                d.els
                    .iter()
                    .filter(|o| o.kind == Kind::Wall && o.id != e.id && !o.hidden)
                    .filter(|o| corners(o).iter().any(|k| dist(*k, q) < TOUCH) || nearest_on(o, q).map(|(_, g)| g < TOUCH).unwrap_or(false))
                    .map(|o| o.thick / 2.0)
                    .fold(0.0, f64::max)
            };
            let (off_a, off_b) = if curved {
                (0.0, 0.0)
            } else {
                (meets(a, shut || s > 0), meets(b, shut || s + 2 < n))
            };
            let from_a = |u: f64| u - w / 2.0 - off_a;
            let from_b = |u: f64| l - u - w / 2.0 - off_b;
            let near_a = from_a(u) <= from_b(u);
            if step > 1e-6 && !curved {
                if near_a {
                    let k = (from_a(u) / step).round().max(0.0) * step;
                    u = k + w / 2.0 + off_a;
                } else {
                    let k = (from_b(u) / step).round().max(0.0) * step;
                    u = l - (k + w / 2.0 + off_b);
                }
                u = u.clamp(0.0, l);
            }
            let at = (a.0 + dir.0 * u, a.1 + dir.1 * u);
            let (from, face, edge) = if near_a {
                (from_a(u), (a.0 + dir.0 * off_a, a.1 + dir.1 * off_a), (a.0 + dir.0 * (u - w / 2.0), a.1 + dir.1 * (u - w / 2.0)))
            } else {
                (from_b(u), (b.0 - dir.0 * off_b, b.1 - dir.1 * off_b), (a.0 + dir.0 * (u + w / 2.0), a.1 + dir.1 * (u + w / 2.0)))
            };
            let found = InWall {
                x: at.0,
                y: at.1,
                rot: norm_deg(dir.1.atan2(dir.0).to_degrees()),
                thick: e.thick,
                wall: e.id.clone(),
                stretch: s,
                from,
                face,
                edge,
            };
            if best.as_ref().map(|b| g < b.1).unwrap_or(true) {
                best = Some((found, g));
            }
        }
    }
    best.map(|b| b.0)
}
