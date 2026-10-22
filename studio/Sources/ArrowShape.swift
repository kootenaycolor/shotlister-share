import CoreGraphics
import Foundation
import SwiftUI

/// **One storyboard arrow, as data and as arithmetic** — the model, the stored
/// line, the standard marks, and the exact shapes it is drawn as.
///
/// Kept apart from the views in `Arrows.swift` on purpose: nothing in here
/// knows about the shell, the engine or a window, so a check can compile this
/// file on its own and set what it draws beside what the engine exports.
///
/// **The engine is the reference** (`engine/src/arrow.rs`). The grammar of the
/// stored line is its module comment; the drawing is the comment on
/// `Arrow::pieces`, followed here step by step. If one changes the other has
/// to: the printed page, the portal and this Mac all draw the same mark.
///
/// **Every coordinate is a fraction of the picture** (or of a Print Frame's
/// whole board), not of the tile it is drawn in. So an arrow stays on the
/// thing it was drawn on however small the tile, and cropping the picture
/// carries its arrows along for free.
extension ViewModel {
    struct Arrow: Hashable {
        /// Where the movement starts.
        var x1: Double
        var y1: Double
        /// Where the movement ends, and where the head is drawn.
        var x2: Double
        var y2: Double
        /// The points the shaft passes through, tail to head. None is a
        /// straight arrow.
        var pins: [Pin] = []
        var shape: Shape = .smooth
        /// 0, 1 (at the head) or 2 (at both ends: back and forth).
        var heads: Int = 1
        var dashed: Bool = false
        var look: Look = .light
        /// A multiple of the old M, `thinnest` to `thickest`. S was 0.7 and
        /// L 1.4 — the engine's `thickness`.
        var thickness: Double = 1
        var depth: Depth = .flat
        /// How much a Toward or Away arrow widens, 0.1 to 1.
        var depthStrength: Double = Arrow.usualDepth
        /// **Widths set by hand** — the engine's `widths`: the shaft's
        /// half-width and the head's half-width (the triangle's base), as
        /// fractions of the picture's longer side at thickness 1. Nil draws
        /// the depth's own (Reset Widths).
        var widths: [Double]? = nil
        /// **A zoom mark** rather than an arrow — the engine's `zoom`:
        /// `(x1, y1)` to `(x2, y2)` is the inner frame, always the picture's
        /// own shape. Look and thickness apply; pins, heads, dashes and depth
        /// mean nothing on one.
        var zoom: Zoom? = nil
        /// **The part of the picture that shows** where a zoom mark was laid
        /// — the engine's `view`, `[x1, y1, x2, y2]`. Its arrows start from
        /// these corners so none is cut off. Nil is the whole picture.
        var view: [Double]? = nil
        /// Floor or Standing — the engine's `stance`, for a Toward or Away
        /// arrow (a solid slab lying on the ground, or stood up facing the
        /// lens). Means nothing on a flat arrow.
        var stance: Stance = .floor

        enum Stance: String, Hashable, CaseIterable {
            case floor, standing
            var label: String { rawValue.capitalized }
        }

        enum Zoom: String, Hashable {
            case zoomIn = "in", zoomOut = "out"
            var label: String { self == .zoomIn ? "Zoom In" : "Zoom Out" }
        }
        /// The smallest and largest an inner frame is, as a fraction of the
        /// picture's width (and of its height).
        static let leastZoom = 0.10, mostZoom = 0.95

        /// A zoom mark dropped on the picture: the picture's shape, 60% of
        /// it, centred.
        static func zoomMark(_ dir: Zoom) -> Arrow {
            var a = Arrow.straight(0.2, 0.2, 0.8, 0.8)
            a.heads = 0
            a.zoom = dir
            return a
        }

        static let thinnest = 0.5, thickest = 3.0
        static let usualDepth = 0.5, leastDepth = 0.1, mostDepth = 1.0
        static let leastWidth = 0.001, mostWidth = 0.75

        /// **The storyboard perspective arrow** — `ArrowDepth`. Flat is every
        /// arrow drawn before it.
        enum Depth: String, Hashable, CaseIterable {
            case flat, toward, away
            var label: String { rawValue.capitalized }
        }

        /// How wide the tail and the tip are drawn, as multiples of a flat
        /// arrow — `Arrow::depth_ends`.
        var depthEnds: (Double, Double) {
            let s = min(max(depthStrength, Arrow.leastDepth), Arrow.mostDepth)
            let near = 1 + 1.2 * s, far = 1 / (1 + 2.4 * s)
            switch depth {
            case .flat: return (1, 1)
            case .toward: return (far, near)
            case .away: return (near, far)
            }
        }

        struct Pin: Hashable {
            var x: Double
            var y: Double
            var point: CGPoint { CGPoint(x: x, y: y) }
        }

        /// The shaft between the pins.
        enum Shape: String, Hashable { case smooth, corner }

