import SwiftUI

/// **Storyboard arrows, drawn on a photograph** — the marks the Mac has drawn
/// since 2026-08-31 and the phone showed bare until now (Ref 462). A board he
/// marked on the Mac reads as unmarked on set, which is exactly when he would
/// be looking at it.
///
/// **Seeing them, not drawing them.** The shape and the wire format are the
/// Mac's, copied line for line out of `studio/Sources/Arrows.swift` — one
/// rule three shells read cannot be allowed to drift. Drawing by hand on a
/// phone is a separate decision and is not here.
///
/// **Every coordinate is a fraction of the picture**, not of the tile it is
/// drawn in, so an arrow stays on the thing it was drawn on however small the
/// tile, and cropping the picture carries its arrows along for free.
///
/// The `Engine.Arrow` type itself lives in `Engine.swift`, so the decoder
/// compiles on its own for the checks.

// ------------------------------------------------------------ the shape

/// **The one place that knows what a storyboard arrow looks like.**
///
/// The proportions are the arrow's own length, not the tile's — that is what
/// makes a short arrow look like a short arrow rather than a stub with an
/// enormous head, and it is how a board is actually drawn. So the same arrow
/// on a 90-point table thumbnail and on a full-screen pop-out is the same
/// picture, larger.
enum Storyboarding {
    /// Where a fraction of the picture lands inside a drawn rectangle.
    static func at(_ p: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
    }

