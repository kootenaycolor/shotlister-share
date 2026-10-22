import CoreGraphics
import Foundation
import SwiftUI

/// **Marks drawn on a picture on the plan** — his ask, 2026-10-15: annotate
/// photos to show perspective. The model, the stored line and the drawing;
/// the editor is `PhotoEditor.swift`.
///
/// **The engine is the reference** (`engine/src/diagram/photomarks.rs`): the
/// stored line's grammar is its module comment, and the plan, the portal, the
/// iPhone and the printed sheet all draw what the engine draws. This copy is
/// for the editor alone, which draws while a hand is down.
///
/// Every number is a fraction of the picture, nought to one, so the marks
/// move, size and turn with it.
enum PhotoMark: Hashable {
    case arrow(ViewModel.Arrow)
    case shape(Kind, a: CGPoint, b: CGPoint, look: ViewModel.Arrow.Look, thick: Double, dashed: Bool)
    case draw([CGPoint], look: ViewModel.Arrow.Look, thick: Double)
    case words(at: CGPoint, text: String, look: ViewModel.Arrow.Look, size: Double)

    enum Kind: String, Hashable { case line, box, oval }

    /// A word's height as a fraction of the picture's — `WORDS_SIZE`.
    static let wordsSize = 0.045
    /// The pen's half-width at thickness 1, of the longer side — `PEN`.
    static let pen = 0.0045
    static let thinnest = 0.5, thickest = 3.0
    static let mostPoints = 400

    var look: ViewModel.Arrow.Look {
        switch self {
        case .arrow(let a): return a.look
        case .shape(_, _, _, let l, _, _), .draw(_, let l, _), .words(_, _, let l, _): return l
        }
    }

    func with(look: ViewModel.Arrow.Look) -> PhotoMark {
        switch self {
        case .arrow(var a): a.look = look; return .arrow(a)
        case .shape(let k, let a, let b, _, let t, let d): return .shape(k, a: a, b: b, look: look, thick: t, dashed: d)
        case .draw(let p, _, let t): return .draw(p, look: look, thick: t)
        case .words(let at, let text, _, let s): return .words(at: at, text: text, look: look, size: s)
        }
    }

    var thick: Double {
        switch self {
        case .arrow(let a): return a.thickness
        case .shape(_, _, _, _, let t, _), .draw(_, _, let t): return t
        case .words: return 1
        }
    }

    func with(thick: Double) -> PhotoMark {
        let t = min(max(thick, PhotoMark.thinnest), PhotoMark.thickest)
        switch self {
        case .arrow(var a): a.thickness = t; return .arrow(a)
        case .shape(let k, let a, let b, let l, _, let d): return .shape(k, a: a, b: b, look: l, thick: t, dashed: d)
        case .draw(let p, let l, _): return .draw(p, look: l, thick: t)
        case .words: return self
        }
    }

