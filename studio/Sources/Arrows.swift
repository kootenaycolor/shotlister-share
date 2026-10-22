import AppKit
import SwiftUI

/// **Storyboard arrows, drawn on a photograph** — his ask, 2026-08-31:
/// *"annotate still photographs in the shot list media frame with storyboard
/// arrows to indicate motion of a shot or character."* Grown into a toolkit on
/// 2026-10-14 (`design/45-print-frame.html`, section H): pins the shaft passes
/// through, smooth or cornered, nought to two heads, dashed, four looks, a
/// thickness, a depth (flat, or a perspective arrow coming toward camera or
/// going away), and the standard marks in two menus.
///
/// The model, the stored line and the drawing arithmetic are in
/// `ArrowShape.swift`. This file is the views:
///
///   - `ArrowMarks` — the arrows painted over any picture or board.
///   - `ArrowCanvas` — drawing and editing on **any** surface whose
///     coordinates are fractions of a rectangle: a photograph, or a Print
///     Frame's whole board. It owns the hand and the picked arrow's bar.
///   - `ArrowBoard` — the canvas on one picture of a shot, saving to that
///     picture's media use.
///   - `ArrowTools` — the tool capsule: Straight / Curve / Corner, the Camera
///     and Subject menus, Clear All.

// ------------------------------------------------------------ drawing them

/// **The arrows, over a picture, wherever that picture is drawn.**
///
/// Sits inside `Framed` and beside every fitted picture, so a mark made in the
/// pop-out is on the table thumbnail, the storyboard card and the schedule
/// strip without any of them being told about arrows.
///
/// Each piece is filled and outlined in the arrow's look, piece by piece and
/// in order — the way the exported page draws them. Nothing here is themed:
/// an arrow drawn on a photograph is part of the photograph.
struct ArrowMarks: View {
    let arrows: [ViewModel.Arrow]