        /// The fill and the outline. Light is every arrow drawn before
        /// 2026-10-14: a white shape with a black edge.
        enum Look: String, Hashable, CaseIterable {
            case light, dark, red, yellow
            var fill: Color {
                switch self {
                case .light: return Color(hex: 0xFFFFFF)
                case .dark: return Color(hex: 0x141414)
                case .red: return Color(hex: 0xD44C47)
                case .yellow: return Color(hex: 0xF3C844)
                }
            }
            /// The side face of a solid Toward or Away arrow — `ArrowLook::shade`:
            /// a darker tint of the fill, lighter for Dark where darker would
            /// not show.
            var shade: Color {
                switch self {
                case .light: return Color(hex: 0xA6A6AB)
                case .dark: return Color(hex: 0x3C3C3E)
                case .red: return Color(hex: 0x8F2F2B)
                case .yellow: return Color(hex: 0xB08A1E)
                }
            }
            var line: Color {
                switch self {
                case .light: return Color(hex: 0x000000)
                case .dark: return Color(hex: 0xF4F4F2)
                case .red, .yellow: return Color(hex: 0x141414)
                }
            }
            var label: String { rawValue.capitalized }
        }

        var tail: CGPoint { CGPoint(x: x1, y: y1) }
        var head: CGPoint { CGPoint(x: x2, y: y2) }

        /// Tail, pins and head, in order.
        var points: [CGPoint] { [tail] + pins.map(\.point) + [head] }

        /// A straight one-headed arrow between two points, in today's look.
        static func straight(_ x1: Double, _ y1: Double,
                             _ x2: Double, _ y2: Double) -> Arrow {
            Arrow(x1: x1, y1: y1, x2: x2, y2: y2)
        }

        /// An arrow through these points, tail and head included.
        static func through(_ points: [CGPoint]) -> Arrow? {
            guard points.count >= 2, let a = points.first, let c = points.last else { return nil }
            var made = Arrow.straight(a.x, a.y, c.x, c.y)
            made.pins = points.dropFirst().dropLast().map { Pin(x: $0.x, y: $0.y) }
            return made
        }

        /// **An arrow as it was stored before pins**: tail, one quadratic
        /// control point, head. The control point becomes one pin at the
        /// curve's own middle, or none when it sits on the straight line.
        static func bent(_ x1: Double, _ y1: Double, _ bx: Double, _ by: Double,
                         _ x2: Double, _ y2: Double, heads: Int = 1) -> Arrow {
            var made = Arrow.straight(x1, y1, x2, y2)
            made.heads = min(max(heads, 0), 2)
            if let pin = pinFromBend(x1, y1, bx, by, x2, y2) { made.pins = [pin] }
            return made
        }

        /// **The one control point an older reader bends the shaft with** —
        /// `Arrow::bend()`: the quadratic whose middle is the middle pin (or
        /// the point between the two middle pins), held inside the picture.
        var bend: CGPoint {
            let n = pins.count
            if n == 0 { return CGPoint(x: (x1 + x2) / 2, y: (y1 + y2) / 2) }
            let m: (Double, Double)
            if n % 2 == 1 {
                m = (pins[n / 2].x, pins[n / 2].y)
            } else {
                let p = pins[n / 2 - 1], q = pins[n / 2]
                m = ((p.x + q.x) / 2, (p.y + q.y) / 2)
            }
            return CGPoint(x: min(max(2 * m.0 - (x1 + x2) / 2, 0), 1),
                           y: min(max(2 * m.1 - (y1 + y2) / 2, 0), 1))
        }
        var bx: Double { bend.x }
        var by: Double { bend.y }

        /// A depth chosen: it sets its own widths, so any set by hand go. The
        /// thickness, like everything else about the arrow, stays.
        func withDepth(_ d: Depth) -> Arrow { var a = self; a.depth = d; a.widths = nil; return a }

        /// Reset Widths: the widths only, never the thickness.
        var widthsReset: Arrow { var a = self; a.widths = nil; return a }

        /// Back to a straight arrow — Straighten.
        var straightened: Arrow { var a = self; a.pins = []; return a }

        /// Held inside the picture, as the engine holds it.
        var held: Arrow {
            if zoom != nil { return heldZoom }
            func hold(_ v: Double) -> Double { v.isFinite ? min(max(v, 0), 1) : 0.5 }
            var a = self
            a.x1 = hold(x1); a.y1 = hold(y1); a.x2 = hold(x2); a.y2 = hold(y2)
            a.pins = pins.prefix(Arrow.mostPins).map { Pin(x: hold($0.x), y: hold($0.y)) }
            a.heads = min(max(heads, 0), 2)
            a.thickness = thickness.isFinite ? min(max(thickness, Arrow.thinnest), Arrow.thickest) : 1
            a.depthStrength = depthStrength.isFinite
                ? min(max(depthStrength, Arrow.leastDepth), Arrow.mostDepth) : Arrow.usualDepth
            if let w = widths, w.count == 2, w.allSatisfy({ $0.isFinite }) {
                a.widths = w.map { min(max($0, Arrow.leastWidth), Arrow.mostWidth) }
            } else {
                a.widths = nil
            }
            return a
        }

