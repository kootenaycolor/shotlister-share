import AppKit
import SwiftUI

/// **Drawing on a picture on the plan** — his ask, 2026-10-15, approved from
/// the mockup (B · Annotating on photos): double-click a photo to draw on it.
/// While he draws, the picture shows at full strength and the plan steps
/// back; what he draws is pinned to the picture (`PhotoMarks.swift`), so
/// moving or sizing the picture carries it. Plain drawing tools, no snapping
/// to the plan's grid or walls; Perspective puts a horizon and a vanishing
/// point on it, and lines and arrows follow their guides. Done (or Escape)
/// goes back to the plan.

enum PhotoTool: String, CaseIterable, Identifiable {
    case select, arrow, line, box, oval, draw, words, perspective
    var id: String { rawValue }
    var title: String { rawValue == "box" ? "Box" : rawValue.capitalized }
    /// The key that picks it (2026-10-17: shown on its button).
    var key: String {
        switch self {
        case .select: return "V"
        case .words: return "T"
        default: return String(rawValue.prefix(1)).uppercased()
        }
    }
    /// The tools that lay a mark.
    static let drawing: [PhotoTool] = [.arrow, .line, .box, .oval, .draw, .words]
}

extension DiagramModel {
    /// The picture being drawn on, as the plan holds it now.
    var photoEl: DiagramEl? { photoEditing.flatMap { el($0) } }

    /// Its marks, as stored.
    var photoMarks: [PhotoMark] { PhotoMark.parse(photoEl?.marks) }

    var photoPerspective: PhotoPerspective? { PhotoPerspective.parse(photoEl?.perspective) }

    /// **The look new marks are drawn in**, remembered across plans.
    var photoLook: ViewModel.Arrow.Look {
        get { ViewModel.Arrow.Look(rawValue: UserDefaults.standard.string(forKey: "photoMarkLook") ?? "") ?? .yellow }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "photoMarkLook"); objectWillChange.send() }
    }

    /// **Draw on Photo**: into the picture, the view fitted round it.
    func drawOnPhoto(_ id: String) {
        guard !readOnly, !presenting, let e = el(id), e.kind == "image" else { return }
        if typing != nil { endTyping(keep: true) }
        photoReturnView = (centre, scale)
        // Details steps aside while he draws (`detailsOpen`), and is back after.
        selection = []
        tool = .select
        // The picture fills the plan with room for the bars above and below.
        if let size = canvas?.bounds.size, size.width > 100, size.height > 100 {
            let r = e.rot * .pi / 180
            let bw = abs(e.w * cos(r)) + abs(e.h * sin(r)), bh = abs(e.w * sin(r)) + abs(e.h * cos(r))
            let fit = min((size.width - 80) / max(bw, 0.05), (size.height - 190) / max(bh, 0.05))
            scale = max(min(fit, 2000), 4)
            centre = CGPoint(x: e.x, y: e.y + 6 / Double(scale))
        }
        photoPicked = nil
        photoTool = .select
        photoStrengthPreview = nil
        photoHand.reset()
        photoEditing = id
        PhotoScroll.start(self)
        canvas?.needsDisplay = true
    }

    /// **Done**: back to the plan as it was, the picture picked.
    func endPhoto() {
        guard let id = photoEditing else { return }
        photoHand.commitWords(self)
        photoHand.reset()
        PhotoScroll.stop()
        photoEditing = nil
        photoPicked = nil
        photoStrengthPreview = nil
        if let back = photoReturnView { centre = back.centre; scale = back.scale }
        photoReturnView = nil
        if el(id) != nil { selection = [id] }
        canvas?.needsDisplay = true
    }

    /// Keep the picture's marks.
    func savePhotoMarks(_ marks: [PhotoMark], label: String = "Draw on Photo") {
        guard let id = photoEditing else { return }
        update([id], ["marks": PhotoMark.encode(marks)])
    }

    func setPhotoPerspective(_ p: PhotoPerspective?) {
        guard let id = photoEditing else { return }
        update([id], ["perspective": p?.encoded ?? ""])
    }

    /// **How many marks lie wholly on a picture** — what Attach to Photo
    /// would move onto it (`photomarks::attach`).
    func marksLyingOn(_ photo: DiagramEl) -> Int {
        guard photo.w > 0, photo.h > 0 else { return 0 }
        let r = photo.rot * .pi / 180
        let (c, s) = (cos(r), sin(r))
        func on(_ x: Double, _ y: Double) -> Bool {
            let dx = x - photo.x, dy = y - photo.y
            let lx = dx * c + dy * s, ly = -dx * s + dy * c
            return abs(lx) <= photo.w / 2 + 0.001 && abs(ly) <= photo.h / 2 + 0.001
        }
        return plan.els.filter { e in
            guard e.id != photo.id, !e.hidden, !e.locked else { return false }
            switch e.kind {
            case "arrow": return on(e.x, e.y) && on(e.x2, e.y2)
            case "shape":
                let rr = e.rot * .pi / 180
                return [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)].allSatisfy { sx, sy in
                    let lx = sx * e.w / 2, ly = sy * e.h / 2
                    return on(e.x + lx * cos(rr) - ly * sin(rr), e.y + lx * sin(rr) + ly * cos(rr))
                }
            case "stroke": return e.points.count >= 2 && e.points.allSatisfy { $0.count >= 2 && on($0[0], $0[1]) }
            case "text": return !e.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSharedLabel(e) && on(e.x, e.y)
            default: return false
            }
        }.count
    }

    /// **Attach to Photo**: the marks lying on it moved onto it, one undo.
    func attachMarks(to id: String) {
        let n = el(id).map(marksLyingOn) ?? 0
        guard n > 0 else { return }
        edit(["op": "attach_marks", "id": id])
        flash(n == 1 ? "1 Mark Attached" : "\(n) Marks Attached")
    }

    /// **The keys while drawing on a picture**, ahead of the plan's own:
    /// Delete takes the picked mark (never the picture), Escape lets go of
    /// it and then leaves.
    func photoKey(_ e: NSEvent) -> Bool {
        guard photoEditing != nil, let window = canvas?.window, e.window === window else { return false }
        if window.firstResponder is NSText || window.firstResponder is NSTextField { return false }
        let mods = e.modifierFlags.intersection([.command, .control, .option])
        if e.keyCode == 53 {
            if photoPicked != nil { photoPicked = nil } else { endPhoto() }
            return true
        }
        if [51, 117].contains(e.keyCode), mods.isEmpty {
            if let i = photoPicked {
                var marks = photoMarks
                if marks.indices.contains(i) { marks.remove(at: i); savePhotoMarks(marks) }
                photoPicked = nil
            }
            return true
        }
        // **Arrow keys nudge the picked mark** (2026-10-17): a point, ten with ⇧.
        if [123, 124, 125, 126].contains(e.keyCode), mods.isEmpty, let i = photoPicked, let p = photoEl {
            let step = (e.modifierFlags.contains(.shift) ? 10.0 : 1.0) / max(Double(scale), 1)
            let dx = e.keyCode == 123 ? -step : e.keyCode == 124 ? step : 0
            let dy = e.keyCode == 126 ? -step : e.keyCode == 125 ? step : 0
            var marks = photoMarks
            if marks.indices.contains(i) {
                marks[i] = marks[i].moved(by: CGSize(width: dx / max(p.w, 0.01), height: dy / max(p.h, 0.01)))
                savePhotoMarks(marks, label: "Nudge")
            }
            return true
        }
        // Space is held to move the view (`PhotoHand.panning`), not a tool.
        if e.keyCode == 49 { return true }
        if mods.isEmpty, let ch = e.charactersIgnoringModifiers?.lowercased() {
            let keys: [String: PhotoTool] = ["v": .select, "a": .arrow, "l": .line, "b": .box, "o": .oval, "d": .draw, "t": .words, "p": .perspective]
            if let t = keys[ch] { photoTool = t; return true }
        }
        // ⌘Z and the rest go on to the app.
        return mods.contains(.command) ? false : true
    }
}

