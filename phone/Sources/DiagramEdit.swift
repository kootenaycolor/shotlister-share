import SwiftUI
import UIKit
import PhotosUI

/// **Editing a diagram on the phone** (parity with Studio Mac, 2026-10-16).
///
/// The engine does all of it — the same `diagramedit` ops the Mac sends, one
/// undo each, the same snapping and rigging — so this file is only touch:
/// tap to pick (`diagramhit`), drag a picked piece to move it (previewed with
/// `diagrampreview`, written on letting go), two fingers to turn it, and a
/// bar of the Mac's commands. Plans, Copy From, Room from Scan and Export sit
/// in the menu at the top. Labels and drawing on photos are another thread's.
struct DiagramEditor: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    let id: String
    let title: String
    /// Whether this is a loose plan (renamed and deleted here) or a scene's.
    let isPlan: Bool
    var changed: () -> Void = {}

    struct El: Decodable, Identifiable {
        var id: String
        var kind: String?
        var layer: String?
        var x: Double?
        var y: Double?
        var rot: Double?
        var label: String?
        var shot: String?
    }

    private struct Reply: Decodable {
        var shapes: [DiagramPlan.Shape]
        var extent: [Double]?
        var els: [El]?
        var lastBeat: Int?
        var settings: Settings?
        struct Settings: Decodable { var snap: Bool? }
    }

    @State private var shapes: [DiagramPlan.Shape] = []
    @State private var els: [El] = []
    @State private var lastBeat = 1
    /// The extent the view was fitted to on opening, kept so the plan does
    /// not jump when a piece goes past its edge.
    @State private var anchor: [Double]?
    @State private var selection: [String] = []
    @State private var beat = 1
    @State private var playing = false
    @State private var tween = 0.0
    @State private var playTimer: Timer?

    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var settledPan: CGSize = .zero
    /// What a drag is doing: moving the picked pieces, or the view.
    @State private var moving: Bool?
    @State private var turning: Double = 0
    @State private var size: CGSize = .zero

    @State private var renaming = false
    @State private var namingPiece = false
    @State private var naming = ""
    @State private var newName = ""
    @State private var deletingPlan = false
    @State private var library = false
    @State private var said: String?
    @State private var exported: MadeFile?

    // Drawing by finger (`DiagramTools.swift`), and the three sheets.
    @State private var tool: DiagramDraw?
    /// The wall being drawn, once it has its first stretch.
    @State private var wallId: String?
    /// The first corner tapped, before there is a wall.
    @State private var wallStart: CGPoint?
    /// The drag being drawn, in screen points.
    @State private var sketch: [CGPoint] = []
    @State private var snaps = true
    /// **Details stays up once asked for** (his note, 2026-10-17): on, it
    /// rises for every piece picked until he shuts it with Done or a swipe.
    @AppStorage("diagramDetailsOpen") private var detailsOn = false
    @State private var layers = false
    @State private var planSettings = false
    /// The picture being drawn on (Draw on Photo).
    @State private var drawingOn: String?
    /// **Pick Several**: each tap adds a piece or takes it off.
    @State private var severalPicking = false
    /// **A wall's corners** while one wall, drawing or ruler is picked:
    /// drag one to move it; tap one, then Break, Curve or Delete it.
    @State private var corners: [CGPoint] = []
    @State private var pickedCorner: Int?
    @State private var cornerDrag: (Int, CGPoint)?
    @State private var cornerKind = ""
    @State private var cornerRound: [Int] = []
    /// A picture from Photos, laid on the plan (the Mac's Picture tool).
    @State private var pickingPicture = false
    @State private var pictureItem: PhotosPickerItem?

    private var engine: Engine? { session.engine }

    private var pickedIsWords: Bool {
        selection.count == 1 && els.first { $0.id == selection[0] }?.kind == "text"
    }

    /// A Words piece's words, off the plan's own JSON.
    private func wordsOf(_ piece: String) -> String? {
        guard let engine else { return nil }
        let data = engine.raw("diagram", id, "beat=\(beat)")
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let all = obj["els"] as? [[String: Any]],
              let e = all.first(where: { $0["id"] as? String == piece }) else { return nil }
        return e["text"] as? String
    }

    static func isPlan(_ id: String, engine: Engine?) -> Bool {
        struct P: Decodable { var plans: [Plan] }
        struct Plan: Decodable { var id: String }
        guard let data = engine?.raw("diagramplans") else { return false }
        return ((try? JSONDecoder().decode(P.self, from: data))?.plans ?? []).contains { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    Color(hex: DiagramInk.light["paper"]!).ignoresSafeArea()
                    canvas
                        .contentShape(Rectangle())
                        .gesture(tap)
                        .simultaneousGesture(drag)
                        .simultaneousGesture(pinch)
                        .simultaneousGesture(turn)
                }
                .onAppear { size = geo.size }
                .onChange(of: geo.size) { _, now in size = now; read() }
            }
            .overlay(alignment: .bottom) { bar }
            .overlay(alignment: .top) {
                if let said {
                    Text(said)
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .glassCapsule(interactive: false)
                        .padding(.top, 6)
                        .transition(.opacity)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { changed(); dismiss() }
                }
                ToolbarItem(placement: .primaryAction) { planMenu }
            }
            .alert("Rename Plan", isPresented: $renaming) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    _ = engine?.raw("diagramplanrename", id, newName)
                    session.refresh()
                    changed()
                }
            }
            .alert(pickedIsWords ? "Words" : "Name", isPresented: $namingPiece) {
                TextField(pickedIsWords ? "Words" : "Name", text: $naming)
                Button("Cancel", role: .cancel) {}
                Button("Set") { name(naming) }
            }
            .confirmationDialog("Delete this plan?", isPresented: $deletingPlan, titleVisibility: .visible) {
                Button("Delete Plan", role: .destructive) {
                    _ = engine?.raw("diagramplandelete", id)
                    session.refresh()
                    changed()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $library) {
                DiagramLibrarySheet { symbol in add(symbol: symbol) }
                    .environmentObject(session)
            }
            .sheet(item: $exported) { made in
                ShareSheetView(items: [made.url])
            }
            // Half height, drag up for full; the plan above stays live, so a
            // tap on another piece shows that one. Nothing picked, it lowers
            // and comes back with the next pick.
            .sheet(isPresented: Binding(get: { detailsOn && selection.count == 1 && tool == nil && drawingOn == nil },
                                        set: { if !$0 { detailsOn = false } }), onDismiss: read) {
                if let one = selection.first {
                    DiagramDetailsSheet(plan: id, pieceId: one, beat: beat) { op in edit(op) }
                        .id(one)
                        .environmentObject(session)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                }
            }
            .fullScreenCover(isPresented: Binding(get: { drawingOn != nil }, set: { if !$0 { drawingOn = nil } }), onDismiss: read) {
                if let photo = drawingOn {
                    PhotoEditorPhone(plan: id, photo: photo) { op in edit(op) }
                        .environmentObject(session)
                }
            }
            .photosPicker(isPresented: $pickingPicture, selection: $pictureItem, matching: .images)
            .onChange(of: pictureItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) { layPicture(data) }
                    pictureItem = nil
                }
            }
            .sheet(isPresented: $layers, onDismiss: read) {
                DiagramLayersSheet(plan: id, picked: selection, pick: { selection = [$0]; read() }) { op in edit(op) }
                    .environmentObject(session)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $planSettings, onDismiss: read) {
                DiagramPlanSettingsSheet(plan: id, edit: { op in edit(op) }, everywhere: changed)
                    .environmentObject(session)
                    .presentationDetents([.medium, .large])
            }
        }
        .environment(\.colorScheme, .light)
        .task { read() }
        .onDisappear { playTimer?.invalidate(); playTimer = nil }
    }

    // ---- reading -----------------------------------------------------------

    /// The plan at the zoom it is drawn at, so names keep their size.
    private var drawnScale: CGFloat { fit.k * zoom }

    private func read() {
        guard let engine else { return }
        let args = ["diagram", id, "beat=\(beat)", "sel=\(selection.joined(separator: ","))", "tween=\(tween)",
                    String(format: "ppm=%.2f", max(Double(drawnScale), 10)),
                    "tz=\(TimeZone.current.secondsFromGMT() / 60)"]
        take(engine.raw(args))
    }

    private func readCorners() {
        guard selection.count == 1,
              let p = DiagramPiece.read(id, engine: engine).els.first(where: { $0.id == selection[0] }),
              ["wall", "stroke", "measure"].contains(p.kind) else {
            corners = []; pickedCorner = nil; return
        }
        cornerKind = p.kind
        cornerRound = (p.raw["round"] as? [NSNumber])?.map(\.intValue) ?? []
        if let pts = p.raw["points"] as? [[NSNumber]], pts.count >= 2 {
            corners = pts.compactMap { $0.count >= 2 ? CGPoint(x: $0[0].doubleValue, y: $0[1].doubleValue) : nil }
        } else {
            corners = [CGPoint(x: p.n("x"), y: p.n("y")), CGPoint(x: p.n("x2"), y: p.n("y2"))]
        }
        if let c = pickedCorner, c >= corners.count { pickedCorner = nil }
    }

    /// The corner under a finger, if one is.
    private func corner(at screen: CGPoint) -> Int? {
        let T = transform
        return corners.indices.min { a, b in
            hypot(corners[a].applying(T).x - screen.x, corners[a].applying(T).y - screen.y)
                < hypot(corners[b].applying(T).x - screen.x, corners[b].applying(T).y - screen.y)
        }.flatMap { i in hypot(corners[i].applying(T).x - screen.x, corners[i].applying(T).y - screen.y) < 22 ? i : nil }
    }

    private func take(_ data: Data) {
        guard let r = try? JSONDecoder().decode(Reply.self, from: data) else { return }
        shapes = r.shapes
        els = r.els ?? []
        lastBeat = max(1, r.lastBeat ?? 1)
        // The first read is made before the screen's size or the plan's
        // extent is known, so its names were kept apart at a made-up zoom
        // (far from their pieces). Once the extent arrives, read again at
        // the zoom the plan is really drawn at.
        let firstExtent = anchor == nil
        if anchor == nil, let e = r.extent, e.count == 4 { anchor = e }
        if firstExtent, anchor != nil { DispatchQueue.main.async { read() } }
        snaps = r.settings?.snap ?? true
        readCorners()
        selection = selection.filter { s in els.contains { $0.id == s } }
    }

    // ---- where the plan is on screen --------------------------------------

    private var fit: (k: CGFloat, T: CGAffineTransform) {
        let e = anchor ?? [-3, -3, 3, 3]
        let w = max(e[2] - e[0], 1), h = max(e[3] - e[1], 1)
        let room = CGRect(x: 12, y: 12, width: max(size.width - 24, 10), height: max(size.height - 120, 10))
        let k = min(room.width / w, room.height / h) * 0.85
        let T = CGAffineTransform(a: k, b: 0, c: 0, d: k,
                                  tx: room.midX - (e[0] + w / 2) * k, ty: room.midY - (e[1] + h / 2) * k)
        return (k, T)
    }

    private var transform: CGAffineTransform {
        let mid = CGPoint(x: size.width / 2, y: size.height / 2)
        return fit.T
            .concatenating(CGAffineTransform(translationX: -mid.x, y: -mid.y))
            .concatenating(CGAffineTransform(scaleX: zoom, y: zoom))
            .concatenating(CGAffineTransform(translationX: mid.x + pan.width, y: mid.y + pan.height))
    }

    private func onPlan(_ p: CGPoint) -> CGPoint { p.applying(transform.inverted()) }

    /// The middle of what is on screen, in metres: where a new piece goes.
    private var middle: CGPoint { onPlan(CGPoint(x: size.width / 2, y: (size.height - 80) / 2)) }

    private var canvas: some View {
        let T = transform
        let scale = drawnScale
        let picked = Set(selection)
        return Canvas { context, _ in
            context.withCGContext { cg in
                UIGraphicsPushContext(cg)
                defer { UIGraphicsPopContext() }
                let painter = DiagramPaint(scale: scale, shrink: min(1, max(0.25, scale / 40)), engine: engine)
                for shape in shapes { painter.paint(shape, cg, T) }
                // **What is picked**, outlined: the box round its drawing.
                var box = CGRect.null
                for shape in shapes where shape.e.map(picked.contains) == true {
                    if let d = shape.d { box = box.union(painter.path(d, T).boundingBoxOfPath) }
                    else if let x = shape.x, let y = shape.y {
                        box = box.union(CGRect(origin: CGPoint(x: x, y: y).applying(T), size: .zero).insetBy(dx: -8, dy: -8))
                    }
                }
                if !box.isNull {
                    cg.setStrokeColor(UIColor.systemBlue.cgColor)
                    cg.setLineWidth(1.5)
                    cg.setLineDash(phase: 0, lengths: [5, 3])
                    cg.stroke(box.insetBy(dx: -6, dy: -6))
                }
                // A picked wall's corners, the picked one filled.
                for (i, c) in corners.enumerated() {
                    let p = (cornerDrag?.0 == i ? cornerDrag!.1 : c).applying(T)
                    let r = CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)
                    cg.setLineDash(phase: 0, lengths: [])
                    cg.setFillColor(pickedCorner == i ? UIColor.systemBlue.cgColor : UIColor.white.cgColor)
                    cg.fillEllipse(in: r)
                    cg.setStrokeColor(UIColor.systemBlue.cgColor)
                    cg.setLineWidth(2)
                    cg.strokeEllipse(in: r)
                }
                // **What a finger is drawing**, before it is a piece.
                cg.setLineDash(phase: 0, lengths: [])
                cg.setStrokeColor(UIColor.systemBlue.cgColor)
                cg.setLineWidth(2)
                if let start = wallStart {
                    let p = start.applying(T)
                    cg.fillEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
                }
                if sketch.count >= 2, let tool {
                    let a = sketch[0], b = sketch[sketch.count - 1]
                    switch tool {
                    case .room, .shape:
                        cg.stroke(CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y)))
                    case .pen:
                        cg.addLines(between: sketch)
                        cg.strokePath()
                    default:
                        cg.addLines(between: [a, b])
                        cg.strokePath()
                    }
                }
            }
        }
    }

    // ---- touch ---------------------------------------------------------------

    private func hit(_ p: CGPoint) -> String? {
        guard let engine else { return nil }
        let at = onPlan(p)
        struct Hit: Decodable { var id: String? }
        let data = engine.raw("diagramhit", id, String(Double(at.x)), String(Double(at.y)),
                              String(Double(22 / max(drawnScale, 1))), "beat=\(beat)",
                              String(format: "ppm=%.2f", max(Double(drawnScale), 10)))
        return (try? JSONDecoder().decode(Hit.self, from: data))?.id
    }

    private var tap: some Gesture {
        SpatialTapGesture().onEnded { value in
            if let tool { toolTap(tool, value.location); return }
            if let c = corner(at: value.location) { pickedCorner = pickedCorner == c ? nil : c; return }
            pickedCorner = nil
            if let piece = hit(value.location) {
                if severalPicking {
                    selection = selection.contains(piece) ? selection.filter { $0 != piece } : selection + [piece]
                } else {
                    selection = selection == [piece] ? [] : [piece]
                }
            } else {
                selection = []
            }
            read()
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if let tool, !tool.taps {
                    if tool == .pen { sketch.append(value.location) }
                    else { sketch = [value.startLocation, value.location] }
                    return
                }
                if moving == nil, cornerDrag == nil, let c = corner(at: value.startLocation) {
                    cornerDrag = (c, corners[c])
                }
                if let (c, _) = cornerDrag {
                    cornerDrag = (c, snapped(value.location))
                    return
                }
                if moving == nil {
                    let on = hit(value.startLocation)
                    moving = on.map { selection.contains($0) } ?? false
                    if moving == false, let on, selection.isEmpty == false, !selection.contains(on) { moving = false }
                }
                if moving == true {
                    preview(moveOp(value.translation))
                } else {
                    pan = CGSize(width: settledPan.width + value.translation.width,
                                 height: settledPan.height + value.translation.height)
                }
            }
            .onEnded { value in
                if let (c, at) = cornerDrag {
                    cornerDrag = nil
                    edit(["op": "wall_corner", "id": selection[0], "corner": c, "x": Double(at.x), "y": Double(at.y)])
                    return
                }
                if let tool, !tool.taps {
                    finishSketch(tool, from: value.startLocation, to: value.location)
                    return
                }
                if moving == true {
                    edit(moveOp(value.translation))
                } else {
                    settledPan = pan
                    read()
                }
                moving = nil
            }
    }

    private func moveOp(_ t: CGSize) -> [String: Any] {
        let k = Double(drawnScale)
        if beat > 1, let one = selection.first, let e = els.first(where: { $0.id == one }), let x = e.x, let y = e.y {
            // On a beat after the first, a piece's place is that beat's.
            return ["op": "beat", "id": one, "beat": beat, "x": x + t.width / k, "y": y + t.height / k]
        }
        return ["op": "move", "ids": selection, "dx": t.width / k, "dy": t.height / k]
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { zoom = min(12, max(0.4, settledZoom * $0.magnification)) }
            .onEnded { _ in settledZoom = zoom; read() }
    }

    private var turn: some Gesture {
        RotateGesture()
            .onChanged { value in
                guard !selection.isEmpty else { return }
                turning = value.rotation.degrees
                preview(["op": "rotate", "ids": selection, "deg": turning])
            }
            .onEnded { value in
                guard !selection.isEmpty else { return }
                // To the nearest 5°, the way a hand means it.
                let deg = (value.rotation.degrees / 5).rounded() * 5
                if deg != 0 { edit(["op": "rotate", "ids": selection, "deg": deg]) } else { read() }
                turning = 0
            }
    }

    // ---- writing ---------------------------------------------------------------

    private static func json(_ op: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(op),
              let data = try? JSONSerialization.data(withJSONObject: op, options: [.withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text.replacingOccurrences(of: "\t", with: "\\t")
    }

    private func preview(_ op: [String: Any]) {
        guard let engine, let json = Self.json(op) else { return }
        let data = engine.raw("diagrampreview", id, json, "beat=\(beat)", "sel=\(selection.joined(separator: ","))",
                              String(format: "ppm=%.2f", max(Double(drawnScale), 10)),
                              "tz=\(TimeZone.current.secondsFromGMT() / 60)")
        if let r = try? JSONDecoder().decode(Reply.self, from: data) { shapes = r.shapes }
    }

    /// One edit, one undo. What it made is picked, when `pick` says so.
    @discardableResult
    private func edit(_ op: [String: Any], pick: Bool = false) -> [String] {
        guard let engine, let json = Self.json(op) else { return [] }
        let data = engine.raw("diagramedit", id, json, "beat=\(beat)", "sel=\(selection.joined(separator: ","))",
                              String(format: "ppm=%.2f", max(Double(drawnScale), 10)),
                              "tz=\(TimeZone.current.secondsFromGMT() / 60)")
        struct Made: Decodable { var made: [String] }
        if let problem = Session.refusal(in: data) { say(problem); read(); return [] }
        let made = (try? JSONDecoder().decode(Made.self, from: data))?.made ?? []
        if pick, !made.isEmpty { selection = made }
        session.refresh()
        read()
        return made
    }

    private func say(_ words: String) {
        withAnimation { said = words }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { withAnimation { if said == words { said = nil } } }
    }

    // ---- adding ----------------------------------------------------------------

    private func addLamp(mark: String, ink: String, solid: Bool) {
        let p = middle
        let mat = mark == "mat"
        var el: [String: Any] = ["kind": "light", "sym": "", "x": p.x, "y": p.y, "rot": mat ? 0 : 270,
                                 "w": mat ? 1.2192 : 0.3, "h": mat ? 0.6096 : 0.3,
                                 "mark": mark, "mark_fill": solid ? "solid" : "open",
                                 "practical": ink == "practical", "existing": ink == "ink"]
        edit(["op": "add", "els": [el]], pick: true)
    }

    private func addCamera(shot: String?) {
        let p = middle
        var el: [String: Any] = ["kind": "camera", "x": p.x, "y": p.y, "rot": 270]
        if let shot { el["shot"] = shot } else { el["new_shot"] = true }
        edit(["op": "add", "els": [el]], pick: true)
    }

    private func addCast(_ name: String?) {
        let p = middle
        var el: [String: Any] = ["kind": "cast", "x": p.x, "y": p.y, "rot": 0]
        if let name, !name.isEmpty { el["label"] = name; el["cast"] = name }
        else { el["label"] = "Cast \(els.filter { $0.kind == "cast" }.count + 1)" }
        edit(["op": "add", "els": [el]], pick: true)
    }

    private func addWords() {
        let p = middle
        edit(["op": "add", "els": [["kind": "text", "x": p.x, "y": p.y, "text": "Words", "size": 14.0]]], pick: true)
    }

    private func add(symbol s: DiagramLibrarySheet.Symbol) {
        let p = middle
        var e: [String: Any] = ["kind": s.light ? "light" : "set", "sym": s.id, "x": p.x, "y": p.y,
                                "rot": s.light ? 270 : 0, "w": s.w, "h": s.h]
        if s.light {
            e["beam"] = s.beam; e["reach"] = s.reach; e["kelvin"] = s.kelvin; e["beam_on"] = s.beam > 0
        }
        edit(["op": "add", "els": [e]], pick: true)
    }

    private func dropFavorite(_ slot: Int) {
        guard let engine else { return }
        let p = middle
        let data = engine.raw("diagramfavoriteat", id, String(slot), String(Double(p.x)), String(Double(p.y)))
        guard let op = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["op"] as? [String: Any]
        else { say("Empty"); return }
        edit(op, pick: true)
    }

    private var favorites: [(slot: Int, name: String)] {
        guard let engine else { return [] }
        let data = engine.raw("diagramfavorites", id)
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let slots = obj["slots"] as? [Any] else { return [] }
        return slots.enumerated().compactMap { at, s in
            guard let s = s as? [String: Any], let name = s["name"] as? String else { return nil }
            return (at, name)
        }
    }

    private var cast: (scene: [String], film: [String]) {
        guard let engine else { return ([], []) }
        struct R: Decodable { var scene: [String]; var film: [String] }
        let r = try? JSONDecoder().decode(R.self, from: engine.raw("diagramcast", id))
        return (r?.scene ?? [], r?.film ?? [])
    }

    // ---- the bar ---------------------------------------------------------------

    private var bar: some View {
        HStack(spacing: 8) {
            if let tool {
                toolBar(tool)
            } else if selection.isEmpty {
                addMenu
                beatStepper
                beatMenu
            } else {
                // **Details, first and in sight** (2026-10-17), not in More.
                if selection.count == 1 {
                    barButton("info.circle", "Details") { detailsOn = true }
                        .accessibilityIdentifier("diagram.details")
                }
                barButton("rotate.left", "Turn Left") { edit(["op": "rotate", "ids": selection, "deg": -15]) }
                barButton("rotate.right", "Turn Right") { edit(["op": "rotate", "ids": selection, "deg": 15]) }
                Menu {
                    Button("Duplicate") { edit(["op": "duplicate", "ids": selection, "dx": 0.5, "dy": 0.5], pick: true) }
                    if let c = pickedCorner, selection.count == 1 {
                        Section("Corner") {
                            if cornerKind == "wall" {
                                Button("Break Here") { edit(["op": "wall_break", "id": selection[0], "corner": c]); pickedCorner = nil }
                                Button(cornerRound.contains(c) ? "Make a Corner" : "Make a Curve") {
                                    edit(["op": "wall_round", "id": selection[0], "corner": c, "round": !cornerRound.contains(c)])
                                }
                            }
                            if corners.count > 2 {
                                Button("Delete Corner", role: .destructive) {
                                    edit(["op": "wall_remove_corner", "id": selection[0], "corner": c]); pickedCorner = nil
                                }
                            }
                            if c + 1 < corners.count || cornerKind == "wall" {
                                Button("Add Corner After") { edit(["op": "wall_insert", "id": selection[0], "stretch": min(c, corners.count - 1)]) }
                            }
                        }
                    }
                    if selection.count == 1, els.first(where: { $0.id == selection[0] })?.kind == "image" {
                        Button("Draw on Photo") { drawingOn = selection[0] }
                    }
                    Button(pickedIsWords ? "Edit Words…" : "Name…") {
                        let e = els.first { $0.id == selection[0] }
                        naming = pickedIsWords ? (wordsOf(selection[0]) ?? "") : (selection.count == 1 ? (e?.label ?? "") : "")
                        namingPiece = true
                    }
                    Button(severalPicking ? "Pick One at a Time" : "Pick Several") {
                        severalPicking.toggle()
                        say(severalPicking ? "Tap to add or take off" : "One at a time")
                    }
                    // **A camera's shot** (the Mac's shot menu on a camera).
                    if selection.count == 1, els.first(where: { $0.id == selection[0] })?.kind == "camera" {
                        Menu("Shot") {
                            ForEach(session.rows(inScene: id)) { row in
                                Button("\(row.number)  \(row.title)") {
                                    edit(["op": "update", "ids": selection, "set": ["shot": row.shot]])
                                }
                            }
                        }
                    }
                    // **One Color for all picked** (2026-10-17).
                    Menu("Color") {
                        Button("None") { edit(["op": "update", "ids": selection, "set": ["color": ""]]) }
                        ForEach(Array(Swatches.highlight.enumerated()), id: \.offset) { i, hex in
                            Button(Swatches.highlightNames[i]) { edit(["op": "update", "ids": selection, "set": ["color": "#" + hex.uppercased()]]) }
                        }
                    }
                    // **Send to Set / Plot, Copy to …** (2026-10-17).
                    let sendable = selection.filter { sid in
                        els.first { $0.id == sid }.map { !["wall", "door", "window", "opening", "road", "cast"].contains($0.kind ?? "") } ?? false
                    }
                    if !sendable.isEmpty {
                        let now = Set(sendable.map { sid in els.first { $0.id == sid }?.layer ?? "plot" })
                        ForEach(now.count == 1 ? [now.first == "set" ? "plot" : "set"] : ["set", "plot"], id: \.self) { to in
                            let name = to == "set" ? "Set" : "Plot"
                            Button("Send to \(name)") { edit(["op": "send_layer", "ids": sendable, "to": to]) }
                            Button("Copy to \(name)") { edit(["op": "send_layer", "ids": sendable, "to": to, "copy": true]) }
                        }
                    }
                    Button("Bring to Front") { edit(["op": "order", "ids": selection, "to": "front"]) }
                    Button("Send to Back") { edit(["op": "order", "ids": selection, "to": "back"]) }
                    Button("Flip Across") { edit(["op": "flip", "ids": selection, "axis": "x"]) }
                    Button("Flip Up and Down") { edit(["op": "flip", "ids": selection, "axis": "y"]) }
                    if beat > 1 {
                        Button("Off This Beat") { edit(["op": "unbeat", "id": selection[0], "beat": beat]) }
                    }
                    Menu("Keep as Favorite") {
                        ForEach(0..<9, id: \.self) { slot in
                            Button("Slot \(slot + 1)") {
                                _ = engine?.raw("diagramfavoriteset", id, String(slot), selection[0])
                                say("Kept")
                            }
                        }
                    }
                } label: { circle("ellipsis") }
                .accessibilityLabel("More")
                barButton("trash", "Delete") { edit(["op": "remove", "ids": selection]); selection = [] }
            }
            Spacer(minLength: 0)
            barButton("arrow.uturn.backward", "Undo") { _ = session.undo(); read() }
            barButton("arrow.uturn.forward", "Redo") { _ = session.redo(); read() }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var beatStepper: some View {
        let last = max(lastBeat, beat)
        return HStack(spacing: 6) {
            Button { stopPlaying(); beat = max(1, beat - 1); read() } label: { Image(systemName: "chevron.left") }
                .disabled(beat <= 1)
                .accessibilityLabel("Previous Beat")
            Text("Beat \(beat) of \(last)").font(.system(size: 13, weight: .semibold)).monospacedDigit()
            Button { stopPlaying(); beat = min(last, beat + 1); read() } label: { Image(systemName: "chevron.right") }
                .disabled(beat >= last)
                .accessibilityLabel("Next Beat")
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .glassCapsule()
        .accessibilityIdentifier("diagram.beat")
    }

    /// **Beats** (the Mac's beat bar): a new beat after the last, Play, and
    /// this beat taken out or moved earlier or later. Beats are numbered, as
    /// on the Mac, so they have no names.
    private var beatMenu: some View {
        Menu {
            Button("Add Beat") { stopPlaying(); beat = max(lastBeat, beat) + 1; read() }
            if lastBeat > 1 {
                Button(playing ? "Stop" : "Play") { playing ? stopPlaying() : play() }
            }
            if beat > 1 {
                Section("This Beat") {
                    if beat > 2 { Button("Move Earlier") { moveBeat(by: -1) } }
                    if beat < lastBeat { Button("Move Later") { moveBeat(by: 1) } }
                    Button("Remove Beat", role: .destructive) { removeBeat() }
                }
            }
        } label: { circle("film.stack") }
        .accessibilityLabel("Beats")
        .accessibilityIdentifier("diagram.beats")
    }

    // ---- beats -----------------------------------------------------------------

    /// Every piece's steps with their beats, off the plan's own `seq`.
    private func beatSteps() -> [DiagramBeats.Piece] {
        DiagramPiece.read(id, engine: engine).els.compactMap { p in
            guard let seq = p.raw["seq"] as? [[String: Any]], seq.count > 1 else { return nil }
            return (p.id, seq.enumerated().map { i, t in
                (i, (t["beat"] as? NSNumber)?.intValue ?? 0, (t["home"] as? Bool) ?? false)
            })
        }
    }

    /// **Remove Beat**: each piece's step on this beat goes, and every later
    /// beat comes down one. One undo.
    private func removeBeat() {
        stopPlaying()
        let n = beat
        guard n > 1 else { return }
        let ops = DiagramBeats.removeOps(n, pieces: beatSteps())
        if !ops.isEmpty { edit(["op": "batch", "ops": ops]) }
        beat = max(1, min(n, max(lastBeat, 1)))
        read()
        say("Beat \(n) removed")
    }

    /// **Move Earlier / Later**: this beat and its neighbour trade places for
    /// every piece. One undo.
    private func moveBeat(by d: Int) {
        stopPlaying()
        let n = beat, m = n + d
        guard n > 1, m > 1 else { return }
        let ops = DiagramBeats.moveOps(n, by: d, pieces: beatSteps())
        if !ops.isEmpty { edit(["op": "batch", "ops": ops]) }
        beat = m
        read()
    }

    /// Watch the blocking happen, a beat at a time, easing between them.
    private func play() {
        guard lastBeat > 1 else { return }
        selection = []
        if beat >= lastBeat { beat = 1 }
        playing = true
        tween = 0
        playTimer?.invalidate()
        playTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { _ in
            DispatchQueue.main.async {
                let next = tween + 1.0 / 24.0
                if next >= 1 {
                    tween = 0
                    beat += 1
                    if beat >= lastBeat { read(); stopPlaying(); return }
                } else {
                    tween = next
                }
                read()
            }
        }
    }

    private func stopPlaying() {
        playTimer?.invalidate()
        playTimer = nil
        if playing || tween != 0 { playing = false; tween = 0; read() }
    }

    private var addMenu: some View {
        Menu {
            Menu("Light") {
                ForEach([("added", "Film Light"), ("practical", "Practical"), ("ink", "Existing")], id: \.0) { ink, name in
                    Menu(name) {
                        ForEach([("chevron", "Chevron"), ("wedge", "Wedge"), ("bar", "Bar"), ("double-bar", "Panel"),
                                 ("ring", "Ring"), ("dot", "Dot"), ("square", "Square"), ("mat", "Mat")], id: \.0) { mark, title in
                            Button(title) {
                                addLamp(mark: mark, ink: ink, solid: ["wedge", "bar", "double-bar", "dot"].contains(mark))
                            }
                        }
                    }
                }
            }
            Menu("Camera") {
                Button("New Shot") { addCamera(shot: nil) }
                let shots = session.rows(inScene: id)
                if !shots.isEmpty {
                    Section("Shots") {
                        ForEach(shots) { row in
                            Button("\(row.number)  \(row.title)") { addCamera(shot: row.shot) }
                        }
                    }
                }
            }
            Menu("Cast") {
                let who = cast
                ForEach(who.scene, id: \.self) { name in Button(name) { addCast(name) } }
                if !who.film.isEmpty {
                    Menu("Others") { ForEach(who.film, id: \.self) { name in Button(name) { addCast(name) } } }
                }
                Button("Cast \(els.filter { $0.kind == "cast" }.count + 1)") { addCast(nil) }
            }
            Button("Words") { addWords() }
            Button("Library…") { library = true }
            Button("Picture…") { pickingPicture = true }
            Menu("Draw") {
                Section { ForEach(DiagramDraw.set) { t in Button(t.title) { start(t) } } }
                Section { ForEach(DiagramDraw.lines) { t in Button(t.title) { start(t) } } }
            }
            let favs = favorites
            if !favs.isEmpty {
                Menu("Favorites") {
                    ForEach(favs, id: \.slot) { f in Button("\(f.slot + 1)  \(f.name)") { dropFavorite(f.slot) } }
                }
            }
        } label: { circle("plus") }
        .accessibilityLabel("Add")
        .accessibilityIdentifier("diagram.add")
    }

    private func barButton(_ symbol: String, _ label: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) { circle(symbol) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }

    private func circle(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color(.label))
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .glassCapsule()
    }

    /// **A picture on the plan** (`diagramimage`): a photo, a fifth of the
    /// screen wide, in the middle of what is shown; picked.
    private func layPicture(_ data: Data) {
        guard let engine, let image = UIImage(data: data),
              let jpeg = image.jpegData(compressionQuality: 0.9) else { return }
        let p = middle
        let pixels = (Int(image.size.width * image.scale), Int(image.size.height * image.scale))
        let wide = max(Double(size.width / max(drawnScale, 1)) * 0.4, 1)
        let line = ["diagramimage", id, String(pixels.0), String(pixels.1), "jpg", jpeg.base64EncodedString(),
                    "photo.jpg", String(Double(p.x)), String(Double(p.y)), String(wide), "photo"]
        struct Made: Decodable { var made: [String] }
        let reply = engine.raw(line)
        if let problem = Session.refusal(in: reply) { say(problem); return }
        if let made = try? JSONDecoder().decode(Made.self, from: reply) { selection = made.made }
        session.refresh()
        read()
    }

    /// **A Name is what he types** (diagram labels, 2026-10-15): one lamp's
    /// alone, or — several picked — each of them given the one Name.
    private func name(_ text: String) {
        if pickedIsWords {
            edit(["op": "update", "ids": selection, "set": ["text": text]])
            return
        }
        // Every kind takes its own Name (2026-10-17): a frame's is its Name,
        // not its Note.
        let ops: [[String: Any]] = selection.map { ["op": "name_piece", "id": $0, "name": text.trimmingCharacters(in: .whitespaces)] }
        guard !ops.isEmpty else { return }
        edit(ops.count == 1 ? ops[0] : ["op": "batch", "ops": ops])
    }

    // ---- drawing by finger -------------------------------------------------------

    private func start(_ t: DiagramDraw) {
        selection = []
        wallId = nil
        wallStart = nil
        sketch = []
        tool = t
        read()
    }

    private func stopDrawing() {
        tool = nil
        wallId = nil
        wallStart = nil
        sketch = []
    }

    /// A point on the plan, caught by the grid, a wall's corner or a face
    /// the way the Mac's pointer is, when Snap is on.
    private func snapped(_ screen: CGPoint) -> CGPoint {
        let p = onPlan(screen)
        guard snaps, let engine else { return p }
        struct S: Decodable { var x: Double; var y: Double }
        var args = ["diagramsnap", id, String(Double(p.x)), String(Double(p.y)), String(Double(16 / max(drawnScale, 1)))]
        if let wallId { args.append("skip=\(wallId)") }
        guard let s = try? JSONDecoder().decode(S.self, from: engine.raw(args)) else { return p }
        return CGPoint(x: s.x, y: s.y)
    }

    private func toolTap(_ t: DiagramDraw, _ at: CGPoint) {
        switch t {
        case .wall:
            let p = snapped(at)
            if let wallId {
                // Back on the first corner: the room closes.
                if let start = wallCorner(wallId, 0), hypot(start.x - p.x, start.y - p.y) * drawnScale < 22 {
                    edit(["op": "update", "ids": [wallId], "set": ["closed": true]])
                    stopDrawing()
                    return
                }
                edit(["op": "wall_extend", "id": wallId, "end": "end", "x": p.x, "y": p.y])
                selection = [wallId]
            } else if let a = wallStart {
                guard hypot(p.x - a.x, p.y - a.y) > 0.05 else { return }
                let made = edit(["op": "add", "els": [["kind": "wall", "x": a.x, "y": a.y, "x2": p.x, "y2": p.y]]], pick: true)
                wallId = made.first
                wallStart = nil
            } else {
                wallStart = p
            }
        case .door, .sliding, .window, .opening:
            let p = onPlan(at)
            var e: [String: Any] = ["kind": t == .sliding ? "door" : t.rawValue, "x": p.x, "y": p.y]
            if t == .sliding { e["slide"] = true; e["swing"] = 0 }
            struct W: Decodable { var x: Double?; var y: Double?; var rot: Double?; var thick: Double? }
            if let engine,
               let w = try? JSONDecoder().decode(W.self, from: engine.raw("diagramwall", id, String(Double(p.x)), String(Double(p.y)), "0.6")),
               let x = w.x, let y = w.y, let rot = w.rot, let thick = w.thick {
                e["x"] = x; e["y"] = y; e["rot"] = rot; e["h"] = thick
            }
            edit(["op": "add", "els": [e]], pick: true)
            stopDrawing()
        default:
            break
        }
    }

    /// A wall's corner, off the plan's own JSON.
    private func wallCorner(_ wall: String, _ i: Int) -> CGPoint? {
        guard let p = DiagramPiece.read(id, engine: engine).els.first(where: { $0.id == wall }) else { return nil }
        if let pts = p.raw["points"] as? [[NSNumber]], i < pts.count, pts[i].count >= 2 {
            return CGPoint(x: pts[i][0].doubleValue, y: pts[i][1].doubleValue)
        }
        return i == 0 ? CGPoint(x: p.n("x"), y: p.n("y")) : nil
    }

    private func finishSketch(_ t: DiagramDraw, from: CGPoint, to: CGPoint) {
        defer { sketch = [] }
        let a = snapped(from), b = snapped(to)
        switch t {
        case .room:
            let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
            guard r.width > 0.3, r.height > 0.3 else { return }
            let pts = [[r.minX, r.minY], [r.maxX, r.minY], [r.maxX, r.maxY], [r.minX, r.maxY]].map { $0.map(Double.init) }
            edit(["op": "add", "els": [["kind": "wall", "points": pts, "closed": true]]], pick: true)
        case .shape:
            let w = max(abs(b.x - a.x), 0.2), h = max(abs(b.y - a.y), 0.2)
            edit(["op": "add", "els": [["kind": "shape", "sym": "rect", "x": (a.x + b.x) / 2, "y": (a.y + b.y) / 2, "w": w, "h": h]]], pick: true)
        case .arrow, .connector, .ruler:
            guard hypot(b.x - a.x, b.y - a.y) > 0.1 else { return }
            let kind = t == .ruler ? "measure" : "arrow"
            var e: [String: Any] = ["kind": kind, "x": a.x, "y": a.y, "x2": b.x, "y2": b.y]
            if kind == "arrow" {
                e["head"] = t == .connector ? "none" : "end"
                if t == .connector { e["weight"] = 0.8 }
                // From or onto a piece: that end is pinned to it.
                if let on = hit(from) { e["start_on"] = on }
                if let on = hit(to) { e["end_on"] = on }
            }
            edit(["op": "add", "els": [e]], pick: true)
        case .pen:
            var pts: [CGPoint] = []
            for p in sketch where pts.last.map({ hypot($0.x - p.x, $0.y - p.y) > 8 }) ?? true { pts.append(p) }
            guard pts.count >= 2 else { return }
            let onPlanPts = pts.map(onPlan).map { [Double($0.x), Double($0.y)] }
            edit(["op": "add", "els": [["kind": "stroke", "points": onPlanPts,
                                         "handles": onPlanPts.map { _ in [0.0, 0.0, 0.0, 0.0] }, "fill": false]]])
        default:
            break
        }
        if t != .pen { stopDrawing() }
    }

    private func toolBar(_ t: DiagramDraw) -> some View {
        HStack(spacing: 8) {
            Text("\(t.title) · \(wallId != nil ? "Tap the next corner" : t.hint)")
                .font(.system(size: Kit.Size.body, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(height: 44)
                .glassCapsule(interactive: false)
                .accessibilityIdentifier("diagram.tool")
            if t == .wall, let wallId {
                Button {
                    edit(["op": "update", "ids": [wallId], "set": ["closed": true]])
                    stopDrawing()
                } label: { circle("square.on.square.dashed") }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            Button { stopDrawing(); read() } label: { circle("checkmark") }
                .buttonStyle(.plain)
                .accessibilityLabel("Done")
        }
    }

    // ---- the plan's menu --------------------------------------------------------

    private var planMenu: some View {
        Menu {
            Section {
                Button("New Plan") {
                    _ = engine?.raw("diagramplanadd", "Plan")
                    session.refresh(); changed(); say("Plan added")
                }
                Button("Duplicate as New Plan") {
                    _ = engine?.raw("diagramplanadd", "\(title) Copy", id)
                    session.refresh(); changed(); say("Plan added")
                }
                if isPlan {
                    Button("Rename Plan…") { newName = title; renaming = true }
                    Button("Delete Plan…", role: .destructive) { deletingPlan = true }
                }
            }
            Menu("Copy From") {
                ForEach(sources, id: \.id) { s in
                    Menu(s.name) {
                        Button("Add on Top") { copy(from: s.id, mode: "add") }
                        Button("Replace This Plan", role: .destructive) { copy(from: s.id, mode: "replace") }
                    }
                }
            }
            if !scans.isEmpty {
                Menu("Room from Scan") {
                    ForEach(scans, id: \.label) { s in
                        Button(s.label) {
                            guard let engine else { return }
                            struct R: Decodable { var made: Int }
                            let data = engine.raw("diagramroom", id, s.place, s.path)
                            let n = (try? JSONDecoder().decode(R.self, from: data))?.made ?? 0
                            if n > 0 { session.refresh(); anchor = nil; read() } else { say(Session.refusal(in: data) ?? "No room in that scan") }
                        }
                    }
                }
            }
            Section {
                Button("Layers…") { layers = true }
                Button("Plan Settings…") { planSettings = true }
            }
            Button("Export PDF") { exportPDF() }
            Button("Fit") { withAnimation { zoom = 1; settledZoom = 1; pan = .zero; settledPan = .zero }; read() }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    /// Every other scene with a plan, and every loose plan.
    private var sources: [(id: String, name: String)] {
        guard let engine else { return [] }
        struct S: Decodable { var scenes: [String] }
        struct P: Decodable { var plans: [Plan] }
        struct Plan: Decodable { var id: String; var name: String }
        let order = session.view?.scenes ?? []
        let sceneIds = (try? JSONDecoder().decode(S.self, from: engine.raw("diagramscenes")))?.scenes ?? []
        let scenes: [(id: String, name: String)] = sceneIds.compactMap { sid in
            guard sid != id, let s = order.first(where: { $0.id == sid }) else { return nil }
            return (sid, "\(s.number) \(session.isCommercial && !s.title.isEmpty ? s.title : s.heading)")
        }
        let plans = ((try? JSONDecoder().decode(P.self, from: engine.raw("diagramplans")))?.plans ?? [])
            .filter { $0.id != id }.map { (id: $0.id, name: $0.name) }
        return scenes + plans
    }

    private func copy(from: String, mode: String) {
        guard let engine else { return }
        struct R: Decodable { var copied: Int }
        let data = engine.raw("diagramcopy", id, from, "mode=\(mode)")
        let n = (try? JSONDecoder().decode(R.self, from: data))?.copied ?? 0
        session.refresh()
        anchor = nil
        read()
        say(n == 0 ? (Session.refusal(in: data) ?? "Nothing copied") : "\(n) piece\(n == 1 ? "" : "s") copied")
    }

    /// The scans of the places this scene is shot at; on a loose plan, all.
    private var scans: [(label: String, place: String, path: String)] {
        let scene = session.scene(id)
        let places = scene.map { s in session.locations.filter { s.locations.contains($0.id) } } ?? session.locations
        return places.flatMap { place in
            session.rooms(of: place).compactMap { room -> (String, String, String)? in
                guard let json = room.json, FileManager.default.fileExists(atPath: json.path) else { return nil }
                // A room named for where it was scanned already says its place.
                let label = room.name.hasPrefix("RoomScan_") ? "\(place.name) — \(room.name)" : room.name
                return (label, place.id, json.path)
            }
        }
    }

    /// **Export** (the Mac's Export…): the printed sheet, drawn as the
    /// viewer draws it, into a PDF to send.
    private func exportPDF() {
        guard let sheet = DiagramSheet.read(id, engine: engine) else { say("Nothing to export"); return }
        let page = CGSize(width: sheet.w, height: sheet.h)
        let view = DiagramCanvas(plan: sheet.plan, engine: engine, sheet: sheet)
            .frame(width: page.width, height: page.height)
        let renderer = ImageRenderer(content: view)
        // His naming (2026-10-15): project, document, what it covers, date.
        let project = FileNames.plain(session.view?.project.shownTitle ?? session.entry.name)
        let scene = session.scene(id).map { FileNames.sceneWords([$0.number]) } ?? FileNames.plain(title)
        let name = [project, "diagram", scene, FileNames.compactDate(Date())].filter { !$0.isEmpty }
            .joined(separator: "-") + ".pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }
        exported = MadeFile(url: url)
    }
}

/// A file made to be sent, as a sheet's item.
struct MadeFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// The share sheet, for a file this screen made.
struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// **The library** (the Mac's set pieces, grip and lights): search, then
/// tap one to put it down in the middle of the screen.
struct DiagramLibrarySheet: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    let pick: (Symbol) -> Void

    struct Symbol: Decodable, Identifiable, Hashable {
        var id: String
        var name: String
        var group: String
        var light: Bool
        var w: Double
        var h: Double
        var beam: Double
        var reach: Double
        var kelvin: Double
        var lib: String?
        var maker: String?
        var aka: String?
    }

    @State private var all: [Symbol] = []
    @State private var query = ""

    private var shown: [(group: String, items: [Symbol])] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let list = q.isEmpty ? all : all.filter {
            "\($0.name) \($0.group) \($0.maker ?? "") \($0.aka ?? "")".lowercased().contains(q)
        }
        var order: [String] = []
        var by: [String: [Symbol]] = [:]
        for s in list {
            if by[s.group] == nil { order.append(s.group) }
            by[s.group, default: []].append(s)
        }
        return order.map { ($0, by[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(shown, id: \.group) { g in
                    Section(g.group) {
                        ForEach(g.items) { s in
                            Button {
                                pick(s)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(s.name).foregroundStyle(Color(.label))
                                    Spacer()
                                    if let maker = s.maker, !maker.isEmpty {
                                        Text(maker).font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search")
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .task {
            struct R: Decodable { var symbols: [Symbol] }
            if let data = session.engine?.raw("diagramlibrary"),
               let r = try? JSONDecoder().decode(R.self, from: data) {
                all = r.symbols
            }
        }
    }
}