        /// A zoom mark held: the picture's shape (equal fractions across and
        /// down), `leastZoom` to `mostZoom`, wholly inside the picture.
        var heldZoom: Arrow {
            func fin(_ v: Double) -> Double { v.isFinite ? v : 0.5 }
            let size = min(max(abs(fin(x2) - fin(x1)), Arrow.leastZoom), Arrow.mostZoom)
            let x = min(max(min(fin(x1), fin(x2)), 0), 1 - size)
            let y = min(max(min(fin(y1), fin(y2)), 0), 1 - size)
            var a = Arrow.straight(x, y, x + size, y + size)
            a.heads = 0
            a.look = look
            a.thickness = thickness.isFinite ? min(max(thickness, Arrow.thinnest), Arrow.thickest) : 1
            a.zoom = zoom
            if let v = view, v.count == 4, v.allSatisfy({ $0.isFinite }) {
                let l = min(max(min(v[0], v[2]), 0), 1), r = min(max(max(v[0], v[2]), 0), 1)
                let t = min(max(min(v[1], v[3]), 0), 1), b = min(max(max(v[1], v[3]), 0), 1)
                let whole = l < 0.0005 && t < 0.0005 && r > 0.9995 && b > 0.9995
                a.view = (whole || r - l < 0.05 || b - t < 0.05) ? nil : [l, t, r, b]
            }
            return a
        }

        /// **A corner of the inner frame dragged**, the opposite corner held
        /// still: corner 0 top-left, 1 top-right, 2 bottom-right, 3
        /// bottom-left. The frame keeps the picture's shape, so the size is
        /// what the hand has done across and down, together.
        func zoomResized(corner k: Int, to p: CGPoint) -> Arrow {
            let ax = (k == 0 || k == 3) ? x2 : x1
            let ay = (k == 0 || k == 1) ? y2 : y1
            let size = min(max((abs(Double(p.x) - ax) + abs(Double(p.y) - ay)) / 2, Arrow.leastZoom), Arrow.mostZoom)
            var next = self
            next.x1 = (k == 0 || k == 3) ? ax - size : ax
            next.x2 = (k == 0 || k == 3) ? ax : ax + size
            next.y1 = (k == 0 || k == 1) ? ay - size : ay
            next.y2 = (k == 0 || k == 1) ? ay : ay + size
            return next.heldZoom
        }

        /// The most pins one arrow keeps — the engine's `MOST_PINS`.
        static let mostPins = 32

        /// Moved bodily, every point together, and held inside `bounds` —
        /// the part of the picture he can actually see. Sliding an arrow off
        /// the side of the frame and having the engine clamp it back later
        /// looks broken while the hand is still down.
        func moved(by delta: CGSize, inside bounds: CGRect) -> Arrow {
            let all = points
            let dx = Double(delta.width), dy = Double(delta.height)
            let xs = all.map(\.x), ys = all.map(\.y)
            let overX = max(0, (xs.max() ?? 0) + dx - bounds.maxX)
                      + min(0, (xs.min() ?? 0) + dx - bounds.minX)
            let overY = max(0, (ys.max() ?? 0) + dy - bounds.maxY)
                      + min(0, (ys.min() ?? 0) + dy - bounds.minY)
            let mx = dx - overX, my = dy - overY
            var next = self
            next.x1 += mx; next.x2 += mx; next.y1 += my; next.y2 += my
            next.pins = pins.map { Pin(x: $0.x + mx, y: $0.y + my) }
            return next
        }

        /// **An end moved, the pins riding along** — each by its share of
        /// the move, by its place between tail and head. One pin rides half
        /// way, which is exactly what the old bend did, so a curved arrow
        /// keeps its curve when an end is dragged.
        func movingEnd(head isHead: Bool, to point: CGPoint) -> Arrow {
            var next = self
            let from = isHead ? head : tail
            let dx = point.x - from.x, dy = point.y - from.y
            let n = pins.count
            next.pins = pins.enumerated().map { k, p in
                let along = Double(k + 1) / Double(n + 1)
                let share = isHead ? along : 1 - along
                return Pin(x: p.x + dx * share, y: p.y + dy * share)
            }
            if isHead { next.x2 = point.x; next.y2 = point.y } else { next.x1 = point.x; next.y1 = point.y }
            return next
        }

        // ---- the wire ------------------------------------------------------

        /// **The same line the engine stores** (`Arrow::encode`). The first
        /// seven numbers are what every older reader understands; the pins
        /// and the look ride after them in tokens an older reader drops.
        static func encode(_ arrows: [Arrow]) -> String {
            arrows.map(\.encoded).joined(separator: ";")
        }

        var encoded: String {
            if let zoom {
                // Four numbers: an older reader needs six, so it drops the entry.
                var out = String(format: "zoom:%@,%.4f,%.4f,%.4f,%.4f", zoom.rawValue, x1, y1, x2, y2)
                if let v = view, v.count == 4 {
                    out += String(format: ",view:%.4f:%.4f:%.4f:%.4f", v[0], v[1], v[2], v[3])
                }
                encodeLook(&out)
                return out
            }
            let b = bend
            var out = String(format: "%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%d",
                              x1, y1, b.x, b.y, x2, y2, min(max(heads, 0), 2))
            // Pins only when the seven numbers would not bring them back — so
            // an arrow drawn before pins keeps exactly the line it had.
            func r(_ v: Double) -> Double { (v * 10_000).rounded() / 10_000 }
            let fromBend = Arrow.pinFromBend(r(x1), r(y1), r(b.x), r(b.y), r(x2), r(y2))
            let recovered: Bool
            switch (pins.count, fromBend) {
            case (0, nil): recovered = true
            case (1, let p?): recovered = abs(p.x - pins[0].x) < 0.0005 && abs(p.y - pins[0].y) < 0.0005
            default: recovered = false
            }
            if !recovered {
                for p in pins { out += String(format: ",p%.4f:%.4f", p.x, p.y) }
            }
            if shape == .corner { out += ",corner" }
            if dashed { out += ",dashed" }
            encodeLook(&out)
            if depth != .flat {
                out += ",depth:\(depth.rawValue)"
                let s = (depthStrength * 100).rounded() / 100
                if abs(s - Arrow.usualDepth) >= 0.005 { out += String(format: ":%.2f", s) }
                if stance == .standing { out += ",stance:standing" }
            }
            if let w = widths, w.count == 2 {
                out += String(format: ",widths:%.4f:%.4f", w[0], w[1])
            }
            return out
        }

