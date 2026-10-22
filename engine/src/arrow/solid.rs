//! **Toward and Away arrows as solid slabs, in perspective** (2026-10-15).
//!
//! His pick from `arrow-3d-options.html`: C, a slab lying on the floor, and D,
//! a slab standing up and turned to face the lens — "should be able to convey
//! perspective either way". A Toward or Away arrow is a real solid seen
//! through one small virtual camera: its sides converge, its far end shrinks,
//! its head foreshortens, and a side face shows in a darker tint.
//!
//! **The two points he drags are the projected tail and head on screen.** The
//! centre line on screen is never moved; each of its samples is given a depth
//! and lifted back along its own ray into the scene, so the solid built around
//! that 3D line projects exactly onto the line he drew.
//!
//! **This is the arithmetic the Mac and the phone port step for step**
//! (`studio/Sources/ArrowShape.swift`, `phone/Sources/Arrows.swift`). If one
//! changes the others have to.
//!
//! ```text
//! 8. Solid (depth Toward or Away). points, lengths, total as step 1;
//!    B = max(w, h).
//!    Camera: cx = w/2; F = 1.0·B; cy (the horizon) = −0.35·h — above the
//!      picture, so a floor arrow is always seen from above — for Floor; for
//!      Standing, the mean y of the points (the arrow at eye level).
//!      back(p, z) = ((p.x − cx)·z/F, (p.y − cy)·z/F, z);
//!      proj(X, Y, Z) = (cx + F·X/z, cy + F·Y/z), z = max(Z, 0.05).
//!    Depth ratio: s = strength (0.1…1); L = min(total, 0.75·B);
//!      k = clamp(1 / (1 + 3.2·s·(L/B + 0.25)), 0.3, 0.8) — the far end's
//!      size as a share of the near end's.
//!      Away: q_tail = 1, q_head = k. Toward: q_tail = k, q_head = 1.
//!    The 3D centre line: C[i] = back(points[i], 1 / (q_tail + (q_head −
//!      q_tail)·lengths[i]/total)) — 1/z runs straight along the screen,
//!      which is what perspective does. Λ[i] = running 3D length; Λ = Λ[end].
//!      T[i] = unit(C[min(i+1, end)] − C[max(i−1, 0)]).
//!    frame(d), d a 3D distance: i = the first index ≥ 1 with Λ[i] ≥ d (the
//!      last when none); u = clamp((d − Λ[i−1]) / max(Λ[i] − Λ[i−1], 1e−12),
//!      0, 1); p = C[i−1] + (C[i] − C[i−1])·u; t = unit(T[i−1]·(1−u) + T[i]·u);
//!      up = `up(t, p)`; side = unit(t × up).
//!    up(t, p): flat(r) = r − t·(r·t); view = unit(−p);
//!      face = unit(flat(view)) (flat((0,−1,0)) when that is ~0);
//!      Standing → face. Floor: floor = unit(flat((0,−1,0))) (face when ~0);
//!      the floor's up, unless the camera would see it nearly edge-on
//!      (floor·view < 0.3): then the least blend unit(floor·(1−m) + face·m)
//!      with ·view ≥ 0.3 (bisect m, 20 steps, keep the high end); when even
//!      face·view ≤ 0.3, whichever of floor and face the camera sees more of.
//!    Sizes, at the near end, in pixels: hand-set [s, hd] → shaft = s·B·f,
//!      head = hd·B·f; else lie = max(L, 0.10·B), head = lie·0.17·f·0.62·1.25,
//!      shaft = head·0.5. In the scene: sw = max(shaft, 0.25)/F;
//!      least = max(0.012·B·√f, 0.55·head);
//!      hw = max(head/F, least/(F·q_head)); sw_end = min(sw, 0.62·hw) with a head
//!      (the shaft is sw at its start, narrowing evenly to sw_end at the head); slab = 0.45·hw.
//!    Heads: tip_len = heads ≥ 1 ? hw/0.55 : 0; back_len = heads = 2 ? hw/0.55
//!      : 0; when tip_len + back_len > 0.6·Λ both are scaled to fit.
//!      starts_at = back_len; ends_at = Λ − tip_len.
//!      The head never reads as a sliver: shape(e) = |proj(C[end]) −
//!      proj(frame(e).p)| / |proj(p + side·hw) − proj(p)|; if shape(ends_at)
//!      < 1.1, floor = min(starts_at + 0.35·(Λ − starts_at), ends_at); ends_at
//!      = floor if shape(floor) ≤ 1.1, else bisect (24 steps) for the largest
//!      e in [floor, ends_at] with shape(e) ≥ 1.1.
//!    ribbon(a, b, half): ds = a, every Λ[i] strictly inside (a, b) (1e−9),
//!      b; left = frame(d).p + side·half for d in ds; right = p − side·half
//!      for d in ds reversed. Every loop vertex carries its frame's up.
//!    tip head = [n + side·hw, C[end] (up at Λ), n − side·hw], n = frame(ends_at);
//!    back head = [n − side·hw, C[0] (up at 0), n + side·hw], n = frame(starts_at).
//!    Solid: one loop: left(starts_at, ends_at, sw) + tip head (heads ≥ 1) +
//!      right + back head (heads = 2).
//!    Dashed: half = 0.6·sw; (dash, gap) = dash_rhythm(ends_at − starts_at,
//!      half); d = starts_at; while d < ends_at − 1e−9: e = min(d + dash,
//!      ends_at); if e − d > 1e−9 a loop left(d, e, half) + right; d = e + gap.
//!      Then the tip head (heads ≥ 1) and the back head (heads = 2) as loops.
//!    Each loop is extruded (`extrude`); loops are drawn far to near by the
//!      mean Z of their vertices.
//!    extrude(loop): top[i] = the vertex, bottom[i] = vertex − up·slab;
//!      the cap is the top when unit(Σ up)·(−centre) > 0, else the bottom.
//!      Edge i (i → i+1, wrapping): e = top[j] − top[i]; seen when |e| ≥ 1e−12
//!      and unit(e × unit(up_i + up_j))·(−(mid − u·slab/2)) > 0.
//!      Sharp at vertex i: either neighbouring edge ~0, or their unit
//!      directions' dot < cos 35°. Runs: start at the first i whose previous
//!      edge is unseen or which is sharp (0 when none); walk every edge from
//!      there: an unseen edge ends the run, a sharp vertex starts a new one.
//!      A run of edges a…b is one side face: proj(top[a…b+1]) then
//!      proj(bottom[b+1…a]). Side faces far to near by the mean Z of their top
//!      vertices, then the cap: proj of its loop.
//!    Fill: the cap in look.fill(), a side in look.shade(); outlines as ever,
//!      at stroke = 0.7 × step 2's.
//! ```
use super::{dash_rhythm, Arrow, ArrowDepth, ArrowStance, LEAST_DEPTH, MOST_DEPTH};