    var body: some View {
        GeometryReader { space in
            let rect = CGRect(origin: .zero, size: space.size)
            ZStack {
                ForEach(Array(arrows.enumerated()), id: \.offset) { _, arrow in
                    let width = Storyboarding.outline(arrow, in: rect)
                    if let ring = Storyboarding.zoomRing(arrow, in: rect) {
                        ring.fill(arrow.look.fill, style: FillStyle(eoFill: true))
                        ring.stroke(arrow.look.line, style: StrokeStyle(lineWidth: width, lineJoin: .miter))
                    }
                    // A solid Toward or Away arrow's side faces are in the
                    // darker tint, drawn first; the face itself last.
                    ForEach(Array(Storyboarding.faces(arrow, in: rect).enumerated()), id: \.offset) { _, face in
                        if face.points.count >= 3 {
                            let piece = Path { path in
                                path.move(to: face.points[0])
                                for p in face.points.dropFirst() { path.addLine(to: p) }
                                path.closeSubpath()
                            }
                            piece.fill(face.side ? arrow.look.shade : arrow.look.fill)
                            piece.stroke(arrow.look.line,
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

// ------------------------------------------------------------ the tool

/// What a drag on bare frame draws. Remembered across windows and launches,
/// so the capsule and the board always agree without being wired together.
enum ArrowTool: String, CaseIterable {
    case straight, curve, corner
    static let key = "arrowTool"
    var label: String { rawValue.capitalized }
}

/// **The thickness a new arrow starts with** — the last one picked on any
/// arrow's Thickness slider, remembered on this Mac (2026-10-15: "the
/// thickness slider doesn't stay — it always resets to its default"). Before
/// this every arrow he drew began at 1 again. Zoom marks and the Camera /
/// Subject presets keep their own looks and neither read nor set it.
enum ArrowThickness {
    static let key = "arrowThickness"
    /// Standard everywhere but a checking run, which must not touch his own.
    static var store = UserDefaults.standard
    static func remembered(_ defaults: UserDefaults = store) -> Double {
        let v = defaults.double(forKey: key)
        guard v.isFinite, v > 0 else { return 1 }
        return min(max(v, ViewModel.Arrow.thinnest), ViewModel.Arrow.thickest)
    }
    static func remember(_ v: Double, _ defaults: UserDefaults = store) {
        guard v.isFinite else { return }
        defaults.set(min(max(v, ViewModel.Arrow.thinnest), ViewModel.Arrow.thickest), forKey: key)
    }
}

/// **What a slider has been moved to, kept where a stale closure cannot miss
/// it.** A Slider reports "let go" in the same breath as its last value, so
/// the arrow the bar was handed on its last redraw can be the arrow from
/// *before* the move, and saving that put the old thickness back. A class,
/// so every closure sees the one copy.
final class ArrowSliderDraft {
    private(set) var latest: ViewModel.Arrow?
    func moved(to arrow: ViewModel.Arrow) { latest = arrow }
    /// The arrow to save when the slider is let go: what it was moved to,
    /// else whatever the bar was showing. Clears the draft.
    func released(showing arrow: ViewModel.Arrow) -> ViewModel.Arrow {
        defer { latest = nil }
        return latest ?? arrow
    }
}

/// **Where the drawing surface sits in the room it is given.**
///
/// `plate` is the rectangle the stored fractions are of — the photograph as
/// it is drawn, or the whole board. `bounds` is the part of it a hand may
/// draw in: the film's frame on a photograph wider than the film, or the
/// board itself.
struct ArrowSurface {
    var bounds: CGRect
    var plate: CGRect

    /// One rectangle that is both: a Print Frame board, fitted in the room
    /// at its own shape and centred.
    static func fitted(ratio: CGFloat, in room: CGSize) -> ArrowSurface {
        let box = Plate.box(ratio, in: room)
        return ArrowSurface(bounds: box, plate: box)
    }

    /// The part a hand may draw in, as fractions of the plate — where marks
    /// are placed and what a whole arrow is held inside while it is dragged.
    var visible: CGRect {
        CGRect(x: (bounds.minX - plate.minX) / max(plate.width, 1),
               y: (bounds.minY - plate.minY) / max(plate.height, 1),
               width: bounds.width / max(plate.width, 1),
               height: bounds.height / max(plate.height, 1))
    }

    /// **Where a point on screen falls on the plate**, nought to one — held
    /// to the bounds first, so a hand that wanders into the letterbox leaves
    /// the mark on the edge of the shot rather than outside it.
    func fraction(_ point: CGPoint) -> CGPoint {
        let held = CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                           y: min(max(point.y, bounds.minY), bounds.maxY))
        return CGPoint(x: (held.x - plate.minX) / max(plate.width, 1),
                       y: (held.y - plate.minY) / max(plate.height, 1))
    }
}

// ------------------------------------------------------------ the canvas

/// **Drawing and editing arrows on any surface.**
///
/// **Drag to draw** with the current tool: Straight draws no pins; Curve
/// follows the hand and keeps up to four pins, evenly along it, so the curve
/// is the hand's but smoothed; Corner keeps the hand's turns as hard corners.
/// **Click to pick up. Drag the tail, the head or any pin.** Double-click
/// the shaft to drop a pin there; double-click a pin to take it out. The
/// picked arrow wears a small bar of its own.
///
/// **The engine is the truth here too.** What is stored is what is drawn; the
/// canvas keeps a copy of its own only while a hand is actually down, because
/// a gesture cannot wait for a round trip per frame. The moment the hand
/// comes up that copy goes to `save` and is dropped.
struct ArrowCanvas<Backdrop: View>: View {
    /// What is stored on this surface now.
    let stored: [ViewModel.Arrow]
    /// **Which one is picked up, by its place in the list** — the list is
    /// re-read after every save, so anything minted here would flicker off.
    @Binding var selected: Int?
    /// Where the surface sits in the room.
    let surface: (CGSize) -> ArrowSurface
    /// The one road back to wherever these arrows are kept.
    let save: ([ViewModel.Arrow]) -> Void
    /// What lies under the arrows, given the surface and the arrows to paint
    /// (the stored ones, or the hand's copy mid-gesture).
    let backdrop: (ArrowSurface, [ViewModel.Arrow]) -> Backdrop
    var hint: String? = "Drag to draw an arrow"

    init(stored: [ViewModel.Arrow], selected: Binding<Int?>,
         surface: @escaping (CGSize) -> ArrowSurface,
         save: @escaping ([ViewModel.Arrow]) -> Void,
         hint: String? = "Drag to draw an arrow",
         @ViewBuilder backdrop: @escaping (ArrowSurface, [ViewModel.Arrow]) -> Backdrop) {
        self.stored = stored
        self._selected = selected
        self.surface = surface
        self.save = save
        self.hint = hint
        self.backdrop = backdrop
    }

    @AppStorage(ArrowTool.key) private var toolName = ArrowTool.straight.rawValue
    private var tool: ArrowTool { ArrowTool(rawValue: toolName) ?? .straight }

    @State private var drafted: [ViewModel.Arrow]?
    @State private var drawing: ViewModel.Arrow?
    /// The hand's path while drawing, in screen points.
    @State private var trail: [CGPoint] = []
    @State private var grabbed: Grab?
    @State private var lastClick: (time: Date, point: CGPoint)?
    @State private var barSize: CGSize = CGSize(width: 420, height: 30)

    private enum Grab: Equatable { case tail, head, pin(Int), width(Int), corner(Int), whole(CGPoint) }

    private var arrows: [ViewModel.Arrow] { drafted ?? stored }
    private var shown: [ViewModel.Arrow] { drawing.map { arrows + [$0] } ?? arrows }

    var body: some View {
        GeometryReader { space in
            let here = surface(space.size)
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    backdrop(here, shown)
                    handles(on: here.plate)
                    if shown.isEmpty, let hint {
                        Text(hint)
                            .sans(Brand.Size.body)
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.bottom, 14)
                            .frame(width: here.bounds.width, height: here.bounds.height,
                                   alignment: .bottom)
                            .offset(x: here.bounds.minX, y: here.bounds.minY)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: space.size.width, height: space.size.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(hand(here))

                if drawing == nil, let at = selected, arrows.indices.contains(at) {
                    ArrowPickedBar(arrow: arrows[at],
                                   change: { changed in
                                       var next = stored
                                       guard next.indices.contains(at) else { return }
                                       next[at] = changed.held
                                       save(next)
                                   },
                                   preview: { shown in
                                       // A slider shows its arrow as it moves
                                       // and saves once, when let go.
                                       guard let shown else { drafted = nil; return }
                                       var next = stored
                                       guard next.indices.contains(at) else { return }
                                       next[at] = shown.held
                                       drafted = next
                                   },
                                   remove: {
                                       var next = stored
                                       guard next.indices.contains(at) else { return }
                                       next.remove(at: at)
                                       selected = nil
                                       save(next)
                                   })
                        .frame(maxWidth: max(space.size.width - 16, 200))
                        .fixedSize(horizontal: false, vertical: true)
                        .background {
                            GeometryReader { bar in
                                Color.clear
                                    .onAppear { barSize = bar.size }
                                    .onChange(of: bar.size) { _, now in barSize = now }
                            }
                        }
                        .position(barSpot(for: arrows[at], on: here.plate, room: space.size))
                }
            }
        }
    }

    /// Under the arrow when there is room, over it when there is not, and
    /// always inside the window.
    private func barSpot(for arrow: ViewModel.Arrow, on plate: CGRect, room: CGSize) -> CGPoint {
        let pts = Storyboarding.centreLine(arrow, in: plate).points
        let lowest = pts.map(\.y).max() ?? plate.midY
        let highest = pts.map(\.y).min() ?? plate.midY
        let middle = ((pts.map(\.x).min() ?? 0) + (pts.map(\.x).max() ?? 0)) / 2
        let gap: CGFloat = 22
        var y = lowest + gap + barSize.height / 2
        if y + barSize.height / 2 > room.height - 4 { y = highest - gap - barSize.height / 2 }
        y = min(max(y, barSize.height / 2 + 4), room.height - barSize.height / 2 - 4)
        let x = min(max(middle, barSize.width / 2 + 4), max(room.width - barSize.width / 2 - 4, barSize.width / 2 + 4))
        return CGPoint(x: x, y: y)
    }

    // ---- the hand -----------------------------------------------------------

    private func hand(_ here: ArrowSurface) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { move in
                if grabbed == nil, drawing == nil, drafted == nil { begin(move.startLocation, here) }
                carry(move.location, here)
            }
            .onEnded { move in
                carry(move.location, here)
                finish(move, here)
            }
    }

    private func begin(_ point: CGPoint, _ here: ArrowSurface) {
        drafted = stored
        let near: CGFloat = 11
        if let at = selected, stored.indices.contains(at) {
            let arrow = stored[at]
            if arrow.zoom != nil {
                // The inner frame's four corners resize it.
                for (k, c) in Storyboarding.zoomCorners(arrow, in: here.plate).enumerated()
                where hypot(point.x - c.inner.x, point.y - c.inner.y) < near {
                    grabbed = .corner(k)
                    return
                }
            }
            var spots: [(Grab, CGPoint)] = arrow.zoom != nil ? [] : [(.head, arrow.head), (.tail, arrow.tail)]
            spots += arrow.pins.enumerated().map { (Grab.pin($0.offset), $0.element.point) }
            for (grab, spot) in spots {
                let on = Storyboarding.at(spot, in: here.plate)
                if hypot(point.x - on.x, point.y - on.y) < near { grabbed = grab; return }
            }
            // The two width handles: shaft, head.
            for (k, on) in Storyboarding.widthHandles(arrow, on: here.plate).enumerated()
            where arrow.zoom == nil && hypot(point.x - on.x, point.y - on.y) < near {
                grabbed = .width(k)
                return
            }
        }
        // The topmost arrow under the point wins — the last drawn is on top.
        if let hit = stored.indices.reversed().first(where: {
            Storyboarding.distance(from: point, to: stored[$0], in: here.plate) < 12
        }) {
            selected = hit
            grabbed = .whole(here.fraction(point))
            return
        }
        selected = nil
        let start = here.fraction(point)
        trail = [point]
        var made = ViewModel.Arrow.straight(start.x, start.y, start.x, start.y)
        made.shape = tool == .corner ? .corner : .smooth
        made.thickness = ArrowThickness.remembered()
        drawing = made
    }

    private func carry(_ point: CGPoint, _ here: ArrowSurface) {
        let now = here.fraction(point)
        if var made = drawing {
            made.x2 = now.x; made.y2 = now.y
            if tool != .straight {
                if let last = trail.last, hypot(point.x - last.x, point.y - last.y) >= 2 {
                    trail.append(point)
                }
                made.pins = ArrowHand.pins(trail + [point], corner: tool == .corner)
                    .map { here.fraction($0) }
                    .map { ViewModel.Arrow.Pin(x: $0.x, y: $0.y) }
            }
            drawing = made
            return
        }
        guard let grabbed, var working = drafted, let at = selected,
              working.indices.contains(at) else { return }
        switch grabbed {
        case .head:
            working[at] = working[at].movingEnd(head: true, to: now)
        case .tail:
            working[at] = working[at].movingEnd(head: false, to: now)
        case .pin(let k):
            guard working[at].pins.indices.contains(k) else { return }
            working[at].pins[k] = ViewModel.Arrow.Pin(x: now.x, y: now.y)
        case .width(let k):
            if let set = Storyboarding.draggedWidths(working[at], handle: k, to: point, on: here.plate) {
                working[at].widths = set
            }
        case .corner(let k):
            working[at] = working[at].zoomResized(corner: k, to: now)
        case .whole(let from):
            working[at] = working[at].moved(by: CGSize(width: now.x - from.x, height: now.y - from.y),
                                            inside: here.visible)
            self.grabbed = .whole(now)
        }
        drafted = working
    }

    private func finish(_ move: DragGesture.Value, _ here: ArrowSurface) {
        defer { drafted = nil; grabbed = nil; trail = [] }
        let travelled = hypot(move.location.x - move.startLocation.x,
                              move.location.y - move.startLocation.y)
        if let made = drawing {
            drawing = nil
            // A click that never became a drag is not an arrow — but it may
            // be the second half of a double-click on nothing, which is
            // harmless.
            guard Storyboarding.length(made, in: here.plate) > 14 else {
                noteClick(move.location, travelled, here)
                return
            }
            let next = stored + [made.held]
            selected = next.count - 1
            save(next)
            return
        }
        if travelled < 4 {
            noteClick(move.location, travelled, here)
            return
        }
        guard grabbed != nil, let working = drafted, working != stored else { return }
        save(working)
    }

    /// **A click, and whether it was the second of two.** A drag gesture
    /// sees every click; this is how it tells a double-click from two.
    private func noteClick(_ point: CGPoint, _ travelled: CGFloat, _ here: ArrowSurface) {
        let now = Date()
        if let last = lastClick,
           now.timeIntervalSince(last.time) < NSEvent.doubleClickInterval,
           hypot(point.x - last.point.x, point.y - last.point.y) < 6 {
            lastClick = nil
            doubleClick(point, here)
        } else {
            lastClick = (now, point)
        }
    }

    /// Double-click a pin to take it out; double-click the shaft to drop
    /// one there.
    private func doubleClick(_ point: CGPoint, _ here: ArrowSurface) {
        guard let at = selected, stored.indices.contains(at), stored[at].zoom == nil else { return }
        var arrow = stored[at]
        if let k = arrow.pins.indices.first(where: {
            let on = Storyboarding.at(arrow.pins[$0].point, in: here.plate)
            return hypot(point.x - on.x, point.y - on.y) < 11
        }) {
            arrow.pins.remove(at: k)
        } else if Storyboarding.distance(from: point, to: arrow, in: here.plate) < 12,
                  arrow.pins.count < ViewModel.Arrow.mostPins {
            let slot = Storyboarding.pinSlot(at: point, on: arrow, in: here.plate)
            let spot = here.fraction(point)
            arrow.pins.insert(ViewModel.Arrow.Pin(x: spot.x, y: spot.y), at: slot)
        } else {
            return
        }
        var next = stored
        next[at] = arrow.held
        save(next)
    }

    // ---- the handles --------------------------------------------------------

    @ViewBuilder
    private func handles(on plate: CGRect) -> some View {
        if drawing == nil, let at = selected, arrows.indices.contains(at) {
            let arrow = arrows[at]
            // **The app's accent, not the system's** — asked for in daylight
            // because these sit on a photograph.
            let ink = Brand.accent(false)
            if arrow.zoom != nil {
                ForEach(Array(Storyboarding.zoomCorners(arrow, in: plate).enumerated()), id: \.offset) { _, c in
                    Circle()
                        .fill(Color.white)
                        .overlay { Circle().strokeBorder(ink, lineWidth: 1.5) }
                        .frame(width: 11, height: 11)
                        .position(x: c.inner.x, y: c.inner.y)
                        .allowsHitTesting(false)
                }
            }
            let spots: [(kind: Int, point: CGPoint)] = arrow.zoom != nil ? [] :
                [(0, arrow.tail)] + arrow.pins.map { (1, $0.point) } + [(2, arrow.head)]
            ForEach(Array(spots.enumerated()), id: \.offset) { _, spot in
                let on = Storyboarding.at(spot.point, in: plate)
                Circle()
                    .fill(spot.kind == 2 ? ink : Color.white)
                    .overlay {
                        Circle().strokeBorder(spot.kind == 2 ? Color.white
                                              : (spot.kind == 1 ? ink : Color(white: 0.08)),
                                              lineWidth: 1.5)
                    }
                    .frame(width: 11, height: 11)
                    .position(x: on.x, y: on.y)
                    .allowsHitTesting(false)
            }
            // **Width handles** — two small diamonds: one on the shaft's edge
            // (how thick the shaft is), one at the head's wide corner (how
            // wide the head's base is). Drag one across the arrow.
            ForEach(Array((arrow.zoom != nil ? [] : Storyboarding.widthHandles(arrow, on: plate)).enumerated()), id: \.offset) { _, on in
                Rectangle()
                    .fill(Color.white)
                    .overlay { Rectangle().strokeBorder(ink, lineWidth: 1.5) }
                    .frame(width: 8, height: 8)
                    .rotationEffect(.degrees(45))
                    .position(x: on.x, y: on.y)
                    .allowsHitTesting(false)
            }
        }
    }

}

extension Storyboarding {
    /// Where the two width handles sit: the shaft's on its edge, the head's
    /// on the wide corner of the triangle's base — never closer to the
    /// centre line than 6 points so a thin one can still be grabbed.
    static func widthHandles(_ arrow: ViewModel.Arrow, on plate: CGRect) -> [CGPoint] {
        if arrow.depth != .flat {
            // A solid arrow: the projected corner, in perspective.
            return SolidArrow.handles(Storyboarding.solid(arrow, in: plate)).map { c, h in
                let dx = h.x - c.x, dy = h.y - c.y, d = hypot(dx, dy)
                guard d < 6 else { return h }
                let ux = d > 0.0001 ? dx / d : 1, uy = d > 0.0001 ? dy / d : 0
                return CGPoint(x: c.x + ux * 6, y: c.y + uy * 6)
            }
        }
        return Storyboarding.widthSpots(arrow, in: plate).map { spot in
            let off = max(spot.half, 6)
            return CGPoint(x: spot.point.x + spot.normal.x * off, y: spot.point.y + spot.normal.y * off)
        }
    }

    /// **What a drag of a width handle makes the widths.** Handle 0 is the
    /// shaft, 1 the head. The pointer's distance from the centre line, across
    /// it, is the half-width there; the other one stays as drawn. A shaft is
    /// free to be wider than its head: that is how the back of an arrow is made wide. Nil when nothing can be drawn.
    static func draggedWidths(_ arrow: ViewModel.Arrow, handle k: Int, to point: CGPoint,
                              on plate: CGRect) -> [Double]? {
        if arrow.depth != .flat {
            // A solid arrow is drawn in perspective, so the handle's reach is
            // the width he set scaled by where it sits: the pointer's reach,
            // along the same line, scales the width alike.
            let spots = SolidArrow.handles(Storyboarding.solid(arrow, in: plate))
            guard spots.indices.contains(k) else { return nil }
            let (c, h) = spots[k]
            let dx = h.x - c.x, dy = h.y - c.y, reach = hypot(dx, dy)
            guard reach > 0.0001 else { return nil }
            let along = abs((point.x - c.x) * dx + (point.y - c.y) * dy) / reach
            let big = max(plate.width, plate.height) * CGFloat(arrow.thickness)
            guard big > 0 else { return nil }
            var fractions = Storyboarding.widths(arrow, in: plate).map { Double($0 / big) }
            fractions[k] *= Double(along / reach)
            return fractions.map { min(max($0, ViewModel.Arrow.leastWidth), ViewModel.Arrow.mostWidth) }
        }
        let spots = Storyboarding.widthSpots(arrow, in: plate)
        guard spots.indices.contains(k) else { return nil }
        let spot = spots[k]
        let half = abs((point.x - spot.point.x) * spot.normal.x + (point.y - spot.point.y) * spot.normal.y)
        let big = max(plate.width, plate.height) * CGFloat(arrow.thickness)
        guard big > 0 else { return nil }
        var fractions = Storyboarding.widths(arrow, in: plate).map { Double($0 / big) }
        fractions[k] = Double(half / big)
        return fractions.map { min(max($0, ViewModel.Arrow.leastWidth), ViewModel.Arrow.mostWidth) }
    }
}

/// **The hand's path, turned into pins.** Kept to four at most: more than
/// that is a wobble, not a mark anybody meant.
enum ArrowHand {
    /// The pins between the first and last points of `path` (screen points).
    /// None when the path is near enough straight.
    static func pins(_ path: [CGPoint], corner: Bool, most: Int = 4) -> [CGPoint] {
        guard path.count >= 3, let a = path.first, let c = path.last else { return [] }
        let walked = zip(path, path.dropFirst()).reduce(CGFloat(0)) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        let far = path.map { off($0, a, c) }.max() ?? 0
        guard far > max(6, walked * 0.04) else { return [] }
        var tolerance = max(6, walked * (corner ? 0.05 : 0.07))
        var kept = simplify(path, tolerance)
        while kept.count - 2 > most { tolerance *= 1.4; kept = simplify(path, tolerance) }
        if corner { return Array(kept.dropFirst().dropLast()) }
        // A curve: as many pins as the shape needs, spread evenly along the
        // hand's own path, so the curve is the hand's, smoothed.
        let count = min(max(kept.count - 2, 1), most)
        var lengths: [CGFloat] = [0]
        for i in 1..<path.count {
            lengths.append(lengths[i - 1] + hypot(path[i].x - path[i - 1].x, path[i].y - path[i - 1].y))
        }
        return (1...count).map { k in
            let want = walked * CGFloat(k) / CGFloat(count + 1)
            let i = lengths.firstIndex(where: { $0 >= want }) ?? path.count - 1
            guard i > 0 else { return path[0] }
            let u = (want - lengths[i - 1]) / max(lengths[i] - lengths[i - 1], 0.0001)
            return CGPoint(x: path[i - 1].x + (path[i].x - path[i - 1].x) * u,
                           y: path[i - 1].y + (path[i].y - path[i - 1].y) * u)
        }
    }

    private static func off(_ p: CGPoint, _ a: CGPoint, _ c: CGPoint) -> CGFloat {
        let dx = c.x - a.x, dy = c.y - a.y
        let len = hypot(dx, dy)
        if len < 0.0001 { return hypot(p.x - a.x, p.y - a.y) }
        return abs((p.x - a.x) * dy - (p.y - a.y) * dx) / len
    }

    /// Ramer–Douglas–Peucker: the fewest points within `tolerance` of the path.
    private static func simplify(_ path: [CGPoint], _ tolerance: CGFloat) -> [CGPoint] {
        guard path.count > 2 else { return path }
        var worst = 0, far: CGFloat = 0
        for i in 1..<(path.count - 1) {
            let d = off(path[i], path[0], path[path.count - 1])
            if d > far { far = d; worst = i }
        }
        guard far > tolerance else { return [path[0], path[path.count - 1]] }
        let left = simplify(Array(path[...worst]), tolerance)
        let right = simplify(Array(path[worst...]), tolerance)
        return left.dropLast() + right
    }
}

// ------------------------------------------------------------ the picked bar

/// **The picked arrow's own bar** — shape, heads, line, look, thickness,
/// depth, Straighten, Remove. Every control saves on the spot; there is
/// nothing to confirm. The two sliders draw the arrow as they move
/// (`preview`) and save once, when let go.
struct ArrowPickedBar: View {
    let arrow: ViewModel.Arrow
    let change: (ViewModel.Arrow) -> Void
    var preview: (ViewModel.Arrow?) -> Void = { _ in }
    let remove: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var draft = ArrowSliderDraft()
    private var dark: Bool { scheme == .dark }

    /// **It fits the room it is given, never clipped**: the whole bar in one
    /// row when it fits, then two rows, then three — a zoom mark's short bar
    /// is a single row.
    var body: some View {
        if arrow.zoom != nil {
            ViewThatFits(in: .horizontal) {
                panel { HStack(spacing: 6) { zoomChoice; looks; thickness; removeChoice } }
                panel {
                    VStack(spacing: 4) {
                        HStack(spacing: 6) { zoomChoice; looks }
                        HStack(spacing: 6) { thickness; removeChoice }
                    }
                }
            }
        } else {
            ViewThatFits(in: .horizontal) {
                panel { HStack(spacing: 6) { lineGroups; lookGroups; depthGroups; actionGroups } }
                panel {
                    VStack(spacing: 4) {
                        HStack(spacing: 6) { lineGroups; lookGroups }
                        HStack(spacing: 6) { depthGroups; actionGroups }
                    }
                }
                panel {
                    VStack(spacing: 4) {
                        HStack(spacing: 6) { lineGroups }
                        HStack(spacing: 6) { lookGroups }
                        HStack(spacing: 6) { depthGroups; actionGroups }
                    }
                }
                panel {
                    VStack(spacing: 4) {
                        HStack(spacing: 6) { lineGroups }
                        HStack(spacing: 6) { lookGroups }
                        HStack(spacing: 6) { depthGroups }
                        HStack(spacing: 6) { actionGroups }
                    }
                }
            }
        }
    }

    /// The bar's capsule — a rounded panel when it takes more than one row.
    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .foregroundStyle(Brand.ink(dark))
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Brand.panel(dark))
                    .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Brand.rule2(dark), lineWidth: 1) }
                    .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
            }
    }