        /// The look and the thickness — what a zoom mark shares with an arrow.
        private func encodeLook(_ out: inout String) {
            if look != .light { out += ",look:\(look.rawValue)" }
            // The old weights stay the old tokens; any other thickness writes
            // the nearest weight for a reader from before thickness, then
            // `thick:`.
            let t = (thickness * 100).rounded() / 100
            func near(_ v: Double) -> Bool { abs(t - v) < 0.005 }
            if near(0.7) {
                out += ",w:S"
            } else if near(1.4) {
                out += ",w:L"
            } else if !near(1) {
                if t < 0.85 { out += ",w:S" } else if t > 1.2 { out += ",w:L" }
                out += String(format: ",thick:%.2f", t)
            }
        }

        /// Forgiving in the same way the engine's reader is (`parse_one`): an
        /// arrow that does not parse costs one arrow, never the picture, and
        /// a token this version does not know is ignored.
        static func parse(_ line: String?) -> [Arrow] {
            guard let line, !line.isEmpty else { return [] }
            return line.split(separator: ";")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .compactMap { parseOne(String($0)) }
        }

        private static func parseOne(_ piece: String) -> Arrow? {
            var n: [Double] = []
            var pins: [Pin] = []
            var shape = Shape.smooth
            var dashed = false
            var look = Look.light
            var weight: Double?
            var thick: Double?
            var depth = Depth.flat
            var depthStrength = Arrow.usualDepth
            var widths: [Double]?
            var zoom: Zoom?
            var view: [Double]?
            var stance = Stance.floor
            for raw in piece.split(separator: ",", omittingEmptySubsequences: false) {
                let token = raw.trimmingCharacters(in: .whitespaces)
                if let v = Double(token), !token.lowercased().hasPrefix("0x") {
                    n.append(v); continue
                }
                if token.hasPrefix("p") {
                    let rest = token.dropFirst()
                    if let colon = rest.firstIndex(of: ":"),
                       let x = Double(rest[..<colon].trimmingCharacters(in: .whitespaces)),
                       let y = Double(rest[rest.index(after: colon)...].trimmingCharacters(in: .whitespaces)),
                       x.isFinite, y.isFinite {
                        pins.append(Pin(x: x, y: y))
                    }
                    continue
                }
                switch token {
                case "corner": shape = .corner
                case "smooth": shape = .smooth
                case "dashed": dashed = true
                default:
                    if token.hasPrefix("view:") {
                        let v = token.dropFirst(5).split(separator: ":", omittingEmptySubsequences: false)
                            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                        if v.count == 4 { view = v }
                    } else if token.hasPrefix("stance:") {
                        switch token.dropFirst(7).trimmingCharacters(in: .whitespaces).lowercased() {
                        case "floor", "ground", "lying": stance = .floor
                        case "standing", "stand", "upright", "air": stance = .standing
                        default: break
                        }
                    } else if token.hasPrefix("zoom:") {
                        zoom = Zoom(rawValue: String(token.dropFirst(5)).trimmingCharacters(in: .whitespaces).lowercased()) ?? zoom
                    } else if token.hasPrefix("look:") {
                        look = Look(rawValue: String(token.dropFirst(5)).trimmingCharacters(in: .whitespaces).lowercased()) ?? look
                    } else if token.hasPrefix("w:") {
                        let said = String(token.dropFirst(2)).trimmingCharacters(in: .whitespaces).uppercased()
                        switch said {
                        case "S", "SMALL", "LIGHT", "THIN": weight = 0.7
                        case "M", "MEDIUM": weight = 1
                        case "L", "LARGE", "HEAVY", "THICK": weight = 1.4
                        default: break
                        }
                    } else if token.hasPrefix("thick:") {
                        if let v = Double(token.dropFirst(6).trimmingCharacters(in: .whitespaces)), v.isFinite {
                            thick = v
                        }
                    } else if token.hasPrefix("widths:") {
                        let v = token.dropFirst(7).split(separator: ":", omittingEmptySubsequences: false)
                            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                        if v.allSatisfy({ $0.isFinite }) {
                            // Two: shaft, head. The first build wrote three
                            // (tail, middle, head): shaft = the middle one.
                            if v.count == 2 { widths = v } else if v.count == 3 { widths = [v[1], v[2]] }
                        }
                    } else if token.hasPrefix("depth:") {
                        let said = token.dropFirst(6).split(separator: ":", maxSplits: 1,
                                                            omittingEmptySubsequences: false)
                        let kind = said.first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
                        let found: Depth?
                        switch kind {
                        case "flat", "none": found = .flat
                        case "toward", "towards", "in", "forward", "near": found = .toward
                        case "away", "out", "back", "backward", "far": found = .away
                        default: found = nil
                        }
                        if let found {
                            depth = found
                            depthStrength = said.count > 1
                                ? (Double(said[1].trimmingCharacters(in: .whitespaces)).flatMap { $0.isFinite ? $0 : nil }
                                   ?? Arrow.usualDepth)
                                : Arrow.usualDepth
                        }
                    }
                }
            }
            if let zoom {
                guard n.count >= 4, n.prefix(4).allSatisfy({ $0.isFinite }) else { return nil }
                var mark = Arrow.zoomMark(zoom)
                mark.x1 = n[0]; mark.y1 = n[1]; mark.x2 = n[2]; mark.y2 = n[3]
                mark.look = look
                mark.thickness = thick ?? weight ?? 1
                mark.view = view
                return mark.held
            }
            guard n.count >= 6, n.prefix(7).allSatisfy({ $0.isFinite }) else { return nil }
            let heads = n.count > 6 ? (n[6] >= 2 ? 2 : (n[6] < 0.5 ? 0 : 1)) : 1
            var made: Arrow
            if pins.isEmpty {
                made = .bent(n[0], n[1], n[2], n[3], n[4], n[5], heads: heads)
            } else {
                made = .straight(n[0], n[1], n[4], n[5])
                made.heads = heads
                made.pins = pins
            }
            made.shape = shape
            made.dashed = dashed
            made.look = look
            made.thickness = thick ?? weight ?? 1
            made.depth = depth
            made.depthStrength = depthStrength
            made.widths = widths
            made.stance = stance
            return made.held
        }

