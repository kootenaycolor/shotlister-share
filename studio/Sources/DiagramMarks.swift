import SwiftUI

/// **Marks on the lighting plot** (Labs, his ask 2026-10-03): *"just chose
/// the symbol and click where i want to add lights, then assign them what
/// light they are later."* A mark is written as one word the engine reads
/// (`plot::look_key`): `chevron|added|open` — the mark, its ink, solid or
/// open. These are the pickers that choose one, always as pictures of the
/// marks themselves, never their names alone.
enum DiagramMarks {
    /// A bar or a double bar is a tube: drawn as long as the lamp is.
    static func isTube(_ mark: String) -> Bool { mark == "bar" || mark == "double-bar" }
    /// What a tube starts at, in metres: four feet, a panel two (his call,
    /// 2026-10-04). The lengths a tube comes in follow.
    static func tubeDefault(_ mark: String) -> Double { mark == "double-bar" ? 0.6096 : 1.2192 }
    /// **A mat** (his ask, 2026-10-15): a soft panel seen from above, drawn
    /// at its own width × depth. It starts 4 × 2 ft, then it is his to size.
    static func isMat(_ mark: String) -> Bool { mark == "mat" }
    static let matSize: (w: Double, h: Double) = (1.2192, 0.6096)
    static let tubes: [(String, Double)] = [("2 ft", 0.6096), ("3 ft", 0.9144), ("4 ft", 1.2192), ("6 ft", 1.8288), ("8 ft", 2.4384)]
    static let marks: [(String, String)] = [
        ("chevron", "Chevron"), ("wedge", "Wedge"), ("bar", "Bar"), ("double-bar", "Panel"),
        ("ring", "Ring"), ("dot", "Dot"), ("square", "Square"), ("mat", "Mat"),
    ]
    static let letters: [String] = ["A", "B", "C", "D", "E", "F", "G", "H"]
    static let inks: [(String, String)] = [("added", "Red"), ("practical", "Amber"), ("ink", "Grey"), ("blue", "Blue")]
    static let solidByDefault: Set<String> = ["wedge", "bar", "double-bar", "dot"]

    /// A lamp, as the engine draws one (`plot::is_lamp`): a light that is
    /// not a frame and gives light. **Its mark is never see-through**
    /// (Back to Paper, 2026-10-04), so it has no Opacity to set.
    static func isLamp(_ e: DiagramEl, _ model: DiagramModel) -> Bool {
        e.kind == "light" && e.sym != DiagramFrames.sym && (e.sym.isEmpty || DiagramActions.emits(e, model))
    }

    /// **What can share a label** (`plot::can_share`; his ask, 2026-10-05:
    /// frames and any object): any piece that stands on the plan, not
    /// words, walls, openings or the lines drawn to measure and point.
    static func canShare(_ e: DiagramEl) -> Bool {
        ["light", "set", "camera", "cast", "track", "road", "shape", "image"].contains(e.kind)
    }

    /// A mat's size as one line in the plan's units: "4 × 2 ft", "1.20 × 0.60 m".
    static func sizeText(_ w: Double, _ h: Double, _ model: DiagramModel) -> String {
        let a = model.length(w), b = model.length(h)
        for unit in [" ft", " m", " in"] where a.hasSuffix(unit) && b.hasSuffix(unit) {
            return "\(a.dropLast(unit.count)) × \(b)"
        }
        return "\(a) × \(b)"
    }

    /// A lamp hung pointing straight down (`plot::points_down`): its Lean at nought.
    static func pointsDown(_ e: DiagramEl) -> Bool { e.tilt < 1 }

    struct Look: Equatable {
        var mark: String
        var ink: String
        var solid: Bool
        var key: String { "\(mark)|\(ink)|\(solid ? "solid" : "open")" }

        init(mark: String, ink: String, solid: Bool) {
            (self.mark, self.ink, self.solid) = (mark, ink, solid)
        }
        init(key: String) {
            let p = key.split(separator: "|").map(String.init)
            mark = p.first ?? "chevron"
            ink = p.count > 1 ? p[1] : "added"
            solid = p.count > 2 ? p[2] == "solid" : DiagramMarks.solidByDefault.contains(mark)
        }
    }

