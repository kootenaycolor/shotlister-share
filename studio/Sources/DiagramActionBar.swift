import SwiftUI
import AppKit

/// **One bar at the foot of the plan** (design/24, redrawn by design/26): only
/// there when something is picked or beats are being stepped. In beats mode
/// the stepping stands on its left; what is picked follows.
///
/// **It stays on its own line** between the scale and the zoom, and when that
/// line is too short it folds rather than jumping up over the zoom (his pick,
/// 2026-10-02): first its actions go into More, then all but its first
/// setting, then it is the name alone. Each fold is measured, not guessed.
struct DiagramFootBar: View {
    @ObservedObject var state: ShellState
    @ObservedObject var model: DiagramModel
    /// How wide the bar is at each fold, measured from copies drawn hidden.
    @State private var widths: [Int: CGFloat] = [:]
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        // **It steps aside while Details is open** (Back to Paper, Batch 2):
        // one place at a time for what a piece is.
        let picked = !model.selection.isEmpty && !model.readOnly && !model.detailsShown && !model.shownPicked.isEmpty
        GeometryReader { g in
            let free = g.size.width
            // The line between the scale (bottom left) and the zoom.
            let hi = free - 126
            let level = (0..<4).first { (widths[$0] ?? .infinity) <= hi - 160 } ?? 3
            // Narrower still: the scale gives way before the bar crosses it.
            let lo: CGFloat = level == 3 && (widths[3] ?? 0) > hi - 160 ? 14 : 160
            let lane = max(hi - lo, 60)
            let w = min(widths[level] ?? 0, lane)
            // Centred on the plan where it can be, else slid along its line.
            let x = min(max(free / 2 - w / 2, lo), lo + lane - w)
            let _ = { model.barLevel = level }()
            VStack {
                Spacer(minLength: 0)
                if model.beatMode || picked {
                    Group {
                        if let natural = widths[level] { bar(level, picked: picked).frame(width: min(natural, lane)) }
                        else { bar(level, picked: picked).fixedSize() }
                    }
                    .frame(width: free, alignment: .leading)
                        .offset(x: x)
                        .transition(.opacity)
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .background(alignment: .bottomLeading) {
                // Every fold, drawn where no one sees it, to know its width.
                if model.beatMode || picked {
                    ZStack(alignment: .bottomLeading) {
                        ForEach(0..<4, id: \.self) { l in
                            bar(l, picked: picked, measuring: true).fixedSize()
                                .background(GeometryReader { b in
                                    Color.clear.preference(key: DiagramBarWidths.self, value: [l: b.size.width])
                                })
                        }
                    }
                    .hidden().allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .onPreferenceChange(DiagramBarWidths.self) { widths = $0 }
        }
    }

    /// The bar at one fold. `measuring`: words alone, no menus behind them —
    /// the same width for a fraction of the drawing.
    private func bar(_ level: Int, picked: Bool, measuring: Bool = false) -> some View {
        HStack(spacing: 2) {
            if model.beatMode {
                DiagramBeatBar(model: model)
                if picked {
                    Rectangle().fill(Brand.rule2(dark)).frame(width: 1, height: 16).padding(.horizontal, 6)
                }
            }
            if picked { DiagramActionBar(state: state, model: model, level: level, measuring: measuring) }
        }
        .padding(.horizontal, 8).frame(height: 38)
        .background(DiagramFloat(dark: dark, radius: 19, solid: true))
    }
}

struct DiagramBarWidths: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

/// **One bar at the foot, per kind** (Back to Paper, Batch 2, design/32
/// item 8): the few things this kind of piece is changed by, each a quiet
/// word and what it is now, a click to change it, then **More** — the same
/// menu as a right-click (`DiagramMenu`). No name repeated at its head: a
/// title only where it is a count (a shared label's lamps, several picked).
/// Name and Note are typed on the plan, in the words themselves.
struct DiagramActionBar: View {
    @ObservedObject var state: ShellState
    @ObservedObject var model: DiagramModel
    /// 0 everything; 1 its actions folded into More; 2 all but its first
    /// setting too; 3 More alone.
    var level = 0
    /// Drawn only to be measured: the same words, no menus behind them.
    var measuring = false
    @State private var focalOpen = false
    /// Which of the bar's pickers is open, by its key.
    @State private var open: String?
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    // MARK: what the bar holds

    private var pick: DiagramPick { DiagramPick.of(model.shownPicked, model) }

    /// The one piece the bar speaks for, when one is picked.
    private var one: DiagramEl? { model.shownPicked.count == 1 ? model.shownPicked.first : nil }

    /// Its title (a count, never a name), its settings and its verbs.
    static func layout(_ pick: DiagramPick, _ model: DiagramModel) -> (title: String?, values: [String], actions: [String]) {
        switch pick {
        case .none:
            return (nil, [], [])
        case .lamp(let e):
            return (nil, ["symbol", "lampname", "count", "note", "gel"] + (DiagramMarks.type(of: e) == "film" ? [] : ["off"]) + hung([e]), [])
        case .shared(_, let lamps):
            // **Frames and any piece share a label too** (his ask,
            // 2026-10-05): lamps alone keep a lamp's settings; with anything
            // else in it, the label's Note.
            guard lamps.allSatisfy({ DiagramMarks.isLamp($0, model) }) else {
                return ("Shared Label · " + heldCount(lamps, model, title: true), ["sharednote"], [])
            }
            let off = lamps.contains { DiagramMarks.type(of: $0) != "film" }
            return ("Shared Label · \(lamps.count) \(lamps.count == 1 ? "Lamp" : "Lamps")",
                    ["symbol", "lampname", "note", "gel"] + (off ? ["off"] : []) + hung(lamps), [])
        case .kind(let lamps):
            return ("\(lamps.count) Lamps", ["symbol", "lampname"], ["sharelabel"])
        case .several(let all):
            var a: [String] = []
            if all.allSatisfy(\.isWall) { a.append("join") }
            if all.filter({ DiagramMarks.canShare($0) }).count >= 2 { a.append("sharelabel") }
            let groups = Set(all.map(\.group))
            a.append(groups.count == 1 && !(groups.first ?? "").isEmpty ? "ungroup" : "group")
            return ("\(all.count) Selected", ["align"], a)
        case .one(let e):
            return (nil, values(e, model), actions(e, model))
        }
    }

    /// **Down, and the height it hangs at** (his ask, 2026-10-05: a LiteMat
    /// 8 over the set, pointing straight down): Height only once it is Down.
    static func hung(_ lamps: [DiagramEl]) -> [String] {
        lamps.allSatisfy(DiagramMarks.pointsDown) ? ["down", "hangheight"] : ["down"]
    }

    /// What a shared label holds, counted: "3 lamps", "2 frames", "4 pieces".
    static func heldCount(_ els: [DiagramEl], _ model: DiagramModel, title: Bool = false) -> String {
        let n = els.count
        let word: String
        if els.allSatisfy({ DiagramMarks.isLamp($0, model) }) { word = n == 1 ? "lamp" : "lamps" }
        else if els.allSatisfy(DiagramFrames.isFrame) { word = n == 1 ? "frame" : "frames" }
        else { word = n == 1 ? "piece" : "pieces" }
        return "\(n) " + (title ? word.prefix(1).uppercased() + word.dropFirst() : word)
    }

    /// The heights a lamp is hung at, in the plan's units.
    static func hangHeights(_ model: DiagramModel) -> [String] {
        model.settings.units == "m"
            ? ["2 m", "2.5 m", "3 m", "3.5 m", "4 m", "5 m", "6 m"]
            : ["6'", "7'", "8'", "9'", "10'", "12'", "14'", "16'", "20'"]
    }

    static func values(_ e: DiagramEl, _ model: DiagramModel) -> [String] {
        switch e.kind {
        // **The same bar as a lamp's** (his note, 2026-10-05): Size, Name,
        // Note, its cloth where a lamp has its Gel, then Opacity.
        case "light" where e.sym == DiagramFrames.sym: return ["framename", "framenote", "framesize", "material", "fade"]
        case "light": return ["name", "piecenote", "swap"]
        case "camera": return ["shot", "camera", "lens"] + (isZoom(e) ? ["focal"] : []) + ["name", "piecenote"]
        case "cast": return ["castname", "piecenote", "pose"]
        case "text", "note": return ["text", "wordsize"]
        case "wall": return ["thickness", "walllength"]
        case "door": return ["doorstyle", "width", "doorstate", "flip"]
        case "window", "opening": return ["width"]
        case "set": return ["name", "piecenote", "swap"]
        case "image": return ["drawon", "setscale", "fade"]
        case "measure": return ["rulerlength"] + (model.pickedCorner.map { $0 < e.corners.count } == true ? ["lockmarker"] : [])
        case "track": return ["tracklength", "name", "piecenote"]
        case "arrow": return ["heads", "line", "piecenote"]
        case "road": return ["name", "piecenote", "roadkind"]
        case "shape": return ["name", "piecenote", "fill"]
        case "cable", "stroke": return ["colour"] + (DiagramNames.notable(e) ? ["piecenote"] : [])
        default: return []
        }
    }

    static func actions(_ e: DiagramEl, _ model: DiagramModel) -> [String] {
        var a: [String] = []
        if e.isWall || e.isPath, let i = model.pickedCorner, i < e.corners.count {
            let end = !e.isClosed && (i == 0 || i == e.corners.count - 1)
            a.append("smooth")
            if e.isWall, !end { a += ["break", "curve"] }
        }
        if model.canClose(e) { a.append("join") }
        return a
    }

    static func isZoom(_ e: DiagramEl) -> Bool {
        if let z = e.zoom, z.count == 2, z[1] > z[0] { return true }
        return false
    }

    /// What is picked, as a checking run reads it: the bar's title, else
    /// the piece's own name.
    static func pickedName(_ model: DiagramModel) -> String {
        let picked = model.shownPicked
        if let t = layout(DiagramPick.of(picked, model), model).title { return t }
        if picked.count == 1, let e = picked.first { return DiagramItems.name(e, model) }
        return "\(picked.count) Selected"
    }

    /// What the bar offers a piece, for a checking run: its settings, then
    /// its actions — the words it shows before it folds.
    func ownActions(_ e: DiagramEl) -> [String] {
        let l = Self.layout(pick, model)
        return l.values + l.actions + ["more"]
    }

    // MARK: the bar

    var body: some View {
        let l = Self.layout(pick, model)
        if level >= 3 {
            HStack(spacing: 4) {
                moreButton(title: l.title ?? "More", bold: l.title != nil, layout: l)
                detailsButton
            }
            .fixedSize()
        } else {
            let shown = level >= 2 ? Array(l.values.prefix(1)) : l.values
            HStack(spacing: 2) {
                if let title = l.title {
                    Text(title).sans(Brand.Size.body, weight: .bold)
                        .foregroundStyle(Brand.ink(dark))
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 4)
                    if !shown.isEmpty { rule }
                }
                ForEach(shown, id: \.self) { value($0) }
                if level < 1, !l.actions.isEmpty {
                    if !shown.isEmpty || l.title != nil { rule }
                    ForEach(l.actions, id: \.self) { action($0) }
                }
                moreButton(title: "More", bold: false, layout: l).padding(.leading, 4)
                detailsButton.padding(.leading, 2)
            }
            .fixedSize()
        }
    }

    /// **Details**, at the end of every fold (2026-10-17): the picked
    /// piece's exact numbers, one click from the piece. The bar steps aside
    /// while it is open; the header's Details shuts it.
    @ViewBuilder private var detailsButton: some View {
        if measuring {
            DiagramMoreFace(title: "Details", bold: false, dark: dark)
        } else {
            Button { model.toggleDetails() } label: {
                DiagramMoreFace(title: "Details", bold: false, dark: dark).contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Details  ⌥⌘I")
            .accessibilityIdentifier("diagram.bar.details")
        }
    }

    /// **More**: a hairline capsule; the pick's one menu.
    @ViewBuilder private func moreButton(title: String, bold: Bool, layout l: (title: String?, values: [String], actions: [String])) -> some View {
        if measuring {
            DiagramMoreFace(title: title, bold: bold, dark: dark)
        } else {
            DiagramMoreButton(title: title, bold: bold, dark: dark) { [self] in moreMenu(l) }
            .popover(isPresented: Binding(get: { focalOpen && level >= 2 && l.values.firstIndex(of: "focal").map { $0 > 0 || level >= 3 } == true },
                                          set: { focalOpen = $0 }), arrowEdge: .top) { focalPicker }
        }
    }

    private func moreMenu(_ l: (title: String?, values: [String], actions: [String])) -> NSMenu {
        // What the width folded away: actions first, then settings.
        var folded: [NSMenuItem] = []
        if level >= 1 { folded += l.actions.map { key in ClosureItem(actionTitle(key)) { [self] in runAction(key) } } }
        let hidden = level >= 3 ? l.values : level >= 2 ? Array(l.values.dropFirst()) : []
        folded += hidden.compactMap(foldedItem)
        return DiagramMenu.picked(model, folded: folded)
    }

    // MARK: faces

    /// A setting as the bar shows it: the quiet word that names it, then
    /// what it is now; a mark only where the mark is the fact.
    private func face(_ label: String, _ value: String?, mark: AnyView? = nil, on: Bool = false) -> some View {
        HStack(spacing: 5) {
            if let mark { mark }
            if !label.isEmpty {
                Text(label).sans(Brand.Size.body, weight: .medium).foregroundStyle(Brand.ink2(dark))
            }
            if let value, !value.isEmpty {
                Text(value).sans(Brand.Size.body, weight: .semibold).monospacedDigit()
                    .foregroundStyle(Brand.ink(dark)).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: 170, alignment: .leading).fixedSize(horizontal: value.count < 26, vertical: false)
            }
        }
        .padding(.horizontal, 8).frame(height: 24)
        .background(Capsule().fill(on ? Brand.glassOn(dark) : .clear))
        .contentShape(Rectangle())
    }

    private func dot(_ hex: String) -> AnyView {
        AnyView(Circle().fill(hex.isEmpty ? Color.clear : Brand.hex(hex.hasPrefix("#") ? String(hex.dropFirst()) : hex))
            .overlay(Circle().strokeBorder(Brand.rule2(dark), lineWidth: hex.isEmpty ? 1 : 0.5))
            .frame(width: 11, height: 11))
    }

    private var rule: some View {
        Rectangle().fill(Brand.rule2(dark)).frame(width: 1, height: 16).padding(.horizontal, 4)
    }

    /// A verb's face: its word in ink.
    private func verbFace(_ title: String) -> some View {
        Text(title).sans(Brand.Size.body, weight: .medium).foregroundStyle(Brand.ink(dark))
            .padding(.horizontal, 7).frame(height: 24).contentShape(Rectangle())
    }

    /// A verb, or a setting that is on or off: filled while it is on.
    private func plain(_ title: String, on: Bool = false, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(title).sans(Brand.Size.body, weight: on ? .semibold : .medium).foregroundStyle(Brand.ink(dark))
                .padding(.horizontal, 7).frame(height: 24)
                .background(Capsule().fill(on ? Brand.glassOn(dark) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func menu<C: View>(_ label: some View, @ViewBuilder _ content: () -> C) -> some View {
        Menu { content() } label: { label }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    /// A button that opens one of the bar's pickers over it.
    private func popping<P: View>(_ key: String, _ label: some View, @ViewBuilder _ picker: @escaping () -> P) -> some View {
        Button { open = key } label: { label }
            .buttonStyle(.plain)
            .popover(isPresented: Binding(get: { open == key }, set: { if !$0 { open = nil } }), arrowEdge: .top) { picker() }
    }

    // MARK: the lamp's words

    private var lamps: [DiagramEl] { pick.lamps }
    private var firstLamp: DiagramEl? { lamps.first }
    private var lampLook: DiagramMarks.Look { DiagramMarks.Look(key: firstLamp?.look ?? "chevron|added|open") }
    private var lampType: String? {
        let t = Set(lamps.map(DiagramMarks.type(of:)))
        return t.count == 1 ? t.first : nil
    }
    private var lampName: String { live(.name, firstLamp?.id, firstLamp?.lamp_name ?? "") }
    private var lampNote: String { live(.note, firstLamp?.id, firstLamp?.label ?? "") }

    /// **What is being typed, as it is typed** (fix round 2): the bar shows
    /// the words on the plan, not what they were.
    private func live(_ what: DiagramTyping.What, _ id: String?, _ stored: String) -> String {
        guard let t = model.typing, t.what == what, let id, t.el == id || t.lamps.contains(id),
              let typed = model.typed else { return stored }
        return typed
    }
    private var lampGels: String {
        let all = lamps.flatMap(\.gels)
        var seen: [String] = []
        for g in all where !seen.contains(g) { seen.append(g) }
        return seen.map(DiagramGels.name).joined(separator: " · ")
    }
    private var offs: [DiagramEl] { lamps.filter { DiagramMarks.type(of: $0) != "film" } }
    private var allDown: Bool { !lamps.isEmpty && lamps.allSatisfy(DiagramMarks.pointsDown) }
    private var hangHeight: String {
        let h = Set(lamps.map(\.height))
        return h.count == 1 ? (h.first.flatMap { $0.isEmpty ? nil : $0 } ?? "None") : "Mixed"
    }
    private var sharedLabelEl: DiagramEl? {
        if case .shared(let label, _) = pick { return label }
        return nil
    }
    private var sharedNote: String {
        guard let label = sharedLabelEl else { return "" }
        return live(.note, label.id, firstLamp.map(model.noteOf) ?? "")
    }
    private var allOff: Bool { !offs.isEmpty && offs.allSatisfy { $0.action == "off" } }

    private var symbolFace: some View {
        face("", nil, mark: AnyView(
            DiagramMarkGlyph(mark: lampLook.mark, ink: lampLook.ink, solid: lampLook.solid, dark: dark, colours: model.settings.colours)
                .frame(width: 20, height: 16)))
    }

    private var symbolPicker: some View {
        let ids = lamps.map(\.id)
        let first = firstLamp
        return DiagramMarkPicker(current: lampLook, type: lampType ?? "film",
                                 pickType: { t in model.update(ids, DiagramMarks.typeSet(t)) }) { l in
            if let first { model.update(ids, DiagramMarks.markSet(l, first)) }
            open = nil
        }
    }

    private var countPicker: some View {
        let e = firstLamp
        let n = Int(e?.count ?? 1)
        return HStack(spacing: 8) {
            Text("Count").sans(Brand.Size.body, weight: .medium).foregroundStyle(Brand.ink2(dark))
            NumberField(value: Double(n), unit: "") { v in
                if let e { model.update([e.id], ["count": min(max(v.rounded(), 1), 999)]) }
            }
            .frame(width: 56)
            Stepper("", onIncrement: { if let e { model.update([e.id], ["count": Double(min(n + 1, 999))]) } },
                    onDecrement: { if let e { model.update([e.id], ["count": Double(max(n - 1, 1))]) } })
                .labelsHidden()
        }
        .padding(12)
    }

    private var gelMenu: some View {
        let ids = lamps
        return menu(face("Gel", lampGels)) {
            ForEach(DiagramGels.groups, id: \.0) { group, gels in
                Section(group) {
                    ForEach(gels) { g in
                        let all = ids.allSatisfy { $0.gels.contains(g.id) }
                        Toggle(g.name, isOn: Binding(get: { all }, set: { _ in
                            for l in ids {
                                let next = all ? l.gels.filter { $0 != g.id } : (l.gels.contains(g.id) ? l.gels : l.gels + [g.id])
                                model.setGels([l.id], next)
                            }
                        }))
                    }
                }
            }
            if ids.contains(where: { !$0.gels.isEmpty }) {
                Divider()
                Button("No Gel") { model.setGels(ids.map(\.id), []) }
            }
        }
    }

    // MARK: settings

    @ViewBuilder private func value(_ key: String) -> some View {
        if measuring {
            plainValue(key)
        } else {
            liveValue(key)
        }
    }

    /// A setting's face alone, for measuring: what each control wears.
    @ViewBuilder private func plainValue(_ key: String) -> some View {
        switch key {
        case "symbol": symbolFace
        case "lampname": face("Name", lampName)
        case "count": face("Count", "\(Int(firstLamp?.count ?? 1))")
        case "note": face("Note", lampNote)
        case "gel": face("Gel", lampGels)
        case "off": face("Off", nil, on: allOff)
        case "down": face("Down", nil, on: allDown)
        case "hangheight": face("Height", hangHeight)
        case "sharednote": face("Note", sharedNote)
        case "align": verbFace("Align")
        default:
            if let e = one { oneFace(key, e) }
        }
    }

    @ViewBuilder private func liveValue(_ key: String) -> some View {
        switch key {
        case "symbol": popping("symbol", symbolFace) { symbolPicker }
        // **Name types on the plan** (his call F): the cursor goes into the
        // lamp's words, the light library listed under them as he types.
        case "lampname":
            Button { if let first = firstLamp { model.startTyping(first.id, .name) } } label: { face("Name", lampName) }
                .buttonStyle(.plain)
        case "count": popping("count", face("Count", "\(Int(firstLamp?.count ?? 1))")) { countPicker }
        case "note":
            Button { if let first = firstLamp { model.startTyping(first.id, .note) } } label: { face("Note", lampNote) }
                .buttonStyle(.plain)
        case "gel": gelMenu
        case "off":
            plain("Off", on: allOff) { model.update(offs.map(\.id), ["action": allOff ? "" : "off"]) }
        case "down":
            plain("Down", on: allDown) { model.update(lamps.map(\.id), ["tilt": allDown ? 90.0 : 0.0]) }
        case "hangheight":
            menu(face("Height", hangHeight)) {
                ForEach(Self.hangHeights(model), id: \.self) { h in
                    Button(h) { model.update(lamps.map(\.id), ["height": h]) }
                }
                Divider()
                Button("None") { model.update(lamps.map(\.id), ["height": ""]) }
            }
        case "sharednote":
            Button { if let label = sharedLabelEl { model.startTyping(label.id, .note) } } label: { face("Note", sharedNote) }
                .buttonStyle(.plain)
        case "align":
            menu(verbFace("Align")) {
                ForEach([("left", "Left"), ("hcentre", "Centre"), ("right", "Right")], id: \.0) { k, t in Button(t) { model.align(k) } }
                Divider()
                ForEach([("top", "Top"), ("vcentre", "Middle"), ("bottom", "Bottom")], id: \.0) { k, t in Button(t) { model.align(k) } }
                if model.selection.count > 2 {
                    Divider()
                    Button("Space Evenly Across") { model.distribute("x") }
                    Button("Space Evenly Down") { model.distribute("y") }
                }
            }
        default:
            if let e = one { oneValue(key, e) }
        }
    }

    // MARK: one piece's settings

    private func frameSize(_ e: DiagramEl) -> String {
        let ft = 0.3048
        let tall = e.tall > 0 ? e.tall : e.h
        return DiagramPlotFrameFields.sizes.first { abs($0.1 * ft - e.h) < 0.05 && abs($0.2 * ft - tall) < 0.05 }?.0 ?? "Custom"
    }

    /// What he typed on it, nothing else (2026-10-17).
    private func pieceName(_ e: DiagramEl) -> String { e.label }

    private var castField: String {
        state.view?.columns.first { ($0.label ?? "").lowercased() == "cast" }?.name ?? "cast"
    }

    private func wallLength(_ e: DiagramEl) -> (String, Int?) {
        let st = e.stretches
        if let s = model.pickedStretch.flatMap({ $0 < st.count ? $0 : nil }) ?? (st.count == 1 ? 0 : nil) {
            return (model.length(model.shownLength(e, s)), s)
        }
        let r = e.run
        return (model.length(zip(r, r.dropFirst()).reduce(0) { $0 + Double(hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y)) }), nil)
    }

    private func rulerLength(_ e: DiagramEl) -> String {
        let c = e.corners
        return model.length(zip(c, c.dropFirst()).reduce(0.0) { $0 + Double(hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y)) })
    }

    /// A dolly track's length and its pieces: "24 ft · 3 × 8'".
    private func trackLength(_ e: DiagramEl) -> String {
        let len = Double(hypot(e.x2 - e.x, e.y2 - e.y))
        var text = model.length(len)
        if model.settings.units != "m", len > 0.1 {
            let pieces = Int((len / (8 * 0.3048)).rounded(.up))
            text += " · \(pieces) × 8'"
        }
        return text
    }

    private func doorState(_ e: DiagramEl) -> String {
        let slides = DoorStyle.of(e).slides
        return e.swing <= 0.5 ? "closed" : (slides && e.swing < 89.5 ? "half" : "open")
    }

    private func headsName(_ e: DiagramEl) -> String {
        switch e.head.isEmpty ? "end" : e.head { case "both": return "Both"; case "none": return "None"; default: return "One" }
    }

    @ViewBuilder private func oneFace(_ key: String, _ e: DiagramEl) -> some View {
        switch key {
        case "framesize": face("Size", frameSize(e))
        case "framename": face("Name", live(.name, e.id, e.lamp_name ?? ""))
        case "framenote": face("Note", live(.note, e.id, e.label))
        case "piecenote": face("Note", live(.note, e.id, e.caption ?? ""))
        case "material": DiagramFrameActions(model: model, e: e, what: "material", measuring: true)
        case "name": face("Name", live(.label, e.id, pieceName(e)))
        case "swap": face("Swap…", nil)
        case "shot": face("Shot", Self.shotText(e, state))
        case "camera": face("Camera", Self.cameraText(e))
        case "lens": face("Lens", Self.lensText(e))
        case "focal": face("Focal", "\(Int((e.focal ?? 0).rounded()))mm")
        case "castname": face("Name", e.label.isEmpty ? e.cast : e.label)
        case "pose": HStack(spacing: 0) { ForEach(["Standing", "Seated", "Lying"], id: \.self) { face($0, nil) } }
        case "text": face("Text", live(.text, e.id, e.text).components(separatedBy: "\n").first ?? "")
        case "wordsize": HStack(spacing: 0) { face("Regular", nil); face("Large", nil) }
        case "thickness": thicknesses(e)
        case "walllength": face("Length", wallLength(e).0)
        case "width": face("Width", model.length(e.w))
        case "doorstyle": face("Style", DoorStyle.of(e).title)
        case "doorstate": HStack(spacing: 0) { ForEach(DoorStyle.of(e).slides ? ["Closed", "Half", "Open"] : ["Closed", "Open"], id: \.self) { face($0, nil) } }
        case "flip": face("Flip", nil)
        case "drawon": face("Draw on Photo", nil)
        case "setscale": face("Set Scale", nil)
        case "fade": face("Opacity", "\(Int((e.opacity * 100).rounded()))%")
        case "rulerlength": face("Length", rulerLength(e))
        case "lockmarker": face("Lock To", lockedName(e) ?? "None")
        case "tracklength": face("Length", trackLength(e))
        case "heads": face("Heads", headsName(e))
        case "line": face("Line", e.dash.isEmpty ? "Solid" : e.dash.capitalized)
        case "roadkind": face("Kind", DiagramActions.roadKinds.first { abs(e.thick - $0.1) < 0.05 }?.0 ?? "Custom")
        case "fill": face("Fill", nil, on: e.fill)
        case "colour": face("Color", nil, mark: dot(e.color))
        default: EmptyView()
        }
    }

    @ViewBuilder private func oneValue(_ key: String, _ e: DiagramEl) -> some View {
        switch key {
        case "framesize":
            menu(oneFace(key, e)) {
                ForEach(DiagramPlotFrameFields.sizes, id: \.0) { s in
                    Button(s.0) { model.update([e.id], ["h": s.1 * 0.3048, "tall": s.2 * 0.3048]) }
                }
            }
        case "material": DiagramFrameActions(model: model, e: e, what: "material")
        case "framename":
            Button { model.startTyping(e.id, .name) } label: { oneFace(key, e) }.buttonStyle(.plain)
        case "framenote", "piecenote":
            Button { model.startTyping(e.id, .note) } label: { oneFace(key, e) }.buttonStyle(.plain)
        case "name":
            Button { model.startTyping(e.id, .label) } label: { oneFace(key, e) }.buttonStyle(.plain)
        case "swap": plain("Swap…") { model.swapping = e.id }
        case "shot": shotMenu(e)
        case "camera": cameraMenu(e)
        case "lens": lensMenu(e)
        case "focal": focalValue(e)
        case "castname":
            let names = state.engine?.vocabulary(castField) ?? []
            menu(oneFace(key, e)) {
                ForEach(names, id: \.self) { n in Button(n) { model.update([e.id], ["label": n, "cast": n]) } }
                if names.isEmpty { Text("No Cast") }
                if DiagramNames.renamable(e) {
                    Divider()
                    Button("Type a Name") { model.startTyping(e.id, .label) }
                }
            }
        case "pose":
            let now = e.pose.isEmpty ? "standing" : e.pose
            HStack(spacing: 0) {
                ForEach([("standing", "Standing"), ("seated", "Seated"), ("lying", "Lying")], id: \.0) { v, t in
                    plain(t, on: now == v) { model.update([e.id], ["pose": v]) }
                }
            }
        case "text":
            Button { model.startTyping(e.id, .text) } label: { oneFace(key, e) }.buttonStyle(.plain)
        case "wordsize":
            let large = DiagramTyping.isLarge(e.size)
            HStack(spacing: 0) {
                plain("Regular", on: !large) { model.update([e.id], ["size": DiagramTyping.wordsRegular]) }
                plain("Large", on: large) { model.update([e.id], ["size": DiagramTyping.wordsLarge]) }
            }
        case "thickness": thicknesses(e)
        case "walllength":
            let (_, stretch) = wallLength(e)
            if let s = stretch {
                popping("walllength", oneFace(key, e)) {
                    Field(e.isClosed ? "Inside Length" : "Length") {
                        LengthField(model: model, value: model.shownLength(e, s)) { model.setWallLength(e, $0, stretch: s) }
                    }
                    .frame(width: 150).padding(12)
                }
            } else {
                oneFace(key, e)
            }
        case "width":
            popping("width", oneFace(key, e)) {
                Field("Width") { LengthField(model: model, value: e.w) { model.update([e.id], ["w": max($0, 0.2)]) } }
                    .frame(width: 150).padding(12)
            }
        case "doorstyle":
            menu(oneFace(key, e)) {
                ForEach(DoorStyle.allCases) { k in
                    Button(k.title) { model.update([e.id], k.change(e)) }
                }
            }
        case "doorstate":
            let slides = DoorStyle.of(e).slides
            let now = doorState(e)
            HStack(spacing: 0) {
                ForEach(slides ? [("closed", "Closed"), ("half", "Half"), ("open", "Open")] : [("closed", "Closed"), ("open", "Open")], id: \.0) { v, t in
                    plain(t, on: now == v) { model.update([e.id], ["swing": v == "closed" ? 0 : v == "half" ? 45 : 90]) }
                }
            }
        case "flip": plain("Flip") { model.update([e.id], DoorStyle.of(e).paired ? ["flip": !e.flip] : ["hinge": e.hinge == "right" ? "" : "right"]) }
        case "drawon": plain("Draw on Photo") { model.drawOnPhoto(e.id) }
        case "setscale": plain("Set Scale") { model.calibrating = e.id }
        case "fade":
            menu(oneFace(key, e)) {
                ForEach([100, 85, 70, 50, 30], id: \.self) { n in
                    Button("\(n)%") { model.update([e.id], ["opacity": Double(n) / 100]) }
                }
            }
        case "rulerlength", "tracklength": oneFace(key, e)
        case "lockmarker": lockMenu(e)
        case "heads":
            menu(oneFace(key, e)) {
                ForEach([("end", "One"), ("both", "Both"), ("none", "None")], id: \.0) { v, t in Button(t) { model.update([e.id], ["head": v]) } }
            }
        case "line":
            menu(oneFace(key, e)) {
                ForEach(["Solid", "Dashed", "Dotted"], id: \.self) { t in Button(t) { model.update([e.id], ["dash": t == "Solid" ? "" : t.lowercased()]) } }
            }
        case "roadkind":
            menu(oneFace(key, e)) {
                ForEach(DiagramActions.roadKinds, id: \.0) { k in Button(k.0) { model.update([e.id], ["thick": k.1]) } }
            }
        case "fill": plain("Fill", on: e.fill) { model.update([e.id], ["fill": !e.fill]) }
        case "colour": colourMenu(e)
        default: EmptyView()
        }
    }

    // MARK: a camera

    static func shotText(_ e: DiagramEl, _ state: ShellState) -> String {
        guard !e.shot.isEmpty, let row = state.view?.allRows.first(where: { $0.shot == e.shot }) else { return "None" }
        return row.number
    }

    static func cameraText(_ e: DiagramEl) -> String {
        (e.cam_unit_label ?? "").isEmpty ? "None" : e.cam_unit_label!
    }

    /// What the bar calls a camera's lens: the film's lens by name, a zoom
    /// where it is set, or a bare focal length.
    static func lensText(_ e: DiagramEl) -> String {
        let name = e.lens_text ?? ""
        if !name.isEmpty { return name }
        return e.lens > 0 ? "\(Int(e.lens.rounded()))mm" : "None"
    }

    /// **The shot this camera is**: link one of the scene's, a new one,
    /// show it in the shot list, or let it go.
    private func shotMenu(_ e: DiagramEl) -> some View {
        let rows = state.rows(of: state.diagramScene)
        return menu(face("Shot", Self.shotText(e, state))) {
            if !e.shot.isEmpty {
                Button("Show in Shot List") { model.showInShotList(e.shot) }
                Button("Unlink") { model.update([e.id], ["shot": ""]) }
                Divider()
            }
            Button("New Shot") { newShot(e) }
            if !rows.isEmpty {
                Divider()
                ForEach(rows) { r in
                    Button("\(r.number)  \(r.description.prefix(40))") { model.update([e.id], ["shot": r.shot]) }
                }
            }
        }
    }

    private func newShot(_ e: DiagramEl) {
        guard let engine = state.engine, let scene = state.diagramScene else { return }
        let before = Set(state.rows(of: scene).map(\.shot))
        state.replace(engine.addShot(scene: scene))
        if let fresh = state.rows(of: scene).first(where: { !before.contains($0.shot) }) {
            model.update([e.id], ["shot": fresh.shot])
        }
    }

    /// **The film's Lens list, and nothing else** — his ask, 2026-10-01: no
    /// built-in focal lengths, only the lenses he made.
    private func lensMenu(_ e: DiagramEl) -> some View {
        let film = state.engine?.vocabulary("lens") ?? []
        return menu(face("Lens", Self.lensText(e))) {
            ForEach(film, id: \.self) { v in Button(v) { model.setLens(e, name: v) } }
            if film.isEmpty { Text("No Lenses") }
        }
    }

    /// **One of the film's cameras** (Project Settings → Cameras) — A-Cam,
    /// with the sensor he typed for it. Written to the shot.
    private func cameraMenu(_ e: DiagramEl) -> some View {
        let units = state.view?.units ?? []
        return menu(face("Camera", Self.cameraText(e))) {
            ForEach(units) { u in
                Button(u.sensorText.map { "\(u.label)  \($0)" } ?? u.label) { model.setCamera(e, unit: u.id) }
            }
            if units.isEmpty { Text("No Cameras") }
        }
    }

    /// **A zoom's focal length, from the bar** (his ask, 2026-10-02): a
    /// slider across the zoom, the cone following as it moves.
    private func focalValue(_ e: DiagramEl) -> some View {
        Button { focalOpen = true } label: { face("Focal", "\(Int((e.focal ?? 0).rounded()))mm", on: focalOpen) }
            .buttonStyle(.plain)
            .popover(isPresented: Binding(get: { focalOpen && level < 2 || (focalOpen && level == 2 && Self.layout(pick, model).values.first == "focal") },
                                          set: { focalOpen = $0 }), arrowEdge: .top) { focalPicker }
    }

    @ViewBuilder private var focalPicker: some View {
        if let e = one, let z = e.zoom, z.count == 2, z[1] > z[0] {
            DiagramFocalPicker(model: model, id: e.id, range: z[0]...z[1], value: e.focal ?? z[0])
        }
    }

    // MARK: the rest

    private func colourMenu(_ e: DiagramEl) -> some View {
        let none = DiagramActions.colours(e) ?? false
        return menu(face("Color", nil, mark: dot(e.color))) {
            Picker("Color", selection: Binding(get: { e.color.uppercased() },
                                                set: { model.update([e.id], ["color": $0]) })) {
                if none { Text("None").tag("") }
                ForEach(Array(Columns.palette.enumerated()), id: \.offset) { i, hex in
                    Text(Columns.paletteNames[i]).tag("#" + hex.uppercased())
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Other Color…") {
                ColourPanel.shared.open(e.color) { model.update([e.id], ["color": $0]) }
            }
        }
    }

    /// The pieces a ruler's marker can lock to: anything on the plan that
    /// can be stood on, by name.
    private var lockable: [DiagramEl] {
        model.plan.els.filter { !$0.isLine && !$0.isPolyline && !["image", "text", "note", "shape"].contains($0.kind) && !$0.hidden }
    }

    private func lockedName(_ e: DiagramEl) -> String? {
        model.pickedCorner.flatMap { e.lock($0) }.flatMap { id in model.el(id).map { model.lockName($0) } }
    }

    /// **Lock the picked marker to a person or object** — its marker then
    /// follows it.
    private func lockMenu(_ e: DiagramEl) -> some View {
        menu(face("Lock To", lockedName(e) ?? "None")) {
            ForEach(lockable) { p in Button(model.lockName(p)) { model.lockMarker(e, to: p.id) } }
            if lockable.isEmpty { Text("Nothing to Lock To") }
        }
    }

    static let thicknessNames = ["Hairline", "Thin", "Standard", "Thick", "Very Thick"]

    /// **A wall's thickness, five pictures, one tap** (Scenario's) —
    /// hairline to very thick, no numbers to type. The one it is, filled.
    private func thicknesses(_ e: DiagramEl) -> some View {
        let drawn: [CGFloat] = [1, 2.5, 4, 6, 8.5]
        let list = model.wallThicknesses
        return HStack(spacing: 1) {
            Text("Thickness").sans(Brand.Size.body, weight: .medium).foregroundStyle(Brand.ink2(dark))
                .padding(.leading, 6).padding(.trailing, 3)
            ForEach(0..<list.count, id: \.self) { i in
                let on = abs(e.thick - list[i]) < 0.002
                Button { model.update([e.id], ["thick": list[i]]) } label: {
                    RoundedRectangle(cornerRadius: 1).fill(Brand.ink(dark))
                        .frame(width: 18, height: drawn[i])
                        .frame(width: 28, height: 24)
                        .background(Capsule().fill(on ? Brand.glassOn(dark) : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(i < Self.thicknessNames.count ? Self.thicknessNames[i] : "")
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: actions

    @ViewBuilder private func action(_ key: String) -> some View {
        switch key {
        case "break": plain("Break") { model.breakCorner() }
        case "smooth":
            let on = one.map { $0.isSmooth(model.pickedCorner ?? -1) } ?? false
            plain("Smooth", on: on) { model.smoothCorner() }
        case "curve":
            let on = one.map { ($0.round ?? []).contains(model.pickedCorner ?? -1) } ?? false
            plain("Round", on: on) { model.roundCorner() }
        case "join": plain("Join") { model.joinWalls() }
        case "group": plain("Group") { model.group() }
        case "sharelabel": plain("Share Label") { model.shareLabel() }
        case "ungroup": plain("Ungroup") { model.ungroup() }
        default: EmptyView()
        }
    }

    private func actionTitle(_ key: String) -> String {
        switch key {
        case "curve": return "Round"
        case "sharelabel": return "Share Label"
        default: return key.prefix(1).uppercased() + key.dropFirst()
        }
    }

    private func runAction(_ key: String) {
        switch key {
        case "break": model.breakCorner()
        case "curve": model.roundCorner()
        case "smooth": model.smoothCorner()
        case "join": model.joinWalls()
        case "group": model.group()
        case "sharelabel": model.shareLabel()
        case "ungroup": model.ungroup()
        default: break
        }
    }

    // MARK: folded into More

    private func sub(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem { DiagramMenu.sub(title, items) }
    private func choice(_ title: String, on: Bool, _ run: @escaping () -> Void) -> NSMenuItem { DiagramMenu.choice(title, on: on, run) }

    /// A setting the width folded away, in More: its own choices where they
    /// fit a menu, else the way to it.
    private func foldedItem(_ key: String) -> NSMenuItem? {
        let m = model
        switch key {
        case "symbol":
            guard let first = firstLamp else { return nil }
            let ids = lamps.map(\.id)
            return sub("Symbol", DiagramMarks.marks.map { mk, name in
                choice(name, on: lampLook.mark == mk) {
                    m.update(ids, DiagramMarks.markSet(DiagramMarks.Look(mark: mk, ink: lampLook.ink, solid: DiagramMarks.solidByDefault.contains(mk)), first))
                }
            })
        case "lampname": return firstLamp.map { f in ClosureItem("Name…") { m.startTyping(f.id, .name) } }
        case "note": return firstLamp.map { f in ClosureItem("Note…") { m.startTyping(f.id, .note) } }
        case "count": return firstLamp.map { DiagramMenu.count($0, m) }
        case "gel": return DiagramMenu.gels(lamps, m)
        case "down":
            let ids = lamps.map(\.id), was = allDown
            return choice("Down", on: was) { m.update(ids, ["tilt": was ? 90.0 : 0.0]) }
        case "hangheight":
            let ids = lamps.map(\.id), now = hangHeight
            return sub("Height", Self.hangHeights(m).map { h in choice(h, on: now == h) { m.update(ids, ["height": h]) } })
        case "sharednote": return sharedLabelEl.map { l in ClosureItem("Note…") { m.startTyping(l.id, .note) } }
        case "off":
            let ids = offs.map(\.id), was = allOff
            return choice("Off", on: was) { m.update(ids, ["action": was ? "" : "off"]) }
        default: break
        }
        guard let e = one else { return nil }
        switch key {
        case "name": return ClosureItem("Name…") { m.startTyping(e.id, .label) }
        case "framename": return ClosureItem("Name…") { m.startTyping(e.id, .name) }
        case "framenote", "piecenote": return ClosureItem("Note…") { m.startTyping(e.id, .note) }
        case "text": return ClosureItem("Text…") { m.startTyping(e.id, .text) }
        case "swap": return ClosureItem("Swap…") { m.swapping = e.id }
        case "framesize":
            return sub("Size · " + frameSize(e), DiagramPlotFrameFields.sizes.map { s in
                choice(s.0, on: frameSize(e) == s.0) { m.update([e.id], ["h": s.1 * 0.3048, "tall": s.2 * 0.3048]) }
            })
        case "material":
            let now = e.material.isEmpty ? DiagramFrames.defaultMaterial(m) : e.material
            var items = DiagramFrames.materials(m).filter { $0.0 != "gel" }.map { id, name in
                choice(name, on: now == id) { m.update([e.id], ["material": id]) }
            }
            items.append(sub("Gel", DiagramGels.groups.flatMap { _, gels in
                gels.map { g in choice(g.name, on: now == "gel" && e.gels.first == g.id) { m.update([e.id], ["material": "gel", "gels": [g.id]]) } }
            }))
            return sub("Material · " + (DiagramFrames.material(e, m)?.name ?? ""), items)
        case "shot":
            let rows = state.rows(of: state.diagramScene)
            return sub("Shot · " + Self.shotText(e, state), [ClosureItem("New Shot") { [self] in newShot(e) }]
                       + rows.map { r in choice("\(r.number)  \(r.description.prefix(40))", on: r.shot == e.shot) { m.update([e.id], ["shot": r.shot]) } })
        case "camera":
            let units = state.view?.units ?? []
            return sub("Camera · " + Self.cameraText(e), units.isEmpty ? [NSMenuItem(title: "No Cameras", action: nil, keyEquivalent: "")]
                       : units.map { u in choice(u.label, on: u.label == e.cam_unit_label) { m.setCamera(e, unit: u.id) } })
        case "lens":
            let film = state.engine?.vocabulary("lens") ?? []
            return sub("Lens · " + Self.lensText(e), film.isEmpty ? [NSMenuItem(title: "No Lenses", action: nil, keyEquivalent: "")]
                       : film.map { v in choice(v, on: v == e.lens_text) { m.setLens(e, name: v) } })
        case "focal":
            return ClosureItem("Focal · \(Int((e.focal ?? 0).rounded()))mm…") { [self] in focalOpen = true }
        case "castname":
            let names = state.engine?.vocabulary(castField) ?? []
            return sub("Name", names.map { n in choice(n, on: e.label == n) { m.update([e.id], ["label": n, "cast": n]) } })
        case "pose":
            let now = e.pose.isEmpty ? "standing" : e.pose
            return sub("Pose", [("standing", "Standing"), ("seated", "Seated"), ("lying", "Lying")].map { v, t in
                choice(t, on: now == v) { m.update([e.id], ["pose": v]) }
            })
        case "wordsize":
            let large = DiagramTyping.isLarge(e.size)
            return sub("Size", [choice("Regular", on: !large) { m.update([e.id], ["size": DiagramTyping.wordsRegular]) },
                                choice("Large", on: large) { m.update([e.id], ["size": DiagramTyping.wordsLarge]) }])
        case "thickness":
            let list = m.wallThicknesses
            return sub("Thickness", list.indices.map { i in
                choice(i < Self.thicknessNames.count ? Self.thicknessNames[i] : "\(i)", on: abs(e.thick - list[i]) < 0.002) { m.update([e.id], ["thick": list[i]]) }
            })
        case "walllength", "width": return ClosureItem(key == "width" ? "Width…" : "Length…") { m.openDetails() }
        case "doorstate":
            let now = doorState(e)
            let states: [(String, String, Double)] = DoorStyle.of(e).slides
                ? [("closed", "Closed", 0), ("half", "Half", 45), ("open", "Open", 90)]
                : [("closed", "Closed", 0), ("open", "Open", 90)]
            let items: [NSMenuItem] = states.map { v, t, swing in
                choice(t, on: now == v) { m.update([e.id], ["swing": swing]) }
            }
            return sub("State", items)
        case "doorstyle":
            let style = DoorStyle.of(e)
            return sub("Style", DoorStyle.allCases.map { k in choice(k.title, on: style == k) { m.update([e.id], k.change(e)) } })
        case "flip": return ClosureItem("Flip") { m.update([e.id], DoorStyle.of(e).paired ? ["flip": !e.flip] : ["hinge": e.hinge == "right" ? "" : "right"]) }
        case "drawon": return ClosureItem("Draw on Photo") { m.drawOnPhoto(e.id) }
        case "setscale": return ClosureItem("Set Scale") { m.calibrating = e.id }
        case "fade": return DiagramMenu.opacity(e, m)
        case "lockmarker":
            return sub("Lock To · " + (lockedName(e) ?? "None"),
                       lockable.isEmpty ? [NSMenuItem(title: "Nothing to Lock To", action: nil, keyEquivalent: "")]
                       : lockable.map { p in ClosureItem(m.lockName(p)) { m.lockMarker(e, to: p.id) } })
        case "heads":
            return sub("Heads", [("end", "One"), ("both", "Both"), ("none", "None")].map { v, t in
                choice(t, on: (e.head.isEmpty ? "end" : e.head) == v) { m.update([e.id], ["head": v]) }
            })
        case "line":
            return sub("Line", ["Solid", "Dashed", "Dotted"].map { t in
                choice(t, on: (e.dash.isEmpty ? "Solid" : e.dash.capitalized) == t) { m.update([e.id], ["dash": t == "Solid" ? "" : t.lowercased()]) }
            })
        case "roadkind":
            return sub("Kind", DiagramActions.roadKinds.map { k in choice(k.0, on: abs(e.thick - k.1) < 0.05) { m.update([e.id], ["thick": k.1]) } })
        case "fill": return choice("Fill", on: e.fill) { m.update([e.id], ["fill": !e.fill]) }
        case "colour":
            let menu = NSMenu()
            DiagramMenu.colour(menu, e, m)
            return menu.items.first.map { item in menu.removeItem(item); return item }
        default: return nil
        }
    }
}

/// **More**, a hairline capsule — the grammar's button — whose menu is an
/// `NSMenu` built when it is pressed, so the keys it lists are shown, never
/// taken: the plan answers them itself, menu open or not.
struct DiagramMoreButton: NSViewRepresentable {
    let title: String
    let bold: Bool
    let dark: Bool
    let menu: () -> NSMenu

    func makeNSView(context: Context) -> NSHostingView<AnyView> {
        let v = MoreHost(rootView: AnyView(EmptyView()))
        v.menu = nil
        return v
    }

    func updateNSView(_ v: NSHostingView<AnyView>, context: Context) {
        v.rootView = AnyView(face)
        (v as? MoreHost)?.build = menu
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSHostingView<AnyView>, context: Context) -> CGSize? {
        let fit = nsView.fittingSize
        return CGSize(width: min(fit.width, proposal.width ?? fit.width), height: fit.height)
    }

    private var face: some View {
        DiagramMoreFace(title: title, bold: bold, dark: dark)
            .environment(\.colorScheme, dark ? .dark : .light)
    }

    final class MoreHost: NSHostingView<AnyView> {
        var build: (() -> NSMenu)?
        /// Up from the button: the bar stands at the foot of the plan.
        override func mouseDown(with event: NSEvent) {
            guard let menu = build?() else { return }
            let up = menu.size.height + 4
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: isFlipped ? -up : bounds.height + up), in: self)
        }
    }
}

/// More's face: its words in a hairline capsule. **No down arrow** (his
/// ruling, 2026-10-04): a menu is a plain button like every other.
struct DiagramMoreFace: View {
    let title: String
    let bold: Bool
    let dark: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text(title).sans(Brand.Size.body, weight: bold ? .bold : .medium).lineLimit(1).truncationMode(.tail)
        }
        .foregroundStyle(Brand.ink(dark))
        .padding(.horizontal, 10).frame(height: 24)
        .overlay(Capsule().strokeBorder(Brand.rule2(dark), lineWidth: 1))
    }
}

/// **A zoom's focal length, dragged** (his ask, 2026-10-02): the zoom's two
/// ends either side of a slider. Each millimetre is written as it goes so the
/// cone on the plan follows the hand, joined into one step of undo.
struct DiagramFocalPicker: View {
    @ObservedObject var model: DiagramModel
    let id: String
    let range: ClosedRange<Double>
    let value: Double
    @State private var draft: Double?
    @State private var started = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let now = draft ?? value
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Focal Length").sans(Brand.Size.small, weight: .medium).foregroundStyle(Brand.ink3(dark))
                Spacer(minLength: 12)
                Text("\(Int(now.rounded()))mm").sans(Brand.Size.title, weight: .semibold).monospacedDigit()
            }
            HStack(spacing: 10) {
                Text("\(Int(range.lowerBound))").sans(Brand.Size.small).foregroundStyle(Brand.ink2(dark)).monospacedDigit()
                Slider(value: Binding(get: { draft ?? value }, set: { write($0.rounded()) }), in: range) { editing in
                    if !editing { started = false; draft = nil }
                }
                .controlSize(.small)
                .frame(width: 200)
                Text("\(Int(range.upperBound))").sans(Brand.Size.small).foregroundStyle(Brand.ink2(dark)).monospacedDigit()
            }
        }
        .foregroundStyle(Brand.ink(dark))
        .padding(12)
    }

    private func write(_ mm: Double) {
        guard mm != (draft ?? value).rounded() || !started else { draft = mm; return }
        draft = mm
        model.edit(["op": "camera_shot", "id": id, "set": ["focal": mm]], join: started)
        started = true
    }
}

/// What the bar offers each kind, and the edits behind it — kept apart from
/// the view so a checking run can make the same edits.
enum DiagramActions {
    static let points = [10, 12, 14, 18, 24, 36, 48]
    static let percents = [50, 75, 100, 125, 150, 200]
    /// A road's kinds, as widths to start from: Street 30 ft, Alley 15 ft,
    /// Driveway 10 ft, Path 4 ft.
    static let roadKinds: [(String, Double)] = [("Street", 9.144), ("Alley", 4.572), ("Driveway", 3.048), ("Path", 1.2192)]

    enum Sizes {
        /// Words: a point size.
        case points([Int])
        /// A piece from the library: a share of its library size.
        case percent([Int], DiagramSymbol)
        /// Anything else with a footprint: a step up or down.
        case step
    }

    /// Whether a piece takes a colour, and if so whether None is one.
    static func colours(_ e: DiagramEl) -> Bool? {
        switch e.kind {
        case "camera", "cast": return false
        case "light", "text", "wall", "arrow", "shape", "cable", "stroke": return true
        default: return nil
        }
    }

    static func sizes(_ e: DiagramEl, _ model: DiagramModel) -> Sizes? {
        switch e.kind {
        case "text": return .points(points)
        case "light", "set":
            if let sym = model.library?.symbols.first(where: { $0.id == e.sym }), sym.w > 0, sym.h > 0 {
                return .percent(percents, sym)
            }
            return .step
        case "cast", "shape", "image", "note": return .step
        default: return nil
        }
    }

    static func emits(_ e: DiagramEl, _ model: DiagramModel) -> Bool {
        (model.library?.symbols.first { $0.id == e.sym }?.beam ?? e.beam) > 0
    }

    /// The piece's size as a share of its library size, to the nearest per cent.
    static func percent(_ e: DiagramEl, _ sym: DiagramSymbol) -> Int {
        Int((e.w / sym.w * 100).rounded())
    }

    static func scaled(_ sym: DiagramSymbol, _ pct: Int) -> [String: Any] {
        ["w": sym.w * Double(pct) / 100, "h": sym.h * Double(pct) / 100]
    }

    /// A camera's lens: on its shot when it stands for one — the lens lives
    /// there, as the Details sidebar has it — else on the camera.
    static func setLens(_ e: DiagramEl, _ mm: Int, model: DiagramModel, state: ShellState?) {
        if !e.shot.isEmpty, let engine = state?.engine,
           state?.view?.allRows.contains(where: { $0.shot == e.shot }) == true {
            state?.replace(engine.set(shot: e.shot, field: "lens", value: "\(mm)mm"))
            if e.lens > 0 { model.update([e.id], ["lens": 0]) } else { model.reload() }
        } else {
            model.update([e.id], ["lens": Double(mm)])
        }
    }
}
