import SwiftUI
import AppKit

// The plan's canvas: a plain AppKit view, because a drawing tool wants the
// whole mouse — which modifier is held, the scroll wheel, a pinch, a right
// click, a key held down for a moment — and SwiftUI's gestures hand over only
// part of it.
//
// It paints what the engine worked out (`DiagramShape`s, in metres) and draws
// only its own furniture on top: the grid, the picked outline and its
// handles, the marquee, and whatever a tool is halfway through drawing.

// MARK: - inks

/// Every role the engine names, in the Mac's light and dark. Paper and walls
/// are the phone's paper floor plan (`Ink.light` / `Ink.dark` in
/// `phone/Sources/FloorPlan.swift`), so a scanned room reads the same in both
/// apps.
enum DiagramInk {
    /// **The paper is a gentle grey** (his note, 2026-09-28: *"more muted —
    /// more of a gentle grey. check for visibility"*), neutral, no warmth.
    /// Every word's ink reads at 4.5 : 1 or better on it — ink 14.2, ink2
    /// 5.4, lightink and sunink 4.7, dim, track, cable and zone 4.6 — and
    /// those word inks are the same in `svg::PAPER`, whose page stays
    /// near white. The grid, set fills and roads keep the steps they had
    /// on the lighter paper.
    ///
    /// **Three inks** (Back to Paper, his call 2026-10-04): Grip and Frames
    /// wear the film lights' red, Existing Lights the walls' grey, as the
    /// engine draws them (`plot::THREE_INKS`), so the Colours panel, the
    /// legend and the lamp palette show what the plan does. Practicals are
    /// amber (2026-10-05), their words a deeper amber (`practicalword`).
    static let light: [String: String] = [
        "paper": "E4E5E7", "grid": "D8D9DB", "grid5": "CECFD1", "griddot": "B9BABD",
        "wall": "48494A", "set": "B4B4B4", "setline": "444444", "setsoft": "D5D5D4", "setink": "8F8F8F",
        "glass": "E2F2F7", "rug": "D4CDC6", "screen": "333333", "vehicle": "7C7C7C", "tyre": "333333",
        "plant": "D1E0C2", "trunk": "AC8D77", "grip": "444444", "silk": "F1F1F1",
        "light": "F0B63F", "lightface": "FFF1CF", "lightline": "93620A", "lightink": "8A5A06", "added": "B42318", "practical": "E08A00", "practicalword": "A35E00", "plan": "74777C", "prop": "989BA0", "blue": "2F5DB8", "gripink": "B42318", "existing": "74777C", "camink": "2F5DB8",
        "fixture": "B4B4B4", "fixtureline": "444444", "muslin": "EFE6D2", "wood": "AC8D77",
        "cast": "4A72C9", "cam": "333333", "cone": "26262B", "tag": "FFFFFF", "tagline": "D5D8DC",
        "ink": "17171A", "ink2": "5A5A61", "dim": "5B6770", "track": "656565",
        "road": "C8C8C8", "roadline": "9E9E9E", "marking": "FFFFFF", "walk": "EDEDED",
        "zone": "6354C6", "zonefill": "6354C6", "cable": "A74643", "note": "FFF4C2", "noteline": "E3CB63",
        "sun": "F2A93B", "sunink": "8A5A06",
    ]
    static let dark: [String: String] = [
        "paper": "25282B", "grid": "2C2F32", "grid5": "353A3E", "griddot": "464B50",
        "wall": "75878F", "set": "33373C", "setline": "A6B1BA", "setsoft": "2C3034", "setink": "7E8A93",
        "glass": "2E3D4A", "rug": "3A352F", "screen": "0F1012", "vehicle": "3A3E44", "tyre": "0F1012",
        "plant": "5F8F5C", "trunk": "7A5E42", "grip": "C9CDD2", "silk": "4A4D52",
        "light": "E9AE3F", "lightface": "6B5423", "lightline": "F2C66B", "lightink": "E9AE3F", "added": "F27A72", "practical": "F5A623", "practicalword": "F5A623", "plan": "8C949A", "prop": "656D73", "blue": "7FA2F0", "gripink": "F27A72", "existing": "8C949A", "camink": "7FA2F0",
        "fixture": "2B2F33", "fixtureline": "A3ACB4", "muslin": "3B352A", "wood": "4A4034",
        "cast": "6E95E8", "cam": "ECECEF", "cone": "ECECEF", "tag": "2A2D31", "tagline": "40454A",
        "ink": "EDEDF0", "ink2": "A0A0A8", "dim": "9FAAB3", "track": "A0A0A8",
        "road": "3A3D41", "roadline": "5E646A", "marking": "C9CDD2", "walk": "303336",
        "zone": "9D90F0", "zonefill": "9D90F0", "cable": "E07A73", "note": "4A4328", "noteline": "8A7A3A",
        "sun": "F2B33D", "sunink": "F2C66B",
    ]

    /// A role, a colour, or a colour with how much of it (`#D9483B/0.30`).
    static func color(_ word: String?, dark: Bool) -> NSColor? {
        guard let word, !word.isEmpty else { return nil }
        if word.hasPrefix("#") {
            let parts = word.split(separator: "/")
            let base = Brand.nsHex(String(parts[0]).replacingOccurrences(of: "#", with: ""))
            let alpha = parts.count > 1 ? (Double(parts[1]) ?? 1) : 1
            return base.withAlphaComponent(CGFloat(alpha))
        }
        let table = dark ? DiagramInk.dark : DiagramInk.light
        return Brand.nsHex(table[word] ?? (dark ? "EDEDF0" : "17171A"))
    }

    static let pick = NSColor(red: 0.18, green: 0.49, blue: 0.96, alpha: 1)
}

// MARK: - the view

struct DiagramCanvas: NSViewRepresentable {
    @ObservedObject var model: DiagramModel
    @Environment(\.colorScheme) private var scheme

    func makeNSView(context: Context) -> DiagramCanvasView {
        let v = DiagramCanvasView()
        v.model = model
        model.canvas = v
        return v
    }

    func updateNSView(_ v: DiagramCanvasView, context: Context) {
        v.model = model
        // The plan is paper, whatever the app around it: the Film Set
        // Objects pack is drawn for a white page (his call, 2026-09-27).
        v.dark = false
        // The desk round the page is the app's own ground (`DiagramPage`).
        v.deskDark = scheme == .dark
        v.needsDisplay = true
    }
}

final class DiagramCanvasView: NSView {
    weak var model: DiagramModel?
    var dark = false { didSet { if dark != oldValue { needsDisplay = true } } }
    /// The desk the sheet lies on, dark with the app (`DiagramPage.swift`).
    var deskDark = false { didSet { if deskDark != oldValue { needsDisplay = true } } }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Tags and badges are drawn at a fixed size, so only the view knows where
    /// they landed; they are hit from here.
    private var tagRects: [(CGRect, String)] = []
    /// Names drawn on the plan, hit to drag a name on its own (`DiagramNames.swift`).
    var labelRects: [(CGRect, String)] = []
    /// A name or a laid-on frame being dragged (`DiagramNames.swift`).
    var nameDrag: DiagramNameDrag?
    /// The words being typed on the plan (`DiagramTyping.swift`).
    var typist: DiagramTypist?
    private var hover: String?
    /// For a checking run: what the pointer is over.
    var hovered: String? { hover }
    /// What a turning knob is over and would aim the piece at.
    private var aimAt: String?
    private var spaceHeld = false
    /// What a plain click in the select tool landed on — a click that does
    /// not drag narrows a many-thing pick to it, on the way up.
    private var pressedOn: String?
    /// What a ⌘- or ⇧-click on something already picked takes out of the
    /// pick — on the way up, and only if it was not dragged.
    private var unpickOnUp: [String]?
    private var mouseWorld: CGPoint?
    /// Alignment guides while pieces are moved, on screen (`DiagramGuides`).
    private(set) var guides: [[CGPoint]] = []
    /// What a wall's corner lined up with while it is drawn or dragged — on
    /// the plan, from the engine's snap (`walls::snap`).
    private var wallGuides: [[CGPoint]] = []
    /// A door, window or opening sliding along its wall: how far its near
    /// edge is from the nearer corner, and the two points that runs between.
    private var slideMark: (face: CGPoint, edge: CGPoint, from: Double)?
    /// The press landed on the one wall already picked — let go without a
    /// drag, it picks the stretch under it.
    private var pressedPicked = false
    private var mouseDownAt: CGPoint?
    /// From the hand to the wall corner it is dragging: a corner just added
    /// by its + is beside the hand, not under it, and must not jump to it.
    private var cornerGrab: CGPoint = .zero

    /// How far a point is from a stretch.
    static func segDist(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let (dx, dy) = (b.x - a.x, b.y - a.y)
        let l2 = dx * dx + dy * dy
        let t = l2 < 1e-12 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
    /// The pieces those guides line the move up with — drawn picked-blue.
    private(set) var linedUp: [String] = []
    /// The pointer in the view, for the readout beside it.
    private var pointerView: CGPoint?

    private enum Drag {
        case none
        case moving(start: CGPoint, ids: [String], anchor: CGPoint?, delta: CGPoint)
        /// A door, window or opening dragged on its own: it catches on a wall
        /// it comes near, slides along it, and comes off only when pulled well
        /// clear — or anywhere with ⌘ held. `set` is where it lands.
        case sliding(start: CGPoint, el: DiagramEl, onWall: Bool, set: [String: Any])
        /// One step's ghost, dragged to where that step goes, or turned by its knob.
        case stepping(el: DiagramEl, step: Int, start: CGPoint, at: CGPoint)
        case stepTurning(el: DiagramEl, step: Int, rot: Double)
        case marquee(start: CGPoint, now: CGPoint, base: [String])
        case resizing(el: DiagramEl, corner: Int, set: [String: Any])
        case rotating(el: DiagramEl, rot: Double)
        /// The pick turned as one by its box's knob — a wall, several, a
        /// group — about `pivot`, on the grid. `from` is where the hand took
        /// hold, in degrees round the pivot; `base` the first piece's own
        /// heading, so the steps land on round angles; `deg` the turn so far.
        case turningPick(pivot: CGPoint, from: Double, base: Double, deg: Double)
        /// `joined`: the other walls whose end sits on this one — a corner
        /// moves as one unless ⌥ pulls this wall free.
        case endpoint(el: DiagramEl, end: Int, at: CGPoint, joined: [(String, Int)])
        case curving(el: DiagramEl, curve: Double)
        /// **One corner of a wall** dragged on its own (`wall_corner`): the
        /// stretches either side follow, and it lines up square with the
        /// other corners. `made`: just added by its +, so adding and
        /// dragging are one step to take back. `free`: ⌥ — nothing joined
        /// there comes along.
        case corner(el: DiagramEl, index: Int, at: CGPoint, made: Bool, free: Bool)
        case reaching(el: DiagramEl, reach: Double)
        /// A frame stood up or laid down by its tilt knob (`DiagramFrames.tilt`).
        case tilting(el: DiagramEl, start: CGPoint, tilt: Double)
        case panning(last: CGPoint)
        /// The compass, turned by hand like a dial: its needle goes round
        /// with the hand, and the sun round the set, which stays put (his
        /// note, 2026-09-29, taking back 2026-09-27's turning plan). `from`
        /// is where the pointer took hold, in degrees round the dial; `was`
        /// the north it began at.
        case turningNorth(from: Double, was: Double, north: Double)
        case placing(at: CGPoint, rot: Double)
        case line(from: CGPoint, to: CGPoint)
        /// One wall, pressed and pulled out. Let go, it stands, and the next
        /// click carries on from its far end.
        case wall(from: CGPoint, to: CGPoint)
        case box(from: CGPoint, to: CGPoint)
        /// A point of the path being drawn, pressed and maybe pulled out into a curve.
        case node
        /// One curve handle of a point, dragged (`wall_handle`).
        case handle(el: DiagramEl, node: Int, out: Bool, at: CGPoint)
    }
    private var drag: Drag = .none
    /// The pieces an arrow or a connector being drawn or dragged would hold
    /// on to if let go now — lit like hover.
    private var pinGlow: [String] = []
    private var dragged = false
    /// ⌥ held as a piece was pressed: a copy is made once the mouse moves,
    /// never on the click alone.
    private var copyOnMove = false
    /// What was picked before an ⌥-drag made its copy — the copy and its
    /// move are one step to take back.
    private var copiedFrom: [String]?
    /// From the pointer to the corner it took hold of: a corner handle sits
    /// just outside its piece, and the corner must not jump to the pointer.
    private var resizeGrab: CGPoint = .zero

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let model, let cg = NSGraphicsContext.current?.cgContext else { return }
        let size = bounds.size
        if !model.fitted, size.width > 40 { model.fit(in: size) }
        // The paper as bright as this Mac has it (View → Backdrop…).
        let paper = model.lit(DiagramInk.color("paper", dark: dark)!)
        // The sheet on the desk (`DiagramPage.swift`), the dots on the paper.
        drawDesk(cg, model, size, paper: paper)
        // The dots follow View › Grid on either layer (his note, 2026-10-05:
        // "grid needs to appear if I want it to").
        if model.settings.grid { onPage(cg, model, size) { drawGrid(cg, model, size) } }
        drawPageFurniture(cg, model, size)

        let T = model.transform(size: size)
        var painter = DiagramPainter(dark: dark, scale: model.scale, engine: model.engine)
        painter.shrink = CGFloat(model.namesShrink)
        // Cuts in walls take the backdrop; names keep their own light patch,
        // so they read however dim the paper is.
        if abs(model.backdrop - DiagramModel.defaultBackdrop) > 0.001 { painter.paper = paper }
        // Less what this Mac's Show panel has switched off.
        let shapes = model.seen(model.shownShapes)
        // A lone name is never dropped for being small (see `DiagramPainter.lone`).
        painter.lone = shapes.filter { $0.p == "label" }.count == 1
        // The engine's compass is for paper and the portal; here it stands
        // still in the corner, and the plan turns.
        // Words being typed are the typist's, not the plan's, until kept.
        // **Set or Plot** (Ref 1498): the layer not being worked in drawn
        // back — the set grey under the plot, the plot faded over the set.
        let back = model.layerLockedIds
        let backAlpha: CGFloat = model.layer == "set" ? 0.2 : 0.5
        // **A picture is never stepped back** (his pick, 2026-10-15): it
        // shows at the strength he set, whichever side he works on.
        let pictures = Set(model.plan.els.filter { $0.kind == "image" }.map(\.id))
        // **Drawing on a picture** (2026-10-15): it shows at full strength —
        // or at the Photo slider while it is held — and the plan steps back;
        // its marks are the editor's to draw while the hand is on them.
        let photo = model.photoEditing
        for s in shapes where s.p != "north" {
            guard var s = typingShape(s) else { continue }
            if let photo {
                if s.e == photo, s.p == "mark" { continue }
                if s.e == photo, s.k == "img" { s.a = model.photoStrengthPreview ?? 1 }
                painter.fade = s.e == photo ? 1 : 0.25
            } else {
                let picture = s.e.map { pictures.contains($0) } == true
                painter.fade = !picture && s.e.map { back.contains($0) } == true ? backAlpha : 1
            }
            painter.paint(s, cg, T)
        }
        painter.fade = 1
        tagRects = painter.tags
        labelRects = painter.labels
        drawCompass(cg)
        placeTypist()

        // Lamps lit while something about all of them is open (Name All),
        // and a shared label's lamps while it, or one of them, is picked.
        for id in model.glow + model.sharedLit {
            if let e = model.shown.els.first(where: { $0.id == id }) {
                outline(e, cg, model, size, colour: DiagramInk.pick, handles: false, width: 1.8)
            }
        }

        // What an arrow or a connector being drawn will hold on to.
        for id in pinGlow {
            if let e = model.shown.els.first(where: { $0.id == id }) {
                outline(e, cg, model, size, colour: DiagramInk.pick, handles: false, width: 1.8)
            }
        }

        // **Hover turns the piece under the pointer blue** (Scenario's): what
        // a click would take, before it is clicked.
        if let hover, !model.presenting, !model.selection.contains(hover), case .none = drag, let e = model.el(hover) {
            outline(e, cg, model, size, colour: DiagramInk.pick, handles: false, width: 1.8)
        }
        if let aimAt, let e = model.shown.els.first(where: { $0.id == aimAt }) {
            outline(e, cg, model, size, colour: DiagramInk.pick, handles: false)
        }
        let hauling: Bool = {
            switch drag {
            case .moving, .sliding, .stepping, .stepTurning: return true
            default: return false
            }
        }()
        // The pick's outline follows it while it is hauled; its handles come
        // back when it is let go.
        let boxed = usesPickBox(model)
        let groups = Set(model.pickedGroups)
        for e in model.shownPicked {
            if let sp = model.stepPick, sp.e.id == e.id {
                stepOutline(e, sp.i, cg, model, size, handles: !hauling)
            } else if groups.contains(e.group) || (boxed && e.isPolyline) {
                // A group picked whole is its box, not its pieces.
                continue
            } else {
                outline(e, cg, model, size, colour: DiagramInk.pick,
                        handles: !hauling && model.shownPicked.count == 1)
            }
        }
        if boxed { drawPickBox(cg, model, size, knob: !hauling) }
        drawInProgress(cg, model, size)
        if hauling {
            DiagramGuides.draw(guides, cg)
            // The piece being lined up with lights up, not just the line.
            for id in linedUp { if let e = model.el(id) { outline(e, cg, model, size, colour: DiagramInk.pick, handles: false, width: 1.8) } }
        }
        if !wallGuides.isEmpty {
            DiagramGuides.draw(wallGuides.map { $0.map { model.toView($0, size: size) } }, cg)
        }
        if case .sliding = drag, let mark = slideMark { drawSlideMark(mark, cg, model, size) }
        if let (text, at) = readout(model, size) { drawReadout(text, at: at, cg) }
    }

    /// A door sliding along its wall: its distance from the nearer corner's
    /// face, as a dimension, while it moves.
    private func drawSlideMark(_ mark: (face: CGPoint, edge: CGPoint, from: Double), _ cg: CGContext, _ m: DiagramModel, _ size: CGSize) {
        let (a, b) = (m.toView(mark.face, size: size), m.toView(mark.edge, size: size))
        let len = hypot(b.x - a.x, b.y - a.y)
        let (nx, ny) = len > 0.5 ? (-(b.y - a.y) / len * 14, (b.x - a.x) / len * 14) : (0, -14)
        let (pa, pb) = (CGPoint(x: a.x + nx, y: a.y + ny), CGPoint(x: b.x + nx, y: b.y + ny))
        cg.saveGState()
        defer { cg.restoreGState() }
        cg.setStrokeColor(DiagramInk.pick.cgColor)
        cg.setLineWidth(1)
        cg.move(to: pa); cg.addLine(to: pb)
        for (p, q) in [(a, pa), (b, pb)] { cg.move(to: p); cg.addLine(to: CGPoint(x: q.x + nx * 0.3, y: q.y + ny * 0.3)) }
        cg.strokePath()
        DiagramPainter.words(m.length(max(mark.from, 0)), at: CGPoint(x: (pa.x + pb.x) / 2 + nx * 0.9, y: (pa.y + pb.y) / 2 + ny * 0.9),
                             font: .systemFont(ofSize: 10.5, weight: .semibold), colour: DiagramInk.pick,
                             anchor: "middle", rot: 0, halo: true, cg: cg, dark: dark)
    }