    /// **A lamp's Type** (his Ref 1466): Film Light, Practical, Existing —
    /// never Source and Action. The Type is the ink.
    static let types: [(key: String, title: String, ink: String)] = [
        ("film", "Film Light", "added"), ("practical", "Practical", "practical"), ("existing", "Existing", "ink"),
    ]
    static func type(of e: DiagramEl) -> String {
        (e.existing ?? false) ? "existing" : (e.practical ?? false) ? "practical" : "film"
    }
    static func type(ofInk ink: String) -> String {
        types.first { $0.ink == ink }?.key ?? "film"
    }
    static func ink(ofType type: String) -> String {
        types.first { $0.key == type }?.ink ?? "added"
    }
    /// The fields a Type writes. A film light is never Off.
    static func typeSet(_ type: String) -> [String: Any] {
        var set: [String: Any] = ["existing": type == "existing", "practical": type == "practical", "mark_ink": ""]
        if type == "film" { set["action"] = "" }
        return set
    }
    /// The fields a new mark writes, a tube started at its length.
    static func markSet(_ l: Look, _ e: DiagramEl) -> [String: Any] {
        var set: [String: Any] = ["mark": l.mark, "mark_ink": "", "mark_fill": l.solid ? "solid" : "open"]
        if isTube(l.mark), max(e.w, e.h) < 0.4 { set["h"] = tubeDefault(l.mark); set["w"] = 0.3 }
        if isMat(l.mark), max(e.w, e.h) < 0.4 { set["w"] = matSize.w; set["h"] = matSize.h }
        return set
    }
    /// Every light name in the library, short and once each: "Arri M18",
    /// "SkyPanel S60" — not what is hung on it.
    static func names(_ model: DiagramModel) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for s in model.library?.symbols ?? [] where s.light && s.lib == "light" {
            let short = s.name.components(separatedBy: " with ").first ?? s.name
            if seen.insert(short).inserted { out.append(short) }
        }
        return out.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

/// A grid of every mark, in the lamp's colour, each named under it, then
/// Solid. **No colours here** (his call, 2026-10-04: one control per job):
/// a lamp's colour is its Type. Picking a mark keeps the fill; Solid keeps
/// the mark. **Eight to choose from, not sixteen** (Back to Paper,
/// 2026-10-04): the lettered circles wait behind Letters.
struct DiagramMarkPicker: View {
    let current: DiagramMarks.Look
    /// **Film Light · Practical · Existing along the top** (Back to Paper,
    /// Batch 2): the Type is chosen with the mark. Nil leaves the row off.
    var type: String?
    var pickType: ((String) -> Void)?
    let pick: (DiagramMarks.Look) -> Void
    @State private var letters: Bool
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    init(current: DiagramMarks.Look, type: String? = nil, pickType: ((String) -> Void)? = nil,
         pick: @escaping (DiagramMarks.Look) -> Void) {
        self.current = current
        self.type = type
        self.pickType = pickType
        self.pick = pick
        _letters = State(initialValue: current.mark.hasPrefix("letter-"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let type, let pickType {
                HStack(spacing: 4) {
                    ForEach(DiagramMarks.types, id: \.key) { t in
                        ChoicePill(title: t.title, on: type == t.key, dark: dark) { pickType(t.key) }
                    }
                }
                Rectangle().fill(Brand.rule(dark)).frame(height: 1)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(62), spacing: 4), count: 4), spacing: 4) {
                ForEach(DiagramMarks.marks, id: \.0) { m in
                    named(DiagramMarks.Look(mark: m.0, ink: current.ink, solid: current.mark == m.0 ? current.solid : DiagramMarks.solidByDefault.contains(m.0)), name: m.1)
                }
            }
            if letters {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(29), spacing: 3), count: 8), spacing: 3) {
                    ForEach(DiagramMarks.letters, id: \.self) { c in
                        tile(DiagramMarks.Look(mark: "letter-\(c)", ink: current.ink, solid: false), help: "Letter \(c)", size: 29)
                    }
                }
            }
            HStack(spacing: 6) {
                ChoicePill(title: "Letters", on: letters, dark: dark) { letters.toggle() }
                Spacer()
                ChoicePill(title: "Solid", on: current.solid, dark: dark) {
                    pick(DiagramMarks.Look(mark: current.mark, ink: current.ink, solid: !current.solid))
                }
                .disabled(current.mark.hasPrefix("letter-"))
            }
        }
        .padding(12)
    }

    /// A mark with its name under it.
    private func named(_ look: DiagramMarks.Look, name: String) -> some View {
        let on = look.mark == current.mark
        return Button { pick(look) } label: {
            VStack(spacing: 5) {
                DiagramMarkGlyph(mark: look.mark, ink: look.ink, solid: look.solid, dark: dark)
                    .frame(width: 22, height: 18)
                    .frame(width: 30, height: 22)
                Text(name).sans(Brand.Size.small).foregroundStyle(Brand.ink(dark))
            }
            .frame(width: 62)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(on ? Brand.selectionQuiet(dark) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(name)
    }

    private func tile(_ look: DiagramMarks.Look, help: String, size: CGFloat = 40) -> some View {
        let on = look.mark == current.mark
        return Button { pick(look) } label: {
            DiagramMarkGlyph(mark: look.mark, ink: look.ink, solid: look.solid, dark: dark)
                .frame(width: size * 0.55, height: size * 0.45)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: 8).fill(on ? Brand.selectionQuiet(dark) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help)
    }
}

/// The Light tool's palette: pick a mark, then click on the plan to put
/// lights down, as many as you like. **An opaque card** (Back to Paper,
/// 2026-10-04), not see-through glass over the plan.
struct DiagramMarkPalette: View {
    @ObservedObject var model: DiagramModel
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        let look = DiagramMarks.Look(key: model.armedLook)
        DiagramMarkPicker(current: look, type: DiagramMarks.type(ofInk: look.ink),
                          pickType: { t in
                              model.armedLook = DiagramMarks.Look(mark: look.mark, ink: DiagramMarks.ink(ofType: t), solid: look.solid).key
                          }) { model.armedLook = $0.key }
            .frame(width: 300)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.surface(dark)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Brand.rule2(dark).opacity(dark ? 1 : 0.6)))
            .shadow(color: .black.opacity(dark ? 0.45 : 0.16), radius: 10, y: 4)
    }
}