    /// Moved by a distance, in fractions.
    func moved(by d: CGSize) -> PhotoMark {
        func m(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + d.width, y: p.y + d.height) }
        switch self {
        case .arrow(var a):
            a.x1 += d.width; a.y1 += d.height; a.x2 += d.width; a.y2 += d.height
            a.pins = a.pins.map { ViewModel.Arrow.Pin(x: $0.x + d.width, y: $0.y + d.height) }
            return .arrow(a)
        case .shape(let k, let a, let b, let l, let t, let ds): return .shape(k, a: m(a), b: m(b), look: l, thick: t, dashed: ds)
        case .draw(let p, let l, let t): return .draw(p.map(m), look: l, thick: t)
        case .words(let at, let text, let l, let s): return .words(at: m(at), text: text, look: l, size: s)
        }
    }

    // ---- the stored line ----------------------------------------------------

    private static func lookToken(_ look: ViewModel.Arrow.Look, _ thick: Double, _ out: inout String) {
        if look != .light { out += ",look:\(look.rawValue)" }
        if abs(thick - 1) > 0.005 { out += String(format: ",thick:%.2f", thick) }
    }

    private static func escape(_ t: String) -> String {
        var out = ""
        for c in t {
            switch c {
            case "%": out += "%25"
            case ",": out += "%2C"
            case ";": out += "%3B"
            case "\n": out += "%0A"
            case "\r": break
            default: out.append(c)
            }
        }
        return out
    }

    private static func unescape(_ t: String) -> String {
        t.replacingOccurrences(of: "%0A", with: "\n").replacingOccurrences(of: "%3B", with: ";")
            .replacingOccurrences(of: "%2C", with: ",").replacingOccurrences(of: "%25", with: "%")
    }

    var encoded: String {
        switch self {
        case .arrow(let a):
            return ViewModel.Arrow.encode([a])
        case .shape(let k, let a, let b, let look, let thick, let dashed):
            var out = String(format: "%@,%.4f,%.4f,%.4f,%.4f", k.rawValue, a.x, a.y, b.x, b.y)
            if dashed { out += ",dashed" }
            PhotoMark.lookToken(look, thick, &out)
            return out
        case .draw(let points, let look, let thick):
            var out = "draw"
            for p in points { out += String(format: ",%.4f:%.4f", p.x, p.y) }
            PhotoMark.lookToken(look, thick, &out)
            return out
        case .words(let at, let text, let look, let size):
            var out = String(format: "words,%.4f,%.4f", at.x, at.y)
            if look != .light { out += ",look:\(look.rawValue)" }
            if abs(size - PhotoMark.wordsSize) > 0.0005 { out += String(format: ",size:%.4f", size) }
            out += ",t:" + PhotoMark.escape(text)
            return out
        }
    }

    static func encode(_ marks: [PhotoMark]) -> String {
        marks.map(\.encoded).joined(separator: ";")
    }

    static func parse(_ line: String?) -> [PhotoMark] {
        guard let line, !line.isEmpty else { return [] }
        return line.split(separator: ";").compactMap { parseOne(String($0)) }
    }

    private static func parseOne(_ piece: String) -> PhotoMark? {
        let piece = piece.trimmingCharacters(in: .whitespaces)
        guard !piece.isEmpty else { return nil }
        let tokens = piece.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        let head = tokens[0]
        var look = ViewModel.Arrow.Look.light
        var thick = 1.0
        var dashed = false
        var size = wordsSize
        var text = ""
        var nums: [Double] = []
        var points: [CGPoint] = []
        func frac(_ v: Double) -> Double { v.isFinite ? min(max(v, -0.5), 1.5) : 0.5 }
        for t in tokens.dropFirst() {
            if t.hasPrefix("look:") { look = ViewModel.Arrow.Look(rawValue: String(t.dropFirst(5))) ?? look }
            else if t.hasPrefix("thick:") { thick = min(max(Double(t.dropFirst(6)) ?? 1, thinnest), thickest) }
            else if t.hasPrefix("size:") { size = min(max(Double(t.dropFirst(5)) ?? wordsSize, 0.01), 0.4) }
            else if t.hasPrefix("t:") { text = unescape(String(t.dropFirst(2))) }
            else if t == "dashed" { dashed = true }
            else if t.contains(":") {
                let xy = t.split(separator: ":")
                if xy.count == 2, let x = Double(xy[0]), let y = Double(xy[1]) { points.append(CGPoint(x: frac(x), y: frac(y))) }
            } else if let v = Double(t) { nums.append(frac(v)) }
        }
        if let kind = Kind(rawValue: head) {
            guard nums.count >= 4 else { return nil }
            return .shape(kind, a: CGPoint(x: nums[0], y: nums[1]), b: CGPoint(x: nums[2], y: nums[3]), look: look, thick: thick, dashed: dashed)
        }
        switch head {
        case "draw":
            let p = Array(points.prefix(mostPoints))
            return p.count >= 2 ? .draw(p, look: look, thick: thick) : nil
        case "words":
            guard nums.count >= 2, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return .words(at: CGPoint(x: nums[0], y: nums[1]), text: text, look: look, size: size)
        default:
            return ViewModel.Arrow.parse(piece).first.map { .arrow($0) }
        }
    }

    // ---- where it is, on screen --------------------------------------------

    static func at(_ p: CGPoint, _ plate: CGRect) -> CGPoint {
        CGPoint(x: plate.minX + p.x * plate.width, y: plate.minY + p.y * plate.height)
    }

    /// How far a point on screen is from the mark, in points.
    func distance(from point: CGPoint, in plate: CGRect) -> CGFloat {
        func seg(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = max(dx * dx + dy * dy, 0.0001)
            let u = min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / len2, 0), 1)
            return hypot(point.x - (a.x + dx * u), point.y - (a.y + dy * u))
        }
        switch self {
        case .arrow(let a):
            return Storyboarding.distance(from: point, to: a, in: plate)
        case .shape(let k, let pa, let pb, _, _, _):
            let a = PhotoMark.at(pa, plate), b = PhotoMark.at(pb, plate)
            switch k {
            case .line: return seg(a, b)
            case .box:
                let c = [a, CGPoint(x: b.x, y: a.y), b, CGPoint(x: a.x, y: b.y)]
                return (0..<4).map { seg(c[$0], c[($0 + 1) % 4]) }.min() ?? .infinity
            case .oval:
                let cx = (a.x + b.x) / 2, cy = (a.y + b.y) / 2
                let rx = max(abs(b.x - a.x) / 2, 1), ry = max(abs(b.y - a.y) / 2, 1)
                let r = hypot((point.x - cx) / rx, (point.y - cy) / ry)
                return abs(r - 1) * min(rx, ry)
            }
        case .draw(let pts, _, _):
            let s = pts.map { PhotoMark.at($0, plate) }
            return zip(s, s.dropFirst()).map { seg($0, $1) }.min() ?? .infinity
        case .words:
            return wordsBox(in: plate).insetBy(dx: -4, dy: -4).contains(point) ? 0 : .infinity
        }
    }

    /// Where words sit on screen: from their spot, as wide as they read.
    func wordsBox(in plate: CGRect) -> CGRect {
        guard case .words(let at, let text, _, let size) = self else { return .zero }
        let h = CGFloat(size) * plate.height
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let font = NSFont.systemFont(ofSize: max(h, 1), weight: .bold)
        let w = lines.map { (String($0) as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let o = PhotoMark.at(at, plate)
        return CGRect(x: o.x, y: o.y, width: max(w, h), height: h * 1.2 * CGFloat(max(lines.count, 1)))
    }

    // ---- drawing -----------------------------------------------------------

    /// **Every mark on the plate**, the last on top — the engine's drawing:
    /// a band in the look's colour with a fine edge in its line colour.
    static func draw(_ marks: [PhotoMark], in plate: CGRect, context c: inout GraphicsContext) {
        let big = max(plate.width, plate.height)
        for m in marks {
            switch m {
            case .arrow(let a):
                let width = Storyboarding.outline(a, in: plate)
                if let ring = Storyboarding.zoomRing(a, in: plate) {
                    c.fill(ring, with: .color(a.look.fill), style: FillStyle(eoFill: true))
                    c.stroke(ring, with: .color(a.look.line), style: StrokeStyle(lineWidth: width, lineJoin: .miter))
                }
                for face in Storyboarding.faces(a, in: plate) where face.points.count >= 3 {
                    var p = Path()
                    p.move(to: face.points[0])
                    for q in face.points.dropFirst() { p.addLine(to: q) }
                    p.closeSubpath()
                    c.fill(p, with: .color(face.side ? a.look.shade : a.look.fill))
                    c.stroke(p, with: .color(a.look.line), style: StrokeStyle(lineWidth: width, lineJoin: .round))
                }
            case .shape(let k, let pa, let pb, let look, let thick, let dashed):
                let a = at(pa, plate), b = at(pb, plate)
                var p = Path()
                switch k {
                case .line: p.move(to: a); p.addLine(to: b)
                case .box: p.addRect(CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y)))
                case .oval: p.addEllipse(in: CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y)))
                }
                stroke(p, look: look, width: 2 * CGFloat(pen * thick) * big, dashed: dashed && k == .line, &c)
            case .draw(let pts, let look, let thick):
                guard pts.count >= 2 else { continue }
                // **A hand's line, smoothed** (2026-10-17): corners between
                // the measured points rounded, as Notes and Markup draw.
                let sm = smoothed(pts.map { at($0, plate) })
                var p = Path()
                p.move(to: sm[0])
                for q in sm.dropFirst() { p.addLine(to: q) }
                stroke(p, look: look, width: 2 * CGFloat(pen * thick) * big, dashed: false, &c)
            case .words(_, let text, let look, let size):
                let box = m.wordsBox(in: plate)
                let h = CGFloat(size) * plate.height
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                for (i, line) in lines.enumerated() {
                    let t = Text(String(line)).font(.system(size: max(h, 1), weight: .bold)).foregroundColor(look.fill)
                    c.draw(t, at: CGPoint(x: box.minX, y: box.minY + CGFloat(i) * h * 1.2), anchor: .topLeading)
                }
            }
        }
    }

    private static func stroke(_ p: Path, look: ViewModel.Arrow.Look, width: CGFloat, dashed: Bool, _ c: inout GraphicsContext) {
        let dash: [CGFloat] = dashed ? [width * 3.5, width * 2.8] : []
        c.stroke(p, with: .color(look.line), style: StrokeStyle(lineWidth: width + 1.2, lineCap: .butt, lineJoin: .round, dash: dash))
        c.stroke(p, with: .color(look.fill), style: StrokeStyle(lineWidth: width, lineCap: .butt, lineJoin: .round, dash: dash))
    }
}