    /// **Faint dots, not graph paper** (Back to Paper, his call 2026-10-04):
    /// a dot at every crossing of the grid, one grid step apart — the step a
    /// drag keeps to, finer close in and coarser far out, so the dots drawn
    /// are the spots caught. Too close to read apart, only every darker
    /// line's crossing keeps its dot. The grid belongs to the plan and turns
    /// with it.
    private func drawGrid(_ cg: CGContext, _ m: DiagramModel, _ size: CGSize) {
        let step = CGFloat(m.snapStep)
        let every = m.gridEvery
        let px = step * m.scale
        let stride = px >= 10 ? 1 : every
        guard px * CGFloat(stride) >= 10 else { return }
        let corners = [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height)]
            .map { m.toWorld($0, size: size) }
        let (x0, x1) = (corners.map(\.x).min()!, corners.map(\.x).max()!)
        let (y0, y1) = (corners.map(\.y).min()!, corners.map(\.y).max()!)
        let i0 = Int(floor(x0 / step)), i1 = Int(ceil(x1 / step))
        let j0 = Int(floor(y0 / step)), j1 = Int(ceil(y1 / step))
        let square = abs(m.turn) < 1e-9
        let r: CGFloat = 1
        let dots = CGMutablePath()
        let view = CGRect(origin: .zero, size: size).insetBy(dx: -2, dy: -2)
        for i in i0...i1 where i % stride == 0 {
            for j in j0...j1 where j % stride == 0 {
                var p = m.toView(CGPoint(x: CGFloat(i) * step, y: CGFloat(j) * step), size: size)
                guard view.contains(p) else { continue }
                // Square to the screen, kept on the pixel.
                if square { p = CGPoint(x: p.x.rounded(), y: p.y.rounded()) }
                dots.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            }
        }
        cg.addPath(dots)
        cg.setFillColor(m.lit(DiagramInk.color("griddot", dark: dark)!).cgColor)
        cg.fillPath()
    }

    // MARK: the compass

    /// Where the compass stands: in the bottom right corner, over the view
    /// bar, still while the plan turns — to the left of any panel down the
    /// right, which would otherwise cover it. Only once the plan has one.
    var compassSpot: (centre: CGPoint, radius: CGFloat)? {
        guard let m = model, m.showsCompass else { return nil }
        return (CGPoint(x: bounds.width - 34 - m.rightCover, y: bounds.height - 88), 12)
    }

    /// Its needle points to north on the plan. Grabbed and turned like a
    /// dial, the needle goes round and the sun with it — the set stays put
    /// (his note, 2026-09-29); clicked, it opens the sun.
    /// **Quiet** (Batch 3): the sheet's own N says where north is; this is
    /// only the dial that turns it — a thin ring and a grey needle, no N.
    private func drawCompass(_ cg: CGContext) {
        guard let m = model, let (c, r) = compassSpot else { return }
        let ink = DiagramInk.color("ink2", dark: dark)!.withAlphaComponent(0.55)
        cg.saveGState()
        defer { cg.restoreGState() }
        cg.setStrokeColor(ink.withAlphaComponent(0.35).cgColor)
        cg.setLineWidth(1)
        cg.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        // Clockwise from straight up, the way the plan's north is kept.
        let north = CGFloat(m.liveNorth ?? m.settings.north) * .pi / 180
        let spin = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: north)
        let k = r * 0.8
        let needle = [CGPoint(x: 0, y: -k * 0.85), CGPoint(x: k * 0.38, y: k * 0.6),
                      CGPoint(x: 0, y: k * 0.35), CGPoint(x: -k * 0.38, y: k * 0.6)].map { $0.applying(spin) }
        cg.move(to: needle[0]); needle.dropFirst().forEach { cg.addLine(to: $0) }
        cg.closePath()
        cg.setFillColor(ink.cgColor)
        cg.fillPath()
    }

    private func onCompass(_ v: CGPoint) -> Bool {
        guard let (c, r) = compassSpot else { return false }
        return hypot(v.x - c.x, v.y - c.y) <= r * 1.6
    }

    /// Degrees round the compass, from its middle to a point on screen.
    private func dial(_ v: CGPoint) -> Double {
        guard let (c, _) = compassSpot else { return 0 }
        return atan2(v.y - c.y, v.x - c.x) * 180 / .pi
    }

    // MARK: the picked outline

    /// The corners, turned, in view points — and the handles a single pick
    /// wears.
    /// A piece's outline on screen: round what is drawn (`drawn`), or, for
    /// a resize to measure from, its own footprint.
    private func frame(_ e: DiagramEl, _ m: DiagramModel, _ size: CGSize, footprint: Bool = false) -> [CGPoint] {
        let now = e.at(beat: m.beat)
        let (w, h) = footprint ? { let f = e.footprint(at: m.beat); return (CGFloat(f.0), CGFloat(f.1)) }() : frameSize(e, m)
        let r = CGFloat(now.rot) * .pi / 180
        let (c, s) = (cos(r), sin(r))
        return [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)].map { lx, ly in
            m.toView(CGPoint(x: now.x + lx * c - ly * s, y: now.y + lx * s + ly * c), size: size)
        }
    }

    private func frameSize(_ e: DiagramEl, _ m: DiagramModel) -> (CGFloat, CGFloat) {
        // **Round what is drawn** (Ref 1511): a lamp's mark, a camera, Words
        // at the size the plan draws them — the engine measures them.
        if let d = e.drawn, d.count == 2 {
            // A lamp's mark, sized as he sized it: round the mark alone.
            // Never under 26 points on screen, so its four corners stand
            // clear of a small mark.
            if e.hug == true { let side = max(CGFloat(d[0]), 26 / m.scale); return (side, side) }
            if e.kind == "text" { return (CGFloat(d[0]) + 4 / m.scale, CGFloat(d[1]) + 4 / m.scale) }
            let (w, h) = e.footprint(at: m.beat)
            return (CGFloat(max(w, d[0])), CGFloat(max(h, d[1])))
        }
        if e.kind == "text", let shown = e.shown, e.text.trimmingCharacters(in: .whitespaces).isEmpty {
            // A shared label: fixed-size words, whatever the zoom — its name,
            // and its notes on a line under it, in ink, one size, regular.
            let font = NSFont.systemFont(ofSize: 10, weight: .regular)
            let lines = shown.components(separatedBy: "\n")
            let w = lines.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 10
            let h = (font.ascender - font.descender) * CGFloat(max(lines.count, 1)) + 2 * CGFloat(max(lines.count - 1, 0))
            return ((w + 10) / m.scale, (h + 8) / m.scale)
        }
        if e.kind == "text" {
            let font = NSFont.systemFont(ofSize: max(CGFloat(e.size) / 40 * m.scale, 1), weight: .semibold)
            let lines = e.text.components(separatedBy: "\n")
            let w = lines.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 10
            let h = (font.ascender - font.descender) * CGFloat(max(lines.count, 1))
            return ((w + 8) / m.scale, (h + 6) / m.scale)
        }
        let (w, h) = e.footprint(at: m.beat)
        return (CGFloat(w), CGFloat(h))
    }

    private struct Handle { var kind: String; var at: CGPoint; var index: Int; var from: CGPoint? = nil }

    private func handles(_ e: DiagramEl, _ m: DiagramModel, _ size: CGSize) -> [Handle] {
        guard !e.locked else { return [] }
        // The far end picked on its own wears only its own knob; the thing
        // picked wears the rest, and never the far end's.
        if let sp = m.stepPick, sp.e.id == e.id { return stepKnob(e, sp.i, m, size).map { [$0] } ?? [] }
        // A ruler's markers are handled as a wall's corners are: dragged,
        // a + to add one, a + past either end to grow it.
        if e.isWall || e.isRuler || e.isPath { return m.tool == .select ? wallHandles(e, m, size) : [] }
        if e.isLine {
            var out = [Handle(kind: "end", at: m.toView(CGPoint(x: e.x, y: e.y), size: size), index: 0),
                       Handle(kind: "end", at: m.toView(CGPoint(x: e.x2, y: e.y2), size: size), index: 1)]
            if ["wall", "track", "road", "arrow"].contains(e.kind) {
                out.append(Handle(kind: "curve", at: curveHandle(e, m, size), index: 0))
            }
            return out
        }
        if e.isPolyline || e.kind == "note" { return [] }
        let corners = frame(e, m, size)
        var out: [Handle] = []
        let mid = CGPoint(x: (corners[0].x + corners[2].x) / 2, y: (corners[0].y + corners[2].y) / 2)
        if !["camera", "cast", "text"].contains(e.kind) {
            // Just outside the piece, so a small piece's body is still there
            // to take hold of (and the body wins inside it: `hitHandle`).
            out += corners.enumerated().map { i, c in
                let (dx, dy) = (c.x - mid.x, c.y - mid.y)
                let len = max(hypot(dx, dy), 0.001)
                return Handle(kind: "corner", at: CGPoint(x: c.x + dx / len * 5, y: c.y + dy / len * 5), index: i)
            }
        }
        // The turning knob: out along the way a light, a camera or a person
        // faces, so the beam follows the hand; off the top of anything else.
        let edge = knobEdge(e, corners)
        let dx = edge.x - mid.x, dy = edge.y - mid.y
        let len = max(hypot(dx, dy), 0.001)
        out.append(Handle(kind: "rotate", at: CGPoint(x: edge.x + dx / len * 22, y: edge.y + dy / len * 22), index: 0))
        // A frame's tilt knob rides its raised edge, out past one side
        // (Scenario's); its turning knob is off the other, so the two never
        // meet, even standing.
        if e.sym == DiagramFrames.sym { out.append(Handle(kind: "tilt", at: tiltTrack(e, m, size).knob, index: 0)) }
        // Its turns: each one's heading on a knob of its own, beside its spot.
        for (i, spot) in e.spots.enumerated() where spot.turn {
            if let knob = stepKnob(e, i, m, size) { out.append(knob) }
        }
        // How far a camera's cone reaches. (A lamp draws no beam on a plot,
        // so it has no reach to drag: 2026-10-05.)
        if e.kind == "camera" && e.cone {
            let now = e.at(beat: m.beat)
            let reach = e.kind == "camera" ? cameraReach(e) : e.reach
            let r = now.rot * .pi / 180
            let tip = CGPoint(x: now.x + cos(r) * (e.w / 2 + reach), y: now.y + sin(r) * (e.w / 2 + reach))
            out.append(Handle(kind: "reach", at: m.toView(tip, size: size), index: 0))
        }
        return out
    }

    /// **A picked wall's handles** (master list 3): a square on every corner,
    /// to pick it and drag it; a + beside the middle of each stretch to add a
    /// corner there — off the wall, so a press on the wall still moves the
    /// wall — and a + past each open end to grow it on.
    private func wallHandles(_ e: DiagramEl, _ m: DiagramModel, _ size: CGSize) -> [Handle] {
        let c = e.corners
        var out = c.enumerated().map { Handle(kind: "wallcorner", at: m.toView($0.element, size: size), index: $0.offset) }
        // The +s go outside a room (its lengths are inside), and on the right
        // of an open wall's travel (its lengths are on the left).
        var side: CGFloat = 1
        if e.isClosed {
            var area = 0.0
            for i in 0..<c.count { area += Double(c[i].x * c[(i + 1) % c.count].y - c[(i + 1) % c.count].x * c[i].y) }
            side = area >= 0 ? -1 : 1
        }
        let off = CGFloat(e.thick) * m.scale / 2 + 14
        for (i, st) in e.stretches.enumerated() {
            let (a, b) = (m.toView(st.0, size: size), m.toView(st.1, size: size))
            let len = hypot(b.x - a.x, b.y - a.y)
            guard len > 40 else { continue }
            if let cub = e.stretchCubic(i) {
                // A curved stretch: the + stands off its middle, square to the curve there.
                let (p0, p1, mid) = (m.toView(DiagramEl.cubic(cub, 0.45), size: size), m.toView(DiagramEl.cubic(cub, 0.55), size: size),
                                     m.toView(DiagramEl.cubic(cub, 0.5), size: size))
                let l = max(hypot(p1.x - p0.x, p1.y - p0.y), 1e-6)
                let (nx, ny) = (-(p1.y - p0.y) / l, (p1.x - p0.x) / l)
                out.append(Handle(kind: "addcorner", at: CGPoint(x: mid.x + nx * side * off, y: mid.y + ny * side * off), index: i))
                continue
            }
            let (nx, ny) = (-(b.y - a.y) / len, (b.x - a.x) / len)
            out.append(Handle(kind: "addcorner", at: CGPoint(x: (a.x + b.x) / 2 + nx * side * off, y: (a.y + b.y) / 2 + ny * side * off), index: i))
        }
        // The picked corner's curve handles, and those of its neighbours that
        // lean on the stretches beside it.
        if let k = m.pickedCorner, k < c.count {
            let n = c.count
            func knob(_ node: Int, out outward: Bool) {
                guard node >= 0, node < n else { return }
                let h = e.handle(node)
                let v = outward ? h.out : h.inn
                guard abs(v.dx) + abs(v.dy) > 1e-9 else { return }
                let from = m.toView(c[node], size: size)
                let at = m.toView(CGPoint(x: c[node].x + v.dx, y: c[node].y + v.dy), size: size)
                out.append(Handle(kind: outward ? "hout" : "hin", at: at, index: node, from: from))
            }
            knob(k, out: false)
            knob(k, out: true)
            if k > 0 || e.isClosed { knob((k + n - 1) % n, out: true) }
            if k + 1 < n || e.isClosed { knob((k + 1) % n, out: false) }
        }
        if !e.isClosed, c.count >= 2 {
            for (end, p, q) in [(0, c[0], c[1]), (1, c[c.count - 1], c[c.count - 2])] {
                let (vp, vq) = (m.toView(p, size: size), m.toView(q, size: size))
                let len = max(hypot(vp.x - vq.x, vp.y - vq.y), 1e-6)
                let at = CGPoint(x: vp.x + (vp.x - vq.x) / len * 22, y: vp.y + (vp.y - vq.y) / len * 22)
                // Not where another handle already is — two ends of a narrow
                // gap would put their +s on each other.
                guard !out.contains(where: { hypot($0.at.x - at.x, $0.at.y - at.y) < 16 }) else { continue }
                out.append(Handle(kind: "extend", at: at, index: end))
            }
        }
        return out
    }

    /// Whether a piece faces along its heading — a lamp's beam, a camera's
    /// lens, a person's nose — and so turns from a knob out in front.
    static func faces(_ e: DiagramEl) -> Bool {
        ["camera", "cast"].contains(e.kind) || (e.kind == "light" && e.sym != DiagramFrames.sym)
    }

    /// The middle of the edge the turning knob stands off, in view points:
    /// the front of what faces, the far side of a frame from its tilt knob,
    /// the top of anything else.
    private func knobEdge(_ e: DiagramEl, _ c: [CGPoint]) -> CGPoint {
        if Self.faces(e) { return CGPoint(x: (c[1].x + c[2].x) / 2, y: (c[1].y + c[2].y) / 2) }
        if e.sym == DiagramFrames.sym { return CGPoint(x: (c[2].x + c[3].x) / 2, y: (c[2].y + c[3].y) / 2) }
        return CGPoint(x: (c[0].x + c[1].x) / 2, y: (c[0].y + c[1].y) / 2)
    }

    /// How far round from the knob's direction a piece's heading is: none
    /// for what faces, a quarter back for a frame (its knob is off its
    /// side), a quarter on for anything else (off its top).
    static func knobOffset(_ e: DiagramEl) -> Double {
        faces(e) ? 0 : e.sym == DiagramFrames.sym ? -90 : 90
    }

    /// A frame's tilt knob and the track it slides on, in view points: a
    /// fixed way out past the frame's side, level with its raised (back)
    /// edge — at the frame's far end lying flat, at its middle standing.
    func tiltTrack(_ e: DiagramEl, _ m: DiagramModel, _ size: CGSize) -> (knob: CGPoint, flat: CGPoint, upright: CGPoint) {
        let now = e.at(beat: m.beat)
        let (w, h) = e.footprint(at: m.beat)
        let tall = e.tall > 0 ? e.tall : e.h
        let r = now.rot * .pi / 180
        let (c, s) = (cos(r), sin(r))
        let at = { (lx: Double, ly: Double) in
            m.toView(CGPoint(x: now.x + lx * c - ly * s, y: now.y + lx * s + ly * c), size: size)
        }
        let edge = at(-w / 2, -h / 2), past = at(-w / 2, -h / 2 - 1)
        let len = max(hypot(past.x - edge.x, past.y - edge.y), 0.001)
        let out = CGPoint(x: (past.x - edge.x) / len * 26, y: (past.y - edge.y) / len * 26)
        let shift = { (p: CGPoint) in CGPoint(x: p.x + out.x, y: p.y + out.y) }
        return (shift(edge), shift(at(-tall / 2, -h / 2)), shift(at(0, -h / 2)))
    }

    /// The way out from a frame's side to its tilt knob, as a unit, in view
    /// points.
    func tiltAway(_ e: DiagramEl, _ m: DiagramModel, _ size: CGSize) -> CGPoint {
        let t = tiltTrack(e, m, size)
        let now = e.at(beat: m.beat)
        let mid = m.toView(CGPoint(x: now.x, y: now.y), size: size)
        let (ux, uy) = (t.upright.x - mid.x, t.upright.y - mid.y)
        let len = max(hypot(ux, uy), 0.001)
        return CGPoint(x: ux / len, y: uy / len)
    }

    // MARK: the pick's box

    /// One box round the pick, with its own turning knob, for several pieces
    /// or a group. **A single line has none** — his note, 2026-10-01: *"there
    /// don't need to be boxes around things like lines. It should just be the
    /// line with two endpoints I can grab"*. A wall, a ruler, an arrow, a
    /// track or a road picked alone is its own line and the handles on it.
    private func usesPickBox(_ m: DiagramModel) -> Bool {
        guard m.stepPick == nil, !m.presenting else { return false }
        let picked = m.shownPicked
        if picked.isEmpty || picked.allSatisfy(\.locked) { return false }
        return picked.count > 1
    }

    /// The pick's box on screen, a little outside what it holds.
    private func pickBox(_ m: DiagramModel, _ size: CGSize) -> CGRect? {
        var pts: [CGPoint] = []
        for e in m.shownPicked {
            if e.isWall { pts += e.run.map { m.toView($0, size: size) } }
            else if e.isLine { pts += [CGPoint(x: e.x, y: e.y), CGPoint(x: e.x2, y: e.y2)].map { m.toView($0, size: size) }
                if abs(e.curve) > 1e-6 { pts.append(curveHandle(e, m, size)) } }
            else if e.isPolyline { pts += e.points.compactMap { $0.count > 1 ? m.toView(CGPoint(x: $0[0], y: $0[1]), size: size) : nil } }
            else { pts += frame(e, m, size) }
        }
        guard let x0 = pts.map(\.x).min(), let x1 = pts.map(\.x).max(),
              let y0 = pts.map(\.y).min(), let y1 = pts.map(\.y).max() else { return nil }
        return CGRect(x: x0 - 7, y: y0 - 7, width: x1 - x0 + 14, height: y1 - y0 + 14)
    }

    /// Where the pick's box's turning knob is.
    private func pickKnob(_ m: DiagramModel, _ size: CGSize) -> CGPoint? {
        guard usesPickBox(m), let r = pickBox(m, size) else { return nil }
        // Straight above the point it turns about, so the hand's angle round
        // that point is the turn.
        // One wall alone: over its box's right edge, clear of the + that
        // adds a corner in the middle of its top stretch.
        if m.shownPicked.count == 1, m.shownPicked[0].isWall { return CGPoint(x: r.maxX, y: r.minY - 22) }
        let x = min(max(m.toView(m.pivot(), size: size).x, r.minX), r.maxX)
        return CGPoint(x: x, y: r.minY - 22)
    }

    private func drawPickBox(_ cg: CGContext, _ m: DiagramModel, _ size: CGSize, knob withKnob: Bool) {
        guard let r = pickBox(m, size) else { return }
        let ink = DiagramInk.pick
        cg.saveGState()
        defer { cg.restoreGState() }
        cg.setStrokeColor(ink.cgColor)
        cg.setLineWidth(1)
        // A group: dashed, its name on its edge. Anything else: a hairline.
        let group: String? = m.pickedGroups.count == 1
            ? (m.members(ofGroup: m.pickedGroups[0]).first?.group_name ?? "Group") : nil
        if !m.pickedGroups.isEmpty { cg.setLineDash(phase: 0, lengths: [5, 4]) }
        else { cg.setStrokeColor(ink.withAlphaComponent(0.55).cgColor) }
        cg.stroke(r)
        cg.setLineDash(phase: 0, lengths: [])
        if let name = group, !name.isEmpty {
            DiagramPainter.words(name, at: CGPoint(x: r.minX + 2, y: r.minY - 9), font: .systemFont(ofSize: 10.5, weight: .semibold),
                                 colour: ink, anchor: "start", rot: 0, halo: true, cg: cg, dark: dark)
        }
        guard withKnob, let k = pickKnob(m, size) else { return }
        cg.setStrokeColor(ink.cgColor)
        cg.move(to: CGPoint(x: k.x, y: r.minY)); cg.addLine(to: k); cg.strokePath()
        let kr = CGRect(x: k.x - 5, y: k.y - 5, width: 10, height: 10)
        cg.setFillColor(NSColor.white.cgColor)
        cg.setLineWidth(1.4)
        cg.fillEllipse(in: kr); cg.strokeEllipse(in: kr)
    }

    /// The corners of one step's ghost, in view points.
    private func stepFrame(_ e: DiagramEl, _ i: Int, _ m: DiagramModel, _ size: CGSize) -> [CGPoint]? {
        guard e.hasSteps, e.spots.indices.contains(i) else { return nil }
        let t = e.spots[i]
        let (w, h) = e.footprint(at: max(t.beat, 1))
        let r = t.rot * .pi / 180
        let (c, s) = (cos(r), sin(r))
        return [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)].map { lx, ly in
            m.toView(CGPoint(x: t.x + lx * c - ly * s, y: t.y + lx * s + ly * c), size: size)
        }
    }

    /// One step's turning knob, out the way the step faces (off its top, for
    /// what does not face) — the thing's own knob, for that step.
    private func stepKnob(_ e: DiagramEl, _ i: Int, _ m: DiagramModel, _ size: CGSize) -> Handle? {
        guard let c = stepFrame(e, i, m, size) else { return nil }
        let edge = knobEdge(e, c)
        let mid = CGPoint(x: (c[0].x + c[2].x) / 2, y: (c[0].y + c[2].y) / 2)
        let dx = edge.x - mid.x, dy = edge.y - mid.y
        let len = max(hypot(dx, dy), 0.001)
        // A turn's knob stands further out, clear of the thing's own.
        let out: CGFloat = e.spots[i].turn ? 52 : 22
        return Handle(kind: "stepturn", at: CGPoint(x: edge.x + dx / len * out, y: edge.y + dy / len * out), index: i)
    }

    /// A picked step's outline, and its knob.
    private func stepOutline(_ e: DiagramEl, _ i: Int, _ cg: CGContext, _ m: DiagramModel, _ size: CGSize, handles withHandles: Bool) {
        guard let c = stepFrame(e, i, m, size) else { return }
        cg.saveGState()
        defer { cg.restoreGState() }
        cg.setStrokeColor(DiagramInk.pick.cgColor)
        cg.setLineWidth(1.2)
        cg.move(to: c[0]); c.dropFirst().forEach { cg.addLine(to: $0) }
        cg.closePath()
        cg.strokePath()
        guard withHandles, !e.locked, let k = stepKnob(e, i, m, size) else { return }
        let edge = knobEdge(e, c)
        cg.setLineWidth(1)
        cg.move(to: edge); cg.addLine(to: k.at); cg.strokePath()
        let r = CGRect(x: k.at.x - 5, y: k.at.y - 5, width: 10, height: 10)
        cg.setFillColor(NSColor.white.cgColor)
        cg.setLineWidth(1.4)
        cg.fillEllipse(in: r); cg.strokeEllipse(in: r)
    }

    /// Whose step's ghost is under a point, the picked thing's first: any
    /// step but the one it stands on at this beat, and not a turn — a turn
    /// shares its spot, and is taken by its knob.
    private func hitStep(_ p: CGPoint) -> (DiagramEl, Int)? {
        guard let m = model else { return nil }
        let tol = 4 / m.scale
        let order = m.picked + m.plan.els.reversed().filter { !m.selection.contains($0.id) }
        for e in order where e.hasSteps && !e.hidden && !e.locked {
            let now = e.at(beat: m.beat)
            for (i, t) in e.spots.enumerated().reversed() where !t.turn {
                if abs(t.x - now.x) < 1e-6 && abs(t.y - now.y) < 1e-6 { continue }
                let (w, h) = e.footprint(at: max(t.beat, 1))
                let r = t.rot * .pi / 180
                let (dx, dy) = (p.x - t.x, p.y - t.y)
                let lx = dx * cos(r) + dy * sin(r), ly = -dx * sin(r) + dy * cos(r)
                if abs(lx) <= w / 2 + tol && abs(ly) <= h / 2 + tol { return (e, i) }
            }
        }
        return nil
    }

    /// For a checking run: where a thing's step is on screen — the one
    /// asked for by letter-order index, else the picked one, else its last.
    func stepPointOf(_ id: String, _ i: Int? = nil) -> CGPoint? {
        guard let m = model, let e = m.el(id), e.hasSteps else { return nil }
        let n = i ?? (m.stepPick?.e.id == id ? m.stepPick?.i : nil) ?? e.spots.lastIndex { !$0.home } ?? 0
        guard e.spots.indices.contains(n) else { return nil }
        return m.toView(CGPoint(x: e.spots[n].x, y: e.spots[n].y), size: bounds.size)
    }

    private func cameraReach(_ e: DiagramEl) -> Double {
        if e.reach > 0 { return e.reach }
        let focal = e.focal ?? (e.lens > 0 ? e.lens : 35)
        return min(max(focal / 10, 1.8), 9)
    }

    private func curveHandle(_ e: DiagramEl, _ m: DiagramModel, _ size: CGSize) -> CGPoint {
        let (dx, dy) = (e.x2 - e.x, e.y2 - e.y)
        let len = max(hypot(dx, dy), 1e-9)
        let (nx, ny) = (-dy / len, dx / len)
        let mid = CGPoint(x: (e.x + e.x2) / 2 + nx * e.curve, y: (e.y + e.y2) / 2 + ny * e.curve)
        return m.toView(mid, size: size)
    }

    private func outline(_ e: DiagramEl, _ cg: CGContext, _ m: DiagramModel, _ size: CGSize,
                         colour: NSColor, handles withHandles: Bool, width: CGFloat = 1.2) {
        cg.saveGState()
        cg.setStrokeColor(colour.cgColor)
        cg.setLineWidth(width)
        if e.isWall || e.isRuler {
            // Its centre line, dashed; the stretch picked for its length, solid.
            // A ruler runs through its markers.
            let r = e.run.map { m.toView($0, size: size) }
            cg.setLineDash(phase: 0, lengths: [4, 3])
            if let f = r.first { cg.move(to: f); r.dropFirst().forEach { cg.addLine(to: $0) } }
            cg.strokePath()
            if withHandles, let s = m.pickedStretch, s < e.stretches.count {
                let st = e.stretches[s]
                cg.setLineDash(phase: 0, lengths: [])
                cg.setLineWidth(3)
                cg.move(to: m.toView(st.0, size: size)); cg.addLine(to: m.toView(st.1, size: size))
                cg.strokePath()
            }
        } else if e.isLine {
            let a = m.toView(CGPoint(x: e.x, y: e.y), size: size), b = m.toView(CGPoint(x: e.x2, y: e.y2), size: size)
            cg.setLineDash(phase: 0, lengths: [4, 3])
            cg.move(to: a)
            if abs(e.curve) > 1e-6 {
                let c = curveHandle(e, m, size)
                let ctrl = CGPoint(x: 2 * c.x - (a.x + b.x) / 2, y: 2 * c.y - (a.y + b.y) / 2)
                cg.addQuadCurve(to: b, control: ctrl)
            } else {
                cg.addLine(to: b)
            }
            cg.strokePath()
        } else if e.isPolyline {
            let pts = e.points.map { m.toView(CGPoint(x: $0[0], y: $0[1]), size: size) }
            if let minX = pts.map(\.x).min(), let maxX = pts.map(\.x).max(),
               let minY = pts.map(\.y).min(), let maxY = pts.map(\.y).max() {
                cg.setLineDash(phase: 0, lengths: [4, 3])
                cg.stroke(CGRect(x: minX - 4, y: minY - 4, width: maxX - minX + 8, height: maxY - minY + 8))
            }
        } else {
            let c = frame(e, m, size)
            cg.move(to: c[0]); c.dropFirst().forEach { cg.addLine(to: $0) }
            cg.closePath()
            cg.strokePath()
        }
        cg.restoreGState()
        guard withHandles else { return }
        // **A camera's storyboard frame, sized by its corners** (his note,
        // 2026-10-05): a knob at each, the corner across staying put.
        if e.kind == "camera", !e.locked, let r = frameRect(e) {
            cg.saveGState()
            cg.setStrokeColor(colour.cgColor)
            cg.setLineWidth(1)
            cg.setLineDash(phase: 0, lengths: [4, 3])
            cg.stroke(r.insetBy(dx: -1.5, dy: -1.5))
            cg.setLineDash(phase: 0, lengths: [])
            cg.setLineWidth(1.4)
            cg.setFillColor(NSColor.white.cgColor)
            for c in frameCorners(r) {
                let k = CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)
                cg.fill(k); cg.stroke(k)
            }
            cg.restoreGState()
        }
        let hs = handles(e, m, size)
        if let rot = hs.first(where: { $0.kind == "rotate" }) {
            let top = knobEdge(e, frame(e, m, size))
            cg.setStrokeColor(colour.cgColor)
            cg.setLineWidth(1)
            cg.move(to: top); cg.addLine(to: rot.at); cg.strokePath()
        }
        // Its turns: each heading's knob on a dashed stalk, marked with its
        // letter so it is never taken for the thing's own.
        for knob in hs where knob.kind == "stepturn" {
            guard let c = stepFrame(e, knob.index, m, size) else { continue }
            let edge = knobEdge(e, c)
            cg.saveGState()
            cg.setStrokeColor(colour.cgColor)
            cg.setLineWidth(1)
            cg.setLineDash(phase: 0, lengths: [3, 3])
            cg.move(to: edge); cg.addLine(to: knob.at); cg.strokePath()
            cg.restoreGState()
            DiagramPainter.words(e.spots[knob.index].letter, at: CGPoint(x: knob.at.x + 12, y: knob.at.y),
                                 font: .systemFont(ofSize: 9.5, weight: .bold), colour: colour,
                                 anchor: "start", rot: 0, halo: true, cg: cg, dark: dark)
        }
        // The tilt knob's track, and how far the frame stands.
        if let k = hs.first(where: { $0.kind == "tilt" }) {
            let t = tiltTrack(e, m, size)
            cg.saveGState()
            cg.setStrokeColor(colour.withAlphaComponent(0.4).cgColor)
            cg.setLineWidth(2)
            cg.setLineCap(.round)
            cg.move(to: t.flat); cg.addLine(to: t.upright); cg.strokePath()
            cg.restoreGState()
            // The angle out past the knob, clear of the frame's corners.
            let away = tiltAway(e, m, size)
            let side = abs(away.x) >= abs(away.y)
            let at = side ? CGPoint(x: k.at.x + away.x * 13, y: k.at.y)
                          : CGPoint(x: k.at.x, y: k.at.y + away.y * 17)
            DiagramPainter.words("\(Int(e.tilt.rounded()))°", at: at,
                                 font: .systemFont(ofSize: 9.5, weight: .bold), colour: colour,
                                 anchor: side ? (away.x > 0 ? "start" : "end") : "middle", rot: 0, halo: true, cg: cg, dark: dark)
        }
        for h in hs {
            let r: CGRect
            switch h.kind {
            case "corner", "end": r = CGRect(x: h.at.x - 4, y: h.at.y - 4, width: 8, height: 8)
            default: r = CGRect(x: h.at.x - 5, y: h.at.y - 5, width: 10, height: 10)
            }
            cg.setFillColor(NSColor.white.cgColor)
            cg.setStrokeColor(colour.cgColor)
            cg.setLineWidth(1.4)
            switch h.kind {
            case "corner", "end":
                cg.fill(r); cg.stroke(r)
            case "wallcorner":
                // A wall's corner; the one picked, filled.
                if m.pickedCorner == h.index { cg.setFillColor(colour.cgColor) }
                cg.fill(r); cg.stroke(r)
            case "addcorner", "extend":
                // A + to add a corner, or to grow the wall on.
                let o = CGRect(x: h.at.x - 6, y: h.at.y - 6, width: 12, height: 12)
                cg.fillEllipse(in: o); cg.strokeEllipse(in: o)
                cg.setLineWidth(1.3)
                cg.move(to: CGPoint(x: h.at.x - 3, y: h.at.y)); cg.addLine(to: CGPoint(x: h.at.x + 3, y: h.at.y))
                cg.move(to: CGPoint(x: h.at.x, y: h.at.y - 3)); cg.addLine(to: CGPoint(x: h.at.x, y: h.at.y + 3))
                cg.strokePath()
            case "hin", "hout":
                // A curve handle: a small round knob on a line from its point.
                if let f = h.from {
                    cg.setLineWidth(1)
                    cg.move(to: f); cg.addLine(to: h.at); cg.strokePath()
                    cg.setLineWidth(1.4)
                }
                let o = CGRect(x: h.at.x - 3.5, y: h.at.y - 3.5, width: 7, height: 7)
                cg.setFillColor(colour.cgColor)
                cg.fillEllipse(in: o)
            case "reach":
                // How far a cone or beam reaches: a diamond, never taken
                // for the round turning knob.
                let d = [CGPoint(x: h.at.x, y: h.at.y - 6), CGPoint(x: h.at.x + 6, y: h.at.y),
                         CGPoint(x: h.at.x, y: h.at.y + 6), CGPoint(x: h.at.x - 6, y: h.at.y)]
                cg.addLines(between: d); cg.closePath()
                cg.drawPath(using: .fillStroke)
            case "curve":
                // A wall's bend: a small solid dot on the wall itself.
                cg.setFillColor(colour.cgColor)
                cg.fillEllipse(in: r.insetBy(dx: 1.5, dy: 1.5))
            case "tilt":
                // A frame's tilt: bigger than the turning knob, with an arrow
                // each way along its track, never taken for it.
                let t = tiltTrack(e, m, size)
                let (dx, dy) = (t.upright.x - t.flat.x, t.upright.y - t.flat.y)
                let len = max(hypot(dx, dy), 0.001)
                let (ux, uy) = (dx / len, dy / len)
                let o = CGRect(x: h.at.x - 8, y: h.at.y - 8, width: 16, height: 16)
                cg.fillEllipse(in: o); cg.strokeEllipse(in: o)
                cg.setFillColor(colour.cgColor)
                for sgn in [CGFloat(1), -1] {
                    let tip = CGPoint(x: h.at.x + ux * 5.5 * sgn, y: h.at.y + uy * 5.5 * sgn)
                    let base = CGPoint(x: h.at.x + ux * 1.5 * sgn, y: h.at.y + uy * 1.5 * sgn)
                    cg.move(to: tip)
                    cg.addLine(to: CGPoint(x: base.x - uy * 3.2, y: base.y + ux * 3.2))
                    cg.addLine(to: CGPoint(x: base.x + uy * 3.2, y: base.y - ux * 3.2))
                    cg.closePath()
                }
                cg.fillPath()
            default:
                cg.fillEllipse(in: r); cg.strokeEllipse(in: r)
            }
        }
    }

    private func drawInProgress(_ cg: CGContext, _ m: DiagramModel, _ size: CGSize) {
        let ink = DiagramInk.pick
        cg.saveGState()
        defer { cg.restoreGState() }
        cg.setStrokeColor(ink.cgColor)
        cg.setLineWidth(1.4)
        switch drag {
        case .marquee(let a, let b, _):
            // Square to the screen, however the plan is turned.
            let (va, vb) = (m.toView(a, size: size), m.toView(b, size: size))
            let v = CGRect(x: min(va.x, vb.x), y: min(va.y, vb.y), width: abs(va.x - vb.x), height: abs(va.y - vb.y))
            cg.setFillColor(ink.withAlphaComponent(0.08).cgColor)
            cg.fill(v)
            cg.stroke(v)
        case .line where m.tool.pins && m.calibrating == nil:
            break // drawn by the engine, as it will be (`mouseDragged`)
        case .line(let a, let b):
            let (va, vb) = (m.toView(a, size: size), m.toView(b, size: size))
            cg.move(to: va); cg.addLine(to: vb); cg.strokePath()
            measureLabel(a, b, cg, m, size)
        case .wall(let a, let b):
            let (va, vb) = (m.toView(a, size: size), m.toView(b, size: size))
            cg.setLineWidth(3)
            cg.move(to: va); cg.addLine(to: vb); cg.strokePath()
            measureLabel(a, b, cg, m, size)
        case .box(let a, let b):
            // Square to the plan: turned with it.
            let pts = [a, CGPoint(x: b.x, y: a.y), b, CGPoint(x: a.x, y: b.y)].map { m.toView($0, size: size) }
            cg.setLineDash(phase: 0, lengths: [5, 4])
            cg.addLines(between: pts)
            cg.closePath()
            cg.strokePath()
            let v = CGRect(x: pts.map(\.x).min()!, y: pts.map(\.y).min()!,
                           width: pts.map(\.x).max()! - pts.map(\.x).min()!, height: pts.map(\.y).max()! - pts.map(\.y).min()!)
            DiagramPainter.words("\(m.length(abs(b.x - a.x))) × \(m.length(abs(b.y - a.y)))",
                  at: CGPoint(x: v.midX, y: v.maxY + 12), font: .systemFont(ofSize: 10.5, weight: .semibold),
                  colour: ink, anchor: "middle", rot: 0, halo: true, cg: cg, dark: dark)
        case .placing(let at, let rot):
            let v = m.toView(at, size: size)
            let r = rot * .pi / 180 + m.turn
            cg.setLineDash(phase: 0, lengths: [4, 3])
            cg.move(to: v)
            cg.addLine(to: CGPoint(x: v.x + cos(r) * 40, y: v.y + sin(r) * 40))
            cg.strokePath()
        default:
            break
        }
        // The Draw tool's path so far, its next leg following the pointer.
        if m.tool == .pen, !m.drawNodes.isEmpty {
            let ink = DiagramInk.color(m.drawAs == "wall" || m.penColour.isEmpty ? "ink" : m.penColour, dark: dark)!
            let nodes = m.drawNodes
            let v = { (p: CGPoint) in m.toView(p, size: size) }
            cg.setLineDash(phase: 0, lengths: [])
            cg.setStrokeColor(ink.cgColor)
            cg.setLineWidth(m.drawAs == "wall" ? 3 : 2)
            cg.setLineCap(.round); cg.setLineJoin(.round)
            cg.move(to: v(nodes[0].p))
            for i in 1..<nodes.count {
                let (a, b) = (nodes[i - 1], nodes[i])
                cg.addCurve(to: v(b.p), control1: v(CGPoint(x: a.p.x + a.hout.dx, y: a.p.y + a.hout.dy)),
                            control2: v(CGPoint(x: b.p.x + b.hin.dx, y: b.p.y + b.hin.dy)))
            }
            if let now = mouseWorld, case .none = drag, let a = nodes.last {
                cg.addCurve(to: v(now), control1: v(CGPoint(x: a.p.x + a.hout.dx, y: a.p.y + a.hout.dy)), control2: v(now))
            }
            cg.strokePath()
            // Its points, and the handle just pulled out.
            for (i, n) in nodes.enumerated() {
                let q = v(n.p)
                let close = i == 0 && nodes.count >= 3 && (mouseWorld.map { hypot($0.x - n.p.x, $0.y - n.p.y) * m.scale < 9 } ?? false)
                let r: CGFloat = close ? 6 : 4
                cg.setFillColor(close ? ink.cgColor : NSColor.white.cgColor)
                cg.setStrokeColor(ink.cgColor)
                cg.setLineWidth(1.4)
                cg.fill(CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r))
                cg.stroke(CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r))
                if i == nodes.count - 1, abs(n.hout.dx) + abs(n.hout.dy) > 1e-9 {
                    for h in [n.hin, n.hout] {
                        let k = v(CGPoint(x: n.p.x + h.dx, y: n.p.y + h.dy))
                        cg.setLineWidth(1)
                        cg.move(to: q); cg.addLine(to: k); cg.strokePath()
                        cg.setFillColor(ink.cgColor)
                        cg.fillEllipse(in: CGRect(x: k.x - 3, y: k.y - 3, width: 6, height: 6))
                    }
                }
            }
        }
        // A chain of walls or a cable, with its next leg following the pointer.
        // Walls stand as each is drawn (his note, 2026-09-29: "wall by
        // wall"), so only the leg to come is drawn here — and the first
        // corner, which a click closes the room on.
        if !m.pending.isEmpty {
            cg.setLineDash(phase: 0, lengths: [])
            cg.setStrokeColor(ink.cgColor)
            cg.setLineWidth(m.tool == .wall ? 3 : 1.6)
            let legs = m.tool == .wall ? [m.pending.last!] : m.pending
            cg.move(to: m.toView(legs[0], size: size))
            legs.dropFirst().forEach { cg.addLine(to: m.toView($0, size: size)) }
            if let now = mouseWorld {
                cg.addLine(to: m.toView(now, size: size))
            }
            cg.strokePath()
            for p in m.tool == .wall ? [m.pending.first!, m.pending.last!] : m.pending {
                let v = m.toView(p, size: size)
                cg.setFillColor(NSColor.white.cgColor)
                cg.fillEllipse(in: CGRect(x: v.x - 3, y: v.y - 3, width: 6, height: 6))
                cg.strokeEllipse(in: CGRect(x: v.x - 3, y: v.y - 3, width: 6, height: 6))
            }
            if let now = mouseWorld, let last = m.pending.last {
                measureLabel(last, now, cg, m, size)
            }
        }
    }

    private func measureLabel(_ a: CGPoint, _ b: CGPoint, _ cg: CGContext, _ m: DiagramModel, _ size: CGSize) {
        let len = hypot(b.x - a.x, b.y - a.y)
        guard len > 0.05 else { return }
        let mid = m.toView(CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), size: size)
        DiagramPainter.words(m.length(len), at: CGPoint(x: mid.x, y: mid.y - 12), font: .systemFont(ofSize: 10.5, weight: .semibold),
              colour: DiagramInk.pick, anchor: "middle", rot: 0, halo: true, cg: cg, dark: dark)
    }

    // MARK: the readout by the pointer

    /// **The size, angle or distance while it changes** (Scenario's): W × D
    /// while a corner is pulled, the heading while a knob turns, how far the
    /// pick has gone while it is dragged — in the film's units, rounded as
    /// the plan rounds them. Nil when nothing is being changed.
    func readout(_ m: DiagramModel, _ size: CGSize) -> (String, CGPoint)? {
        guard dragged, let at = pointerView else { return nil }
        func deg(_ d: Double) -> String {
            let r = (d.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
            let shown = (r * 10).rounded() / 10
            return shown == shown.rounded() ? "\(Int(shown) % 360)°" : String(format: "%.1f°", shown)
        }
        func signed(_ v: CGFloat) -> String { (v < -1e-6 ? "−" : "") + m.length(abs(Double(v))) }
        let text: String
        switch drag {
        case .moving(_, let ids, _, let d):
            guard !ids.isEmpty, d != .zero else { return nil }
            // In the plan's own ways across and down, as Details reads x and y.
            var parts: [String] = []
            if abs(d.x) > 1e-6 { parts.append("Δx \(signed(d.x))") }
            if abs(d.y) > 1e-6 { parts.append("Δy \(signed(d.y))") }
            text = parts.joined(separator: "  ")
        case .resizing(let e, _, let set):
            // A lamp's mark: how big against its page size.
            if let k = set["mark_k"] as? Double { text = "\(Int((k * 100).rounded()))%"; break }
            guard let w = set["w"] as? Double, let h = set["h"] as? Double else { return nil }
            // A frame reads across × tall, as its sides say.
            if e.sym == DiagramFrames.sym { text = "\(m.length(h)) × \(m.length((set["tall"] as? Double) ?? e.tall))" }
            else { text = "\(m.length(w)) × \(m.length(h))" }
        case .rotating(_, let rot): text = deg(rot)
        case .stepTurning(_, _, let rot): text = deg(rot)
        case .turningPick(_, _, let base, let d): text = deg(base + d)
        case .reaching(_, let r): text = m.length(r)
        default: return nil
        }
        guard !text.isEmpty else { return nil }
        return (text, CGPoint(x: at.x + 16, y: at.y + 22))
    }

    private func drawReadout(_ text: String, at p: CGPoint, _ cg: CGContext) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let s = NSAttributedString(string: text, attributes: attrs)
        let sz = s.size()
        var r = CGRect(x: p.x, y: p.y - sz.height / 2 - 3, width: sz.width + 12, height: sz.height + 6)
        // Kept on the plan near its right and bottom edges.
        if r.maxX > bounds.maxX - 4 { r.origin.x = p.x - 32 - r.width }
        if r.maxY > bounds.maxY - 4 { r.origin.y = p.y - 44 - r.height }
        cg.saveGState()
        cg.setFillColor(DiagramInk.pick.cgColor)
        cg.addPath(CGPath(roundedRect: r, cornerWidth: 5, cornerHeight: 5, transform: nil))
        cg.fillPath()
        cg.restoreGState()
        NSGraphicsContext.saveGraphicsState()
        s.draw(at: CGPoint(x: r.minX + 6, y: r.minY + 3))
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: the mouse

    private func world(_ event: NSEvent) -> CGPoint {
        guard let m = model else { return .zero }
        return m.toWorld(convert(event.locationInWindow, from: nil), size: bounds.size)
    }

    /// What a marquee dragged between two plan points takes in. It is square
    /// to the screen; turned, the engine is asked for the plan box round it
    /// and each answer kept only if it shows inside.
    private func marqueeCatch(from a: CGPoint, to b: CGPoint, engine: Engine, scene: String) -> [String] {
        guard let m = model else { return [] }
        let size = bounds.size
        let (va, vb) = (m.toView(a, size: size), m.toView(b, size: size))
        let screen = CGRect(x: min(va.x, vb.x), y: min(va.y, vb.y), width: abs(va.x - vb.x), height: abs(va.y - vb.y))
        let corners = [CGPoint(x: screen.minX, y: screen.minY), CGPoint(x: screen.maxX, y: screen.minY),
                       CGPoint(x: screen.maxX, y: screen.maxY), CGPoint(x: screen.minX, y: screen.maxY)].map { m.toWorld($0, size: size) }
        let world = CGRect(x: corners.map(\.x).min()!, y: corners.map(\.y).min()!,
                           width: corners.map(\.x).max()! - corners.map(\.x).min()!,
                           height: corners.map(\.y).max()! - corners.map(\.y).min()!)
        let unseen = m.unseenIds, locked = lockedIds
        let caught = engine.diagramWithin(scene: scene, world).filter { !unseen.contains($0) && !locked.contains($0) }
        if abs(m.turn) < 1e-9 { return caught }
        return caught.filter { id in
            guard let e = m.el(id) else { return false }
            let pts: [CGPoint]
            if e.isWall { pts = e.run.map { m.toView($0, size: size) } }
            else if e.isLine { pts = [CGPoint(x: e.x, y: e.y), CGPoint(x: e.x2, y: e.y2)].map { m.toView($0, size: size) } }
            else if e.isPolyline { pts = e.points.map { m.toView(CGPoint(x: $0[0], y: $0[1]), size: size) } }
            else { pts = frame(e, m, size) }
            guard let x0 = pts.map(\.x).min(), let x1 = pts.map(\.x).max(),
                  let y0 = pts.map(\.y).min(), let y1 = pts.map(\.y).max() else { return false }
            return CGRect(x: x0, y: y0, width: max(x1 - x0, 0.5), height: max(y1 - y0, 0.5)).intersects(screen)
        }
    }

    /// Snap a new point: a wall's corner or line in reach, lined up square
    /// with a corner, else the grid — unless ⌘ is held. `own`: the wall
    /// corner being dragged or drawn; its line-ups are kept to draw.
    private func snapped(_ p: CGPoint, _ event: NSEvent?, skip: [String] = [], own: (String, Int)? = nil) -> CGPoint {
        guard let m = model, let engine = m.engine, let scene = m.scene else { return p }
        if event?.modifierFlags.contains(.command) == true { wallGuides = []; return p }
        let reach = 10 / m.scale
        let s = engine.diagramSnap(scene: scene, x: p.x, y: p.y, reach: reach, skip: skip, step: m.snapStep, own: own)
        if own != nil || m.tool == .wall { wallGuides = s.guides }
        return CGPoint(x: s.x, y: s.y)
    }

    /// Where the next corner of the wall being drawn lands — lined up with
    /// its own corners as well as every other wall's.
    private func drawingSnap(_ p: CGPoint, _ event: NSEvent?) -> CGPoint {
        guard let m = model else { return p }
        if let id = m.drawingWall, let e = m.el(id) { return snapped(p, event, own: (id, e.corners.count)) }
        return snapped(p, event)
    }

    /// Hold ⇧ to keep a line to the nearest eighth of a turn: the point
    /// dropped straight onto that line — not swung round to it, which kept
    /// a slanted hand's longer length (36 ft drawn read 36 ft 1 in) — and,
    /// with Snap on, its length a whole number of grid steps.
    private func constrained(_ a: CGPoint, _ b: CGPoint, _ event: NSEvent) -> CGPoint {
        guard event.modifierFlags.contains(.shift), let m = model else { return b }
        let eighth = Int((atan2(b.y - a.y, b.x - a.x) / (.pi / 4)).rounded())
        // Exact for the square ways, so a level wall stays exactly level.
        let k = 0.5.squareRoot()
        let dirs: [(CGFloat, CGFloat)] = [(1, 0), (k, k), (0, 1), (-k, k), (-1, 0), (-k, -k), (0, -1), (k, -k)]
        let (cx, cy) = dirs[((eighth % 8) + 8) % 8]
        var len = (b.x - a.x) * cx + (b.y - a.y) * cy
        if m.settings.snap, !event.modifierFlags.contains(.command) {
            let step = CGFloat(m.snapStep)
            len = (len / step).rounded() * step
        }
        return CGPoint(x: a.x + cx * len, y: a.y + cy * len)
    }

    /// For a checking run: where a picked thing's handle is on screen —
    /// `turn` is the pick's box's knob (a wall, several, a group).
    func handlePoint(kind: String, index: Int) -> CGPoint? {
        guard let m = model else { return nil }
        if kind == "turn" { return pickKnob(m, bounds.size) }
        guard let e = m.picked.first else { return nil }
        return handles(e, m, bounds.size).first { $0.kind == kind && $0.index == index }?.at
    }

    /// For a checking run: where a thing stands on screen.
    func pointOf(_ id: String) -> CGPoint? {
        guard let m = model, let e = m.el(id) else { return nil }
        // A wall by the middle of its first stretch — the inside of a room is
        // floor, not wall.
        if e.isWall, let st = e.stretches.first {
            return m.toView(CGPoint(x: (st.0.x + st.1.x) / 2, y: (st.0.y + st.1.y) / 2), size: bounds.size)
        }
        if e.isLine { return m.toView(CGPoint(x: (e.x + e.x2) / 2, y: (e.y + e.y2) / 2), size: bounds.size) }
        let now = e.at(beat: m.beat)
        return m.toView(CGPoint(x: now.x, y: now.y), size: bounds.size)
    }

    private func hitHandle(_ v: CGPoint) -> (DiagramEl, Handle)? {
        guard let m = model, let e = m.picked.first else { return nil }
        // The pick's box's knob: a wall, several, a group.
        if let k = pickKnob(m, bounds.size), hypot(k.x - v.x, k.y - v.y) <= 8 {
            return (e, Handle(kind: "turn", at: k, index: 0))
        }
        guard m.picked.count == 1 else { return nil }
        // **The body wins** inside a piece with one: a small piece's handles
        // never take the press meant to move it.
        let body: CGPath? = e.isLine || e.isPolyline || m.stepPick != nil ? nil : {
            let c = frame(e, m, bounds.size)
            let p = CGMutablePath()
            p.addLines(between: c)
            p.closeSubpath()
            return p
        }()
        let inside = body?.contains(v) ?? false
        for h in handles(e, m, bounds.size) where hypot(h.at.x - v.x, h.at.y - v.y) <= 7 {
            if inside, ["corner", "reach", "rotate"].contains(h.kind) { continue }
            return (e, h)
        }
        return nil
    }

    /// **A locked piece is clicked straight through** (Scenario's way): a
    /// plain click, a hover or a drag-select never finds it — a locked
    /// floor plan under everything no longer swallows them. `all` finds it
    /// anyway: the right-click, which offers Unlock.
    private func hitTag(_ v: CGPoint, all: Bool = false) -> String? {
        let locked = all ? [] : lockedIds
        return tagRects.last { $0.0.insetBy(dx: -2, dy: -2).contains(v) && !locked.contains($0.1) }?.1
    }

    private func hitElement(_ p: CGPoint, all: Bool = false) -> String? {
        guard let m = model, let engine = m.engine, let scene = m.scene else { return nil }
        let skip = all ? m.unseenIds.union(m.layerLockedIds) : m.unseenIds.union(lockedIds)
        let found = engine.diagramHit(scene: scene, x: p.x, y: p.y, tolerance: 4 / m.scale, beat: m.beat, skip: skip)
        if let id = found, m.el(id)?.hug == true { return id }
        // **A small lamp is taken anywhere in its outline** (2026-10-17): the
        // outline round its mark is never under 26 points, and a click
        // inside it takes the lamp, as a click inside any outline does.
        let reach = 13 / m.scale
        if let lamp = m.plan.els.last(where: { e in
            guard e.hug == true, !skip.contains(e.id) else { return false }
            let at = e.at(beat: m.beat)
            return hypot(at.x - p.x, at.y - p.y) <= max(reach, (e.drawn?.first ?? 0) / 2)
        }) { return lamp.id }
        return found
    }

    /// **The piece an arrow's end lands on** (SL-1231): the top thing under
    /// the point that is not a line, a drawing or a picture — what a note
    /// points at.
    private func pinTarget(_ p: CGPoint, skip: [String]) -> String? {
        guard let m = model, let engine = m.engine, let scene = m.scene else { return nil }
        var skipped = m.unseenIds.union(skip)
        for _ in 0..<6 {
            guard let id = engine.diagramHit(scene: scene, x: p.x, y: p.y, tolerance: 6 / m.scale, beat: m.beat, skip: skipped),
                  let e = m.el(id) else { return nil }
            if e.isLine || e.isPolyline || e.kind == "image" { skipped.insert(id); continue }
            return id
        }
        return nil
    }

    /// **What a ruler's marker holds on to**: a person, a camera or a lamp, whose
    /// middle is the point. Never a table, a wall or any other box: its edge is
    /// what is measured, and the marker stays exactly where it was let go
    /// (his report, 2026-10-06: it jumped to the table's middle). With Snap
    /// off, or ⌘ held, it holds on to nothing.
    private func rulerTarget(_ p: CGPoint, skip: [String], _ event: NSEvent?) -> String? {
        guard let m = model, m.settings.snap, event?.modifierFlags.contains(.command) != true,
              let id = pinTarget(p, skip: skip), let e = m.el(id),
              ["cast", "camera", "light"].contains(e.kind) else { return nil }
        return id
    }

    /// Locked pieces, and the layer not being worked in (Ref 1498).
    private var lockedIds: Set<String> {
        guard let m = model else { return [] }
        return Set(m.plan.els.filter(\.locked).map(\.id)).union(m.layerLockedIds)
    }

    /// Everything that moves with what was clicked: its group.
    private func withGroup(_ id: String) -> [String] {
        guard let m = model, let e = m.el(id), !e.group.isEmpty, m.enteredGroup != e.group else { return [id] }
        return m.plan.els.filter { $0.group == e.group }.map(\.id)
    }

    /// **What lands on the grid when the pick is moved**, one number for
    /// each way: a lamp, a camera or a person by its middle; a piece with a
    /// body by whichever of its edges is nearer the hand, so its edges sit
    /// on grid lines (its middle on one put an 11 × 8 ft box's edges off);
    /// a wall by its nearer end; several, or a group, by the edges of the
    /// box round them all.
    private func snapRef(_ ids: [String], clicked: String, press p: CGPoint) -> CGPoint? {
        guard let m = model, let e = m.el(clicked) else { return nil }
        func nearer(_ a: CGFloat, _ b: CGFloat, to v: CGFloat) -> CGFloat { abs(a - v) <= abs(b - v) ? a : b }
        if ids.count > 1, let box = m.extent(ids) {
            return CGPoint(x: nearer(box.minX, box.maxX, to: p.x), y: nearer(box.minY, box.maxY, to: p.y))
        }
        // A wall by its corner nearest the hand.
        if e.isWall { return e.corners.min { hypot($0.x - p.x, $0.y - p.y) < hypot($1.x - p.x, $1.y - p.y) } }
        if e.isLine { return CGPoint(x: nearer(e.x, e.x2, to: p.x), y: nearer(e.y, e.y2, to: p.y)) }
        if e.isPolyline, let f = e.points.first, f.count > 1 { return CGPoint(x: f[0], y: f[1]) }
        let now = e.at(beat: m.beat)
        if Self.faces(e) || e.kind == "text" { return CGPoint(x: now.x, y: now.y) }
        guard let box = m.extent([clicked]) else { return CGPoint(x: now.x, y: now.y) }
        return CGPoint(x: nearer(box.minX, box.maxX, to: p.x), y: nearer(box.minY, box.maxY, to: p.y))
    }

    /// Esc while dragging: the drag is dropped, and nothing it did is kept.
    private func cancelDrag() {
        guard let m = model else { return }
        if case .none = drag { return }
        m.preview = nil
        if let was = copiedFrom { m.state?.undo(quiet: true); m.selection = was }
        copiedFrom = nil
        copyOnMove = false
        drag = .none
        guides = []; linedUp = []
        aimAt = nil
        needsDisplay = true
    }

    /// Whether a plan point lies on a picture, its turn allowed for.
    static func inside(_ p: CGPoint, _ e: DiagramEl) -> Bool {
        let r = e.rot * .pi / 180
        let dx = Double(p.x) - e.x, dy = Double(p.y) - e.y
        let lx = dx * cos(r) + dy * sin(r), ly = -dx * sin(r) + dy * cos(r)
        return abs(lx) <= e.w / 2 && abs(ly) <= e.h / 2
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        // Space let go of while another window had the keys never sends its
        // key-up here; ask the keyboard rather than stay stuck panning.
        if spaceHeld && !CGEventSource.keyState(.combinedSessionState, key: 49) { letGoOfSpace() }
        guard let m = model else { return }
        // Drawing on a picture: the editor over it has the hand; the plan
        // around it is left alone.
        if m.photoEditing != nil { return }
        let v = convert(event.locationInWindow, from: nil)
        let p = m.toWorld(v, size: bounds.size)
        dragged = false
        mouseDownAt = p

        // Presenting, the plan can be moved about and nothing on it touched.
        if m.tool == .hand || spaceHeld || event.buttonNumber == 2 || m.presenting {
            drag = .panning(last: v)
            NSCursor.closedHand.set()
            return
        }

        if event.clickCount == 2 {
            if [.wall, .cable].contains(m.tool), !m.pending.isEmpty {
                finishChain(closed: false)
                return
            }
            if m.tool == .pen, !m.drawNodes.isEmpty {
                finishPath(closed: false)
                return
            }
            // A corner double-clicked is made smooth, or sharp again.
            if m.tool == .select, let (e, h) = hitHandle(v), h.kind == "wallcorner", e.isWall || e.isPath {
                m.pickedCorner = h.index
                m.smoothCorner()
                return
            }
            // **Words double-clicked are typed in, right there** (his call
            // F): a lamp's Name or Note by the line clicked, Words whole.
            if m.tool == .select, !m.readOnly, let (id, what) = wordsAt(v, p) {
                m.startTyping(id, what)
                return
            }
            // **A camera's shot, in the sidebar** — his ask, 2026-10-01: *"The
            // sidebar should just come out when I double-click its shot. It
            // shouldn't be a hidden menu."* (It was a card with Show All.)
            if m.tool == .select, let id = hitTag(v) ?? hitElement(p), let e = m.el(id), e.kind == "camera" {
                m.selection = [id]
                m.openDetails()
                return
            }
            // Into a group: one of its pieces, picked on its own — moved,
            // turned, copied or deleted without the rest.
            if m.tool == .select, let id = hitTag(v) ?? hitElement(p), let e = m.el(id), !e.group.isEmpty {
                m.selection = [id]
                m.enteredGroup = e.group
                drag = .none
                needsDisplay = true
                return
            }
            // **A picture double-clicked is drawn on** (his ask, 2026-10-15),
            // a traced one under the plot too.
            if m.tool == .select, !m.readOnly {
                let hit = (hitTag(v) ?? hitElement(p)).flatMap { m.el($0) }
                if let e = hit, e.kind == "image" { m.drawOnPhoto(e.id); return }
                if hit == nil, let e = m.plan.els.last(where: { $0.kind == "image" && !$0.hidden && Self.inside(p, $0) }) {
                    m.drawOnPhoto(e.id)
                    return
                }
            }
            // Anything else double-clicked: its Details, asked for.
            if m.tool == .select, let id = hitTag(v) ?? hitElement(p), m.el(id) != nil {
                if !m.selection.contains(id) { m.selection = [id] }
                m.openDetails()
                return
            }
        }

        if m.calibrating != nil {
            drag = .line(from: p, to: p)
            return
        }
        switch placingOnPicked(v, p) ? .select : m.tool {
        case .select:
            if onCompass(v) {
                drag = .turningNorth(from: dial(v), was: m.settings.north, north: m.settings.north)
                return
            }
            if let (e, h) = hitHandle(v) {
                switch h.kind {
                case "corner":
                    // Held by the corner itself, not by the handle beside it —
                    // the footprint's, so a lamp outlined round its larger
                    // mark is sized from where it is, not from its mark.
                    let c = frame(e, m, bounds.size, footprint: true)[h.index]
                    let cw = m.toWorld(c, size: bounds.size)
                    resizeGrab = CGPoint(x: cw.x - p.x, y: cw.y - p.y)
                    drag = .resizing(el: e, corner: h.index, set: [:])
                case "rotate": drag = .rotating(el: e, rot: e.at(beat: m.beat).rot)
                case "turn":
                    let pivot = m.pivot()
                    drag = .turningPick(pivot: pivot, from: atan2(p.y - pivot.y, p.x - pivot.x) * 180 / .pi,
                                        base: m.heading(e), deg: 0)
                case "end":
                    let at = h.index == 0 ? CGPoint(x: e.x, y: e.y) : CGPoint(x: e.x2, y: e.y2)
                    let joined = event.modifierFlags.contains(.option) ? [] : Self.joined(to: e, at: at, in: m.plan.els)
                    drag = .endpoint(el: e, end: h.index, at: at, joined: joined)
                case "curve": drag = .curving(el: e, curve: e.curve)
                case "wallcorner":
                    cornerGrab = CGPoint(x: e.corners[h.index].x - p.x, y: e.corners[h.index].y - p.y)
                    m.pickedCorner = h.index
                    m.pickedStretch = nil
                    drag = .corner(el: e, index: h.index, at: e.corners[h.index], made: false,
                                   free: event.modifierFlags.contains(.option))
                case "hin", "hout":
                    let at = e.corners[h.index]
                    let hv = e.handle(h.index)
                    let v = h.kind == "hout" ? hv.out : hv.inn
                    cornerGrab = CGPoint(x: at.x + v.dx - p.x, y: at.y + v.dy - p.y)
                    drag = .handle(el: e, node: h.index, out: h.kind == "hout", at: CGPoint(x: at.x + v.dx, y: at.y + v.dy))
                case "addcorner":
                    // A corner added at the stretch's middle, picked, and
                    // dragged from there if the hand moves on.
                    m.edit(m.wallOp("wall_insert", e, ["stretch": h.index]))
                    if let now = m.el(e.id), h.index + 1 < now.corners.count {
                        m.pickedCorner = h.index + 1
                        m.pickedStretch = nil
                        let c = now.corners[h.index + 1]
                        cornerGrab = CGPoint(x: c.x - p.x, y: c.y - p.y)
                        drag = .corner(el: now, index: h.index + 1, at: c, made: true, free: false)
                    }
                case "extend":
                    // Grown on the way it runs, about eighty points' worth on
                    // the grid; the new corner picked and dragged from there.
                    let c = e.corners
                    let (a, b) = h.index == 0 ? (c[0], c[1]) : (c[c.count - 1], c[c.count - 2])
                    let len = max(hypot(a.x - b.x, a.y - b.y), 1e-6)
                    let step = CGFloat(m.snapStep)
                    let want = max(((80 / m.scale) / step).rounded() * step, step)
                    let to = CGPoint(x: a.x + (a.x - b.x) / len * want, y: a.y + (a.y - b.y) / len * want)
                    m.edit(m.wallOp("wall_extend", e, ["end": h.index == 0 ? "start" : "end", "x": to.x, "y": to.y]))
                    if let now = m.el(e.id) {
                        let i = h.index == 0 ? 0 : now.corners.count - 1
                        m.pickedCorner = i
                        m.pickedStretch = nil
                        cornerGrab = CGPoint(x: to.x - p.x, y: to.y - p.y)
                        drag = .corner(el: now, index: i, at: to, made: true, free: false)
                    }
                case "reach": drag = .reaching(el: e, reach: e.reach)
                case "tilt": drag = .tilting(el: e, start: p, tilt: e.tilt)
                case "stepturn":
                    // A turn's knob, on the thing as it stands, picks that turn.
                    if m.stepPick?.i != h.index { m.pickStep(e.id, h.index) }
                    drag = .stepTurning(el: e, step: h.index, rot: e.spots[h.index].rot)
                default: break
                }
                return
            }
            if nameDown(v, event) { return }
            if !event.modifierFlags.contains(.shift), let (e, i) = hitStep(p) {
                m.pickStep(e.id, i)
                drag = .stepping(el: e, step: i, start: p, at: CGPoint(x: e.spots[i].x, y: e.spots[i].y))
                return
            }
            if let id = hitTag(v) ?? hitElement(p) {
                // The thing itself, not one of its steps.
                m.pickedStep = nil
                let members = withGroup(id)
                pressedPicked = m.selection == [id] && m.el(id)?.isWall == true
                if !pressedPicked, m.selection != [id] { m.pickedCorner = nil; m.pickedStretch = nil }
                // **⌘ or ⇧ adds to the pick, or takes away** — no mode to
                // turn on first (his note, 2026-09-29). Taking away waits for
                // the mouse to come up, so ⌘- or ⇧-dragging what is already
                // picked still moves it all.
                let adding = !event.modifierFlags.isDisjoint(with: [.shift, .command])
                pressedOn = event.modifierFlags.isDisjoint(with: [.shift, .option, .command]) ? id : nil
                unpickOnUp = nil
                if adding {
                    if m.selection.contains(id) {
                        unpickOnUp = members
                    } else {
                        m.selection += members.filter { !m.selection.contains($0) }
                    }
                } else if !m.selection.contains(id) {
                    m.selection = members
                }
                let movable = m.selection.filter { !(m.el($0)?.locked ?? true) }
                // ⌥-drag leaves the original behind and takes a copy — made
                // once the mouse moves, never on the click alone.
                copyOnMove = event.modifierFlags.contains(.option) && !movable.isEmpty
                copiedFrom = nil
                if !copyOnMove, let only = m.selection.first, m.selection.count == 1, let e = m.el(only),
                   ["door", "window", "opening"].contains(e.kind), !e.locked {
                    drag = .sliding(start: p, el: e, onWall: sitsOnWall(e), set: [:])
                    return
                }
                // A label moves on its own; the lamps tied to it stay put (his
                // call, 2026-10-04: dragging a label must not drag the lights).
                drag = .moving(start: p, ids: movable, anchor: snapRef(movable, clicked: id, press: p), delta: .zero)
            } else {
                // The sheet's legend, notes or shots, clicked.
                if event.modifierFlags.isDisjoint(with: [.shift, .command]), pageClick(p) { return }
                let adding = !event.modifierFlags.isDisjoint(with: [.shift, .command])
                let base = adding ? m.selection : []
                if !adding { m.selection = [] }
                drag = .marquee(start: p, now: p, base: base)
            }
        case .camera, .cast:
            drag = .placing(at: snapped(p, event), rot: 0)
        case .light:
            drag = .placing(at: snapped(p, event), rot: m.restingRot)
        case .set, .grip:
            if m.armed == nil { NSSound.beep(); return }
            drag = .placing(at: snapped(p, event), rot: m.restingRot)
        case .door, .sliding, .window, .opening:
            keeping(event) { m.addOpening(m.tool.rawValue, at: p) }
        case .wall:
            // **Wall by wall** (his note, 2026-09-29): each click stands the
            // next wall from the last corner, there and then — one step of
            // undo each. A click on the first corner closes the room;
            // Return, Esc or a double-click stops. Pressed and pulled, a
            // wall is drawn in one go. ⇧ held as the first corner goes down
            // draws a whole room instead.
            // **One wall, corner by corner** (master list 3): the first
            // stretch makes the wall, each click after grows it on — one
            // step to take back each — and a click on its first corner
            // closes it.
            if m.pending.isEmpty {
                m.drawingWall = nil
                let q = snapped(p, event)
                drag = event.modifierFlags.contains(.shift) ? .box(from: q, to: q) : .wall(from: q, to: q)
            } else {
                let q = drawingSnap(p, event)
                if let first = m.pending.first, m.pending.count >= 3,
                   hypot(first.x - q.x, first.y - q.y) * m.scale < 8 {
                    m.closeWall()
                    finishChain(closed: true)
                    return
                }
                let point = m.pending.last.map { constrained($0, q, event) } ?? q
                if let last = m.pending.last, hypot(point.x - last.x, point.y - last.y) > 0.05 {
                    if m.drawingWall == nil { m.startWall(last, point) } else { m.extendWall(to: point) }
                    m.pending.append(point)
                }
            }
        case .cable:
            m.pending.append(snapped(p, event))
        case .track, .road, .arrow, .connector, .measure:
            let q = snapped(p, event)
            drag = .line(from: q, to: q)
        case .shape:
            let q = snapped(p, event)
            drag = .box(from: q, to: q)
        case .pen:
            // A click is a corner; pulled, a curve. A click on the first point closes it.
            let q = snapped(p, event)
            if m.drawNodes.count >= 3, hypot(q.x - m.drawNodes[0].p.x, q.y - m.drawNodes[0].p.y) * m.scale < 9 {
                finishPath(closed: true)
                return
            }
            m.drawNodes.append(PathNode(p: q))
            drag = .node
        case .text, .note:
            let q = snapped(p, event)
            keeping(event) { m.addWords("text", at: q) }
        case .frame:
            let q = snapped(p, event)
            keeping(event) { m.addFrame(at: q) }
        case .hand, .picture:
            break
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let m = model, m.photoEditing == nil else { return }
        let v = convert(event.locationInWindow, from: nil)
        let p = m.toWorld(v, size: bounds.size)
        mouseWorld = p; pointerView = v; m.pointer = p
        dragged = true
        if nameDragged(v, event) { needsDisplay = true; return }
        switch drag {
        case .turningNorth(let from, let was, _):
            // Turned like a dial: the needle goes round with the hand, and
            // the sun round the set, which stays put.
            var north = was + (dial(v) - from)
            if event.modifierFlags.contains(.shift) { north = (north / 15).rounded() * 15 }
            north = (north.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
            drag = .turningNorth(from: from, was: was, north: north)
            m.previewing(["op": "settings", "set": ["north": north]])
        case .panning(let last):
            m.pan(by: CGPoint(x: v.x - last.x, y: v.y - last.y))
            drag = .panning(last: v)
        case .moving(let start, var ids, let anchor, _):
            guard !ids.isEmpty else { return }
            var raw = CGPoint(x: p.x - start.x, y: p.y - start.y)
            // ⌥ held at the press: the copy is made now the mouse has moved,
            // and it is the copy that goes.
            if copyOnMove, copiedFrom == nil, hypot(raw.x, raw.y) * m.scale >= 3 {
                let was = m.selection
                let made = m.edit(m.alone(["op": "duplicate", "ids": ids, "dx": 0, "dy": 0]), select: true)
                if !made.isEmpty {
                    copiedFrom = was
                    ids = m.selection.filter { !(m.el($0)?.locked ?? true) }
                }
                copyOnMove = false
            }
            // **⇧ keeps the move to one way** — and that is all it does mid-drag.
            var lockX = false, lockY = false
            if event.modifierFlags.contains(.shift) {
                if abs(raw.x) > abs(raw.y) { raw.y = 0; lockY = true } else { raw.x = 0; lockX = true }
            }
            var d = raw
            let free = event.modifierFlags.contains(.command)
            let step = CGFloat(m.snapStep)
            let gridded = anchor != nil && m.settings.snap && !free
            func onGrid(_ v: CGFloat, _ a: CGFloat) -> CGFloat { ((a + v) / step).rounded() * step - a }
            if gridded, let anchor {
                if !lockX { d.x = onGrid(raw.x, anchor.x) }
                if !lockY { d.y = onGrid(raw.y, anchor.y) }
            }
            // Lined up with another piece, when nearly — **but never off the
            // grid**: with Snap on, a line-up is taken only where it lands
            // the piece on the grid too. ⌘ lets it go free of both.
            if free { guides = []; linedUp = [] }
            else {
                (d, guides, linedUp) = DiagramGuides.snap(m, size: bounds.size, ids: ids, raw: raw, delta: d, lock: (lockX, lockY)) { x, w in
                    guard gridded, let anchor else { return true }
                    let a = x ? anchor.x : anchor.y
                    return abs(onGrid(w, a) - w) < 0.002 * step
                }
                // …and put exactly on it.
                if gridded, let anchor {
                    if !lockX { d.x = onGrid(d.x, anchor.x) }
                    if !lockY { d.y = onGrid(d.y, anchor.y) }
                }
                // Then flush against a wall's face, which beats the grid.
                let (fd, faced) = DiagramGuides.faces(m, size: bounds.size, ids: ids, delta: d, lock: (lockX, lockY))
                d = fd
                guides += faced
            }
            // Over a favorite slot: let go there and it is kept.
            let slot = m.favoriteSlots.first { $0.value.contains(v) }?.key
            if slot != m.favoriteHover { m.favoriteHover = slot }
            drag = .moving(start: start, ids: ids, anchor: anchor, delta: d)
            // Every move is the engine's, frame by frame, so everything the
            // move touches answers while it happens: a lamp aimed at what is
            // moving turns, a beam is cut by the wall it now meets, a door
            // rides its wall (his ask, 2026-09-28). Under a millisecond a
            // frame at sixty pieces.
            m.previewing(m.moveOp(ids: ids, dx: Double(d.x), dy: Double(d.y)))
        case .stepping(let e, let i, let start, _):
            guard e.spots.indices.contains(i) else { return }
            let t = e.spots[i]
            var at = CGPoint(x: t.x + p.x - start.x, y: t.y + p.y - start.y)
            if m.settings.snap, !event.modifierFlags.contains(.command) {
                let step = CGFloat(m.snapStep)
                at = CGPoint(x: (at.x / step).rounded() * step, y: (at.y / step).rounded() * step)
            }
            drag = .stepping(el: e, step: i, start: start, at: at)
            m.previewing(m.stepOp(e, i, x: at.x, y: at.y))
        case .stepTurning(let e, let i, _):
            guard e.spots.indices.contains(i) else { return }
            let t = e.spots[i]
            let deg = m.stepped(atan2(p.y - t.y, p.x - t.x) * 180 / .pi + Self.knobOffset(e),
                                shift: event.modifierFlags.contains(.shift), free: event.modifierFlags.contains(.command))
            drag = .stepTurning(el: e, step: i, rot: deg)
            m.previewing(m.stepOp(e, i, rot: deg))
        case .sliding(let start, let e, let onWall, _):
            let want = CGPoint(x: e.x + p.x - start.x, y: e.y + p.y - start.y)
            let (set, caught) = slide(e, to: want, onWall: onWall, event)
            drag = .sliding(start: start, el: e, onWall: caught, set: set)
            m.previewing(DiagramOps.update([e.id], set))
        case .marquee(let start, _, let base):
            drag = .marquee(start: start, now: p, base: base)
            if let engine = m.engine, let scene = m.scene {
                // A piece of a group caught takes its group: a group is one thing.
                var caught: [String] = []
                for id in marqueeCatch(from: start, to: p, engine: engine, scene: scene) {
                    for g in withGroup(id) where !caught.contains(g) { caught.append(g) }
                }
                let merged = base + caught.filter { !base.contains($0) }
                if merged != m.selection { m.selection = merged }
            }
        case .resizing(let e, let corner, _):
            let set = resize(e, corner: corner, to: CGPoint(x: p.x + resizeGrab.x, y: p.y + resizeGrab.y),
                             keep: event.modifierFlags.contains(.shift), free: event.modifierFlags.contains(.command), m)
            drag = .resizing(el: e, corner: corner, set: set)
            m.previewing(DiagramOps.update([e.id], set))
        case .rotating(let e, _):
            let now = e.at(beat: m.beat)
            // Let go over another piece and it is aimed there, and keeps
            // facing it (Scenario's targeting); over the floor, turned by hand.
            if let t = aimTarget(v, p, from: e), let te = m.el(t) {
                let c = te.isLine ? CGPoint(x: (te.x + te.x2) / 2, y: (te.y + te.y2) / 2)
                                  : { let n = te.at(beat: m.beat); return CGPoint(x: n.x, y: n.y) }()
                let deg = atan2(c.y - now.y, c.x - now.x) * 180 / .pi
                aimAt = t
                drag = .rotating(el: e, rot: (deg + 360).truncatingRemainder(dividingBy: 360))
                m.previewing(DiagramOps.update([e.id], ["aim": t]))
                needsDisplay = true
                return
            }
            aimAt = nil
            // The knob stands out in front of what faces, and off the top of
            // anything else: the heading is where the hand is, either way.
            let offset = Self.knobOffset(e)
            let deg = m.stepped(atan2(p.y - now.y, p.x - now.x) * 180 / .pi + offset,
                                shift: event.modifierFlags.contains(.shift), free: event.modifierFlags.contains(.command))
            drag = .rotating(el: e, rot: deg)
            m.previewing(byHand(e, to: deg))
        case .turningPick(let pivot, let from, let base, _):
            let now = atan2(p.y - pivot.y, p.x - pivot.x) * 180 / .pi
            let to = m.stepped(base + now - from, shift: event.modifierFlags.contains(.shift),
                               free: event.modifierFlags.contains(.command))
            var deg = (to - base).truncatingRemainder(dividingBy: 360)
            if deg > 180 { deg -= 360 } else if deg < -180 { deg += 360 }
            drag = .turningPick(pivot: pivot, from: from, base: base, deg: deg)
            m.previewing(m.turnPickOp(by: deg, pivot: pivot))
        case .endpoint(let e, let end, _, let joined):
            let fixed = end == 0 ? CGPoint(x: e.x2, y: e.y2) : CGPoint(x: e.x, y: e.y)
            let q = constrained(fixed, snapped(p, event, skip: [e.id] + joined.map(\.0)), event)
            drag = .endpoint(el: e, end: end, at: q, joined: joined)
            if e.kind == "arrow" {
                // The piece the end would hold on to, lit, and the end shown
                // on its edge — what letting go here will do.
                let on = pinTarget(p, skip: [e.id]) ?? pinTarget(q, skip: [e.id])
                pinGlow = on.map { [$0] } ?? []
                var set: [String: Any] = end == 0 ? ["x": q.x, "y": q.y] : ["x2": q.x, "y2": q.y]
                if let on { set[end == 0 ? "start_on" : "end_on"] = on }
                let ops = [DiagramOps.update([e.id], set)] + joined.map { id, n in
                    DiagramOps.update([id], n == 0 ? ["x": q.x, "y": q.y] : ["x2": q.x, "y2": q.y]) }
                m.previewing(ops.count == 1 ? ops[0] : DiagramOps.batch(ops))
            } else {
                m.previewing(Self.endsOp([(e.id, end)] + joined, to: q))
            }
        case .curving(let e, _):
            let (dx, dy) = (e.x2 - e.x, e.y2 - e.y)
            let len = max(hypot(dx, dy), 1e-9)
            let (nx, ny) = (-dy / len, dx / len)
            let mid = CGPoint(x: (e.x + e.x2) / 2, y: (e.y + e.y2) / 2)
            var off = (p.x - mid.x) * nx + (p.y - mid.y) * ny
            if abs(off) * m.scale < 6 { off = 0 }
            drag = .curving(el: e, curve: off)
            m.previewing(DiagramOps.update([e.id], ["curve": off]))
        case .corner(let e, let i, _, let made, let free):
            let c = e.corners
            var q = snapped(CGPoint(x: p.x + cornerGrab.x, y: p.y + cornerGrab.y), event, own: (e.id, i))
            // ⇧ keeps it square to the corner before it (or after, at a start).
            if event.modifierFlags.contains(.shift), c.count > 1 {
                let prev = i > 0 ? c[i - 1] : (e.isClosed ? c[c.count - 1] : c[1])
                q = constrained(prev, q, event)
                wallGuides = []
            }
            drag = .corner(el: e, index: i, at: q, made: made, free: free)
            var op = m.wallOp("wall_corner", e, ["corner": i, "x": q.x, "y": q.y])
            if free { op["free"] = true }
            m.previewing(op)
        case .handle(let e, let i, let outward, _):
            let q = CGPoint(x: p.x + cornerGrab.x, y: p.y + cornerGrab.y)
            drag = .handle(el: e, node: i, out: outward, at: q)
            var op = m.wallOp("wall_handle", e, ["corner": i, "side": outward ? "out" : "in", "x": q.x, "y": q.y])
            if event.modifierFlags.contains(.option) { op["free"] = true }
            m.previewing(op)
        case .node:
            // Pulled out from the point it was pressed on: the curve there, the
            // other handle opposite — a corner again if it is not pulled far.
            if var last = m.drawNodes.last {
                let v = CGVector(dx: p.x - last.p.x, dy: p.y - last.p.y)
                if hypot(v.dx, v.dy) * m.scale > 5 {
                    last.hout = v
                    last.hin = CGVector(dx: -v.dx, dy: -v.dy)
                } else {
                    last.hout = .zero
                    last.hin = .zero
                }
                m.drawNodes[m.drawNodes.count - 1] = last
            }
        case .reaching(let e, _):
            let now = e.at(beat: m.beat)
            let r = now.rot * .pi / 180
            let along = (p.x - now.x) * cos(r) + (p.y - now.y) * sin(r) - e.w / 2
            let reach = max(Double(along), 0.3)
            drag = .reaching(el: e, reach: reach)
            m.previewing(DiagramOps.update([e.id], ["reach": reach]))
        case .tilting(let e, let start, _):
            let t = DiagramFrames.tilt(e, at: e.at(beat: m.beat), from: start, to: p)
            drag = .tilting(el: e, start: start, tilt: t)
            m.previewing(DiagramOps.update([e.id], ["tilt": t]))
        case .placing(let at, _):
            var deg = atan2(p.y - at.y, p.x - at.x) * 180 / .pi
            if event.modifierFlags.contains(.shift) { deg = (deg / 15).rounded() * 15 }
            drag = .placing(at: at, rot: hypot(p.x - at.x, p.y - at.y) * m.scale > 8 ? deg : m.restingRot)
        case .line(let a, _):
            let b = m.calibrating != nil ? p : constrained(a, snapped(p, event), event)
            drag = .line(from: a, to: b)
            // **An arrow or a connector snaps to what it is drawn from and
            // onto**: each piece it will hold on to lights up, and the line
            // is shown already stopping at their edges, as it will be.
            if m.tool.pins, m.calibrating == nil {
                let pins = (pinTarget(a, skip: []), pinTarget(p, skip: []) ?? pinTarget(b, skip: []))
                pinGlow = [pins.0, pins.1].compactMap { $0 }
                // A connector from a label to a lamp is shown as the tie it will be.
                if m.tool == .connector, let ids = m.tiePair(pins.0, pins.1) {
                    m.previewing(["op": "share_label", "ids": ids])
                } else {
                    m.previewing(["op": "add", "els": [DiagramModel.lineEl("arrow", from: a, to: b, pins: pins,
                                                                            connector: m.tool == .connector, inSet: m.layer == "set")]])
                }
            }
        case .box(let a, _):
            drag = .box(from: a, to: snapped(p, event))
        case .wall(let a, _):
            drag = .wall(from: a, to: constrained(a, snapped(p, event), event))
            wallGuides = []
        case .none:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let m = model, m.photoEditing == nil else { return }
        defer {
            drag = .none
            guides = []; linedUp = []
            wallGuides = []
            pinGlow = []
            slideMark = nil
            if m.favoriteHover != nil { m.favoriteHover = nil }
            needsDisplay = true
            if m.tool == .hand || spaceHeld { NSCursor.openHand.set() }
        }
        if nameUp() { return }
        switch drag {
        case .moving(_, let ids, _, let d):
            let copied = copiedFrom
            copiedFrom = nil
            copyOnMove = false
            if dragged, let slot = m.favoriteHover, let id = pressedOn ?? ids.first {
                m.preview = nil
                if let was = copied { m.state?.undo(quiet: true); m.selection = was }
                m.setFavorite(slot, from: id)
            } else if dragged, !ids.isEmpty, d != .zero {
                // An ⌥-drag's copy and its move: one step to take back.
                m.edit(m.moveOp(ids: ids, dx: Double(d.x), dy: Double(d.y)), join: copied != nil)
            } else if let was = copied {
                // Copied, then brought back to where it started: no copy.
                m.preview = nil
                m.state?.undo(quiet: true)
                m.selection = was
            } else {
                m.preview = nil
                if let gone = unpickOnUp, !dragged {
                    m.selection.removeAll { gone.contains($0) }
                } else if let id = pressedOn, !dragged {
                    let members = withGroup(id)
                    if m.selection.count > members.count { m.selection = members }
                    // A click on the wall already picked picks the stretch
                    // under the hand, for its length.
                    if pressedPicked, let e = m.el(id), e.isWall, let at = mouseDownAt {
                        let st = e.stretches
                        let near = st.indices.min { a, b in
                            DiagramCanvasView.segDist(at, st[a].0, st[a].1) < DiagramCanvasView.segDist(at, st[b].0, st[b].1)
                        }
                        m.pickedStretch = near
                        m.pickedCorner = nil
                    }
                }
            }
            pressedOn = nil
            pressedPicked = false
            unpickOnUp = nil
        case .stepping(let e, let i, _, let at):
            if dragged { m.edit(m.stepOp(e, i, x: at.x, y: at.y)) } else { m.preview = nil }
        case .stepTurning(let e, let i, let rot):
            if dragged { m.edit(m.stepOp(e, i, rot: rot)) } else { m.preview = nil }
        case .sliding(_, let e, _, let set):
            if dragged, !set.isEmpty { m.update([e.id], set) } else { m.preview = nil }
            pressedOn = nil
        case .resizing(let e, _, let set):
            if !set.isEmpty { m.update([e.id], set) } else { m.preview = nil }
        case .turningNorth(_, _, let north):
            // Turned: kept, one step to take back. Clicked: the sun's panel.
            if dragged { m.setting("north", north) } else { m.preview = nil; m.showingSun = true }
        case .rotating(let e, let rot):
            if !dragged { m.preview = nil }
            else if let t = aimAt { m.edit(DiagramOps.update([e.id], ["aim": t])) }
            else { m.edit(byHand(e, to: rot)) }
            aimAt = nil
        case .turningPick(let pivot, _, _, let deg):
            if dragged, abs(deg) > 1e-9 { m.edit(m.turnPickOp(by: deg, pivot: pivot)) } else { m.preview = nil }
        case .endpoint(let e, let end, let q, let joined):
            if !dragged { m.preview = nil }
            else if e.kind == "arrow" {
                // **Arrows that stay attached** (SL-1231): an end let go on a
                // piece is pinned to it; let go anywhere else, it is free.
                let raw = m.toWorld(convert(event.locationInWindow, from: nil), size: bounds.size)
                let on = pinTarget(raw, skip: [e.id]) ?? pinTarget(q, skip: [e.id]) ?? ""
                var set: [String: Any] = end == 0 ? ["x": q.x, "y": q.y] : ["x2": q.x, "y2": q.y]
                if !on.isEmpty { set[end == 0 ? "start_on" : "end_on"] = on }
                let ops = [DiagramOps.update([e.id], set)] + joined.map { id, n in
                    DiagramOps.update([id], n == 0 ? ["x": q.x, "y": q.y] : ["x2": q.x, "y2": q.y]) }
                m.edit(ops.count == 1 ? ops[0] : DiagramOps.batch(ops))
            } else { m.edit(Self.endsOp([(e.id, end)] + joined, to: q)) }
        case .curving(let e, let c):
            if dragged { m.update([e.id], ["curve": c]) } else { m.preview = nil }
        case .corner(let e, let i, let q, let made, let free):
            if dragged {
                var op = m.wallOp("wall_corner", e, ["corner": i, "x": q.x, "y": q.y])
                if free { op["free"] = true }
                // A ruler's marker let go on a person locks to them.
                if e.isRuler, !free, let on = rulerTarget(q, skip: [e.id], event) { op["on"] = on }
                m.edit(op, join: made)
            } else { m.preview = nil }
        case .reaching(let e, let r):
            if dragged { m.update([e.id], ["reach": r]) } else { m.preview = nil }
        case .tilting(let e, _, let t):
            if dragged, t != e.tilt { m.update([e.id], ["tilt": t]) } else { m.preview = nil }
        case .placing(let at, let rot):
            keeping(event) {
                switch m.tool {
                case .camera: m.addCamera(at: at, rot: rot)
                case .cast:
                    if let who = m.armedCast { m.addCast(at: at, rot: rot, character: who.isEmpty ? nil : who) }
                    else { castMenu(at: at, rot: rot, event: event) }
                case .light: m.addLamp(at: at, rot: rot)
                case .set, .grip: if let sym = m.armed { m.addSymbol(sym, at: at, rot: rot) }
                default: break
                }
            }
        case .line(let a, let b) where m.calibrating != nil:
            let pic = m.calibrating!
            m.calibrating = nil
            if hypot(b.x - a.x, b.y - a.y) * m.scale > 6, let metres = askLength(now: m.length(Double(hypot(b.x - a.x, b.y - a.y)))) {
                m.calibrate(pic, from: a, to: b, metres: metres)
            }
        case .line(let a, let b):
            if hypot(b.x - a.x, b.y - a.y) * m.scale > 6 {
                let kind: String
                switch m.tool {
                case .track: kind = "track"
                case .road: kind = "road"
                case .arrow, .connector: kind = "arrow"
                default: kind = "measure"
                }
                if kind == "arrow" || kind == "measure" {
                    // Drawn from a note to a piece: both ends pinned (SL-1231);
                    // a ruler's end laid on a person or object locks to it.
                    let raw = m.toWorld(convert(event.locationInWindow, from: nil), size: bounds.size)
                    let pins = kind == "measure"
                        ? (rulerTarget(a, skip: [], event), rulerTarget(raw, skip: [], event) ?? rulerTarget(b, skip: [], event))
                        : (pinTarget(a, skip: []), pinTarget(raw, skip: []) ?? pinTarget(b, skip: []))
                    let connector = m.tool == .connector
                    // **A connector from a label to a lamp ties them**: the
                    // lamp shares that label (Same Lamp) and the label's own
                    // lines join them. Drag it again to the next lamp.
                    if connector, m.tieLabel(pins.0, pins.1) {
                        m.preview = nil
                    } else {
                        keeping(event) { m.addLine(kind, from: a, to: b, pins: pins, connector: connector) }
                    }
                } else {
                    keeping(event) { m.addLine(kind, from: a, to: b) }
                }
            } else if m.tool.pins {
                m.preview = nil
            }
        case .wall(let a, let b):
            // Pulled out: that wall stands, and the chain goes on from its
            // far end. Only clicked: the chain starts there.
            if dragged, hypot(b.x - a.x, b.y - a.y) * m.scale > 6 {
                m.startWall(a, b)
                m.pending = [a, b]
            } else {
                m.pending = [a]
            }
        case .box(let a, let b):
            let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
            if m.tool == .wall { m.addRoom(r); m.tool = .select } else if r.width * m.scale > 4 || r.height * m.scale > 4 { keeping(event) { m.addShape(r) } }
        case .node:
            break
        case .handle(let e, let i, let outward, let q):
            if dragged {
                var op = m.wallOp("wall_handle", e, ["corner": i, "side": outward ? "out" : "in", "x": q.x, "y": q.y])
                if event.modifierFlags.contains(.option) { op["free"] = true }
                m.edit(op)
            } else { m.preview = nil }
        case .marquee, .panning, .none:
            m.preview = nil
        }
    }

    /// **⌥-click keeps the tool** (Scenario's): put one down and the tool
    /// stays in hand, armed with the same piece, to put down another. A
    /// plain click goes back to the arrow as it always has.
    private func keeping(_ event: NSEvent, _ add: () -> Void) {
        guard let m = model else { return add() }
        let (tool, armed, cast, shot) = (m.tool, m.armed, m.armedCast, m.armedShot)
        add()
        guard event.modifierFlags.contains(.option), m.tool != tool else { return }
        m.tool = tool
        (m.armed, m.armedCast, m.armedShot) = (armed, cast, shot)
    }

    /// Whether a door or window sits in a wall now.
    private func sitsOnWall(_ e: DiagramEl) -> Bool {
        guard let m = model, let engine = m.engine, let scene = m.scene,
              let on = engine.diagramWall(scene: scene, x: e.x, y: e.y, reach: 0.02) else { return false }
        return hypot(on.x - e.x, on.y - e.y) < 0.03
    }

    /// Where a dragged door or window goes. Near a wall it lands on the
    /// wall's line, turned to it and as thick as it; once on, it stays on —
    /// sliding along — until pulled well clear. It keeps facing the side it
    /// faced, so a door does not flip its swing as it catches. ⌘ moves it
    /// freely; off a wall it steps on the grid like anything else.
    private func slide(_ e: DiagramEl, to want: CGPoint, onWall: Bool, _ event: NSEvent) -> ([String: Any], Bool) {
        guard let m = model else { return ([:], false) }
        let free = event.modifierFlags.contains(.command)
        slideMark = nil
        if !free, let engine = m.engine, let scene = m.scene {
            // Catches within a few inches, lets go only past most of a metre.
            // On it, it steps by the grid from the nearer corner, and says
            // how far it is (master list 3).
            let reach = onWall ? max(0.9, 36 / m.scale) : max(0.3, 12 / m.scale)
            if let on = engine.diagramWall(scene: scene, x: want.x, y: want.y, reach: reach,
                                           width: e.w, step: m.settings.snap ? m.snapStep : 0) {
                if let face = on.face, let edge = on.edge, let from = on.from { slideMark = (face, edge, from) }
                var rot = on.rot
                let turn = abs(((e.rot - rot).truncatingRemainder(dividingBy: 360) + 540).truncatingRemainder(dividingBy: 360) - 180)
                if turn > 90 { rot = (rot + 180).truncatingRemainder(dividingBy: 360) }
                return (["x": on.x, "y": on.y, "rot": rot, "h": on.thick], true)
            }
        }
        var at = want
        if m.settings.snap, !free {
            let step = CGFloat(m.snapStep)
            at = CGPoint(x: (at.x / step).rounded() * step, y: (at.y / step).rounded() * step)
        }
        return (["x": at.x, "y": at.y], false)
    }

    /// Resize from a corner: the opposite corner stays put, in the element's
    /// own turned frame. ⇧ keeps its shape. With Snap on, **the corner
    /// dragged lands on the grid** — so a piece whose other corner is on it
    /// is on it all round — or, turned off square, its size in whole steps.
    private func resize(_ e: DiagramEl, corner: Int, to p: CGPoint, keep: Bool, free: Bool, _ m: DiagramModel) -> [String: Any] {
        if e.hug == true, let d = e.drawn, d.count == 2, d[0] > 0 { return resizeMark(e, mark: d[0], side: max(d[0], Double(26 / m.scale)), corner: corner, to: p) }
        let r = e.rot * .pi / 180
        let (c, s) = (cos(r), sin(r))
        let signs = [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)][corner]
        let opposite = CGPoint(x: e.x - signs.0 * e.w / 2 * c + signs.1 * e.h / 2 * s,
                               y: e.y - signs.0 * e.w / 2 * s - signs.1 * e.h / 2 * c)
        let step = m.snapStep
        let snapping = m.settings.snap && !free
        let quarter = e.rot.truncatingRemainder(dividingBy: 90)
        let square = abs(quarter) < 1e-6 || abs(abs(quarter) - 90) < 1e-6
        var q = p
        if snapping, square, !keep {
            q = CGPoint(x: (p.x / step).rounded() * step, y: (p.y / step).rounded() * step)
        }
        let dx = q.x - opposite.x, dy = q.y - opposite.y
        var lw = abs(dx * c + dy * s), lh = abs(-dx * s + dy * c)
        if keep, e.w > 0, e.h > 0 {
            let k = max(lw / e.w, lh / e.h)
            lw = e.w * k; lh = e.h * k
        }
        if snapping {
            if !square || keep {
                lw = (lw / step).rounded() * step
                lh = (lh / step).rounded() * step
            }
            lw = max(lw, step)
            lh = max(lh, step)
        }
        lw = max(lw, 0.05); lh = max(lh, 0.05)
        // A frame's depth on the floor is its height leaning: a standing one
        // keeps its thickness, a leaning one grows taller.
        var lean: Double?
        if e.sym == DiagramFrames.sym {
            let k = cos(e.tilt * .pi / 180)
            if k > 0.1 { lean = lw / k } else { lw = e.w }
        }
        let mid = CGPoint(x: opposite.x + (signs.0 * lw / 2 * c - signs.1 * lh / 2 * s),
                          y: opposite.y + (signs.0 * lw / 2 * s + signs.1 * lh / 2 * c))
        var out: [String: Any] = ["w": lw, "h": lh, "x": Double(mid.x), "y": Double(mid.y)]
        if let lean { out["tall"] = lean }
        return out
    }

    /// **A lamp's mark, sized by a corner** (his note, 2026-10-17: lamps
    /// "need to size up when I scale them"): the mark stays square, the
    /// opposite corner stays put, and the mark grows by as much as its box
    /// did — `mark_k`. Its footprint is left as it is; the grid has no say
    /// in a symbol's size.
    private func resizeMark(_ e: DiagramEl, mark: Double, side: Double, corner: Int, to p: CGPoint) -> [String: Any] {
        let r = e.rot * .pi / 180
        let (c, s) = (cos(r), sin(r))
        let signs = [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)][corner]
        let half = side / 2
        let opposite = CGPoint(x: e.x - signs.0 * half * c + signs.1 * half * s,
                               y: e.y - signs.0 * half * s - signs.1 * half * c)
        let dx = p.x - opposite.x, dy = p.y - opposite.y
        let lw = abs(dx * c + dy * s), lh = abs(-dx * s + dy * c)
        // The mark's corner goes with the hand: the box it stands in (never
        // under its 26 points) gives way as the mark outgrows it.
        let k0 = e.mark_k ?? 1
        let k = min(max(k0 * (mark + max(lw, lh) - side) / mark, 0.4), 10)
        let now = max(mark * k / k0, side == mark ? 0 : side)
        let mid = CGPoint(x: opposite.x + (signs.0 * now / 2 * c - signs.1 * now / 2 * s),
                          y: opposite.y + (signs.0 * now / 2 * s + signs.1 * now / 2 * c))
        return ["mark_k": k, "x": Double(mid.x), "y": Double(mid.y)]
    }

    /// Fewer points along a pen stroke, the same shape (Ramer–Douglas–Peucker).
    private func simplify(_ pts: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        var keep = [Bool](repeating: false, count: pts.count)
        keep[0] = true; keep[pts.count - 1] = true
        func dist(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = b.x - a.x, dy = b.y - a.y
            let l2 = dx * dx + dy * dy
            if l2 == 0 { return hypot(p.x - a.x, p.y - a.y) }
            let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2))
            return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
        }
        var stack = [(0, pts.count - 1)]
        while let (i, j) = stack.popLast() {
            guard j > i + 1 else { continue }
            var best = 0 as CGFloat, at = i
            for k in (i + 1)..<j {
                let d = dist(pts[k], pts[i], pts[j])
                if d > best { best = d; at = k }
            }
            if best > tolerance {
                keep[at] = true
                stack.append((i, at)); stack.append((at, j))
            }
        }
        return pts.enumerated().filter { keep[$0.offset] }.map(\.element)
    }

    /// The Draw tool's path laid down: closed when the first point was clicked
    /// again, else as it stands. A double-click's first press already laid
    /// its point, so none is lost.
    private func finishPath(closed: Bool) {
        guard let m = model else { return }
        var nodes = m.drawNodes
        // The same point pressed twice is one point.
        if nodes.count >= 2, let a = nodes.last?.p, let b = nodes.dropLast().last?.p, hypot(a.x - b.x, a.y - b.y) * m.scale < 3 { nodes.removeLast() }
        m.drawNodes = []
        drag = .none
        if nodes.count >= 2 { m.addPath(nodes, closed: closed) } else { m.tool = .select }
        needsDisplay = true
    }

    private func finishChain(closed: Bool) {
        guard let m = model else { return }
        let pts = m.pending
        m.pending = []
        m.drawingWall = nil
        wallGuides = []
        // Each wall stood as it was drawn; a cable is laid in one go.
        if m.tool == .cable {
            m.addPolyline("cable", pts)
        }
        // Done drawing: back to the arrow, to pick up what was drawn.
        m.tool = .select
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        guard let m = model, m.photoEditing == nil else { return }
        let v = convert(event.locationInWindow, from: nil)
        let p = m.toWorld(v, size: bounds.size)
        mouseWorld = p; pointerView = v; m.pointer = p
        if spaceHeld { NSCursor.openHand.set(); return }
        if m.tool == .pen, !m.drawNodes.isEmpty { needsDisplay = true; return }
        if !m.pending.isEmpty {
            if let last = m.pending.last, m.tool == .wall {
                mouseWorld = constrained(last, drawingSnap(p, event), event)
                if event.modifierFlags.contains(.shift) { wallGuides = [] }
            }
            needsDisplay = true
            return
        }
        switch m.tool {
        case .select:
            if m.presenting { return }
            if hitHandle(v) != nil {
                NSCursor.pointingHand.set()
                return
            }
            if let (_, corner) = hitFrame(v), corner != nil {
                NSCursor.crosshair.set()
                return
            }
            if onCompass(v) {
                NSCursor.openHand.set()
                return
            }
            let now = hitTag(v) ?? hitElement(p)
            if now != hover {
                hover = now
                needsDisplay = true
            }
            if pageHover(now == nil ? p : nil) { NSCursor.pointingHand.set(); return }
            NSCursor.arrow.set()
        case .hand:
            NSCursor.openHand.set()
        default:
            if placingOnPicked(v, p) { NSCursor.pointingHand.set() } else { NSCursor.crosshair.set() }
        }
    }

    /// How long the line just drawn really is, asked once. Nil when he
    /// cancels or types nothing a length can be read from.
    private func askLength(now: String) -> Double? {
        guard let m = model else { return nil }
        if let given = m.calibrateAnswer { m.calibrateAnswer = nil; return m.parseLength(given) }
        let alert = NSAlert()
        alert.messageText = "Set Scale"
        alert.informativeText = "Drawn at \(now)."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = m.settings.units == "m" ? "Length in m" : "Length in ft"
        alert.accessoryView = field
        alert.addButton(withTitle: "Set Scale")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return m.parseLength(field.stringValue)
    }

    /// The piece a turning knob is over, when the one being turned can be
    /// aimed and this is something to aim at.
    private func aimTarget(_ v: CGPoint, _ p: CGPoint, from e: DiagramEl) -> String? {
        guard ["light", "camera", "cast"].contains(e.kind), let m = model,
              let id = hitTag(v, all: true) ?? hitElement(p, all: true), id != e.id, let t = m.el(id),
              !["wall", "door", "window", "opening", "image", "road", "track", "measure", "arrow", "cable", "stroke"].contains(t.kind)
        else { return nil }
        return id
    }

    /// Turned by hand: an aimed piece lets go of its aim in the same step.
    private func byHand(_ e: DiagramEl, to rot: Double) -> [String: Any] {
        guard let m = model else { return [:] }
        if e.aim.isEmpty { return m.turnOp(e, to: rot) }
        return DiagramOps.batch([DiagramOps.update([e.id], ["aim": ""]), m.turnOp(e, to: rot)])
    }

    /// A piece just put down with a placing tool stays picked, and a press on
    /// it or its handles answers as it would under the arrow — so it turns or
    /// nudges without going back to the arrow first. Walls and cables are left
    /// out: a new run often starts on the end of the last one.
    private func placingOnPicked(_ v: CGPoint, _ p: CGPoint) -> Bool {
        guard let m = model, m.pending.isEmpty, m.picked.count == 1, let e = m.picked.first,
              ["light", "set", "camera", "cast", "door", "window", "opening", "image"].contains(e.kind),
              [.set, .light, .grip, .camera, .cast, .door, .sliding, .window, .opening, .picture].contains(m.tool) else { return false }
        if hitHandle(v) != nil { return true }
        // A lamp or camera clicked onto the stand just put down goes on it (rigging).
        if [.light, .camera].contains(m.tool), e.kind == "set" || e.sym == DiagramFrames.sym { return false }
        return (hitTag(v) ?? hitElement(p)) == e.id
    }

    override func mouseExited(with event: NSEvent) {
        hover = nil
        mouseWorld = nil; pointerView = nil; model?.pointer = nil
        needsDisplay = true
        NSCursor.arrow.set()
    }

    override func otherMouseDown(with event: NSEvent) { mouseDown(with: event) }
    override func otherMouseDragged(with event: NSEvent) { mouseDragged(with: event) }
    override func otherMouseUp(with event: NSEvent) { mouseUp(with: event) }

    override func scrollWheel(with event: NSEvent) {
        guard let m = model else { return }
        let v = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.command) || !event.hasPreciseScrollingDeltas {
            // A mouse wheel, or ⌘ with a trackpad: zoom about the pointer.
            let amount = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.08
            m.zoom(by: exp(amount), around: v, size: bounds.size)
        } else {
            m.pan(by: CGPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY))
        }
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        guard let m = model else { return }
        m.zoom(by: 1 + event.magnification, around: convert(event.locationInWindow, from: nil), size: bounds.size)
        needsDisplay = true
    }

    // MARK: the right click

    /// Putting a person down offers who it could be: the scene's characters,
    /// the film's others, or a plain person. Anyone already on the plan is
    /// ticked. With no characters in the film, a plain person goes straight down.
    private func castMenu(at: CGPoint, rot: Double, event: NSEvent?) {
        guard let m = model else { return }
        // Driven by the checks, a menu would wait for a click that never
        // comes: they name the character (`castas`), or get a plain person.
        if ProcessInfo.processInfo.environment["SHOTLISTER_DIAGRAMDRIVE"] != nil {
            let who = m.castAs
            m.castAs = nil
            m.addCast(at: at, rot: rot, character: who)
            return
        }
        let (here, film, placed) = m.castChoices()
        guard !here.isEmpty || !film.isEmpty else { m.addCast(at: at, rot: rot); return }
        let menu = NSMenu()
        func add(_ names: [String], _ head: String) {
            guard !names.isEmpty else { return }
            menu.addItem(.sectionHeader(title: head))
            for name in names {
                let item = ClosureItem(name) { m.addCast(at: at, rot: rot, character: name) }
                item.state = placed.contains(name.lowercased()) ? .on : .off
                menu.addItem(item)
            }
        }
        add(here, "In This Scene")
        add(film, here.isEmpty ? "Characters" : "Other Characters")
        menu.addItem(.separator())
        menu.addItem(ClosureItem("Person") { m.addCast(at: at, rot: rot) })
        if let event { NSMenu.popUpContextMenu(menu, with: event, for: self) }
        else { menu.popUp(positioning: nil, at: m.toView(at, size: bounds.size), in: self) }
    }

    // MARK: the Cast and Camera buttons

    /// The Cast or Camera button's choices, in a menu under it: who, or which
    /// shot. Picked, the tool is ready and a click on the plan puts it down.
    func offerChoices(_ tool: DiagramTool) {
        guard let m = model, let menu = choices(tool) else { return }
        let spot = m.toolSpots[tool.rawValue] ?? CGRect(x: bounds.midX, y: 60, width: 0, height: 0)
        menu.popUp(positioning: nil, at: CGPoint(x: spot.minX, y: spot.maxY + 6), in: self)
    }

    /// The menu itself — apart, so a check can read it and pick from it
    /// without a menu open on screen waiting for a hand.
    func choices(_ tool: DiagramTool) -> NSMenu? {
        guard let m = model else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        func arm(_ set: @escaping (DiagramModel) -> Void) -> () -> Void {
            { [weak m] in
                guard let m else { return }
                m.tool = tool
                set(m)
            }
        }
        if tool == .cast {
            let (here, film, placed) = m.castChoices()
            func add(_ names: [String], _ head: String) {
                guard !names.isEmpty else { return }
                menu.addItem(.sectionHeader(title: head))
                for name in names {
                    let item = ClosureItem(name, run: arm { $0.armedCast = name })
                    item.state = placed.contains(name.lowercased()) ? .on : .off
                    menu.addItem(item)
                }
            }
            add(here, "In This Scene")
            add(film, here.isEmpty ? "Characters" : "Other Characters")
            if menu.numberOfItems > 0 { menu.addItem(.separator()) }
            menu.addItem(ClosureItem("Person", run: arm { $0.armedCast = "" }))
        } else {
            menu.addItem(ClosureItem("New Shot", run: arm { $0.armedShot = "new" }))
            let rows = m.state?.rows(of: m.state?.diagramScene) ?? []
            if !rows.isEmpty {
                menu.addItem(.separator())
                menu.addItem(.sectionHeader(title: "Shots in This Scene"))
                for r in rows {
                    let words = r.description.isEmpty ? r.title : r.description
                    let item = ClosureItem("\(r.number)  \(words.prefix(40))", run: arm { $0.armedShot = r.shot })
                    item.state = m.cameras(for: r.shot).isEmpty ? .off : .on
                    menu.addItem(item)
                }
            }
            menu.addItem(.separator())
            menu.addItem(ClosureItem("Camera Only", run: arm { $0.armedShot = "" }))
        }
        return menu
    }

    // MARK: dragged in

    /// Something dragged off the rail or out of the library, let go at `v`:
    /// placed where it landed, the way a click with its tool would.
    func drop(_ what: String, at v: CGPoint, swap: Bool? = nil) {
        guard let m = model, !m.readOnly else { return }
        window?.makeFirstResponder(self)
        let raw = m.toWorld(v, size: bounds.size)
        let p = snapped(raw, nil)
        // ⇧-dropped on a set piece or a lamp: swapped for it, where it stands.
        if what.hasPrefix("sym:"), swap ?? NSEvent.modifierFlags.contains(.shift),
           let id = hitTag(v) ?? hitElement(raw), let e = m.el(id), ["set", "light"].contains(e.kind), !e.locked {
            m.swap([id], to: String(what.dropFirst(4)))
            needsDisplay = true
            return
        }
        switch what {
        case _ where what.hasPrefix("fav:"):
            if let n = Int(what.dropFirst(4)) { m.dropFavorite(n, at: p) }
        case "camera": m.addCamera(at: p, rot: 0)
        case "cast": castMenu(at: p, rot: 0, event: nil)
        case "door", "sliding", "window", "opening": m.addOpening(what, at: raw)
        case "text", "note": m.addWords(what, at: p)
        case "frame": m.addFrame(at: p)
        case _ where what.hasPrefix("shot:"): m.placeShot(String(what.dropFirst(5)), at: p)
        case _ where what.hasPrefix("pic:"):
            let hash = String(what.dropFirst(4))
            guard let pic = m.projectPictures().flatMap(\.1).first(where: { $0.hash == hash }) else { return }
            m.addProjectPicture(pic, at: raw)
        default:
            guard what.hasPrefix("sym:"),
                  let sym = m.library?.symbols.first(where: { $0.id == what.dropFirst(4) }) else { return }
            m.addSymbol(sym, at: p, rot: DiagramModel.restingRot(sym))
        }
        needsDisplay = true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        if model?.readOnly == true || model?.presenting == true || model?.photoEditing != nil { return nil }
        guard let m = model else { return nil }
        let v = convert(event.locationInWindow, from: nil)
        let p = m.toWorld(v, size: bounds.size)
        if let id = hitTag(v, all: true) ?? hitLabel(v) ?? hitElement(p, all: true) {
            if !m.selection.contains(id) { m.selection = withGroup(id) }
        } else {
            // A legend line: every lamp of its kind, and their menu.
            pageMenuPick(p)
        }
        guard !m.selection.isEmpty else {
            return DiagramMenu.nothing(m) { [weak self] in
                guard let self else { return }
                m.fit(in: self.bounds.size); self.needsDisplay = true
            }
        }
        // **One menu** (Back to Paper, Batch 2): the bar's More and this are
        // the same, built in one place (`DiagramMenu`).
        return DiagramMenu.picked(m)
    }

    /// Words under a double-click, to type in: the piece they belong to and
    /// which of them — a lamp's Name or Note by the line clicked; Words, or
    /// any other piece's name, whole.
    private func wordsAt(_ v: CGPoint, _ p: CGPoint) -> (String, DiagramTyping.What?)? {
        guard let m = model else { return nil }
        // The same words a single click there takes (`clickedLabel`).
        if let id = clickedLabel(v), let e = m.el(id), !e.locked {
            guard DiagramMarks.isLamp(e, m) || DiagramFrames.isFrame(e) else {
                // Any piece's Note is its second line (2026-10-05); its name
                // the first, or the only one.
                if DiagramNames.notable(e), !(e.caption ?? "").isEmpty, !e.label.isEmpty, lineAt(v, of: id, part: "label") >= 1 { return (id, .note) }
                return DiagramNames.renamable(e) ? (id, nil) : nil
            }
            let first = e.label_lines?.first ?? ""
            if first.isEmpty { return (id, .note) }
            return (id, lineAt(v, of: id, part: "label") == 0 ? .name : .note)
        }
        if let id = hitElement(p), let e = m.el(id), ["text", "note"].contains(e.kind), !e.locked {
            if m.isSharedLabel(e) { return (id, lineAt(v, of: id, part: "body") == 0 ? .name : .note) }
            return (id, .text)
        }
        return nil
    }

    /// Which line of a piece's drawn words a point is on.
    private func lineAt(_ v: CGPoint, of id: String, part: String) -> Int {
        guard let m = model, let s = m.shown.shapes.first(where: { $0.e == id && $0.p == part && $0.k == "text" }),
              let x = s.x, let y = s.y else { return 0 }
        let T = m.transform(size: bounds.size)
        let shrink = CGFloat(m.namesShrink)
        let size = (s.fx ?? true) ? CGFloat(s.sz ?? 10) * shrink : CGFloat(s.sz ?? 0.3) * m.scale
        let font = NSFont.systemFont(ofSize: max(size, 3))
        let lines = max((s.tx ?? "").components(separatedBy: "\n").count, 1)
        let lineH = font.ascender - font.descender + font.leading
        let top = CGPoint(x: x, y: y).applying(T).y - lineH * CGFloat(lines) / 2
        return min(max(Int((v.y - top) / lineH), 0), lines - 1)
    }

    // MARK: one key, one thing at the pointer

    /// Scenario's one-key adds, put down under the pointer (or in the middle
    /// of the view): 1–9 a favorite, C a camera, T words, F a frame (below),
    /// and — because A, W and P already pick his Arrow, Wall and Cast tools
    /// — ⇧A a person, ⇧W an arrow, ⇧P the Pictures panel.
    private func oneKeyAdd(_ ch: String, _ mods: NSEvent.ModifierFlags, _ event: NSEvent) -> Bool {
        guard let m = model else { return false }
        let mid = m.toWorld(CGPoint(x: bounds.midX, y: bounds.midY), size: bounds.size)
        let at = { self.snapped(self.mouseWorld ?? mid, event) }
        switch (ch, mods) {
        case (_, []) where ch.count == 1 && ("1"..."9").contains(ch):
            guard let n = Int(ch), m.favorite(n - 1) != nil else { NSSound.beep(); return true }
            m.dropFavorite(n - 1, at: at())
        case ("c", []): m.addCamera(at: at(), rot: 0)
        case ("t", []): m.addWords("text", at: at())
        case ("a", [.shift]): castMenu(at: at(), rot: 0, event: nil)
        case ("w", [.shift]):
            let p = at(), half = m.unturned(CGPoint(x: 0.6, y: 0))
            m.addLine("arrow", from: CGPoint(x: p.x - half.x, y: p.y - half.y), to: CGPoint(x: p.x + half.x, y: p.y + half.y))
            m.tool = .select
        case ("p", [.shift]): m.tool = .picture
        default: return false
        }
        return true
    }

    // MARK: corners

    /// The other walls with an end on this point — within a centimetre, which
    /// is what a chain drawn with the grid on or off leaves them at.
    static func joined(to e: DiagramEl, at p: CGPoint, in els: [DiagramEl]) -> [(String, Int)] {
        guard e.kind == "wall" else { return [] }
        var out: [(String, Int)] = []
        for o in els where o.kind == "wall" && o.id != e.id && !o.locked {
            if hypot(o.x - p.x, o.y - p.y) < 0.01 { out.append((o.id, 0)) }
            if hypot(o.x2 - p.x, o.y2 - p.y) < 0.01 { out.append((o.id, 1)) }
        }
        return out
    }

    /// Every one of these ends to one point, as one thing to take back.
    static func endsOp(_ ends: [(String, Int)], to q: CGPoint) -> [String: Any] {
        let ops = ends.map { id, end in DiagramOps.update([id], end == 0 ? ["x": q.x, "y": q.y] : ["x2": q.x, "y2": q.y]) }
        return ops.count == 1 ? ops[0] : DiagramOps.batch(ops)
    }

    // MARK: the keyboard

    override func keyDown(with event: NSEvent) {
        guard let m = model else { return }
        let command = event.modifierFlags.contains(.command)
        if command { super.keyDown(with: event); return }
        if m.presenting { return }
        // Drawing a path: Return or Esc lays it down as it is, ⌫ takes the last point back.
        if m.tool == .pen, !m.drawNodes.isEmpty {
            switch event.keyCode {
            case 36, 76, 53: finishPath(closed: false); return
            case 51, 117:
                m.drawNodes.removeLast()
                needsDisplay = true
                return
            default: break
            }
        }
        switch event.keyCode {
        case 49: // space: move the view while held
            if !spaceHeld { spaceHeld = true; NSCursor.openHand.set() }
            return
        case 51, 117: // ⌫ ⌦ — one step alone, or a wall's corner, when that is what is picked
            if m.stepPick != nil { m.removePickedStep() }
            else if m.pickedCorner != nil { m.removeCorner() }
            else { m.remove(m.selection) }
            return
        case 53: // esc
            if m.swapping != nil { m.swapping = nil; return }
            if case .none = drag {} else { cancelDrag(); return }
            if m.pickedCorner != nil || m.pickedStretch != nil { m.pickedCorner = nil; m.pickedStretch = nil; needsDisplay = true; return }
            if m.calibrating != nil { m.calibrating = nil }
            else if !m.pending.isEmpty { m.pending = []; m.tool = .select }
            else if m.tool != .select { m.tool = .select }
            else { m.selection = [] }
            needsDisplay = true
            return
        case 36, 76: // return
            if !m.pending.isEmpty { finishChain(closed: false); return }
            if let e = m.picked.first, m.picked.count == 1 {
                if e.kind == "camera", !e.shot.isEmpty { m.openDetails() } else { m.startTyping(e.id) }
            }
            return
        case 123, 124, 125, 126:
            if event.modifierFlags.contains(.option) {
                // ⌥← ⌥→ turn the pick: 5° with Snap on, 1° off, 15° with ⇧.
                if [123, 124].contains(event.keyCode) {
                    m.turnKey(clockwise: event.keyCode == 124, shift: event.modifierFlags.contains(.shift))
                }
                return
            }
            // A small step, or with ⇧ one step of the grid; a run of presses
            // is one step of undo.
            let step = event.modifierFlags.contains(.shift) ? m.snapStep : m.nudgeStep
            let (dx, dy): (Double, Double) = [123: (-step, 0), 124: (step, 0), 125: (0, step), 126: (0, -step)][Int(event.keyCode)]!
            m.nudge(screen: dx, dy)
            return
        default:
            break
        }
        if event.modifierFlags.contains(.shift), !m.selection.isEmpty,
           let ch = event.charactersIgnoringModifiers?.lowercased(), ch == "h" || ch == "v" {
            m.flip(ch == "h" ? "x" : "y")
            return
        }
        if !m.readOnly, let ch = event.charactersIgnoringModifiers?.lowercased(),
           oneKeyAdd(ch, event.modifierFlags.intersection([.option, .control, .command, .shift]), event) {
            needsDisplay = true
            return
        }
        // F puts a frame down at the pointer, Scenario's way — or in the
        // middle of the view when the pointer is not over the plan.
        if event.charactersIgnoringModifiers?.lowercased() == DiagramTool.frame.key, !m.readOnly,
           event.modifierFlags.intersection([.option, .control, .command, .shift]).isEmpty {
            let mid = m.toWorld(CGPoint(x: bounds.midX, y: bounds.midY), size: bounds.size)
            m.addFrame(at: snapped(mouseWorld ?? mid, event))
            needsDisplay = true
            return
        }
        if let ch = event.charactersIgnoringModifiers?.lowercased(),
           let tool = DiagramTool.forKey(ch),
           !event.modifierFlags.contains(.option), !event.modifierFlags.contains(.control) {
            m.tool = tool
            return
        }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { letGoOfSpace() }
    }

    override func resignFirstResponder() -> Bool {
        letGoOfSpace()
        return super.resignFirstResponder()
    }

    private func letGoOfSpace() {
        guard spaceHeld else { return }
        spaceHeld = false
        NSCursor.arrow.set()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let m = model, window?.firstResponder === self,
              event.modifierFlags.contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        let shift = event.modifierFlags.contains(.shift)
        let option = event.modifierFlags.contains(.option)
        if m.presenting, !["0", "=", "+", "-"].contains(key) { return super.performKeyEquivalent(with: event) }
        switch key {
        case "z": shift ? m.state?.redo() : m.state?.undo()
        case "a":
            let unseen = m.unseenIds.union(m.layerLockedIds)
            m.selection = m.plan.els.filter { !$0.locked && !$0.hidden && !unseen.contains($0.id) }.map(\.id)
        case "d": m.duplicate()
        case "c": m.copy()
        case "x": m.cut()
        case "v": m.paste()
        case "g": shift ? m.ungroup() : m.group()
        case "]": m.order(option ? "front" : "forward")
        case "[": m.order(option ? "back" : "backward")
        case "0": m.fit(in: bounds.size)
        case "=", "+": m.zoom(by: 1.25, size: bounds.size)
        case "-": m.zoom(by: 0.8, size: bounds.size)
        case "l": m.update(m.selection, ["locked": !(m.picked.first?.locked ?? false)])
        case "r": m.rotate(shift ? -90 : 90)
        case "h" where shift: m.update(m.selection, ["hidden": true]); m.selection = []
        default: return super.performKeyEquivalent(with: event)
        }
        needsDisplay = true
        return true
    }
}

