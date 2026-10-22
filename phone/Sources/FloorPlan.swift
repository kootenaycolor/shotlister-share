import SwiftUI
import simd

/// The room from above, drawn to scale and measured wall by wall.
///
/// This is the half of a scan that does real work: it is measured, so it can be
/// read off, printed, and one day become the underlay a scene diagram is drawn
/// on top of. The 3D view is for recognising the place; this is for planning
/// in it.
struct FloorPlanView: View {
    let plan: Plan

    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var settledPan: CGSize = .zero

    /// Furniture is what the room *had* on the day rather than what it is, and
    /// for blocking a scene an empty room is often the truth.
    @AppStorage("floorplan.furniture") private var showFurniture = true
    @AppStorage("floorplan.dimensions") private var showDimensions = true

    private let margin: CGFloat = 64

    /// Drawing decisions, in one place, and different in the dark.
    ///
    /// **Neither end was paper.** Pure white in the light and near-black in the
    /// dark are what a *screen* does, not what a drawing does — his note, and
    /// right: a plan is read like a printed page, and a page is off-white. The
    /// dark one is a drawing board rather than a hole.
    struct Ink {
        var paper: Color
        var wall: Color
        var outline: Color
        var furniture: Color
        var detail: Color
        var soft: Color
        var rule: Color
        var grid: Color

        /// RoomPlan calls a wall a plane with no thickness. A plan needs one,
        /// and this is it — a drawing convention, never a measurement.
        static let wallThickness: Float = 0.12

        static let light = Ink(
            paper:     Color(red: 0.96, green: 0.965, blue: 0.97),
            wall:      Color(red: 0.55, green: 0.62, blue: 0.67),
            outline:   Color(red: 0.36, green: 0.42, blue: 0.46),
            furniture: Color(red: 1.00, green: 1.00, blue: 1.00),
            detail:    Color(red: 0.62, green: 0.68, blue: 0.72),
            soft:      Color(red: 0.91, green: 0.93, blue: 0.95),
            rule:      Color(red: 0.68, green: 0.72, blue: 0.75),
            grid:      Color(red: 0.91, green: 0.92, blue: 0.93)
        )

        static let dark = Ink(
            paper:     Color(red: 0.145, green: 0.155, blue: 0.170),
            wall:      Color(red: 0.46, green: 0.53, blue: 0.58),
            outline:   Color(red: 0.72, green: 0.77, blue: 0.81),
            furniture: Color(red: 0.20, green: 0.215, blue: 0.235),
            detail:    Color(red: 0.52, green: 0.58, blue: 0.63),
            soft:      Color(red: 0.26, green: 0.28, blue: 0.30),
            rule:      Color(red: 0.44, green: 0.48, blue: 0.52),
            grid:      Color(red: 0.19, green: 0.20, blue: 0.215)
        )
    }

    @Environment(\.colorScheme) private var scheme
    private var ink: Ink { scheme == .dark ? .dark : .light }

    var body: some View {
        VStack(spacing: 0) {
            Canvas { context, size in draw(in: &context, size: size) }
                .background(ink.paper)
                .gesture(
                    SimultaneousGesture(
                        MagnifyGesture()
                            .onChanged { zoom = min(max(settledZoom * $0.magnification, 0.4), 10) }
                            .onEnded { _ in settledZoom = zoom },
                        DragGesture()
                            .onChanged { pan = CGSize(width: settledPan.width + $0.translation.width,
                                                      height: settledPan.height + $0.translation.height) }
                            .onEnded { _ in settledPan = pan }
                    )
                )
                .onTapGesture(count: 2) { reset() }

            controls
        }
    }

