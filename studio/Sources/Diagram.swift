import SwiftUI
import AppKit

// The Diagram mode: an overhead of the scene picked in the sidebar.
//
// His rulings: a diagram is a *mode* (2026-08-23) — the fifth pill in the top
// bar, with the same scene list down the side as Shot List and Schedule. Tools
// wear pictures, but none of the stock glyph icons (2026-09-26): every tool's
// picture is drawn here, most of them by the engine's own plan drawings, so a
// tool looks like the thing it puts down. A camera's colour is his, set by
// hand (2026-09-26).

struct DiagramMode: View {
    @ObservedObject var state: ShellState
    @StateObject private var model = DiagramModel()
    /// The Diagram's own keys (`DiagramKeys`), watched while it shows.
    @State private var keys: Any?
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        Group {
            if let sheet = state.diagramSheet {
                VStack(spacing: 0) {
                    if !state.diagramPresenting {
                        DiagramHeader(state: state, model: model, sheet: sheet,
                                      scene: state.diagramPlanLive == nil ? state.scene : nil)
                    }
                    ZStack {
                        DiagramCanvas(model: model)
                            // Dragged off the toolbar or out of the library.
                            .dropDestination(for: String.self) { items, at in
                                guard let what = items.first, what.hasPrefix(DiagramRail.dragPrefix),
                                      let canvas = model.canvas as? DiagramCanvasView else { return false }
                                canvas.drop(String(what.dropFirst(DiagramRail.dragPrefix.count)), at: at)
                                return true
                            }
                        if !state.diagramPresenting { overlays.environment(\.onGlass, true) }
                    }
                    .coordinateSpace(name: DiagramMode.space)
                    .onPreferenceChange(DiagramFavoriteSlots.self) { model.favoriteSlots = $0 }
                    .clipped()
                }
            } else {
                EmptyState(title: "No scenes yet") { EmptyView() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            model.state = state
            state.diagram = model
            model.open(scene: state.diagramOwner)
            DiagramChecks.apply(to: model)
            if keys == nil { keys = DiagramKeys.install(model) }
        }
        .onDisappear {
            if state.diagram === model { state.diagram = nil }
            DiagramKeys.remove(keys)
            keys = nil
            model.present(false)
        }
        .onChange(of: state.sceneId) { _, _ in model.open(scene: state.diagramOwner) }
        // The sidebar folds while he draws, and comes back with its button.
        .onChange(of: model.tool) { _, tool in
            if ![.select, .hand].contains(tool), !state.diagramFolded {
                withAnimation(.easeOut(duration: 0.18)) { state.diagramFolded = true }
            }
        }
        .onChange(of: state.diagramPlan) { _, _ in model.open(scene: state.diagramOwner); model.fitted = false }
        // Another of the scene's diagrams picked, made or deleted.
        .onChange(of: state.diagramOwner) { _, owner in
            if model.scene != owner { model.open(scene: owner); model.fitted = false }
        }
        .onChange(of: state.diagramShot) { _, shot in findShot(shot) }
        .onAppear { findShot(state.diagramShot) }
        // Anything that changed the film — an undo from the menu, another
        // device, a shot renamed in the table — may have changed the plan.
        .onReceive(state.$view) { _ in
            if model.preview == nil { model.reload() }
        }
    }

    /// Arriving from the shot list's Show on Diagram: pick that shot's camera,
    /// or say there is none on this plan.
    private func findShot(_ shot: String?) {
        guard let shot else { return }
        state.diagramShot = nil
        state.diagramPlan = nil
        model.open(scene: state.diagramOwner)
        if let cam = model.plan.els.first(where: { $0.kind == "camera" && $0.shot == shot }) {
            model.selection = [cam.id]
        } else {
            state.say("No camera for this shot yet")
        }
    }

    /// The right sidebar's width, and the air round every floating piece.
    static let rightWidth: CGFloat = 292
    static let margin: CGFloat = 10

    /// Where each tool's button is, so its library opens under it.
    @State private var spots: [String: CGRect] = [:]

    /// **Five zones** (design/24, approved 2026-09-28): the tools in one row
    /// centred on top, the picked piece's bar centred at the foot, zoom and
    /// north in the bottom-right corner, the scale in the bottom-left, and
    /// Details · Gear down the right. Layers and Shots are tabs of the app's
    /// own sidebar (`DiagramSidebar`). Everything centres itself in what the
    /// right sidebar leaves of the plan.
    @ViewBuilder private var overlays: some View {
        GeometryReader { g in
            let free = max(g.size.width - model.panelCover, 320)
            let m = DiagramMode.margin
            ZStack(alignment: .topLeading) {
                // 3 — the toolbar, and what the tool in hand offers under it
                // Drawing on a picture: the hand on it, and its own tools.
                if let photo = model.photoEditing {
                    PhotoEditor(model: model, id: photo)
                        .frame(width: g.size.width, height: g.size.height)
                }
                VStack(spacing: 8) {
                    if model.photoEditing != nil { PhotoToolbar(model: model).zIndex(1) }
                    else if !model.readOnly { DiagramToolbar(model: model, free: free).zIndex(1) }
                    if !model.showingFavorites, model.photoEditing == nil { DiagramToolOptions(model: model) }
                }
                .frame(width: free)
                .padding(.top, 12)
                // Its hover names over any panel opened under it.
                .zIndex(2)

                if model.photoEditing != nil {
                    // Nothing of the plan's tools while a picture is drawn on.
                } else if !model.readOnly, let id = model.swapping, let e = model.el(id) {
                    // Swap… from the right-click menu: the library, swapping
                    // that piece, under its own tool in the toolbar.
                    let own = model.library?.symbols.first { $0.id == e.sym }?.lib ?? (e.kind == "light" ? "light" : "set")
                    let spot = spots[own] ?? spots["light"] ?? .zero
                    let h = min(460, g.size.height - spot.maxY - 70)
                    let pw = DiagramLibraryPanel.width
                    DiagramLibraryPanel(model: model, height: h, swap: e) { model.swapping = nil }
                        .offset(x: min(max(spot.midX - pw / 2, 12), free - pw - 12), y: spot.maxY + 10)
                        .transition(.opacity)
                        .onChange(of: model.selection) { _, now in if now != [id] { model.swapping = nil } }
                } else if !model.readOnly, model.tool == .light {
                    let spot = spots["light"] ?? .zero
                    DiagramMarkPalette(model: model)
                        .fixedSize()
                        .offset(x: min(max(spot.midX - 145, 12), free - 302), y: spot.maxY + 10)
                        .transition(.opacity)
                } else if !model.readOnly, model.tool.usesLibrary || model.tool == .picture {
                    let spot = spots[model.tool.rawValue] ?? .zero
                    let h = min(460, g.size.height - spot.maxY - 70)
                    let pw: CGFloat = model.tool == .picture ? 300 : DiagramLibraryPanel.width
                    Group {
                        if model.tool == .picture { DiagramPicturesPanel(model: model, height: h) }
                        else { DiagramLibraryPanel(model: model, height: h) }
                    }
                    .offset(x: min(max(spot.midX - pw / 2, 12), free - pw - 12), y: spot.maxY + 10)
                    .transition(.opacity)
                }

                if !model.readOnly, model.showingFavorites, let fav = spots["favorites"] {
                    DiagramFavoritesStrip(model: model)
                        .fixedSize()
                        .offset(x: min(max(fav.maxX - DiagramFavoritesStrip.width, 12), free - DiagramFavoritesStrip.width - 12),
                                y: fav.maxY + 10)
                        .transition(.opacity)
                }

                // 4 — one bar at the foot: the beat, and what is picked
                if model.photoEditing != nil {
                    PhotoFootBar(model: model)
                        .frame(width: free, height: g.size.height - 12, alignment: .bottom)
                } else {
                    DiagramFootBar(state: state, model: model)
                        .frame(width: free, height: g.size.height - 12, alignment: .bottom)
                }

                // 5 — zoom bottom right. The scale is the sheet's, and only
                // when View › Sheet › Scale Bar asks (his call G).
                HStack(alignment: .bottom) {
                    Spacer()
                    DiagramZoom(model: model)
                }
                .padding(.horizontal, 14)
                .frame(width: free, height: g.size.height - 12, alignment: .bottom)

                // 6 — Details · Gear, down the right
                if model.rightTab != nil {
                    DiagramRightPanel(state: state, model: model)
                        .frame(width: DiagramMode.rightWidth, height: max(g.size.height - 2 * m, 100))
                        .offset(x: g.size.width - DiagramMode.rightWidth - m, y: m)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }

                if model.showingSun {
                    DiagramSunPanel(model: model)
                        .fixedSize()
                        .frame(width: free - 14, height: g.size.height - 56, alignment: .bottomTrailing)
                }
                if model.showingColours {
                    DiagramColoursPanel(model: model)
                        .fixedSize()
                        .frame(width: free - 14, height: g.size.height - 56, alignment: .bottomTrailing)
                }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
            .animation(.easeOut(duration: 0.18), value: model.rightTab)
        }
        .onPreferenceChange(DiagramToolSpots.self) { spots = $0; model.toolSpots = $0 }

        if model.plan.els.isEmpty, model.pending.isEmpty, model.tool == .select, !model.readOnly {
            DiagramEmpty(state: state, model: model)
        }

        // What an undo or redo just did — "Undo Move" — over the foot bar.
        GeometryReader { g in
            if let toast = model.toast {
                Text(toast)
                    .sans(13)
                    .foregroundStyle(Brand.onImage)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.78)))
                    .frame(width: max(g.size.width - model.panelCover, 320), height: g.size.height - 118, alignment: .bottom)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.15), value: model.toast)
    }
}

// MARK: - the header