    /// **The centre line and its running length**, exactly the recipe in the
    /// doc comment on the engine's `Arrow::pieces` (step 1). If one changes
    /// the others have to.
    static func walk(_ arrow: Engine.Arrow, in rect: CGRect)
        -> (points: [CGPoint], lengths: [CGFloat]) {
        let p = ([arrow.tail] + arrow.pins + [arrow.head]).map { at($0, in: rect) }
        let n = p.count - 2
        var points: [CGPoint] = []
        if n == 0 || arrow.shape == .corner {
            for i in 0..<(p.count - 1) {
                for k in 0..<24 {
                    let t = CGFloat(k) / 24
                    points.append(CGPoint(x: p[i].x + (p[i + 1].x - p[i].x) * t,
                                          y: p[i].y + (p[i + 1].y - p[i].y) * t))
                }
            }
            points.append(p[p.count - 1])
        } else if n == 1 {
            let a = p[0], m = p[1], c = p[2]
            let q = CGPoint(x: 2 * m.x - (a.x + c.x) / 2, y: 2 * m.y - (a.y + c.y) / 2)
            for i in 0...40 {
                let t = CGFloat(i) / 40, u = 1 - t
                points.append(CGPoint(x: u * u * a.x + 2 * u * t * q.x + t * t * c.x,
                                      y: u * u * a.y + 2 * u * t * q.y + t * t * c.y))
            }
        } else {
            let last = p.count - 1
            for i in 0..<last {
                let p0 = p[max(i - 1, 0)], p1 = p[i], p2 = p[i + 1], p3 = p[min(i + 2, last)]
                for k in 0..<24 {
                    let t = CGFloat(k) / 24, t2 = t * t, t3 = t * t * t
                    func f(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
                        0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2
                               + (-a + 3 * b - 3 * c + d) * t3)
                    }
                    points.append(CGPoint(x: f(p0.x, p1.x, p2.x, p3.x), y: f(p0.y, p1.y, p2.y, p3.y)))
                }
            }
            points.append(p[last])
        }
        var lengths: [CGFloat] = [0]
        for i in 1..<points.count {
            lengths.append(lengths[i - 1] + hypot(points[i].x - points[i - 1].x,
                                                  points[i].y - points[i - 1].y))
        }
        return (points, lengths)
    }

    /// How long the shaft is on screen. Nought for an arrow with no length.
    static func length(_ arrow: Engine.Arrow, in rect: CGRect) -> CGFloat {
        walk(arrow, in: rect).lengths.last ?? 0
    }

    /// The outline's width — the whole reason an arrow reads over a bright
    /// photograph as well as a dark one. `Arrow::stroke`: a deep arrow's pen
    /// follows how big it lies, not how long it looks.
    static func outline(_ arrow: Engine.Arrow, in rect: CGRect) -> CGFloat {
        if arrow.zoom != nil { return zoomStroke(arrow, in: rect) }
        let big = max(rect.width, rect.height)
        let size = min(length(arrow, in: rect), 0.75 * big)
        let pen = max(size * 0.020 * CGFloat(arrow.thickness), 0.7)
        return arrow.depth == .flat ? pen : max(pen * SolidArrow.pen, 0.7)
    }

    /// The arrow as `SolidArrow` needs it — step 8, a Toward or Away arrow.
    static func solid(_ arrow: Engine.Arrow, in rect: CGRect) -> SolidArrow.Arrow {
        let (points, lengths) = walk(arrow, in: rect)
        return SolidArrow.Arrow(points: points, lengths: lengths, rect: rect,
                                toward: arrow.depth == .toward, standing: arrow.stance == .standing,
                                strength: arrow.depthStrength, thickness: arrow.thickness,
                                heads: arrow.heads, dashed: arrow.dashed, widths: arrow.widths)
    }

    /// **The faces to draw, in order** — `Arrow::faces`: a solid Toward or
    /// Away arrow's side faces (the darker tint) first, its face last.
    static func faces(_ arrow: Engine.Arrow, in rect: CGRect) -> [SolidArrow.Face] {
        if arrow.depth != .flat && arrow.zoom == nil { return SolidArrow.faces(solid(arrow, in: rect)) }
        let flat: [[CGPoint]] = arrow.zoom != nil ? (zoom(arrow, in: rect)?.arrows ?? []) : outlines(arrow, in: rect)
        return flat.map { SolidArrow.Face(points: $0, side: false) }
    }

    /// **The two widths the handles set** — `Arrow::widths_px`: the shaft's
    /// half-width (at its middle) and the head's half-width, in the drawn
    /// rectangle's points. The hand-set ones, else the depth's — where the
    /// handles sit before they are touched.
    static func widths(_ arrow: Engine.Arrow, in rect: CGRect) -> [CGFloat] {
        if arrow.depth != .flat {
            return SolidArrow.widthsPx(total: length(arrow, in: rect), rect: rect,
                                       thickness: arrow.thickness, widths: arrow.widths)
        }
        let big = max(rect.width, rect.height)
        if let w = arrow.widths, w.count == 2 {
            return w.map { CGFloat($0) * big * CGFloat(arrow.thickness) }
        }
        let d = defaultLaid(arrow, in: rect)
        return [d[1], d[3]]
    }

    /// The depth's own [wt, wm, we, wh] (step 6), before any hand-set widths.
    private static func defaultLaid(_ arrow: Engine.Arrow, in rect: CGRect) -> [CGFloat] {
        let total = length(arrow, in: rect)
        let big = max(rect.width, rect.height)
        let f = CGFloat(arrow.thickness)
        let size = min(total, 0.75 * big)
        if arrow.depth == .flat {
            let headLength = min(size * 0.17 * f, total * 0.45)
            let headHalf = headLength * 0.62, neckHalf = headHalf * 0.62
            let tailHalf = arrow.heads == 1 && !arrow.dashed ? headHalf * 0.30 : neckHalf
            return [tailHalf, (tailHalf + neckHalf) / 2, neckHalf, arrow.heads >= 1 ? headHalf : neckHalf]
        }
        let lie = max(size, 0.10 * big)
        let base = lie * 0.17 * f
        let ends = arrow.depthEnds
        let m0 = CGFloat(ends.0), m1 = CGFloat(ends.1)
        func head(_ m: CGFloat) -> CGFloat { m >= 1 ? m : (1 + m) / 2 }
        let wt = base * 0.3844 * m0
        let wh = arrow.heads >= 1 ? base * 0.62 * head(m1) : base * 0.3844 * m1
        let we = arrow.heads >= 1 ? 0.62 * wh : wh
        return [wt, (wt + we) / 2, we, wh]
    }

    /// Step 6's [wt, wm, we, wh, backHalf], floored at 0.25 — `laid_widths`.
    private static func laidWidths(_ arrow: Engine.Arrow, in rect: CGRect) -> [CGFloat] {
        let d = defaultLaid(arrow, in: rect)
        func floor(_ v: CGFloat) -> CGFloat { max(v, 0.25) }
        guard arrow.widths != nil else {
            return [floor(d[0]), floor(d[1]), floor(d[2]), floor(d[3]), floor(d[0]) / 0.62]
        }
        let hand = widths(arrow, in: rect)
        let shaft = hand[0], head = hand[1]
        let wt: CGFloat, we: CGFloat, back: CGFloat
        if arrow.depth == .flat {
            wt = shaft; we = arrow.heads >= 1 ? min(shaft, 0.62 * head) : shaft; back = head
        } else {
            let wm0 = max(d[1], 1e-9)
            wt = shaft * d[0] / wm0; we = shaft * d[2] / wm0
            back = head * (d[0] / 0.62) / max(d[3], 1e-9)
        }
        return [floor(wt), floor(arrow.depth == .flat && we < wt ? (wt + we) / 2 : shaft), floor(we), floor(head), floor(back)]
    }

    /// Step 6's lengths: where the shaft starts and ends, and the heads.
    private static func laid(_ arrow: Engine.Arrow, total: CGFloat, in rect: CGRect)
        -> (startsAt: CGFloat, endsAt: CGFloat, tipHalf: CGFloat, backHalf: CGFloat) {
        if arrow.depth == .flat && arrow.widths == nil {
            let size = min(total, 0.75 * max(rect.width, rect.height))
            let headLength = min(size * 0.17 * CGFloat(arrow.thickness), total * 0.45)
            return (arrow.heads >= 2 ? headLength : 0,
                    arrow.heads >= 1 ? total - headLength : total,
                    headLength * 0.62, headLength * 0.62)
        }
        let w = laidWidths(arrow, in: rect)
        let tipHalf = w[3], backHalf = w[4]
        var tipLength: CGFloat = arrow.heads >= 1 ? tipHalf / 0.62 : 0
        var backLength: CGFloat = arrow.heads >= 2 ? backHalf / 0.62 : 0
        let room = 0.6 * total
        if tipLength + backLength > room {
            let k = room / (tipLength + backLength)
            tipLength *= k; backLength *= k
        }
        return (backLength, total - tipLength, tipHalf, backHalf)
    }

    /// at(s) of step 5: the point `s` along the centre line, and the normal
    /// of the sample run it falls in.
    private static func along(_ points: [CGPoint], _ lengths: [CGFloat], _ s: CGFloat) -> (CGPoint, CGPoint) {
        let end = points.count - 1
        var i = end
        for k in 1..<lengths.count where lengths[k] >= s { i = k; break }
        let p = points[i - 1], q = points[i]
        let run = max(lengths[i] - lengths[i - 1], 0.0001)
        let u = min(max((s - lengths[i - 1]) / run, 0), 1)
        let dx = q.x - p.x, dy = q.y - p.y
        let len = max(hypot(dx, dy), 0.0001)
        return (CGPoint(x: p.x + dx * u, y: p.y + dy * u), CGPoint(x: -dy / len, y: dx / len))
    }

    /// normal(i) of step 3.
    private static func normal(_ points: [CGPoint], _ i: Int) -> CGPoint {
        let end = points.count - 1
        let before = points[max(i - 1, 0)], after = points[min(i + 1, end)]
        let dx = after.x - before.x, dy = after.y - before.y
        let len = max(hypot(dx, dy), 0.0001)
        return CGPoint(x: -dy / len, y: dx / len)
    }

    /// **The arrow as closed outlines** — `Arrow::pieces`. A solid arrow is
    /// one outline, so shaft and head can never show a seam; a dashed one is
    /// one per dash, then its heads. A flat arrow with no hand-set widths is
    /// steps 2 to 5, exactly as ever; a deep one or a hand-set one is step 6,
    /// the arrow laid flat on the ground.
    static func outlines(_ arrow: Engine.Arrow, in rect: CGRect) -> [[CGPoint]] {
        if arrow.depth != .flat && arrow.zoom == nil {
            return SolidArrow.faces(solid(arrow, in: rect)).map(\.points)
        }
        let (points, lengths) = walk(arrow, in: rect)
        let total = lengths.last ?? 0
        guard total > 1, points.count >= 2 else { return [] }
        let end = points.count - 1
        func step(_ distance: CGFloat) -> Int {
            for i in 0..<lengths.count where lengths[i] >= distance { return max(i, 1) }
            return end
        }
        let flatOld = arrow.depth == .flat && arrow.widths == nil
        let w = laidWidths(arrow, in: rect)
        let lay = laid(arrow, total: total, in: rect)
        let startsAt = lay.startsAt, endsAt = lay.endsAt
        guard endsAt > startsAt else { return [headOnly(points: points, half: lay.tipHalf)] }
        let first = step(startsAt), last = step(endsAt)

        // The shaft's half-width at distance d.
        let wt = w[0], wm = w[1], we = w[2]
        let mid = (startsAt + endsAt) / 2
        let knots: [(CGFloat, CGFloat)] = [(0, wt), (startsAt, wt), (mid, wm), (endsAt, we), (total, we)]
        // Steps 2–3's flat widths.
        let neckHalf = lay.tipHalf * 0.62
        let tailHalf = arrow.heads == 1 && !arrow.dashed ? lay.tipHalf * 0.30 : neckHalf
        func half(_ i: Int) -> CGFloat {
            if !flatOld { return knotWidth(knots, lengths[i]) }
            if first == last { return neckHalf }
            let along = (lengths[i] - startsAt) / max(endsAt - startsAt, 0.0001)
            return tailHalf + (neckHalf - tailHalf) * min(max(along, 0), 1)
        }
        let nIn = normal(points, first), nOut = normal(points, last)
        let tail = points[first], neck = points[last], tip = points[end]
        let tipHalf = lay.tipHalf, backHalf = lay.backHalf
        let headAtTip = [CGPoint(x: neck.x + nOut.x * tipHalf, y: neck.y + nOut.y * tipHalf),
                         tip,
                         CGPoint(x: neck.x - nOut.x * tipHalf, y: neck.y - nOut.y * tipHalf)]
        let headAtTail = [CGPoint(x: tail.x - nIn.x * backHalf, y: tail.y - nIn.y * backHalf),
                          points[0],
                          CGPoint(x: tail.x + nIn.x * backHalf, y: tail.y + nIn.y * backHalf)]

        if !arrow.dashed {
            var out: [CGPoint] = []
            for i in first...last {
                let n = normal(points, i), d = half(i)
                out.append(CGPoint(x: points[i].x + n.x * d, y: points[i].y + n.y * d))
            }
            if arrow.heads >= 1 { out += headAtTip }
            for i in stride(from: last, through: first, by: -1) {
                let n = normal(points, i), d = half(i)
                out.append(CGPoint(x: points[i].x - n.x * d, y: points[i].y - n.y * d))
            }
            if arrow.heads >= 2 { out += headAtTail }
            return [out]
        }

        // Dashed: flat, an even dash; laid, dashes that grow with the width,
        // laid out in the stretched distance τ.
        let from: CGFloat = arrow.heads >= 2 ? lengths[first] : 0
        let to: CGFloat = arrow.heads >= 1 ? lengths[last] : total
        let dashHalf = neckHalf * 0.60
        func dashWidth(_ s: CGFloat) -> CGFloat { flatOld ? dashHalf : 0.6 * knotWidth(knots, s) }
        func tau(_ d: CGFloat) -> CGFloat { flatOld ? d : stretched(knots, wm, d) }
        func untau(_ t: CGFloat) -> CGFloat { flatOld ? t : unstretched(knots, wm, t) }
        let tFrom = tau(from), tEnd = tau(to)
        let (dash, gap) = dashRhythm(tEnd - tFrom, half: flatOld ? dashHalf : 0.6 * wm)
        var out: [[CGPoint]] = []
        var t = tFrom
        while t < tEnd - 0.01 && dash > 0 {
            let u = min(t + dash, tEnd)
            let d = untau(t)
            let e = u >= tEnd ? to : untau(u)
            if e - d > 0.01 {
                let (pd, nd) = along(points, lengths, d)
                var centre: [(CGPoint, CGPoint, CGFloat)] = [(pd, nd, d)]
                for i in 0..<points.count where lengths[i] > d && lengths[i] < e {
                    centre.append((points[i], normal(points, i), lengths[i]))
                }
                let (pe, ne) = along(points, lengths, e)
                centre.append((pe, ne, e))
                var poly = centre.map { p, n, s -> CGPoint in
                    let k = dashWidth(s)
                    return CGPoint(x: p.x + n.x * k, y: p.y + n.y * k)
                }
                poly += centre.reversed().map { p, n, s -> CGPoint in
                    let k = dashWidth(s)
                    return CGPoint(x: p.x - n.x * k, y: p.y - n.y * k)
                }
                out.append(poly)
            }
            t = flatOld ? e + gap : u + gap
        }
        if arrow.heads >= 1 { out.append(headAtTip) }
        if arrow.heads >= 2 { out.append(headAtTail) }
        return out
    }

    /// W(d) of step 6: straight lines through the knots.
    private static func knotWidth(_ knots: [(CGFloat, CGFloat)], _ d: CGFloat) -> CGFloat {
        if d <= knots[0].0 { return knots[0].1 }
        for k in 1..<knots.count {
            let (a, wa) = knots[k - 1], (b, wb) = knots[k]
            if d <= b {
                if b - a <= 1e-9 { return wb }
                return wa + (wb - wa) * (d - a) / (b - a)
            }
        }
        return knots[knots.count - 1].1
    }

    /// τ(d) of step 6.
    private static func stretched(_ knots: [(CGFloat, CGFloat)], _ wm: CGFloat, _ d: CGFloat) -> CGFloat {
        var t: CGFloat = 0
        for k in 1..<knots.count {
            let (a, wa) = knots[k - 1], (b, wb) = knots[k]
            if b - a <= 1e-9 { continue }
            let l = max(min(d, b) - a, 0)
            if l <= 0 { break }
            let slope = (wb - wa) / (b - a)
            t += abs(slope) < 1e-12 ? wm * l / wa : (wm / slope) * log((wa + slope * l) / wa)
        }
        let last = knots[knots.count - 1]
        if d > last.0 { t += wm * (d - last.0) / last.1 }
        return t
    }

    /// d(τ) of step 6.
    private static func unstretched(_ knots: [(CGFloat, CGFloat)], _ wm: CGFloat, _ t: CGFloat) -> CGFloat {
        var left = t
        for k in 1..<knots.count {
            let (a, wa) = knots[k - 1], (b, wb) = knots[k]
            if b - a <= 1e-9 { continue }
            let slope = (wb - wa) / (b - a)
            let whole = abs(slope) < 1e-12 ? wm * (b - a) / wa : (wm / slope) * log(wb / wa)
            if left <= whole {
                return abs(slope) < 1e-12 ? a + left * wa / wm : a + wa * (exp(slope * left / wm) - 1) / slope
            }
            left -= whole
        }
        let last = knots[knots.count - 1]
        return last.0 + left * last.1 / wm
    }

    // ---- the zoom mark (step 7 of the engine's `pieces`) ---------------------

    /// Outer picture corner and the matching inner frame corner, in the drawn
    /// rectangle's points, top-left, top-right, bottom-right, bottom-left.
    static func zoomCorners(_ a: Engine.Arrow, in rect: CGRect) -> [(outer: CGPoint, inner: CGPoint)] {
        let tl = at(CGPoint(x: a.x1, y: a.y1), in: rect), br = at(CGPoint(x: a.x2, y: a.y2), in: rect)
        // The outer corners are those of what is seen (`view`), else the picture's.
        let v = a.view.flatMap { $0.count == 4 ? $0 : nil } ?? [0, 0, 1, 1]
        let ol = at(CGPoint(x: v[0], y: v[1]), in: rect), or = at(CGPoint(x: v[2], y: v[3]), in: rect)
        return [(ol, tl),
                (CGPoint(x: or.x, y: ol.y), CGPoint(x: br.x, y: tl.y)),
                (or, br),
                (CGPoint(x: ol.x, y: or.y), CGPoint(x: tl.x, y: br.y))]
    }

    /// `Arrow::zoom_stroke`.
    static func zoomStroke(_ a: Engine.Arrow, in rect: CGRect) -> CGFloat {
        let run = zoomCorners(a, in: rect).map { hypot($0.inner.x - $0.outer.x, $0.inner.y - $0.outer.y) }.max() ?? 0
        return max(min(run, 0.75 * max(rect.width, rect.height)) * 0.020 * CGFloat(a.thickness), 0.7)
    }

    /// `Arrow::zoom_shapes`: the frame as two closed rectangles (filled
    /// even-odd, outlined) and four corner arrows, inset from the corners.
    static func zoom(_ a: Engine.Arrow, in rect: CGRect)
        -> (ring: [[CGPoint]], arrows: [[CGPoint]], stroke: CGFloat)? {
        guard let dir = a.zoom else { return nil }
        let stroke = zoomStroke(a, in: rect)
        let band = 3.2 * stroke
        let tl = at(CGPoint(x: a.x1, y: a.y1), in: rect), br = at(CGPoint(x: a.x2, y: a.y2), in: rect)
        func box(_ g: CGFloat) -> [CGPoint] {
            let l = tl.x - g, t = tl.y - g
            let r = max(br.x + g, l + 0.5), b = max(br.y + g, t + 0.5)
            return [CGPoint(x: l, y: t), CGPoint(x: r, y: t), CGPoint(x: r, y: b), CGPoint(x: l, y: b)]
        }
        var arrows: [[CGPoint]] = []
        for (o, i) in zoomCorners(a, in: rect) {
            let dx = i.x - o.x, dy = i.y - o.y
            let len = hypot(dx, dy)
            if len < 1 { continue }
            let ux = dx / len, uy = dy / len
            let outer = 0.10 * len, inner = 0.10 * len + 0.75 * band
            var from = CGPoint(x: o.x + ux * outer, y: o.y + uy * outer)
            // Wholly inside what is seen — `Arrow::zoom_shapes`.
            let size = min(len, 0.75 * max(rect.width, rect.height))
            let headHalf = 0.62 * min(size * 0.17 * CGFloat(a.thickness), len * 0.45)
            let m = (dir == .zoomOut ? headHalf : 0.30 * headHalf) + stroke
            from.x = ux >= 0 ? max(from.x, o.x + m) : min(from.x, o.x - m)
            from.y = uy >= 0 ? max(from.y, o.y + m) : min(from.y, o.y - m)
            let to = CGPoint(x: i.x - ux * inner, y: i.y - uy * inner)
            if (to.x - from.x) * ux + (to.y - from.y) * uy < 6 * stroke { continue }
            let (tail, head) = dir == .zoomIn ? (from, to) : (to, from)
            func f(_ p: CGPoint) -> (Double, Double) {
                (Double((p.x - rect.minX) / max(rect.width, 1)), Double((p.y - rect.minY) / max(rect.height, 1)))
            }
            let (tx, ty) = f(tail), (hx, hy) = f(head)
            var arrow = Engine.Arrow(x1: tx, y1: ty, x2: hx, y2: hy)
            arrow.thickness = a.thickness
            if let poly = outlines(arrow, in: rect).first { arrows.append(poly) }
        }
        return ([box(band / 2), box(-band / 2)], arrows, stroke)
    }

    /// The frame band as one path of two closed rectangles — fill it
    /// even-odd, then stroke it: no bridge, no seam.
    static func zoomRing(_ a: Engine.Arrow, in rect: CGRect) -> Path? {
        guard let shapes = zoom(a, in: rect) else { return nil }
        var path = Path()
        for r in shapes.ring {
            path.move(to: r[0])
            for p in r.dropFirst() { path.addLine(to: p) }
            path.closeSubpath()
        }
        return path
    }

    /// **The arrow as closed polygons**: one for a solid arrow, one per dash
    /// then the heads for a dashed one. Each is filled once and stroked once.
    static func pieces(_ arrow: Engine.Arrow, in rect: CGRect) -> [Path] {
        if arrow.zoom != nil {
            return (zoom(arrow, in: rect)?.arrows ?? []).filter { $0.count >= 3 }.map { pts in
                var path = Path()
                path.move(to: pts[0])
                for p in pts.dropFirst() { path.addLine(to: p) }
                path.closeSubpath()
                return path
            }
        }
        return outlines(arrow, in: rect).filter { $0.count >= 3 }.map { pts in
            var path = Path()
            path.move(to: pts[0])
            for p in pts.dropFirst() { path.addLine(to: p) }
            path.closeSubpath()
            return path
        }
    }

    /// The dash and the gap for a dashed shaft `run` long, `half` either side
    /// of the centre — `dash_rhythm`: three widths and 1.6, stretched alike
    /// so a whole number of dashes fills the run, tail to head.
    static func dashRhythm(_ run: CGFloat, half: CGFloat) -> (CGFloat, CGFloat) {
        let width = 2 * half
        let dash = width * 3, gap = width * 1.6
        guard run > 0, dash > 0 else { return (0, 0) }
        let count = max(((run + gap) / (dash + gap)).rounded(), 1)
        let k = run / (count * dash + (count - 1) * gap)
        return (dash * k, gap * k)
    }

    /// An arrow drawn so short it is all head.
    private static func headOnly(points: [CGPoint], half: CGFloat) -> [CGPoint] {
        let tip = points[points.count - 1]
        let back = points[max(points.count - 6, 0)]
        let dx = tip.x - back.x, dy = tip.y - back.y
        let len = max(hypot(dx, dy), 0.0001)
        let n = CGPoint(x: -dy / len, y: dx / len)
        return [CGPoint(x: back.x + n.x * half, y: back.y + n.y * half), tip,
                CGPoint(x: back.x - n.x * half, y: back.y - n.y * half)]
    }

    /// How far a point is from an arrow's shaft, for picking one up.
    static func distance(from point: CGPoint, to arrow: Engine.Arrow,
                         in rect: CGRect) -> CGFloat {
        walk(arrow, in: rect).points.map { hypot($0.x - point.x, $0.y - point.y) }.min() ?? .infinity
    }

    /// The side face of a solid arrow — `ArrowLook::shade`.
    static func shade(_ look: Engine.Arrow.Look) -> Color {
        func hex(_ v: UInt32) -> Color {
            Color(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255,
                  blue: Double(v & 255) / 255)
        }
        switch look {
        case .light: return hex(0xA6A6AB)
        case .dark: return hex(0x3C3C3E)
        case .red: return hex(0x8F2F2B)
        case .yellow: return hex(0xB08A1E)
        }
    }

    /// Fill and outline for each look.
    static func colours(_ look: Engine.Arrow.Look) -> (fill: Color, line: Color) {
        func hex(_ v: UInt32) -> Color {
            Color(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255,
                  blue: Double(v & 255) / 255)
        }
        switch look {
        case .light: return (hex(0xFFFFFF), hex(0x000000))
        case .dark: return (hex(0x141414), hex(0xF4F4F2))
        case .red: return (hex(0xD44C47), hex(0x141414))
        case .yellow: return (hex(0xF3C844), hex(0x141414))
        }
    }
}