/// **The perspective helper** — `photomarks::Perspective`: a horizon across
/// the picture and, when shown, a vanishing point on it. Stored on the
/// picture as `<horizon>:<vanishing x>`, or `<horizon>:` for the horizon alone.
struct PhotoPerspective: Equatable {
    var horizon: Double
    var vanish: Double?

    static func parse(_ s: String?) -> PhotoPerspective? {
        guard let s, let i = s.firstIndex(of: ":"), let h = Double(s[..<i].trimmingCharacters(in: .whitespaces)), h.isFinite else { return nil }
        let v = Double(s[s.index(after: i)...].trimmingCharacters(in: .whitespaces))
        return PhotoPerspective(horizon: min(max(h, -1), 2), vanish: v.flatMap { $0.isFinite ? min(max($0, -2), 3) : nil })
    }

    var encoded: String {
        vanish.map { String(format: "%.4f:%.4f", horizon, $0) } ?? String(format: "%.4f:", horizon)
    }

    /// The guide lines' colour.
    static let ink = Color(red: 0.37, green: 0.83, blue: 1.0)

    /// **Draw it**: the horizon, the point, and lines fanning out from it to
    /// the picture's edges.
    func draw(in plate: CGRect, context c: inout GraphicsContext, showPoint: Bool) {
        let y = plate.minY + CGFloat(horizon) * plate.height
        var h = Path()
        h.move(to: CGPoint(x: plate.minX, y: y)); h.addLine(to: CGPoint(x: plate.maxX, y: y))
        c.stroke(h, with: .color(.black.opacity(0.35)), lineWidth: 3)
        c.stroke(h, with: .color(PhotoPerspective.ink), lineWidth: 1.4)
        c.draw(Text("HORIZON").font(.system(size: 10, weight: .bold)).foregroundColor(PhotoPerspective.ink),
               at: CGPoint(x: plate.minX + 8, y: y - 4), anchor: .bottomLeading)
        guard showPoint, let v = vanish else { return }
        let vp = CGPoint(x: plate.minX + CGFloat(v) * plate.width, y: y)
        var fan = Path()
        for t in stride(from: 0.0, through: 1.0, by: 1.0 / 6) {
            for edge in [CGPoint(x: plate.minX + CGFloat(t) * plate.width, y: plate.maxY),
                         CGPoint(x: plate.minX + CGFloat(t) * plate.width, y: plate.minY)] {
                fan.move(to: vp); fan.addLine(to: edge)
            }
        }
        for t in [0.25, 0.5, 0.75] {
            for x in [plate.minX, plate.maxX] {
                let edge = CGPoint(x: x, y: plate.minY + CGFloat(t) * plate.height)
                fan.move(to: vp); fan.addLine(to: edge)
            }
        }
        c.stroke(fan, with: .color(PhotoPerspective.ink.opacity(0.75)), style: StrokeStyle(lineWidth: 0.9, dash: [5, 5]))
        let ring = Path(ellipseIn: CGRect(x: vp.x - 7, y: vp.y - 7, width: 14, height: 14))
        c.stroke(ring, with: .color(.black.opacity(0.35)), lineWidth: 3.5)
        c.stroke(ring, with: .color(PhotoPerspective.ink), lineWidth: 2)
        c.fill(Path(ellipseIn: CGRect(x: vp.x - 2, y: vp.y - 2, width: 4, height: 4)), with: .color(PhotoPerspective.ink))
    }