struct DiagramHeader: View {
    @ObservedObject var state: ShellState
    @ObservedObject var model: DiagramModel
    /// What this plan is: a scene, or a loose plan (then `scene` is nil).
    let sheet: DiagramSheet
    let scene: ViewModel.Scene?
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            top
            // The scene's diagrams (`DiagramScenes`); a loose plan has one.
            if scene != nil, !state.sceneDiagramsNow.isEmpty {
                DiagramTabStrip(state: state, readOnly: model.readOnly)
                    .padding(.horizontal, 14)
            }
        }
        .background(Brand.surface(dark))
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.rule(dark)).frame(height: 1) }
    }

    private var top: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    if let scene {
                        Text(scene.number).sans(Brand.Size.large, weight: .bold)
                        Text(headingLine(scene)).sans(Brand.Size.large, weight: .bold).lineLimit(1)
                        let shots = state.rows(of: scene.id).count
                        Text(shots == 1 ? "1 shot" : "\(shots) shots")
                            .sans(Brand.Size.small, weight: .medium)
                            .foregroundStyle(Brand.ink3(dark))
                    } else if let plan = state.diagramPlanLive {
                        Text(plan.name).sans(Brand.Size.large, weight: .bold).lineLimit(1)
                        Menu {
                            Button("Rename…") { DiagramPlanActions.rename(state, plan) }
                            Button("Duplicate") { DiagramPlanActions.add(state, from: plan.id, name: "\(plan.name) Copy") }
                            Divider()
                            Button("Delete…") { DiagramPlanActions.delete(state, plan) }
                        } label: {
                            Text("Plan")
                                .sans(Brand.Size.small, weight: .medium)
                                .foregroundStyle(Brand.ink2(dark))
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .fixedSize()
                        .padding(.horizontal, 7).padding(.vertical, 1)
                        .background(Capsule().fill(Brand.selectionQuiet(dark)))
                        .disabled(model.readOnly)
                    }
                }
                HStack(spacing: 14) {
                    if let place = location {
                        HStack(spacing: 5) {
                            Circle().fill(Brand.hex("3F9B6E")).frame(width: 6, height: 6)
                            Text(place.name).sans(Brand.Size.small, weight: .semibold)
                        }
                    }
                    if let day = scene?.day, !day.isEmpty { Text(day).sans(Brand.Size.small) }
                    if !model.plan.roomFrom.isEmpty { Text("Room from Scan").sans(Brand.Size.small) }
                    // One diagram: a quiet way to a second (`DiagramScenes`);
                    // with several, the tabs below carry the +.
                    if scene != nil, state.sceneDiagramsNow.isEmpty, !model.readOnly {
                        Button { DiagramSceneActions.add(state) } label: {
                            Text("+ New Diagram").sans(Brand.Size.small, weight: .medium)
                                .foregroundStyle(Brand.ink3(dark)).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("diagram.newDiagram")
                    }
                }
                .foregroundStyle(Brand.ink2(dark))
            }
            Spacer()
            // 2 — how the plan is drawn, Grid and Snap among it, all in View
            // (Back to Paper, design/32 item 9).
            DiagramViewMenu(model: model)
            detailsToggle
            if !model.readOnly {
                roomMenu
                copyMenu
            }
            Button("Export…") { Exporting.exportDiagram(sheet.id, state: state) }
                .buttonStyle(.capsule)
                // Export takes every diagram of the scene, so any drawn counts.
                .disabled(model.plan.els.isEmpty && (scene?.diagram ?? 0) == 0)
        }
        .padding(.horizontal, 20).padding(.top, 11).padding(.bottom, scene != nil && !state.sceneDiagramsNow.isEmpty ? 2 : 11)
    }

    /// **Details**, always in sight (his note, 2026-10-17: "the detail
    /// panel needs to be easier to pull up"): lit while the panel is open.
    private var detailsToggle: some View {
        Button { model.toggleDetails() } label: {
            Text("Details").sans(13, weight: model.detailsOpen ? .semibold : .regular).foregroundStyle(Brand.ink(dark))
                .padding(.horizontal, Brand.barPadding).frame(height: Brand.barHeight)
                .barPill(dark, on: model.detailsOpen)
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .fixedSize()
        .help("Details  ⌥⌘I")
        .accessibilityIdentifier("diagram.details")
        .accessibilityAddTraits(model.detailsOpen ? .isSelected : [])
    }

    private func headingLine(_ scene: ViewModel.Scene) -> String {
        let h = scene.heading.trimmingCharacters(in: .whitespaces)
        if !h.isEmpty { return h }
        return scene.title.isEmpty ? "Scene \(scene.number)" : scene.title
    }

    private var location: ViewModel.Location? {
        guard let id = scene?.locations.first else { return nil }
        return state.view?.locations.first { $0.id == id }
    }

    /// Every scan of every place this scene is shot at — on a loose plan,
    /// every scan in the film (his ruling: any 3D scan can go on one).
    private var scans: [(name: String, place: ViewModel.Location, url: URL)] {
        guard let folder = state.engine?.folder else { return [] }
        let places = scene.map { s in s.locations.compactMap { id in state.view?.locations.first { $0.id == id } } }
            ?? (state.view?.locations ?? [])
        return places.flatMap { place in
            Scout.scans(of: place, in: folder).compactMap { item in
                item.measurements.map { (item.name, place, $0) }
            }
        }
    }

    @ViewBuilder private var roomMenu: some View {
        let found = scans
        if !found.isEmpty {
            Menu {
                ForEach(Array(found.enumerated()), id: \.offset) { _, s in
                    // A room named for where it was scanned already says its
                    // place; one still wearing the phone's name does not.
                    Button(found.count == 1 ? "Use \(s.place.name)"
                           : s.name.hasPrefix("RoomScan_") ? "\(s.place.name) — \(s.name)" : s.name) {
                        guard let engine = state.engine, let id = model.scene else { return }
                        if engine.diagramRoom(scene: id, location: s.place.id, path: s.url.path) {
                            state.replace(engine.view())
                            model.reload()
                            model.fitted = false
                        }
                    }
                }
            } label: {
                Text(model.plan.roomFrom.isEmpty ? "Room from Scan" : "Room from Scan")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .buttonStyle(.capsule)
        }
    }

    /// **Copy** — Copy From another scene's plan, Copy To others
    /// (`DiagramCopy`).
    @ViewBuilder private var copyMenu: some View {
        let all = DiagramCopy.targets(model)
        let from = all.filter { $0.count > 0 }
        Menu {
            Menu("Copy From") {
                ForEach(from) { t in Button(t.label) { DiagramCopy.from(t, into: model) } }
            }
            .disabled(from.isEmpty)
            Button("Copy To…") { DiagramCopy.to(model: model, ids: []) }
                .disabled(model.plan.els.isEmpty || all.isEmpty)
            Button("Copy to New Plan") {
                DiagramPlanActions.add(state, from: model.scene, name: scene.map { "Scene \($0.number)" } ?? "\(sheet.heading) Copy")
            }
            .disabled(model.plan.els.isEmpty)
            Divider()
            // The sheet's legend counted: each kind's name times its Count.
            Button("Gear List") { DiagramGear.copy(model) }
                .disabled(DiagramGear.lines(model).isEmpty)
        } label: {
            Text("Copy").sans(13).foregroundStyle(Brand.ink(dark))
                .padding(.horizontal, Brand.barPadding).frame(height: Brand.barHeight)
                .barPill(dark, on: false)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

extension DiagramModel {
    static func scenesWithPlans(_ engine: Engine) -> [String] {
        struct Reply: Decodable { var scenes: [String] }
        return (try? JSONDecoder().decode(Reply.self, from: engine.call("diagramscenes", "")))?.scenes ?? []
    }

    /// Leave the plan for the shot list, at the shot this camera is.
    func showInShotList(_ shot: String) {
        guard let state else { return }
        guard let row = state.view?.allRows.first(where: { $0.shot == shot }) else { return }
        state.sideTab = .scenes
        if let scene = row.sceneId { state.sceneId = scene }
        state.cursorShot = row.id
    }
}

// MARK: - pictures of things

/// One drawing from the engine, cached by what it is.
enum DiagramGlyphs {
    private static var held: [String: [DiagramShape]] = [:]

    static func shapes(kind: String, sym: String, w: Double, h: Double, engine: Engine?) -> [DiagramShape] {
        let key = "\(kind)|\(sym)|\(w)|\(h)"
        if let got = held[key] { return got }
        guard let engine else { return [] }
        struct Reply: Decodable { var shapes: [DiagramShape] }
        let data = engine.call("diagramglyph", kind, sym, String(w), String(h))
        let shapes = (try? JSONDecoder().decode(Reply.self, from: data))?.shapes ?? []
        held[key] = shapes
        return shapes
    }
}

/// A drawing from the engine, fitted into a box — a library tile, a tool.
struct DiagramGlyph: View {
    let kind: String
    let sym: String
    let w: Double
    let h: Double
    var rot: Double = 0
    let engine: Engine?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { context, size in
            let shapes = DiagramGlyphs.shapes(kind: kind, sym: sym, w: w, h: h, engine: engine)
            guard !shapes.isEmpty else { return }
            // Fit the footprint, turned, with a little room.
            let r = rot * .pi / 180
            let bw = abs(w * cos(r)) + abs(h * sin(r)), bh = abs(w * sin(r)) + abs(h * cos(r))
            let k = min(size.width / max(bw, 0.01), size.height / max(bh, 0.01)) * 0.8
            // Drawn on paper, the way the plan is.
            context.withCGContext { cg in
                let T = CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
                    .scaledBy(x: k, y: k)
                    .rotated(by: r)
                var painter = DiagramPainter(dark: false, scale: k, engine: engine)
                for s in shapes where s.k == "path" || s.k == "img" { painter.paint(s, cg, T) }
            }
        }
    }
}

/// A tool's picture: a small drawing of the thing it puts down, seen from
/// above the way the plan sees it, in one ink. Never a stock glyph.
struct DiagramToolIcon: View {
    let tool: DiagramTool
    let engine: Engine?
    let on: Bool
    /// Another ink — a Layers row's, white on the picked blue.
    var ink: Color? = nil
    @Environment(\.colorScheme) private var scheme

    /// **Lamp, Frame and Camera wear their own ink** (Back to Paper, Batch
    /// 2), so the toolbar doubles as a key: red what we bring, blue the
    /// camera.
    private func own(_ dark: Bool) -> Color? {
        guard self.ink == nil else { return nil }
        switch tool {
        case .light, .frame: return Color(nsColor: DiagramInk.color("added", dark: dark)!)
        case .camera: return Color(nsColor: DiagramInk.color("camink", dark: dark)!)
        default: return nil
        }
    }

    var body: some View {
        let dark = scheme == .dark
        let ink = own(dark) ?? self.ink ?? (on ? Brand.surface(dark) : Brand.ink(dark))
        Canvas { c, size in
            let s = min(size.width, size.height)
            let o = CGPoint(x: (size.width - s) / 2, y: (size.height - s) / 2)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(origin: p(x, y), size: CGSize(width: w * s, height: h * s))
            }
            var path = Path()
            var fill = Path()
            var width: CGFloat = 1.4
            switch tool {
            case .select:
                fill.move(to: p(0.28, 0.12)); fill.addLine(to: p(0.28, 0.8)); fill.addLine(to: p(0.44, 0.64))
                fill.addLine(to: p(0.56, 0.9)); fill.addLine(to: p(0.66, 0.85)); fill.addLine(to: p(0.54, 0.6))
                fill.addLine(to: p(0.76, 0.58)); fill.closeSubpath()
            case .hand:
                for (a, b) in [((0.5, 0.1), (0.5, 0.9)), ((0.1, 0.5), (0.9, 0.5))] {
                    path.move(to: p(a.0, a.1)); path.addLine(to: p(b.0, b.1))
                }
                for (tip, l, rr) in [((0.5, 0.1), (0.38, 0.22), (0.62, 0.22)), ((0.5, 0.9), (0.38, 0.78), (0.62, 0.78)),
                                     ((0.1, 0.5), (0.22, 0.38), (0.22, 0.62)), ((0.9, 0.5), (0.78, 0.38), (0.78, 0.62))] {
                    path.move(to: p(l.0, l.1)); path.addLine(to: p(tip.0, tip.1)); path.addLine(to: p(rr.0, rr.1))
                }
            case .camera:
                // Body, and the matte box opening toward what it sees: an
                // outline, the plot's camera.
                path.addRoundedRect(in: r(0.12, 0.3, 0.5, 0.4), cornerSize: CGSize(width: s * 0.06, height: s * 0.06))
                path.move(to: p(0.62, 0.42)); path.addLine(to: p(0.88, 0.3)); path.addLine(to: p(0.88, 0.7))
                path.addLine(to: p(0.62, 0.58))
                width = 1.6
            case .cast:
                // A person: the head, and the shoulders under it.
                fill.addEllipse(in: r(0.34, 0.1, 0.32, 0.32))
                fill.move(to: p(0.14, 0.9)); fill.addLine(to: p(0.14, 0.76))
                fill.addQuadCurve(to: p(0.5, 0.48), control: p(0.14, 0.48))
                fill.addQuadCurve(to: p(0.86, 0.76), control: p(0.86, 0.48))
                fill.addLine(to: p(0.86, 0.9)); fill.closeSubpath()
            case .light:
                // A lamp as the plot marks one: a chevron.
                path.move(to: p(0.32, 0.2)); path.addLine(to: p(0.7, 0.5)); path.addLine(to: p(0.32, 0.8))
                width = 2.4
            case .grip:
                // A C-stand: the riser in three sections, the turtle base
                // with its front legs nesting at two heights, and the gobo
                // arm out through the grip head.
                fill.addRect(r(0.28, 0.22, 0.04, 0.3))
                fill.addRect(r(0.27, 0.5, 0.06, 0.22))
                fill.addRect(r(0.26, 0.7, 0.08, 0.22))
                path.move(to: p(0.3, 0.58)); path.addLine(to: p(0.04, 0.92))
                for h in [0.46, 0.72] as [CGFloat] {
                    path.move(to: p(0.3, h)); path.addLine(to: p(0.3 + (0.92 - h) * 0.7, 0.92))
                }
                path.move(to: p(0.14, 0.256)); path.addLine(to: p(0.92, 0.08))
                fill.addEllipse(in: r(0.215, 0.135, 0.17, 0.17))
                fill.addEllipse(in: r(0.86, 0.02, 0.12, 0.12))
                width = 1.7
            case .frame:
                // A frame as the plot draws one from above: a double line.
                path.move(to: p(0.14, 0.4)); path.addLine(to: p(0.86, 0.4))
                path.move(to: p(0.14, 0.6)); path.addLine(to: p(0.86, 0.6))
                width = 1.6
            case .set:
                // A sofa, from the front: its back, its arms, its seat.
                fill.addRoundedRect(in: r(0.22, 0.22, 0.56, 0.3), cornerSize: CGSize(width: s * 0.06, height: s * 0.06))
                fill.addRoundedRect(in: r(0.08, 0.4, 0.17, 0.36), cornerSize: CGSize(width: s * 0.06, height: s * 0.06))
                fill.addRoundedRect(in: r(0.75, 0.4, 0.17, 0.36), cornerSize: CGSize(width: s * 0.06, height: s * 0.06))
                fill.addRect(r(0.25, 0.57, 0.5, 0.19))
                path.move(to: p(0.16, 0.76)); path.addLine(to: p(0.16, 0.86))
                path.move(to: p(0.84, 0.76)); path.addLine(to: p(0.84, 0.86))
                width = 1.8
            case .wall:
                width = 3.4
                path.move(to: p(0.16, 0.8)); path.addLine(to: p(0.16, 0.2)); path.addLine(to: p(0.84, 0.2))
            case .door:
                width = 3.4
                path.move(to: p(0.08, 0.78)); path.addLine(to: p(0.28, 0.78))
                path.move(to: p(0.82, 0.78)); path.addLine(to: p(0.92, 0.78))
                var leaf = Path()
                leaf.move(to: p(0.8, 0.78)); leaf.addLine(to: p(0.8, 0.24))
                leaf.move(to: p(0.3, 0.78))
                leaf.addArc(center: p(0.8, 0.78), radius: s * 0.5, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
                c.stroke(leaf, with: .color(ink), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [2.5, 2]))
            case .sliding:
                // A wall broken for a track: the panel across the gap, its
                // far half in the dashed place it slides to.
                width = 3.4
                path.move(to: p(0.06, 0.62)); path.addLine(to: p(0.2, 0.62))
                path.move(to: p(0.8, 0.62)); path.addLine(to: p(0.94, 0.62))
                var track = Path()
                track.move(to: p(0.2, 0.4)); track.addLine(to: p(0.8, 0.4))
                c.stroke(track, with: .color(ink), style: StrokeStyle(lineWidth: 1.1, lineCap: .round, dash: [2.5, 2]))
                fill.addRect(r(0.2, 0.52, 0.42, 0.2))
            case .opening:
                width = 3.4
                path.move(to: p(0.06, 0.5)); path.addLine(to: p(0.24, 0.5))
                path.move(to: p(0.76, 0.5)); path.addLine(to: p(0.94, 0.5))
                var gap = Path()
                gap.move(to: p(0.24, 0.5)); gap.addLine(to: p(0.76, 0.5))
                c.stroke(gap, with: .color(ink), style: StrokeStyle(lineWidth: 1.1, lineCap: .round, dash: [2.5, 2]))
            case .window:
                width = 3.4
                path.move(to: p(0.08, 0.5)); path.addLine(to: p(0.22, 0.5))
                path.move(to: p(0.78, 0.5)); path.addLine(to: p(0.92, 0.5))
                var glass = Path()
                glass.addRect(r(0.22, 0.42, 0.56, 0.16))
                glass.move(to: p(0.22, 0.5)); glass.addLine(to: p(0.78, 0.5))
                c.stroke(glass, with: .color(ink), style: StrokeStyle(lineWidth: 1.1))
            case .track:
                path.move(to: p(0.1, 0.38)); path.addLine(to: p(0.9, 0.38))
                path.move(to: p(0.1, 0.62)); path.addLine(to: p(0.9, 0.62))
                for x in stride(from: 0.18, through: 0.84, by: 0.13) {
                    path.move(to: p(x, 0.3)); path.addLine(to: p(x, 0.7))
                }
                width = 1.1
            case .road:
                path.move(to: p(0.28, 0.1)); path.addLine(to: p(0.28, 0.9))
                path.move(to: p(0.72, 0.1)); path.addLine(to: p(0.72, 0.9))
                for y in [0.14, 0.42, 0.7] { path.move(to: p(0.5, y)); path.addLine(to: p(0.5, y + 0.16)) }
            case .text:
                // Words: "Aa".
                c.draw(Text("Aa").font(.system(size: s * 0.66, weight: .semibold)).foregroundColor(ink),
                       at: CGPoint(x: o.x + s * 0.5, y: o.y + s * 0.52))
            case .arrow:
                width = 1.8
                path.move(to: p(0.15, 0.82)); path.addLine(to: p(0.74, 0.26))
                fill.move(to: p(0.86, 0.14)); fill.addLine(to: p(0.56, 0.24)); fill.addLine(to: p(0.76, 0.44)); fill.closeSubpath()
            case .connector:
                // Two pieces, joined.
                width = 1.5
                path.addRoundedRect(in: r(0.08, 0.14, 0.3, 0.26), cornerSize: CGSize(width: s * 0.05, height: s * 0.05))
                path.addEllipse(in: r(0.62, 0.6, 0.3, 0.3))
                path.move(to: p(0.38, 0.38)); path.addLine(to: p(0.66, 0.65))
            case .measure:
                path.move(to: p(0.12, 0.5)); path.addLine(to: p(0.88, 0.5))
                for x in [0.12, 0.88] { path.move(to: p(x, 0.34)); path.addLine(to: p(x, 0.66)) }
                for x in [0.31, 0.5, 0.69] { path.move(to: p(x, 0.5)); path.addLine(to: p(x, 0.4)) }
            case .shape:
                path.addRect(r(0.12, 0.3, 0.44, 0.44))
                path.addEllipse(in: r(0.42, 0.14, 0.44, 0.44))
            case .pen:
                width = 1.8
                path.move(to: p(0.12, 0.7))
                path.addCurve(to: p(0.5, 0.5), control1: p(0.2, 0.2), control2: p(0.4, 0.2))
                path.addCurve(to: p(0.88, 0.3), control1: p(0.6, 0.8), control2: p(0.8, 0.8))
            case .cable:
                path.move(to: p(0.16, 0.22))
                path.addCurve(to: p(0.84, 0.78), control1: p(0.8, 0.1), control2: p(0.2, 0.9))
                fill.addEllipse(in: r(0.08, 0.14, 0.14, 0.14))
                fill.addRect(r(0.78, 0.72, 0.13, 0.13))
            case .note:
                path.addRoundedRect(in: r(0.1, 0.28, 0.8, 0.44), cornerSize: CGSize(width: s * 0.14, height: s * 0.14))
                path.move(to: p(0.24, 0.44)); path.addLine(to: p(0.72, 0.44))
                path.move(to: p(0.24, 0.56)); path.addLine(to: p(0.56, 0.56))
            case .picture:
                // A frame with a hill and a sun in it — a picture, from above.
                path.addRoundedRect(in: r(0.12, 0.2, 0.76, 0.6), cornerSize: CGSize(width: s * 0.06, height: s * 0.06))
                fill.move(to: p(0.18, 0.74)); fill.addLine(to: p(0.42, 0.46)); fill.addLine(to: p(0.56, 0.6))
                fill.addLine(to: p(0.66, 0.52)); fill.addLine(to: p(0.82, 0.74)); fill.closeSubpath()
                fill.addEllipse(in: r(0.62, 0.28, 0.12, 0.12))
            }
            c.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            c.fill(fill, with: .color(ink))
        }
    }
}

// MARK: - the toolbar

/// **One row of tools, centred across the top of the plan** — the tall rail
/// laid on its side (design/24). The same tools, drawings, keys and
/// drag-out-to-place, in four groups: pick and pan · what is filmed and lit
/// · the room · words and marks. Favorites is the last button; its nine
/// slots open under it.
struct DiagramToolbar: View {
    @ObservedObject var model: DiagramModel
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    private var groups: [[DiagramTool]] { DiagramTool.groups(model.layer) }

    /// How wide each tool's cell is: the roomy 52, or a tighter one when the
    /// window is too narrow to show every tool (Set now carries Words and
    /// Arrow too), so nothing is clipped at either end.
    var free: CGFloat = 10_000
    private var cell: CGFloat {
        let count = CGFloat(groups.flatMap { $0 }.count + 1)
        for c in [52, 44, 38] as [CGFloat] where count * (c + 2) + 260 <= free - 16 { return c }
        return 38
    }

    var body: some View { bar }

    private var bar: some View {
        HStack(spacing: 2) {
            layers
            rule
            ForEach(Array(groups.enumerated()), id: \.offset) { i, tools in
                if i > 0 { rule }
                ForEach(tools) { tool in button(tool) }
            }
            rule
            more
        }
        .padding(.horizontal, 6).frame(height: 54)
        .background(DiagramFloat(dark: dark, radius: 14))
        .fixedSize()
    }

    private var rule: some View {
        Rectangle().fill(Brand.rule2(dark)).frame(width: 1, height: 30).padding(.horizontal, 4)
    }

    /// **Each tool's picture with its name under it** (design/32 item 6).
    private func named(_ title: String, on: Bool, @ViewBuilder picture: () -> some View) -> some View {
        VStack(spacing: 3) {
            picture().frame(width: 20, height: 20)
            Text(title).sans(11, weight: on ? .semibold : .medium)
                .foregroundStyle(on ? Brand.ink(dark) : Brand.ink2(dark))
                .lineLimit(1).fixedSize()
        }
        .frame(width: cell, height: 46)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(on ? Brand.glassOn(dark) : Color.clear))
        .contentShape(Rectangle())
    }

    /// Name and key, in the app's dark pill, under the button.
    private func label(_ tool: DiagramTool) -> some View {
        HStack(spacing: 6) {
            Text(tool.title).sans(Brand.Size.body)
            Text(tool.key.uppercased()).sans(Brand.Size.tiny).opacity(0.6)
        }
        .foregroundStyle(Brand.paper(dark))
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Brand.ink(dark)))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .fixedSize()
        .allowsHitTesting(false)
    }

    /// The tools that place one thing, and so can be dragged onto the plan.
    private static let draggable: Set<DiagramTool> = [.camera, .cast, .frame, .door, .sliding, .window, .opening, .text, .note]

    private func choose(_ tool: DiagramTool) {
        // **Cast and Camera offer their choices first** (his note,
        // 2026-09-29): who, or which shot — then a click on the plan
        // puts it there.
        if [.cast, .camera].contains(tool), !model.readOnly, let view = model.canvas as? DiagramCanvasView {
            DispatchQueue.main.async { view.offerChoices(tool) }
        } else {
            model.tool = tool
        }
    }

    /// **Set · Plot** (Ref 1498, design/32 item 10): the one switch, at the
    /// left. Set lays the room; Plot puts the lamps, frames and camera on it.
    private var layers: some View {
        HStack(spacing: 2) {
            ForEach([("set", "Set"), ("plot", "Plot")], id: \.0) { key, title in
                let on = model.layer == key
                Button { model.layer = key } label: {
                    Text(title).sans(Brand.Size.body, weight: on ? .semibold : .medium)
                        .foregroundStyle(on ? Brand.ink(dark) : Brand.ink2(dark))
                        .padding(.horizontal, 11).frame(height: 28)
                        .background(Capsule().fill(on ? Brand.glassOn(dark) : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().strokeBorder(Brand.rule2(dark), lineWidth: 1))
        .padding(.leading, 4)
    }

    /// **More**: the layer's tools used now and then, by name and key, and
    /// Favorites. While one of them is in hand, More wears its picture and
    /// its name.
    private var more: some View {
        let list = DiagramTool.more(model.layer)
        let inHand = list.first { $0 == model.tool }
        return Menu {
            ForEach(list) { tool in
                Button { choose(tool) } label: { Text("\(tool.title)    \(tool.key.uppercased())") }
            }
            Divider()
            Button { withAnimation(.easeOut(duration: 0.15)) { model.showingFavorites.toggle() } } label: {
                Text(model.showingFavorites ? "Hide Favorites    1–9" : "Favorites    1–9")
            }
        } label: {
            named(inHand?.title ?? "More", on: inHand != nil || model.showingFavorites) {
                if let t = inHand {
                    DiagramToolIcon(tool: t, engine: model.engine, on: false)
                } else {
                    Canvas { c, size in
                        for k in 0..<3 {
                            let x = size.width * (0.2 + 0.3 * CGFloat(k))
                            c.fill(Path(ellipseIn: CGRect(x: x - 1.6, y: size.height / 2 - 1.6, width: 3.2, height: 3.2)),
                                   with: .color(Brand.ink(dark)))
                        }
                    }
                }
            }
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("More Tools")
        // The favorites strip opens under it.
        .background(GeometryReader { g in
            Color.clear.preference(key: DiagramToolSpots.self,
                                   value: ["favorites": g.frame(in: .named(DiagramMode.space))])
        })
    }

    private func button(_ tool: DiagramTool) -> some View {
        let on = model.tool == tool
        return Button {
            choose(tool)
        } label: {
            named(tool.title, on: on) { DiagramToolIcon(tool: tool, engine: model.engine, on: false) }
        }
        .buttonStyle(.plain)
        .diagramDragOut(Self.draggable.contains(tool) ? tool.rawValue : nil) {
            DiagramToolIcon(tool: tool, engine: model.engine, on: false).frame(width: 28, height: 28)
        }
        .onHover { inside in
            if inside { model.railHover = tool } else if model.railHover == tool { model.railHover = nil }
        }
        .overlay(alignment: .top) {
            if model.railHover == tool { label(tool).offset(y: 54) }
        }
        .zIndex(model.railHover == tool ? 1 : 0)
        .background(GeometryReader { g in
            Color.clear.preference(key: DiagramToolSpots.self,
                                   value: [tool.rawValue: g.frame(in: .named(DiagramMode.space))])
        })
    }
}

/// What a drag off the toolbar or the library carries, ahead of the thing.
enum DiagramRail {
    static let dragPrefix = "shotlister-diagram-add:"
}

/// Where each toolbar button stands on the canvas, by tool — so a tool's
/// library can open under it.
struct DiagramToolSpots: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Lets a toolbar button or a library tile be dragged onto the plan; `nil` leaves
/// it a plain button.
extension View {
    @ViewBuilder func diagramDragOut<P: View>(_ payload: String?, @ViewBuilder preview: () -> P) -> some View {
        if let payload {
            let picture = preview()
            draggable(DiagramRail.dragPrefix + payload) { picture }
        } else {
            self
        }
    }
}

/// **How bright the plan's paper is, on this Mac** (his ask, 2026-10-02):
/// a slider from dim to white. Only the screen: paper exports keep the paper.
struct DiagramBackdropPicker: View {
    @ObservedObject var model: DiagramModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Backdrop").sans(Brand.Size.title, weight: .semibold)
                Spacer(minLength: 16)
                Button("Reset") { model.backdrop = DiagramModel.defaultBackdrop }
                    .buttonStyle(.plain)
                    .sans(Brand.Size.small, weight: .medium).foregroundStyle(Brand.ink2(dark))
                    .disabled(abs(model.backdrop - DiagramModel.defaultBackdrop) < 0.005)
            }
            HStack(spacing: 10) {
                Text("Dim").sans(Brand.Size.small).foregroundStyle(Brand.ink2(dark))
                Slider(value: $model.backdrop, in: 0...1).controlSize(.small).frame(width: 200)
                Text("Bright").sans(Brand.Size.small).foregroundStyle(Brand.ink2(dark))
            }
        }
        .foregroundStyle(Brand.ink(dark))
        .padding(12)
    }
}

/// The floating panel look: the app's glass, a hairline, a soft shadow.
struct DiagramFloat: View {
    let dark: Bool
    var radius: CGFloat = 14
    /// The panel's own colour, not glass: what is behind it never shows
    /// through, so words on it read over the brightest plan (his note,
    /// 2026-10-02, on the foot bar).
    var solid = false
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(solid ? AnyShapeStyle(Brand.panel(dark)) : AnyShapeStyle(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Brand.rule2(dark).opacity(0.8), lineWidth: 1))
            .shadow(color: .black.opacity(dark ? 0.4 : 0.1), radius: 14, y: 5)
    }
}

