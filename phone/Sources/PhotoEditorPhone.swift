import SwiftUI

// **Draw on Photo, on the phone** (the Mac's `PhotoEditor`, parity 3,
// 2026-10-16): the picture at full strength, tools to lay arrows, lines,
// boxes, ovals, drawing and words on it, a horizon and vanishing point that
// lines and arrows follow, four colors, and the picture's strength. The
// marks are stored on the picture as fractions (`photomarks` in the engine),
// so they move, size and turn with it, and every app draws them.

enum PhotoToolPhone: String, CaseIterable, Identifiable {
    case select, arrow, line, box, oval, draw, words, perspective
    var id: String { rawValue }
    var title: String { rawValue == "box" ? "Box" : rawValue.capitalized }
    var symbol: String {
        switch self {
        case .select: return "hand.point.up.left"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .box: return "square"
        case .oval: return "circle"
        case .draw: return "scribble"
        case .words: return "textformat"
        case .perspective: return "perspective"
        }
    }
}

/// One mark on a picture — the engine's grammar (`photomarks.rs`).
enum PhotoMarkPhone: Hashable {
    case arrow(Engine.Arrow)
    case shape(Kind, a: CGPoint, b: CGPoint, look: Engine.Arrow.Look, thick: Double, dashed: Bool)
    case draw([CGPoint], look: Engine.Arrow.Look, thick: Double)
    case words(at: CGPoint, text: String, look: Engine.Arrow.Look, size: Double)

    enum Kind: String, Hashable { case line, box, oval }

    static let wordsSize = 0.045
    static let pen = 0.0045
    static let mostPoints = 400

    var look: Engine.Arrow.Look {
        switch self {
        case .arrow(let a): return a.look
        case .shape(_, _, _, let l, _, _), .draw(_, let l, _), .words(_, _, let l, _): return l
        }
    }

    func with(look: Engine.Arrow.Look) -> PhotoMarkPhone {
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

    func with(thick: Double) -> PhotoMarkPhone {
        let t = min(max(thick, 0.5), 3)
        switch self {
        case .arrow(var a): a.thickness = t; return .arrow(a)
        case .shape(let k, let a, let b, let l, _, let d): return .shape(k, a: a, b: b, look: l, thick: t, dashed: d)
        case .draw(let p, let l, _): return .draw(p, look: l, thick: t)
        case .words: return self
        }
    }

    func moved(by d: CGSize) -> PhotoMarkPhone {
        func m(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + d.width, y: p.y + d.height) }
        switch self {
        case .arrow(var a):
            a.x1 += d.width; a.y1 += d.height; a.x2 += d.width; a.y2 += d.height
            a.pins = a.pins.map(m)
            return .arrow(a)
        case .shape(let k, let a, let b, let l, let t, let ds): return .shape(k, a: m(a), b: m(b), look: l, thick: t, dashed: ds)
        case .draw(let p, let l, let t): return .draw(p.map(m), look: l, thick: t)
        case .words(let at, let text, let l, let s): return .words(at: m(at), text: text, look: l, size: s)
        }
    }