/// **A lamp's Details: its exact numbers** (Back to Paper, Batch 2). What
/// it is and what it says — Symbol, Name, Count, Note, Gel, Off — are the
/// bar's; this is what is typed exactly: how many, a string's spread and
/// length, a tube's length.
struct DiagramLampFields: View {
    @ObservedObject var model: DiagramModel
    let e: DiagramEl
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        let look = DiagramMarks.Look(key: e.look ?? "chevron|added|open")
        let spread = e.spread ?? ""
        HStack(alignment: .bottom, spacing: 10) {
            Field("Count") { NumberField(value: e.count ?? 1, unit: "") { model.update([e.id], ["count": min(max($0.rounded(), 1), 999)]) } }
            // **A mat's size, in the plan's units** ("4 × 2 ft"): typed here
            // or dragged by its corners on the plan; no locked ratio.
            if DiagramMarks.isMat(look.mark), spread.isEmpty {
                Field("Width") { LengthField(model: model, value: e.w) { model.update([e.id], ["w": max($0, 0.05)]) } }
                Field("Depth") { LengthField(model: model, value: e.h) { model.update([e.id], ["h": max($0, 0.05)]) } }
            }
            // **A tube to scale** (his ask, 2026-10-03): length matters on a
            // top-down plan, so a bar is as long as it is set here.
            if DiagramMarks.isTube(look.mark), spread.isEmpty {
                Field("Length") {
                    LengthField(model: model, value: max(e.w, e.h)) { model.update([e.id], ["h": max($0, 0.3), "w": 0.3]) }
                }
            }
        }
        if DiagramMarks.isMat(look.mark), spread.isEmpty {
            Text(DiagramMarks.sizeText(e.w, e.h, model))
                .sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark)).monospacedDigit()
        }
        // **A string of lamps** (his ask, 2026-10-04): one mark, many spots —
        // along a line, bowed if he likes, or round a ring. Count is how many.
        Field("Spread") {
            HStack(spacing: 4) {
                ForEach([("", "One"), ("line", "Line"), ("ring", "Ring")], id: \.0) { s in
                    ChoicePill(title: s.1, on: spread == s.0, dark: dark) { DiagramMenu.setSpread(e, s.0, model) }
                }
            }
        }
        if spread == "line" {
            HStack(alignment: .bottom, spacing: 10) {
                Field("Length") { LengthField(model: model, value: max(e.w, e.h)) { model.update([e.id], ["h": max($0, 0.3), "w": 0.3]) } }
                Field("Bend") { LengthField(model: model, value: e.curve) { model.update([e.id], ["curve": $0]) } }
            }
        } else if spread == "ring" {
            HStack(alignment: .bottom, spacing: 10) {
                Field("Width") { LengthField(model: model, value: e.w) { model.update([e.id], ["w": max($0, 0.3)]) } }
                Field("Depth") { LengthField(model: model, value: e.h) { model.update([e.id], ["h": max($0, 0.3)]) } }
            }
        }
    }
}

