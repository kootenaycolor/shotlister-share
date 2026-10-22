//! **Walls stop light.** His note of 2026-09-27: *"walls should intersect
//! light fall off from lamps."*
//!
//! A lamp's beam or glow is cut to what the lamp can see: a visibility
//! polygon, cast from where the light leaves the lamp against every wall's
//! line. Light passes where a wall is not solid —
//!
//! - a **window** and an **opening** let it through;
//! - a **door** lets it through when it is drawn open (any swing), because
//!   the plan draws a door open; one swung shut (swing 0) stops it.
//!
//! Everything else in a wall stops it. Set pieces, people and cameras do not:
//! a plan is not a render, and a sofa does not throw a shadow on paper.
//! **Grip does** (2026-09-28): a frame, flag or board in the beam cuts it,
//! dims it or softens it, by what it is made of (`frame.rs`; `trace`).
//!
//! Kept cheap — rays only toward the corners that matter and a fine sweep for
//! the round edge — so a plan of hundreds of things still draws in well under
//! a millisecond.

use super::{render::line_points, seg_dist, Diagram, El, Kind};

/// A stretch of wall that stops light.
pub type Blocker = ((f64, f64), (f64, f64));

/// Every stretch of wall on the plan that light cannot pass: each wall's line,
/// with the windows, openings and open doors lying on it cut out.
pub fn blockers(d: &Diagram) -> Vec<Blocker> {
    let passes: Vec<&El> = d
        .els
        .iter()
        .filter(|e| !e.hidden)
        .filter(|e| match e.kind {
            Kind::Window | Kind::Opening => true,
            Kind::Door => e.swing > 0.5,
            _ => false,
        })
        .collect();
    let mut out = Vec::new();
    for w in d.els.iter().filter(|e| e.kind == Kind::Wall && !e.hidden) {
        let pts = line_points(w);
        for pair in pts.windows(2) {
            let (a, b) = (pair[0], pair[1]);
            let (dx, dy) = (b.0 - a.0, b.1 - a.1);
            let len = (dx * dx + dy * dy).sqrt();
            if len < 1e-6 {
                continue;
            }
            // The gaps along this stretch, in metres from `a`.
            let mut gaps: Vec<(f64, f64)> = passes
                .iter()
                .filter(|o| seg_dist(o.x, o.y, a, b) <= w.thick / 2.0 + 0.05)
                .map(|o| {
                    let t = ((o.x - a.0) * dx + (o.y - a.1) * dy) / len;
                    (t - o.w / 2.0, t + o.w / 2.0)
                })
                .collect();
            gaps.sort_by(|p, q| p.0.partial_cmp(&q.0).unwrap_or(std::cmp::Ordering::Equal));
            let mut from = 0.0;
            let at = |t: f64| (a.0 + dx / len * t, a.1 + dy / len * t);
            for (g0, g1) in gaps {
                if g0 > from + 1e-6 {
                    out.push((at(from), at(g0.min(len))));
                }
                from = from.max(g1);
                if from >= len {
                    break;
                }
            }
            if from < len - 1e-6 {
                out.push((at(from), at(len)));
            }
        }
    }
    out
}