/// One drawn face of an arrow: its outline, and whether it is a side face
/// (filled in `ArrowLook::shade`) or the face itself (`ArrowLook::fill`).
#[derive(Clone, Debug, PartialEq)]
pub struct Face {
    pub points: Vec<(f64, f64)>,
    pub side: bool,
}

type V3 = [f64; 3];
fn add(a: V3, b: V3) -> V3 {
    [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
}
fn sub(a: V3, b: V3) -> V3 {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}
fn mul(a: V3, k: f64) -> V3 {
    [a[0] * k, a[1] * k, a[2] * k]
}
fn dot(a: V3, b: V3) -> f64 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}
fn cross(a: V3, b: V3) -> V3 {
    [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
}
fn size3(a: V3) -> f64 {
    dot(a, a).sqrt()
}
fn unit(a: V3) -> V3 {
    mul(a, 1.0 / size3(a).max(1e-12))
}

/// The camera's horizon, as a share of the picture's height from its top: above
/// the picture, so every floor arrow is seen from above.
pub const HORIZON: f64 = -0.35;
/// The focal length, as a multiple of the picture's longer side.
pub const FOCAL: f64 = 1.0;
/// The far end's size as a share of the near end's: never smaller, never larger.
pub const FAREST: f64 = 0.3;
pub const NEAREST: f64 = 0.8;
/// How little of a floor slab's face the camera may see before it turns up.
const LEAST_VIEW: f64 = 0.3;
/// A head is at least this many times as long, on screen, as it is half wide.
const HEAD_SHAPE: f64 = 1.1;
/// The neck (where the shaft meets the head) is at most this share of the head's
/// base, so the head always has shoulders.
const NECK: f64 = 0.62;
/// The outline of a solid arrow, against step 2's.
pub const SOLID_PEN: f64 = 0.7;

struct Camera {
    cx: f64,
    cy: f64,
    f: f64,
}

impl Camera {
    fn back(&self, p: (f64, f64), z: f64) -> V3 {
        [(p.0 - self.cx) * z / self.f, (p.1 - self.cy) * z / self.f, z]
    }
    fn proj(&self, v: V3) -> (f64, f64) {
        let z = v[2].max(0.05);
        (self.cx + self.f * v[0] / z, self.cy + self.f * v[1] / z)
    }
}

/// up(t, p) of step 8.
fn up_at(t: V3, p: V3, stance: ArrowStance) -> V3 {
    let flat = |r: V3| sub(r, mul(t, dot(r, t)));
    let view = unit(mul(p, -1.0));
    let face = flat(view);
    let face = unit(if size3(face) < 1e-6 { flat([0.0, -1.0, 0.0]) } else { face });
    if stance == ArrowStance::Standing {
        return face;
    }
    let floor = flat([0.0, -1.0, 0.0]);
    if size3(floor) < 1e-6 {
        return face;
    }
    let floor = unit(floor);
    let (seen_floor, seen_face) = (dot(floor, view), dot(face, view));
    if seen_floor >= LEAST_VIEW {
        return floor;
    }
    if seen_face <= LEAST_VIEW {
        return if seen_floor >= seen_face { floor } else { face };
    }
    let (mut lo, mut hi) = (0.0, 1.0);
    for _ in 0..20 {
        let m = (lo + hi) / 2.0;
        if dot(unit(add(mul(floor, 1.0 - m), mul(face, m))), view) >= LEAST_VIEW {
            hi = m;
        } else {
            lo = m;
        }
    }
    unit(add(mul(floor, 1.0 - hi), mul(face, hi)))
}

/// Everything step 8 works out before it draws.
struct Solid {
    cam: Camera,
    c3: Vec<V3>,
    lam: Vec<f64>,
    tang: Vec<V3>,
    stance: ArrowStance,
    sw: f64,
    /// The shaft's half-width where it meets the head: `sw`, unless the shaft
    /// is wider than the head allows (then it narrows from its middle).
    sw_end: f64,
    hw: f64,
    slab: f64,
    starts_at: f64,
    ends_at: f64,
}

impl Solid {
    /// frame(d) of step 8: the point, the up and the side.
    fn frame(&self, d: f64) -> (V3, V3, V3) {
        let end = self.c3.len() - 1;
        let mut i = end;
        for (j, l) in self.lam.iter().enumerate().skip(1) {
            if *l >= d {
                i = j;
                break;
            }
        }
        let run = (self.lam[i] - self.lam[i - 1]).max(1e-12);
        let u = ((d - self.lam[i - 1]) / run).clamp(0.0, 1.0);
        let p = add(self.c3[i - 1], mul(sub(self.c3[i], self.c3[i - 1]), u));
        let t = unit(add(mul(self.tang[i - 1], 1.0 - u), mul(self.tang[i], u)));
        let up = up_at(t, p, self.stance);
        (p, up, unit(cross(t, up)))
    }

    /// The shaft's half-width at distance d, times `scale`: `sw` at the back,
    /// narrowing steadily to `sw_end` (the neck) where the head starts.
    fn half_at(&self, d: f64, scale: f64) -> f64 {
        if self.sw_end >= self.sw {
            return self.sw * scale;
        }
        let u = ((d - self.starts_at) / (self.ends_at - self.starts_at).max(1e-12)).clamp(0.0, 1.0);
        (self.sw + (self.sw_end - self.sw) * u) * scale
    }

    fn ribbon(&self, a: f64, b: f64, scale: f64) -> (Vec<(V3, V3)>, Vec<(V3, V3)>) {
        let mut ds = vec![a];
        ds.extend(self.lam.iter().copied().filter(|l| *l > a + 1e-9 && *l < b - 1e-9));
        ds.push(b);
        let left = ds
            .iter()
            .map(|d| {
                let (p, u, s) = self.frame(*d);
                (add(p, mul(s, self.half_at(*d, scale))), u)
            })
            .collect();
        let right = ds
            .iter()
            .rev()
            .map(|d| {
                let (p, u, s) = self.frame(*d);
                (sub(p, mul(s, self.half_at(*d, scale))), u)
            })
            .collect();
        (left, right)
    }

    fn tip_head(&self) -> Vec<(V3, V3)> {
        let end = self.c3.len() - 1;
        let (p, u, s) = self.frame(self.ends_at);
        let up_end = self.frame(*self.lam.last().unwrap()).1;
        vec![(add(p, mul(s, self.hw)), u), (self.c3[end], up_end), (sub(p, mul(s, self.hw)), u)]
    }

    fn back_head(&self) -> Vec<(V3, V3)> {
        let (p, u, s) = self.frame(self.starts_at);
        let up_start = self.frame(0.0).1;
        vec![(sub(p, mul(s, self.hw)), u), (self.c3[0], up_start), (add(p, mul(s, self.hw)), u)]
    }
}

impl Arrow {
    /// k of step 8: the far end's size as a share of the near end's.
    pub fn solid_ratio(&self, total: f64, big: f64) -> f64 {
        let s = self.depth_strength.clamp(LEAST_DEPTH, MOST_DEPTH);
        let l = total.min(0.75 * big);
        (1.0 / (1.0 + 3.2 * s * (l / big + 0.25))).clamp(FAREST, NEAREST)
    }

    /// The shaft's and the head's half-widths at the near end, in pixels —
    /// what the two handles set on a Toward or Away arrow.
    pub(super) fn solid_widths_px(&self, total: f64, w: f64, h: f64) -> [f64; 2] {
        let big = w.max(h);
        let f = self.thickness;
        if let Some([s, hd]) = self.widths {
            return [s * big * f, hd * big * f];
        }
        let lie = total.min(0.75 * big).max(0.10 * big);
        let head = lie * 0.17 * f * 0.62 * 1.25;
        [head * 0.5, head]
    }

    fn solid(&self, points: &[(f64, f64)], lengths: &[f64], w: f64, h: f64) -> Solid {
        let big = w.max(h);
        let total = *lengths.last().unwrap_or(&0.0);
        let cy = if self.stance == ArrowStance::Standing {
            points.iter().map(|p| p.1).sum::<f64>() / points.len() as f64
        } else {
            HORIZON * h
        };
        let cam = Camera { cx: w / 2.0, cy, f: FOCAL * big };
        let k = self.solid_ratio(total, big);
        let (q0, q1) = if self.depth == ArrowDepth::Toward { (k, 1.0) } else { (1.0, k) };
        let c3: Vec<V3> = points
            .iter()
            .zip(lengths)
            .map(|(p, l)| cam.back(*p, 1.0 / (q0 + (q1 - q0) * l / total)))
            .collect();
        let end = c3.len() - 1;
        let mut lam = vec![0.0];
        for i in 1..=end {
            lam.push(lam[i - 1] + size3(sub(c3[i], c3[i - 1])));
        }
        let tang = (0..=end).map(|i| unit(sub(c3[(i + 1).min(end)], c3[i.saturating_sub(1)]))).collect();
        let [shaft_px, head_px] = self.solid_widths_px(total, w, h);
        let sw = shaft_px.max(0.25) / cam.f;
        let least = (0.012 * big * self.thickness.sqrt()).max(0.55 * head_px);
        // The head is what was set, however wide the shaft is (a wide tail
        // is allowed); a shaft wider than head/1.6 narrows into the head.
        let hw = (head_px / cam.f).max(least / (cam.f * q1));
        let sw_end = if self.heads >= 1 { sw.min(NECK * hw) } else { sw };
        let world = lam[end];
        let mut tip_len = if self.heads >= 1 { hw / 0.55 } else { 0.0 };
        let mut back_len = if self.heads >= 2 { hw / 0.55 } else { 0.0 };
        if tip_len + back_len > 0.6 * world {
            let s = 0.6 * world / (tip_len + back_len);
            tip_len *= s;
            back_len *= s;
        }
        let mut solid = Solid {
            cam,
            c3,
            lam,
            tang,
            stance: self.stance,
            sw,
            sw_end,
            hw,
            slab: 0.45 * hw,
            starts_at: back_len,
            ends_at: world - tip_len,
        };
        if self.heads >= 1 {
            let tip = solid.cam.proj(solid.c3[end]);
            let shape = |s: &Solid, e: f64| -> f64 {
                let (p, _, side) = s.frame(e);
                let n = s.cam.proj(p);
                let b = s.cam.proj(add(p, mul(side, s.hw)));
                (tip.0 - n.0).hypot(tip.1 - n.1) / (b.0 - n.0).hypot(b.1 - n.1).max(1e-9)
            };
            if shape(&solid, solid.ends_at) < HEAD_SHAPE {
                let floor = (solid.starts_at + 0.35 * (world - solid.starts_at)).min(solid.ends_at);
                if shape(&solid, floor) <= HEAD_SHAPE {
                    solid.ends_at = floor;
                } else {
                    let (mut lo, mut hi) = (floor, solid.ends_at);
                    for _ in 0..24 {
                        let m = (lo + hi) / 2.0;
                        if shape(&solid, m) >= HEAD_SHAPE {
                            lo = m;
                        } else {
                            hi = m;
                        }
                    }
                    solid.ends_at = lo;
                }
            }
        }
        solid
    }

    /// **Step 8: a Toward or Away arrow as solid faces**, drawn in order.
    pub(super) fn solid_faces(&self, points: &[(f64, f64)], lengths: &[f64], w: f64, h: f64) -> Vec<Face> {
        let s = self.solid(points, lengths, w, h);
        let mut loops: Vec<Vec<(V3, V3)>> = Vec::new();
        if !self.dashed {
            let (left, right) = s.ribbon(s.starts_at, s.ends_at, 1.0);
            let mut lp = left;
            if self.heads >= 1 {
                lp.extend(s.tip_head());
            }
            lp.extend(right);
            if self.heads >= 2 {
                lp.extend(s.back_head());
            }
            loops.push(lp);
        } else {
            let half = 0.6 * s.sw;
            let (dash, gap) = dash_rhythm(s.ends_at - s.starts_at, half);
            let mut d = s.starts_at;
            while d < s.ends_at - 1e-9 && dash > 0.0 {
                let e = (d + dash).min(s.ends_at);
                if e - d > 1e-9 {
                    let (left, right) = s.ribbon(d, e, 0.6);
                    let mut lp = left;
                    lp.extend(right);
                    loops.push(lp);
                }
                d = e + gap;
            }
            if self.heads >= 1 {
                loops.push(s.tip_head());
            }
            if self.heads >= 2 {
                loops.push(s.back_head());
            }
        }
        let mut drawn: Vec<(f64, Vec<Face>)> = loops.iter().map(|lp| extrude(lp, s.slab, &s.cam)).collect();
        drawn.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));
        drawn.into_iter().flat_map(|(_, f)| f).collect()
    }

    /// **Where the two width handles sit on a Toward or Away arrow**: for the
    /// shaft (at its middle) and the head (its wide corner), the point on the
    /// centre line and the handle's point, on screen.
    pub(super) fn solid_handles(&self, points: &[(f64, f64)], lengths: &[f64], w: f64, h: f64) -> Vec<[(f64, f64); 2]> {
        let s = self.solid(points, lengths, w, h);
        let mut out = Vec::new();
        // At the shaft's start: the tail corner, where the back is dragged wide.
        let (p, _, side) = s.frame(s.starts_at);
        out.push([s.cam.proj(p), s.cam.proj(add(p, mul(side, s.sw)))]);
        if self.heads >= 1 {
            let (p, _, side) = s.frame(s.ends_at);
            out.push([s.cam.proj(p), s.cam.proj(add(p, mul(side, s.hw)))]);
        }
        out
    }
}