        /// The pin an old control point stands for: the quadratic's own
        /// middle, `(a + 2b + c) / 4` — or none when the control point sits
        /// on the straight line (within a thousandth of the picture).
        static func pinFromBend(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double,
                                _ cx: Double, _ cy: Double) -> Pin? {
            let dx = cx - ax, dy = cy - ay
            let len = hypot(dx, dy)
            let off = len < 1e-9 ? hypot(bx - ax, by - ay)
                                 : abs((bx - ax) * dy - (by - ay) * dx) / len
            if off < 0.001 { return nil }
            return Pin(x: (ax + 2 * bx + cx) / 4, y: (ay + 2 * by + cy) / 4)
        }

        // ---- the marks -----------------------------------------------------

        /// **The standard marks**, in two menus: what the camera does, and
        /// what somebody in the frame does. Each one is a set of ordinary
        /// arrows, so every one can be picked up, bent and moved after it
        /// lands. Positions are `design/45-print-frame.html` section H; the
        /// four that existed before keep exactly the places they had.
        enum Mark: String, CaseIterable, Identifiable {
            /// One plain arrow across the middle. Not in either menu (drag
            /// draws one); kept for the checking flag `--arrows Arrow`.
            case arrow = "Arrow"
            case panLeft = "Pan Left"
            case panRight = "Pan Right"
            case tiltUp = "Tilt Up"
            case tiltDown = "Tilt Down"
            case pushIn = "Push In"
            case pullOut = "Pull Out"
            case dollyIn = "Dolly In"
            case dollyOut = "Dolly Out"
            case truckLeft = "Truck Left"
            case truckRight = "Truck Right"
            case craneUp = "Crane Up"
            case craneDown = "Crane Down"
            case orbit = "Orbit"
            case roll = "Roll"
            case walk = "Walk"
            case crossFrame = "Cross Frame"
            case turnAround = "Turn Around"
            case exit = "Exit"
            case towardCamera = "Toward Camera"
            /// A zoom mark: the frame inside the frame. In the Camera menu.
            case zoomIn = "Zoom In"
            case zoomOut = "Zoom Out"
            var id: String { rawValue }

            static let camera: [Mark] = [.panLeft, .panRight, .tiltUp, .tiltDown,
                                         .pushIn, .pullOut, .dollyIn, .dollyOut, .truckLeft, .truckRight,
                                         .craneUp, .craneDown, .orbit, .roll, .zoomIn, .zoomOut]
            static let subject: [Mark] = [.walk, .crossFrame, .turnAround, .exit, .towardCamera]

            /// Placed inside `frame` — the part of the picture he is actually
            /// looking at, not the whole photograph.
            func arrows(in frame: CGRect) -> [Arrow] {
                if self == .zoomIn || self == .zoomOut {
                    // The picture's shape (equal fractions), 60% of the part he
                    // is looking at, centred in it.
                    let size = 0.6 * min(frame.width, frame.height)
                    var mark = Arrow.zoomMark(self == .zoomIn ? .zoomIn : .zoomOut)
                    mark.x1 = frame.midX - size / 2; mark.x2 = frame.midX + size / 2
                    mark.y1 = frame.midY - size / 2; mark.y2 = frame.midY + size / 2
                    // Its arrows start from the corners of what is seen.
                    mark.view = [frame.minX, frame.minY, frame.maxX, frame.maxY]
                    return [mark.held]
                }
                return placed.map { a in
                    func px(_ v: Double) -> Double { frame.minX + v * frame.width }
                    func py(_ v: Double) -> Double { frame.minY + v * frame.height }
                    var out = a
                    out.x1 = px(a.x1); out.y1 = py(a.y1); out.x2 = px(a.x2); out.y2 = py(a.y2)
                    out.pins = a.pins.map { Pin(x: px($0.x), y: py($0.y)) }
                    return out
                }
            }