/// Paints the engine's shapes into a CoreGraphics context — the canvas, a
/// library tile and a tool's picture all draw through this, so they cannot
/// draw a thing two ways.
struct DiagramPainter {
    var dark: Bool
    var scale: CGFloat
    var engine: Engine?
    /// Where fixed tags landed, for hitting them.
    var tags: [(CGRect, String)] = []
    /// Where names (`label`) landed, so a name can be dragged on its own.
    var labels: [(CGRect, String)] = []
    /// How far the shape being painted is drawn back: the layer not being
    /// worked in (Set or Plot, Ref 1498).
    var fade: CGFloat = 1
    /// The paper names sit on, when it is not the canvas's own (an export
    /// on white).
    var ground: NSColor?
    /// What the paper role fills with — a door's cut, an open marker — when
    /// the screen's backdrop is dimmed or brightened (View → Backdrop…), so
    /// they stay the colour of what is round them. Names keep `ground`.
    var paper: NSColor?
    /// How much smaller (or larger) than their own size names and notes are
    /// drawn: with the page, as the page is (`DiagramModel.namesShrink`). An
    /// export draws them whole.
    var shrink: CGFloat = 1
    /// **The only name on the plan is drawn at least 3 points**, not dropped. When the
    /// sheet re-lays itself out round the first piece placed, the page's scale can jump
    /// to four times what it was while the view stays put, and the page's own size for
    /// the name falls under the 3-point floor: the lamp was placed and its name did not
    /// show until some later edit changed the zoom. One name cannot crowd anything.
    var lone = false