    private var controls: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 1) {
                Text(overall).font(.footnote.monospacedDigit())
                // The one measurement a plan cannot show by drawing, and the one
                // that decides what can be rigged in the room.
                Text(ceiling)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(isOn: $showDimensions) { Image(systemName: "ruler") }
                .toggleStyle(.button)
                .accessibilityLabel("Dimensions")
            Toggle(isOn: $showFurniture) { Image(systemName: "sofa") }
                .toggleStyle(.button)
                .accessibilityLabel("Furniture")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var overall: String {
        "\(Measured.imperial(plan.extent.x))  ×  \(Measured.imperial(plan.extent.y))"
    }

    private var ceiling: String {
        guard plan.ceiling > 0 else { return "\(plan.walls.count) walls" }
        if plan.ceilingVaries {
            let (low, high) = plan.ceilingRange
            return "Ceiling \(Measured.imperial(low))–\(Measured.imperial(high))"
        }
        return "Ceiling \(Measured.imperial(plan.ceiling))"
    }

    private func reset() {
        withAnimation(.snappy) {
            zoom = 1; settledZoom = 1; pan = .zero; settledPan = .zero
        }
    }

    // ---- the drawing -------------------------------------------------------

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let extent = plan.extent
        guard extent.x > 0, extent.y > 0 else { return }

        // One scale for both axes, or the room comes out stretched and every
        // measurement written on it becomes a lie.
        let fit = min((size.width - margin * 2) / CGFloat(extent.x),
                      (size.height - margin * 2) / CGFloat(extent.y))
        let scale = fit * zoom
        let middle = (plan.bounds.min + plan.bounds.max) / 2

        func place(_ point: SIMD2<Float>) -> CGPoint {
            CGPoint(x: size.width / 2 + CGFloat(point.x - middle.x) * scale + pan.width,
                    y: size.height / 2 + CGFloat(point.y - middle.y) * scale + pan.height)
        }

        grid(in: &context, size: size, scale: scale, place: place)

        // **Furniture goes under the walls.** A scanner measures a wardrobe to
        // its back panel and a wall to its face, so anything standing against a
        // wall overlaps it by a centimetre or two — and once a wall is drawn
        // with an invented thickness, by rather more. Letting the wall cover it
        // is how a plan looks right without moving anything.
        if showFurniture {
            for object in plan.items where object.isObject {
                Symbol.draw(object, in: &context, place: place, scale: scale, ink: (
                    fill: ink.furniture, outline: ink.outline, detail: ink.detail, soft: ink.soft
                ))
            }
        }

        for wall in plan.walls {
            context.fill(slab(wall, place), with: .color(ink.wall))
        }
        for hole in plan.items where hole.isHole {
            // The hole is cut a shade wider than the wall so no sliver of wall
            // survives along its edge.
            context.fill(slab(hole, place, thickness: Ink.wallThickness * 1.6),
                         with: .color(ink.paper))
            if hole.part == "window" { window(hole, in: &context, place: place) }
            if hole.part == "door" { swing(hole, in: &context, place: place, scale: scale) }
        }

        if showDimensions { measureEveryWall(in: &context, place: place, scale: scale) }
    }

    /// A wall as a slab of the drawing's own thickness, since the scan gives it
    /// none.
    private func slab(_ item: Plan.Item, _ place: (SIMD2<Float>) -> CGPoint,
                      thickness: Float = Ink.wallThickness) -> Path {
        var path = Path()
        let corners = item.corners(thickness: thickness).map(place)
        path.move(to: corners[0])
        corners.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    /// A window: the two lines of glass across the hole, which is how a plan has
    /// always drawn one.
    private func window(_ hole: Plan.Item, in context: inout GraphicsContext,
                        place: (SIMD2<Float>) -> CGPoint) {
        let (start, end) = hole.ends
        let across = hole.normal * (Ink.wallThickness / 3)
        var path = Path()
        path.move(to: place(start + across)); path.addLine(to: place(end + across))
        path.move(to: place(start - across)); path.addLine(to: place(end - across))
        context.stroke(path, with: .color(ink.wall), lineWidth: 1.25)
    }

    /// A faint two-foot grid, so the eye has a scale before it reads a number.
    private func grid(in context: inout GraphicsContext, size: CGSize, scale: CGFloat,
                      place: (SIMD2<Float>) -> CGPoint) {
        let step = CGFloat(0.6096) * scale
        guard step > 8 else { return }
        var path = Path()
        let origin = place(plan.bounds.min)
        var x = origin.x.truncatingRemainder(dividingBy: step)
        while x < size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
        var y = origin.y.truncatingRemainder(dividingBy: step)
        while y < size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
        context.stroke(path, with: .color(ink.grid), lineWidth: 0.5)
    }

    /// The quarter-circle a door sweeps. Which way it opens is not in the scan,
    /// so it is drawn into the room — the question on a location is whether the
    /// door fouls the shot, and the arc is what answers it.
    private func swing(_ door: Plan.Item, in context: inout GraphicsContext,
                       place: (SIMD2<Float>) -> CGPoint, scale: CGFloat) {
        let hinge = place(door.ends.0)
        let width = CGFloat(door.length) * scale
        var arc = Path()
        arc.addArc(center: hinge, radius: width,
                   startAngle: .radians(Double(door.angle)),
                   endAngle: .radians(Double(door.angle) + .pi / 2),
                   clockwise: false)
        context.stroke(arc, with: .color(ink.rule), lineWidth: 0.75)

        // The leaf itself, standing open at a right angle — without it the arc
        // is a stray curve rather than a door.
        var leaf = Path()
        leaf.move(to: hinge)
        leaf.addLine(to: CGPoint(x: hinge.x + width * CGFloat(cos(Double(door.angle) + .pi / 2)),
                                 y: hinge.y + width * CGFloat(sin(Double(door.angle) + .pi / 2))))
        context.stroke(leaf, with: .color(ink.outline), lineWidth: 1.5)
    }

    // ---- measuring ---------------------------------------------------------

    /// **Every wall carries its own length.** The room's outer extent alone says
    /// almost nothing: it is the bounding box of a shape that is rarely a
    /// rectangle, so on an L-shaped room it describes a wall that does not
    /// exist. What anybody standing in the room wants is *this* wall, in feet.
    /// **Every wall carries its own length.** The room's outer extent alone says
    /// almost nothing: it is the bounding box of a shape that is rarely a
    /// rectangle, so on an L-shaped room it describes a wall that does not
    /// exist. What anybody standing in the room wants is *this* wall, in feet.
    ///
    /// Two short walls meeting at a corner want to write their numbers in the
    /// same place, so a label that would land on one already placed is pushed
    /// further out until it does not. Longest walls are placed first, so the
    /// dimensions that matter most sit closest to the room and the fiddly
    /// returns are the ones that get pushed out.
    private func measureEveryWall(in context: inout GraphicsContext,
                                  place: (SIMD2<Float>) -> CGPoint, scale: CGFloat) {
        let centre = (plan.bounds.min + plan.bounds.max) / 2
        var taken: [CGRect] = []

        for wall in plan.walls.sorted(by: { $0.length > $1.length }) {
            // A short return is still a wall somebody has to shoot past, so it
            // is measured too. Below about eight inches it is scanner noise.
            guard wall.length > 0.2 else { continue }

            let (start, end) = wall.ends
            let out = wall.normal
            let away = simd_dot(out, wall.centre - centre) >= 0 ? out : -out

            let text = Measured.imperial(wall.length)
            let width = CGFloat(text.count) * 6 + 12

            var placed: (a: CGPoint, b: CGPoint, box: CGRect)?
            for step in 0..<9 {
                let gap = CGFloat(22 + step * 20)
                let offset = away * Float(gap / max(scale, 0.001))
                let a = place(start + offset), b = place(end + offset)
                let middle = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                let box = CGRect(x: middle.x - width / 2, y: middle.y - 8, width: width, height: 16)
                if !taken.contains(where: { $0.intersects(box) }) {
                    placed = (a, b, box)
                    break
                }
            }
            // Nine tries out and still colliding means the plan is denser than
            // the screen can carry; drawing it anyway would be worse.
            guard let spot = placed else { continue }
            taken.append(spot.box)

            var line = Path()
            line.move(to: spot.a); line.addLine(to: spot.b)
            line.move(to: place(start)); line.addLine(to: spot.a)
            line.move(to: place(end));   line.addLine(to: spot.b)
            context.stroke(line, with: .color(ink.rule), lineWidth: 0.75)

            tick(at: spot.a, along: wall.angle, in: &context)
            tick(at: spot.b, along: wall.angle, in: &context)

            // The number sits in a gap in its own line rather than on top of it.
            context.fill(Path(spot.box), with: .color(ink.paper))
            context.draw(
                Text(text).font(.system(size: 10, weight: .medium)).foregroundColor(.secondary),
                at: CGPoint(x: spot.box.midX, y: spot.box.midY)
            )
        }
    }

    private func tick(at point: CGPoint, along angle: Float, in context: inout GraphicsContext) {
        let across = CGVector(dx: CGFloat(-sin(angle)) * 3, dy: CGFloat(cos(angle)) * 3)
        var path = Path()
        path.move(to: CGPoint(x: point.x - across.dx, y: point.y - across.dy))
        path.addLine(to: CGPoint(x: point.x + across.dx, y: point.y + across.dy))
        context.stroke(path, with: .color(ink.rule), lineWidth: 1)
    }
}