/// **Two fingers move the view, a pinch zooms** (2026-10-17), over the
/// picture as over the plan: the picture's hand would otherwise swallow
/// them. Scrolls and pinches inside the canvas go straight to it.
enum PhotoScroll {
    private static var monitor: Any?
    static func start(_ m: DiagramModel) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak m] e in
            guard let m, m.photoEditing != nil, let v = m.canvas, e.window === v.window else { return e }
            let p = v.convert(e.locationInWindow, from: nil)
            guard v.bounds.contains(p), v.window?.contentView?.hitTest(e.locationInWindow) !== v else { return e }
            if e.type == .magnify { v.magnify(with: e) } else { v.scrollWheel(with: e) }
            return nil
        }
    }
    static func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

// MARK: - the overlay

/// **The hand on the picture**: laid exactly over it, turned with it, so a
/// point under the pointer is a point of the photograph.
struct PhotoEditor: View {
    @ObservedObject var model: DiagramModel
    @ObservedObject var hand: PhotoHand
    let id: String
    @FocusState private var typing: Bool

    init(model: DiagramModel, id: String) {
        self.model = model
        self.hand = model.photoHand
        self.id = id
    }

    var body: some View {
        GeometryReader { g in
            if let e = model.el(id) {
                let size = CGSize(width: max(CGFloat(e.w) * model.scale, 1), height: max(CGFloat(e.h) * model.scale, 1))
                let c = model.toView(CGPoint(x: e.x, y: e.y), size: g.size)
                let plate = CGRect(origin: .zero, size: size)
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, _ in
                        var ctx = ctx
                        if let p = hand.perspective(model) {
                            // Guides step back while the tool on has no use for them (2026-10-17).
                            var g = ctx
                            if [.box, .oval, .draw, .words].contains(model.photoTool) { g.opacity = 0.35 }
                            p.draw(in: plate, context: &g, showPoint: p.vanish != nil)
                        }
                        PhotoMark.draw(hand.shown(model), in: plate, context: &ctx)
                        hand.drawHandles(model, in: plate, &ctx)
                    }
                    .frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { move in
                            // **One gesture per job** (2026-10-17): with Space held
                            // the drag moves the view, whatever tool is on.
                            if hand.panFrom != nil || (hand.panFrom == nil && !hand.isDown && PhotoHand.spaceHeld) {
                                hand.pan(model, by: move.translation)
                                return
                            }
                            hand.moved(model, from: local(move.startLocation, e, g, c, size), to: local(move.location, e, g, c, size), plate)
                        }
                        .onEnded { move in
                            if hand.panFrom != nil { hand.panFrom = nil; return }
                            hand.ended(model, from: local(move.startLocation, e, g, c, size), to: local(move.location, e, g, c, size), plate)
                        })
                    .onContinuousHover { phase in
                        if case .active = phase { (PhotoHand.spaceHeld ? NSCursor.openHand : cursor).set() } else { NSCursor.arrow.set() }
                    }
                    if let w = hand.words {
                        wordsField(w, plate)
                    }
                }
                .frame(width: size.width, height: size.height)
                .rotationEffect(.degrees(e.rot))
                .position(c)
            }
        }
        .onChange(of: model.photoTool) { _, _ in hand.commitWords(model) }
        .onDisappear { hand.commitWords(model) }
    }

    /// A point in the window, as a point of the picture's own drawn plate:
    /// the drag reads the window so a pan can move the plate under it.
    private func local(_ p: CGPoint, _ e: DiagramEl, _ g: GeometryProxy, _ c: CGPoint, _ size: CGSize) -> CGPoint {
        let frame = g.frame(in: .global)
        let v = CGPoint(x: p.x - frame.minX - c.x, y: p.y - frame.minY - c.y)
        let r = -e.rot * .pi / 180
        return CGPoint(x: v.x * cos(r) - v.y * sin(r) + size.width / 2, y: v.x * sin(r) + v.y * cos(r) + size.height / 2)
    }

    private var cursor: NSCursor {
        switch model.photoTool {
        case .select: return .arrow
        case .words: return .iBeam
        case .perspective: return .openHand
        default: return .crosshair
        }
    }

    @ViewBuilder
    private func wordsField(_ w: PhotoHand.WordsDraft, _ plate: CGRect) -> some View {
        let h = max(CGFloat(PhotoMark.wordsSize) * plate.height, 11)
        let stored = model.photoMarks
        let look = w.index.flatMap { stored.indices.contains($0) ? stored[$0].look : nil } ?? model.photoLook
        TextField("", text: Binding(get: { hand.words?.text ?? "" }, set: { hand.words?.text = $0 }))
            .textFieldStyle(.plain)
            .font(.system(size: h, weight: .bold))
            .foregroundStyle(look.fill)
            .focused($typing)
            .frame(minWidth: 120, maxWidth: max(plate.width - PhotoMark.at(w.at, plate).x - 4, 60), alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 3)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(nsColor: DiagramInk.pick), lineWidth: 1.2))
            .offset(x: PhotoMark.at(w.at, plate).x - 3, y: PhotoMark.at(w.at, plate).y)
            .onSubmit { hand.commitWords(model) }
            .onAppear { DispatchQueue.main.async { typing = true } }
    }
}