/// extrude(loop) of step 8: the mean depth, and the faces far to near.
fn extrude(lp: &[(V3, V3)], slab: f64, cam: &Camera) -> (f64, Vec<Face>) {
    let m = lp.len();
    let tops: Vec<V3> = lp.iter().map(|v| v.0).collect();
    let bots: Vec<V3> = lp.iter().map(|v| sub(v.0, mul(v.1, slab))).collect();
    let centre = mul(tops.iter().fold([0.0; 3], |a, b| add(a, *b)), 1.0 / m as f64);
    let up_all = unit(lp.iter().fold([0.0; 3], |a, b| add(a, b.1)));
    let top_seen = dot(up_all, mul(centre, -1.0)) > 0.0;
    let edge = |i: usize| sub(tops[(i + 1) % m], tops[i]);
    let seen: Vec<bool> = (0..m)
        .map(|i| {
            let j = (i + 1) % m;
            let e = edge(i);
            if size3(e) < 1e-12 {
                return false;
            }
            let u = unit(add(lp[i].1, lp[j].1));
            let out = unit(cross(e, u));
            let mid = sub(mul(add(tops[i], tops[j]), 0.5), mul(u, slab / 2.0));
            dot(out, mul(mid, -1.0)) > 0.0
        })
        .collect();
    let sharp_cos = 35f64.to_radians().cos();
    let sharp = |i: usize| -> bool {
        let (a, b) = (edge((i + m - 1) % m), edge(i));
        if size3(a) < 1e-12 || size3(b) < 1e-12 {
            return true;
        }
        dot(unit(a), unit(b)) < sharp_cos
    };
    let start = (0..m).find(|&i| !seen[(i + m - 1) % m] || sharp(i)).unwrap_or(0);
    let mut sides: Vec<(f64, Face)> = Vec::new();
    let mut run: Vec<usize> = Vec::new();
    let flush = |run: &mut Vec<usize>, sides: &mut Vec<(f64, Face)>| {
        if run.is_empty() {
            return;
        }
        let mut at = run.clone();
        at.push((run[run.len() - 1] + 1) % m);
        let mut points: Vec<(f64, f64)> = at.iter().map(|&i| cam.proj(tops[i])).collect();
        points.extend(at.iter().rev().map(|&i| cam.proj(bots[i])));
        let depth = at.iter().map(|&i| tops[i][2]).sum::<f64>() / at.len() as f64;
        sides.push((depth, Face { points, side: true }));
        run.clear();
    };
    for n in 0..m {
        let i = (start + n) % m;
        if !seen[i] {
            flush(&mut run, &mut sides);
            continue;
        }
        if !run.is_empty() && sharp(i) {
            flush(&mut run, &mut sides);
        }
        run.push(i);
    }
    flush(&mut run, &mut sides);
    sides.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));
    let cap = if top_seen { &tops } else { &bots };
    let mut out: Vec<Face> = sides.into_iter().map(|s| s.1).collect();
    out.push(Face { points: cap.iter().map(|v| cam.proj(*v)).collect(), side: false });
    (centre[2], out)
}