    @ViewBuilder private var lineGroups: some View {
        group {
            choice(.straight, "Straight", lit: arrow.pins.isEmpty) { change(arrow.straightened) }
            choice(.smooth, "Smooth", lit: !arrow.pins.isEmpty && arrow.shape == .smooth) { shape(.smooth) }
            choice(.corner, "Corner", lit: !arrow.pins.isEmpty && arrow.shape == .corner) { shape(.corner) }
        }
        group {
            choice(.oneHead, "One Head", lit: arrow.heads == 1) { set { $0.heads = 1 } }
            choice(.bothEnds, "Both Ends", lit: arrow.heads == 2) { set { $0.heads = 2 } }
            choice(.noHead, "No Head", lit: arrow.heads == 0) { set { $0.heads = 0 } }
        }
        group {
            choice(.solid, "Solid", lit: !arrow.dashed) { set { $0.dashed = false } }
            choice(.dashed, "Dashed", lit: arrow.dashed) { set { $0.dashed = true } }
        }
    }

    @ViewBuilder private var lookGroups: some View {
        looks
        thickness
    }

    private var looks: some View {
        group {
            ForEach(ViewModel.Arrow.Look.allCases, id: \.self) { look in
                ArrowChoice(help: look.label, lit: arrow.look == look) {
                    set { $0.look = look }
                } label: {
                    Circle().fill(look.fill)
                        .overlay { Circle().strokeBorder(look.line.opacity(0.7), lineWidth: 1) }
                        .frame(width: 12, height: 12)
                }
            }
        }
    }