    func path(_ d: [Double], _ T: CGAffineTransform) -> CGPath {
        let p = CGMutablePath()
        var i = 0
        func pt(_ a: Int) -> CGPoint { CGPoint(x: d[a], y: d[a + 1]).applying(T) }
        while i < d.count {
            switch Int(d[i]) {
            case 0 where i + 2 < d.count: p.move(to: pt(i + 1)); i += 3
            case 1 where i + 2 < d.count: p.addLine(to: pt(i + 1)); i += 3
            case 2 where i + 6 < d.count: p.addCurve(to: pt(i + 5), control1: pt(i + 1), control2: pt(i + 3)); i += 7
            case 3: p.closeSubpath(); i += 1
            default: i = d.count
            }
        }
        return p
    }

    mutating func paint(_ s: DiagramShape, _ cg: CGContext, _ T: CGAffineTransform) {
        let alpha = CGFloat(s.a ?? 1) * fade
        cg.saveGState()
        defer { cg.restoreGState() }
        cg.setAlpha(min(max(alpha, 0), 1))
        switch s.k {
        case "path":
            guard let d = s.d else { return }
            let p = path(d, T)
            if let fill = (s.f == "paper" ? paper : nil) ?? DiagramInk.color(s.f, dark: dark) {
                if let fd = s.fd, fd.count == 3 {
                    cg.saveGState()
                    cg.addPath(p)
                    cg.clip()
                    let c = CGPoint(x: fd[0], y: fd[1]).applying(T)
                    let r = CGFloat(fd[2]) * scale
                    let colours = [fill.cgColor, fill.withAlphaComponent(0).cgColor] as CFArray
                    if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: [0, 1]) {
                        cg.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
                    }
                    cg.restoreGState()
                } else {
                    cg.addPath(p)
                    cg.setFillColor(fill.cgColor)
                    cg.fillPath()
                }
            }
            if let stroke = DiagramInk.color(s.s, dark: dark), let w = s.w, w > 0 {
                cg.addPath(p)
                cg.setStrokeColor(stroke.cgColor)
                cg.setLineWidth(CGFloat(w))
                cg.setLineJoin(.round)
                cg.setLineCap(s.da == "dot" ? .round : .butt)
                switch s.da {
                case "dash": cg.setLineDash(phase: 0, lengths: [5, 4])
                case "dot": cg.setLineDash(phase: 0, lengths: [0.1, 3.5])
                default: cg.setLineDash(phase: 0, lengths: [])
                }
                cg.strokePath()
            }
        case "text":
            guard let x = s.x, let y = s.y, let tx = s.tx, !tx.isEmpty else { return }
            let fixed = s.fx ?? true
            var size = fixed ? CGFloat(s.sz ?? 10) * shrink : CGFloat(s.sz ?? 0.3) * scale
            guard size >= 3 || (lone && s.p == "label") else { return }
            size = max(size, 3)
            let colour = DiagramInk.color(s.f, dark: dark) ?? .labelColor
            // **Words are ink** (Back to Paper, 2026-10-04): a name or a
            // callout is regular weight; only words he set bold are heavier.
            let font = NSFont.systemFont(ofSize: size, weight: (s.b ?? false) ? .semibold : .regular)
            let at = CGPoint(x: x, y: y).applying(T)
            // Words lying along something on the plan turn with the view and
            // never read upside down; a label standing upright stays upright.
            var rot = CGFloat(s.r ?? 0)
            if !fixed || rot != 0 {
                rot += atan2(T.b, T.a) * 180 / .pi
                if (s.an ?? "middle") == "middle" { rot = DiagramPainter.readable(rot) }
            }
            // A piece's name on its patch of paper, so whatever line it lies
            // across breaks round it (`render::place_names`, `PATCH_PAD`).
            let box = DiagramPainter.wordsBox(tx, at: at, font: font, anchor: s.an ?? "middle", rot: rot)
            let patch = box.insetBy(dx: -2, dy: -1)
            if s.pa == true {
                cg.addPath(CGPath(roundedRect: patch, cornerWidth: 2, cornerHeight: 2, transform: nil))
                cg.setFillColor((ground ?? DiagramInk.color("paper", dark: dark)!).cgColor)
                cg.fillPath()
            }
            DiagramPainter.words(tx, at: at, font: font, colour: colour, anchor: s.an ?? "middle",
                  rot: rot, halo: s.h ?? false, cg: cg, dark: dark, ground: ground,
                  under: DiagramInk.color(s.f2, dark: dark), lead: s.n1 ?? 1)
            if s.p == "label", let e = s.e {
                labels.append((s.pa == true ? patch : box, e))
            }
        case "pill":
            guard let x = s.x, let y = s.y, let tx = s.tx else { return }
            let at = CGPoint(x: x, y: y).applying(T)
            let size = CGFloat(s.sz ?? 10.5) * shrink
            guard size >= 3 else { return }
            let font = NSFont.systemFont(ofSize: size, weight: .semibold)
            let textW = (tx as NSString).size(withAttributes: [.font: font]).width
            let r = CGRect(x: at.x - textW / 2 - size * 0.62, y: at.y - size * 0.86,
                           width: textW + size * 1.24, height: size * 1.72)
            let shape = CGPath(roundedRect: r, cornerWidth: r.height * 0.36, cornerHeight: r.height * 0.36, transform: nil)
            cg.addPath(shape)
            cg.setFillColor((DiagramInk.color(s.f, dark: dark) ?? .white).cgColor)
            cg.fillPath()
            if let st = DiagramInk.color(s.s, dark: dark) {
                cg.addPath(shape)
                cg.setStrokeColor(st.cgColor)
                cg.setLineWidth(1)
                cg.strokePath()
            }
            let ink = (s.on.flatMap { $0.isEmpty ? nil : DiagramInk.color($0, dark: dark) })
                ?? DiagramInk.color("ink", dark: dark)!
            DiagramPainter.words(tx, at: at, font: font, colour: ink, anchor: "middle", rot: 0, halo: false, cg: cg, dark: dark)
            if let e = s.e { tags.append((r, e)) }
        case "badge":
            guard let x = s.x, let y = s.y, let tx = s.tx else { return }
            let at = CGPoint(x: x, y: y).applying(T)
            let r = CGRect(x: at.x - 7, y: at.y - 7, width: 14, height: 14)
            cg.setFillColor((DiagramInk.color(s.f, dark: dark) ?? .gray).cgColor)
            cg.fillEllipse(in: r)
            let ink = (s.on.flatMap { $0.isEmpty ? nil : DiagramInk.color($0, dark: dark) })
                ?? DiagramInk.color("paper", dark: dark)!
            DiagramPainter.words(tx, at: at, font: .systemFont(ofSize: 8.5, weight: .bold), colour: ink,
                  anchor: "middle", rot: 0, halo: false, cg: cg, dark: dark)
        case "img":
            guard let x = s.x, let y = s.y, let w = s.iw, let h = s.ih, let media = s.m,
                  var image = DiagramPictures.image(media, engine: engine) else { return }
            // A picture with a colour is one of the pack's people in their
            // character's colour (`render::cast`).
            if let tint = s.f, tint.hasPrefix("#") { image = DiagramPictures.tinted(image, media: media, tint: tint) }
            if s.f == DiagramPictures.inkedRole { image = DiagramPictures.inked(image, media: media) }
            let c = CGPoint(x: x, y: y).applying(T)
            let pw = CGFloat(w) * scale, ph = CGFloat(h) * scale
            cg.translateBy(x: c.x, y: c.y)
            // Its own turn, plus whatever turn the view itself carries (a
            // library tile shows a lamp facing up).
            cg.rotate(by: CGFloat(s.r ?? 0) * .pi / 180 + atan2(T.b, T.a))
            let rect = CGRect(x: -pw / 2, y: -ph / 2, width: pw, height: ph)
            // Drawn into this context by name: a SwiftUI canvas (a library
            // tile) has no current AppKit context of its own. Both it and the
            // plan's view run top-down.
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
            // Its opacity by `fraction`: NSImage draws at the fraction it is
            // given, whatever alpha the context carries — a lamp's Opacity
            // faded its edge and left its picture solid.
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: min(max(alpha, 0), 1),
                       respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
        default:
            break
        }
    }

    /// The box words take on screen, as `words` sets them — turned, the box
    /// round the turned box.
    static func wordsBox(_ text: String, at: CGPoint, font: NSFont, anchor: String, rot: CGFloat) -> CGRect {
        let lines = text.components(separatedBy: "\n")
        let lineH = font.ascender - font.descender + font.leading
        let w = lines.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let h = lineH * CGFloat(lines.count)
        let x0: CGFloat = anchor == "start" ? 0 : (anchor == "end" ? -w : -w / 2)
        let local = CGRect(x: x0, y: -h / 2, width: w, height: h)
        let t = CGAffineTransform(translationX: at.x, y: at.y).rotated(by: rot * .pi / 180)
        return local.applying(t)
    }

    /// An angle kept between a quarter turn either way, so words never hang
    /// upside down.
    static func readable(_ deg: CGFloat) -> CGFloat {
        var d = deg.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        if d > 90 && d < 270 { return d - 180 }
        return d >= 270 ? d - 360 : d
    }

    /// `under` is the ink of every line after the first (a callout's
    /// second line in grey); nil, they all take `colour`.
    static func words(_ text: String, at: CGPoint, font: NSFont, colour: NSColor, anchor: String,
                      rot: CGFloat, halo: Bool, cg: CGContext, dark: Bool = false, ground: NSColor? = nil,
                      under: NSColor? = nil, lead: Int = 1) {
        let lines = text.components(separatedBy: "\n")
        let lineH = font.ascender - font.descender + font.leading
        cg.saveGState()
        cg.translateBy(x: at.x, y: at.y)
        if rot != 0 { cg.rotate(by: rot * .pi / 180) }
        let total = lineH * CGFloat(lines.count)
        // The paper round the words, so a name reads over whatever it lies
        // on — as wide as the portal's and the PDF's (`svg.rs`: 3.5 px, round
        // joins). `strokeWidth` is a percentage of the point size; the 7 it
        // was gave well under a point, which a name over a piece never showed.
        let haloWidth = max(3.5, font.pointSize * 0.22)
        if halo { cg.setLineJoin(.round) }
        for (i, line) in lines.enumerated() {
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: i >= max(lead, 1) ? (under ?? colour) : colour]
            let str = NSAttributedString(string: line, attributes: attrs)
            let w = str.size().width
            let x: CGFloat = anchor == "start" ? 0 : (anchor == "end" ? -w : -w / 2)
            let y = -total / 2 + CGFloat(i) * lineH
            if halo {
                let back = NSAttributedString(string: line, attributes: [
                    .font: font, .strokeColor: ground ?? DiagramInk.color("paper", dark: dark)!,
                    .strokeWidth: haloWidth / font.pointSize * 100,
                ])
                back.draw(at: CGPoint(x: x, y: y))
            }
            str.draw(at: CGPoint(x: x, y: y))
        }
        cg.restoreGState()
    }

}