// ------------------------------------------------------------- furniture

/// Furniture drawn as furniture.
///
/// A plan of grey rectangles has to be deciphered; one where the bed looks like
/// a bed is read at a glance, and on a location that is the difference between
/// a useful drawing and a diagram of a warehouse.
private enum Symbol {
    struct Ink {
        var fill: Color
        var outline: Color
        var detail: Color
        var soft: Color
    }

    static func draw(_ item: Plan.Item, in context: inout GraphicsContext,
                     place: (SIMD2<Float>) -> CGPoint, scale: CGFloat,
                     ink: (fill: Color, outline: Color, detail: Color, soft: Color)) {
        let corners = item.corners().map(place)
        var body = Path()
        body.move(to: corners[0])
        corners.dropFirst().forEach { body.addLine(to: $0) }
        body.closeSubpath()

        context.fill(body, with: .color(ink.fill))
        context.stroke(body, with: .color(ink.outline), lineWidth: 1)

        // The detail is drawn in the thing's own frame and then turned with it,
        // so a bed's pillow stays at its head whichever way the bed is facing.
        var inner = context
        inner.translateBy(x: place(item.centre).x, y: place(item.centre).y)
        inner.rotate(by: .radians(Double(item.angle)))
        let w = CGFloat(item.length) * scale
        let d = CGFloat(item.depth) * scale
        let rect = CGRect(x: -w / 2, y: -d / 2, width: w, height: d)
        detail(item.furnishing, in: &inner, rect: rect, ink: ink)
    }