// MARK: - the library

struct DiagramLibraryPanel: View {
    @ObservedObject var model: DiagramModel
    var height: CGFloat = 460
    /// **Swap, not place** (design/26, his ask 2026-10-02): opened from a
    /// piece's Fixture or Kind, the same library swaps that piece instead —
    /// what it is now on top, a click to swap it.
    var swap: DiagramEl? = nil
    /// Drawn on the plan as a floating panel; in a popover the popover is
    /// the panel.
    var chrome = true
    var done: () -> Void = {}
    @State private var search = ""
    /// The section chip that is on; empty is All.
    @State private var kind = ""
    /// The maker picked; empty is any.
    @State private var maker = ""
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    static let width: CGFloat = 330

    /// **A library you can find things in** (2026-09-30): the tool's own
    /// library — lamps under Light, grip under Grip, the rest under Set —
    /// in its sections, filtered by section and maker, searched by any word
    /// a crew calls a thing ("m18", "kino", "4k par").
    /// Which library: the tool's, or the one the piece being swapped is from.
    private var lib: String {
        guard let e = swap else { return model.tool.library }
        if let own = model.library?.symbols.first(where: { $0.id == e.sym })?.lib, !own.isEmpty { return own }
        return e.kind == "light" ? "light" : "set"
    }

    private var all: [DiagramSymbol] {
        (model.library?.symbols ?? []).filter { $0.lib == lib }
    }

    private var kinds: [String] {
        let present = Set(all.map(\.kind))
        let order = model.library?.kinds?[lib] ?? []
        return order.filter(present.contains) + present.subtracting(order).sorted()
    }

    private var makers: [String] {
        Array(Set(all.map(\.maker).filter { !$0.isEmpty })).sorted()
    }

    private var shown: [DiagramSymbol] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return all.filter { s in
            (kind.isEmpty || s.kind == kind) && (maker.isEmpty || s.maker == maker) && (q.isEmpty || s.matches(q))
        }
    }

    private var recent: [DiagramSymbol] {
        guard search.isEmpty, kind.isEmpty, maker.isEmpty else { return [] }
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return DiagramRecent.ids(in: lib).compactMap { byId[$0] }.filter { $0.id != swap?.sym }
    }

    /// What the piece being swapped is now.
    private var now: DiagramSymbol? {
        guard let e = swap, search.isEmpty, kind.isEmpty, maker.isEmpty else { return nil }
        return model.library?.symbols.first { $0.id == e.sym }
    }

    private var sections: [(String, [DiagramSymbol])] {
        var by: [String: [DiagramSymbol]] = [:]
        for s in shown { by[s.kind, default: []].append(s) }
        var out: [(String, [DiagramSymbol])] = []
        if let now { out.append(("Now", [now])) }
        let r = recent
        if !r.isEmpty { out.append(("Recent", r)) }
        for k in kinds { if let items = by[k], !items.isEmpty { out.append((k, items)) } }
        return out
    }

    private var noun: String {
        switch lib {
        case "light": return "lights"
        case "grip": return "grip"
        default: return "set pieces"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if swap != nil {
                Text(lib == "light" ? "Swap Fixture" : "Swap Kind").sans(Brand.Size.title, weight: .bold)
                    .foregroundStyle(Brand.ink(dark))
            }
            FieldText(placeholder: "Search " + noun, text: $search)
            filters
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(sections, id: \.0) { section, items in
                        Text(section).fieldLabel(dark).padding(.top, 8).padding(.bottom, 2)
                        ForEach(items) { sym in row(sym) }
                    }
                    if sections.isEmpty {
                        Text("Nothing called that").sans(Brand.Size.body).foregroundStyle(Brand.ink2(dark))
                            .padding(.vertical, 12)
                    }
                }
            }
            // The tool's hint, here rather than under the toolbar where the
            // panel would cover it.
            Text(swap != nil ? "Click to swap · Esc to close" : model.armed == nil ? hint : "Click to place · drag to turn")
                .sans(Brand.Size.small, weight: .medium).foregroundStyle(Brand.ink2(dark))
        }
        .padding(12)
        .frame(width: Self.width, height: max(height, 200))
        .background { if chrome { DiagramFloat(dark: dark) } }
        .onExitCommand { if swap != nil { done() } }
        .onChange(of: model.tool) { _, _ in kind = ""; maker = "" }
    }

    private var hint: String {
        switch lib {
        case "light": return "Pick a light"
        case "grip": return "Pick a piece of grip"
        default: return "Pick a set piece"
        }
    }

    /// The section chips, and the maker where the library has makers.
    private var filters: some View {
        WrappingRow(spacing: 2, runSpacing: 2) {
            ChoicePill(title: "All", on: kind.isEmpty, dark: dark) { kind = "" }
            ForEach(kinds, id: \.self) { k in
                ChoicePill(title: k, on: kind == k, dark: dark) { kind = kind == k ? "" : k }
            }
            if makers.count > 1 {
                Menu {
                    Button("Any Maker") { maker = "" }
                    Divider()
                    ForEach(makers, id: \.self) { m in Button(m) { maker = m } }
                } label: {
                    Text(maker.isEmpty ? "Maker" : maker).sans(Brand.Size.small, weight: .semibold)
                        .foregroundStyle(maker.isEmpty ? Brand.ink2(dark) : Brand.ink(dark))
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton).menuIndicator(.visible).fixedSize()
                .padding(.horizontal, 8).frame(height: Brand.barHeight)
            }
        }
    }

    /// One piece: its picture as the plan draws it, and its whole name.
    private func row(_ sym: DiagramSymbol) -> some View {
        let on = swap.map { $0.sym == sym.id } ?? (model.armed?.id == sym.id)
        let rot = DiagramModel.restingRot(sym) == 0 ? 0.0 : -90.0
        return Button {
            if let e = swap {
                if e.sym != sym.id {
                    model.swap([e.id], to: sym.id)
                    DiagramRecent.use(sym.id, in: lib)
                }
                done()
            } else {
                model.armed = sym
            }
        } label: {
            HStack(spacing: 10) {
                DiagramGlyph(kind: sym.light ? "light" : "set", sym: sym.id, w: sym.w, h: sym.h, rot: rot, engine: model.engine)
                    .frame(width: 52, height: 38)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(DiagramInk.color("paper", dark: false).map { Color(nsColor: $0) } ?? .white))
                VStack(alignment: .leading, spacing: 1) {
                    Text(sym.name).sans(Brand.Size.body, weight: on ? .semibold : .regular)
                        .foregroundStyle(Brand.ink(dark))
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    if !sym.maker.isEmpty, !sym.name.lowercased().hasPrefix(sym.maker.lowercased().prefix(4)) {
                        Text(sym.maker).sans(Brand.Size.tiny).foregroundStyle(Brand.ink2(dark)).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(on ? Brand.glassOn(dark) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .diagramDragOut("sym:" + sym.id) {
            DiagramGlyph(kind: sym.light ? "light" : "set", sym: sym.id, w: sym.w, h: sym.h, rot: rot, engine: model.engine)
                .frame(width: 58, height: 44)
        }
        .help(sym.name)
    }
}

// MARK: - the project's pictures

struct DiagramPicturesPanel: View {
    @ObservedObject var model: DiagramModel
    var height: CGFloat = 460
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        let groups = model.projectPictures()
        VStack(alignment: .leading, spacing: 8) {
            Segmented(selection: $model.pictureAsPhoto,
                      items: [.init(value: false, title: "Background"), .init(value: true, title: "Photo")],
                      quiet: true)
            Button("Choose File…") { model.pickPicture() }
                .buttonStyle(.plain)
                .sans(Brand.Size.small, weight: .medium)
                .foregroundStyle(Brand.ink2(dark))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(groups, id: \.0) { group, pics in
                        Text(group).fieldLabel(dark).padding(.top, 6)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(86), spacing: 6), count: 3), spacing: 6) {
                            ForEach(pics) { tile($0) }
                        }
                    }
                    if groups.isEmpty {
                        Text("No pictures in this project").sans(Brand.Size.body).foregroundStyle(Brand.ink2(dark))
                            .padding(.vertical, 12)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 300, height: max(height, 200))
        .background(DiagramFloat(dark: dark))
    }

    private func picture(_ pic: DiagramProjectPicture) -> some View {
        let still = Thumbs.shared.image(ViewModel.Frame(hash: pic.hash, filename: pic.filename, kind: "image"),
                                        from: model.engine)
        return ZStack {
            Brand.rule(dark)
            if let still {
                Image(nsImage: still).resizable().aspectRatio(contentMode: .fill)
            } else {
                Frames.gap(pic.hash, dark: dark, small: true)
            }
        }
        .frame(width: 86, height: 62)
        // A picture is never rounded (his rule, 2026-10-07).
        .clipShape(Rectangle())
    }

    private func tile(_ pic: DiagramProjectPicture) -> some View {
        Button { model.addProjectPicture(pic) } label: { picture(pic) }
            .buttonStyle(.plain)
            .diagramDragOut("pic:" + pic.hash) { picture(pic) }
            .help(pic.filename)
    }
}

// MARK: - a tool's options

