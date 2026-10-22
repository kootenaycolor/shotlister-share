import SwiftUI

// **Drawing arrows on a frame** (the Mac's arrow tools, parity 3,
// 2026-10-16): drag to draw, tap one to pick it, then its bar sets heads,
// line, color, thickness, depth, stance and shape. Zoom In / Zoom Out marks.
// Saved as the engine's own arrow line, the one the Mac writes.

extension Engine.Arrow {
    /// **The same line the engine stores** (`Arrow::encode`, the Mac's
    /// `ArrowShape.encode`): seven numbers, then the tokens newer readers know.
    static func encode(_ arrows: [Engine.Arrow]) -> String {
        arrows.map(\.encoded).joined(separator: ";")
    }

    var lookWord: String {
        switch look { case .light: return "light"; case .dark: return "dark"; case .red: return "red"; case .yellow: return "yellow" }
    }

    var encoded: String {
        var look = ""
        if self.look != .light { look += ",look:\(lookWord)" }
        let t = (thickness * 100).rounded() / 100
        func near(_ v: Double) -> Bool { abs(t - v) < 0.005 }
        if near(0.7) { look += ",w:S" } else if near(1.4) { look += ",w:L" } else if !near(1) {
            if t < 0.85 { look += ",w:S" } else if t > 1.2 { look += ",w:L" }
            look += String(format: ",thick:%.2f", t)
        }
        if let zoom {
            var out = String(format: "zoom:%@,%.4f,%.4f,%.4f,%.4f", zoom == .zoomIn ? "in" : "out", x1, y1, x2, y2)
            if let v = view, v.count == 4 { out += String(format: ",view:%.4f:%.4f:%.4f:%.4f", v[0], v[1], v[2], v[3]) }
            return out + look
        }
        let b = bend
        var out = String(format: "%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%d", x1, y1, b.x, b.y, x2, y2, min(max(heads, 0), 2))
        for p in pins { out += String(format: ",p%.4f:%.4f", p.x, p.y) }
        if shape == .corner { out += ",corner" }
        if dashed { out += ",dashed" }
        out += look
        if depth != .flat {
            out += ",depth:" + (depth == .toward ? "toward" : "away")
            let s = (depthStrength * 100).rounded() / 100
            if abs(s - 0.5) >= 0.005 { out += String(format: ":%.2f", s) }
            if stance == .standing { out += ",stance:standing" }
        }
        if let w = widths, w.count == 2 { out += String(format: ",widths:%.4f:%.4f", w[0], w[1]) }
        return out
    }
}