    private static func lookWord(_ l: Engine.Arrow.Look) -> String {
        switch l { case .light: return "light"; case .dark: return "dark"; case .red: return "red"; case .yellow: return "yellow" }
    }
    private static func look(_ w: String) -> Engine.Arrow.Look? {
        switch w { case "light": return .light; case "dark": return .dark; case "red": return .red; case "yellow": return .yellow; default: return nil }
    }
    private static func lookToken(_ look: Engine.Arrow.Look, _ thick: Double, _ out: inout String) {
        if look != .light { out += ",look:\(lookWord(look))" }
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
            return Engine.Arrow.encode([a])
        case .shape(let k, let a, let b, let look, let thick, let dashed):
            var out = String(format: "%@,%.4f,%.4f,%.4f,%.4f", k.rawValue, a.x, a.y, b.x, b.y)
            if dashed { out += ",dashed" }
            Self.lookToken(look, thick, &out)
            return out
        case .draw(let points, let look, let thick):
            var out = "draw"
            for p in points { out += String(format: ",%.4f:%.4f", p.x, p.y) }
            Self.lookToken(look, thick, &out)
            return out
        case .words(let at, let text, let look, let size):
            var out = String(format: "words,%.4f,%.4f", at.x, at.y)
            if look != .light { out += ",look:\(Self.lookWord(look))" }
            if abs(size - Self.wordsSize) > 0.0005 { out += String(format: ",size:%.4f", size) }
            out += ",t:" + Self.escape(text)
            return out
        }
    }

    static func encode(_ marks: [PhotoMarkPhone]) -> String { marks.map(\.encoded).joined(separator: ";") }

    static func parse(_ line: String?) -> [PhotoMarkPhone] {
        guard let line, !line.isEmpty else { return [] }
        return line.split(separator: ";").compactMap { parseOne(String($0)) }
    }

    private static func parseOne(_ piece: String) -> PhotoMarkPhone? {
        let piece = piece.trimmingCharacters(in: .whitespaces)
        guard !piece.isEmpty else { return nil }
        let tokens = piece.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        let head = tokens[0]
        var look = Engine.Arrow.Look.light
        var thick = 1.0, dashed = false, size = wordsSize, text = ""
        var nums: [Double] = []
        var points: [CGPoint] = []
        func frac(_ v: Double) -> Double { v.isFinite ? min(max(v, -0.5), 1.5) : 0.5 }
        for t in tokens.dropFirst() {
            if t.hasPrefix("look:") { look = Self.look(String(t.dropFirst(5))) ?? look }
            else if t.hasPrefix("thick:") { thick = min(max(Double(t.dropFirst(6)) ?? 1, 0.5), 3) }
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
            return Engine.Arrow.parse(piece).first.map { .arrow($0) }
        }
    }

    static func at(_ p: CGPoint, _ plate: CGRect) -> CGPoint {
        CGPoint(x: plate.minX + p.x * plate.width, y: plate.minY + p.y * plate.height)
    }

    func wordsBox(in plate: CGRect) -> CGRect {
        guard case .words(let at, let text, _, let size) = self else { return .zero }
        let h = CGFloat(size) * plate.height
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let font = UIFont.systemFont(ofSize: max(h, 1), weight: .bold)
        let w = lines.map { (String($0) as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let o = Self.at(at, plate)
        return CGRect(x: o.x, y: o.y, width: max(w, h), height: h * 1.2 * CGFloat(max(lines.count, 1)))
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
            let pts = ([a.tail] + a.pins + [a.head]).map { Self.at($0, plate) }
            return zip(pts, pts.dropFirst()).map { seg($0, $1) }.min() ?? .infinity
        case .shape(let k, let pa, let pb, _, _, _):
            let a = Self.at(pa, plate), b = Self.at(pb, plate)
            switch k {
            case .line: return seg(a, b)
            case .box:
                let c = [a, CGPoint(x: b.x, y: a.y), b, CGPoint(x: a.x, y: b.y)]
                return (0..<4).map { seg(c[$0], c[($0 + 1) % 4]) }.min() ?? .infinity
            case .oval:
                let cx = (a.x + b.x) / 2, cy = (a.y + b.y) / 2
                let rx = max(abs(b.x - a.x) / 2, 1), ry = max(abs(b.y - a.y) / 2, 1)
                return abs(hypot((point.x - cx) / rx, (point.y - cy) / ry) - 1) * min(rx, ry)
            }
        case .draw(let pts, _, _):
            let s = pts.map { Self.at($0, plate) }
            return zip(s, s.dropFirst()).map { seg($0, $1) }.min() ?? .infinity
        case .words:
            return wordsBox(in: plate).insetBy(dx: -8, dy: -8).contains(point) ? 0 : .infinity
        }
    }

    static func colours(_ l: Engine.Arrow.Look) -> (fill: Color, line: Color) {
        let c = Storyboarding.colours(l)
        return (c.fill, c.line)
    }

    /// Every mark, the last on top: a band in the look's color with a fine edge.
    static func draw(_ marks: [PhotoMarkPhone], in plate: CGRect, context c: inout GraphicsContext) {
        let big = max(plate.width, plate.height)
        for m in marks {
            switch m {
            case .arrow(let a):
                let width = Storyboarding.outline(a, in: plate)
                let col = Storyboarding.colours(a.look)
                if let ring = Storyboarding.zoomRing(a, in: plate) {
                    c.fill(ring, with: .color(col.fill), style: FillStyle(eoFill: true))
                    c.stroke(ring, with: .color(col.line), style: StrokeStyle(lineWidth: width, lineJoin: .miter))
                }
                for face in Storyboarding.faces(a, in: plate) where face.points.count >= 3 {
                    var p = Path()
                    p.move(to: face.points[0])
                    for q in face.points.dropFirst() { p.addLine(to: q) }
                    p.closeSubpath()
                    c.fill(p, with: .color(face.side ? Storyboarding.shade(a.look) : col.fill))
                    c.stroke(p, with: .color(col.line), style: StrokeStyle(lineWidth: width, lineJoin: .round))
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
                    let t = Text(String(line)).font(.system(size: max(h, 1), weight: .bold)).foregroundColor(colours(look).fill)
                    c.draw(t, at: CGPoint(x: box.minX, y: box.minY + CGFloat(i) * h * 1.2), anchor: .topLeading)
                }
            }
        }
    }

    private static func stroke(_ p: Path, look: Engine.Arrow.Look, width: CGFloat, dashed: Bool, _ c: inout GraphicsContext) {
        let dash: [CGFloat] = dashed ? [width * 3.5, width * 2.8] : []
        let col = colours(look)
        c.stroke(p, with: .color(col.line), style: StrokeStyle(lineWidth: width + 1.2, lineCap: .butt, lineJoin: .round, dash: dash))
        c.stroke(p, with: .color(col.fill), style: StrokeStyle(lineWidth: width, lineCap: .butt, lineJoin: .round, dash: dash))
    }
}