/// **What the hand is doing on a picture** — kept apart from the view so a
/// checking run can drive the same road a drag takes (a synthetic mouse
/// cannot drive a SwiftUI drag): `moved` while the hand is down, `ended`
/// when it lifts, points in the picture's own drawn rectangle.
final class PhotoHand: ObservableObject {
    @Published var drafted: [PhotoMark]?
    @Published var drawing: PhotoMark?
    @Published var guide: PhotoPerspective?
    @Published var words: WordsDraft?
    private var trail: [CGPoint] = []
    private var grab: Grab?
    private var lastClick: (time: Date, point: CGPoint)?
    private var down = false
    var isDown: Bool { down }
    /// Where the view stood when a Space-drag began (2026-10-17).
    var panFrom: CGPoint?

    /// Space held down, read from the keyboard itself.
    static var spaceHeld: Bool { CGEventSource.keyState(.combinedSessionState, key: 49) }

    /// The view slid with the hand, the picture and its marks with it.
    func pan(_ m: DiagramModel, by t: CGSize) {
        if panFrom == nil { panFrom = m.centre }
        guard let from = panFrom else { return }
        let k = max(Double(m.scale), 0.001)
        m.centre = CGPoint(x: from.x - t.width / k, y: from.y - t.height / k)
        m.canvas?.needsDisplay = true
    }

    private enum Grab: Equatable { case whole(CGPoint), handle(Int), horizon, vanish }
    struct WordsDraft: Equatable { var at: CGPoint; var text: String; var index: Int? }

    func marks(_ m: DiagramModel) -> [PhotoMark] { drafted ?? m.photoMarks }
    func shown(_ m: DiagramModel) -> [PhotoMark] { drawing.map { marks(m) + [$0] } ?? marks(m) }
    func perspective(_ m: DiagramModel) -> PhotoPerspective? { guide ?? m.photoPerspective }

    func reset() { drafted = nil; drawing = nil; guide = nil; words = nil; trail = []; grab = nil; down = false }