struct DiagramToolOptions: View {
    @ObservedObject var model: DiagramModel
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        Group {
            if model.calibrating != nil {
                hint("Drag across a length you know")
            } else {
                toolOptions
            }
        }
    }

    @ViewBuilder private var toolOptions: some View {
        Group {
            switch model.tool {
            case .shape:
                HStack(spacing: 2) {
                    ForEach(["rect", "ellipse", "triangle", "diamond", "hexagon", "star", "line"], id: \.self) { k in
                        ChoicePill(title: k == "rect" ? "Rectangle" : k.capitalized, on: model.shapeKind == k, dark: dark) { model.shapeKind = k }
                    }
                }
                .padding(5)
                .background(DiagramFloat(dark: dark, radius: 12))
            case .pen:
                HStack(spacing: 10) {
                    // What it will be: a plain line, a curved wall, or a filled shape.
                    HStack(spacing: 2) {
                        ForEach([("line", "Line"), ("wall", "Wall"), ("object", "Object")], id: \.0) { k, title in
                            ChoicePill(title: title, on: model.drawAs == k, dark: dark) { model.drawAs = k }
                        }
                    }
                    ChoicePill(title: "Fill", on: model.drawFill || model.drawAs == "object", dark: dark) {
                        if model.drawAs == "object" { model.drawAs = "line"; model.drawFill = false } else { model.drawFill.toggle() }
                    }
                    Text(model.drawNodes.isEmpty ? "Click for a corner · drag for a curve · click the first point to close" : "Return to finish · ⌫ to undo point")
                        .sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark)).fixedSize()
                    if model.drawAs != "wall" || model.drawFill {
                    HStack(spacing: 6) {
                    // The first is the plan's own ink — dark on paper, light on
                    // the dark canvas — so a line drawn at night can be read.
                    ForEach(["", "#E5484D", "#D97706", "#16A34A", "#0A6CE8", "#7B4BC4"], id: \.self) { c in
                        Circle().fill(c.isEmpty ? Brand.ink(dark) : Brand.hex(String(c.dropFirst())))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(Color(nsColor: DiagramInk.pick),
                                                           lineWidth: model.penColour == c ? 2 : 0).padding(-3))
                            .onTapGesture { model.penColour = c }
                    }
                    }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(DiagramFloat(dark: dark, radius: 12))
            case .set, .light, .grip:
                // Said in the library panel, which opens under the tool.
                EmptyView()
            case .camera, .cast:
                hint("Click to place · drag to turn")
            case .door, .sliding, .window, .opening:
                hint("Click on a wall")
            case .cable:
                hint(model.pending.isEmpty ? "Click to start" : "Double-click to finish")
            default:
                EmptyView()
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).sans(Brand.Size.small, weight: .medium)
            .foregroundStyle(Brand.ink2(dark))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(DiagramFloat(dark: dark, radius: 12))
    }
}

// MARK: - the bars at the foot

/// **Stepping through the beats**, on the left of the foot bar while in
/// beats mode (Beats in the scene's line goes in; Done comes out).
struct DiagramBeatBar: View {
    @ObservedObject var model: DiagramModel
    @State private var playing = false
    @State private var timer: Timer?
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        stepping
            .onDisappear { stop() }
            .onChange(of: model.scene) { _, _ in stop() }
    }

    private var stepping: some View {
        let last = max(model.lastBeat, model.beat)
        return HStack(spacing: 4) {
            Button { model.beat = max(1, model.beat - 1) } label: { chevron(left: true) }
                .buttonStyle(.plain).disabled(model.beat <= 1)
            Text("Beat \(model.beat)").sans(Brand.Size.body, weight: .semibold).monospacedDigit()
            Text("of \(last)").sans(Brand.Size.body).foregroundStyle(Brand.ink2(dark)).monospacedDigit()
            Button { model.beat = min(last, model.beat + 1) } label: { chevron(left: false) }
                .buttonStyle(.plain).disabled(model.beat >= last)
            Rectangle().fill(Brand.rule2(dark)).frame(width: 1, height: 16).padding(.horizontal, 4)
            Button { model.addBeat() } label: { PlusLabel(text: "Beat", dark: dark) }
                .buttonStyle(.plain)
                .disabled(model.readOnly)
                .help("Add Beat")
            Button { playing ? stop() : play() } label: {
                Text(playing ? "Stop" : "Play").sans(Brand.Size.body, weight: .medium)
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
            .disabled(model.lastBeat <= 1)
            Rectangle().fill(Brand.rule2(dark)).frame(width: 1, height: 16).padding(.horizontal, 4)
            Button("Done") { stop(); model.beatMode = false }
                .buttonStyle(.plain)
                .sans(Brand.Size.body, weight: .semibold)
        }
    }

    private func chevron(left: Bool) -> some View {
        Canvas { c, size in
            var p = Path()
            let (x0, x1) = left ? (size.width * 0.62, size.width * 0.38) : (size.width * 0.38, size.width * 0.62)
            p.move(to: CGPoint(x: x0, y: size.height * 0.25))
            p.addLine(to: CGPoint(x: x1, y: size.height * 0.5))
            p.addLine(to: CGPoint(x: x0, y: size.height * 0.75))
            c.stroke(p, with: .color(Brand.ink(dark)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 22, height: 22)
        .contentShape(Rectangle())
    }

    /// Watch the scene's blocking happen: every move eased from each beat to
    /// the next, a beat a second and a bit, then stop on the last.
    private func play() {
        playing = true
        model.selection = []
        if model.beat >= model.lastBeat { model.beat = 1 }
        model.tween = 0
        let step = 1.0 / 36.0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            let next = model.tween + step
            if next >= 1 {
                model.tween = 0
                model.beat += 1
                if model.beat >= model.lastBeat { stop() }
            } else {
                model.tween = next
            }
        }
    }

    private func stop() {
        playing = false
        timer?.invalidate()
        timer = nil
        model.tween = 0
    }
}

/// **Zoom, in the bottom-right corner** — how big the picture is, with the
/// compass just over it (drawn by the canvas). Double-click the per cent to
/// fit, as ⌘0 does.
struct DiagramZoom: View {
    @ObservedObject var model: DiagramModel
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        HStack(spacing: 2) {
            Button("−") { model.zoom(by: 0.8, size: .zero); model.objectWillChange.send() }
                .buttonStyle(.plain).sans(Brand.Size.large)
                .frame(width: 22)
            Text("\(Int((model.scale / 60 * 100).rounded()))%")
                .sans(Brand.Size.body).monospacedDigit().foregroundStyle(Brand.ink2(dark))
                .frame(minWidth: 40)
                .onTapGesture(count: 2) { model.fitted = false; model.objectWillChange.send() }
                .help("Zoom to Fit  ⌘0")
            Button("+") { model.zoom(by: 1.25, size: .zero); model.objectWillChange.send() }
                .buttonStyle(.plain).sans(Brand.Size.large)
                .frame(width: 22)
        }
        .padding(.horizontal, 8).frame(height: 34)
        .background(DiagramFloat(dark: dark, radius: 17))
        .fixedSize()
    }
}

/// **The View menu**, in the scene's line: everything about how the plan is
/// drawn that is not Grid or Snap. **It stays open while he clicks** (his
/// ask, 2026-10-05: *"I dont want it to go away, i want it to stay until i
/// click off of it"*) — a panel, not a menu, so a switch flips and the
/// panel waits for the next one. Show by Kind's switches are this Mac's own.
struct DiagramViewMenu: View {
    @ObservedObject var model: DiagramModel
    @State private var backdropOpen = false
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    /// `Sun`, or where the clock has it: `Sun 16:00`.
    private var sunWord: String {
        guard model.settings.sun, let m = model.plan.sun?.minutes else { return "Sun" }
        return "Sun " + DiagramSunPanel.clock(m)
    }

    private func flag(_ title: String, _ key: String, _ on: Bool, disabled: Bool = false) -> some View {
        Toggle(title, isOn: Binding(get: { on }, set: { model.setting(key, $0) }))
            .toggleStyle(.checkbox).sans(Brand.Size.body).disabled(disabled)
    }

    private func head(_ title: String) -> some View {
        Text(title).fieldLabel(dark).padding(.top, 4)
    }

    /// A row that opens something else: the panel closes for it.
    private func row(_ title: String, disabled: Bool = false, _ act: @escaping () -> Void) -> some View {
        Button { model.viewOpen = false; act() } label: {
            Text(title).sans(Brand.Size.body).foregroundStyle(Brand.ink(dark)).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(disabled)
    }

    private var panel: some View {
        let s = model.settings
        let ro = model.readOnly
        // Two columns, so nothing scrolls: how the plan is drawn on the
        // left; what is shown, the sheet, units and panels on the right.
        return HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                row("Colors…", disabled: ro) { model.showingColours = true }
                Divider()
                flag("Grid", "grid", s.grid)
                flag("Snap", "snap", s.snap)
                // **Sketch** (his ask, 2026-10-04): marks and words over a
                // location photo or a drawing — no grid, scale, lengths or sun.
                flag("Sketch", "sketch", s.sketch, disabled: ro)
                // **Lengths**: none, the picked wall's on screen only, or every
                // wall's on screen and on paper (`dims` and `all_lengths`).
                Text("Lengths").sans(Brand.Size.body)
                Picker("", selection: Binding(get: { lengths }, set: { setLengths($0) })) {
                    Text("Off").tag("off")
                    Text("Picked").tag("picked")
                    Text("All").tag("all")
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
                // **Measurements** (his ask, 2026-10-05): the rulers he laid,
                // kept when off, on screen and on paper.
                flag("Measurements", "measures", s.measures, disabled: ro)
                flag("Cones", "cones", s.cones)
                flag(sunWord, "sun", s.sun)
                row("Sun and North…") { model.showingShow = false; model.showingSun = true }
                Divider()
                flag("Labels", "labels", s.labels)
                flag("All Caps", "caps", s.caps, disabled: ro)
                flag("Counts", "counts", s.counts, disabled: ro)
                Toggle("Storyboard Frames", isOn: $model.showFrames).toggleStyle(.checkbox).sans(Brand.Size.body)
                // A frame's cloth across it, quietly, on screen and on paper.
                flag("Frame Fabric", "fabric", s.fabric, disabled: ro)
                row("Backdrop…") { DispatchQueue.main.async { backdropOpen = true } }
            }
            .frame(width: 190, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text("Show by Kind").fieldLabel(dark)
                ForEach(DiagramShow.kinds, id: \.key) { k in
                    Toggle(k.title, isOn: Binding(get: { !model.unseenKinds.contains(k.key) },
                                                  set: { model.setShown(k.key, $0) }))
                        .toggleStyle(.checkbox).sans(Brand.Size.body)
                }
                Button("Show All") { model.unseenKinds = [] }
                    .buttonStyle(.capsule).disabled(model.unseenKinds.isEmpty)
                // **The sheet** the plan lies on, as it prints (`DiagramPage`).
                head("Sheet")
                Group {
                    Picker("Paper", selection: Binding(get: { s.paper }, set: { model.setting("paper", $0) })) {
                        Text("Letter").tag("letter")
                        Text("Tabloid").tag("tabloid")
                        Text("A4").tag("a4")
                    }
                    .pickerStyle(.menu).sans(Brand.Size.body).fixedSize()
                    Picker("", selection: Binding(get: { s.orientation == "portrait" ? "portrait" : "landscape" },
                                                  set: { model.setting("orientation", $0) })) {
                        Text("Landscape").tag("landscape")
                        Text("Portrait").tag("portrait")
                    }
                    .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
                    flag("Legend", "legend", s.legend)
                    flag("Show Unlabeled", "unlabeled", s.unlabeled)
                    flag("Sheet Notes", "notes", s.notes)
                    flag("Scale Bar", "scale_bar", s.scale_bar, disabled: s.sketch)
                }
                .disabled(ro)
                Divider()
                Picker("", selection: Binding(get: { s.units == "m" ? "m" : "ft" }, set: { model.setting("units", $0) })) {
                    Text("Feet and Inches").tag("ft")
                    Text("Metres").tag("m")
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
                // The step the grid keeps to as the plan first shows; zoomed in
                // or out, it goes finer or coarser on its own.
                Picker("Grid Step", selection: Binding(get: { gridChoice }, set: { model.setting("step", $0) })) {
                    ForEach(gridSteps, id: \.0) { v, name in Text(name).tag(v) }
                }
                .pickerStyle(.menu).sans(Brand.Size.body).fixedSize()
                Divider()
                row("Layers") { model.toggle(panel: "layers") }
                row("Details") { model.toggle(panel: "details") }
                row("Present") { model.present(true) }
            }
            .frame(width: 200, alignment: .leading)
        }
        .padding(14)
        .fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        Button { model.viewOpen.toggle() } label: {
            HStack(spacing: 4) {
                Text("View").sans(13).foregroundStyle(Brand.ink(dark))
                // Something switched off by kind: said on the menu's face.
                if !model.unseenKinds.isEmpty {
                    Circle().fill(Color(nsColor: DiagramInk.pick)).frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, Brand.barPadding).frame(height: Brand.barHeight)
            .barPill(dark, on: false)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .fixedSize()
        .popover(isPresented: $model.viewOpen, arrowEdge: .bottom) { panel }
        .background {
            // The menu's shortcuts, kept while the panel is shut.
            ZStack {
                Button("") { model.toggle(panel: "layers") }.keyboardShortcut("1", modifiers: [.command, .control])
                Button("") { model.toggle(panel: "details") }.keyboardShortcut("2", modifiers: [.command, .control])
                Button("") { model.present(true) }.keyboardShortcut("f", modifiers: .command)
            }
            .opacity(0).frame(width: 0, height: 0).allowsHitTesting(false)
        }
        .background(Color.clear.popover(isPresented: $backdropOpen, arrowEdge: .bottom) { DiagramBackdropPicker(model: model) })
    }

    /// Lengths, as one choice: `off`, `picked`, `all`.
    private var lengths: String {
        !model.settings.dims ? "off" : (model.settings.all_lengths ? "all" : "picked")
    }
    private func setLengths(_ v: String) {
        if v == "off" { model.setting("dims", false); return }
        model.edit(["op": "settings", "set": ["dims": true, "all_lengths": v == "all"]])
    }

    /// The steps the menu offers, in the plan's units.
    private var gridSteps: [(Double, String)] {
        model.settings.units == "m"
            ? [(1.0, "Every Metre"), (0.5, "Every 50 cm"), (0.1, "Every 10 cm")]
            : [(0.3048, "Every Foot"), (0.1524, "Every 6 Inches")]
    }

    /// The grid step, as one of those the menu offers.
    private var gridChoice: Double {
        let steps = gridSteps.map(\.0)
        return steps.min { abs($0 - model.settings.step) < abs($1 - model.settings.step) } ?? steps[0]
    }
}

// MARK: - an empty plan

struct DiagramEmpty: View {
    @ObservedObject var state: ShellState
    @ObservedObject var model: DiagramModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        VStack(spacing: 10) {
            Text("No diagram yet").sans(Brand.Size.large, weight: .semibold).foregroundStyle(Brand.ink2(dark))
            HStack(spacing: 8) {
                Button("Draw Walls") { model.tool = .wall }
                    .buttonStyle(.capsule)
                Button("Add Camera") { model.tool = .camera }
                    .buttonStyle(.capsule)
            }
        }
        .padding(22)
        .background(DiagramFloat(dark: dark, radius: 18))
    }
}

/// What a checking run asks the Diagram mode to show: `--diagramtool camera`,
/// `--diagrampick 2` (the second element), `--diagrambeat 2`, and
/// `--diagramsays`, which prints what the plan holds so a check can read it.
enum DiagramChecks {
    static func apply(to model: DiagramModel) {
        // Also read from the environment (`SHOTLISTER_DIAGRAMTOOL=camera` and so
        // on): a run with the screen locked gets no window at all once it
        // carries extra flags, and the environment is not a flag.
        let args = CommandLine.arguments
        let env = ProcessInfo.processInfo.environment
        func value(_ flag: String) -> String? {
            if let at = args.firstIndex(of: flag), at + 1 < args.count { return args[at + 1] }
            return env["SHOTLISTER_" + flag.dropFirst(2).uppercased()]
        }
        if let look = env["SHOTLISTER_LOOK"] {
            NSApp.appearance = NSAppearance(named: look == "light" ? .aqua : .darkAqua)
        }
        if let t = value("--diagramtool"), let tool = DiagramTool(rawValue: t) { model.tool = tool }
        if let b = value("--diagrambeat"), let n = Int(b) { model.beat = n }
        if let shot = value("--diagramshot") { model.state?.diagramShot = shot }
        if let p = value("--diagrampick") {
            let wanted = p.split(separator: ",").compactMap { Int($0) }
            model.selection = wanted.compactMap { i in model.plan.els.indices.contains(i) ? model.plan.els[i].id : nil }
        }
        if value("--diagramtool") != nil, model.tool.usesLibrary {
            model.armed = model.library?.symbols.first { $0.lib == model.tool.library }
        }
        if let script = env["SHOTLISTER_DIAGRAMDRIVE"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { DiagramDrive.run(script, model: model) }
        }
        if args.contains("--diagramsays") || env["SHOTLISTER_DIAGRAMSAYS"] != nil {
            let kinds = model.plan.els.map(\.kind).joined(separator: ",")
            FileHandle.standardError.write(Data("diagram: \(model.plan.els.count) els [\(kinds)] shapes \(model.plan.shapes.count) beat \(model.beat)\n".utf8))
        }
    }
}

/// **A checking run's hand on the plan.** `SHOTLISTER_DIAGRAMDRIVE` is a
/// script of steps separated by `;` — real mouse events posted into the
/// window, so what is checked is the canvas's own handling, not a shortcut
/// round it:
///
///     tool camera; down 400 300; drag 460 300; up 460 300; report
///
/// Points are in the canvas, from its top left. `down`/`drag`/`up`/`click`/
/// `dbl` take an optional modifier word (`shift`, `option`, `command`);
/// `tool`, `arm` (a library entry), `beat`, `key` (a character, or `delete`,
/// `escape`, `return`), `wait` (seconds) and `report` round it out.
enum DiagramDrive {
    /// Where the painted sun's disc stands on screen, if one is painted.
    static func sunDisc(_ model: DiagramModel, size: CGSize) -> CGPoint? {
        guard let disc = model.shownShapes.last(where: { $0.p == "sun" && $0.k == "path" && ($0.a ?? 1) > 0.5 }),
              let d = disc.d else { return nil }
        var xs: [Double] = [], ys: [Double] = []
        var i = 0
        while i < d.count {
            let op = Int(d[i]), n = op == 2 ? 6 : (op == 3 ? 0 : 2)
            if n > 0, i + n < d.count { xs.append(d[i + n - 1]); ys.append(d[i + n]) }
            i += n + 1
        }
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return nil }
        return model.toView(CGPoint(x: (x0 + x1) / 2, y: (y0 + y1) / 2), size: size)
    }

    static func run(_ script: String, model: DiagramModel) {
        let steps = script.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var delay: TimeInterval = 0
        for step in steps {
            let words = step.split(separator: " ").map(String.init)
            guard let verb = words.first else { continue }
            if verb == "wait", words.count > 1, let s = Double(words[1]) { delay += s; continue }
            delay += 0.12
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated { perform(verb, Array(words.dropFirst()), model) }
            }
        }
    }

