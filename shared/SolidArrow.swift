import CoreGraphics
import Foundation

/// **Toward and Away arrows as solid slabs, in perspective** (2026-10-15) —
/// step 8 of the engine's `Arrow::pieces`, written out in
/// `engine/src/arrow/solid.rs`, followed here step for step. One file for the
/// Mac and the iPhone (both compile `shared/`), so the two cannot drift; the
/// engine draws the same shape for print and the portal. **If one changes the
/// others have to.**
///
/// A Toward or Away arrow is a real solid seen through one small virtual
/// camera: Floor is a slab lying on the ground, Standing one stood up and
/// turned to face the lens. The centre line on screen is never moved — each
/// sample is lifted back along its own ray — so the two points he drags stay
/// the tail and the head on screen.
enum SolidArrow {
    /// One drawn face: its outline, and whether it is a side face (the
    /// darker tint) or the face itself.
    struct Face: Equatable {
        var points: [CGPoint]
        var side: Bool
    }

    /// Everything about one arrow that the solid needs.
    struct Arrow {
        /// The centre line and its running length — step 1 — in the drawn
        /// rectangle's own points.
        var points: [CGPoint]
        var lengths: [CGFloat]
        var rect: CGRect
        var toward: Bool
        var standing: Bool
        var strength: Double
        var thickness: Double
        var heads: Int
        var dashed: Bool
        /// Hand-set [shaft, head], fractions of the longer side at thickness 1.
        var widths: [Double]?
    }

    /// The outline of a solid arrow, against step 2's.
    static let pen: CGFloat = 0.7

    typealias V3 = SIMD3<Double>
    private static func dot(_ a: V3, _ b: V3) -> Double { (a * b).sum() }
    private static func cross(_ a: V3, _ b: V3) -> V3 {
        V3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }
    private static func size(_ a: V3) -> Double { dot(a, a).squareRoot() }
    private static func unit(_ a: V3) -> V3 { a / max(size(a), 1e-12) }

    private struct Camera {
        let cx: Double, cy: Double, f: Double
        func back(_ p: CGPoint, _ z: Double) -> V3 {
            V3((Double(p.x) - cx) * z / f, (Double(p.y) - cy) * z / f, z)
        }
        func proj(_ v: V3) -> CGPoint {
            let z = max(v.z, 0.05)
            return CGPoint(x: cx + f * v.x / z, y: cy + f * v.y / z)
        }
    }

    /// k: the far end's size as a share of the near end's.
    static func ratio(total: Double, big: Double, strength: Double) -> Double {
        let s = min(max(strength, 0.1), 1)
        let l = min(total, 0.75 * big)
        return min(max(1 / (1 + 3.2 * s * (l / big + 0.25)), 0.3), 0.8)
    }

    /// The shaft's and the head's half-widths at the near end, in points —
    /// what the two handles set.
    static func widthsPx(total: CGFloat, rect: CGRect, thickness: Double, widths: [Double]?) -> [CGFloat] {
        let big = Double(max(rect.width, rect.height)), f = thickness
        if let w = widths, w.count == 2 { return [CGFloat(w[0] * big * f), CGFloat(w[1] * big * f)] }
        let lie = max(min(Double(total), 0.75 * big), 0.10 * big)
        let head = lie * 0.17 * f * 0.62 * 1.25
        return [CGFloat(head * 0.5), CGFloat(head)]
    }

    /// up(t, p) of step 8.
    private static func up(_ t: V3, _ p: V3, standing: Bool) -> V3 {
        func flat(_ r: V3) -> V3 { r - t * dot(r, t) }
        let view = unit(-p)
        var face = flat(view)
        if size(face) < 1e-6 { face = flat(V3(0, -1, 0)) }
        face = unit(face)
        if standing { return face }
        var floor = flat(V3(0, -1, 0))
        if size(floor) < 1e-6 { return face }
        floor = unit(floor)
        let seenFloor = dot(floor, view), seenFace = dot(face, view)
        if seenFloor >= 0.3 { return floor }
        if seenFace <= 0.3 { return seenFloor >= seenFace ? floor : face }
        var lo = 0.0, hi = 1.0
        for _ in 0..<20 {
            let m = (lo + hi) / 2
            if dot(unit(floor * (1 - m) + face * m), view) >= 0.3 { hi = m } else { lo = m }
        }
        return unit(floor * (1 - hi) + face * hi)
    }

    private struct Solid {
        let cam: Camera
        let c3: [V3]
        let lam: [Double]
        let tang: [V3]
        let standing: Bool
        let sw: Double, swEnd: Double, hw: Double, slab: Double
        var startsAt: Double, endsAt: Double