/// **The arrow editor for one picture**, full screen.
struct ArrowEditorPhone: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    let ref: String
    let image: UIImage
    let start: [Engine.Arrow]

    @State private var arrows: [Engine.Arrow] = []
    @State private var picked: Int?
    @State private var trail: [CGPoint] = []

    private var ratio: CGFloat { image.size.height > 0 ? image.size.width / image.size.height : 1 }

    var body: some View {
        NavigationStack {
            GeometryReader { space in
                let plate = fitted(in: space.size)
                ZStack(alignment: .topLeading) {
                    Color.black.ignoresSafeArea()
                    Image(uiImage: image).resizable().frame(width: plate.width, height: plate.height)
                        .position(x: plate.midX, y: plate.midY)
                    ArrowMarks(arrows: shown(plate))
                        .frame(width: plate.width, height: plate.height)
                        .position(x: plate.midX, y: plate.midY)
                    if let picked, arrows.indices.contains(picked) {
                        let a = arrows[picked]
                        let box = CGRect(x: min(a.x1, a.x2), y: min(a.y1, a.y2), width: abs(a.x2 - a.x1), height: abs(a.y2 - a.y1))
                        Rectangle()
                            .stroke(Color(markHex: "0A84FF"), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                            .frame(width: box.width * plate.width + 24, height: box.height * plate.height + 24)
                            .position(x: plate.minX + box.midX * plate.width, y: plate.minY + box.midY * plate.height)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 4)
                    .onChanged { trail.append($0.location) }
                    .onEnded { _ in finish(plate) })
                .simultaneousGesture(SpatialTapGesture().onEnded { pick($0.location, plate) })
            }
            .safeAreaInset(edge: .bottom) { bar }
            .navigationTitle("Arrows")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if arrows != start { session.setArrows(ref: ref, arrows) }
                        dismiss()
                    }
                    .accessibilityIdentifier("arrows.done")
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear { arrows = start }
    }

    private func fitted(in room: CGSize) -> CGRect {
        let usable = CGSize(width: room.width - 16, height: room.height - 16)
        var w = usable.width, h = w / ratio
        if h > usable.height { h = usable.height; w = h * ratio }
        return CGRect(x: (room.width - w) / 2, y: (room.height - h) / 2, width: w, height: h)
    }

    /// The arrows, plus the one being drawn.
    private func shown(_ plate: CGRect) -> [Engine.Arrow] {
        guard trail.count >= 2, let a = drawn(plate) else { return arrows }
        return arrows + [a]
    }

    private func frac(_ p: CGPoint, _ plate: CGRect) -> CGPoint {
        CGPoint(x: min(max((p.x - plate.minX) / plate.width, 0), 1), y: min(max((p.y - plate.minY) / plate.height, 0), 1))
    }

    /// The finger's path as an arrow: tail where it began, head where it
    /// ended, one pin where it bent furthest from the straight line.
    private func drawn(_ plate: CGRect) -> Engine.Arrow? {
        guard let first = trail.first, let last = trail.last, hypot(last.x - first.x, last.y - first.y) > 14 else { return nil }
        let a = frac(first, plate), c = frac(last, plate)
        var arrow = Engine.Arrow(x1: a.x, y1: a.y, x2: c.x, y2: c.y)
        if let p = picked, arrows.indices.contains(p) {
            // A new arrow takes the look of the one picked.
            let o = arrows[p]
            arrow.look = o.look; arrow.thickness = o.thickness; arrow.dashed = o.dashed; arrow.heads = o.heads
        }
        let dx = last.x - first.x, dy = last.y - first.y, len = max(hypot(dx, dy), 1)
        var far: CGPoint?, most: CGFloat = 0
        for p in trail {
            let d = abs((p.x - first.x) * dy - (p.y - first.y) * dx) / len
            if d > most { most = d; far = p }
        }
        if let far, most > max(len * 0.08, 10) { arrow.pins = [frac(far, plate)] }
        return arrow
    }

    private func finish(_ plate: CGRect) {
        defer { trail = [] }
        guard let a = drawn(plate) else { return }
        arrows.append(a)
        picked = arrows.count - 1
    }

    private func pick(_ at: CGPoint, _ plate: CGRect) {
        let p = frac(at, plate)
        var best: (Int, CGFloat)?
        for (i, a) in arrows.enumerated() {
            let pts = [a.tail] + a.pins + [a.head]
            var d = CGFloat.infinity
            for k in 0..<(pts.count - 1) {
                d = min(d, Self.distance(p, pts[k], pts[k + 1], plate))
            }
            if a.zoom != nil {
                let r = CGRect(x: min(a.x1, a.x2), y: min(a.y1, a.y2), width: abs(a.x2 - a.x1), height: abs(a.y2 - a.y1))
                if r.contains(p) { d = 0 }
            }
            if d < 28, d < (best?.1 ?? .infinity) { best = (i, d) }
        }
        picked = best?.0
    }

    /// Screen distance from a point to a segment, all in fractions.
    private static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint, _ plate: CGRect) -> CGFloat {
        let P = CGPoint(x: p.x * plate.width, y: p.y * plate.height)
        let A = CGPoint(x: a.x * plate.width, y: a.y * plate.height), B = CGPoint(x: b.x * plate.width, y: b.y * plate.height)
        let dx = B.x - A.x, dy = B.y - A.y, l2 = dx * dx + dy * dy
        let t = l2 == 0 ? 0 : max(0, min(1, ((P.x - A.x) * dx + (P.y - A.y) * dy) / l2))
        return hypot(P.x - (A.x + t * dx), P.y - (A.y + t * dy))
    }

    private func set(_ change: (inout Engine.Arrow) -> Void) {
        guard let p = picked, arrows.indices.contains(p) else { return }
        change(&arrows[p])
    }

    @ViewBuilder private var bar: some View {
        HStack(spacing: 10) {
            if let p = picked, arrows.indices.contains(p) {
                let a = arrows[p]
                Menu {
                    if a.zoom == nil {
                        Picker("Heads", selection: Binding(get: { a.heads }, set: { v in set { $0.heads = v } })) {
                            Text("One").tag(1); Text("Both").tag(2); Text("None").tag(0)
                        }
                        Picker("Line", selection: Binding(get: { a.dashed }, set: { v in set { $0.dashed = v } })) {
                            Text("Solid").tag(false); Text("Dashed").tag(true)
                        }
                        Picker("Shape", selection: Binding(get: { a.shape == .corner }, set: { v in set { $0.shape = v ? .corner : .smooth } })) {
                            Text("Curve").tag(false); Text("Corner").tag(true)
                        }
                        Picker("Depth", selection: Binding(get: { a.depth }, set: { v in set { $0.depth = v } })) {
                            Text("Flat").tag(Engine.Arrow.Depth.flat)
                            Text("Toward").tag(Engine.Arrow.Depth.toward)
                            Text("Away").tag(Engine.Arrow.Depth.away)
                        }
                        if a.depth != .flat {
                            Picker("Lies", selection: Binding(get: { a.stance }, set: { v in set { $0.stance = v } })) {
                                Text("Floor").tag(Engine.Arrow.Stance.floor)
                                Text("Standing").tag(Engine.Arrow.Stance.standing)
                            }
                        }
                        if a.widths != nil { Button("Reset Widths") { set { $0.widths = nil } } }
                    }
                    Picker("Color", selection: Binding(get: { a.look }, set: { v in set { $0.look = v } })) {
                        Text("Light").tag(Engine.Arrow.Look.light)
                        Text("Dark").tag(Engine.Arrow.Look.dark)
                        Text("Red").tag(Engine.Arrow.Look.red)
                        Text("Yellow").tag(Engine.Arrow.Look.yellow)
                    }
                    Picker("Thickness", selection: Binding(get: { (a.thickness * 10).rounded() / 10 }, set: { v in set { $0.thickness = v } })) {
                        ForEach([0.5, 0.7, 1.0, 1.4, 2.0, 3.0], id: \.self) { Text(String(format: "%.1f×", $0)).tag($0) }
                    }
                } label: { pill("slider.horizontal.3", "Style") }
                Button { arrows.remove(at: p); picked = nil } label: { pill("trash", "Delete") }
            } else {
                Menu {
                    Button("Zoom In") { addZoom(.zoomIn) }
                    Button("Zoom Out") { addZoom(.zoomOut) }
                    if !arrows.isEmpty { Button("Clear All", role: .destructive) { arrows = []; picked = nil } }
                } label: { pill("plus.viewfinder", "Add") }
                Text("Drag to draw").font(.system(size: Kit.Size.body)).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black)
    }

    private func addZoom(_ z: Engine.Arrow.Zoom) {
        var a = Engine.Arrow(x1: 0.3, y1: 0.3, x2: 0.7, y2: 0.7)
        a.zoom = z
        arrows.append(a)
        picked = arrows.count - 1
    }

    private func pill(_ symbol: String, _ title: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: Kit.Size.body, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).frame(height: 36)
            .background(Capsule().fill(Color.white.opacity(0.16)))
    }
}