    @MainActor
    private static func perform(_ verb: String, _ args: [String], _ model: DiagramModel) {
        guard let canvas = model.canvas, let window = canvas.window else {
            FileHandle.standardError.write(Data("drive: no canvas\n".utf8))
            return
        }
        func flags(_ from: Int) -> NSEvent.ModifierFlags {
            var f: NSEvent.ModifierFlags = []
            for w in args.dropFirst(from) {
                switch w {
                case "shift": f.insert(.shift)
                case "option": f.insert(.option)
                case "command": f.insert(.command)
                case "control": f.insert(.control)
                default: break
                }
            }
            return f
        }
        func post(_ type: NSEvent.EventType, _ p: CGPoint, clicks: Int = 1, flags f: NSEvent.ModifierFlags = []) {
            let at = canvas.convert(p, to: nil)
            guard let e = NSEvent.mouseEvent(with: type, location: at, modifierFlags: f,
                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil,
                                             eventNumber: 0, clickCount: clicks,
                                             pressure: type == .leftMouseUp ? 0 : 1) else { return }
            window.sendEvent(e)
        }
        /// Press at a point and drag it by dx, dy in eight steps.
        func pull(from p: CGPoint, dx: Double, dy: Double, flags f: NSEvent.ModifierFlags = []) {
            post(.leftMouseDown, p, flags: f)
            for i in 1...8 {
                let k = CGFloat(i) / 8
                post(.leftMouseDragged, CGPoint(x: p.x + CGFloat(dx) * k, y: p.y + CGFloat(dy) * k), flags: f)
            }
            post(.leftMouseUp, CGPoint(x: p.x + CGFloat(dx), y: p.y + CGFloat(dy)), flags: f)
        }
        func mouse(_ type: NSEvent.EventType, clicks: Int = 1) {
            guard args.count >= 2, let x = Double(args[0]), let y = Double(args[1]) else { return }
            let at = canvas.convert(CGPoint(x: x, y: y), to: nil)
            guard let e = NSEvent.mouseEvent(with: type, location: at, modifierFlags: flags(2),
                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil,
                                             eventNumber: 0, clickCount: clicks,
                                             pressure: type == .leftMouseUp ? 0 : 1) else { return }
            window.sendEvent(e)
        }
        switch verb {
        case "tool": if let t = args.first.flatMap(DiagramTool.init(rawValue:)) { model.tool = t }
        // layer set|plot — the Set · Plot switch (Ref 1498)
        case "layer": model.layer = args.first == "set" ? "set" : "plot"
        // clickkind <kind> — a real click where the first piece of that kind
        // stands, then what is picked (Set or Plot: a set piece is clicked
        // straight through while plotting)
        case "clickkind":
            guard let kind = args.first, let e = model.plan.els.first(where: { $0.kind == kind }),
                  let view = canvas as? DiagramCanvasView, let p = view.pointOf(e.id) else { return }
            model.selection = []
            post(.leftMouseDown, p); post(.leftMouseUp, p)
            FileHandle.standardError.write(Data("clickkind: \(kind) at \(Int(p.x)),\(Int(p.y)) layer \(model.layer) picked [\(model.selection.compactMap { model.el($0)?.kind }.joined(separator: ","))]\n".utf8))
        case "drawas": model.drawAs = args.first ?? "line"
        case "drawfill": model.drawFill = args.first != "off"
        case "drop":
            // drop <what> <x> <y> [shift] — as if dragged off the rail and let go there
            guard args.count >= 3, let x = Double(args[1]), let y = Double(args[2]) else { return }
            (canvas as? DiagramCanvasView)?.drop(args[0], at: CGPoint(x: x, y: y), swap: args.dropFirst(3).contains("shift"))
        case "fav", "favclear", "favs", "favdrag", "favorites", "swap", "guides", "haulby", "lineup", "letgo":
            DiagramSpeedDrive.perform(verb, args, model, pull: { p, dx, dy in pull(from: p, dx: dx, dy: dy) },
                                      post: { type, p, f in post(type, p, flags: f) })
        case "hover": model.railHover = args.first.flatMap(DiagramTool.init(rawValue:))
        case "arm": model.armed = model.library?.symbols.first { $0.id == args.first }
        case "armlook": if let k = args.first { model.armedLook = k }
        case "swatches":
            // swatches <path> — a picture of the frame bar's picker: every
            // skin's swatch, as the popover draws it
            guard let path = args.first, let choices = model.library?.frames else { return }
            let sheet = VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(70), spacing: 8), count: 7), alignment: .leading, spacing: 8) {
                    ForEach(choices.materials) { m in
                        VStack(spacing: 3) {
                            DiagramSwatch(material: m, gel: m.id == "gel" ? "ctb-half" : nil).frame(width: 40, height: 40)
                            Text(m.name).font(.system(size: 9)).multilineTextAlignment(.center).frame(width: 70)
                        }
                    }
                }
            }
            .padding(14).background(Color.white).environment(\.colorScheme, .light)
            let r = ImageRenderer(content: sheet)
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
            }
        case "libsays":
            // libsays <light|grip|set> [words…] — what that library offers: how
            // many, how many lamps, its sections, and what the words find
            let lib = args.first ?? "light"
            let q = args.dropFirst().joined(separator: " ")
            let all = (model.library?.symbols ?? []).filter { $0.lib == lib }
            let found = q.isEmpty ? all : all.filter { $0.matches(q) }
            let kinds = model.library?.kinds?[lib] ?? []
            let lamps = all.filter { $0.light && $0.beam > 0 }.count
            FileHandle.standardError.write(Data(("library: \(lib) \(all.count) lamps \(lamps) kinds \(kinds.joined(separator: ",")) found \(found.count): "
                + found.prefix(8).map(\.name).joined(separator: " | ") + "\n").utf8))
        case "castas": model.castAs = args.joined(separator: " ")
        case "castchoices":
            let (here, film, _) = model.castChoices()
            print("castchoices: scene=\(here.joined(separator: "|")) film=\(film.joined(separator: "|"))")
        case "picture": if let path = args.first { model.addPicture(URL(fileURLWithPath: path)) }
        case "pictures":
            // pictures [n photo|back] — list the project's pictures, or lay the nth
            let all = model.projectPictures()
            if args.count >= 2, let n = Int(args[0]) {
                let flat = all.flatMap(\.1)
                guard n < flat.count else { return }
                model.pictureAsPhoto = args[1] == "photo"
                model.addProjectPicture(flat[n])
            } else {
                print("pictures: " + all.map { "\($0.0)=\($0.1.count)" }.joined(separator: " "))
            }
        case "beat": if let n = args.first.flatMap(Int.init) { model.beat = n }
        case "beatmode": model.beatMode = args.first != "off"
        case "tween": if let t = args.first.flatMap(Double.init) { model.tween = t }
        case "frames": model.showFrames = args.first != "off"
        case "sunpanel": model.showingSun = true
        case "colourspanel": model.showingColours = true
        case "sharelabel": model.shareLabel()
        case "ride":
            // ride — the picked camera locked to the nearest track
            if let id = model.selection.first { _ = model.edit(["op": "ride", "id": id]) }
        case "colour-of":
            // colour-of <category> <#rrggbb> — a plot colour, for every plan
            if args.count >= 2 {
                var now = model.settings.colours
                now[args[0]] = args[1]
                model.settingEverywhere("colours", now)
            }
        case "compass":
            // compass <dx> <dy> — take the compass by the top of its ring and
            // pull the pointer this far, turning it like a dial
            guard args.count >= 2, let dx = Double(args[0]), let dy = Double(args[1]),
                  let view = canvas as? DiagramCanvasView, let c = view.compassSpot else {
                FileHandle.standardError.write(Data("drive: no compass\n".utf8)); return
            }
            pull(from: CGPoint(x: c.centre.x, y: c.centre.y - c.radius * 0.9), dx: dx, dy: dy)
        case "sunpick":
            // sunpick <Sunrise|Noon|Sunset|…> — a quick pick, by its name
            let want = args.joined(separator: " ").lowercased()
            let sun = model.plan.sun
            let at = ["sunrise": sun?.rise, "noon": sun?.noon, "sunset": sun?.set,
                      "morning golden hour": sun?.goldenMorning, "evening golden hour": sun?.goldenEvening][want] ?? nil
            if let at { model.setting("sun_time", DiagramSunPanel.clock(at)) }
        case "room":
            // room [path] — the sample scanned room (or a RoomPlan file) laid
            // on the plan, through the same engine call the Room from Scan
            // menu makes
            if let engine = model.engine, let scene = model.scene, engine.diagramRoom(scene: scene, location: "", path: args.first ?? "") {
                model.state?.replace(engine.view()); model.reload()
            }
        case "copyfrom":
            // copyfrom <scene number> [add] — Copy From, without the asking
            // (or a plan's name, with its spaces as _)
            let named = (args.first ?? "").replacingOccurrences(of: "_", with: " ")
            if let from = DiagramCopy.targets(model).first(where: { $0.short == named }) {
                DiagramCopy.from(from, into: model, mode: args.dropFirst().first == "add" ? .add : .replace)
            }
        case "diagramtab":
            // diagramtab <n> — pick the scene's nth diagram (1 = first), as
            // clicking its tab does (`DiagramScenes`)
            if let state = model.state, let n = Int(args.first ?? ""), n >= 1, n <= state.sceneDiagramsNow.count {
                state.sceneDiagramPick = state.sceneDiagramsNow[n - 1].id
            }
        case "hideempty":
            // hideempty on|off — the Scenes head's Hide Empty
            model.state?.diagramHideEmpty = args.first != "off"
        case "hidescenes", "showscenes":
            // hidescenes 4,7 / showscenes 4 — Hide from Diagrams / Show, by
            // scene number, as the list's right-click does
            if let state = model.state {
                let numbers = (args.first ?? "").split(separator: ",").map(String.init)
                let ids = (state.view?.scenes ?? []).filter { numbers.contains($0.number) }.map(\.id)
                state.hideFromDiagrams(ids, hidden: verb == "hidescenes")
            }
        case "revealhidden":
            // revealhidden on|off — the "N Hidden" line, clicked
            model.state?.diagramRevealHidden = args.first != "off"
        case "scenelist":
            // scenelist — which scenes the Diagram's list shows, and how many it leaves out
            if let state = model.state {
                let listed = state.scenes.filter { !state.diagramHides($0) }.map(\.number)
                let by = state.scenes.filter { $0.diagramHidden == true }.map(\.number)
                FileHandle.standardError.write(Data("scenelist: all \(state.scenes.count) listed [\(listed.joined(separator: ","))] hidden \(state.diagramHiddenCount) byhand [\(by.joined(separator: ","))] open \(state.diagramRevealHidden)\n".utf8))
            }
        case "newplan":
            // newplan [name, spaces as _] [copy] — + in the Plans list, or
            // Copy to New Plan with `copy`
            if let state = model.state {
                let name = (args.first ?? "").replacingOccurrences(of: "_", with: " ")
                DiagramPlanActions.add(state, from: args.dropFirst().first == "copy" ? model.scene : nil, name: name)
            }
        case "openplan":
            // openplan <name, spaces as _> — a plan picked in the list; `scene` goes back
            if let state = model.state {
                let name = (args.first ?? "").replacingOccurrences(of: "_", with: " ")
                state.diagramPlan = state.diagramPlans.first { $0.name == name }?.id
            }
        case "deleteplan":
            // deleteplan — the open plan, without the asking
            if let state = model.state, let plan = state.diagramPlanLive { DiagramPlanActions.delete(state, plan, asking: false) }
        case "copypicker":
            // copypicker <path> — the Copy To list, as a picture
            if let path = args.first, let data = DiagramCopy.pickerPicture(model: model) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        case "copyto", "sendto":
            // copyto <scene numbers, by commas> [replace] — Copy To; sendto
            // the same with only the picked pieces, as Send to Scene
            let numbers = (args.first ?? "").split(separator: ",").map { $0.replacingOccurrences(of: "_", with: " ") }
            let to = DiagramCopy.targets(model).filter { numbers.contains($0.short) }.map(\.id)
            if let engine = model.engine, let scene = model.scene, !to.isEmpty {
                DiagramCopy.send(model: model, engine: engine, scene: scene, to: to,
                                 mode: args.dropFirst().first == "replace" ? .replace : .add,
                                 ids: verb == "sendto" ? model.selection : [])
            }
        case "export":
            // export — the Export… button: the Share export, on this plan's page
            if let state = model.state, let sheet = state.diagramSheet { Exporting.exportDiagram(sheet.id, state: state) }
        case "png":
            // png <path> — the Export… page as a picture, without the window
            guard let path = args.first, let engine = model.engine, let sheet = model.state?.diagramSheet else { return }
            let page = FileManager.default.temporaryDirectory.appendingPathComponent("shotlister-dia-\(UUID().uuidString).html")
            guard engine.printPage("diagram", to: page.path,
                                   scope: Engine.ExportScope(scenes: [sheet.id], extra: ["bar=0"])) != nil else { return }
            Printing.render(fromPageAt: page, kind: .diagram) { result in
                try? FileManager.default.removeItem(at: page)
                if case .success(let doc) = result, let first = doc.page(at: 0),
                   let data = Exporting.picture(of: first) {
                    try? data.write(to: URL(fileURLWithPath: path))
                }
            }
        case "update":
            // update {"spread":"line",…} — the picked pieces' fields, as their Details set them
            if let data = args.joined(separator: " ").data(using: .utf8),
               let set = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], !model.selection.isEmpty {
                model.update(model.selection, set)
            }
        case "pickall":
            // pickall — every piece shown in this view, as ⌘A picks
            model.selection = model.plan.els.filter { !$0.hidden && !model.layerLockedIds.contains($0.id) }.map(\.id)
        case "sendlayer":
            // sendlayer <set|plot> [copy] — Send to / Copy to on the pick
            model.sendLayer(model.selection, to: args.first == "set" ? "set" : "plot", copy: args.dropFirst().first == "copy")
        case "setting":
            // setting <key> <value> — a plan setting, as the View menu or the Sun panel sets it
            guard args.count >= 2 else { return }
            let v = args[1]
            if v == "true" || v == "false" { model.setting(args[0], v == "true") }
            else if let n = Double(v) { model.setting(args[0], n) }
            else { model.setting(args[0], v) }
        case "items":
            // items <path.png> — the Items list, drawn to a file: a popover is a
            // window of its own and never in the main window's photograph.
            guard let path = args.first else { return }
            let r = ImageRenderer(content: DiagramItems(model: model, flat: true).padding(4)
                .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark))
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
            }
        case "down": mouse(.leftMouseDown)
        case "drag": mouse(.leftMouseDragged)
        case "up": mouse(.leftMouseUp)
        case "move":
            // A posted move reaches no tracking area; the canvas is told as well,
            // so what goes "under the pointer" (F, C, T, 1–9) knows where it is.
            mouse(.mouseMoved)
            if args.count >= 2, let x = Double(args[0]), let y = Double(args[1]),
               let e = NSEvent.mouseEvent(with: .mouseMoved, location: canvas.convert(CGPoint(x: x, y: y), to: nil),
                                          modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                          clickCount: 0, pressure: 0) {
                canvas.mouseMoved(with: e)
            }
        case "click": mouse(.leftMouseDown); mouse(.leftMouseUp)
        case "dbl": mouse(.leftMouseDown, clicks: 2); mouse(.leftMouseUp, clicks: 2)
        case "key":
            window.makeFirstResponder(canvas)
            let (chars, code): (String, UInt16) = {
                switch args.first ?? "" {
                case "delete": return ("\u{7f}", 51)
                case "escape": return ("\u{1b}", 53)
                case "return": return ("\r", 36)
                case "left": return ("", 123)
                case "right": return ("", 124)
                case "down": return ("", 125)
                case "up": return ("", 126)
                default: return (args.first ?? "", 0)
                }
            }()
            if let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags(1),
                                        timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: window.windowNumber, context: nil,
                                        characters: chars, charactersIgnoringModifiers: chars,
                                        isARepeat: false, keyCode: code) {
                if flags(1).contains(.command) { _ = canvas.performKeyEquivalent(with: e) } else { canvas.keyDown(with: e) }
            }
        case "press":
            // press <delete|escape|return|down|up|letter> [modifier…] — a key the way a
            // hand presses it: through the app, its menus and whatever has
            // the keyboard, not handed to the plan (`key` does that).
            let (chars, code): (String, UInt16) = {
                switch args.first ?? "" {
                case "delete": return ("\u{7f}", 51)
                case "escape": return ("\u{1b}", 53)
                case "return": return ("\r", 36)
                case "down": return (String(UnicodeScalar(UInt16(NSDownArrowFunctionKey))!), 125)
                case "up": return (String(UnicodeScalar(UInt16(NSUpArrowFunctionKey))!), 126)
                default: return (args.first ?? "", 0)
                }
            }()
            if let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags(1),
                                        timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: window.windowNumber, context: nil,
                                        characters: chars, charactersIgnoringModifiers: chars,
                                        isARepeat: false, keyCode: code) {
                NSApp.sendEvent(e)
            }
        case "offer":
            // offer <cast|camera> — the button pressed: its menu opens under it
            // (and waits for a hand — a check photographs it from outside)
            if let view = canvas as? DiagramCanvasView, let tool = args.first.flatMap(DiagramTool.init(rawValue:)) {
                view.offerChoices(tool)
            }
        case "choices", "choose":
            // choices <cast|camera> — the button's menu, as it reads;
            // choose <cast|camera> <item…> — picked from it, as a hand would
            guard let view = canvas as? DiagramCanvasView, let tool = args.first.flatMap(DiagramTool.init(rawValue:)),
                  let menu = view.choices(tool) else { return }
            if verb == "choices" {
                let words = menu.items.map { $0.isSeparatorItem ? "—" : ($0.state == .on ? "✓" : "") + $0.title }
                FileHandle.standardError.write(Data("choices: \(words.joined(separator: " | "))\n".utf8))
                // Where the menu opens: under its button.
                if let spot = model.toolSpots[tool.rawValue] {
                    FileHandle.standardError.write(Data(String(format: "choices at %.0f,%.0f button %.0f,%.0f %.0fx%.0f\n", spot.minX, spot.maxY + 6, spot.minX, spot.minY, spot.width, spot.height).utf8))
                }
            } else {
                let want = args.dropFirst().joined(separator: " ")
                if let item = menu.items.first(where: { $0.title == want || $0.title.hasPrefix(want + "  ") }),
                   let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
            }
        case "focus":
            // focus [away] — who has the keyboard; `away` takes it off the
            // plan first, the way a click in a panel or the toolbar does
            if args.first == "away" { window.makeFirstResponder(nil) }
            let r = window.firstResponder
            FileHandle.standardError.write(Data("focus: \(r.map { String(describing: type(of: $0)) } ?? "none")\(r === canvas ? " (plan)" : "")\n".utf8))
        case "pick":
            // pick <index>[,<index>…] — by place in the stack
            let wanted = (args.first ?? "").split(separator: ",").compactMap { Int($0) }
            model.selection = wanted.compactMap { i in model.plan.els.indices.contains(i) ? model.plan.els[i].id : nil }
        case "grab":
            // grab <corner|rotate|end|curve|reach> <index> <dx> <dy> [modifier]
            guard args.count >= 4, let view = canvas as? DiagramCanvasView,
                  let i = Int(args[1]), let dx = Double(args[2]), let dy = Double(args[3]),
                  let p = view.handlePoint(kind: args[0], index: i) else {
                FileHandle.standardError.write(Data("drive: no such handle \(args)\n".utf8)); return
            }
            pull(from: p, dx: dx, dy: dy, flags: flags(4))
        case "hold":
            // hold <corner|rotate|reach|turn> <index> <dx> <dy> — a handle
            // taken and dragged, the mouse still down: what shows mid-drag
            guard args.count >= 4, let view = canvas as? DiagramCanvasView,
                  let i = Int(args[1]), let dx = Double(args[2]), let dy = Double(args[3]),
                  let p = view.handlePoint(kind: args[0], index: i) else {
                FileHandle.standardError.write(Data("drive: no such handle \(args)\n".utf8)); return
            }
            post(.leftMouseDown, p)
            for k in 1...8 {
                let f = CGFloat(k) / 8
                post(.leftMouseDragged, CGPoint(x: p.x + CGFloat(dx) * f, y: p.y + CGFloat(dy) * f))
            }
        case "beamsall":
            // beamsall <on|off> — the View menu's Light Beams, for the whole film
            model.settingEverywhere("beams", args.first != "off")
        case "live":
            // live — every piece as it stands on screen right now, mid-drag included
            let out = model.shown.els.map { e -> String in
                let now = e.at(beat: model.beat)
                return String(format: "live: %@ at %.2f,%.2f rot %.0f", e.kind, now.x, now.y, now.rot)
            }.joined(separator: "\n")
            FileHandle.standardError.write(Data((out + "\n").utf8))
        case "layers":
            // layers — open the Layers sidebar and print it, top of the stack
            // first; a rider follows its piece, marked `>`
            model.showingLayers = true
            let riding = DiagramRigs.riding(model.shown.els)
            let names = model.shown.els.reversed().filter { !riding.contains($0.id) }.flatMap { e in
                [DiagramItems.name(e, model)] + DiagramRigs.riders(of: e.id, in: model.shown.els).map {
                    String(repeating: ">", count: $0.1) + DiagramItems.name($0.0, model)
                }
            }
            FileHandle.standardError.write(Data(("layers: " + names.joined(separator: " | ") + "\n").utf8))
        case "exact":
            // exact — every piece to the ten-thousandth of a metre, a line's
            // length as Details reads it, and whether it sits on the grid
            // (its ends; a body's edges when square, a lamp's middle)
            let step = model.snapStep
            func on(_ v: Double) -> Bool { abs(v / step - (v / step).rounded()) < 1e-3 }
            var out = String(format: "exact: step %.4f units %@ snap %@ scale %.1f\n", step, model.settings.units,
                             model.settings.snap ? "on" : "off", Double(model.scale))
            for e in model.plan.els {
                let now = e.at(beat: model.beat)
                out += String(format: "  %@ %@ at %.4f,%.4f rot %.2f", e.kind, e.id, now.x, now.y, now.rot)
                if e.isWall {
                    // A wall: its ends, its whole length, whether every corner
                    // is on the grid, then each corner and each stretch as the
                    // plan shows it.
                    let st = e.stretches
                    let len = st.count == 1 ? Double(hypot(st[0].1.x - st[0].0.x, st[0].1.y - st[0].0.y))
                        : (0..<st.count).reduce(0) { $0 + model.shownLength(e, $1) }
                    out += String(format: " to %.4f,%.4f len %.4f \"%@\" grid %@", e.x2, e.y2, len, model.length(len),
                                  e.corners.allSatisfy { on(Double($0.x)) && on(Double($0.y)) } ? "yes" : "no")
                    out += " corners \(e.corners.count)\(e.isClosed ? " closed" : "") ["
                        + e.corners.map { String(format: "%.4f,%.4f", $0.x, $0.y) }.joined(separator: " ") + "]"
                    out += " lengths [" + (0..<st.count).map { model.length(model.shownLength(e, $0)) }.joined(separator: "|") + "]"
                    if let r = e.round, !r.isEmpty { out += " round \(r)" }
                    out += String(format: " thick %.4f", e.thick)
                } else if e.isLine {
                    let len = hypot(e.x2 - e.x, e.y2 - e.y)
                    out += String(format: " to %.4f,%.4f len %.4f \"%@\" grid %@", e.x2, e.y2, len, model.length(len),
                                  [e.x, e.y, e.x2, e.y2].allSatisfy(on) ? "yes" : "no")
                } else if !e.isPolyline {
                    let (w, h) = e.footprint(at: model.beat)
                    out += String(format: " size %.4fx%.4f", w, h)
                    if e.sym == DiagramFrames.sym { out += String(format: " tilt %.0f", e.tilt) }
                    let quarter = now.rot.truncatingRemainder(dividingBy: 90)
                    if DiagramCanvasView.faces(e) { out += " grid \(on(now.x) && on(now.y) ? "yes" : "no")" }
                    else if abs(quarter) < 1e-6 || abs(abs(quarter) - 90) < 1e-6 {
                        let (bw, bh) = abs(quarter) < 1e-6 && Int((now.rot / 90).rounded()) % 2 == 0 ? (w, h) : (h, w)
                        out += " edges \([now.x - bw / 2, now.x + bw / 2, now.y - bh / 2, now.y + bh / 2].allSatisfy(on) ? "yes" : "no")"
                    }
                }
                if !e.group.isEmpty { out += " group \(e.group) \"\(e.group_name ?? "")\"" }
                if model.selection.contains(e.id) { out += " [picked]" }
                out += "\n"
            }
            FileHandle.standardError.write(Data(out.utf8))
        case "length":
            // length <text…> — typed into Details' Length for the picked wall,
            // as the field reads it; `parse <text…>` only prints what it reads
            let text = args.joined(separator: " ")
            let read = LengthField.parse(text, metric: model.settings.units == "m")
            FileHandle.standardError.write(Data(String(format: "length: \"%@\" reads %.4f m\n", text, read ?? -1).utf8))
            if let read, let e = model.picked.first, e.isLine { model.setWallLength(e, read) }
        case "parse":
            let text = args.joined(separator: " ")
            let read = LengthField.parse(text, metric: model.settings.units == "m")
            FileHandle.standardError.write(Data(String(format: "parse: \"%@\" reads %.4f m %@\n", text, read ?? -1, model.length(read ?? 0)).utf8))
        case "history":
            // history — how many steps undo holds, and what the next takes back
            if let h = model.engine?.history() {
                FileHandle.standardError.write(Data("history: depth \(h.depth) undo \"\(h.undoLabel)\"\n".utf8))
            }
        case "handles":
            // handles — the pick's handles on screen, and its middle
            if let view = canvas as? DiagramCanvasView {
                let kinds = ["rotate", "reach", "turn", "tilt", "corner", "end", "curve", "wallcorner", "addcorner", "extend", "hin", "hout"]
                var out = "handles:"
                for k in kinds { for i in 0..<8 { if let p = view.handlePoint(kind: k, index: i) { out += String(format: " %@%d=%.0f,%.0f", k, i, p.x, p.y) } } }
                if let id = model.selection.first, let c = view.pointOf(id) { out += String(format: " middle=%.0f,%.0f", c.x, c.y) }
                FileHandle.standardError.write(Data((out + "\n").utf8))
            }
        case "pickkind":
            // pickkind <kind> — the first piece of that kind in the stack;
            // `frame` a frame, `lamp` a lamp that is not one
            let want = args.first ?? ""
            let found = model.plan.els.first { e in
                switch want {
                case "frame": return e.kind == "light" && e.sym == DiagramFrames.sym
                case "lamp": return e.kind == "light" && e.sym != DiagramFrames.sym && DiagramMarks.isLamp(e, model)
                default: return e.kind == want
                }
            }
            model.selection = found.map { [$0.id] } ?? []
        case "corner":
            // corner <i> — one corner of the picked wall picked on its own
            model.pickedCorner = args.first.flatMap(Int.init)
        case "stretch":
            // stretch <i> — one stretch of the picked wall picked, for its length
            model.pickedStretch = args.first.flatMap(Int.init)
        case "wallact":
            // wallact break|curve|deletecorner|join — the wall's own actions
            switch args.first {
            case "break": model.breakCorner()
            case "curve": model.roundCorner()
            case "deletecorner": model.removeCorner()
            case "join": model.joinWalls()
            case "smooth": model.smoothCorner()
            default: break
            }
        case "thick":
            // thick <0-4> — the action bar's five thicknesses, thinnest first
            if let i = args.first.flatMap(Int.init), let e = model.picked.first, e.isWall,
               model.wallThicknesses.indices.contains(i) { model.update([e.id], ["thick": model.wallThicknesses[i]]) }
        case "place":
            // place <x…> / <y…> — typed into Details' X or Y for the pick
            // (`place x 12' 6"`); a wall's picked corner, else the piece
            guard args.count >= 2, let e = model.picked.first else { return }
            let text = args.dropFirst().joined(separator: " ")
            guard let v = LengthField.parse(text, metric: model.settings.units == "m") else { return }
            let signed = text.hasPrefix("-") ? -v : v
            if e.isWall, let i = model.pickedCorner, i < e.corners.count {
                let c = e.corners[i]
                let to = args[0] == "x" ? CGPoint(x: signed, y: c.y) : CGPoint(x: c.x, y: signed)
                model.edit(model.wallOp("wall_corner", e, ["corner": i, "x": to.x, "y": to.y]))
            } else {
                let now = e.at(beat: model.beat)
                model.place(e, at: args[0] == "x" ? CGPoint(x: signed, y: now.y) : CGPoint(x: now.x, y: signed))
            }
        case "group": model.group()
        case "ungroup": model.ungroup()
        case "groups":
            // groups — every group, its name and how many pieces
            var seen: [String] = []
            for e in model.plan.els where !e.group.isEmpty && !seen.contains(e.group) { seen.append(e.group) }
            let said = seen.map { g in "\(model.members(ofGroup: g).first?.group_name ?? "?")=\(model.members(ofGroup: g).count)" }
            FileHandle.standardError.write(Data(("groups: " + said.joined(separator: " ") + "\n").utf8))
        case "renamegroup":
            // renamegroup <index> <name…> — the group of the piece at that place in the stack
            if let i = args.first.flatMap(Int.init), model.plan.els.indices.contains(i) {
                model.renameGroup(model.plan.els[i].group, args.dropFirst().joined(separator: " "))
            }
        case "regroup":
            // regroup <index> <index|none> — a piece into the group of another, or out of any
            if args.count == 2, let i = Int(args[0]), model.plan.els.indices.contains(i) {
                let into = Int(args[1]).flatMap { model.plan.els.indices.contains($0) ? model.plan.els[$0].group : nil } ?? ""
                model.regroup([model.plan.els[i].id], into: into)
            }
        case "restack":
            // restack <kind> <above|below> <kind> — the last piece of one kind dragged over or under the last of another
            guard args.count >= 3, let a = model.plan.els.last(where: { $0.kind == args[0] }),
                  let b = model.plan.els.last(where: { $0.kind == args[2] }) else { return }
            model.restack([a.id], next: b.id, above: args[1] == "above")
        case "gear":
            print("gear: " + DiagramGear.text(model).replacingOccurrences(of: "\n", with: " | "))
        case "calibrate":
            // calibrate <length> — Set Scale on the first picture, answered with this length
            model.calibrating = model.plan.els.last { $0.kind == "image" }?.id
            model.calibrateAnswer = args.joined(separator: " ")
        case "aimat":
            // aimat <kind> — drag the picked thing's turning knob onto the last piece of that kind
            guard let view = canvas as? DiagramCanvasView, let kind = args.first,
                  let target = model.plan.els.last(where: { $0.kind == kind }),
                  let p = view.handlePoint(kind: "rotate", index: 0),
                  let t = view.pointOf(target.id) else { return }
            pull(from: p, dx: t.x - p.x, dy: t.y - p.y, flags: [])
        case "knobto":
            // knobto <dx> <dy> [kind] [modifier] — drag the pick's turning knob
            // (`rotate`, or `turn` for the box round a wall, several or a
            // group) to dx, dy points off the middle of the first picked piece
            // (for `turn`, off the point the pick turns about)
            let turn = args.count > 2 && args[2] == "turn"
            guard args.count >= 2, let view = canvas as? DiagramCanvasView, let id = model.selection.first,
                  let dx = Double(args[0]), let dy = Double(args[1]),
                  let c = turn ? model.toView(model.pivot(), size: view.bounds.size) : view.pointOf(id),
                  let k = view.handlePoint(kind: turn ? "turn" : "rotate", index: 0) else {
                FileHandle.standardError.write(Data("drive: no knob\n".utf8)); return
            }
            pull(from: k, dx: c.x + dx - k.x, dy: c.y + dy - k.y, flags: flags(2))
        case "drawto":
            // drawto <from> <to> — with a line tool armed, drag from one piece's middle to another's;
            // each an index in the stack or a kind (the last of that kind)
            func piece(_ s: String) -> DiagramEl? {
                if let i = Int(s) { return model.plan.els.indices.contains(i) ? model.plan.els[i] : nil }
                return model.plan.els.last { $0.kind == s }
            }
            guard args.count >= 2, let view = canvas as? DiagramCanvasView, let i = piece(args[0]), let j = piece(args[1]),
                  let a = view.pointOf(i.id), let b = view.pointOf(j.id) else { return }
            pull(from: a, dx: b.x - a.x, dy: b.y - a.y, flags: [])
        case "endto":
            // endto <0|1> <index|kind> | <0|1> <x> <y> — drag the picked arrow's end onto a piece's middle, or to a point
            guard args.count >= 2, let view = canvas as? DiagramCanvasView, let end = Int(args[0]),
                  let p = view.handlePoint(kind: "end", index: end) else { return }
            var to: CGPoint?
            if args.count >= 3, let x = Double(args[1]), let y = Double(args[2]) { to = CGPoint(x: x, y: y) }
            else if let j = Int(args[1]) { to = model.plan.els.indices.contains(j) ? view.pointOf(model.plan.els[j].id) : nil }
            else if let t = model.plan.els.last(where: { $0.kind == args[1] }) { to = view.pointOf(t.id) }
            guard let t = to else { return }
            pull(from: p, dx: t.x - p.x, dy: t.y - p.y, flags: [])
        case "haul":
            // haul <dx> <dy> [modifier] — drag the first picked thing from where it stands
            guard args.count >= 2, let view = canvas as? DiagramCanvasView, let id = model.selection.first,
                  let dx = Double(args[0]), let dy = Double(args[1]), let p = view.pointOf(id) else { return }
            pull(from: p, dx: dx, dy: dy, flags: flags(2))
        case "trip":
            // trip <to|from|off> — the right-click menu's Add Move To / Add Move From, on the first
            // picked thing (after or before its picked step); `off` takes away its picked step, else its last
            guard let id = model.selection.first else { return }
            // …and `turnto` / `turnfrom`, its Add Turn To / Add Turn From.
            switch args.first {
            case "off":
                if model.stepPick != nil { model.removePickedStep() }
                else if let e = model.el(id), let i = e.spots.lastIndex(where: { !$0.home }) { model.removeStep(id, i) }
            case "turnto", "turnfrom": model.addTurn(id, from: args.first == "turnfrom")
            default: model.addMove(id, from: args.first == "from")
            }
        case "stepbeat":
            // stepbeat <n> — the picked step's Beat menu: on beat n, 0 for none
            guard let (e, i, _) = model.stepPick, let n = args.first.flatMap(Int.init) else { return }
            model.edit(model.stepOp(e, i, beat: n))
        case "haultrip":
            // haultrip <dx> <dy> [step] — drag the first picked thing's step ghost: the one at that
            // letter-order index, else the picked one, else its last
            guard args.count >= 2, let view = canvas as? DiagramCanvasView, let id = model.selection.first,
                  let dx = Double(args[0]), let dy = Double(args[1]),
                  let p = view.stepPointOf(id, args.count > 2 ? Int(args[2]) : nil) else { return }
            pull(from: p, dx: dx, dy: dy, flags: [])
        case "clicktrip":
            // clicktrip <index> [step] — click a step's ghost (its last, if not said) of the piece at that place in the stack
            guard let view = canvas as? DiagramCanvasView, let i = args.first.flatMap(Int.init),
                  model.plan.els.indices.contains(i),
                  let p = view.stepPointOf(model.plan.els[i].id, args.count > 1 ? Int(args[1]) : nil) else {
                FileHandle.standardError.write(Data("drive: no ghost \(args)\n".utf8)); return
            }
            post(.leftMouseDown, p); post(.leftMouseUp, p)
        case "zoom":
            // zoom <factor> — the view closer (or further), about its middle
            if let f = args.first.flatMap(Double.init) { model.zoom(by: CGFloat(f), size: canvas.bounds.size); canvas.needsDisplay = true }
        case "clickon":
            // clickon <index> — click the piece at that place in the stack, where it stands
            guard let view = canvas as? DiagramCanvasView, let i = args.first.flatMap(Int.init),
                  model.plan.els.indices.contains(i), let p = view.pointOf(model.plan.els[i].id) else { return }
            // …with ⌘ or ⇧ held, when named after it
            post(.leftMouseDown, p, flags: flags(1)); post(.leftMouseUp, p, flags: flags(1))
        case "showall": model.openDetails()
        case "link":
            // link <n> — the first picked camera stands for the scene's nth shot
            if let n = args.first.flatMap(Int.init), let id = model.selection.first {
                let rows = model.state?.rows(of: model.state?.diagramScene) ?? []
                if rows.indices.contains(n) { model.update([id], ["shot": rows[n].shot]) }
            }
        case "pan":
            // pan <dx> <dy> — the view slides, in canvas points
            if args.count >= 2, let dx = Double(args[0]), let dy = Double(args[1]) {
                model.pan(by: CGPoint(x: dx, y: dy))
            }
        case "align": if let to = args.first { model.align(to) }
        case "showinlist":
            // The picked camera's Show in Shot List, then where it landed.
            if let e = model.picked.first(where: { !$0.shot.isEmpty }) {
                model.showInShotList(e.shot)
                let row = model.state?.view?.allRows.first { $0.id == model.state?.cursorShot }
                FileHandle.standardError.write(Data(
                    "shotlist: place \(model.state?.sideTab.rawValue ?? "?") row \(row?.number ?? "none") for \(e.shot)\n".utf8))
            }
        case "keys":
            // keys <char|escape> [command] [control] … — a key pressed on the
            // window the way the keyboard sends it, so the Diagram's own keys
            // (⌃⌘1–3, ⌘F, Esc) are caught where they really are
            let (chars, code): (String, UInt16) = {
                switch args.first ?? "" {
                case "escape": return ("\u{1b}", 53)
                case "1": return ("1", 18)
                case "2": return ("2", 19)
                case "3": return ("3", 20)
                case "f": return ("f", 3)
                default: return (args.first ?? "", 0)
                }
            }()
            if let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags(1),
                                        timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: window.windowNumber, context: nil,
                                        characters: chars, charactersIgnoringModifiers: chars,
                                        isARepeat: false, keyCode: code) {
                NSApp.sendEvent(e)
            }
        case "showkind":
            // showkind <cameras|cast|lights|…|all> <on|off> — a switch in the Show panel
            model.showingShow = true
            if args.first == "all" { model.unseenKinds = args.last == "off" ? Set(DiagramShow.kinds.map(\.key)) : [] }
            else if let k = args.first { model.setShown(k, args.last != "off") }
        case "act":
            // act <colour|size|lens|beam|dim|duplicate|delete|lock|hide|frame> [value] — the action bar, on what is picked
            guard let e = model.shownPicked.first else { return }
            let v = args.count > 1 ? args[1] : ""
            switch args.first ?? "" {
            case "colour": model.update(model.selection, ["color": v == "none" ? "" : "#" + v.uppercased()])
            case "size":
                switch DiagramActions.sizes(e, model) {
                case .points: model.update([e.id], ["size": Double(v) ?? e.size])
                case .percent(_, let sym): model.update([e.id], DiagramActions.scaled(sym, Int(v) ?? 100))
                case .step: model.update([e.id], v == "smaller" ? ["w": e.w * 0.8, "h": e.h * 0.8] : ["w": e.w * 1.25, "h": e.h * 1.25])
                case nil: break
                }
            case "lens": DiagramActions.setLens(e, Int(v) ?? 35, model: model, state: model.state)
            case "beam": model.update([e.id], ["beam_on": !e.beam_on])
            case "dim": model.update([e.id], ["dim": Double(v) ?? 100])
            case "duplicate": model.duplicate()
            case "delete": model.remove(model.selection)
            case "lock": model.update(model.selection, ["locked": !e.locked])
            case "hide": model.update(model.selection, ["hidden": true]); model.selection = []
            case "frame": model.update([e.id], ["frame_on": !(e.frame_on ?? false)])
            case "body": model.swap([e.id], to: v)
            // act backdrop <0…1> — the plan's paper, as View → Backdrop… sets it
            case "backdrop": model.backdrop = min(max(Double(v) ?? DiagramModel.defaultBackdrop, 0), 1)
            // act swapping — the library open to swap the picked piece, as
            // right-click's Swap… opens it (design/26)
            case "swapping": model.swapping = e.id
            default: break
            }
        case "chrome":
            // chrome — what is open, what is hidden, what the action bar offers
            let shapes = model.shown.shapes
            var out = "chrome: layers \(model.showingLayers) details \(model.showingDetails) gear \(model.showingGear)"
            out += " show \(model.showingShow) presenting \(model.presenting) fitted \(model.fitted)"
            out += " unseen [\(model.unseenKinds.sorted().joined(separator: ","))]"
            out += " shapes \(model.seen(shapes).count)/\(shapes.count)"
            out += String(format: " scale %.1f", Double(model.scale))
            // design/24's zones: the left sidebar's tab, the right's, the favorites
            out += " tab \(model.sideTab) right \(model.rightTab ?? "-") favorites \(model.showingFavorites)"
            if !model.selection.isEmpty { out += " bar \"\(DiagramActionBar.pickedName(model))\" fold \(model.barLevel)" }
            if let e = model.shownPicked.first, model.shownPicked.count == 1 {
                let bar = DiagramActionBar(state: model.state ?? ShellState.shared, model: model)
                out += " actions [\(bar.ownActions(e).joined(separator: ","))] picked \(e.kind)"
                out += String(format: " colour %@ size %.2fx%.2f pt %.0f lens %.0f focal %.0f beam %@ dim %.0f locked %@ hidden %@",
                              e.color.isEmpty ? "-" : e.color, e.w, e.h, e.size, e.lens, e.focal ?? 0,
                              e.beam_on ? "on" : "off", e.dim ?? -1, e.locked ? "yes" : "no", e.hidden ? "yes" : "no")
            }
            // Last on the line, so the words checks read whole stay whole.
            let paper = model.lit(DiagramInk.color("paper", dark: false)!).usingColorSpace(.sRGB)!
            out += String(format: " backdrop %.2f paper #%02X%02X%02X", model.backdrop,
                          Int((paper.redComponent * 255).rounded()), Int((paper.greenComponent * 255).rounded()), Int((paper.blueComponent * 255).rounded()))
            FileHandle.standardError.write(Data((out + "\n").utf8))
        case "gels":
            // gels <id>… | gels none — the picked pieces' gels, as the Gels field sets them
            model.setGels(model.selection, args.first == "none" ? [] : args)
        case "frameset":
            // frameset <field> <value> — a field on the picked pieces: material, pipe, grid, tilt, tall, h
            if args.count >= 2 { model.update(model.selection, [args[0]: Double(args[1]) ?? args[1]]) }
        case "beams":
            // beams — every light and frame's beams as drawn: how many, their inks, how far they reach
            var out = ""
            for e in model.plan.els where e.kind == "light" {
                let mine = model.plan.shapes.filter { $0.e == e.id && $0.p == "beam" }
                var far = 0.0
                for b in mine {
                    let d = b.d ?? []
                    var i = 0
                    while i < d.count {
                        let op = Int(d[i]), n = op == 2 ? 6 : (op == 3 ? 0 : 2)
                        if n > 0, i + n < d.count { far = max(far, hypot(d[i + n - 1] - e.x, d[i + n] - e.y)) }
                        i += n + 1
                    }
                }
                // (Its gels are the name's second line; read as " / ".)
                let label = (model.plan.shapes.first { $0.e == e.id && $0.p == "label" }?.tx ?? "")
                    .replacingOccurrences(of: "\n", with: " / ")
                // Picked: its outline with Beams off, and its spread/dimmer note.
                let lines = model.plan.shapes.filter { $0.e == e.id && $0.p == "beamline" }.count
                let note = model.plan.shapes.first { $0.e == e.id && $0.p == "beamnote" }?.tx ?? ""
                out += String(format: "beams: %@ %@ n %d far %.2f fills %@ label \"%@\" lines %d note \"%@\"\n", e.sym, e.id, mine.count, far,
                              mine.map { $0.f ?? "" }.joined(separator: ","), label, lines, note)
            }
            FileHandle.standardError.write(Data(out.utf8))
        case "sunwatch":
            // sunwatch <dx> <dy> — haul the first picked thing in eight steps
            // and print where the painted sun stands after each one
            guard args.count >= 2, let view = canvas as? DiagramCanvasView, let id = model.selection.first,
                  let dx = Double(args[0]), let dy = Double(args[1]), let p = view.pointOf(id) else { return }
            func say(_ step: String) {
                let at = sunDisc(model, size: view.bounds.size).map { String(format: "%.1f,%.1f", $0.x, $0.y) } ?? "none"
                FileHandle.standardError.write(Data("sunwatch: \(step) sun \(at)\n".utf8))
            }
            say("before")
            post(.leftMouseDown, p)
            for i in 1...8 {
                let k = CGFloat(i) / 8
                post(.leftMouseDragged, CGPoint(x: p.x + CGFloat(dx) * k, y: p.y + CGFloat(dy) * k))
                say("step \(i)")
            }
            post(.leftMouseUp, CGPoint(x: p.x + CGFloat(dx), y: p.y + CGFloat(dy)))
            say("after")
        case "levels": FileHandle.standardError.write(Data(DiagramLevels.report(model).utf8))
        case "settext": if let id = model.typing?.el ?? model.selection.first { model.typing = nil; model.update([id], ["text": args.joined(separator: " ")]) }
        case "readout":
            // readout — what the label by the pointer says now, mid-drag
            let view = canvas as? DiagramCanvasView
            let said = view.flatMap { v in v.readout(model, v.bounds.size)?.0 } ?? "none"
            FileHandle.standardError.write(Data("readout: \(said)\n".utf8))
        case "menuat":
            // menuat <x> <y> — the right-click menu there, read, not opened
            guard args.count >= 2, let x = Double(args[0]), let y = Double(args[1]),
                  let e = NSEvent.mouseEvent(with: .rightMouseDown, location: canvas.convert(CGPoint(x: x, y: y), to: nil),
                                             modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                             clickCount: 1, pressure: 1) else { return }
            let items = canvas.menu(for: e)?.items.map(\.title).filter { !$0.isEmpty } ?? []
            FileHandle.standardError.write(Data("menu: \(items.joined(separator: " | "))\n".utf8))
        case "snap":
            // snap <path> — the window as it is now, popovers and all, mid-run
            guard let path = args.first, let frame = window.contentView?.superview ?? window.contentView,
                  let data = Launch.picture(of: frame, in: window) else { return }
            try? data.write(to: URL(fileURLWithPath: path))
            FileHandle.standardError.write(Data("snap: \(path)\n".utf8))
        case "op":
            // op <json> — one of the engine's edits, as the app sends it (no ";" inside)
            if let data = args.joined(separator: " ").data(using: .utf8),
               let op = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let made = model.edit(op)
                FileHandle.standardError.write(Data("op: \(op["op"] ?? "?") made \(made)\n".utf8))
            } else {
                FileHandle.standardError.write(Data("op: unreadable\n".utf8))
            }
        case "pickids":
            // pickids <id|sym,…> — those pieces picked, by id or by what they are
            let want = Set((args.first ?? "").split(separator: ",").map(String.init))
            model.selection = model.plan.els.filter { want.contains($0.id) || want.contains($0.sym) }.map(\.id)
        case "viewpanel":
            // viewpanel — View's panel opened, as a click on View does
            model.viewOpen = true
        case "viewclick":
            // viewclick <x> <y> — a click inside the open View panel, from its top left
            guard args.count >= 2, let x = Double(args[0]), let y = Double(args[1]),
                  let pop = NSApp.windows.first(where: { $0 !== window && $0.isVisible && String(describing: type(of: $0)).contains("Popover") }),
                  let content = pop.contentView else {
                FileHandle.standardError.write(Data("viewclick: no panel\n".utf8))
                return
            }
            let at = CGPoint(x: x, y: content.bounds.height - y)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let e = NSEvent.mouseEvent(with: type, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: pop.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                    NSApp.sendEvent(e)
                }
            }
        case "viewsays":
            // viewsays — whether View's panel is open, and the switches it holds
            let pop = NSApp.windows.contains { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }
            let s = model.settings
            FileHandle.standardError.write(Data("viewsays: open=\(model.viewOpen) shown=\(pop) measures=\(s.measures) grid=\(s.grid) cones=\(s.cones)\n".utf8))
        case "moremenu":
            // moremenu — the pick's one menu (More and right-click), read, with its submenus
            func titles(_ menu: NSMenu, _ depth: Int) -> [String] {
                menu.items.flatMap { i -> [String] in
                    if i.isSeparatorItem { return [String(repeating: "  ", count: depth) + "—"] }
                    let me = String(repeating: "  ", count: depth) + (i.state == .on ? "✓" : "") + i.title
                    return [me] + (i.submenu.map { titles($0, depth + 1) } ?? [])
                }
            }
            FileHandle.standardError.write(Data(("moremenu:\n" + titles(DiagramMenu.picked(model), 1).joined(separator: "\n") + "\n").utf8))
        case "bar":
            // bar — what the foot bar shows for the pick: its title, settings and verbs
            let l = DiagramActionBar.layout(DiagramPick.of(model.shownPicked, model), model)
            FileHandle.standardError.write(Data("bar: title \(l.title ?? "-") values [\(l.values.joined(separator: ","))] actions [\(l.actions.joined(separator: ","))] details \(model.detailsShown)\n".utf8))
        case "hovered":
            // hovered — what the pointer is over, outlined blue
            let id = (canvas as? DiagramCanvasView)?.hovered
            FileHandle.standardError.write(Data("hovered: \(id.flatMap { model.el($0)?.kind } ?? "none")\n".utf8))
        case "report":
            var out = "drive: \(model.plan.els.count) els; picked \(model.selection.count); tool \(model.tool.rawValue); beat \(model.beat)\n"
            // How many wall lengths the plan writes, and what of a wall is picked.
            out += "walls: lengths \(model.plan.shapes.filter { $0.p == "dim" && $0.k == "text" }.count) corner \(model.pickedCorner ?? -1) stretch \(model.pickedStretch ?? -1)\n"
            let sun = model.plan.sun
            out += String(format: "sun: on %@ north %.0f time %@ rise %@ set %@ rays %@ light %d\n", model.settings.sun ? "yes" : "no", model.settings.north,
                          sun?.minutes.map { DiagramSunPanel.clock($0) } ?? "-", sun?.rise.map { DiagramSunPanel.clock($0) } ?? "-",
                          sun?.set.map { DiagramSunPanel.clock($0) } ?? "-", model.settings.sun_rays ? "yes" : "no",
                          model.plan.shapes.filter { $0.p == "sunlight" }.count)
            if let view = canvas as? DiagramCanvasView {
                // How the plan is turned, where the compass stands, and where
                // the first wall's two ends land on screen.
                let size = view.bounds.size
                let c = view.compassSpot.map { String(format: "%.0f,%.0f", $0.centre.x, $0.centre.y) } ?? "none"
                var ends = "-"
                if let w = model.plan.els.first(where: { $0.kind == "wall" }) {
                    let a = model.toView(CGPoint(x: w.x, y: w.y), size: size), b = model.toView(CGPoint(x: w.x2, y: w.y2), size: size)
                    ends = String(format: "%.0f,%.0f %.0f,%.0f", a.x, a.y, b.x, b.y)
                }
                out += String(format: "view: turn %.0f compass %@ wall %@\n", Double(model.turn) * 180 / .pi, c, ends)
                let disc = sunDisc(model, size: size).map { String(format: "%.0f,%.0f", $0.x, $0.y) } ?? "none"
                out += String(format: "sundisc: at %@ canvas %.0fx%.0f right %.0f\n", disc, size.width, size.height, Double(model.rightCover))
            }
            out += "pop: none; panel \(model.detailsShown ? "shown" : "hidden")\n"
            for e in model.plan.els {
                let now = e.at(beat: model.beat)
                out += String(format: "  %@ %@ at %.2f,%.2f rot %.0f", e.kind, e.id, now.x, now.y, now.rot)
                if e.kind == "wall" || e.isLine { out += String(format: " to %.2f,%.2f", e.x2, e.y2) }
                if e.isWall || e.isPath { out += " corners \(e.corners.count)\(e.isClosed ? " closed" : "")" }
                if e.isWall || e.isPath { out += " smooth \((0..<e.corners.count).filter { e.isSmooth($0) })\(e.isPath ? " path" : "")\(e.isFilled ? " filled" : "")" }
                if !e.shot.isEmpty { out += " shot \(e.shot)" }
                if e.hasSteps { out += " beats \(e.spots.filter { !$0.home && $0.beat > 0 }.map(\.beat).sorted())" }
                if e.kind != "wall" && !e.isLine && !e.isPolyline { out += String(format: " size %.2fx%.2f", e.w, e.h) }
                if !e.text.isEmpty { out += " text \"\(e.text)\"" }
                if !e.group.isEmpty { out += " group \(e.group)" }
                if e.kind == "image", !e.role.isEmpty { out += " role \(e.role)" }
                if !e.aim.isEmpty { out += " aim \(model.el(e.aim)?.kind ?? "?")" }
                if let on = e.rig_on, !on.isEmpty { out += " on \(model.el(on)?.kind ?? "?")" }
                if e.kind == "light" { out += " sym \(e.sym)" }
                if e.layer == "set" { out += " in set" }
                if e.kind == "camera" { out += " body \(model.body(e)?.id ?? "-")" }
                if let d = model.plan.shapes.first(where: { $0.e == e.id && $0.p == "aim" && $0.k == "text" }), let t = d.tx {
                    out += " distance \"\(t)\""
                }
                if e.kind == "arrow" {
                    let on = { (id: String?) in id.flatMap { $0.isEmpty ? nil : model.el($0)?.kind } ?? "-" }
                    out += " pins \(on(e.start_on)),\(on(e.end_on))"
                }
                if e.isRuler {
                    let on = { (id: String) in id.isEmpty ? "-" : (model.el(id)?.kind ?? "?") }
                    out += " locks \((e.pins ?? []).map(on).joined(separator: ","))"
                }
                if !e.gels.isEmpty { out += " gels \(e.gels.joined(separator: ","))" }
                if e.sym == DiagramFrames.sym {
                    out += String(format: " material %@ pipe %@ grid %.0f tilt %.0f tall %.2f", e.material.isEmpty ? "-" : e.material,
                                  e.pipe.isEmpty ? "-" : e.pipe, e.grid, e.tilt, e.tall)
                }
                for t in e.spots where e.hasSteps && !t.home {
                    // `beat#n`, not `beat n`: the checks read a position as `at x,y`.
                    out += String(format: " step %@%@ %.2f,%.2f rot %.0f beat#%d", t.letter, t.turn ? " turn" : "", t.x, t.y, t.rot, t.beat)
                }
                if model.selection.contains(e.id) { out += model.stepPick?.e.id == e.id ? " [picked \(model.stepPick!.spot.letter)]" : " [picked]" }
                out += "\n"
            }
            FileHandle.standardError.write(Data(out.utf8))
        default:
            if PhotoDrive.perform(verb, args, model, post: { type, p in post(type, p) }) { return }
            if DiagramShotsDrive.perform(verb, args, model, pull: { p, dx, dy in pull(from: p, dx: dx, dy: dy) }) { return }
            FileHandle.standardError.write(Data("drive: what is \(verb)?\n".utf8))
        }
    }
}