        func frame(_ d: Double) -> (p: V3, up: V3, side: V3) {
            let end = c3.count - 1
            var i = end
            for j in 1..<lam.count where lam[j] >= d { i = j; break }
            let run = max(lam[i] - lam[i - 1], 1e-12)
            let u = min(max((d - lam[i - 1]) / run, 0), 1)
            let p = c3[i - 1] + (c3[i] - c3[i - 1]) * u
            let t = SolidArrow.unit(tang[i - 1] * (1 - u) + tang[i] * u)
            let upv = SolidArrow.up(t, p, standing: standing)
            return (p, upv, SolidArrow.unit(SolidArrow.cross(t, upv)))
        }

        /// The shaft's half-width at d, times `scale`: `sw` at the back,
        /// narrowing steadily to `swEnd` (the neck) where the head starts.
        func halfAt(_ d: Double, _ scale: Double) -> Double {
            if swEnd >= sw { return sw * scale }
            let u = min(max((d - startsAt) / max(endsAt - startsAt, 1e-12), 0), 1)
            return (sw + (swEnd - sw) * u) * scale
        }

        func ribbon(_ a: Double, _ b: Double, _ scale: Double) -> [(V3, V3)] {
            var ds = [a]
            ds += lam.filter { $0 > a + 1e-9 && $0 < b - 1e-9 }
            ds.append(b)
            let left = ds.map { d -> (V3, V3) in let f = frame(d); return (f.p + f.side * halfAt(d, scale), f.up) }
            let right = ds.reversed().map { d -> (V3, V3) in let f = frame(d); return (f.p - f.side * halfAt(d, scale), f.up) }
            return left + right
        }

        func tipHead() -> [(V3, V3)] {
            let f = frame(endsAt), upEnd = frame(lam[lam.count - 1]).up
            return [(f.p + f.side * hw, f.up), (c3[c3.count - 1], upEnd), (f.p - f.side * hw, f.up)]
        }

        func backHead() -> [(V3, V3)] {
            let f = frame(startsAt), upStart = frame(0).up
            return [(f.p - f.side * hw, f.up), (c3[0], upStart), (f.p + f.side * hw, f.up)]
        }
    }

    private static func solid(_ a: Arrow) -> Solid? {
        guard a.points.count >= 2, let totalG = a.lengths.last, totalG > 1 else { return nil }
        let total = Double(totalG)
        let w = Double(a.rect.width), h = Double(a.rect.height), big = max(w, h)
        let cy = a.standing
            ? a.points.map { Double($0.y) }.reduce(0, +) / Double(a.points.count)
            : Double(a.rect.minY) - 0.35 * h
        let cam = Camera(cx: Double(a.rect.minX) + w / 2, cy: cy, f: 1.0 * big)
        let k = ratio(total: total, big: big, strength: a.strength)
        let (q0, q1) = a.toward ? (k, 1.0) : (1.0, k)
        let c3 = zip(a.points, a.lengths).map { p, l in cam.back(p, 1 / (q0 + (q1 - q0) * Double(l) / total)) }
        let end = c3.count - 1
        var lam = [0.0]
        for i in 1...end { lam.append(lam[i - 1] + size(c3[i] - c3[i - 1])) }
        let tang = (0...end).map { i in unit(c3[min(i + 1, end)] - c3[max(i - 1, 0)]) }
        let px = widthsPx(total: totalG, rect: a.rect, thickness: a.thickness, widths: a.widths).map(Double.init)
        let sw = max(px[0], 0.25) / cam.f
        let least = max(0.012 * big * a.thickness.squareRoot(), 0.55 * px[1])
        let hw = max(px[1] / cam.f, least / (cam.f * q1))
        let swEnd = a.heads >= 1 ? min(sw, 0.62 * hw) : sw
        let world = lam[end]
        var tipLen = a.heads >= 1 ? hw / 0.55 : 0
        var backLen = a.heads >= 2 ? hw / 0.55 : 0
        if tipLen + backLen > 0.6 * world {
            let s = 0.6 * world / (tipLen + backLen)
            tipLen *= s; backLen *= s
        }
        var s = Solid(cam: cam, c3: c3, lam: lam, tang: tang, standing: a.standing,
                      sw: sw, swEnd: swEnd, hw: hw, slab: 0.45 * hw, startsAt: backLen, endsAt: world - tipLen)
        if a.heads >= 1 {
            let tip = cam.proj(c3[end])
            func shape(_ e: Double) -> Double {
                let f = s.frame(e)
                let n = cam.proj(f.p), b = cam.proj(f.p + f.side * hw)
                return Double(hypot(tip.x - n.x, tip.y - n.y)) / max(Double(hypot(b.x - n.x, b.y - n.y)), 1e-9)
            }
            if shape(s.endsAt) < 1.1 {
                let floor = min(s.startsAt + 0.35 * (world - s.startsAt), s.endsAt)
                if shape(floor) <= 1.1 {
                    s.endsAt = floor
                } else {
                    var lo = floor, hi = s.endsAt
                    for _ in 0..<24 {
                        let m = (lo + hi) / 2
                        if shape(m) >= 1.1 { lo = m } else { hi = m }
                    }
                    s.endsAt = lo
                }
            }
        }
        return s
    }