    private static func detail(_ kind: String, in context: inout GraphicsContext, rect: CGRect,
                               ink: (fill: Color, outline: Color, detail: Color, soft: Color)) {
        let line = GraphicsContext.Shading.color(ink.detail)
        let soft = GraphicsContext.Shading.color(ink.soft)

        switch kind {
        case "bed":
            // A pillow at the head, the covers below it, and one corner turned
            // back. The turned-back corner has to be a *filled triangle* — as
            // an open line it reads as a stray diagonal across the room rather
            // than as a bed.
            //
            // **The head is at one end of the long axis, whichever axis that
            // is.** RoomPlan measures a bed's *width* along its own x — a single
            // bed comes back 1.0 by 2.0 — so assuming x is the length laid the
            // pillow down the whole side of the bed instead of across its head.
            let inset = rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.06)
            let lengthwise = inset.height >= inset.width

            let pillow = lengthwise
                ? CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: inset.height * 0.22)
                : CGRect(x: inset.minX, y: inset.minY, width: inset.width * 0.22, height: inset.height)
            let covers = lengthwise
                ? CGRect(x: inset.minX, y: inset.minY + inset.height * 0.28,
                         width: inset.width, height: inset.height * 0.72)
                : CGRect(x: inset.minX + inset.width * 0.28, y: inset.minY,
                         width: inset.width * 0.72, height: inset.height)

