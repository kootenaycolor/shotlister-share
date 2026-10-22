import SwiftUI
import simd

/// The room from above, drawn to scale and measured wall by wall.
///
/// This is the half of a scan that does real work: it is measured, so it can be
/// read off, printed, and one day become the underlay a scene diagram is drawn
/// on top of. The 3D view is for recognising the place; this is for planning in
/// it.
///
/// **Ported from `phone/Sources/FloorPlan.swift`**, which found the bugs first
/// and on a real room. Changed only where the Mac differs: the gestures, the
/// zoom control, and the paper it is drawn on.
struct FloorPlanView: View {
    let plan: Plan

    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var settledPan: CGSize = .zero

    /// Furniture is what the room *had* on the day rather than what it is, and
    /// for blocking a scene an empty room is often the truth.
    ///
    /// Kept through `Remembering` rather than `@AppStorage` for the reason
    /// written on `ScanContent.mode`: `@AppStorage` writes to his real settings
    /// even during a checking run.
    @State private var showFurniture = true
    @State private var showDimensions = true
    @State private var showGrid = true

    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    private let margin: CGFloat = 68

    /// Drawing decisions, in one place.
    ///
    /// **The plan follows the app's theme now.** His note: *"the scene diagram
    /// viewer and the media viewer have different designs in general. One's all
    /// black, and one's gray with the white grid. Can we just make them feel
    /// more similar."* They were two different apps sitting in one window — a
    /// pop-out of black chrome, and a plan on white paper.
    ///
    /// The argument for white paper was real — every printed plan a location
    /// manager has ever held is dark ink on pale stock — but it was an argument
    /// about *paper*, and this is a screen at midnight beside a black shot list.
    /// So the ink stays exactly where it is in hue and the ground moves: slate
    /// walls, cool outlines, a barely-there grid, on whichever ground the rest
    /// of the app is standing on.
    private struct Ink {
        let dark: Bool
        var paper: Color { dark ? Brand.hex("15151A") : Color(red: 0.99, green: 0.99, blue: 0.995) }
        var wall: Color { dark ? Color(red: 0.44, green: 0.50, blue: 0.55)
                               : Color(red: 0.58, green: 0.65, blue: 0.69) }
        var outline: Color { dark ? Color(red: 0.62, green: 0.69, blue: 0.74)
                                  : Color(red: 0.36, green: 0.42, blue: 0.46) }
        var furniture: Color { dark ? Brand.hex("22242A") : .white }
        var detail: Color { dark ? Color(red: 0.52, green: 0.58, blue: 0.63)
                                 : Color(red: 0.62, green: 0.68, blue: 0.72) }
        var soft: Color { dark ? Brand.hex("2C2F36") : Color(red: 0.93, green: 0.95, blue: 0.96) }
        var rule: Color { dark ? Color(red: 0.42, green: 0.47, blue: 0.52)
                               : Color(red: 0.72, green: 0.75, blue: 0.77) }
        var grid: Color { dark ? Brand.hex("1D1E24") : Color(red: 0.94, green: 0.95, blue: 0.96) }
        var figure: Color { dark ? Color(red: 0.68, green: 0.74, blue: 0.79)
                                 : Color(red: 0.42, green: 0.47, blue: 0.51) }
        /// RoomPlan calls a wall a plane with no thickness. A plan needs one,
        /// and this is it — a drawing convention, never a measurement.
        static let wallThickness: Float = 0.12
    }

    private var ink: Ink { Ink(dark: dark) }

    var body: some View {
        VStack(spacing: 0) {
            Canvas { context, size in draw(in: &context, size: size) }
                .background(ink.paper)
                .gesture(
                    SimultaneousGesture(
                        MagnifyGesture()
                            .onChanged { zoom = clamp(settledZoom * $0.magnification) }
                            .onEnded { _ in settledZoom = zoom },
                        DragGesture()
                            .onChanged { pan = CGSize(width: settledPan.width + $0.translation.width,
                                                      height: settledPan.height + $0.translation.height) }
                            .onEnded { _ in settledPan = pan }
                    )
                )
                .onTapGesture(count: 2) { reset() }
                .overlay(alignment: .bottomTrailing) { controls }
                .overlay(alignment: .bottomLeading) { readout }
                .onAppear {
                    let kept = Remembering()
                    showFurniture = kept.object(forKey: "floorplan.furniture") as? Bool ?? true
                    showDimensions = kept.object(forKey: "floorplan.dimensions") as? Bool ?? true
                    showGrid = kept.object(forKey: "floorplan.grid") as? Bool ?? true
                }
                .onChange(of: showFurniture) { _, v in
                    Remembering().set(v, forKey: "floorplan.furniture")
                }
                .onChange(of: showDimensions) { _, v in
                    Remembering().set(v, forKey: "floorplan.dimensions")
                }
                .onChange(of: showGrid) { _, v in
                    Remembering().set(v, forKey: "floorplan.grid")
                }
        }
    }