/// What a light at `src` sees between two headings (degrees clockwise from
/// east), out to `reach`: the outline of the lit ground, or `None` when no
/// wall comes near — then the lamp's own round shape is drawn as it always
/// was. A full turn (`a1 - a0 >= 360`) is a glow; the outline then goes all
/// the way round the source, otherwise it starts and ends at the source.
pub fn lit(src: (f64, f64), a0: f64, a1: f64, reach: f64, blockers: &[Blocker]) -> Option<Vec<(f64, f64)>> {
    let near: Vec<&Blocker> = blockers
        .iter()
        .filter(|(a, b)| seg_dist(src.0, src.1, *a, *b) < reach)
        .collect();
    if near.is_empty() || reach <= 0.0 {
        return None;
    }
    let full = a1 - a0 >= 359.999;
    let span = if full { 360.0 } else { a1 - a0 };
    let inside = |deg: f64| -> Option<f64> {
        // `deg`, as an offset into the span, if it falls in it.
        let off = (deg - a0).rem_euclid(360.0);
        (full || off <= span).then_some(off)
    };
    // A fine sweep for the round edge; a ray a hair either side of every
    // corner and of every place a wall crosses the edge of the reach.
    let steps = ((span / 1.5).ceil() as usize).max(2);
    let mut offs: Vec<f64> = (0..=steps).map(|i| span * i as f64 / steps as f64).collect();
    if full {
        offs.pop();
    }
    let mut toward = |p: (f64, f64)| {
        let deg = (p.1 - src.1).atan2(p.0 - src.0).to_degrees();
        for nudge in [-0.02, 0.0, 0.02] {
            if let Some(o) = inside(deg + nudge) {
                offs.push(o);
            }
        }
    };
    for (a, b) in &near {
        for p in [*a, *b] {
            if (p.0 - src.0).hypot(p.1 - src.1) < reach {
                toward(p);
            }
        }
        for p in crossings(src, reach, *a, *b) {
            toward(p);
        }
    }
    offs.sort_by(|p, q| p.partial_cmp(q).unwrap_or(std::cmp::Ordering::Equal));
    offs.dedup_by(|p, q| (*p - *q).abs() < 1e-9);
    let mut pts = Vec::with_capacity(offs.len() + 2);
    if !full {
        pts.push(src);
    }
    for o in offs {
        let r = (a0 + o).to_radians();
        let (c, s) = (r.cos(), r.sin());
        let mut t = reach;
        for (a, b) in &near {
            if let Some(hit) = ray_hits(src, (c, s), *a, *b) {
                if hit > 1e-3 && hit < t {
                    t = hit;
                }
            }
        }
        pts.push((src.0 + c * t, src.1 + s * t));
    }
    Some(pts)
}

/// **Grip in a beam** (2026-09-28): a frame, flag or board the light
/// meets. Its outline — the four sides of its footprint — and whether light
/// goes on through it (a net, a diffusion) or stops there (a solid, a
/// bounce). `tag` is the caller's own index for it.
pub struct Obstacle {
    pub edges: [Blocker; 4],
    pub passes: bool,
    pub tag: usize,
}

/// One ray of a traced beam, in the order swept: its heading (degrees and
/// unit vector), how far it runs before something stops it, and the first
/// piece of grip it passes through before that, if any — by tag and
/// distance.
#[derive(Clone, Copy, Debug)]
pub struct Ray {
    pub deg: f64,
    pub dir: (f64, f64),
    pub stop: f64,
    pub through: Option<(usize, f64)>,
}

/// A beam traced against walls **and grip**: what `lit` does, and for each
/// ray also the first net or diffusion it goes through. `None` when no grip
/// comes within reach — then `lit` draws it as it always did, and a plan
/// with no frames costs nothing new. Only the first piece a ray passes
/// through changes it; a solid or a bounce behind it still stops it.
pub fn trace(src: (f64, f64), a0: f64, a1: f64, reach: f64, walls: &[Blocker], grip: &[Obstacle]) -> Option<Vec<Ray>> {
    if reach <= 0.0 || !reach.is_finite() {
        return None;
    }
    let grip: Vec<&Obstacle> = grip
        .iter()
        .filter(|o| o.edges.iter().any(|(a, b)| seg_dist(src.0, src.1, *a, *b) < reach))
        .collect();
    if grip.is_empty() {
        return None;
    }
    let walls: Vec<&Blocker> = walls.iter().filter(|(a, b)| seg_dist(src.0, src.1, *a, *b) < reach).collect();
    let full = a1 - a0 >= 359.999;
    let span = if full { 360.0 } else { a1 - a0 };
    let inside = |deg: f64| -> Option<f64> {
        let off = (deg - a0).rem_euclid(360.0);
        (full || off <= span).then_some(off)
    };
    let steps = ((span / 1.5).ceil() as usize).max(2);
    let mut offs: Vec<f64> = (0..=steps).map(|i| span * i as f64 / steps as f64).collect();
    if full {
        offs.pop();
    }
    let mut toward = |p: (f64, f64)| {
        let deg = (p.1 - src.1).atan2(p.0 - src.0).to_degrees();
        for nudge in [-0.02, 0.0, 0.02] {
            if let Some(o) = inside(deg + nudge) {
                offs.push(o);
            }
        }
    };
    let every = walls.iter().copied().chain(grip.iter().flat_map(|o| o.edges.iter()));
    for (a, b) in every {
        for p in [*a, *b] {
            if (p.0 - src.0).hypot(p.1 - src.1) < reach {
                toward(p);
            }
        }
        for p in crossings(src, reach, *a, *b) {
            toward(p);
        }
    }
    offs.sort_by(|p, q| p.partial_cmp(q).unwrap_or(std::cmp::Ordering::Equal));
    offs.dedup_by(|p, q| (*p - *q).abs() < 1e-9);
    let mut rays = Vec::with_capacity(offs.len());
    for o in offs {
        let deg = a0 + o;
        let r = deg.to_radians();
        let dir = (r.cos(), r.sin());
        let first = |segs: &mut dyn Iterator<Item = &Blocker>, most: f64| -> f64 {
            let mut t = most;
            for (a, b) in segs {
                if let Some(hit) = ray_hits(src, dir, *a, *b) {
                    if hit > 1e-3 && hit < t {
                        t = hit;
                    }
                }
            }
            t
        };
        let mut stop = first(&mut walls.iter().copied(), reach);
        stop = first(&mut grip.iter().filter(|o| !o.passes).flat_map(|o| o.edges.iter()), stop);
        let mut through: Option<(usize, f64)> = None;
        for g in grip.iter().filter(|o| o.passes) {
            let t = first(&mut g.edges.iter(), stop);
            if t < stop && through.map(|(_, b)| t < b).unwrap_or(true) {
                through = Some((g.tag, t));
            }
        }
        rays.push(Ray { deg, dir, stop, through });
    }
    Some(rays)
}

