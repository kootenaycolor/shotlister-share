import SwiftUI
import UIKit

/// **Diagrams on the phone, to look at** — Ref 1541 Stage F,
/// `design/33-one-app.html` section 1. Every scene with a plan, and every loose
/// plan; open one and it is drawn the way the Mac draws it.
///
/// **Drawn by the engine, painted here.** The engine lays the plan out and
/// hands over a list of shapes (`engine/src/diagram/wire.rs`): paths as flat
/// number lists, words, pills, badges, pictures, each with an ink that is a
/// role (`wall`) or a colour. `DiagramPaint` below turns them into strokes the
/// same way the Mac's `DiagramPainter` does, with the Mac's own ink table,
/// so a plan reads the same in his hand as on the desk. Nothing about the plan
/// is worked out in Swift.
///
/// Look only: no tools, no picking. Editing a plan stays on the Mac.
struct DiagramsView: View {
    @EnvironmentObject private var session: Session

    struct Item: Identifiable, Hashable {
        var id: String
        var title: String
        var number: String
        var count: Int
        /// How many diagrams the scene has (`scenediagrams`).
        var diagrams: Int = 1
        /// Left out of this list by hand (`diagramhide`): the same on the Mac
        /// and the portal.
        var hidden = false
    }

    @State private var scenes: [Item] = []
    @State private var plans: [Item] = []
    @State private var loaded = false
    /// The "N Hidden" line opened: the hidden scenes listed again, dimmed,
    /// each with Show. This visit only.
    @State private var reveal = false
    /// Opened at once: the checking door `--opendiagram`, so a plan can be
    /// photographed full screen without a tap.
    @State private var opened: Item?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if loaded, scenes.isEmpty, plans.isEmpty {
                    Text("No diagrams yet")
                        .font(.system(size: 15))
                        .foregroundStyle(Style.ink3)
                        .padding(.horizontal, 4)
                }
                if !scenes.isEmpty {
                    SectionTitle("Scenes")
                        .padding(.horizontal, 4)
                        .padding(.top, 8)
                        .padding(.bottom, 10)
                    LibraryCard {
                        ForEach(scenes.filter { reveal || !$0.hidden }) { item in
                            NavigationLink(value: item) { DiagramRow(item: item) }
                                .buttonStyle(.plain)
                                .opacity(item.hidden ? 0.5 : 1)
                                .contextMenu {
                                    // A long press: Hide from Diagrams, or Show on one listed again.
                                    if !session.isReadOnly {
                                        if item.hidden {
                                            Button("Show") { hide(item, false) }
                                        } else {
                                            Button("Hide from Diagrams") { hide(item, true) }
                                        }
                                    }
                                }
                        }
                        // How many are left out; tapping lists them again.
                        let away = scenes.filter(\.hidden).count
                        if away > 0 {
                            Button { reveal.toggle() } label: {
                                Text(reveal ? "Hide \(away)" : "\(away) Hidden")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Style.ink3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12).padding(.vertical, 10)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("diagram.hiddenCount")
                        }
                    }
                }
                if loaded, !scenes.isEmpty || !plans.isEmpty {
                    SectionTitle("Plans")
                        .padding(.horizontal, 4)
                        .padding(.top, 22)
                        .padding(.bottom, 10)
                    if plans.isEmpty {
                        Text("No plans yet")
                            .font(.system(size: 15))
                            .foregroundStyle(Style.ink3)
                            .padding(.horizontal, 4)
                    } else {
                        LibraryCard {
                            ForEach(plans) { item in
                                NavigationLink(value: item) { DiagramRow(item: item) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Style.page)
        .leadingTitle("Diagrams")
        .toolbar {
            if !session.isReadOnly {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        _ = session.engine?.raw("diagramplanadd", "Plan")
                        session.refresh()
                        load()
                    } label: { Label("New Plan", systemImage: "plus") }
                }
            }
        }
        .navigationDestination(for: Item.self) { item in
            DiagramScreen(item: item).environment(\.tabRoot, false)
        }
        .navigationDestination(item: $opened) { item in
            DiagramScreen(item: item).environment(\.tabRoot, false)
        }
        .task {
            load()
            if ProcessInfo.processInfo.arguments.contains("--opendiagram") { opened = scenes.first ?? plans.first }
            // Checking doors: `--hidediagram <n>` hides the nth scene of the list, `--revealhidden` opens the "N Hidden" line.
            let args = ProcessInfo.processInfo.arguments
            if let at = args.firstIndex(of: "--hidediagram"), at + 1 < args.count, let n = Int(args[at + 1]), n >= 1, n <= scenes.count {
                hide(scenes[n - 1], true)
            }
            if args.contains("--revealhidden") { reveal = true }
        }
    }

    /// Hide a scene from this list, or show it again. Only the list moves:
    /// the shot list, the schedule and the diagram stay as they are.
    private func hide(_ item: Item, _ hidden: Bool) {
        _ = session.engine?.raw("diagramhide", hidden ? "on" : "off", item.id)
        session.refresh()
        load()
        if scenes.allSatisfy({ !$0.hidden }) { reveal = false }
    }

    private func load() {
        guard let engine = session.engine else { loaded = true; return }
        struct Scenes: Decodable { var scenes: [String]; var counts: [String: Int]; var totals: [String: Int]?; var several: [String: Int]?; var hidden: [String]? }
        struct Plans: Decodable { var plans: [Plan] }
        struct Plan: Decodable { var id: String; var name: String; var count: Int }
        if let got = try? JSONDecoder().decode(Scenes.self, from: engine.raw("diagramscenes")) {
            // In the film's own order, which is the order the shot list reads.
            let order = session.view?.scenes ?? []
            scenes = got.scenes.compactMap { id in
                guard let scene = order.first(where: { $0.id == id }) else { return nil }
                let title = session.isCommercial && !scene.title.isEmpty ? scene.title : scene.heading
                return Item(id: id, title: title, number: scene.number, count: got.totals?[id] ?? got.counts[id] ?? 0,
                            diagrams: got.several?[id] ?? 1, hidden: got.hidden?.contains(id) ?? false)
            }
            .sorted { a, b in
                (order.firstIndex { $0.id == a.id } ?? 0) < (order.firstIndex { $0.id == b.id } ?? 0)
            }
        }
        if let got = try? JSONDecoder().decode(Plans.self, from: engine.raw("diagramplans")) {
            plans = got.plans.map { Item(id: $0.id, title: $0.name, number: "", count: $0.count) }
        }
        loaded = true
    }
}

private struct DiagramRow: View {
    @EnvironmentObject private var session: Session
    let item: DiagramsView.Item
    @State private var plan: DiagramPlan?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Color(hex: DiagramInk.light["paper"]!)
                if let plan {
                    DiagramCanvas(plan: plan, engine: session.engine)
                }
            }
            .frame(width: 110, height: 84)
            // A picture is never rounded (his rule, 2026-10-07).
            .clipped()
            .overlay {
                Rectangle()
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
            }
            VStack(alignment: .leading, spacing: 4) {
                (Text(item.number.isEmpty ? "" : "\(item.number) ").font(.system(size: 15, weight: .heavy))
                 + Text(item.title).font(.system(size: 15, weight: .semibold)))
                    .foregroundStyle(Color(.label))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Text(item.diagrams > 1 ? "\(item.diagrams) diagrams" : (item.count == 1 ? "1 piece" : "\(item.count) pieces"))
                    .font(.system(size: 13))
                    .foregroundStyle(Style.ink3)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .task { plan = DiagramPlan.read(item.id, engine: session.engine) }
    }
}