            context.fill(Path(roundedRect: pillow, cornerRadius: 4), with: soft)
            context.stroke(Path(roundedRect: pillow, cornerRadius: 4), with: line, lineWidth: 0.75)
            context.stroke(Path(roundedRect: covers, cornerRadius: 2), with: line, lineWidth: 0.75)

            // The corner turned back sits at the foot, away from the pillow.
            let turn = min(covers.width, covers.height) * 0.42
            var fold = Path()
            if lengthwise {
                fold.move(to: CGPoint(x: covers.maxX, y: covers.maxY))
                fold.addLine(to: CGPoint(x: covers.maxX - turn, y: covers.maxY))
                fold.addLine(to: CGPoint(x: covers.maxX, y: covers.maxY - turn))
            } else {
                fold.move(to: CGPoint(x: covers.maxX, y: covers.minY))
                fold.addLine(to: CGPoint(x: covers.maxX - turn, y: covers.minY))
                fold.addLine(to: CGPoint(x: covers.maxX, y: covers.minY + turn))
            }
            fold.closeSubpath()
            context.fill(fold, with: soft)
            context.stroke(fold, with: line, lineWidth: 0.75)

        case "seat":
            // The seat, and a back along one edge. Which edge the back is on is
            // which way the chair faces — worth knowing before you put a camera
            // in front of it.
            let seat = rect.insetBy(dx: rect.width * 0.14, dy: rect.height * 0.14)
            context.stroke(Path(roundedRect: seat, cornerRadius: 3), with: line, lineWidth: 0.75)
            let back = CGRect(x: rect.minX, y: rect.minY,
                              width: rect.width * 0.16, height: rect.height)
            context.fill(Path(roundedRect: back, cornerRadius: 3), with: soft)
            context.stroke(Path(roundedRect: back, cornerRadius: 3), with: line, lineWidth: 0.75)

        case "sofa":
            // The back runs along a long edge, so it says which way the sofa
            // faces rather than turning it sideways.
            let alongWidth = rect.width >= rect.height
            let back = alongWidth
                ? CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.26)
                : CGRect(x: rect.minX, y: rect.minY, width: rect.width * 0.26, height: rect.height)
            context.fill(Path(roundedRect: back, cornerRadius: 3), with: soft)
            context.stroke(Path(roundedRect: back, cornerRadius: 3), with: line, lineWidth: 0.75)

        case "table":
            // Nothing. A table is a rectangle, and drawing a second rectangle
            // inside the first says nothing the first did not.
            break

        case "storage":
            // Doors, and the line where they meet.
            var doors = Path()
            doors.move(to: CGPoint(x: rect.midX, y: rect.minY))
            doors.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            context.stroke(doors, with: line, lineWidth: 0.75)

        case "screen":
            // Thin, and drawn with a face — which way a television points is
            // exactly what you want to know when placing a camera.
            var face = Path()
            face.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            face.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            context.stroke(face, with: GraphicsContext.Shading.color(ink.outline), lineWidth: 2)

        case "appliance":
            context.stroke(Path(ellipseIn: rect.insetBy(dx: rect.width * 0.25, dy: rect.height * 0.25)),
                           with: line, lineWidth: 0.75)

        case "plumbing":
            context.stroke(Path(ellipseIn: rect.insetBy(dx: rect.width * 0.15, dy: rect.height * 0.15)),
                           with: line, lineWidth: 0.75)

        case "stairs":
            var treads = Path()
            let count = max(Int(rect.height / 8), 2)
            for i in 1..<count {
                let y = rect.minY + rect.height * CGFloat(i) / CGFloat(count)
                treads.move(to: CGPoint(x: rect.minX, y: y))
                treads.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            context.stroke(treads, with: line, lineWidth: 0.5)

        default:
            break
        }
    }
}