// ------------------------------------------------------------ drawing them

/// **The arrows, over a picture, wherever that picture is drawn.**
///
/// Sits inside `Framed` and beside every fitted picture, so a mark made in the
/// pop-out is on the table thumbnail, the storyboard card and the schedule
/// strip without any of them being told about arrows.
///
/// Pale fill, dark outline, and a whisper of shadow: that combination is why
/// the traditional mark survives over a bright sky and over a night exterior
/// alike. Nothing here is themed — an arrow drawn on a photograph is part of
/// the photograph, and it must not change colour when the app does.
struct ArrowMarks: View {
    let arrows: [Engine.Arrow]

    var body: some View {
        GeometryReader { space in
            let rect = CGRect(origin: .zero, size: space.size)
            ZStack {
                ForEach(Array(arrows.enumerated()), id: \.offset) { _, arrow in
                    let width = Storyboarding.outline(arrow, in: rect)
                    let colours = Storyboarding.colours(arrow.look)
                    if let ring = Storyboarding.zoomRing(arrow, in: rect) {
                        ring.fill(colours.fill, style: FillStyle(eoFill: true))
                        ring.stroke(colours.line, style: StrokeStyle(lineWidth: width, lineJoin: .miter))
                    }
                    // A solid Toward or Away arrow's side faces in the darker
                    // tint, drawn first; the face itself last.
                    ForEach(Array(Storyboarding.faces(arrow, in: rect).enumerated()), id: \.offset) { _, face in
                        if face.points.count >= 3 {
                            let shape = Path { path in
                                path.move(to: face.points[0])
                                for p in face.points.dropFirst() { path.addLine(to: p) }
                                path.closeSubpath()
                            }
                            shape.fill(face.side ? Storyboarding.shade(arrow.look) : colours.fill)
                            shape.stroke(colours.line,
                                         style: StrokeStyle(lineWidth: width, lineJoin: .round))
                        }
                    }
                }
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.35), radius: 1.2, x: 0, y: 0.5)
        }
        .allowsHitTesting(false)
    }
}