    private func frac(_ p: CGPoint, _ plate: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x / max(plate.width, 1), 0), 1), y: min(max(p.y / max(plate.height, 1), 0), 1))
    }

    func moved(_ m: DiagramModel, from start: CGPoint, to point: CGPoint, _ plate: CGRect) {
        if !down { down = true; begin(m, start, plate) }
        carry(m, point, plate)
    }

    func ended(_ m: DiagramModel, from start: CGPoint, to point: CGPoint, _ plate: CGRect) {
        if !down { begin(m, start, plate) }
        carry(m, point, plate)
        finish(m, travelled: hypot(point.x - start.x, point.y - start.y), at: point, plate)
        down = false
    }

    func commitWords(_ m: DiagramModel) {
        guard let w = words else { return }
        words = nil
        let stored = m.photoMarks
        var next = stored
        let text = w.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = w.index, next.indices.contains(i) {
            if text.isEmpty { next.remove(at: i); m.photoPicked = nil }
            else if case .words(let at, _, let look, let size) = next[i] { next[i] = .words(at: at, text: text, look: look, size: size) }
        } else if !text.isEmpty {
            next.append(.words(at: w.at, text: text, look: m.photoLook, size: PhotoMark.wordsSize))
            m.photoPicked = next.count - 1
        }
        if next != stored { m.savePhotoMarks(next) }
    }

    /// The handles of a mark, by number, where they stand.
    func handleSpots(_ mk: PhotoMark, _ plate: CGRect) -> [CGPoint] {
        switch mk {
        case .arrow(let a): return [a.tail, a.head].map { PhotoMark.at($0, plate) }
        case .shape(.line, let a, let b, _, _, _): return [a, b].map { PhotoMark.at($0, plate) }
        case .shape(_, let a, let b, _, _, _):
            return [a, CGPoint(x: b.x, y: a.y), b, CGPoint(x: a.x, y: b.y)].map { PhotoMark.at($0, plate) }
        default: return []
        }
    }

    private func begin(_ m: DiagramModel, _ point: CGPoint, _ plate: CGRect) {
        if words != nil { commitWords(m) }
        let tool = m.photoTool
        let f = frac(point, plate)
        let stored = m.photoMarks
        if tool == .perspective {
            let p = m.photoPerspective ?? PhotoPerspective(horizon: Double(f.y), vanish: Double(f.x))
            let y = CGFloat(p.horizon) * plate.height
            if let v = p.vanish, hypot(point.x - CGFloat(v) * plate.width, point.y - y) < 14 { grab = .vanish }
            else if abs(point.y - y) < 10 { grab = .horizon }
            else { grab = p.vanish != nil ? .vanish : .horizon }
            guide = p
            return
        }
        drafted = stored
        if let i = m.photoPicked, stored.indices.contains(i),
           let k = handleSpots(stored[i], plate).firstIndex(where: { hypot($0.x - point.x, $0.y - point.y) < 9 }) {
            grab = .handle(k)
            return
        }
        if tool == .select {
            if let hit = stored.indices.reversed().first(where: { stored[$0].distance(from: point, in: plate) < 9 }) {
                m.photoPicked = hit
                grab = .whole(f)
            } else {
                m.photoPicked = nil
            }
            return
        }
        if tool == .words { return }
        m.photoPicked = nil
        let look = m.photoLook
        switch tool {
        case .arrow:
            var a = ViewModel.Arrow.straight(f.x, f.y, f.x, f.y)
            a.look = look
            a.thickness = ArrowThickness.remembered()
            drawing = .arrow(a)
        case .line: drawing = .shape(.line, a: f, b: f, look: look, thick: 1, dashed: false)
        case .box: drawing = .shape(.box, a: f, b: f, look: look, thick: 1, dashed: false)
        case .oval: drawing = .shape(.oval, a: f, b: f, look: look, thick: 1, dashed: false)
        case .draw:
            trail = [f]
            drawing = .draw([f], look: look, thick: 1)
        default: break
        }
    }

    private func carry(_ m: DiagramModel, _ point: CGPoint, _ plate: CGRect) {
        let f = frac(point, plate)
        if var p = guide {
            switch grab {
            case .vanish: p.horizon = Double(f.y); p.vanish = Double(f.x)
            default: p.horizon = Double(f.y)
            }
            guide = p
            return
        }
        let persp = m.photoPerspective
        if let made = drawing {
            let snap = { (a: CGPoint) -> CGPoint in persp?.snapped(from: a, to: f, in: plate) ?? f }
            switch made {
            case .arrow(var a):
                let end = snap(a.tail)
                a.x2 = end.x; a.y2 = end.y
                drawing = .arrow(a)
            case .shape(.line, let a, _, let l, let t, let d): drawing = .shape(.line, a: a, b: snap(a), look: l, thick: t, dashed: d)
            case .shape(let k, let a, _, let l, let t, let d): drawing = .shape(k, a: a, b: f, look: l, thick: t, dashed: d)
            case .draw(_, let l, let t):
                if let last = trail.last, hypot((f.x - last.x) * plate.width, (f.y - last.y) * plate.height) >= 2.5,
                   trail.count < PhotoMark.mostPoints {
                    trail.append(f)
                }
                drawing = .draw(trail + [f], look: l, thick: t)
            default: break
            }
            return
        }
        guard let grab, var working = drafted, let i = m.photoPicked, working.indices.contains(i) else { return }
        switch grab {
        case .whole(let from):
            working[i] = working[i].moved(by: CGSize(width: f.x - from.x, height: f.y - from.y))
            self.grab = .whole(f)
        case .handle(let k):
            switch working[i] {
            case .arrow(let a):
                working[i] = .arrow(a.movingEnd(head: k == 1, to: f))
            case .shape(.line, let a, let b, let l, let t, let d):
                let end = persp?.snapped(from: k == 0 ? b : a, to: f, in: plate) ?? f
                working[i] = .shape(.line, a: k == 0 ? end : a, b: k == 1 ? end : b, look: l, thick: t, dashed: d)
            case .shape(let kind, var a, var b, let l, let t, let d):
                if k == 0 || k == 3 { a.x = f.x } else { b.x = f.x }
                if k == 0 || k == 1 { a.y = f.y } else { b.y = f.y }
                working[i] = .shape(kind, a: a, b: b, look: l, thick: t, dashed: d)
            default: break
            }
        default: break
        }
        drafted = working
    }

    private func finish(_ m: DiagramModel, travelled: CGFloat, at point: CGPoint, _ plate: CGRect) {
        defer { drafted = nil; grab = nil; trail = [] }
        let stored = m.photoMarks
        if let p = guide {
            guide = nil
            m.setPhotoPerspective(p)
            return
        }
        if let made = drawing {
            drawing = nil
            guard travelled > 6 else { return }
            var next = stored
            next.append(made)
            m.photoPicked = next.count - 1
            m.savePhotoMarks(next)
            return
        }
        if travelled < 4 {
            noteClick(m, point, plate)
            return
        }
        guard grab != nil, let working = drafted, working != stored else { return }
        m.savePhotoMarks(working)
    }

    private func noteClick(_ m: DiagramModel, _ point: CGPoint, _ plate: CGRect) {
        let now = Date()
        let double = lastClick.map { now.timeIntervalSince($0.time) < NSEvent.doubleClickInterval && hypot(point.x - $0.point.x, point.y - $0.point.y) < 6 } ?? false
        lastClick = double ? nil : (now, point)
        let stored = m.photoMarks
        // Words: a click puts them there; double-clicked, words are typed over.
        if let i = stored.indices.reversed().first(where: { stored[$0].distance(from: point, in: plate) < 4 }),
           case .words(let at, let text, _, _) = stored[i], double || m.photoTool == .words {
            m.photoPicked = i
            words = WordsDraft(at: at, text: text, index: i)
            return
        }
        if m.photoTool == .words {
            words = WordsDraft(at: frac(point, plate), text: "", index: nil)
        }
    }

    func drawHandles(_ m: DiagramModel, in plate: CGRect, _ c: inout GraphicsContext) {
        let all = marks(m)
        guard drawing == nil, let i = m.photoPicked, all.indices.contains(i) else { return }
        let mk = all[i]
        let ink = Color(nsColor: DiagramInk.pick)
        switch mk {
        case .draw(let pts, _, _):
            let s = pts.map { PhotoMark.at($0, plate) }
            let xs = s.map(\.x), ys = s.map(\.y)
            if let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() {
                c.stroke(Path(CGRect(x: x0 - 5, y: y0 - 5, width: x1 - x0 + 10, height: y1 - y0 + 10)),
                         with: .color(ink), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        case .words:
            c.stroke(Path(mk.wordsBox(in: plate).insetBy(dx: -4, dy: -3)), with: .color(ink), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        default:
            for (k, p) in handleSpots(mk, plate).enumerated() {
                let r = CGRect(x: p.x - 5.5, y: p.y - 5.5, width: 11, height: 11)
                let head: Bool = { if case .arrow = mk { return k == 1 }; return false }()
                c.fill(Path(ellipseIn: r), with: .color(head ? ink : .white))
                c.stroke(Path(ellipseIn: r), with: .color(head ? .white : ink), lineWidth: 1.5)
            }
        }
    }
}

// MARK: - the bars

/// **The tools on a picture**, where the plan's toolbar was: Select, then
/// what a hand lays — Arrow, Line, Box, Oval, Draw, Words — then
/// Perspective, then Undo and Redo (2026-10-17: each with its key on it, the
/// picked one filled, a press darkening at once).
struct PhotoToolbar: View {
    @ObservedObject var model: DiagramModel
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        HStack(spacing: 2) {
            button(.select)
            rule
            ForEach(PhotoTool.drawing) { button($0) }
            rule
            button(.perspective)
            rule
            verb("Undo", "arrow.uturn.backward", help: "Undo (⌘Z)") { model.state?.undo() }
            verb("Redo", "arrow.uturn.forward", help: "Redo (⇧⌘Z)") { model.state?.redo() }
        }
        .padding(.horizontal, 6).frame(height: 54)
        .background(DiagramFloat(dark: dark, radius: 14))
        .fixedSize()
    }

    private var rule: some View {
        Rectangle().fill(Brand.rule2(dark)).frame(width: 1, height: 30).padding(.horizontal, 4)
    }

    private func button(_ tool: PhotoTool) -> some View {
        let on = model.photoTool == tool
        return Button {
            model.photoTool = tool
            if tool == .perspective, model.photoPerspective == nil {
                model.setPhotoPerspective(PhotoPerspective(horizon: 0.42, vanish: 0.5))
            }
        } label: {
            VStack(spacing: 3) {
                PhotoToolIcon(tool: tool, ink: on ? PhotoBar.onInk : nil).frame(width: 20, height: 20)
                Text(tool.title).sans(11, weight: on ? .semibold : .medium)
                    .foregroundStyle(on ? PhotoBar.onInk : Brand.ink2(dark))
                    .lineLimit(1).fixedSize()
            }
            .frame(width: tool == .perspective ? 76 : 52, height: 46)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? PhotoBar.on : Color.clear))
            .overlay(alignment: .topTrailing) {
                Text(tool.key).font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(on ? PhotoBar.onInk.opacity(0.6) : Brand.ink3(dark))
                    .padding(.top, 3).padding(.trailing, 5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PhotoPress())
        .help("\(tool.title) (\(tool.key))")
        .accessibilityLabel(tool.title)
    }

    private func verb(_ title: String, _ symbol: String, help: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium)).frame(width: 20, height: 20)
                Text(title).sans(11, weight: .medium).lineLimit(1).fixedSize()
            }
            .foregroundStyle(Brand.ink2(dark))
            .frame(width: 46, height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(PhotoPress())
        .help(help)
    }
}