/// **A frame's details on the plot** (his ask, 2026-10-03: *"i just want to
/// adjust frame and color"*): its size and what is in it, and its colour.
/// The lean is dragged on the plan.
struct DiagramPlotFrameFields: View {
    @ObservedObject var model: DiagramModel
    let e: DiagramEl
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    static let sizes: [(String, Double, Double)] = [
        ("4×4", 4, 4), ("6×6", 6, 6), ("8×8", 8, 8), ("12×12", 12, 12), ("12×20", 12, 20), ("20×20", 20, 20), ("20×40", 20, 40),
    ]

    var body: some View {
        let ft = 0.3048
        let tall = e.tall > 0 ? e.tall : e.h
        let size = Self.sizes.first { abs($0.1 * ft - e.h) < 0.05 && abs($0.2 * ft - tall) < 0.05 }?.0 ?? "Custom"
        Field("Frame") {
            HStack(spacing: 6) {
                Menu {
                    ForEach(Self.sizes, id: \.0) { s in Button(s.0) { model.update([e.id], ["h": s.1 * ft, "tall": s.2 * ft]) } }
                } label: { FieldFace(text: size, chevron: false, dark: dark) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                .frame(width: 84)
                Menu {
                    ForEach(DiagramFrames.materials(model), id: \.0) { m in Button(m.1) { model.update([e.id], ["material": m.0]) } }
                } label: {
                    let id = e.material.isEmpty ? DiagramFrames.defaultMaterial(model) : e.material
                    FieldFace(text: DiagramFrames.materials(model).first { $0.0 == id }?.1 ?? id, chevron: false, dark: dark)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            }
        }
        // **Its Name is what he types** (2026-10-17), its Note under it.
        Field("Name") { Committing(text: e.lamp_name ?? "", multiline: true) { model.edit(["op": "name_piece", "id": e.id, "name": $0]) } }
        Field("Note") { Committing(text: e.label, multiline: true) { model.update([e.id], ["label": $0]) } }
        Field("Color") { ColourRow(selected: e.color, allowNone: true) { model.update([e.id], ["color": $0]) } }
    }
}

/// **The plot's colours** (his ask, 2026-10-03: *"the colors we start with
/// are good but its always good to be able to change them … and set the
/// default colors across the board for catagories"*): one colour per
/// category, set for every plan in the film at once. Any single piece can
/// still wear its own colour.
struct DiagramColoursPanel: View {
    @ObservedObject var model: DiagramModel
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    static let categories: [(String, String)] = [
        ("added", "Film Lights"), ("practical", "Practicals"), ("existing", "Existing Lights"), ("blue", "Third Ink"),
        ("gripink", "Grip and Frames"), ("camink", "Cameras"), ("plan", "Walls"), ("prop", "Furniture and Props"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Colors").sans(Brand.Size.title, weight: .semibold)
                Spacer()
                Button("Done") { model.showingColours = false }.buttonStyle(.capsule)
            }
            ForEach(Self.categories, id: \.0) { c in
                HStack(spacing: 10) {
                    ColorPicker("", selection: binding(c.0), supportsOpacity: false)
                        .labelsHidden()
                    Text(c.1).sans(Brand.Size.body)
                    Spacer(minLength: 12)
                    if model.settings.colours[c.0] != nil {
                        Button("Reset") { set(c.0, nil) }.buttonStyle(.rowAction)
                    }
                }
            }
            Text("Every plan in this film").sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark))
        }
        .padding(16)
        .frame(width: 290)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Brand.rule(dark)))
    }

    private func binding(_ role: String) -> Binding<Color> {
        Binding(
            get: {
                if let hex = model.settings.colours[role] { return Color(nsColor: Brand.nsHex(String(hex.dropFirst()))) }
                return Color(nsColor: DiagramInk.color(role, dark: dark) ?? .labelColor)
            },
            set: { c in
                let ns = NSColor(c).usingColorSpace(.sRGB) ?? .black
                let hex = String(format: "#%02X%02X%02X", Int(round(ns.redComponent * 255)), Int(round(ns.greenComponent * 255)), Int(round(ns.blueComponent * 255)))
                set(role, hex)
            })
    }

    /// Applied once the colour well settles, not at every step of a drag.
    private func set(_ role: String, _ hex: String?) {
        DiagramColoursPanel.pending[role] = hex ?? ""
        DiagramColoursPanel.settle?.cancel()
        let work = DispatchWorkItem { [model] in
            var now = model.settings.colours
            for (k, v) in DiagramColoursPanel.pending { now[k] = v.isEmpty ? nil : v }
            DiagramColoursPanel.pending = [:]
            model.settingEverywhere("colours", now)
        }
        DiagramColoursPanel.settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (hex == nil ? 0 : 0.35), execute: work)
    }
    @MainActor static var pending: [String: String] = [:]
    @MainActor static var settle: DispatchWorkItem?
}