/// The perspective helper: a horizon, and a vanishing point on it.
struct PhotoPerspectivePhone: Equatable {
    var horizon: Double
    var vanish: Double?

    static func parse(_ s: String?) -> PhotoPerspectivePhone? {
        guard let s, let i = s.firstIndex(of: ":"), let h = Double(s[..<i].trimmingCharacters(in: .whitespaces)), h.isFinite else { return nil }
        let v = Double(s[s.index(after: i)...].trimmingCharacters(in: .whitespaces))
        return PhotoPerspectivePhone(horizon: min(max(h, -1), 2), vanish: v.flatMap { $0.isFinite ? min(max($0, -2), 3) : nil })
    }

    var encoded: String {
        vanish.map { String(format: "%.4f:%.4f", horizon, $0) } ?? String(format: "%.4f:", horizon)
    }

    static let ink = Color(red: 0.37, green: 0.83, blue: 1.0)

    func draw(in plate: CGRect, context c: inout GraphicsContext) {
        let y = plate.minY + CGFloat(horizon) * plate.height
        var h = Path()
        h.move(to: CGPoint(x: plate.minX, y: y)); h.addLine(to: CGPoint(x: plate.maxX, y: y))
        c.stroke(h, with: .color(.black.opacity(0.35)), lineWidth: 3)
        c.stroke(h, with: .color(Self.ink), lineWidth: 1.4)
        c.draw(Text("HORIZON").font(.system(size: 10, weight: .bold)).foregroundColor(Self.ink),
               at: CGPoint(x: plate.minX + 8, y: y - 4), anchor: .bottomLeading)
        guard let v = vanish else { return }
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
                fan.move(to: vp); fan.addLine(to: CGPoint(x: x, y: plate.minY + CGFloat(t) * plate.height))
            }
        }
        c.stroke(fan, with: .color(Self.ink.opacity(0.75)), style: StrokeStyle(lineWidth: 0.9, dash: [5, 5]))
        let ring = Path(ellipseIn: CGRect(x: vp.x - 9, y: vp.y - 9, width: 18, height: 18))
        c.stroke(ring, with: .color(.black.opacity(0.35)), lineWidth: 3.5)
        c.stroke(ring, with: .color(Self.ink), lineWidth: 2)
    }

    /// A line drawn from `a` follows a guide when within a few degrees of one.
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