/// The bars' shared look (2026-10-17): the picked tool filled in Studio's
/// amber, its words dark on it.
enum PhotoBar {
    static let on = Color(red: 0.89, green: 0.63, blue: 0.23)
    static let onInk = Color(red: 0.11, green: 0.08, blue: 0.03)
}

/// **A press shows at once**: the button darkens and gives a little while
/// held, with no wait.
struct PhotoPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// Each photo tool's picture, drawn (no stock glyphs in the Diagram).
struct PhotoToolIcon: View {
    let tool: PhotoTool
    var ink: Color?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { c, size in
            let ink = self.ink ?? Brand.ink(scheme == .dark)
            let s = min(size.width, size.height) / 20
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            let line = StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
            switch tool {
            case .select:
                var a = Path()
                a.move(to: p(6, 3)); a.addLine(to: p(15, 11)); a.addLine(to: p(10.8, 11.6)); a.addLine(to: p(13, 16))
                a.addLine(to: p(11.2, 16.8)); a.addLine(to: p(9, 12.3)); a.addLine(to: p(6, 15)); a.closeSubpath()
                c.fill(a, with: .color(ink))
            case .arrow:
                var a = Path(); a.move(to: p(4, 16)); a.addLine(to: p(15, 5))
                a.move(to: p(9, 5)); a.addLine(to: p(15, 5)); a.addLine(to: p(15, 11))
                c.stroke(a, with: .color(ink), style: line)
            case .line:
                var a = Path(); a.move(to: p(3, 17)); a.addLine(to: p(17, 3))
                c.stroke(a, with: .color(ink), style: line)
            case .box:
                c.stroke(Path(CGRect(x: 3.5 * s, y: 5 * s, width: 13 * s, height: 10 * s)), with: .color(ink), style: line)
            case .oval:
                c.stroke(Path(ellipseIn: CGRect(x: 3 * s, y: 4.5 * s, width: 14 * s, height: 11 * s)), with: .color(ink), style: line)
            case .draw:
                var a = Path(); a.move(to: p(3, 14))
                a.addCurve(to: p(11, 11), control1: p(6, 8), control2: p(8, 16))
                a.addCurve(to: p(17, 7), control1: p(14, 6), control2: p(15, 6))
                c.stroke(a, with: .color(ink), style: line)
            case .words:
                c.draw(Text("Aa").font(.system(size: 12 * s, weight: .bold)).foregroundColor(ink), at: p(10, 10))
            case .perspective:
                var a = Path(); a.move(to: p(1, 9)); a.addLine(to: p(19, 9))
                c.stroke(a, with: .color(ink), style: line)
                var b = Path()
                b.move(to: p(10, 9)); b.addLine(to: p(3, 17)); b.move(to: p(10, 9)); b.addLine(to: p(17, 17))
                b.move(to: p(10, 9)); b.addLine(to: p(10, 17))
                c.stroke(b, with: .color(ink), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            }
        }
    }
}