    private var thickness: some View {
        group {
            Text("Thickness").sans(Brand.Size.small)
                .padding(.leading, 8)
                .padding(.trailing, 4)
            slider(\.thickness, ViewModel.Arrow.thinnest...ViewModel.Arrow.thickest,
                   help: "Thickness", width: 78, remember: true)
                .padding(.trailing, 8)
        }
    }

    @ViewBuilder private var depthGroups: some View {
        group {
            // A depth sets its own widths; any set by hand go.
            choice(.flat, "Flat", lit: arrow.depth == .flat) { change(arrow.withDepth(.flat)) }
            choice(.toward, "Toward", lit: arrow.depth == .toward) { change(arrow.withDepth(.toward)) }
            choice(.away, "Away", lit: arrow.depth == .away) { change(arrow.withDepth(.away)) }
            if arrow.depth != .flat {
                slider(\.depthStrength, ViewModel.Arrow.leastDepth...ViewModel.Arrow.mostDepth,
                       help: "Strength", width: 56)
                    .padding(.leading, 4)
                    .padding(.trailing, 8)
            }
        }
        if arrow.depth != .flat {
            // Where the solid arrow is: lying on the floor, or standing up
            // facing the lens.
            group {
                ForEach(ViewModel.Arrow.Stance.allCases, id: \.self) { stance in
                    ArrowChoice(help: stance.label, lit: arrow.stance == stance, wide: true) {
                        set { $0.stance = stance }
                    } label: {
                        Text(stance.label).sans(Brand.Size.small)
                    }
                }
            }
        }
    }