/// One plan, filling the screen: pinch to zoom, drag to move.
///
/// **As the Mac shows it** (his ask, 2026-10-10: *"display it in a way that
/// looks like the Mac app"*): the printed sheet on the desk, always — the
/// engine's own page (`diagramsheet`), its title, north, legend and shots
/// where they print, on the plan's grey paper, not white. Turn the phone for
/// a landscape sheet. A plan with no sheet falls back to the bare plan.
///
/// **The bar at the foot**: **Set** and **Plot**, the Mac's switch, say which
/// layer is in front, the other drawn back the way the Mac draws it (the set
/// grey under the plot, the plot faded over the set). **Legend** only where
/// there is no sheet to print one. The zoom circle fits it again.
private struct DiagramScreen: View {
    @EnvironmentObject private var session: Session
    let item: DiagramsView.Item
    @State private var plan: DiagramPlan?
    /// The plan read again at the sheet's own scale, with the sheet.
    @State private var sheet: DiagramSheet?
    @State private var zoom: CGFloat = 1
    @State private var settled: CGFloat = 1
    @State private var shift: CGSize = .zero
    @State private var moved: CGSize = .zero
    @State private var layer = Self.asked("DiagramLayer") ?? "plot"
    @State private var legend = Self.asked("DiagramLegend") == "1"
    @State private var loaded = false
    @State private var editing = ProcessInfo.processInfo.arguments.contains("--editdiagram")
    /// **The scene's diagrams** (`scenediagrams`), when it has more than one,
    /// and the one open. A loose plan has only itself.
    @State private var diagrams: [SceneDiagram] = []
    @State private var current: String?
    @State private var renaming: SceneDiagram?
    @State private var newName = ""
    @State private var deleting: SceneDiagram?
    private var owner: String { current.flatMap { c in diagrams.contains { $0.id == c } ? c : nil } ?? diagrams.first?.id ?? item.id }
    private var isScene: Bool { !DiagramEditor.isPlan(item.id, engine: session.engine) }

    /// On the sheet whenever the engine has one for it.
    private var paper: Bool { sheet != nil }

    /// A checking run opens on a layer or the legend
    /// (`-DiagramLayer set`, `-DiagramLegend 1`).
    private static func asked(_ key: String) -> String? {
        #if targetEnvironment(simulator)
        return UserDefaults.standard.string(forKey: key)
        #else
        return nil
        #endif
    }