            private var placed: [Arrow] {
                func line(_ pts: [(Double, Double)]) -> Arrow {
                    Arrow.through(pts.map { CGPoint(x: $0.0, y: $0.1) })!
                }
                /// Somebody going somewhere: dashed and red, so it never reads
                /// as a camera move.
                func subject(_ pts: [(Double, Double)]) -> Arrow {
                    var a = line(pts); a.dashed = true; a.look = .red; return a
                }
                switch self {
                case .zoomIn, .zoomOut:
                    return [Arrow.zoomMark(self == .zoomIn ? .zoomIn : .zoomOut)]
                case .arrow:
                    var a = Arrow.straight(0.22, 0.5, 0.78, 0.5)
                    a.thickness = ArrowThickness.remembered()
                    return [a]
                case .panRight:
                    return [.straight(0.18, 0.16, 0.74, 0.16),
                            .straight(0.18, 0.84, 0.74, 0.84)]
                case .panLeft:
                    return [.straight(0.82, 0.16, 0.26, 0.16),
                            .straight(0.82, 0.84, 0.26, 0.84)]
                case .tiltUp:
                    return [.bent(0.16, 0.82, 0.06, 0.5, 0.18, 0.16),
                            .bent(0.84, 0.82, 0.94, 0.5, 0.82, 0.16)]
                case .tiltDown:
                    return [.bent(0.16, 0.18, 0.06, 0.5, 0.18, 0.84),
                            .bent(0.84, 0.18, 0.94, 0.5, 0.82, 0.84)]
                case .pushIn:
                    return [.straight(0.07, 0.09, 0.30, 0.30),
                            .straight(0.93, 0.09, 0.70, 0.30),
                            .straight(0.07, 0.91, 0.30, 0.70),
                            .straight(0.93, 0.91, 0.70, 0.70)]
                case .pullOut:
                    return [.straight(0.30, 0.30, 0.07, 0.09),
                            .straight(0.70, 0.30, 0.93, 0.09),
                            .straight(0.30, 0.70, 0.07, 0.91),
                            .straight(0.70, 0.70, 0.93, 0.91)]
                // Perspective arrows up the middle of the frame: the camera
                // travelling into the picture, or backing out of it.
                case .dollyIn:
                    var a = Arrow.straight(0.5, 0.9, 0.5, 0.2)
                    a.depth = .away; a.depthStrength = 0.6; a.thickness = 1.6
                    return [a]
                case .dollyOut:
                    var a = Arrow.straight(0.5, 0.2, 0.5, 0.9)
                    a.depth = .toward; a.depthStrength = 0.6; a.thickness = 1.6
                    return [a]
                case .truckRight:
                    return [.straight(0.15, 0.887, 0.85, 0.887)]
                case .truckLeft:
                    return [.straight(0.85, 0.887, 0.15, 0.887)]
                case .craneUp:
                    return [.straight(0.9, 0.858, 0.9, 0.143)]
                case .craneDown:
                    return [.straight(0.9, 0.143, 0.9, 0.858)]
                case .orbit:
                    return [line([(0.2, 0.644), (0.35, 0.858), (0.65, 0.858), (0.8, 0.644)])]
                case .roll:
                    return [line([(0.62, 0.257), (0.78, 0.5), (0.62, 0.744),
                                  (0.38, 0.744), (0.22, 0.5), (0.36, 0.286)])]
                case .walk:
                    return [subject([(0.68, 0.14), (0.61, 0.5), (0.5, 0.86)])]
                case .crossFrame:
                    return [subject([(0.08, 0.715), (0.5, 0.601), (0.92, 0.715)])]
                case .turnAround:
                    return [subject([(0.35, 0.887), (0.35, 0.429), (0.5, 0.257),
                                     (0.65, 0.429), (0.65, 0.787)])]
                case .exit:
                    return [subject([(0.55, 0.88), (0.55, 0.38)])]
                case .towardCamera:
                    var a = subject([(0.5, 0.16), (0.5, 0.88)]); a.depth = .toward
                    return [a]
                }
            }
        }
    }
}

extension Color {
    /// `0xRRGGBB`, in sRGB — the arrow looks are fixed colours, the same on a
    /// light window and a dark one, because they are part of the photograph.
    fileprivate init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

// ------------------------------------------------------------ the shape

/// **The one place on the Mac that knows what a storyboard arrow looks
/// like** — `Arrow::pieces` in the engine, step for step.
///
/// The proportions are the arrow's own length, not the tile's — that is what
/// makes a short arrow look like a short arrow rather than a stub with an
/// enormous head. So the same arrow on a 90-point table thumbnail and on a
/// full-screen pop-out is the same picture, larger.
enum Storyboarding {
    /// Where a fraction of the picture lands inside a drawn rectangle.
    static func at(_ p: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
    }

    /// **Step 1: the centre line**, sampled, with the running length
    /// alongside — in the drawn rectangle's own points.
    static func centreLine(_ arrow: ViewModel.Arrow, in rect: CGRect)
        -> (points: [CGPoint], lengths: [CGFloat]) {
        if arrow.zoom != nil {
            // A zoom mark's "line" is the inner frame's edge, once round.
            let c = zoomCorners(arrow, in: rect).map(\.inner)
            var points: [CGPoint] = []
            for i in 0..<4 {
                let a = c[i], b = c[(i + 1) % 4]
                for k in 0..<12 {
                    let t = CGFloat(k) / 12
                    points.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                }
            }
            points.append(c[0])
            var lengths: [CGFloat] = [0]
            for i in 1..<points.count {
                lengths.append(lengths[i - 1] + hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y))
            }
            return (points, lengths)
        }
        let p = arrow.points.map { at($0, in: rect) }
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
                    let t = CGFloat(k) / 24, t2 = t * t, t3 = t2 * t
                    func at(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
                        0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2
                               + (-a + 3 * b - 3 * c + d) * t3)
                    }
                    points.append(CGPoint(x: at(p0.x, p1.x, p2.x, p3.x),
                                          y: at(p0.y, p1.y, p2.y, p3.y)))
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