    private func clamp(_ value: CGFloat) -> CGFloat { min(max(value, 0.4), 10) }

    // ---- what it says about itself ----------------------------------------

    private var readout: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(overall).mono(11, weight: .medium)
                .foregroundStyle(ink.outline)
            // The one measurement a plan cannot show by drawing, and the one
            // that decides what can be rigged in the room.
            Text(ceiling).mono(10)
                .foregroundStyle(ink.figure)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background { RoundedRectangle(cornerRadius: Brand.radius).fill(ink.paper.opacity(0.92)) }
        .overlay { RoundedRectangle(cornerRadius: Brand.radius).strokeBorder(ink.rule.opacity(0.5)) }
        .padding(12)
    }

    private var controls: some View {
        HStack(spacing: 6) {
            toggle("grid", $showGrid, "Two-foot grid")
            toggle("ruler", $showDimensions, "Wall dimensions")
            toggle("sofa", $showFurniture, "Furniture")
            Divider().frame(height: 14)
            step("minus", { zoom = clamp(zoom / 1.25); settledZoom = zoom })
            Button { reset() } label: {
                Text("\(Int(zoom * 100))%").mono(10)
                    .foregroundStyle(ink.outline)
                    .frame(width: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to fitting the page")
            step("plus", { zoom = clamp(zoom * 1.25); settledZoom = zoom })
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background { RoundedRectangle(cornerRadius: Brand.radius).fill(ink.paper.opacity(0.92)) }
        .overlay { RoundedRectangle(cornerRadius: Brand.radius).strokeBorder(ink.rule.opacity(0.5)) }
        .padding(12)
    }

    private func toggle(_ icon: String, _ on: Binding<Bool>, _ help: String) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(on.wrappedValue ? ink.outline : ink.rule)
                .frame(width: 22, height: 20)
                .background {
                    if on.wrappedValue {
                        RoundedRectangle(cornerRadius: Brand.radiusSmall).fill(ink.soft)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func step(_ icon: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ink.outline)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

        if showGrid { grid(in: &context, size: size, scale: scale, place: place) }

        // **Furniture goes under the walls.** A scanner measures a wardrobe to
        // its back panel and a wall to its face, so anything standing against a
        // wall overlaps it by a centimetre or two — and once a wall is drawn
        // with an invented thickness, by rather more. Letting the wall cover it
        // is how a plan looks right without moving anything.
        if showFurniture {
            for object in plan.items where object.kind == .object {
                Symbol.draw(object, in: &context, place: place, scale: scale, ink: (
                    fill: ink.furniture, outline: ink.outline, detail: ink.detail, soft: ink.soft
                ))
            }
        }

        for wall in plan.walls {
            context.fill(slab(wall, place), with: .color(ink.wall))
        }
        for hole in plan.items where hole.kind != .wall && hole.kind != .object {
            // The hole is cut a shade wider than the wall so no sliver of wall
            // survives along its edge.
            context.fill(slab(hole, place, thickness: Ink.wallThickness * 1.6),
                         with: .color(ink.paper))
            if hole.kind == .window { window(hole, in: &context, place: place) }
            if hole.kind == .door { swing(hole, in: &context, place: place, scale: scale) }
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
        while x < size.width {
            path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
            x += step
        }
        var y = origin.y.truncatingRemainder(dividingBy: step)
        while y < size.height {
            path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
            y += step
        }
        context.stroke(path, with: .color(ink.grid), lineWidth: 0.5)
    }

    /// The quarter-circle a door sweeps. Which way it opens is not in the scan,
    /// so it is drawn into the room — the question on a location is whether the
    /// door fouls the shot, and the arc is what answers it.
    private func swing(_ door: Plan.Item, in context: inout GraphicsContext,
                       place: (SIMD2<Float>) -> CGPoint, scale: CGFloat) {
        let hinge = place(door.ends.0)
        let width = CGFloat(door.size.x) * scale
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

        for wall in plan.walls.sorted(by: { $0.size.x > $1.size.x }) {
            // A short return is still a wall somebody has to shoot past, so it
            // is measured too. Below about eight inches it is scanner noise.
            guard wall.size.x > 0.2 else { continue }

            let (start, end) = wall.ends
            let out = wall.normal
            let away = simd_dot(out, wall.centre - centre) >= 0 ? out : -out

            let text = Measured.imperial(wall.size.x)
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
                Text(text).font(.system(size: 10, weight: .medium)).foregroundColor(ink.figure),
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

// MARK: - furniture

/// Furniture drawn as furniture.
///
/// A plan of grey rectangles has to be deciphered; one where the bed looks like
/// a bed is read at a glance, and on a location that is the difference between
/// a useful drawing and a diagram of a warehouse.
private enum Symbol {
    static func draw(_ item: Plan.Item, in context: inout GraphicsContext,
                     place: (SIMD2<Float>) -> CGPoint, scale: CGFloat,
                     ink: (fill: Color, outline: Color, detail: Color, soft: Color)) {
        let corners = item.corners.map(place)
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
        let w = CGFloat(item.size.x) * scale
        let d = CGFloat(item.size.y) * scale
        let rect = CGRect(x: -w / 2, y: -d / 2, width: w, height: d)
        detail(item.furnishing, in: &inner, rect: rect, ink: ink)
    }

    private static func detail(_ kind: Plan.Furnishing, in context: inout GraphicsContext, rect: CGRect,
                               ink: (fill: Color, outline: Color, detail: Color, soft: Color)) {
        let line = GraphicsContext.Shading.color(ink.detail)
        let soft = GraphicsContext.Shading.color(ink.soft)

        switch kind {
        case .bed:
            // A pillow at the head, the covers below it, and one corner turned
            // back — as a *filled triangle*, because an open line reads as a
            // stray diagonal across the room rather than as a bed.
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

            context.fill(Path(roundedRect: pillow, cornerRadius: Brand.radiusSmall), with: soft)
            context.stroke(Path(roundedRect: pillow, cornerRadius: Brand.radiusSmall), with: line, lineWidth: 0.75)
            context.stroke(Path(roundedRect: covers, cornerRadius: Brand.radiusSmall), with: line, lineWidth: 0.75)

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

        case .seat:
            // The seat, and a back along one edge. Which edge the back is on is
            // which way the chair faces — worth knowing before you put a camera
            // in front of it.
            let seat = rect.insetBy(dx: rect.width * 0.14, dy: rect.height * 0.14)
            context.stroke(Path(roundedRect: seat, cornerRadius: Brand.radiusSmall), with: line, lineWidth: 0.75)
            let back = CGRect(x: rect.minX, y: rect.minY,
                              width: rect.width * 0.16, height: rect.height)
            context.fill(Path(roundedRect: back, cornerRadius: Brand.radiusSmall), with: soft)
            context.stroke(Path(roundedRect: back, cornerRadius: Brand.radiusSmall), with: line, lineWidth: 0.75)

        case .sofa:
            // The back runs along a long edge, so it says which way the sofa
            // faces rather than turning it sideways.
            let alongWidth = rect.width >= rect.height
            let back = alongWidth
                ? CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.26)
                : CGRect(x: rect.minX, y: rect.minY, width: rect.width * 0.26, height: rect.height)
            context.fill(Path(roundedRect: back, cornerRadius: Brand.radiusSmall), with: soft)
            context.stroke(Path(roundedRect: back, cornerRadius: Brand.radiusSmall), with: line, lineWidth: 0.75)

        case .table:
            // Nothing. A table is a rectangle, and drawing a second rectangle
            // inside the first says nothing the first did not.
            break

        case .storage:
            var doors = Path()
            doors.move(to: CGPoint(x: rect.midX, y: rect.minY))
            doors.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            context.stroke(doors, with: line, lineWidth: 0.75)

        case .screen:
            // Thin, and drawn with a face — which way a television points is
            // exactly what you want to know when placing a camera.
            var face = Path()
            face.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            face.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            context.stroke(face, with: GraphicsContext.Shading.color(ink.outline), lineWidth: 2)

        case .appliance:
            context.stroke(Path(ellipseIn: rect.insetBy(dx: rect.width * 0.25, dy: rect.height * 0.25)),
                           with: line, lineWidth: 0.75)

        case .plumbing:
            context.stroke(Path(ellipseIn: rect.insetBy(dx: rect.width * 0.15, dy: rect.height * 0.15)),
                           with: line, lineWidth: 0.75)

        case .stairs:
            var treads = Path()
            let count = max(Int(rect.height / 8), 2)
            for i in 1..<count {
                let y = rect.minY + rect.height * CGFloat(i) / CGFloat(count)
                treads.move(to: CGPoint(x: rect.minX, y: y))
                treads.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            context.stroke(treads, with: line, lineWidth: 0.5)

        case .other:
            break
        }
    }
}