    var body: some View {
        ZStack {
            // The Mac's desk round the sheet (`drawDesk`).
            (paper || !loaded ? Color(light: 0xC9CBCE, dark: 0x1C1C1F) : Color(hex: DiagramInk.light["paper"]!))
                .ignoresSafeArea()
            if loaded, let plan {
                GeometryReader { geo in
                    DiagramCanvas(plan: paper ? (sheet?.plan ?? plan) : plan, engine: session.engine,
                                  zoom: zoom, shift: shift, back: back(plan), sheet: paper ? sheet : nil,
                                  room: room(geo))
                        .contentShape(Rectangle())
                        .gesture(
                            MagnifyGesture()
                                .onChanged { zoom = min(12, max(1, settled * $0.magnification)) }
                                .onEnded { _ in settled = zoom }
                                .simultaneously(with: DragGesture()
                                    .onChanged { shift = CGSize(width: moved.width + $0.translation.width,
                                                                height: moved.height + $0.translation.height) }
                                    .onEnded { _ in moved = shift })
                        )
                        .onTapGesture(count: 2) { fit() }
                }
                .ignoresSafeArea(edges: .bottom)
            } else if loaded {
                Text("Nothing on this plan")
                    .font(.system(size: 15))
                    .foregroundStyle(Style.ink3)
            } else {
                ProgressView()
            }
        }
        .overlay(alignment: .bottom) { bar }
        .safeAreaInset(edge: .top, spacing: 0) { if diagrams.count > 1 { pills } }
        // The plan has the whole screen, its own bar at the foot (the
        // mockup's diagram has no tab bar under it).
        .toolbar(.hidden, for: .tabBar)
        // **Edit** (parity 2, 2026-10-16): the plan opens in the editor
        // (`DiagramEdit.swift`); on coming back it is read again.
        .toolbar {
            if !session.isReadOnly {
                if isScene {
                    ToolbarItem(placement: .primaryAction) { diagramMenu }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { editing = true }.accessibilityIdentifier("diagram.edit")
                }
            }
        }
        .alert(renaming.map { $0.name.isEmpty && $0.count == 0 ? "New Diagram" : "Rename Diagram" } ?? "", isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(renaming?.title ?? "", text: $newName)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("OK") {
                if let r = renaming {
                    _ = session.engine?.raw("scenediagramrename", r.id, newName.trimmingCharacters(in: .whitespaces))
                    reload()
                }
                renaming = nil
            }
        }
        .confirmationDialog(deleting.map { "Delete \($0.title)?" } ?? "", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let d = deleting {
                    _ = session.engine?.raw("scenediagramdelete", d.id)
                    if current == d.id { current = nil }
                    reload()
                }
                deleting = nil
            }
        } message: {
            if let d = deleting, d.count > 0 { Text(d.count == 1 ? "1 piece on it goes with it." : "\(d.count) pieces on it go with it.") }
        }
        .fullScreenCover(isPresented: $editing, onDismiss: {
            sheet = DiagramSheet.read(owner, engine: session.engine)
            plan = DiagramPlan.read(owner, engine: session.engine)
        }) {
            DiagramEditor(id: owner, title: item.number.isEmpty ? item.title : "\(item.number) \(item.title)",
                          isPlan: DiagramEditor.isPlan(item.id, engine: session.engine))
                .environmentObject(session)
        }
        .navigationTitle(item.number.isEmpty ? item.title : "\(item.number) \(item.title)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $legend) {
            DiagramLegendSheet(entries: plan?.legend ?? [], heads: plan?.legendColours ?? [],
                               colours: plan?.colours ?? [:])
                .presentationDetents([.fraction(0.45), .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.45)))
        }
        .task {
            readDiagrams()
            // A checking door: `--diagrampill <n>` opens the scene's nth diagram.
            let args = ProcessInfo.processInfo.arguments
            if let at = args.firstIndex(of: "--diagrampill"), at + 1 < args.count, let n = Int(args[at + 1]),
               n >= 1, n <= diagrams.count { current = diagrams[n - 1].id }
            // Both read before anything is drawn, so the bare plan never
            // flashes up before its sheet.
            sheet = DiagramSheet.read(owner, engine: session.engine)
            plan = DiagramPlan.read(owner, engine: session.engine)
            loaded = true
        }
    }

    /// Where the plan may stand: clear of the bar at the foot, and on paper
    /// clear of the bars at the top too, so the whole sheet is seen.
    private func room(_ geo: GeometryProxy) -> EdgeInsets {
        EdgeInsets(top: paper ? 12 : 0, leading: paper ? 14 : 0, bottom: geo.safeAreaInsets.bottom + 74,
                   trailing: paper ? 14 : 0)
    }

    /// The pieces of the layer not in front.
    private func back(_ plan: DiagramPlan) -> (ids: Set<String>, alpha: CGFloat) {
        (Set(plan.els.filter { ($0.layer ?? "plot") != layer }.map(\.id)), layer == "set" ? 0.2 : 0.5)
    }

    // ---- the scene's diagrams ----------------------------------------------------

    private func readDiagrams() {
        struct R: Decodable { var diagrams: [SceneDiagram] }
        guard isScene, let data = session.engine?.raw("scenediagrams", item.id) else { diagrams = []; return }
        let all = (try? JSONDecoder().decode(R.self, from: data))?.diagrams ?? []
        diagrams = all.count > 1 ? all : []
    }

    /// After a change to the row: the list again, then the open one.
    private func reload() {
        session.refresh()
        readDiagrams()
        sheet = DiagramSheet.read(owner, engine: session.engine)
        plan = DiagramPlan.read(owner, engine: session.engine)
    }

    private func pick(_ id: String) {
        current = id
        sheet = DiagramSheet.read(id, engine: session.engine)
        plan = DiagramPlan.read(id, engine: session.engine)
        fit()
    }

    private var open: SceneDiagram? { diagrams.first { $0.id == owner } }

    /// The switcher: one pill a diagram, swiped sideways when they run long.
    /// Long-press a pill for what the ⋯ menu offers.
    private var pills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(diagrams.enumerated()), id: \.element.id) { i, d in
                    let on = d.id == owner
                    Button { pick(d.id) } label: {
                        Text(d.title)
                            .font(.system(size: 14, weight: on ? .semibold : .medium))
                            .italic(d.name.isEmpty)
                            .lineLimit(1)
                            .foregroundStyle(on ? Color(.systemBackground) : (d.name.isEmpty ? Color(.tertiaryLabel) : Color(.label)))
                            .padding(.horizontal, 16)
                            .frame(minHeight: 36)
                            .background(Capsule().fill(on ? Color(.label) : Color(.tertiarySystemFill)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("diagram.pill.\(i)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .contextMenu { if !session.isReadOnly { actions(d, index: i) } }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }

    @ViewBuilder private func actions(_ d: SceneDiagram, index: Int) -> some View {
        Button { newName = d.name; renaming = d } label: { Label("Rename…", systemImage: "pencil") }
        Button { add(from: d.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        if diagrams.count > 1 {
            Button { move(d, to: index - 1) } label: { Label("Move Left", systemImage: "arrow.left") }.disabled(index == 0)
            Button { move(d, to: index + 1) } label: { Label("Move Right", systemImage: "arrow.right") }.disabled(index == diagrams.count - 1)
            Button(role: .destructive) { deleting = d } label: { Label("Delete…", systemImage: "trash") }
        }
    }

    private var diagramMenu: some View {
        Menu {
            Button { add(from: nil) } label: { Label("New Diagram", systemImage: "plus") }
            if let d = open ?? diagrams.first {
                actions(d, index: diagrams.firstIndex { $0.id == d.id } ?? 0)
            } else {
                Button { newName = ""; renaming = SceneDiagram(id: item.id, name: "", title: "Diagram 1", count: 1) } label: {
                    Label("Rename…", systemImage: "pencil")
                }
                Button { add(from: item.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityIdentifier("diagram.menu")
    }

    private func add(from: String?) {
        struct R: Decodable { var id: String }
        var parts = ["scenediagramadd", item.id, ""]
        if let from { parts.append(from) }
        guard let data = session.engine?.raw(parts), let made = (try? JSONDecoder().decode(R.self, from: data))?.id else { return }
        session.refresh()
        readDiagrams()
        pick(made)
        if let d = diagrams.first(where: { $0.id == made }) { newName = ""; renaming = d }
    }

    private func move(_ d: SceneDiagram, to index: Int) {
        _ = session.engine?.raw("scenediagrammove", d.id, String(max(0, index)))
        reload()
    }

    private func fit() {
        withAnimation(.snappy) { zoom = 1; settled = 1; shift = .zero; moved = .zero }
    }

    // ---- the bar ----------------------------------------------------------------

    private var bar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                part("Set", on: layer == "set") { layer = "set" }
                part("Plot", on: layer == "plot") { layer = "plot" }
                if !paper {
                    part("Legend", on: legend) { legend.toggle() }
                }
            }
            .padding(4)
            .frame(height: 50)
            .glassCapsule()

            // **How near, and the way back** (the mockup's `.zoom`): a glass
            // circle; a tap fits the plan again.
            Button { fit() } label: {
                VStack(spacing: 1) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .semibold))
                    Text(zoom == 1 ? "Fit" : "\(Int((zoom * 100).rounded()))%")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                }
                .foregroundStyle(Color(.label))
                .frame(width: 50, height: 50)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassCapsule()
            .accessibilityLabel("Fit")
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private func part(_ title: String, on: Bool, _ act: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) { act() }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(on ? Color(.systemBackground) : Color(.label))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background { if on { Capsule().fill(Color(.label)) } }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// **The plan's legend** (Legend in the bar): every kind of lamp the plan
/// uses, its mark in its ink, its name and how many, under the group it is
/// in (Film Lights, Practicals…), as the printed sheet's legend reads.
private struct DiagramLegendSheet: View {
    let entries: [DiagramPlan.LegendEntry]
    let heads: [DiagramPlan.LegendHead]
    let colours: [String: String]

    /// The entries under each group's head, in the order the sheet prints
    /// them; any whose ink has no head last.
    private var groups: [(name: String, lines: [DiagramPlan.LegendEntry])] {
        var out: [(String, [DiagramPlan.LegendEntry])] = []
        var used = Set<String>()
        for head in heads {
            let lines = entries.filter { Self.role(of: $0.ink) == head.role }
            guard !lines.isEmpty else { continue }
            out.append((head.name, lines))
            lines.forEach { used.insert($0.key) }
        }
        let rest = entries.filter { !used.contains($0.key) }
        if !rest.isEmpty { out.append(("", rest)) }
        return out
    }

    /// A lamp drawn in plain ink is an Existing Light's.
    static func role(of ink: String) -> String { ink == "ink" ? "existing" : ink }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if entries.isEmpty {
                        Text("No lights on this plan")
                            .font(.system(size: 15))
                            .foregroundStyle(Style.ink3)
                            .padding(.horizontal, 4)
                    }
                    ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                        if !group.name.isEmpty {
                            SectionTitle(group.name, size: 17)
                                .padding(.horizontal, 4)
                                .padding(.top, index == 0 ? 0 : 18)
                                .padding(.bottom, 8)
                        }
                        LibraryCard {
                            ForEach(group.lines, id: \.key) { line in
                                HStack(spacing: 12) {
                                    DiagramMark(mark: line.mark, ink: line.ink, solid: line.solid, colours: colours)
                                        .frame(width: 22, height: 22)
                                        .frame(width: 34, height: 34)
                                    Text(line.name.isEmpty ? "Light" : line.name)
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color(.label))
                                        .lineLimit(2)
                                    Spacer(minLength: 6)
                                    Text("×\(Int(line.count))")
                                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                                        .foregroundStyle(Style.ink3)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .background(Style.page)
            .leadingTitle("Legend")
        }
    }
}

/// A legend mark, drawn as the plan draws it (`plot::mark`), facing right:
/// the Mac's `DiagramMarkGlyph`, on paper.
struct DiagramMark: View {
    let mark: String
    let ink: String
    let solid: Bool
    var colours: [String: String] = [:]

    var body: some View {
        Canvas { ctx, size in
            let role = DiagramLegendSheet.role(of: ink)
            let c = Color(uiColor: colours[role].flatMap { DiagramInk.color($0) } ?? DiagramInk.color(role) ?? .label)
            let s = min(size.width, size.height)
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: mid.x + x * s, y: mid.y + y * s) }
            var path = Path()
            switch mark {
            case "chevron":
                path.move(to: p(0.5, -0.42)); path.addLine(to: p(-0.5, 0)); path.addLine(to: p(0.5, 0.42))
                if solid { path.addLine(to: p(0.18, 0)); path.closeSubpath(); ctx.fill(path, with: .color(c)) }
                else { ctx.stroke(path, with: .color(c), style: StrokeStyle(lineWidth: 2, lineJoin: .round)) }
            case "wedge":
                path.move(to: p(-0.5, 0)); path.addLine(to: p(0.5, -0.45)); path.addLine(to: p(0.5, 0.45)); path.closeSubpath()
                solid ? ctx.fill(path, with: .color(c)) : ctx.stroke(path, with: .color(c), lineWidth: 1.6)
            case "bar":
                let r = Path(CGRect(x: mid.x - s * 0.1, y: mid.y - s * 0.5, width: s * 0.2, height: s))
                solid ? ctx.fill(r, with: .color(c)) : ctx.stroke(r, with: .color(c), lineWidth: 1.2)
            case "double-bar":
                let box = Path(CGRect(x: mid.x - s * 0.25, y: mid.y - s * 0.5, width: s * 0.5, height: s))
                if solid { ctx.fill(box, with: .color(c)) } else {
                    ctx.stroke(box, with: .color(c), lineWidth: 1.2)
                    ctx.fill(Path(CGRect(x: mid.x + s * 0.09, y: mid.y - s * 0.5, width: s * 0.16, height: s)), with: .color(c))
                }
            case "ring":
                let r = Path(ellipseIn: CGRect(x: mid.x - s * 0.36, y: mid.y - s * 0.36, width: s * 0.72, height: s * 0.72))
                if solid { ctx.fill(r, with: .color(c)) } else { ctx.stroke(r, with: .color(c), lineWidth: 1.6) }
                let d = Path(ellipseIn: CGRect(x: mid.x - s * 0.13, y: mid.y - s * 0.13, width: s * 0.26, height: s * 0.26))
                ctx.fill(d, with: .color(solid ? Color(.systemBackground) : c))
            case "dot":
                let r = Path(ellipseIn: CGRect(x: mid.x - s * 0.3, y: mid.y - s * 0.3, width: s * 0.6, height: s * 0.6))
                solid ? ctx.fill(r, with: .color(c)) : ctx.stroke(r, with: .color(c), lineWidth: 1.6)
            case "mat":
                let box = CGRect(x: mid.x - s * 0.42, y: mid.y - s * 0.27, width: s * 0.84, height: s * 0.54)
                ctx.fill(Path(box), with: .color(c.opacity(solid ? 0.42 : 0.13)))
                ctx.stroke(Path(box), with: .color(c), lineWidth: 1.6)
                ctx.stroke(Path(box.insetBy(dx: s * 0.09, dy: s * 0.09)), with: .color(c.opacity(0.75)), lineWidth: 0.7)
            case "arrow":
                path.move(to: p(-0.5, 0)); path.addLine(to: p(0.42, 0))
                ctx.stroke(path, with: .color(c), lineWidth: 1.8)
                var head = Path()
                head.move(to: p(0.1, -0.3)); head.addLine(to: p(0.5, 0)); head.addLine(to: p(0.1, 0.3))
                if solid { head.closeSubpath(); ctx.fill(head, with: .color(c)) } else { ctx.stroke(head, with: .color(c), lineWidth: 1.8) }
            case "square":
                let r = Path(CGRect(x: mid.x - s * 0.33, y: mid.y - s * 0.33, width: s * 0.66, height: s * 0.66))
                solid ? ctx.fill(r, with: .color(c)) : ctx.stroke(r, with: .color(c), lineWidth: 1.6)
            default:
                let r = Path(ellipseIn: CGRect(x: mid.x - s * 0.45, y: mid.y - s * 0.45, width: s * 0.9, height: s * 0.9))
                ctx.stroke(r, with: .color(c), lineWidth: 1.4)
                let letter = String(mark.split(separator: "-").last ?? "")
                ctx.draw(Text(letter).font(.system(size: s * 0.55, weight: .bold)).foregroundColor(c), at: mid)
            }
        }
    }
}

/// What the engine says a plan looks like.
struct DiagramPlan {
    var shapes: [Shape]
    /// The plan's bounds, metres: x1, y1, x2, y2.
    var extent: [Double]
    /// Each piece and the layer it is drawn in, Set or Plot (Ref 1498).
    var els: [El] = []
    /// The sheet's legend: a line per kind of lamp (`plot::legend`).
    var legend: [LegendEntry] = []
    /// Each group's head over its legend lines (`plot::colour_rows`).
    var legendColours: [LegendHead] = []
    /// His own inks for the groups, where he set them.
    var colours: [String: String] = [:]

    struct El: Decodable {
        var id: String
        var layer: String?
    }

    struct LegendEntry: Decodable {
        var key: String
        var name: String
        var mark: String
        var ink: String
        var solid: Bool
        var count: Double
    }

    struct LegendHead: Decodable {
        var role: String
        var name: String
    }

    struct Shape: Decodable {
        var e: String?
        var p: String?
        var k: String
        var d: [Double]?
        var x: Double?, y: Double?
        var tx: String?
        var sz: Double?
        var an: String?
        var b: Bool?
        var r: Double?
        var fx: Bool?
        var h: Bool?
        var on: String?
        var m: String?
        var iw: Double?, ih: Double?
        var f: String?
        var s: String?
        var w: Double?
        var da: String?
        var a: Double?
        var fd: [Double]?
        var pa: Bool?
        var f2: String?
        /// Lines in `f` before `f2` (a Name of several lines, 2026-10-17).
        var n1: Int?
    }

    /// Read with `page=1`: the plan lettered as its sheet letters it, so words
    /// and marks keep their size against the plan however small it is drawn.
    /// `ppm`, the sheet's own scale, when it is to be laid on the sheet.
    static func read(_ id: String, engine: Engine?, ppm: Double? = nil) -> DiagramPlan? {
        guard let engine else { return nil }
        struct Settings: Decodable { var colours: [String: String]? }
        struct Reply: Decodable {
            var shapes: [Shape]
            var extent: [Double]?
            var els: [El]?
            var legend: [LegendEntry]?
            var legendColours: [LegendHead]?
            var settings: Settings?
        }
        let args = ["page=1"] + (ppm.map { [String(format: "ppm=%.4f", $0)] } ?? [])
        guard let r = try? JSONDecoder().decode(Reply.self, from: engine.raw(["diagram", id] + args)),
              let extent = r.extent, extent.count == 4 else { return nil }
        return DiagramPlan(shapes: r.shapes, extent: extent, els: r.els ?? [], legend: r.legend ?? [],
                           legendColours: r.legendColours ?? [], colours: r.settings?.colours ?? [:])
    }
}

/// **The printed sheet** (`diagramsheet`, `engine/src/diagram/sheet.rs`): the
/// paper, where the plan stands on it and at how many points to the metre,
/// and its own words and rules in paper points. With the plan read again at
/// that scale, so its names are placed as the page places them.
struct DiagramSheet {
    var w: Double
    var h: Double
    var scale: Double
    var ox: Double
    var oy: Double
    var shapes: [DiagramPlan.Shape]
    var plan: DiagramPlan

    static func read(_ id: String, engine: Engine?) -> DiagramSheet? {
        guard let engine else { return nil }
        struct Reply: Decodable {
            var w: Double, h: Double, scale: Double, ox: Double, oy: Double
            var shapes: [DiagramPlan.Shape]
        }
        let tz = "tz=\(TimeZone.current.secondsFromGMT() / 60)"
        guard let r = try? JSONDecoder().decode(Reply.self, from: engine.raw("diagramsheet", id, tz)),
              r.w > 0, r.h > 0, r.scale > 0,
              let plan = DiagramPlan.read(id, engine: engine, ppm: r.scale) else { return nil }
        return DiagramSheet(w: r.w, h: r.h, scale: r.scale, ox: r.ox, oy: r.oy, shapes: r.shapes, plan: plan)
    }
}

/// The plan, fitted to whatever room it is given — or, with a sheet, the
/// sheet fitted and the plan where it prints on it. Zoom and shift are drawn,
/// not scaled after, so words and lines stay sharp however near.
struct DiagramCanvas: View {
    let plan: DiagramPlan
    let engine: Engine?
    var zoom: CGFloat = 1
    var shift: CGSize = .zero
    /// The layer not in front, and how far it is drawn back.
    var back: (ids: Set<String>, alpha: CGFloat) = ([], 1)
    var sheet: DiagramSheet? = nil
    /// Kept clear at the edges: the bars over the plan.
    var room = EdgeInsets()

    var body: some View {
        Canvas { context, size in
            let box = CGRect(x: room.leading, y: room.top,
                             width: max(size.width - room.leading - room.trailing, 10),
                             height: max(size.height - room.top - room.bottom, 10))
            // Zoom about the middle of the room, then the drag.
            func zoomed(_ T: CGAffineTransform) -> CGAffineTransform {
                T.concatenating(CGAffineTransform(translationX: -box.midX, y: -box.midY))
                    .concatenating(CGAffineTransform(scaleX: zoom, y: zoom))
                    .concatenating(CGAffineTransform(translationX: box.midX + shift.width, y: box.midY + shift.height))
            }
            context.withCGContext { cg in
                UIGraphicsPushContext(cg)
                defer { UIGraphicsPopContext() }
                if let sheet {
                    // The page fitted whole, the plan where the sheet says.
                    let k0 = min(box.width / sheet.w, box.height / sheet.h)
                    let k = k0 * zoom
                    let P = zoomed(CGAffineTransform(a: k0, b: 0, c: 0, d: k0,
                                                     tx: box.midX - sheet.w * k0 / 2, ty: box.midY - sheet.h * k0 / 2))
                    let page = CGRect(x: 0, y: 0, width: sheet.w, height: sheet.h).applying(P)
                    cg.saveGState()
                    cg.setShadow(offset: CGSize(width: 0, height: 4), blur: 16,
                                 color: UIColor.black.withAlphaComponent(0.22).cgColor)
                    // The plan's own grey paper, as the Mac's sheet is.
                    let paper = DiagramInk.color("paper")!
                    cg.setFillColor(paper.cgColor)
                    cg.fill(page)
                    cg.restoreGState()
                    let T = CGAffineTransform(a: sheet.scale, b: 0, c: 0, d: sheet.scale, tx: sheet.ox, ty: sheet.oy)
                        .concatenating(P)
                    var painter = DiagramPaint(scale: k * sheet.scale, shrink: k, engine: engine)
                    for shape in plan.shapes where shape.p != "north" {
                        painter.fade = shape.e.map { back.ids.contains($0) } == true ? back.alpha : 1
                        painter.paint(shape, cg, T)
                    }
                    let words = DiagramPaint(scale: k, shrink: k, engine: engine)
                    for shape in sheet.shapes { words.paint(shape, cg, P) }
                    return
                }
                let x1 = plan.extent[0], y1 = plan.extent[1], x2 = plan.extent[2], y2 = plan.extent[3]
                let w = max(x2 - x1, 0.1), h = max(y2 - y1, 0.1)
                // The engine's extent is the pieces; their names and callouts
                // can stand outside it, so the plan keeps room round it.
                let pad: CGFloat = max(10, min(box.width, box.height) * 0.1)
                let fit = min((box.width - pad * 2) / w, (box.height - pad * 2) / h)
                let T = zoomed(CGAffineTransform(a: fit, b: 0, c: 0, d: fit,
                                                 tx: box.midX - (x1 + w / 2) * fit, ty: box.midY - (y1 + h / 2) * fit))
                let scale = fit * zoom
                // Words are sized for the sheet; on a small canvas they shrink
                // with it, the way the Mac's page view shrinks them.
                let shrink = min(1, max(0.25, scale / 40))
                var painter = DiagramPaint(scale: scale, shrink: shrink, engine: engine)
                for shape in plan.shapes {
                    painter.fade = shape.e.map { back.ids.contains($0) } == true ? back.alpha : 1
                    painter.paint(shape, cg, T)
                }
            }
        }
    }
}

/// The Mac's ink table (`studio/Sources/DiagramCanvas.swift`, `DiagramInk`),
/// light paper only: a plan is paper, and his phone reads it as paper.
enum DiagramInk {
    static let light: [String: String] = [
        "paper": "E4E5E7", "grid": "D8D9DB", "grid5": "CECFD1", "griddot": "B9BABD",
        "wall": "48494A", "set": "B4B4B4", "setline": "444444", "setsoft": "D5D5D4", "setink": "8F8F8F",
        "glass": "E2F2F7", "rug": "D4CDC6", "screen": "333333", "vehicle": "7C7C7C", "tyre": "333333",
        "plant": "D1E0C2", "trunk": "AC8D77", "grip": "444444", "silk": "F1F1F1",
        "light": "F0B63F", "lightface": "FFF1CF", "lightline": "93620A", "lightink": "8A5A06", "added": "B42318",
        "practical": "E08A00", "practicalword": "A35E00", "plan": "74777C", "prop": "989BA0", "blue": "2F5DB8",
        "gripink": "B42318", "existing": "74777C", "camink": "2F5DB8",
        "fixture": "B4B4B4", "fixtureline": "444444", "muslin": "EFE6D2", "wood": "AC8D77",
        "cast": "4A72C9", "cam": "333333", "cone": "26262B", "tag": "FFFFFF", "tagline": "D5D8DC",
        "ink": "17171A", "ink2": "5A5A61", "dim": "5B6770", "track": "656565",
        "road": "C8C8C8", "roadline": "9E9E9E", "marking": "FFFFFF", "walk": "EDEDED",
        "zone": "6354C6", "zonefill": "6354C6", "cable": "A74643", "note": "FFF4C2", "noteline": "E3CB63",
        "sun": "F2A93B", "sunink": "8A5A06",
    ]

    /// A role, a colour, or a colour with how much of it (`#D9483B/0.30`).
    static func color(_ word: String?) -> UIColor? {
        guard let word, !word.isEmpty else { return nil }
        if word.hasPrefix("#") {
            let parts = word.split(separator: "/")
            let alpha = parts.count > 1 ? (Double(parts[1]) ?? 1) : 1
            return UIColor(hex: String(parts[0]).replacingOccurrences(of: "#", with: ""))
                .withAlphaComponent(CGFloat(alpha))
        }
        return UIColor(hex: light[word] ?? "17171A")
    }
}

/// Paints the engine's shapes into a CoreGraphics context: the Mac's
/// `DiagramPainter`, line for line where it can be, on UIKit.
struct DiagramPaint {
    var scale: CGFloat
    var shrink: CGFloat
    var engine: Engine?
    /// How far the shape being painted is drawn back: the layer not in
    /// front (Set or Plot, Ref 1498).
    var fade: CGFloat = 1
    /// What names sit on, when it is not the plan's grey paper: the white
    /// of the printed sheet.
    var ground: UIColor?

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

    func paint(_ s: DiagramPlan.Shape, _ cg: CGContext, _ T: CGAffineTransform) {
        let alpha = CGFloat(s.a ?? 1) * fade
        cg.saveGState()
        defer { cg.restoreGState() }
        cg.setAlpha(min(max(alpha, 0), 1))
        switch s.k {
        case "path":
            guard let d = s.d else { return }
            let p = path(d, T)
            // A cut in a wall takes whatever the plan is on.
            if let fill = s.f == "paper" ? (ground ?? DiagramInk.color(s.f)) : DiagramInk.color(s.f) {
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
            if let stroke = DiagramInk.color(s.s), let w = s.w, w > 0 {
                cg.addPath(p)
                cg.setStrokeColor(stroke.cgColor)
                // Lines keep their weight against the plan as it shrinks.
                cg.setLineWidth(max(0.4, CGFloat(w) * shrink))
                cg.setLineJoin(.round)
                cg.setLineCap(s.da == "dot" ? .round : .butt)
                switch s.da {
                case "dash": cg.setLineDash(phase: 0, lengths: [5 * shrink, 4 * shrink])
                case "dot": cg.setLineDash(phase: 0, lengths: [0.1, 3.5 * shrink])
                default: cg.setLineDash(phase: 0, lengths: [])
                }
                cg.strokePath()
            }
        case "text":
            guard let x = s.x, let y = s.y, let tx = s.tx, !tx.isEmpty else { return }
            let fixed = s.fx ?? true
            let size = fixed ? CGFloat(s.sz ?? 10) * shrink : CGFloat(s.sz ?? 0.3) * scale
            guard size >= 2.5 else { return }
            let colour = DiagramInk.color(s.f) ?? .label
            let font = UIFont.systemFont(ofSize: size, weight: (s.b ?? false) ? .semibold : .regular)
            let at = CGPoint(x: x, y: y).applying(T)
            var rot = CGFloat(s.r ?? 0)
            if (s.an ?? "middle") == "middle" { rot = Self.readable(rot) }
            if s.pa == true {
                let box = Self.wordsBox(tx, at: at, font: font, anchor: s.an ?? "middle", rot: rot).insetBy(dx: -2, dy: -1)
                cg.addPath(CGPath(roundedRect: box, cornerWidth: 2, cornerHeight: 2, transform: nil))
                cg.setFillColor((ground ?? DiagramInk.color("paper")!).cgColor)
                cg.fillPath()
            }
            Self.words(tx, at: at, font: font, colour: colour, anchor: s.an ?? "middle", rot: rot,
                       halo: s.h ?? false, cg: cg, under: DiagramInk.color(s.f2), ground: ground, lead: s.n1 ?? 1)
        case "pill":
            guard let x = s.x, let y = s.y, let tx = s.tx else { return }
            let at = CGPoint(x: x, y: y).applying(T)
            let size = CGFloat(s.sz ?? 10.5) * shrink
            guard size >= 2.5 else { return }
            let font = UIFont.systemFont(ofSize: size, weight: .semibold)
            let textW = (tx as NSString).size(withAttributes: [.font: font]).width
            let r = CGRect(x: at.x - textW / 2 - size * 0.62, y: at.y - size * 0.86,
                           width: textW + size * 1.24, height: size * 1.72)
            let shape = CGPath(roundedRect: r, cornerWidth: r.height * 0.36, cornerHeight: r.height * 0.36, transform: nil)
            cg.addPath(shape)
            cg.setFillColor((DiagramInk.color(s.f) ?? .white).cgColor)
            cg.fillPath()
            if let st = DiagramInk.color(s.s) {
                cg.addPath(shape)
                cg.setStrokeColor(st.cgColor)
                cg.setLineWidth(1)
                cg.strokePath()
            }
            let ink = (s.on.flatMap { $0.isEmpty ? nil : DiagramInk.color($0) }) ?? DiagramInk.color("ink")!
            Self.words(tx, at: at, font: font, colour: ink, anchor: "middle", rot: 0, halo: false, cg: cg)
        case "badge":
            guard let x = s.x, let y = s.y, let tx = s.tx else { return }
            let at = CGPoint(x: x, y: y).applying(T)
            let half = 7 * shrink
            cg.setFillColor((DiagramInk.color(s.f) ?? .gray).cgColor)
            cg.fillEllipse(in: CGRect(x: at.x - half, y: at.y - half, width: half * 2, height: half * 2))
            let ink = (s.on.flatMap { $0.isEmpty ? nil : DiagramInk.color($0) }) ?? DiagramInk.color("paper")!
            Self.words(tx, at: at, font: .systemFont(ofSize: 8.5 * shrink, weight: .bold), colour: ink,
                       anchor: "middle", rot: 0, halo: false, cg: cg)
        case "img":
            guard let x = s.x, let y = s.y, let w = s.iw, let h = s.ih, let media = s.m,
                  let image = DiagramArt.image(media, engine: engine) else { return }
            let c = CGPoint(x: x, y: y).applying(T)
            let pw = CGFloat(w) * scale, ph = CGFloat(h) * scale
            cg.translateBy(x: c.x, y: c.y)
            cg.rotate(by: CGFloat(s.r ?? 0) * .pi / 180)
            image.draw(in: CGRect(x: -pw / 2, y: -ph / 2, width: pw, height: ph), blendMode: .normal,
                       alpha: min(max(alpha, 0), 1))
        default:
            break
        }
    }

    static func wordsBox(_ text: String, at: CGPoint, font: UIFont, anchor: String, rot: CGFloat) -> CGRect {
        let lines = text.components(separatedBy: "\n")
        let lineH = font.lineHeight
        let w = lines.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let h = lineH * CGFloat(lines.count)
        let x0: CGFloat = anchor == "start" ? 0 : (anchor == "end" ? -w : -w / 2)
        let local = CGRect(x: x0, y: -h / 2, width: w, height: h)
        return local.applying(CGAffineTransform(translationX: at.x, y: at.y).rotated(by: rot * .pi / 180))
    }

    static func readable(_ deg: CGFloat) -> CGFloat {
        var d = deg.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        if d > 90 && d < 270 { return d - 180 }
        return d >= 270 ? d - 360 : d
    }

    static func words(_ text: String, at: CGPoint, font: UIFont, colour: UIColor, anchor: String,
                      rot: CGFloat, halo: Bool, cg: CGContext, under: UIColor? = nil, ground: UIColor? = nil, lead: Int = 1) {
        let lines = text.components(separatedBy: "\n")
        let lineH = font.lineHeight
        cg.saveGState()
        cg.translateBy(x: at.x, y: at.y)
        if rot != 0 { cg.rotate(by: rot * .pi / 180) }
        let total = lineH * CGFloat(lines.count)
        let haloWidth = max(3.5, font.pointSize * 0.22)
        for (i, line) in lines.enumerated() {
            let ink = i >= max(lead, 1) ? (under ?? colour) : colour
            let str = NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: ink])
            let w = str.size().width
            let x: CGFloat = anchor == "start" ? 0 : (anchor == "end" ? -w : -w / 2)
            let y = -total / 2 + CGFloat(i) * lineH
            if halo {
                NSAttributedString(string: line, attributes: [
                    .font: font, .strokeColor: ground ?? DiagramInk.color("paper")!,
                    .strokeWidth: haloWidth / font.pointSize * 100,
                ]).draw(at: CGPoint(x: x, y: y))
            }
            str.draw(at: CGPoint(x: x, y: y))
        }
        cg.restoreGState()
    }
}

/// Pictures laid on a plan, kept once read: the Film Set Objects pack's
/// (`fso:`), carried by the engine, and the film's own, by hash.
enum DiagramArt {
    private static var held: [String: UIImage] = [:]
    private static let lock = NSLock()

    static func image(_ media: String, engine: Engine?) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        if let got = held[media] { return got }
        guard let engine else { return nil }
        struct Reply: Decodable { var data: String }
        var made: UIImage?
        if media.hasPrefix("fso:") {
            if let r = try? JSONDecoder().decode(Reply.self, from: engine.raw("diagramart", String(media.dropFirst(4)))),
               let data = Data(base64Encoded: r.data) { made = UIImage(data: data) }
        } else {
            let parts = media.split(separator: ".", maxSplits: 1).map(String.init)
            if let hash = parts.first {
                for ext in [parts.count > 1 ? parts[1] : "jpg", "jpg", "png"] {
                    if let r = try? JSONDecoder().decode(Reply.self, from: engine.raw("media", hash, ext)),
                       let data = Data(base64Encoded: r.data), let image = UIImage(data: data) {
                        made = image
                        break
                    }
                }
            }
        }
        if let made { held[media] = made }
        return made
    }
}

extension UIColor {
    convenience init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&v)
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: String) { self.init(uiColor: UIColor(hex: hex)) }
}

/// One of a scene's diagrams, as the engine lists it (`scenediagrams`).
struct SceneDiagram: Decodable, Identifiable, Equatable {
    var id: String
    var name: String
    var title: String
    var count: Int
}