/// **The editor**, full screen over the plan.
struct PhotoEditorPhone: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    let plan: String
    let photo: String
    /// One edit, as the diagram editor sends it.
    let edit: ([String: Any]) -> Void

    @State private var image: UIImage?
    @State private var marks: [PhotoMarkPhone] = []
    @State private var perspective: PhotoPerspectivePhone?
    @State private var strength: Double = 1
    @State private var tool: PhotoToolPhone = .select
    @State private var picked: Int?
    @State private var trail: [CGPoint] = []
    @State private var dragFrom: CGPoint?
    @State private var dragging: CGSize = .zero
    @State private var typing: CGPoint?
    @State private var words = ""
    @AppStorage("photoMarkLook") private var lookWord = "yellow"
    /// **Two fingers move and zoom the view** (2026-10-17); one finger draws.
    @State private var zoom: CGFloat = 1
    @State private var zoomFrom: CGFloat?
    @State private var pan: CGSize = .zero
    @State private var panFrom: CGSize?
    /// A second finger came down: the stroke the first one began is let go.
    @State private var twoFingers = false
    /// Where the finger is about to be (UIKit's predicted touches): drawn
    /// with the stroke, never kept.
    @State private var predicted: [CGPoint] = []
    @State private var strokeStart: CGPoint?
    @State private var clearing = false

    private var look: Engine.Arrow.Look {
        switch lookWord { case "light": return .light; case "dark": return .dark; case "red": return .red; default: return .yellow }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { space in
                let plate = shownPlate(space.size)
                ZStack {
                    Color.black.ignoresSafeArea()
                    if let image {
                        Image(uiImage: image).resizable()
                            .frame(width: plate.width, height: plate.height)
                            .position(x: plate.midX, y: plate.midY)
                    }
                    Canvas { c, _ in
                        var shown = marks
                        if let p = picked, shown.indices.contains(p), dragging != .zero {
                            shown[p] = shown[p].moved(by: CGSize(width: dragging.width / plate.width, height: dragging.height / plate.height))
                        }
                        if let live = sketch(plate) { shown.append(live) }
                        PhotoMarkPhone.draw(shown, in: plate, context: &c)
                        if let perspective { perspective.draw(in: plate, context: &c) }
                        if let p = picked, shown.indices.contains(p) {
                            let box = bounds(shown[p], plate).insetBy(dx: -8, dy: -8)
                            c.stroke(Path(box), with: .color(Color(markHex: "0A84FF")), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                        }
                    }
                    .allowsHitTesting(false)
                }
                // **Drawing with a finger, as on any touch screen** (his note,
                // 2026-10-17): one finger (or the Pencil) draws the moment it
                // touches, every coalesced point kept and the next ones
                // predicted; two fingers move and zoom, never draw; a tap
                // picks; three fingers undo (double-tap, or swipe left;
                // swipe right redoes).
                .overlay(PhotoTouchSurface(
                    down: { at in hand(.began(at), plate) },
                    move: { pts, ahead in hand(.moved(pts, ahead), plate) },
                    up: { at, tap in hand(.ended(at, tap), plate) },
                    cancel: { trail = []; predicted = []; dragFrom = nil; dragging = .zero },
                    two: { phase, scale, shift in
                        switch phase {
                        case .began: twoFingers = true; trail = []; predicted = []; dragFrom = nil; dragging = .zero; zoomFrom = zoom; panFrom = pan
                        case .changed:
                            zoom = min(max((zoomFrom ?? 1) * scale, 1), 6)
                            pan = CGSize(width: (panFrom ?? .zero).width + shift.width, height: (panFrom ?? .zero).height + shift.height)
                        default:
                            twoFingers = false; zoomFrom = nil; panFrom = nil
                            if zoom <= 1.01 { withAnimation(.easeOut(duration: 0.2)) { zoom = 1; pan = .zero } }
                        }
                    },
                    undo: { _ = session.undo(); reload() },
                    redo: { _ = session.redo(); reload() }))
            }
            .safeAreaInset(edge: .bottom) { bars }
            .navigationTitle("Draw on Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("photo.done") }
                ToolbarItem(placement: .cancellationAction) {
                    HStack {
                        Button { _ = session.undo(); reload() } label: { Image(systemName: "arrow.uturn.backward") }
                        Button { _ = session.redo(); reload() } label: { Image(systemName: "arrow.uturn.forward") }
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Words", isPresented: Binding(get: { typing != nil }, set: { if !$0 { typing = nil } })) {
                TextField("Words", text: $words)
                Button("Cancel", role: .cancel) { typing = nil }
                Button("Add") {
                    if let at = typing, !words.trimmingCharacters(in: .whitespaces).isEmpty {
                        marks.append(.words(at: at, text: words, look: look, size: PhotoMarkPhone.wordsSize))
                        picked = marks.count - 1
                        save()
                    }
                    typing = nil
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { reload() }
    }

    // ---- reading and writing --------------------------------------------------

    private func reload() {
        let r = DiagramPiece.read(plan, engine: session.engine)
        guard let p = r.els.first(where: { $0.id == photo }) else { return }
        marks = PhotoMarkPhone.parse(p.s("marks"))
        perspective = PhotoPerspectivePhone.parse(p.s("perspective"))
        strength = p.n("opacity", 1)
        if picked.map({ !marks.indices.contains($0) }) == true { picked = nil }
        if image == nil, !p.s("media").isEmpty { image = DiagramArt.image(p.s("media"), engine: session.engine) }
    }

    private func save() { edit(["op": "update", "ids": [photo], "set": ["marks": PhotoMarkPhone.encode(marks)]]) }

    private func savePerspective() {
        edit(["op": "update", "ids": [photo], "set": ["perspective": perspective?.encoded ?? ""]])
    }

    // ---- where it is ------------------------------------------------------------

    /// The fitted picture, zoomed and slid by two fingers.
    private func shownPlate(_ room: CGSize) -> CGRect {
        let f = fitted(room)
        let w = f.width * zoom, h = f.height * zoom
        return CGRect(x: f.midX - w / 2 + pan.width, y: f.midY - h / 2 + pan.height, width: w, height: h)
    }

    private func fitted(_ room: CGSize) -> CGRect {
        let ratio = image.map { $0.size.width / max($0.size.height, 1) } ?? 1.5
        let usable = CGSize(width: room.width - 16, height: room.height - 16)
        var w = usable.width, h = w / ratio
        if h > usable.height { h = usable.height; w = h * ratio }
        return CGRect(x: (room.width - w) / 2, y: (room.height - h) / 2, width: w, height: h)
    }

    private func frac(_ p: CGPoint, _ plate: CGRect) -> CGPoint {
        CGPoint(x: (p.x - plate.minX) / plate.width, y: (p.y - plate.minY) / plate.height)
    }

    private func bounds(_ m: PhotoMarkPhone, _ plate: CGRect) -> CGRect {
        switch m {
        case .arrow(let a):
            let pts = ([a.tail] + a.pins + [a.head]).map { PhotoMarkPhone.at($0, plate) }
            return pts.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
        case .shape(_, let a, let b, _, _, _):
            return CGRect(origin: PhotoMarkPhone.at(a, plate), size: .zero).union(CGRect(origin: PhotoMarkPhone.at(b, plate), size: .zero))
        case .draw(let pts, _, _):
            return pts.map { PhotoMarkPhone.at($0, plate) }.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
        case .words:
            return m.wordsBox(in: plate)
        }
    }

    /// What the finger is laying, before it is a mark.
    private func sketch(_ plate: CGRect) -> PhotoMarkPhone? {
        let trail = self.trail + predicted
        guard trail.count >= 2, let first = trail.first, let last = trail.last else { return nil }
        var a = frac(first, plate), b = frac(last, plate)
        if [.line, .arrow].contains(tool), let perspective { b = perspective.snapped(from: a, to: b, in: plate) }
        switch tool {
        case .arrow:
            var arrow = Engine.Arrow(x1: a.x, y1: a.y, x2: b.x, y2: b.y)
            arrow.look = look
            return .arrow(arrow)
        case .line: return .shape(.line, a: a, b: b, look: look, thick: 1, dashed: false)
        case .box: return .shape(.box, a: a, b: b, look: look, thick: 1, dashed: false)
        case .oval: return .shape(.oval, a: a, b: b, look: look, thick: 1, dashed: false)
        case .draw:
            var pts: [CGPoint] = []
            for p in trail where pts.last.map({ hypot(($0.x - frac(p, plate).x) * plate.width, ($0.y - frac(p, plate).y) * plate.height) > 4 }) ?? true {
                pts.append(frac(p, plate))
            }
            a = pts.first ?? a
            return pts.count >= 2 ? .draw(Array(pts.prefix(PhotoMarkPhone.mostPoints)), look: look, thick: 1) : nil
        default: return nil
        }
    }

    // ---- touch --------------------------------------------------------------------

    private func pick(_ at: CGPoint, _ plate: CGRect) -> Int? {
        var best: (Int, CGFloat)?
        for (i, m) in marks.enumerated() {
            let d = m.distance(from: at, in: plate)
            if d < 24, d <= (best?.1 ?? .infinity) { best = (i, d) }
        }
        return best?.0
    }

    private func tapped(_ at: CGPoint, _ plate: CGRect) {
        switch tool {
        case .words:
            words = ""
            typing = frac(at, plate)
        case .perspective:
            let f = frac(at, plate)
            if perspective == nil { perspective = PhotoPerspectivePhone(horizon: f.y, vanish: nil) }
            else { perspective?.vanish = f.x }
            savePerspective()
        default:
            picked = pick(at, plate)
        }
    }

    enum Touch { case began(CGPoint), moved([CGPoint], [CGPoint]), ended(CGPoint, Bool) }

    /// One finger on the picture, from `PhotoTouchSurface`.
    private func hand(_ t: Touch, _ plate: CGRect) {
        switch t {
        case .began(let at):
            strokeStart = at
            trail = [at]
            predicted = []
            changed(Stroke(start: at, location: at), plate)
        case .moved(let pts, let ahead):
            guard let s = strokeStart, let last = pts.last else { return }
            if ![.select, .perspective, .words].contains(tool) { trail.append(contentsOf: pts.dropLast()) }
            predicted = [.select, .perspective, .words].contains(tool) ? [] : ahead
            changed(Stroke(start: s, location: last), plate)
        case .ended(let at, let tap):
            predicted = []
            guard let s = strokeStart else { return }
            strokeStart = nil
            if tap {
                trail = []; dragFrom = nil; dragging = .zero
                tapped(at, plate)
            } else {
                ended(Stroke(start: s, location: at), plate)
            }
        }
    }

    /// A finger's way across the picture: where it began and where it is.
    struct Stroke {
        var start: CGPoint
        var location: CGPoint
        var startLocation: CGPoint { start }
        var translation: CGSize { CGSize(width: location.x - start.x, height: location.y - start.y) }
    }

    private func changed(_ v: Stroke, _ plate: CGRect) {
        switch tool {
        case .select:
            if dragFrom == nil {
                dragFrom = v.startLocation
                if let hit = pick(v.startLocation, plate) { picked = hit } else { picked = nil }
            }
            if picked != nil { dragging = v.translation }
        case .perspective:
            let f = frac(v.location, plate)
            if perspective == nil { perspective = PhotoPerspectivePhone(horizon: f.y, vanish: nil) }
            // Near the vanishing point it slides along the horizon; else the horizon moves.
            if let vp = perspective?.vanish, abs((vp - Double(frac(v.startLocation, plate).x)) * plate.width) < 30,
               abs((perspective!.horizon - Double(frac(v.startLocation, plate).y)) * plate.height) < 30 {
                perspective?.vanish = f.x
            } else {
                perspective?.horizon = f.y
            }
        case .words:
            break
        default:
            trail.append(v.location)
        }
    }

    private func ended(_ v: Stroke, _ plate: CGRect) {
        defer { trail = []; dragFrom = nil; dragging = .zero }
        switch tool {
        case .select:
            if let p = picked, marks.indices.contains(p), dragging != .zero {
                marks[p] = marks[p].moved(by: CGSize(width: dragging.width / plate.width, height: dragging.height / plate.height))
                save()
            }
        case .perspective:
            savePerspective()
        case .words:
            break
        default:
            if let m = sketch(plate) {
                marks.append(m)
                picked = marks.count - 1
                save()
            }
        }
    }

    // ---- the bars -----------------------------------------------------------------

    private static let amber = Color(red: 0.89, green: 0.63, blue: 0.23)
    private static let amberInk = Color(red: 0.11, green: 0.08, blue: 0.03)
    private static let looks: [(String, Engine.Arrow.Look)] = [("light", .light), ("dark", .dark), ("red", .red), ("yellow", .yellow)]

    /// **The bars** (refined 2026-10-17): every control named, 44-point
    /// targets, the picked tool filled amber.
    private var bars: some View {
        VStack(spacing: 8) {
            // One height whatever row shows, so the picture never jumps.
            Group {
            if let p = picked, marks.indices.contains(p) {
                markBar(p)
            } else if tool == .perspective {
                HStack(spacing: 10) {
                    Text("Guides").font(.kitBody).foregroundStyle(.white.opacity(0.75))
                    Picker("Guides", selection: Binding(get: { perspective == nil ? "off" : perspective?.vanish == nil ? "horizon" : "point" },
                                                        set: { v in
                        switch v {
                        case "off": perspective = nil
                        case "horizon": perspective = PhotoPerspectivePhone(horizon: perspective?.horizon ?? 0.42, vanish: nil)
                        default: perspective = PhotoPerspectivePhone(horizon: perspective?.horizon ?? 0.42, vanish: perspective?.vanish ?? 0.5)
                        }
                        savePerspective()
                    })) {
                        Text("Off").tag("off"); Text("Horizon").tag("horizon"); Text("+ Point").tag("point")
                    }
                    .pickerStyle(.segmented)
                }
            } else {
                HStack(spacing: 10) {
                    Text("Photo").font(.kitBody).foregroundStyle(.white.opacity(0.75))
                    Slider(value: $strength, in: 0.1...1) { done in
                        if !done { edit(["op": "update", "ids": [photo], "set": ["opacity": (strength * 100).rounded() / 100]]) }
                    }
                    Text("\(Int((strength * 100).rounded()))%").font(.kitBody).monospacedDigit().foregroundStyle(.white.opacity(0.75))
                        .frame(width: 44, alignment: .trailing)
                }
            }
            }
            .frame(height: 44)
            HStack(spacing: 2) {
                ForEach(Self.looks, id: \.0) { word, l in
                    Button {
                        lookWord = word
                        if let p = picked, marks.indices.contains(p) { marks[p] = marks[p].with(look: l); save() }
                    } label: {
                        Circle().fill(PhotoMarkPhone.colours(l).fill)
                            .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                            .frame(width: 24, height: 24)
                            .padding(3)
                            .overlay(Circle().stroke(lookWord == word ? Self.amber : .clear, lineWidth: 2.5))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(word.capitalized)
                }
                Text(lookWord.capitalized).font(.kitBody).foregroundStyle(.white.opacity(0.75)).lineLimit(1).fixedSize()
                Spacer(minLength: 8)
                if picked == nil, !marks.isEmpty {
                    Button("Clear All…") { clearing = true }.font(.kitBody.weight(.semibold)).frame(minHeight: 44)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PhotoToolPhone.allCases) { t in
                        Button { tool = t; if t != .select { picked = nil } } label: {
                            VStack(spacing: 2) {
                                Image(systemName: t.symbol).font(.system(size: 17, weight: .semibold))
                                Text(t.title).font(.kitLabel).lineLimit(1).fixedSize()
                            }
                            .foregroundStyle(tool == t ? Self.amberInk : Color.white)
                            .frame(width: 64, height: 48)
                            .background(RoundedRectangle(cornerRadius: Kit.Radius.control, style: .continuous)
                                .fill(tool == t ? Self.amber : Color.white.opacity(0.12)))
                        }
                        .accessibilityIdentifier("photo.tool.\(t.rawValue)")
                        .accessibilityLabel(t.title)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black)
        .confirmationDialog("Clear all marks on this photo?", isPresented: $clearing, titleVisibility: .visible) {
            Button("Clear All", role: .destructive) { marks = []; picked = nil; save() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Undo brings them back.") }
    }

    private func markBar(_ p: Int) -> some View {
        let m = marks[p]
        return HStack(spacing: 12) {
            Text(kindWord(m)).foregroundStyle(.white)
            if case .words = m {
                Button("Edit Words") {
                    if case .words(let at, let text, _, _) = m { words = text; marks.remove(at: p); picked = nil; typing = at }
                }
            } else {
                Button { marks[p] = m.with(thick: m.thick - 0.5); save() } label: { Image(systemName: "minus").frame(width: 44, height: 44) }
                    .accessibilityLabel("Thinner")
                Text(String(format: "%.1f×", m.thick)).font(.kitBody).monospacedDigit().foregroundStyle(.white.opacity(0.75))
                Button { marks[p] = m.with(thick: m.thick + 0.5); save() } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                    .accessibilityLabel("Thicker")
                if case .shape(.line, let a, let b, let l, let t, let d) = m {
                    Button(d ? "Solid" : "Dashed") { marks[p] = .shape(.line, a: a, b: b, look: l, thick: t, dashed: !d); save() }
                }
            }
            Spacer()
            Button(role: .destructive) { marks.remove(at: p); picked = nil; save() } label: { Label("Delete", systemImage: "trash").frame(minHeight: 44) }
        }
        .font(.kitBody.weight(.semibold))
    }
}

private func kindWord(_ m: PhotoMarkPhone) -> String {
    switch m {
    case .arrow: return "Arrow"
    case .shape(let k, _, _, _, _, _): return k == .line ? "Line" : k == .box ? "Box" : "Oval"
    case .draw: return "Drawing"
    case .words: return "Words"
    }
}

/// **The picture under the finger** (2026-10-17, his note: *"the draw feature
/// better work like drawing with your finger normally on a touch screen"*).
/// UIKit touches, so a stroke starts the instant a finger or the Pencil
/// lands, takes every coalesced point the screen measured, and runs ahead
/// with the predicted ones. A second finger turns it into a move-and-zoom;
/// a short touch that barely moves is a tap. Three fingers undo.
struct PhotoTouchSurface: UIViewRepresentable {
    enum Phase { case began, changed, ended }
    let down: (CGPoint) -> Void
    let move: ([CGPoint], [CGPoint]) -> Void
    let up: (CGPoint, Bool) -> Void
    let cancel: () -> Void
    let two: (Phase, CGFloat, CGSize) -> Void
    let undo: () -> Void
    let redo: () -> Void

    func makeUIView(context: Context) -> Surface {
        let v = Surface()
        v.owner = self
        return v
    }
    func updateUIView(_ v: Surface, context: Context) { v.owner = self }

    final class Surface: UIView {
        var owner: PhotoTouchSurface?
        private var drawing: UITouch?
        private var began: (at: CGPoint, time: TimeInterval)?
        private var travelled: CGFloat = 0
        private var pair: (dist: CGFloat, mid: CGPoint)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isMultipleTouchEnabled = true
            backgroundColor = .clear
            let three = UITapGestureRecognizer(target: self, action: #selector(undoTap))
            three.numberOfTouchesRequired = 3
            three.numberOfTapsRequired = 2
            addGestureRecognizer(three)
            for (dir, sel) in [(UISwipeGestureRecognizer.Direction.left, #selector(undoTap)), (.right, #selector(redoSwipe))] {
                let sw = UISwipeGestureRecognizer(target: self, action: sel)
                sw.numberOfTouchesRequired = 3
                sw.direction = dir
                addGestureRecognizer(sw)
            }
        }
        required init?(coder: NSCoder) { fatalError() }

        @objc private func undoTap() { owner?.undo() }
        @objc private func redoSwipe() { owner?.redo() }

        private func live(_ e: UIEvent?) -> [UITouch] {
            (e?.allTouches ?? []).filter { $0.phase != .ended && $0.phase != .cancelled && $0.view === self }
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            let now = live(event)
            if now.count >= 2 {
                // A second finger: whatever the first began is let go.
                if drawing != nil { drawing = nil; owner?.cancel() }
                if pair == nil, now.count == 2 {
                    let a = now[0].location(in: self), b = now[1].location(in: self)
                    pair = (hypot(a.x - b.x, a.y - b.y), CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2))
                    owner?.two(.began, 1, .zero)
                }
                return
            }
            guard drawing == nil, pair == nil, let t = touches.first else { return }
            drawing = t
            let at = t.location(in: self)
            began = (at, t.timestamp)
            travelled = 0
            owner?.down(at)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            if let p = pair {
                let now = live(event)
                guard now.count >= 2 else { return }
                let a = now[0].location(in: self), b = now[1].location(in: self)
                let d = hypot(a.x - b.x, a.y - b.y)
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                owner?.two(.changed, p.dist > 1 ? d / p.dist : 1, CGSize(width: mid.x - p.mid.x, height: mid.y - p.mid.y))
                return
            }
            guard let t = drawing, touches.contains(t) else { return }
            let pts = (event?.coalescedTouches(for: t) ?? [t]).map { $0.location(in: self) }
            let ahead = (event?.predictedTouches(for: t) ?? []).map { $0.location(in: self) }
            if let b = began, let last = pts.last { travelled = max(travelled, hypot(last.x - b.at.x, last.y - b.at.y)) }
            owner?.move(pts, ahead)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            if pair != nil {
                if live(event).count < 2 { pair = nil; owner?.two(.ended, 1, .zero) }
                return
            }
            guard let t = drawing, touches.contains(t) else { return }
            drawing = nil
            let at = t.location(in: self)
            let quick = began.map { t.timestamp - $0.time < 0.35 } ?? false
            owner?.up(at, travelled < 6 && quick)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            if pair != nil { pair = nil; owner?.two(.ended, 1, .zero) }
            if drawing != nil { drawing = nil; owner?.cancel() }
        }
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