/// **The bar at the foot while drawing on a picture** (refined 2026-10-17,
/// mockup claude.ai/artifact/CnWRuArKE5EkCFQ4s96g69): the photo's
/// strength, Guides as one choice, the color new marks take with its name,
/// Clear All, Done. With a mark picked: what it is, its color, its style,
/// thickness or size, a nudge, Delete, Done — every control named.
struct PhotoFootBar: View {
    @ObservedObject var model: DiagramModel
    @State private var thickDraft: Double?
    @State private var clearing = false
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    private var picked: (Int, PhotoMark)? {
        guard let i = model.photoPicked else { return nil }
        let m = model.photoMarks
        return m.indices.contains(i) ? (i, m[i]) : nil
    }

    var body: some View {
        HStack(spacing: 2) {
            if let (i, m) = picked { markControls(i, m) } else { photoControls }
            sep
            done
        }
        .padding(.horizontal, 8).frame(height: 38)
        .background(DiagramFloat(dark: dark, radius: 19, solid: true))
        .fixedSize()
        .alert("Clear all marks on this photo?", isPresented: $clearing) {
            Button("Clear All", role: .destructive) {
                model.photoPicked = nil
                model.savePhotoMarks([], label: "Clear All")
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Undo brings them back.") }
    }

    private var sep: some View {
        Rectangle().fill(Brand.rule2(dark)).frame(width: 1, height: 16).padding(.horizontal, 6)
    }

    private var done: some View {
        Button { model.endPhoto() } label: {
            Text("Done").sans(Brand.Size.body, weight: .semibold).foregroundStyle(dark ? Color.black : Color.white)
                .padding(.horizontal, 12).frame(height: 24)
                .background(Capsule().fill(Brand.ink(dark)))
                .contentShape(Capsule())
        }
        .buttonStyle(PhotoPress())
        .help("Done (Esc)")
    }

    private func word(_ t: String) -> some View {
        Text(t).sans(Brand.Size.body, weight: .medium).foregroundStyle(Brand.ink2(dark)).padding(.horizontal, 4)
            .lineLimit(1).fixedSize()
    }

    private func toggle(_ title: String, on: Bool, help: String? = nil, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(title).sans(Brand.Size.body, weight: on ? .semibold : .medium).foregroundStyle(Brand.ink(dark))
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 8).frame(height: 24)
                .background(Capsule().fill(on ? Brand.glassOn(dark) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(PhotoPress())
        .help(help ?? title)
    }

    /// **Guides, one choice** (2026-10-17): Off, Horizon, or Horizon and a
    /// vanishing point — they no longer fight as two switches.
    private var guides: some View {
        let p = model.photoPerspective
        let now = p == nil ? "off" : (p?.vanish == nil ? "horizon" : "point")
        return HStack(spacing: 0) {
            ForEach([("off", "Off"), ("horizon", "Horizon"), ("point", "+ Point")], id: \.0) { key, title in
                toggle(title, on: now == key, help: key == "point" ? "Horizon and Vanishing Point" : title) {
                    switch key {
                    case "off": model.setPhotoPerspective(nil)
                    case "horizon": model.setPhotoPerspective(PhotoPerspective(horizon: p?.horizon ?? 0.42, vanish: nil))
                    default: model.setPhotoPerspective(PhotoPerspective(horizon: p?.horizon ?? 0.42, vanish: p?.vanish ?? 0.5))
                    }
                }
            }
        }
        .padding(1)
        .background(Capsule().fill(Brand.rule(dark).opacity(0.6)))
    }

    @ViewBuilder private var photoControls: some View {
        if let e = model.photoEl {
            word("Photo")
            Slider(value: Binding(get: { model.photoStrengthPreview ?? e.opacity },
                                  set: { model.photoStrengthPreview = $0; model.canvas?.needsDisplay = true }),
                   in: 0.1...1, onEditingChanged: { held in
                       if !held, let v = model.photoStrengthPreview {
                           model.update([e.id], ["opacity": (v * 100).rounded() / 100])
                           model.photoStrengthPreview = nil
                           model.canvas?.needsDisplay = true
                       }
                   })
                .controlSize(.small)
                .frame(width: 96)
                .help("Photo Strength")
            Text("\(Int(((model.photoStrengthPreview ?? e.opacity) * 100).rounded()))%")
                .sans(Brand.Size.body, weight: .semibold).monospacedDigit().foregroundStyle(Brand.ink(dark))
                .frame(width: 40, alignment: .leading)
            sep
            word("Guides")
            guides
            sep
            word("Color")
            looks(model.photoLook) { model.photoLook = $0 }
            if !model.photoMarks.isEmpty {
                sep
                toggle("Clear All…", on: false) { clearing = true }
            }
        }
    }

    private func kindWord(_ m: PhotoMark) -> String {
        switch m {
        case .arrow: return "Arrow"
        case .shape(let k, _, _, _, _, _): return k == .line ? "Line" : k == .box ? "Box" : "Oval"
        case .draw: return "Drawing"
        case .words: return "Words"
        }
    }

    @ViewBuilder private func markControls(_ i: Int, _ m: PhotoMark) -> some View {
        Text(kindWord(m)).sans(Brand.Size.body, weight: .semibold).foregroundStyle(Brand.ink(dark))
            .padding(.horizontal, 4).lineLimit(1).fixedSize()
        sep
        looks(m.look) { look in
            model.photoLook = look
            replace(i, m.with(look: look))
        }
        switch m {
        case .arrow(let a):
            sep
            arrowStyle(i, a)
            word("Thickness")
            Slider(value: Binding(get: { thickDraft ?? a.thickness }, set: { thickDraft = $0 }),
                   in: ViewModel.Arrow.thinnest...ViewModel.Arrow.thickest,
                   onEditingChanged: { held in
                       if !held, let t = thickDraft { thickDraft = nil; var b = a; b.thickness = t; replace(i, .arrow(b.held)) }
                   })
                .controlSize(.small).frame(width: 80)
        case .shape, .draw:
            sep
            word("Thickness")
            // Kept once, when let go: one step to undo.
            Slider(value: Binding(get: { thickDraft ?? m.thick }, set: { thickDraft = $0 }),
                   in: PhotoMark.thinnest...PhotoMark.thickest,
                   onEditingChanged: { held in
                       if !held, let t = thickDraft { thickDraft = nil; replace(i, m.with(thick: t)) }
                   })
                .controlSize(.small).frame(width: 80)
            if case .shape(.line, let a, let b, let l, let t, let d) = m {
                toggle("Dashed", on: d) { replace(i, .shape(.line, a: a, b: b, look: l, thick: t, dashed: !d)) }
            }
        case .words(let at, let text, let l, let size):
            sep
            ForEach([("Small", 0.032), ("Medium", PhotoMark.wordsSize), ("Large", 0.07)], id: \.0) { name, v in
                toggle(name, on: abs(size - v) < 0.002) { replace(i, .words(at: at, text: text, look: l, size: v)) }
            }
        }
        sep
        nudge(i)
        sep
        toggle("Delete", on: false, help: "Delete (⌫)") { remove(i) }
    }

    /// **Style** for a picked arrow: its line, heads, dashes and depth,
    /// each by name in one menu (2026-10-17).
    private func arrowStyle(_ i: Int, _ a: ViewModel.Arrow) -> some View {
        let set = { (edit: (inout ViewModel.Arrow) -> Void) in var b = a; edit(&b); replace(i, .arrow(b.held)) }
        return Menu {
            Section("Line") {
                PhotoFootBar.pick("Straight", a.pins.isEmpty) { replace(i, .arrow(a.straightened.held)) }
                PhotoFootBar.pick("Smooth", !a.pins.isEmpty && a.shape == .smooth) { replace(i, .arrow(Self.shaped(a, .smooth))) }
                PhotoFootBar.pick("Corner", !a.pins.isEmpty && a.shape == .corner) { replace(i, .arrow(Self.shaped(a, .corner))) }
            }
            Section("Heads") {
                PhotoFootBar.pick("One Head", a.heads == 1) { set { $0.heads = 1 } }
                PhotoFootBar.pick("Both Ends", a.heads == 2) { set { $0.heads = 2 } }
                PhotoFootBar.pick("No Head", a.heads == 0) { set { $0.heads = 0 } }
            }
            Section("Stroke") {
                PhotoFootBar.pick("Solid", !a.dashed) { set { $0.dashed = false } }
                PhotoFootBar.pick("Dashed", a.dashed) { set { $0.dashed = true } }
            }
            Section("Depth") {
                ForEach(ViewModel.Arrow.Depth.allCases, id: \.self) { d in
                    PhotoFootBar.pick(d.label, a.depth == d) { replace(i, .arrow(a.withDepth(d).held)) }
                }
            }
        } label: {
            Text("Style").sans(Brand.Size.body, weight: .medium).foregroundStyle(Brand.ink(dark))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.visible).fixedSize()
        .padding(.horizontal, 6)
        .help("Line, Heads, Stroke, Depth")
    }

    @ViewBuilder static func pick(_ title: String, _ on: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) { if on { Label(title, systemImage: "checkmark") } else { Text(title) } }
    }

    /// Smooth or Corner: a straight arrow takes the pin that shows it.
    static func shaped(_ a: ViewModel.Arrow, _ shape: ViewModel.Arrow.Shape) -> ViewModel.Arrow {
        var next = a
        next.shape = shape
        if next.pins.isEmpty {
            if shape == .corner {
                next.pins = [.init(x: a.x2, y: a.y1)]
            } else {
                let dx = a.x2 - a.x1, dy = a.y2 - a.y1
                next.pins = [.init(x: (a.x1 + a.x2) / 2 + dy * 0.15, y: (a.y1 + a.y2) / 2 - dx * 0.15)]
            }
        }
        return next.held
    }

    /// **Nudge** without dragging: a point a press, ten with ⇧ (or the arrow keys).
    private func nudge(_ i: Int) -> some View {
        HStack(spacing: 0) {
            ForEach([("arrow.left", -1.0, 0.0, "Left"), ("arrow.up", 0, -1, "Up"), ("arrow.down", 0, 1, "Down"), ("arrow.right", 1, 0, "Right")], id: \.0) { sym, dx, dy, name in
                Button {
                    let k = (NSEvent.modifierFlags.contains(.shift) ? 10.0 : 1.0) / max(Double(model.scale), 1)
                    guard let p = model.photoEl else { return }
                    var all = model.photoMarks
                    guard all.indices.contains(i) else { return }
                    all[i] = all[i].moved(by: CGSize(width: dx * k / max(p.w, 0.01), height: dy * k / max(p.h, 0.01)))
                    model.savePhotoMarks(all, label: "Nudge")
                } label: {
                    Image(systemName: sym).font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.ink(dark))
                        .frame(width: 22, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(PhotoPress())
                .help("Nudge \(name) (arrow keys; ⇧ for ten)")
            }
        }
    }

    /// The four looks, as the arrows have them, each named on hover.
    private func looks(_ now: ViewModel.Arrow.Look, _ pick: @escaping (ViewModel.Arrow.Look) -> Void) -> some View {
        HStack(spacing: 2) {
            ForEach(ViewModel.Arrow.Look.allCases, id: \.self) { look in
                Button { pick(look) } label: {
                    Circle().fill(look.fill)
                        .overlay { Circle().strokeBorder(look.line.opacity(0.7), lineWidth: 1) }
                        .frame(width: 13, height: 13)
                        .padding(4)
                        .background(Circle().strokeBorder(now == look ? PhotoBar.on : .clear, lineWidth: 2))
                        .contentShape(Circle())
                }
                .buttonStyle(PhotoPress())
                .help(look.label)
                .accessibilityLabel(look.label)
            }
        }
    }

    private func replace(_ i: Int, _ m: PhotoMark) {
        var all = model.photoMarks
        guard all.indices.contains(i), all[i] != m else { return }
        all[i] = m
        model.savePhotoMarks(all)
    }

    private func remove(_ i: Int) {
        var all = model.photoMarks
        guard all.indices.contains(i) else { return }
        all.remove(at: i)
        model.photoPicked = nil
        model.savePhotoMarks(all)
    }
}

// MARK: - the checks' hand (`studio/diagram.sh`)

/// Verbs for drawing on a picture in a checking run: real mouse events at
/// points given as fractions of the picture.
enum PhotoDrive {
    @MainActor
    static func perform(_ verb: String, _ args: [String], _ model: DiagramModel,
                        post: (NSEvent.EventType, CGPoint) -> Void) -> Bool {
        func say(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
        let n = args.compactMap(Double.init)
        switch verb {
        case "photoon":
            // photoon — the first picture on the plan, drawn on (Draw on Photo)
            if let e = model.plan.els.first(where: { $0.kind == "image" }) { model.drawOnPhoto(e.id) }
        case "phototool":
            // phototool <select|arrow|line|box|oval|draw|words|perspective>
            if let t = args.first.flatMap(PhotoTool.init(rawValue:)) { model.photoTool = t }
        case "photodrag", "photoclick":
            // photodrag fx1 fy1 fx2 fy2 — the hand pressed at one point of the
            // picture and dragged to the other; photoclick fx fy — a click.
            // Through `PhotoHand`, the road a drag takes (a synthetic mouse
            // cannot drive a SwiftUI drag).
            guard let e = model.photoEl else { say("photo: no picture"); return true }
            let plate = CGRect(x: 0, y: 0, width: CGFloat(e.w) * model.scale, height: CGFloat(e.h) * model.scale)
            let need = verb == "photoclick" ? 2 : 4
            guard n.count >= need else { return true }
            let a = CGPoint(x: n[0] * plate.width, y: n[1] * plate.height)
            let b = verb == "photoclick" ? a : CGPoint(x: n[2] * plate.width, y: n[3] * plate.height)
            let hand = model.photoHand
            if verb == "photodrag" {
                for k in 1...8 {
                    let t = CGFloat(k) / 8
                    hand.moved(model, from: a, to: CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), plate)
                }
            }
            hand.ended(model, from: a, to: b, plate)
        case "photokey":
            // photokey <escape|delete> — as the keyboard sends it while drawing on a picture
            guard let window = model.canvas?.window else { return true }
            let (chars, code): (String, UInt16) = args.first == "delete" ? ("\u{7f}", 51) : ("\u{1b}", 53)
            if let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: window.windowNumber, context: nil, characters: chars,
                                        charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) {
                _ = DiagramKeys.handle(e, model)
            }
        case "photoreport":
            // photoreport — whether a picture is drawn on, and what it holds
            let e = model.plan.els.first { $0.id == model.photoEditing } ?? model.plan.els.first { $0.kind == "image" }
            let marks = PhotoMark.parse(e?.marks)
            let kinds = marks.map { m -> String in
                switch m {
                case .arrow: return "arrow"
                case .shape(let k, _, _, _, _, _): return k.rawValue
                case .draw: return "draw"
                case .words(_, let t, _, _): return "words(\(t))"
                }
            }
            say(String(format: "photo: editing %@ tool %@ picked %@ opacity %.2f perspective %@ marks %d [%@] at %.2f,%.2f size %.2fx%.2f scale %.1f shapes %d",
                       model.photoEditing ?? "none", model.photoTool.rawValue, model.photoPicked.map(String.init) ?? "none",
                       e?.opacity ?? -1, (e?.perspective ?? "").isEmpty ? "none" : e!.perspective!, marks.count,
                       kinds.joined(separator: ","), e?.x ?? 0, e?.y ?? 0, e?.w ?? 0, e?.h ?? 0, Double(model.scale),
                       model.plan.shapes.filter { $0.e == e?.id && $0.p == "mark" }.count))
        case "photodone":
            model.endPhoto()
        default:
            return false
        }
        return true
    }
}