    @ViewBuilder private var actionGroups: some View {
        if arrow.widths != nil {
            ArrowChoice(help: "Reset Widths", lit: false, wide: true) { change(arrow.widthsReset) } label: {
                Text("Reset Widths").sans(Brand.Size.small)
            }
        }
        ArrowChoice(help: "Straighten", lit: false, wide: true) { change(arrow.straightened) } label: {
            Text("Straighten").sans(Brand.Size.small)
        }
        .disabled(arrow.pins.isEmpty)
        .opacity(arrow.pins.isEmpty ? 0.4 : 1)
        ArrowChoice(help: "Remove", lit: false, wide: true) { remove() } label: {
            Text("Remove").sans(Brand.Size.small)
        }
    }

    /// A zoom mark's own bar: In or Out, colour, thickness, Remove.
    private var zoomChoice: some View {
        group {
            ArrowChoice(help: "Zoom In", lit: arrow.zoom == .zoomIn, wide: true) { set { $0.zoom = .zoomIn } } label: {
                Text("Zoom In").sans(Brand.Size.small)
            }
            ArrowChoice(help: "Zoom Out", lit: arrow.zoom == .zoomOut, wide: true) { set { $0.zoom = .zoomOut } } label: {
                Text("Zoom Out").sans(Brand.Size.small)
            }
        }
    }