    /// How long the shaft is on screen. Nought for an arrow with no length,
    /// which is what a click that never became a drag leaves behind.
    static func length(_ arrow: ViewModel.Arrow, in rect: CGRect) -> CGFloat {
        centreLine(arrow, in: rect).lengths.last ?? 0
    }

    /// The outline's width — the whole reason an arrow reads over a bright
    /// photograph as well as a dark one. `Arrow::stroke`: a deep arrow's pen
    /// follows how big it lies, not how long it looks.
    static func outline(_ arrow: ViewModel.Arrow, in rect: CGRect) -> CGFloat {
        if arrow.zoom != nil { return zoomStroke(arrow, in: rect) }
        let big = max(rect.width, rect.height)
        let size = min(length(arrow, in: rect), 0.75 * big)
        let pen = max(size * 0.020 * CGFloat(arrow.thickness), 0.7)
        return arrow.depth == .flat ? pen : max(pen * SolidArrow.pen, 0.7)
    }

    /// The arrow as `SolidArrow` needs it — step 8, a Toward or Away arrow.
    static func solid(_ arrow: ViewModel.Arrow, in rect: CGRect) -> SolidArrow.Arrow {
        let (points, lengths) = centreLine(arrow, in: rect)
        return SolidArrow.Arrow(points: points, lengths: lengths, rect: rect,
                                toward: arrow.depth == .toward, standing: arrow.stance == .standing,
                                strength: arrow.depthStrength, thickness: arrow.thickness,
                                heads: arrow.heads, dashed: arrow.dashed, widths: arrow.widths)
    }

    /// **The faces to draw, in order** — `Arrow::faces`: the pieces, with
    /// which of them are a solid arrow's side faces (`Look.shade`).
    static func faces(_ arrow: ViewModel.Arrow, in rect: CGRect) -> [SolidArrow.Face] {
        if arrow.depth != .flat && arrow.zoom == nil { return SolidArrow.faces(solid(arrow, in: rect)) }
        return pieces(arrow, in: rect).map { SolidArrow.Face(points: $0, side: false) }
    }