/// A soft source: light leaving a lit stretch `a`–`b` of a frame, fanned
/// from `heading - spread/2` at `a` to `heading + spread/2` at `b`, out to
/// `reach` or the first thing that stops it. The outline, starting at `a`
/// and ending at `b`.
pub fn fan(a: (f64, f64), b: (f64, f64), heading: f64, spread: f64, reach: f64, stops: &[Blocker]) -> Vec<(f64, f64)> {
    let n = ((spread / 3.0).ceil() as usize).clamp(8, 60);
    let near: Vec<&Blocker> = stops
        .iter()
        .filter(|(p, q)| seg_dist(a.0, a.1, *p, *q) < reach + (b.0 - a.0).hypot(b.1 - a.1))
        .collect();
    let mut pts = Vec::with_capacity(n + 3);
    pts.push(a);
    for i in 0..=n {
        let u = i as f64 / n as f64;
        let o = (a.0 + (b.0 - a.0) * u, a.1 + (b.1 - a.1) * u);
        let r = (heading - spread / 2.0 + spread * u).to_radians();
        let dir = (r.cos(), r.sin());
        let mut t = reach;
        for (p, q) in &near {
            if let Some(hit) = ray_hits(o, dir, *p, *q) {
                if hit > 1e-3 && hit < t {
                    t = hit;
                }
            }
        }
        pts.push((o.0 + dir.0 * t, o.1 + dir.1 * t));
    }
    pts.push(b);
    pts
}

/// How far along a ray from `o` heading `dir` (a unit vector) it meets the
/// stretch `a`–`b`, if it does.
pub(super) fn ray_hits(o: (f64, f64), dir: (f64, f64), a: (f64, f64), b: (f64, f64)) -> Option<f64> {
    let (ex, ey) = (b.0 - a.0, b.1 - a.1);
    let den = dir.0 * ey - dir.1 * ex;
    if den.abs() < 1e-12 {
        return None;
    }
    let (wx, wy) = (a.0 - o.0, a.1 - o.1);
    let t = (wx * ey - wy * ex) / den;
    let u = (wx * dir.1 - wy * dir.0) / den;
    (t >= 0.0 && (-1e-9..=1.0 + 1e-9).contains(&u)).then_some(t)
}

/// Where a stretch crosses the circle of the light's reach.
fn crossings(c: (f64, f64), r: f64, a: (f64, f64), b: (f64, f64)) -> Vec<(f64, f64)> {
    let (dx, dy) = (b.0 - a.0, b.1 - a.1);
    let (fx, fy) = (a.0 - c.0, a.1 - c.1);
    let qa = dx * dx + dy * dy;
    if qa < 1e-12 {
        return Vec::new();
    }
    let qb = 2.0 * (fx * dx + fy * dy);
    let qc = fx * fx + fy * fy - r * r;
    let disc = qb * qb - 4.0 * qa * qc;
    if disc < 0.0 {
        return Vec::new();
    }
    let root = disc.sqrt();
    [(-qb - root) / (2.0 * qa), (-qb + root) / (2.0 * qa)]
        .into_iter()
        .filter(|t| (0.0..=1.0).contains(t))
        .map(|t| (a.0 + dx * t, a.1 + dy * t))
        .collect()
}