/// **Everything on the plan, in a list** — OpenShotDesigner's layers, kept
/// small: the top of the stack first, a click picks it, and each row can be
/// hidden or locked. The one way back to something hidden, and the easy way
/// to something too small to click.
struct DiagramItems: View {
    @ObservedObject var model: DiagramModel
    /// Laid out whole rather than scrolled — for drawing it to a file.
    var flat = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        VStack(alignment: .leading, spacing: 0) {
            Text("Items").sans(Brand.Size.title, weight: .bold).padding(.horizontal, 14).padding(.vertical, 10)
            Rectangle().fill(Brand.rule(dark)).frame(height: 1)
            if model.plan.els.isEmpty {
                Text("Nothing on the plan").sans(Brand.Size.body).foregroundStyle(Brand.ink2(dark)).padding(14)
            } else if flat {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.plan.els.reversed()) { e in row(e, dark) }
                }
                .padding(.vertical, 4)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.plan.els.reversed()) { e in row(e, dark) }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 420)
            }
        }
        .frame(width: 300)
    }

    private func row(_ e: DiagramEl, _ dark: Bool) -> some View {
        let picked = model.selection.contains(e.id)
        let name = DiagramItems.name(e, model)
        let kind = DiagramItems.kindWord(e.kind)
        return HStack(spacing: 8) {
            Text(name).sans(Brand.Size.body, weight: picked ? .semibold : .regular)
                .foregroundStyle(e.hidden ? Brand.ink3(dark) : Brand.ink(dark))
                .lineLimit(1)
            if name != kind {
                Text(kind).sans(Brand.Size.small).foregroundStyle(Brand.ink2(dark))
            }
            Spacer(minLength: 4)
            Button(e.hidden ? "Show" : "Hide") { model.update([e.id], ["hidden": !e.hidden]) }
                .buttonStyle(.rowAction)
            Button(e.locked ? "Unlock" : "Lock") { model.update([e.id], ["locked": !e.locked]) }
                .buttonStyle(.rowAction)
        }
        .padding(.horizontal, 12).frame(height: 30)
        .background(picked ? Brand.glassOn(dark) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { model.selection = [e.id] }
    }

    static func kindWord(_ kind: String) -> String {
        switch kind {
        case "set": return "Set Piece"
        case "cast": return "Cast"
        case "stroke": return "Drawing"
        case "image": return "Picture"
        case "measure": return "Ruler"
        default: return kind.capitalized
        }
    }

    /// What a piece is called in a list: the Layers tab, the Items list, the
    /// bar's title.
    ///
    /// **A lamp and a frame are named, not noted** (his report, 2026-10-07:
    /// the Layers tab was "named by their note and not the name of the label
    /// itself"). Two pieces keep their Note in `label` rather than their
    /// Name — a lamp's Name is its `lamp_name`, a frame's is its size and
    /// cloth — so reaching for `label` first gave a list of notes:
    /// *Backlight on the stairs*, *Bounce for the key*. Every other piece's
    /// Name **is** its `label`, and its Note lives in `caption`. The engine
    /// draws the same split (`render::note_of`, `shared_words`).
    static func name(_ e: DiagramEl, _ model: DiagramModel) -> String {
        if e.kind == "camera", let n = e.name, !n.isEmpty { return n }
        if DiagramMarks.isLamp(e, model) {
            if let n = e.lamp_name, !n.isEmpty { return n }
            return symName(e, model) ?? kindWord(e.kind)
        }
        if DiagramFrames.isFrame(e) {
            if let n = e.lamp_name, !n.isEmpty { return n }
            if let n = e.name, !n.isEmpty { return n }
            return "Frame"
        }
        if !e.label.isEmpty { return e.label }
        if ["text", "note"].contains(e.kind), !e.text.isEmpty { return String(e.text.prefix(30)) }
        if let sym = symName(e, model) { return sym }
        // A wall by its length; one closed on itself is a room.
        if e.isWall {
            if e.isClosed { return "Room" }
            let r = e.run
            return model.length(zip(r, r.dropFirst()).reduce(0) { $0 + Double(hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y)) })
        }
        return kindWord(e.kind)
    }

    /// A set piece's or lamp's own name: the library's, else the catalogue's
    /// as the engine sends it (the pack hides some of our drawings from the
    /// library — a scanned room's `table` — but they are still a Table), else
    /// the drawing's id in Title Case. Never "Set Piece" for a thing that has
    /// a name.
    static func symName(_ e: DiagramEl, _ model: DiagramModel) -> String? {
        guard ["set", "light"].contains(e.kind), !e.sym.isEmpty else { return nil }
        // A frame's name is written from its size and skin, by the engine.
        if e.sym == DiagramFrames.sym, let n = e.name, !n.isEmpty { return n }
        if let sym = model.library?.symbols.first(where: { $0.id == e.sym }) { return sym.name }
        if let n = e.name, !n.isEmpty { return n }
        return e.sym.split(whereSeparator: { $0 == "-" || $0 == "_" }).map { $0.capitalized }.joined(separator: " ")
    }
}