    /// **The faces to draw, in order** — step 8.
    static func faces(_ a: Arrow) -> [Face] {
        guard let s = solid(a) else { return [] }
        var loops: [[(V3, V3)]] = []
        if !a.dashed {
            let r = s.ribbon(s.startsAt, s.endsAt, 1)
            let half = r.count / 2
            var lp = Array(r[..<half])
            if a.heads >= 1 { lp += s.tipHead() }
            lp += r[half...]
            if a.heads >= 2 { lp += s.backHead() }
            loops.append(lp)
        } else {
            let half = 0.6 * s.sw
            let width = 2 * half
            let run = s.endsAt - s.startsAt
            var dash = width * 3, gap = width * 1.6
            if run > 0, dash > 0 {
                let count = max(((run + gap) / (dash + gap)).rounded(), 1)
                let k = run / (count * dash + (count - 1) * gap)
                dash *= k; gap *= k
            } else { dash = 0; gap = 0 }
            var d = s.startsAt
            while d < s.endsAt - 1e-9 && dash > 0 {
                let e = min(d + dash, s.endsAt)
                if e - d > 1e-9 { loops.append(s.ribbon(d, e, 0.6)) }
                d = e + gap
            }
            if a.heads >= 1 { loops.append(s.tipHead()) }
            if a.heads >= 2 { loops.append(s.backHead()) }
        }
        let drawn = loops.map { extrude($0, slab: s.slab, cam: s.cam) }
        // Far to near; equal depths keep their order, as Rust's stable sort does.
        let order = drawn.indices.sorted { drawn[$0].depth > drawn[$1].depth || (drawn[$0].depth == drawn[$1].depth && $0 < $1) }
        return order.flatMap { drawn[$0].faces }
    }

    /// For the shaft (its middle) and, with a head, the head (its wide
    /// corner): the point on the centre line and the handle's own point.
    static func handles(_ a: Arrow) -> [(centre: CGPoint, handle: CGPoint)] {
        guard let s = solid(a) else { return [] }
        var out: [(CGPoint, CGPoint)] = []
        let m = s.frame(s.startsAt)
        out.append((s.cam.proj(m.p), s.cam.proj(m.p + m.side * s.sw)))
        if a.heads >= 1 {
            let n = s.frame(s.endsAt)
            out.append((s.cam.proj(n.p), s.cam.proj(n.p + n.side * s.hw)))
        }
        return out
    }

    private static func extrude(_ lp: [(V3, V3)], slab: Double, cam: Camera) -> (depth: Double, faces: [Face]) {
        let m = lp.count
        let tops = lp.map(\.0)
        let bots = lp.map { $0.0 - $0.1 * slab }
        let centre = tops.reduce(V3(0, 0, 0), +) / Double(m)
        let upAll = unit(lp.reduce(V3(0, 0, 0)) { $0 + $1.1 })
        let topSeen = dot(upAll, -centre) > 0
        func edge(_ i: Int) -> V3 { tops[(i + 1) % m] - tops[i] }
        let seen: [Bool] = (0..<m).map { i in
            let j = (i + 1) % m
            let e = edge(i)
            if size(e) < 1e-12 { return false }
            let u = unit(lp[i].1 + lp[j].1)
            let out = unit(cross(e, u))
            let mid = (tops[i] + tops[j]) * 0.5 - u * (slab / 2)
            return dot(out, -mid) > 0
        }
        let sharpCos = cos(35.0 * Double.pi / 180)
        func sharp(_ i: Int) -> Bool {
            let a = edge((i + m - 1) % m), b = edge(i)
            if size(a) < 1e-12 || size(b) < 1e-12 { return true }
            return dot(unit(a), unit(b)) < sharpCos
        }
        let start = (0..<m).first { !seen[($0 + m - 1) % m] || sharp($0) } ?? 0
        var sides: [(Double, Face)] = []
        var run: [Int] = []
        func flush() {
            guard let last = run.last else { return }
            let at = run + [(last + 1) % m]
            var points = at.map { cam.proj(tops[$0]) }
            points += at.reversed().map { cam.proj(bots[$0]) }
            let depth = at.map { tops[$0].z }.reduce(0, +) / Double(at.count)
            sides.append((depth, Face(points: points, side: true)))
            run = []
        }
        for n in 0..<m {
            let i = (start + n) % m
            if !seen[i] { flush(); continue }
            if !run.isEmpty && sharp(i) { flush() }
            run.append(i)
        }
        flush()
        let ordered = sides.indices.sorted { sides[$0].0 > sides[$1].0 || (sides[$0].0 == sides[$1].0 && $0 < $1) }
        var out = ordered.map { sides[$0].1 }
        out.append(Face(points: (topSeen ? tops : bots).map { cam.proj($0) }, side: false))
        return (centre.z, out)
    }
}