    /// **A line drawn from `a` follows the guides** when it is within a few
    /// degrees of one: aimed at the vanishing point, or level with the
    /// horizon. Answers where its end goes. Fractions in, fractions out;
    /// `plate` for the angles' true shape.
    func snapped(from a: CGPoint, to b: CGPoint, in plate: CGRect) -> CGPoint {
        let w = max(plate.width, 1), h = max(plate.height, 1)
        let dx = (b.x - a.x) * w, dy = (b.y - a.y) * h
        let len = hypot(dx, dy)
        guard len > 6 else { return b }
        let angle = atan2(dy, dx)
        let close: CGFloat = 4 * .pi / 180
        func diff(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
            var d = abs(x - y).truncatingRemainder(dividingBy: 2 * .pi)
            if d > .pi { d = 2 * .pi - d }
            return d
        }
        if let v = vanish {
            let vx = (CGFloat(v) - a.x) * w, vy = (CGFloat(horizon) - a.y) * h
            if hypot(vx, vy) > 4 {
                let toward = atan2(vy, vx)
                for dir in [toward, toward + .pi] where diff(angle, dir) < close {
                    return CGPoint(x: a.x + cos(dir) * len / w, y: a.y + sin(dir) * len / h)
                }
            }
        }
        for dir in [0, CGFloat.pi] where diff(angle, dir) < close {
            return CGPoint(x: a.x + cos(dir) * len / w, y: a.y)
        }
        return b
    }
}


/// Chaikin's corner cutting, twice: a drawn line's points rounded off, its
/// two ends kept where the finger began and lifted (the engine's
/// `photomarks::smoothed`).
func smoothed(_ pts: [CGPoint]) -> [CGPoint] {
    guard pts.count > 2 else { return pts }
    var cur = pts
    for _ in 0..<2 {
        var next = [cur[0]]
        for i in 0..<(cur.count - 1) {
            let a = cur[i], b = cur[i + 1]
            next.append(CGPoint(x: a.x * 0.75 + b.x * 0.25, y: a.y * 0.75 + b.y * 0.25))
            next.append(CGPoint(x: a.x * 0.25 + b.x * 0.75, y: a.y * 0.25 + b.y * 0.75))
        }
        next.append(cur[cur.count - 1])
        cur = next
    }
    return cur
}