/// **The sun, and which way is north** — OpenShotDesigner's sun across the
/// plan, and his row SL-59. The place is the scene's location; the day is its
/// shoot day and the hour its time of day, unless set here.
struct DiagramSunPanel: View {
    @ObservedObject var model: DiagramModel
    @Environment(\.colorScheme) private var scheme
    /// While a slider is held: what it shows and the plan previews, kept
    /// only when it is let go — one step to take back, not a hundred.
    @State private var scrubTime: Double?
    @State private var scrubNorth: Double?

    var body: some View {
        let dark = scheme == .dark
        let s = model.settings
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sun and North").sans(Brand.Size.title, weight: .bold)
                Spacer()
                Button("Done") { model.showingSun = false }.buttonStyle(.capsule)
            }
            Toggle(isOn: Binding(get: { s.sun }, set: { model.setting("sun", $0) })) {
                Text("Show the Sun").sans(Brand.Size.body)
            }
            .toggleStyle(.switch).controlSize(.mini)
            if s.sun {
                Toggle(isOn: Binding(get: { s.sun_rays }, set: { model.setting("sun_rays", $0) })) {
                    Text("Rays").sans(Brand.Size.body)
                }
                .toggleStyle(.switch).controlSize(.mini)
            }
            Field("Day") {
                HStack(spacing: 8) {
                    DatePicker("", selection: Binding(get: { date }, set: { model.setting("sun_date", DiagramSunPanel.day.string(from: $0)) }),
                               displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.field)
                    if !s.sun_date.isEmpty {
                        Button("Shoot Day") { model.setting("sun_date", "") }.buttonStyle(.rowAction)
                    }
                }
            }
            Field("Time") {
                HStack(spacing: 8) {
                    Slider(value: Binding(get: { scrubTime ?? minutes }, set: { v in
                        scrubTime = v
                        model.previewing(["op": "settings", "set": ["sun_time": DiagramSunPanel.clock(v)]])
                    }), in: 0...1435, step: 5, onEditingChanged: { editing in
                        if !editing, let v = scrubTime {
                            model.setting("sun_time", DiagramSunPanel.clock(v))
                            scrubTime = nil
                        }
                    })
                    Text(DiagramSunPanel.clock(scrubTime ?? minutes)).sans(Brand.Size.body).monospacedDigit().frame(width: 44)
                }
            }
            if !picks.isEmpty {
                VStack(spacing: 2) {
                    ForEach(picks, id: \.0) { name, at in
                        Button { model.setting("sun_time", DiagramSunPanel.clock(at)) } label: {
                            HStack {
                                Text(name).sans(Brand.Size.body)
                                Spacer()
                                Text(DiagramSunPanel.clock(at)).sans(Brand.Size.body).monospacedDigit()
                                    .foregroundStyle(Brand.ink2(dark))
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(abs(minutes - at) < 3 ? Brand.glassOn(dark) : Color.clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !s.sun_time.isEmpty {
                Button("Scene's Time of Day") { model.setting("sun_time", "") }.buttonStyle(.rowAction)
            }
            Field("North") {
                HStack(spacing: 8) {
                    Slider(value: Binding(get: { scrubNorth ?? (s.north > 180 ? s.north - 360 : s.north) }, set: { v in
                        scrubNorth = v
                        model.previewing(["op": "settings", "set": ["north": (v + 360).truncatingRemainder(dividingBy: 360)]])
                    }), in: -180...180, step: 1, onEditingChanged: { editing in
                        if !editing, let v = scrubNorth {
                            model.setting("north", (v + 360).truncatingRemainder(dividingBy: 360))
                            scrubNorth = nil
                        }
                    })
                    let shown = scrubNorth ?? (s.north > 180 ? s.north - 360 : s.north)
                    Text("\(Int(shown.rounded()))°").sans(Brand.Size.body).monospacedDigit().frame(width: 44)
                }
            }
            Text(status).sans(Brand.Size.small).foregroundStyle(Brand.ink2(dark))
        }
        .padding(14)
        .frame(width: 300)
        .background(DiagramFloat(dark: dark, radius: 16))
    }

    /// The day's turning points for the place and day, to jump to.
    private var picks: [(String, Double)] {
        guard model.settings.sun, let sun = model.plan.sun else { return [] }
        return [("Sunrise", sun.rise), ("Morning Golden Hour", sun.goldenMorning), ("Noon", sun.noon),
                ("Evening Golden Hour", sun.goldenEvening), ("Sunset", sun.set)]
            .compactMap { name, at in at.map { (name, $0) } }
    }

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func clock(_ minutes: Double) -> String {
        String(format: "%02d:%02d", Int(minutes) / 60, Int(minutes) % 60)
    }

    private var date: Date {
        let said = model.settings.sun_date.isEmpty ? (model.plan.sceneDate ?? "") : model.settings.sun_date
        return DiagramSunPanel.day.date(from: said) ?? Date()
    }

    private var minutes: Double {
        if let m = model.plan.sun?.minutes { return m }
        let t = model.settings.sun_time.split(separator: ":").compactMap { Double($0) }
        return t.count == 2 ? t[0] * 60 + t[1] : 780
    }

    private var status: String {
        guard model.settings.sun else { return "Hidden" }
        guard let sun = model.plan.sun else { return "" }
        if let why = sun.why { return why }
        guard let az = sun.azimuth, let alt = sun.altitude else { return "" }
        if alt <= -0.9 { return "Below the horizon" }
        if alt < 0.5 { return "On the horizon" }
        let points = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
        let from = points[Int(((az + 22.5).truncatingRemainder(dividingBy: 360)) / 45) % 8]
        return "From the \(from), \(Int(alt.rounded()))° up"
    }
}