/// A menu item that runs a closure.
final class ClosureItem: NSMenuItem {
    private let run: () -> Void
    /// `key` only shows the shortcut beside the name; the canvas answers the
    /// key itself, menu open or not.
    init(_ title: String, key: String = "", mods: NSEvent.ModifierFlags = .command, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        keyEquivalentModifierMask = mods
        target = self
    }
    required init(coder: NSCoder) { fatalError("not from a nib") }
    @objc private func fire() { run() }
}

/// Pictures laid on a plan, by `hash.ext`, kept once read.
enum DiagramPictures {
    private static var held: [String: NSImage] = [:]
    private static var tints: [String: NSImage] = [:]

    /// The picture in a colour, its light and shade kept: the colour
    /// multiplied into it, then cut back to its own shape. One per picture
    /// and colour, made once.
    static func tinted(_ image: NSImage, media: String, tint: String) -> NSImage {
        let key = media + tint
        if let got = tints[key] { return got }
        guard let colour = DiagramInk.color(tint, dark: false) else { return image }
        let made = NSImage(size: image.size, flipped: false) { r in
            image.draw(in: r)
            colour.set()
            r.fill(using: .multiply)
            image.draw(in: r, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
        tints[key] = made
        return made
    }

    static func image(_ media: String, engine: Engine?) -> NSImage? {
        if let got = held[media] { return got }
        // A Film Set Objects picture, carried by the engine.
        if media.hasPrefix("fso:"), let engine {
            struct Reply: Decodable { var data: String }
            guard let r = try? JSONDecoder().decode(Reply.self, from: engine.call("diagramart", String(media.dropFirst(4)))),
                  let data = Data(base64Encoded: r.data), let image = NSImage(data: data) else { return nil }
            held[media] = image
            return image
        }
        let parts = media.split(separator: ".", maxSplits: 1).map(String.init)
        guard let hash = parts.first, let engine else { return nil }
        let ext = parts.count > 1 ? parts[1] : "jpg"
        // A clip's frame is its poster — `.jpg`, or `.png` in an older film.
        // Asked by a name whose file is not there, the engine hands back the
        // nearest by hash, which for a clip can be the movie: never a picture.
        for want in [ext, "jpg", "png"] {
            if let stored = engine.stored(hash: hash, ext: want),
               !["mp4", "mov", "m4v"].contains(stored.ext.lowercased()),
               let image = NSImage(data: stored.data) {
                held[media] = image
                return image
            }
        }
        return nil
    }
}