/// A legend mark, drawn as the plan draws it (`plot::mark`), facing right.
struct DiagramMarkGlyph: View {
    let mark: String
    let ink: String
    let solid: Bool
    let dark: Bool
    /// His colours for the plot's categories (`DiagramSettings.colours`).
    var colours: [String: String] = [:]

    var body: some View {
        Canvas { ctx, size in
            let role = ink == "ink" ? "existing" : ink
            let c = colours[role].map { Color(nsColor: Brand.nsHex(String($0.dropFirst()))) }
                ?? Color(nsColor: DiagramInk.color(role, dark: dark) ?? .labelColor)
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
                // A panel: a box with a heavy front edge.
                let box = Path(CGRect(x: mid.x - s * 0.25, y: mid.y - s * 0.5, width: s * 0.5, height: s))
                if solid { ctx.fill(box, with: .color(c)) } else {
                    ctx.stroke(box, with: .color(c), lineWidth: 1.2)
                    ctx.fill(Path(CGRect(x: mid.x + s * 0.09, y: mid.y - s * 0.5, width: s * 0.16, height: s)), with: .color(c))
                }
            case "ring":
                let r = Path(ellipseIn: CGRect(x: mid.x - s * 0.36, y: mid.y - s * 0.36, width: s * 0.72, height: s * 0.72))
                if solid { ctx.fill(r, with: .color(c)) } else { ctx.stroke(r, with: .color(c), lineWidth: 1.6) }
                let d = Path(ellipseIn: CGRect(x: mid.x - s * 0.13, y: mid.y - s * 0.13, width: s * 0.26, height: s * 0.26))
                ctx.fill(d, with: .color(solid ? Color(nsColor: .textBackgroundColor) : c))
            case "dot":
                let r = Path(ellipseIn: CGRect(x: mid.x - s * 0.3, y: mid.y - s * 0.3, width: s * 0.6, height: s * 0.6))
                solid ? ctx.fill(r, with: .color(c)) : ctx.stroke(r, with: .color(c), lineWidth: 1.6)
            case "mat":
                // A soft panel from above: a wide box, a wash, a fine inner line.
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