    /// **The two widths the handles set** — `Arrow::widths_px`: the shaft's
    /// half-width (at its middle) and the head's half-width, in the drawn
    /// rectangle's points. The hand-set ones, else the depth's — where the
    /// handles sit before they are touched.
    static func widths(_ arrow: ViewModel.Arrow, in rect: CGRect) -> [CGFloat] {
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
    private static func defaultLaid(_ arrow: ViewModel.Arrow, in rect: CGRect) -> [CGFloat] {
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
    private static func laidWidths(_ arrow: ViewModel.Arrow, in rect: CGRect) -> [CGFloat] {
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

    /// **Where the two widths are measured** — the middle of the shaft, and
    /// the head's wide base (the neck; none when there is no head): each a
    /// point on the centre line, the unit normal there, and the half-width.
    /// The handles sit at point + normal·half.
    static func widthSpots(_ arrow: ViewModel.Arrow, in rect: CGRect)
        -> [(point: CGPoint, normal: CGPoint, half: CGFloat)] {
        let (points, lengths) = centreLine(arrow, in: rect)
        let total = lengths.last ?? 0
        guard total > 1, points.count >= 2 else { return [] }
        let w = laidWidths(arrow, in: rect)
        let lay = laid(arrow, total: total, in: rect)
        let mid = (lay.startsAt + lay.endsAt) / 2
        // A flat arrow with widths set by hand: the shaft's handle is at its
        // start, where the back is as wide as he set it.
        var spots = [arrow.depth == .flat && arrow.widths != nil ? (lay.startsAt, w[0]) : (mid, w[1])]
        if arrow.heads >= 1 { spots.append((lay.endsAt, w[3])) }
        return spots.map { s, half in
            let (p, n) = along(points, lengths, s)
            return (p, n, half)
        }
    }

    /// Step 6's lengths: where the shaft starts and ends, and the heads.
    private static func laid(_ arrow: ViewModel.Arrow, total: CGFloat, in rect: CGRect)
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
    static func pieces(_ arrow: ViewModel.Arrow, in rect: CGRect) -> [[CGPoint]] {
        if arrow.depth != .flat && arrow.zoom == nil {
            return SolidArrow.faces(solid(arrow, in: rect)).map(\.points)
        }
        if arrow.zoom != nil { return zoom(arrow, in: rect)?.arrows ?? [] }
        let (points, lengths) = centreLine(arrow, in: rect)
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
        guard endsAt > startsAt else { return [headOnly(points, half: lay.tipHalf)] }
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
    private static func headOnly(_ points: [CGPoint], half: CGFloat) -> [CGPoint] {
        let tip = points[points.count - 1]
        let back = points[max(points.count - 6, 0)]
        let dx = tip.x - back.x, dy = tip.y - back.y
        let len = max(hypot(dx, dy), 0.0001)
        let n = CGPoint(x: -dy / len, y: dx / len)
        return [CGPoint(x: back.x + n.x * half, y: back.y + n.y * half), tip,
                CGPoint(x: back.x - n.x * half, y: back.y - n.y * half)]
    }

    // ---- the zoom mark (step 7) --------------------------------------------

    /// Outer picture corner and the matching inner frame corner, in the drawn
    /// rectangle's points, top-left, top-right, bottom-right, bottom-left.
    static func zoomCorners(_ a: ViewModel.Arrow, in rect: CGRect) -> [(outer: CGPoint, inner: CGPoint)] {
        let tl = at(CGPoint(x: a.x1, y: a.y1), in: rect), br = at(CGPoint(x: a.x2, y: a.y2), in: rect)
        // The outer corners are those of what is seen (`view`), else the picture's.
        let v = a.view.flatMap { $0.count == 4 ? $0 : nil } ?? [0, 0, 1, 1]
        let ol = at(CGPoint(x: v[0], y: v[1]), in: rect), or = at(CGPoint(x: v[2], y: v[3]), in: rect)
        return [(ol, tl),
                (CGPoint(x: or.x, y: ol.y), CGPoint(x: br.x, y: tl.y)),
                (or, br),
                (CGPoint(x: ol.x, y: or.y), CGPoint(x: tl.x, y: br.y))]
    }

    /// `Arrow::zoom_stroke`: arrow arithmetic on the longest corner run.
    static func zoomStroke(_ a: ViewModel.Arrow, in rect: CGRect) -> CGFloat {
        let run = zoomCorners(a, in: rect).map { hypot($0.inner.x - $0.outer.x, $0.inner.y - $0.outer.y) }.max() ?? 0
        return max(min(run, 0.75 * max(rect.width, rect.height)) * 0.020 * CGFloat(a.thickness), 0.7)
    }

    /// **The zoom mark as shapes** — `Arrow::zoom_shapes`: the frame as two
    /// closed rectangles (the band's outer and inner edge, drawn even-odd and
    /// outlined) and the four corner arrows as ordinary polygons, inset from
    /// the corners so they stay legible. In for inward, Out for outward.
    static func zoom(_ a: ViewModel.Arrow, in rect: CGRect)
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
            var arrow = ViewModel.Arrow.straight(tx, ty, hx, hy)
            arrow.thickness = a.thickness
            if let poly = pieces(arrow, in: rect).first { arrows.append(poly) }
        }
        return ([box(band / 2), box(-band / 2)], arrows, stroke)
    }

    /// The frame band as one path of two closed rectangles — fill it
    /// even-odd, then stroke it. No bridge, so no seam.
    static func zoomRing(_ a: ViewModel.Arrow, in rect: CGRect) -> Path? {
        guard let shapes = zoom(a, in: rect) else { return nil }
        var path = Path()
        for r in shapes.ring {
            path.move(to: r[0])
            for p in r.dropFirst() { path.addLine(to: p) }
            path.closeSubpath()
        }
        return path
    }

    /// The pieces as SwiftUI paths, one per piece.
    static func paths(_ arrow: ViewModel.Arrow, in rect: CGRect) -> [Path] {
        pieces(arrow, in: rect).filter { $0.count >= 3 }.map { piece in
            var path = Path()
            path.move(to: piece[0])
            for p in piece.dropFirst() { path.addLine(to: p) }
            path.closeSubpath()
            return path
        }
    }

    /// How far a point is from an arrow's shaft, for picking one up.
    static func distance(from point: CGPoint, to arrow: ViewModel.Arrow,
                         in rect: CGRect) -> CGFloat {
        if arrow.zoom != nil {
            // The frame's edge, or any of the four arrows' own lines.
            func seg(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
                let dx = b.x - a.x, dy = b.y - a.y
                let len2 = max(dx * dx + dy * dy, 0.0001)
                let u = min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / len2, 0), 1)
                return hypot(point.x - (a.x + dx * u), point.y - (a.y + dy * u))
            }
            let c = zoomCorners(arrow, in: rect)
            var best = CGFloat.infinity
            for i in 0..<4 {
                best = min(best, seg(c[i].inner, c[(i + 1) % 4].inner), seg(c[i].outer, c[i].inner))
            }
            return best
        }
        return centreLine(arrow, in: rect).points
            .map { hypot($0.x - point.x, $0.y - point.y) }.min() ?? .infinity
    }

    /// **Where a new pin goes in the list** when the shaft is double-clicked
    /// at `point`: after however many pins come before the nearest spot on
    /// the shaft. The samples are laid out a fixed count per span, so the
    /// nearest sample says which span it is on.
    static func pinSlot(at point: CGPoint, on arrow: ViewModel.Arrow, in rect: CGRect) -> Int {
        let samples = centreLine(arrow, in: rect).points
        guard let nearest = samples.indices.min(by: {
            hypot(samples[$0].x - point.x, samples[$0].y - point.y)
                < hypot(samples[$1].x - point.x, samples[$1].y - point.y)
        }) else { return 0 }
        let n = arrow.pins.count
        if n == 1 && arrow.shape == .smooth { return nearest < 20 ? 0 : 1 }
        return min(nearest / 24, n)
    }
}