    private var removeChoice: some View {
        ArrowChoice(help: "Remove", lit: false, wide: true) { remove() } label: {
            Text("Remove").sans(Brand.Size.small)
        }
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) { content() }
            .padding(.horizontal, 2)
            .background { Capsule(style: .continuous).fill(Brand.cellHover(dark).opacity(0.6)) }
    }

    private func choice(_ icon: ArrowIcon.Kind, _ help: String, lit: Bool,
                        _ action: @escaping () -> Void) -> some View {
        ArrowChoice(help: help, lit: lit, action: action) { ArrowIcon(kind: icon) }
    }

    /// A small slider on one number of the arrow: drawn live, saved on
    /// release.
    private func slider(_ key: WritableKeyPath<ViewModel.Arrow, Double>,
                        _ range: ClosedRange<Double>, help: String, width: CGFloat,
                        remember: Bool = false) -> some View {
        Slider(value: Binding(get: { arrow[keyPath: key] },
                              set: { value in
                                  var next = arrow
                                  next[keyPath: key] = value
                                  draft.moved(to: next)
                                  preview(next)
                              }),
               in: range,
               onEditingChanged: { editing in
                   if !editing {
                       let done = draft.released(showing: arrow)
                       if remember, done.zoom == nil { ArrowThickness.remember(done.thickness) }
                       change(done)
                       preview(nil)
                   }
               })
        .controlSize(.mini)
        .frame(width: width)
        .help(help)
    }

    private func set(_ edit: (inout ViewModel.Arrow) -> Void) {
        var next = arrow
        edit(&next)
        change(next)
    }

    /// Smooth or Corner. A straight arrow has nothing to round or turn, so
    /// it gets the pin that makes the choice visible: a gentle bow for
    /// Smooth, the turn under the head for Corner.
    private func shape(_ shape: ViewModel.Arrow.Shape) {
        var next = arrow
        next.shape = shape
        if next.pins.isEmpty {
            if shape == .corner {
                next.pins = [.init(x: arrow.x2, y: arrow.y1)]
            } else {
                let dx = arrow.x2 - arrow.x1, dy = arrow.y2 - arrow.y1
                next.pins = [.init(x: (arrow.x1 + arrow.x2) / 2 + dy * 0.15,
                                   y: (arrow.y1 + arrow.y2) / 2 - dx * 0.15)]
            }
        }
        change(next.held)
    }
}

/// One small round choice in the picked arrow's bar.
private struct ArrowChoice<Label: View>: View {
    let help: String
    let lit: Bool
    var wide: Bool = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        let dark = scheme == .dark
        Button(action: action) {
            label()
                .fixedSize()
                .foregroundStyle(lit ? Brand.accent(dark) : Brand.ink(dark))
                .padding(.horizontal, wide ? 10 : 0)
                .frame(minWidth: 28, minHeight: 22)
                .background {
                    Capsule(style: .continuous)
                        .fill(lit ? Brand.accentTint(dark) : (hovering ? Brand.cellHover(dark) : .clear))
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// **The small line drawings on the arrow controls** — each one *is* the
/// fact it stands for (a straight shaft, a curve, a corner, two heads, a
/// dash), drawn rather than borrowed from a symbol set. From the mockup.
struct ArrowIcon: View {
    enum Kind { case straight, smooth, curve, corner, oneHead, bothEnds, noHead, solid, dashed,
                flat, toward, away }
    let kind: Kind

    var body: some View {
        Canvas { context, size in
            let s = min(size.width / 22, size.height / 12)
            let ox = (size.width - 22 * s) / 2, oy = (size.height - 12 * s) / 2
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
            var path = Path()
            var dashed = false
            switch kind {
            case .straight, .oneHead:
                path.move(to: p(2, 6)); path.addLine(to: p(19, 6))
                path.move(to: p(15, 2)); path.addLine(to: p(19, 6)); path.addLine(to: p(15, 10))
            case .smooth:
                path.move(to: p(2, 6)); path.addCurve(to: p(19, 6), control1: p(7, 0), control2: p(14, 12))
                path.move(to: p(15, 3)); path.addLine(to: p(19, 6)); path.addLine(to: p(15, 9))
            case .curve:
                path.move(to: p(2, 9)); path.addCurve(to: p(19, 4), control1: p(7, 0), control2: p(14, 12))
                path.move(to: p(15, 2)); path.addLine(to: p(19, 4)); path.addLine(to: p(16, 7))
            case .corner:
                path.move(to: p(2, 10)); path.addLine(to: p(2, 3)); path.addLine(to: p(12, 3))
                path.addLine(to: p(12, 9)); path.addLine(to: p(19, 9))
                path.move(to: p(15, 6)); path.addLine(to: p(19, 9)); path.addLine(to: p(15, 12))
            case .bothEnds:
                path.move(to: p(3, 6)); path.addLine(to: p(19, 6))
                path.move(to: p(15, 2)); path.addLine(to: p(19, 6)); path.addLine(to: p(15, 10))
                path.move(to: p(7, 2)); path.addLine(to: p(3, 6)); path.addLine(to: p(7, 10))
            case .noHead, .solid:
                path.move(to: p(2, 6)); path.addLine(to: p(20, 6))
            case .dashed:
                path.move(to: p(2, 6)); path.addLine(to: p(20, 6))
                dashed = true
            // The depth choices are outlines: the width is the point.
            case .flat:
                path.addLines([p(2, 5), p(14, 5), p(14, 2.5), p(20, 6), p(14, 9.5), p(14, 7), p(2, 7)])
                path.closeSubpath()
            case .toward:
                path.addLines([p(2, 5.4), p(13, 3.8), p(13, 0.8), p(20.5, 6), p(13, 11.2), p(13, 8.2), p(2, 6.6)])
                path.closeSubpath()
            case .away:
                path.addLines([p(1.5, 2.6), p(15, 5), p(15, 3.6), p(20, 6), p(15, 8.4), p(15, 7), p(1.5, 9.4)])
                path.closeSubpath()
            }
            context.stroke(path, with: .foreground,
                           style: StrokeStyle(lineWidth: [.flat, .toward, .away].contains(kind) ? 1.1 : 1.6,
                                              lineCap: .round, lineJoin: .round,
                                              dash: dashed ? [3 * s, 2 * s] : []))
        }
        .frame(width: 22, height: 12)
    }
}

// ------------------------------------------------------------ on a picture

/// **Drawing the arrows on one picture of a shot** — the canvas, with the
/// picture under it framed as the film, saving to that picture's media use.
///
/// Lives inside the two pop-outs that already own a picture rather than in a
/// sheet of its own: a sheet in this app cannot be photographed at all, so it
/// could never be checked.
struct ArrowBoard: View {
    @ObservedObject var state: ShellState
    /// The use of the picture being marked — the media ref, not the file.
    let ref: String
    let picture: NSImage
    /// Which part of the picture the crop keeps, so the frame drawn here is
    /// the frame drawn everywhere else.
    var framing: ViewModel.Framing = .middle
    /// The film's own shape. **Arrows are composed in the frame he will
    /// actually see** — his instruction, 2026-08-31.
    var ratio: CGFloat = 2.39
    /// What the engine says is on this picture.
    let stored: [ViewModel.Arrow]
    @Binding var selected: Int?

    var body: some View {
        ArrowCanvas(stored: stored, selected: $selected,
                    surface: { room in
                        let box = Plate.box(ratio, in: room)
                        return ArrowSurface(bounds: box, plate: Plate.plate(picture, framing, in: box))
                    },
                    save: { ArrowBoard.save($0, ref: ref, state: state) }) { here, shown in
            Framed(picture: picture, framing: framing, arrows: shown)
                .frame(width: here.bounds.width, height: here.bounds.height)
                .offset(x: here.bounds.minX, y: here.bounds.minY)
        }
    }

    /// **The one road from a set of arrows on a picture to the engine**,
    /// shared with the tool capsule so a mark and a hand-drawn arrow cannot
    /// be saved two different ways. Nothing left is cleared rather than
    /// stored as an empty line: absent and "no arrows" have to be one fact.
    static func save(_ arrows: [ViewModel.Arrow], ref: String, state: ShellState) {
        guard let engine = state.engine else { return }
        if arrows.isEmpty {
            state.replace(engine.clearArrows(ref))
        } else {
            state.replace(engine.arrows(ref, ViewModel.Arrow.encode(arrows)))
        }
    }
}

// ------------------------------------------------------------ the capsule

/// **The arrow tool capsule**, worn by every surface that can be marked, so
/// the same feature cannot grow two different sets of buttons: Straight,
/// Curve, Corner; the Camera and Subject marks; Clear All. What belongs to
/// one arrow is on that arrow's own bar.
struct ArrowTools: View {
    let arrows: [ViewModel.Arrow]
    /// **The part of the surface the film's frame shows** — where a mark
    /// belongs, as fractions of the surface. The unit rectangle on a board.
    var visible: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @Binding var selected: Int?
    let save: ([ViewModel.Arrow]) -> Void

    @AppStorage(ArrowTool.key) private var toolName = ArrowTool.straight.rawValue
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    init(arrows: [ViewModel.Arrow], visible: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
         selected: Binding<Int?>, save: @escaping ([ViewModel.Arrow]) -> Void) {
        self.arrows = arrows
        self.visible = visible
        self._selected = selected
        self.save = save
    }

    /// On one picture of a shot.
    init(state: ShellState, ref: String, arrows: [ViewModel.Arrow],
         visible: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
         selected: Binding<Int?>) {
        self.init(arrows: arrows, visible: visible, selected: selected) {
            ArrowBoard.save($0, ref: ref, state: state)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(ArrowTool.allCases, id: \.self) { tool in
                    Button { toolName = tool.rawValue } label: {
                        HStack(spacing: 4) {
                            ArrowIcon(kind: tool == .straight ? .straight
                                      : (tool == .curve ? .curve : .corner))
                            Text(tool.label).sans(Brand.Size.body)
                        }
                        .foregroundStyle(toolName == tool.rawValue ? Brand.accent(dark) : Brand.ink(dark))
                        .padding(.horizontal, 10)
                        .frame(height: Brand.barHeight)
                        .background {
                            Capsule(style: .continuous)
                                .fill(toolName == tool.rawValue ? Brand.accentTint(dark) : .clear)
                        }
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .help(tool.label)
                }
            }
            .overlay { Capsule(style: .continuous).strokeBorder(Brand.rule2(dark), lineWidth: 1) }

            marks("Camera", ViewModel.Arrow.Mark.camera)
            marks("Subject", ViewModel.Arrow.Mark.subject)

            Button { save([]); selected = nil } label: {
                Text("Clear All").sans(Brand.Size.body)
                    .foregroundStyle(Brand.ink(dark))
                    .padding(.horizontal, Brand.barPadding)
                    .frame(height: Brand.barHeight)
                    .barPill(dark, on: false)
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .disabled(arrows.isEmpty)
            .opacity(arrows.isEmpty ? 0.4 : 1)
            .help("Clear All")

            // Left-aligned, under the row of actions it belongs to.
            Spacer(minLength: 0)
        }
    }

    private func marks(_ title: String, _ list: [ViewModel.Arrow.Mark]) -> some View {
        Menu {
            ForEach(list) { mark in
                Button(mark.rawValue) { add(mark) }
            }
        } label: {
            Text("\(title) ▾").sans(Brand.Size.body)
                .foregroundStyle(Brand.ink(dark))
                .padding(.horizontal, Brand.barPadding)
                .frame(height: Brand.barHeight)
                .barPill(dark, on: false)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .focusEffectDisabled()
        .fixedSize()
        .help(title)
    }

    private func add(_ mark: ViewModel.Arrow.Mark) {
        let made = mark.arrows(in: visible).map(\.held)
        save(arrows + made)
        // A single arrow lands picked up, so it can be moved straight away; a
        // set does not, because there is no one of them to pick.
        selected = made.count == 1 ? arrows.count : nil
    }
}
