import SwiftUI
import UIKit

// **The diagram's deeper tools on the phone** (parity 3, 2026-10-16): drawing
// walls, rooms, doors, windows and lines by finger; a piece's Details; the
// Layers list; the plan's settings. Every change is one of the engine's own
// `diagramedit` ops, the ones the Mac sends, so the two cannot disagree.

/// What a finger draws while a tool is on.
enum DiagramDraw: String, CaseIterable, Identifiable {
    case wall, room, door, sliding, window, opening, arrow, connector, ruler, shape, pen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wall: return "Wall"
        case .room: return "Room"
        case .door: return "Door"
        case .sliding: return "Sliding Door"
        case .window: return "Window"
        case .opening: return "Opening"
        case .arrow: return "Arrow"
        case .connector: return "Connector"
        case .ruler: return "Ruler"
        case .shape: return "Shape"
        case .pen: return "Draw"
        }
    }

    var hint: String {
        switch self {
        case .wall: return "Tap each corner"
        case .door, .sliding, .window, .opening: return "Tap a wall"
        case .pen: return "Draw"
        default: return "Drag"
        }
    }

    /// Placed by a tap rather than a drag.
    var taps: Bool { [.wall, .door, .sliding, .window, .opening].contains(self) }

    static let set: [DiagramDraw] = [.wall, .room, .door, .sliding, .window, .opening, .shape]
    static let lines: [DiagramDraw] = [.arrow, .connector, .ruler, .pen]
}

/// A plan's element, as the engine wrote it: the full JSON, read by key.
struct DiagramPiece {
    var raw: [String: Any]

    var id: String { raw["id"] as? String ?? "" }
    var kind: String { raw["kind"] as? String ?? "" }
    func s(_ k: String) -> String { raw[k] as? String ?? "" }
    func n(_ k: String, _ d: Double = 0) -> Double { (raw[k] as? NSNumber)?.doubleValue ?? d }
    func b(_ k: String) -> Bool { (raw[k] as? Bool) ?? ((raw[k] as? NSNumber)?.boolValue ?? false) }
    var gels: [String] { raw["gels"] as? [String] ?? [] }
    var isFrame: Bool { kind == "light" && s("sym") == "frame" }
    /// A lamp: a light with a mark, not a frame (`plot::is_lamp`).
    var isLamp: Bool { kind == "light" && !isFrame }
    var corners: Int { (raw["points"] as? [Any])?.count ?? 0 }

    /// What a list calls it: its own name, else its catalogue name, else its kind.
    var shownName: String {
        for k in ["lamp_name", "label", "name", "cast", "text"] where !s(k).isEmpty {
            return s(k).replacingOccurrences(of: "\n", with: " ")
        }
        return DiagramPiece.kindWord(kind)
    }

    static func kindWord(_ k: String) -> String {
        switch k {
        case "light": return "Light"
        case "camera": return "Camera"
        case "cast": return "Cast"
        case "set": return "Piece"
        case "wall": return "Wall"
        case "door": return "Door"
        case "window": return "Window"
        case "opening": return "Opening"
        case "text": return "Words"
        case "note": return "Note"
        case "arrow": return "Arrow"
        case "measure": return "Ruler"
        case "shape": return "Shape"
        case "stroke": return "Drawing"
        case "cable": return "Cable"
        case "track": return "Track"
        case "road": return "Street"
        case "image": return "Picture"
        default: return k.prefix(1).uppercased() + k.dropFirst()
        }
    }

    static func symbol(_ k: String) -> String {
        switch k {
        case "light": return "lightbulb"
        case "camera": return "video"
        case "cast": return "person"
        case "wall": return "square.dashed"
        case "door", "opening": return "door.left.hand.open"
        case "window": return "window.vertical.closed"
        case "text", "note": return "textformat"
        case "arrow": return "arrow.up.right"
        case "measure": return "ruler"
        case "shape": return "square"
        case "stroke", "cable": return "scribble"
        case "track", "road": return "road.lanes"
        case "image": return "photo"
        default: return "cube"
        }
    }

    /// Every piece of a plan, bottom of the stack first, and its settings.
    static func read(_ id: String, engine: Engine?) -> (els: [DiagramPiece], settings: [String: Any]) {
        guard let engine,
              let obj = (try? JSONSerialization.jsonObject(with: engine.raw("diagram", id))) as? [String: Any] else { return ([], [:]) }
        let els = (obj["els"] as? [[String: Any]] ?? []).map(DiagramPiece.init)
        return (els, obj["settings"] as? [String: Any] ?? [:])
    }
}

/// Lengths as the plan's units say them: feet and inches, or metres.
enum DiagramLength {
    static func text(_ metres: Double, metric: Bool) -> String {
        if metric { return String(format: "%.2f m", metres) }
        let inches = (metres / 0.0254).rounded()
        let ft = Int(inches) / 12, inch = Int(inches) % 12
        return inch == 0 ? "\(ft)'" : "\(ft)' \(inch)\""
    }

    /// `6`, `6'`, `6' 4`, `6'4"`, `6.5`, `76"` in feet; a number in metres.
    static func parse(_ text: String, metric: Bool) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        if metric {
            let n = t.replacingOccurrences(of: "m", with: "").trimmingCharacters(in: .whitespaces)
            return Double(n).flatMap { $0 > 0 ? $0 : nil }
        }
        if t.hasSuffix("\""), !t.contains("'"), let i = Double(t.dropLast().trimmingCharacters(in: .whitespaces)) {
            return i * 0.0254
        }
        let parts = t.replacingOccurrences(of: "\"", with: "").split(separator: "'", omittingEmptySubsequences: false)
        let ft = Double(parts.first?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0
        let inch = parts.count > 1 ? Double(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0 : 0
        let m = (ft * 12 + inch) * 0.0254
        return m > 0 ? m : nil
    }
}

/// A colour as the plan stores it, `#RRGGBB`.
private func hexOf(_ c: Color) -> String {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
    return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
}

/// A length typed into a row, written when he is done typing.
private struct LengthRow: View {
    let title: String
    let metres: Double
    let metric: Bool
    let set: (Double) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent(title) {
            TextField(title, text: $text)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numbersAndPunctuation)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, now in if !now { commit() } }
        }
        .onAppear { text = DiagramLength.text(metres, metric: metric) }
        .onChange(of: metres) { _, now in if !focused { text = DiagramLength.text(now, metric: metric) } }
    }

    private func commit() {
        if let m = DiagramLength.parse(text, metric: metric), abs(m - metres) > 0.001 { set(m) }
        else { text = DiagramLength.text(metres, metric: metric) }
    }
}

/// Words typed into a row, written on Return or leaving it.
private struct WordsRow: View {
    let title: String
    let value: String
    var axis: Axis = .horizontal
    let set: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $text, axis: axis)
            .focused($focused)
            .onSubmit { if text != value { set(text) } }
            .onChange(of: focused) { _, now in if !now, text != value { set(text) } }
            .onAppear { text = value }
            .onChange(of: value) { _, now in if !focused { text = now } }
    }
}

// MARK: - Details

/// **A piece's Details** (the Mac's Details panel and its action bar's
/// settings): what the piece is decides the rows. Every change writes at once
/// and the sheet reads the piece back.
struct DiagramDetailsSheet: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    let plan: String
    let pieceId: String
    let beat: Int
    /// One edit, as the editor sends it (one undo each).
    let edit: ([String: Any]) -> Void

    @State private var piece: DiagramPiece?
    @State private var settings: [String: Any] = [:]
    @State private var materials: [(id: String, name: String)] = []

    private var metric: Bool { settings["units"] as? String == "m" }

    static let gels: [(String, [(String, String)])] = [
        ("Color Temperature", [("cto-quarter", "¼ CTO"), ("cto-half", "½ CTO"), ("cto-3q", "¾ CTO"), ("cto-full", "Full CTO"),
                               ("ctb-quarter", "¼ CTB"), ("ctb-half", "½ CTB"), ("ctb-full", "Full CTB")]),
        ("Neutral Density", [("nd3", "ND .3"), ("nd6", "ND .6"), ("nd9", "ND .9")]),
        ("Green", [("plus-green-quarter", "¼ Plus Green"), ("plus-green-half", "½ Plus Green"),
                   ("minus-green-quarter", "¼ Minus Green"), ("minus-green-half", "½ Minus Green")]),
        ("Diffusion", [("opal", "Opal"), ("216", "216"), ("250", "250"), ("hampshire", "Hampshire")]),
    ]
    static let marks: [(String, String)] = [
        ("chevron", "Chevron"), ("wedge", "Wedge"), ("bar", "Bar"), ("double-bar", "Panel"),
        ("ring", "Ring"), ("dot", "Dot"), ("square", "Square"), ("mat", "Mat"),
    ]
    static let frameSizes: [(String, Double, Double)] = [
        ("4×4", 4, 4), ("6×6", 6, 6), ("8×8", 8, 8), ("12×12", 12, 12), ("12×20", 12, 20), ("20×20", 20, 20), ("20×40", 20, 40),
    ]
    static let thicknessNames = ["Hairline", "Thin", "Standard", "Thick", "Very Thick"]

    var body: some View {
        NavigationStack {
            Form {
                if let p = piece { rows(p) } else { Text("Nothing picked").foregroundStyle(.secondary) }
            }
            .navigationTitle(piece.map { DiagramPiece.kindWord($0.kind) } ?? "Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task {
            reload()
            struct L: Decodable { var frames: F?; struct F: Decodable { var materials: [M] }; struct M: Decodable { var id: String; var name: String } }
            if let data = session.engine?.raw("diagramlibrary"), let l = try? JSONDecoder().decode(L.self, from: data) {
                materials = (l.frames?.materials ?? []).map { ($0.id, $0.name) }
            }
        }
    }

    private func reload() {
        let r = DiagramPiece.read(plan, engine: session.engine)
        piece = r.els.first { $0.id == pieceId }
        settings = r.settings
    }

    private func set(_ values: [String: Any]) {
        edit(["op": "update", "ids": [pieceId], "set": values])
        reload()
    }

    private func op(_ o: [String: Any]) { edit(o); reload() }

    // ---- the rows, by kind ---------------------------------------------------

    @ViewBuilder private func rows(_ p: DiagramPiece) -> some View {
        switch p.kind {
        case "light" where p.isFrame: frame(p)
        case "light": lamp(p)
        case "camera": camera(p)
        case "cast": cast(p)
        case "text", "note": words(p)
        case "wall": wall(p)
        case "door": door(p)
        case "window", "opening":
            Section { LengthRow(title: "Width", metres: p.n("w"), metric: metric) { set(["w": max($0, 0.2)]) } }
        case "arrow": arrow(p)
        case "set", "shape", "track", "road": piece(p)
        default:
            Section { colour(p) ; note(p, key: "caption") }
        }
        layerRows(p)
        place(p)
    }

    /// What he types, on as many lines as he likes (2026-10-17).
    private func name(_ p: DiagramPiece) -> some View {
        WordsRow(title: "Name", value: p.s("label"), axis: .vertical) { set(["label": $0]) }
    }

    /// **Send to Set / Plot, Copy to …** (his ask, 2026-10-17).
    @ViewBuilder private func layerRows(_ p: DiagramPiece) -> some View {
        if !["wall", "door", "window", "opening", "road", "cast"].contains(p.kind) {
            let to = p.s("layer") == "set" ? "plot" : "set"
            let name = to == "set" ? "Set" : "Plot"
            Section {
                Button("Send to \(name)") { op(["op": "send_layer", "ids": [pieceId], "to": to]) }
                Button("Copy to \(name)") { op(["op": "send_layer", "ids": [pieceId], "to": to, "copy": true]) }
            }
        }
    }

    private func note(_ p: DiagramPiece, key: String) -> some View {
        WordsRow(title: "Note", value: p.s(key), axis: .vertical) { set([key: $0]) }
    }

    private func colour(_ p: DiagramPiece, allowNone: Bool = true) -> some View {
        HStack {
            ColorPicker("Color", selection: Binding(
                get: { p.s("color").isEmpty ? Color(.label) : Color(hex: String(p.s("color").dropFirst())) },
                set: { set(["color": hexOf($0)]) }), supportsOpacity: false)
            if allowNone, !p.s("color").isEmpty {
                Button("Clear") { set(["color": ""]) }.buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder private func lamp(_ p: DiagramPiece) -> some View {
        Section {
            WordsRow(title: "Name", value: p.s("lamp_name"), axis: .vertical) {
                op(["op": "name_piece", "id": pieceId, "name": $0.trimmingCharacters(in: .whitespaces)])
            }
            WordsRow(title: "Note", value: p.s("label"), axis: .vertical) { set(["label": $0]) }
        }
        Section {
            Picker("Type", selection: Binding(get: { p.b("existing") ? "existing" : p.b("practical") ? "practical" : "film" },
                                              set: { t in
                var v: [String: Any] = ["existing": t == "existing", "practical": t == "practical", "mark_ink": ""]
                if t == "film" { v["action"] = "" }
                set(v)
            })) {
                Text("Film Light").tag("film"); Text("Practical").tag("practical"); Text("Existing").tag("existing")
            }
            Picker("Symbol", selection: Binding(get: { p.s("mark").isEmpty ? "chevron" : p.s("mark") }, set: { mk in
                var v: [String: Any] = ["mark": mk, "mark_ink": "",
                                        "mark_fill": ["wedge", "bar", "double-bar", "dot"].contains(mk) ? "solid" : "open"]
                if mk == "mat", max(p.n("w"), p.n("h")) < 0.4 { v["w"] = 1.2192; v["h"] = 0.6096 }
                set(v)
            })) { ForEach(Self.marks, id: \.0) { Text($0.1).tag($0.0) } }
            Picker("Count", selection: Binding(get: { max(1, Int(p.n("count", 1))) }, set: { set(["count": Double($0)]) })) {
                ForEach(1...12, id: \.self) { Text("\($0)").tag($0) }
            }
        }
        Section("Gels") {
            ForEach(Self.gels, id: \.0) { group, list in
                DisclosureGroup(group) {
                    ForEach(list, id: \.0) { id, title in
                        Button {
                            let now = p.gels
                            set(["gels": now.contains(id) ? now.filter { $0 != id } : now + [id]])
                        } label: {
                            HStack {
                                Text(title).foregroundStyle(Color(.label))
                                Spacer()
                                if p.gels.contains(id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                    }
                }
            }
        }
        Section {
            LabeledContent("Dimmer") {
                Slider(value: Binding(get: { p.n("dim", 100) }, set: { set(["dim": ($0).rounded()]) }), in: 0...100, step: 5)
                    .frame(maxWidth: 180)
                Text("\(Int(p.n("dim", 100)))%").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
            }
            Picker("Color Temperature", selection: Binding(get: { Int(p.n("kelvin", 5600)) }, set: { set(["kelvin": Double($0)]) })) {
                ForEach(Array(Set([2700, 3200, 4300, 5600, 6500, Int(p.n("kelvin", 5600))])).sorted(), id: \.self) { Text("\($0)K").tag($0) }
            }
            Toggle("Beam", isOn: Binding(get: { p.b("beam_on") }, set: { set(["beam_on": $0]) }))
            if p.b("existing") || p.b("practical") {
                Toggle("Off", isOn: Binding(get: { p.s("action") == "off" }, set: { set(["action": $0 ? "off" : ""]) }))
            }
            Toggle("Down", isOn: Binding(get: { p.raw["tilt"] != nil && p.n("tilt", 90) < 45 }, set: { set(["tilt": $0 ? 0.0 : 90.0]) }))
            if p.raw["tilt"] != nil && p.n("tilt", 90) < 45 {
                Picker("Height", selection: Binding(get: { p.s("height") }, set: { set(["height": $0]) })) {
                    Text("—").tag("")
                    ForEach(metric ? ["2 m", "2.5 m", "3 m", "3.5 m", "4 m", "5 m", "6 m"]
                                   : ["6'", "7'", "8'", "9'", "10'", "12'", "14'", "16'", "20'"], id: \.self) { Text($0).tag($0) }
                }
            }
        }
    }

    @ViewBuilder private func frame(_ p: DiagramPiece) -> some View {
        Section {
            // **Its Name is what he types** (2026-10-17), never its size or cloth.
            WordsRow(title: "Name", value: p.s("lamp_name"), axis: .vertical) {
                op(["op": "name_piece", "id": pieceId, "name": $0.trimmingCharacters(in: .whitespaces)])
            }
            Picker("Size", selection: Binding(get: { frameSize(p) }, set: { s in
                if let f = Self.frameSizes.first(where: { $0.0 == s }) { set(["h": f.1 * 0.3048, "tall": f.2 * 0.3048]) }
            })) {
                if !Self.frameSizes.contains(where: { $0.0 == frameSize(p) }) { Text(frameSize(p)).tag(frameSize(p)) }
                ForEach(Self.frameSizes, id: \.0) { Text($0.0).tag($0.0) }
            }
            Picker("Material", selection: Binding(get: { p.s("material") == "gel" ? "gel:" + (p.gels.first ?? "") : (p.s("material").isEmpty ? "undecided" : p.s("material")) },
                                                  set: { v in
                if v.hasPrefix("gel:") { set(["material": "gel", "gels": [String(v.dropFirst(4))]]) } else { set(["material": v]) }
            })) {
                if !materials.contains(where: { $0.id == "undecided" }) { Text("Not Decided").tag("undecided") }
                ForEach(materials.filter { $0.id != "gel" }, id: \.id) { Text($0.name).tag($0.id) }
                ForEach(Self.gels.flatMap(\.1), id: \.0) { Text($0.1).tag("gel:" + $0.0) }
            }
            WordsRow(title: "Note", value: p.s("label"), axis: .vertical) { set(["label": $0]) }
            opacity(p)
        }
    }

    private func frameSize(_ p: DiagramPiece) -> String {
        let ft = 0.3048
        let tall = p.n("tall") > 0 ? p.n("tall") : p.n("h")
        return "\(Int((p.n("h") / ft).rounded()))×\(Int((tall / ft).rounded()))"
    }

    @ViewBuilder private func camera(_ p: DiagramPiece) -> some View {
        let rows = session.rows(inScene: plan)
        let row = rows.first { $0.shot == p.s("shot") }
        Section {
            Picker("Shot", selection: Binding(get: { p.s("shot") }, set: { set(["shot": $0]) })) {
                Text("None").tag("")
                ForEach(rows) { r in Text("\(r.number)  \(r.title)").tag(r.shot) }
            }
            Picker("Camera", selection: Binding(get: { p.s("cam_unit") }, set: { u in
                if let row { session.set(row, "unit", to: u); reload() } else { set(["unit": u]) }
            })) {
                if !session.units.contains(where: { $0.id == p.s("cam_unit") }) { Text(p.s("cam_unit_label").isEmpty ? "None" : p.s("cam_unit_label")).tag(p.s("cam_unit")) }
                ForEach(session.units) { u in Text(u.label).tag(u.id) }
            }
            let lenses = session.vocabulary("lens")
            Picker("Lens", selection: Binding(get: { p.s("lens_text") }, set: { name in
                if let row { session.set(row, "lens", to: name); if p.n("lens") > 0 { set(["lens": 0.0]) } else { reload() } }
                else { set(["lens_name": name, "lens": 0.0]) }
            })) {
                if !lenses.contains(p.s("lens_text")) { Text(p.s("lens_text").isEmpty ? "None" : p.s("lens_text")).tag(p.s("lens_text")) }
                ForEach(lenses, id: \.self) { Text($0).tag($0) }
            }
            focal(p, row: row)
            // His own label wins over the shot's number (2026-10-17).
            WordsRow(title: "Name", value: p.s("label"), axis: .vertical) { set(["label": $0]) }
            WordsRow(title: "Note", value: p.s("caption"), axis: .vertical) { set(["caption": $0]) }
        }
    }

    /// A zoom's focal length, or one typed on a camera with no lens.
    @ViewBuilder private func focal(_ p: DiagramPiece, row: Engine.Row?) -> some View {
        let zoom = (p.raw["zoom"] as? [NSNumber])?.map(\.doubleValue)
        let now = p.n("focal", 35)
        if let zoom, zoom.count == 2, zoom[1] > zoom[0] {
            LabeledContent("Focal") {
                Slider(value: Binding(get: { now }, set: { mm in
                    if let row { session.set(row, "focal", to: String(Int(mm.rounded()))); reload() }
                    else { set(["lens": mm.rounded()]) }
                }), in: zoom[0]...zoom[1], step: 1).frame(maxWidth: 170)
                Text("\(Int(now.rounded()))mm").monospacedDigit().foregroundStyle(.secondary).frame(width: 54, alignment: .trailing)
            }
        } else if p.s("lens_text").isEmpty || p.n("lens") > 0 {
            Picker("Focal", selection: Binding(get: { Int(now.rounded()) }, set: { set(["lens": Double($0)]) })) {
                ForEach(Array(Set([14, 18, 21, 25, 28, 32, 35, 40, 50, 65, 75, 85, 100, 135, Int(now.rounded())])).sorted(), id: \.self) {
                    Text("\($0)mm").tag($0)
                }
            }
        } else {
            LabeledContent("Focal", value: "\(Int(now.rounded()))mm")
        }
    }

    @ViewBuilder private func cast(_ p: DiagramPiece) -> some View {
        Section {
            WordsRow(title: "Name", value: p.s("label"), axis: .vertical) { set(["label": $0]) }
            let names = session.vocabulary("cast")
            if !names.isEmpty {
                Menu("Choose Name") { ForEach(names, id: \.self) { n in Button(n) { set(["label": n, "cast": n]) } } }
            }
            Picker("Pose", selection: Binding(get: { p.s("pose").isEmpty ? "standing" : p.s("pose") }, set: { set(["pose": $0]) })) {
                Text("Standing").tag("standing"); Text("Seated").tag("seated"); Text("Lying").tag("lying")
            }
            colour(p, allowNone: true)
            // **One color per person, for the whole project** (2026-10-17).
            let who = (p.s("cast").isEmpty ? p.s("label") : p.s("cast")).trimmingCharacters(in: .whitespaces)
            let field = session.columns.first { ($0.label ?? "").lowercased() == "cast" }?.name
            if !who.isEmpty, let field {
                let now = session.termColour(field, who)
                Menu {
                    ForEach(Array(Swatches.highlight.enumerated()), id: \.offset) { i, hex in
                        Button(Swatches.highlightNames[i] + (now?.uppercased() == hex.uppercased() ? "  ✓" : "")) {
                            session.colourTerm(field, who, hex: hex); reload()
                        }
                    }
                    ForEach(Array(Swatches.inks.enumerated()), id: \.offset) { i, hex in
                        Button(Swatches.inkNames[i] + (now?.uppercased() == hex.uppercased() ? "  ✓" : "")) {
                            session.colourTerm(field, who, hex: hex); reload()
                        }
                    }
                } label: {
                    HStack {
                        Text("Color for \(who)").foregroundStyle(Color(.label))
                        Spacer()
                        Circle().fill(now.map { Color(hex: $0) } ?? Color(.systemGray3)).frame(width: 18, height: 18)
                    }
                }
            }
            WordsRow(title: "Note", value: p.s("caption"), axis: .vertical) { set(["caption": $0]) }
        }
    }

    @ViewBuilder private func words(_ p: DiagramPiece) -> some View {
        Section {
            WordsRow(title: "Words", value: p.s("text"), axis: .vertical) { set(["text": $0]) }
            Picker("Size", selection: Binding(get: { p.n("size", 10 * 40 / 60) >= 12 * 40 / 60 ? "large" : "regular" },
                                              set: { set(["size": $0 == "large" ? 14.0 * 40 / 60 : 10.0 * 40 / 60]) })) {
                Text("Regular").tag("regular"); Text("Large").tag("large")
            }
            Toggle("Bold", isOn: Binding(get: { p.b("bold") }, set: { set(["bold": $0]) }))
            colour(p)
        }
    }

    private var thicknesses: [Double] {
        metric ? [0.025, 0.1, 0.15, 0.23, 0.3] : [1, 4, 6, 9, 12].map { $0 * 0.0254 }
    }

    @ViewBuilder private func wall(_ p: DiagramPiece) -> some View {
        Section {
            Picker("Thickness", selection: Binding(get: { thicknesses.firstIndex { abs($0 - p.n("thick", 0.1524)) < 0.002 } ?? -1 },
                                                   set: { if $0 >= 0 { set(["thick": thicknesses[$0]]) } })) {
                if !thicknesses.contains(where: { abs($0 - p.n("thick", 0.1524)) < 0.002 }) {
                    Text(DiagramLength.text(p.n("thick"), metric: metric)).tag(-1)
                }
                ForEach(thicknesses.indices, id: \.self) { Text(Self.thicknessNames[$0]).tag($0) }
            }
            if !p.b("closed"), p.corners <= 2 {
                LengthRow(title: "Length", metres: hypot(p.n("x2") - p.n("x"), p.n("y2") - p.n("y")), metric: metric) {
                    op(["op": "wall_length", "id": pieceId, "stretch": 0, "length": max($0, 0.05)])
                }
            }
            if p.b("closed") {
                Toggle("Fill", isOn: Binding(get: { !p.s("fill_color").isEmpty }, set: { set(["fill_color": $0 ? "auto" : ""]) }))
            } else if p.corners >= 3 {
                Button("Close") { set(["closed": true]) }
            }
            WordsRow(title: "Name", value: p.s("label")) { set(["label": $0]) }
        }
    }

    /// **A door's kind** (2026-10-17), as the engine names it
    /// (`El::door_style`): set by its word, kept as slide / pair / pocket.
    static let doorKinds: [(String, String)] = [("swing", "Swing"), ("double", "Double"), ("sliding", "Sliding"), ("center", "Center"), ("pocket", "Pocket")]
    static func doorKind(_ p: DiagramPiece) -> String {
        switch (p.b("slide"), p.b("pair"), p.b("pocket")) {
        case (false, false, _): return "swing"
        case (false, true, _): return "double"
        case (true, true, false): return "center"
        case (true, _, true): return "pocket"
        default: return "sliding"
        }
    }

    @ViewBuilder private func door(_ p: DiagramPiece) -> some View {
        let kind = Self.doorKind(p)
        let slides = p.b("slide")
        let paired = kind == "double" || kind == "center"
        Section {
            LengthRow(title: "Width", metres: p.n("w", 0.9), metric: metric) { set(["w": max($0, 0.2)]) }
            Picker("Style", selection: Binding(get: { kind }, set: { new in
                var change: [String: Any] = ["door": new]
                let nowSlides = new == "sliding" || new == "center" || new == "pocket"
                if nowSlides != slides, p.n("swing", 90) > 0.5 { change["swing"] = 90 }
                set(change)
            })) {
                ForEach(Self.doorKinds, id: \.0) { k, t in Text(t).tag(k) }
            }
            .pickerStyle(.menu)
            Picker("State", selection: Binding(get: { p.n("swing", 90) < 1 ? 0.0 : (slides && p.n("swing", 90) < 60 ? 45.0 : 90.0) },
                                               set: { set(["swing": $0]) })) {
                Text("Closed").tag(0.0)
                if slides { Text("Half").tag(45.0) }
                Text("Open").tag(90.0)
            }
            if !paired {
                Button(kind == "pocket" ? "Flip Pocket" : slides ? "Flip Direction" : "Flip Hinge") { set(["hinge": p.s("hinge") == "right" ? "" : "right"]) }
            }
            Button("Flip Side") { set(["flip": !p.b("flip")]) }
        }
    }

    @ViewBuilder private func arrow(_ p: DiagramPiece) -> some View {
        Section {
            Picker("Heads", selection: Binding(get: { p.s("head").isEmpty ? "end" : p.s("head") }, set: { set(["head": $0]) })) {
                Text("One").tag("end"); Text("Both").tag("both"); Text("None").tag("none")
            }
            Picker("Line", selection: Binding(get: { p.s("dash") }, set: { set(["dash": $0]) })) {
                Text("Solid").tag(""); Text("Dashed").tag("dashed"); Text("Dotted").tag("dotted")
            }
            colour(p)
            WordsRow(title: "Name", value: p.s("label")) { set(["label": $0]) }
            WordsRow(title: "Note", value: p.s("caption"), axis: .vertical) { set(["caption": $0]) }
        }
    }

    @ViewBuilder private func piece(_ p: DiagramPiece) -> some View {
        Section {
            name(p)
            note(p, key: "caption")
            if p.kind == "set" || p.kind == "shape" {
                LengthRow(title: "Width", metres: p.n("w"), metric: metric) { set(["w": max($0, 0.02)]) }
                LengthRow(title: "Depth", metres: p.n("h"), metric: metric) { set(["h": max($0, 0.02)]) }
            }
            if p.kind == "track" {
                LengthRow(title: "Length", metres: hypot(p.n("x2") - p.n("x"), p.n("y2") - p.n("y")), metric: metric) {
                    op(["op": "wall_length", "id": pieceId, "stretch": 0, "length": max($0, 0.1)])
                }
            }
            if p.kind == "shape" {
                Toggle("Fill", isOn: Binding(get: { p.b("fill") }, set: { set(["fill": $0]) }))
                colour(p)
            }
        }
    }

    private func opacity(_ p: DiagramPiece) -> some View {
        LabeledContent("Opacity") {
            Slider(value: Binding(get: { p.n("opacity", 1) }, set: { set(["opacity": ($0 * 20).rounded() / 20]) }), in: 0.1...1)
                .frame(maxWidth: 180)
        }
    }

    /// Where it is, which way it faces, and whether it can be moved.
    @ViewBuilder private func place(_ p: DiagramPiece) -> some View {
        Section {
            if !["wall", "measure", "stroke", "cable"].contains(p.kind) {
                LengthRow(title: "Across", metres: p.n("x"), metric: metric) { to in
                    op(["op": "move", "ids": [pieceId], "dx": to - p.n("x"), "dy": 0.0])
                }
                LengthRow(title: "Down", metres: p.n("y"), metric: metric) { to in
                    op(["op": "move", "ids": [pieceId], "dx": 0.0, "dy": to - p.n("y")])
                }
                LabeledContent("Turn") {
                    Stepper("\(Int(p.n("rot").rounded()))°", onIncrement: {
                        op(["op": "rotate", "ids": [pieceId], "deg": 15.0])
                    }, onDecrement: {
                        op(["op": "rotate", "ids": [pieceId], "deg": -15.0])
                    })
                    .monospacedDigit()
                }
            }
            if p.kind != "light", p.kind != "text", p.kind != "note" { opacity(p) }
            Toggle("Locked", isOn: Binding(get: { p.b("locked") }, set: { set(["locked": $0]) }))
            Toggle("Hidden", isOn: Binding(get: { p.b("hidden") }, set: { set(["hidden": $0]) }))
        }
    }
}

// MARK: - Layers

/// **Layers** (the Mac's Layers sidebar): every piece, top of the stack
/// first. Tap picks it on the plan; drag to restack; swipe to hide or lock.
struct DiagramLayersSheet: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    let plan: String
    let picked: [String]
    let pick: (String) -> Void
    let edit: ([String: Any]) -> Void

    @State private var els: [DiagramPiece] = []
    @State private var search = ""
    @State private var renaming: DiagramPiece?
    @State private var newName = ""

    private var shown: [DiagramPiece] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let top = Array(els.reversed())
        guard !q.isEmpty else { return top }
        return top.filter { "\($0.shownName) \(DiagramPiece.kindWord($0.kind)) \($0.s("caption"))".lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(shown, id: \.id) { p in
                    Button { pick(p.id); dismiss() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: DiagramPiece.symbol(p.kind))
                                .frame(width: 22)
                                .foregroundStyle(Color(.secondaryLabel))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.shownName).foregroundStyle(p.b("hidden") ? Color(.secondaryLabel) : Color(.label)).lineLimit(1)
                                if p.shownName != DiagramPiece.kindWord(p.kind) {
                                    Text(DiagramPiece.kindWord(p.kind)).font(.system(size: Kit.Size.label)).foregroundStyle(Color(.secondaryLabel))
                                }
                            }
                            Spacer()
                            if p.b("locked") { Image(systemName: "lock.fill").font(.system(size: Kit.Size.label)).foregroundStyle(.secondary) }
                            if p.b("hidden") { Image(systemName: "eye.slash").font(.system(size: Kit.Size.label)).foregroundStyle(.secondary) }
                            if picked.contains(p.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(p.b("hidden") ? "Show" : "Hide") { update(p, ["hidden": !p.b("hidden")]) }
                        Button(p.b("locked") ? "Unlock" : "Lock") { update(p, ["locked": !p.b("locked")]) }.tint(.gray)
                    }
                    .contextMenu {
                        Button("Rename…") { newName = p.shownName; renaming = p }
                        Button(p.b("hidden") ? "Show" : "Hide") { update(p, ["hidden": !p.b("hidden")]) }
                        Button(p.b("locked") ? "Unlock" : "Lock") { update(p, ["locked": !p.b("locked")]) }
                        Button("Bring to Front") { edit(["op": "order", "ids": [p.id], "to": "front"]); reload() }
                        Button("Send to Back") { edit(["op": "order", "ids": [p.id], "to": "back"]); reload() }
                    }
                }
                .onMove(perform: search.isEmpty ? move : nil)
            }
            .searchable(text: $search, prompt: "Search")
            .navigationTitle("Layers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    guard let p = renaming else { return }
                    if p.isLamp {
                        edit(["op": "name_lamp", "id": p.id, "name": newName.trimmingCharacters(in: .whitespaces)])
                    } else if p.kind == "text" {
                        edit(["op": "update", "ids": [p.id], "set": ["text": newName]])
                    } else {
                        edit(["op": "update", "ids": [p.id], "set": ["label": newName]])
                    }
                    reload()
                }
            }
        }
        .task { reload() }
    }

    private func reload() { els = DiagramPiece.read(plan, engine: session.engine).els }

    private func update(_ p: DiagramPiece, _ set: [String: Any]) {
        edit(["op": "update", "ids": [p.id], "set": set])
        reload()
    }

    /// A row dropped between two others: over the one now under it, else
    /// under the one now over it.
    private func move(_ from: IndexSet, _ to: Int) {
        var top = shown
        guard let i = from.first else { return }
        let piece = top[i]
        top.move(fromOffsets: from, toOffset: to)
        guard let at = top.firstIndex(where: { $0.id == piece.id }) else { return }
        if at + 1 < top.count {
            edit(["op": "order", "ids": [piece.id], "to": "above", "next": top[at + 1].id])
        } else if at > 0 {
            edit(["op": "order", "ids": [piece.id], "to": "below", "next": top[at - 1].id])
        }
        reload()
    }
}

// MARK: - Plan settings

/// **The plan's settings** (the Mac's View panel, Sun and North, and Colors).
struct DiagramPlanSettingsSheet: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    let plan: String
    let edit: ([String: Any]) -> Void
    /// After a change on every plan of the project (Colors, Light Beams).
    let everywhere: () -> Void

    @State private var s: [String: Any] = [:]

    private func b(_ k: String, _ d: Bool = false) -> Bool { s[k] as? Bool ?? d }
    private func str(_ k: String) -> String { s[k] as? String ?? "" }
    private func num(_ k: String, _ d: Double = 0) -> Double { (s[k] as? NSNumber)?.doubleValue ?? d }
    private var metric: Bool { str("units") == "m" }

    static let colourRoles: [(String, String)] = [
        ("added", "Film Lights"), ("practical", "Practicals"), ("existing", "Existing Lights"), ("blue", "Third Ink"),
        ("gripink", "Grip and Frames"), ("camink", "Cameras"), ("plan", "Walls"), ("prop", "Furniture and Props"),
    ]

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan") {
                    Picker("Units", selection: bind("units", metric ? "m" : "ft")) {
                        Text("Feet and Inches").tag("ft"); Text("Metres").tag("m")
                    }
                    Picker("Grid Step", selection: Binding(get: { gridChoice }, set: { set(["step": $0]) })) {
                        ForEach(gridSteps, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    toggle("Grid", "grid", true)
                    toggle("Snap", "snap", true)
                    toggle("Sketch", "sketch")
                    Picker("Lengths", selection: Binding(get: { !b("dims", true) ? "off" : (b("all_lengths") ? "all" : "picked") },
                                                         set: { v in set(v == "off" ? ["dims": false] : ["dims": true, "all_lengths": v == "all"]) })) {
                        Text("Off").tag("off"); Text("Picked").tag("picked"); Text("All").tag("all")
                    }
                    toggle("Measurements", "measures", true)
                }
                Section("Lights") {
                    toggle("Cones", "cones", true)
                    Toggle("Light Beams", isOn: Binding(get: { b("beams", true) }, set: { v in
                        _ = session.engine?.raw("diagrameverywhere", plan, "beams", v ? "true" : "false")
                        session.refresh(); everywhere(); reload()
                    }))
                    toggle("Labels", "labels", true)
                    toggle("All Caps", "caps")
                    toggle("Counts", "counts")
                    toggle("Frame Fabric", "fabric", true)
                    Picker("Lights As", selection: bind("style", "plot")) {
                        Text("Plot").tag("plot"); Text("Pictures").tag("picture")
                    }
                }
                Section("Sun and North") {
                    Toggle("Sun", isOn: Binding(get: { b("sun") }, set: { sun(["sun": $0]) }))
                    if b("sun") {
                        DatePicker("Day", selection: Binding(get: { Self.day.date(from: str("sun_date")) ?? Date() },
                                                             set: { sun(["sun_date": Self.day.string(from: $0)]) }),
                                   displayedComponents: .date)
                        DatePicker("Time", selection: Binding(get: { time }, set: { d in
                            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                            sun(["sun_time": String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)])
                        }), displayedComponents: .hourAndMinute)
                        toggle("Sun Rays", "sun_rays")
                    }
                    LabeledContent("North") {
                        Slider(value: Binding(get: { num("north") }, set: { set(["north": ($0 / 5).rounded() * 5]) }), in: 0...355, step: 5)
                            .frame(maxWidth: 170)
                        Text("\(Int(num("north")))°").monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                    }
                }
                Section("Sheet") {
                    Picker("Paper", selection: bind("paper", "letter")) {
                        Text("Letter").tag("letter"); Text("Tabloid").tag("tabloid"); Text("A4").tag("a4")
                    }
                    Picker("Orientation", selection: Binding(get: { str("orientation") == "portrait" ? "portrait" : "landscape" },
                                                             set: { set(["orientation": $0]) })) {
                        Text("Landscape").tag("landscape"); Text("Portrait").tag("portrait")
                    }
                    toggle("Legend", "legend", true)
                    toggle("Show Unlabeled", "unlabeled")
                    toggle("Sheet Notes", "notes", true)
                    if b("notes", true) {
                        WordsRow(title: "Notes", value: str("sheet_notes"), axis: .vertical) { set(["sheet_notes": $0]) }
                    }
                    toggle("Scale Bar", "scale_bar")
                }
                Section("Colors") {
                    ForEach(Self.colourRoles, id: \.0) { role, title in
                        HStack {
                            ColorPicker(title, selection: Binding(get: { colour(role) }, set: { setColour(role, hexOf($0)) }),
                                        supportsOpacity: false)
                            if colours[role] != nil {
                                Button("Reset") { setColour(role, nil) }.buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Plan Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task { reload() }
    }

    private func reload() { s = DiagramPiece.read(plan, engine: session.engine).settings }

    private func set(_ values: [String: Any]) {
        edit(["op": "settings", "set": values])
        reload()
    }

    /// The sun is read on this phone's clock for the day it is drawn for.
    private func sun(_ values: [String: Any]) {
        var v = values
        let day = Self.day.date(from: (values["sun_date"] as? String) ?? str("sun_date")) ?? Date()
        v["sun_tz"] = TimeZone.current.secondsFromGMT(for: day) / 60
        set(v)
    }

    private var time: Date {
        let parts = str("sun_time").split(separator: ":").compactMap { Int($0) }
        return Calendar.current.date(bySettingHour: parts.first ?? 12, minute: parts.count > 1 ? parts[1] : 0, second: 0, of: Date()) ?? Date()
    }

    private func toggle(_ title: String, _ key: String, _ d: Bool = false) -> some View {
        Toggle(title, isOn: Binding(get: { b(key, d) }, set: { set([key: $0]) }))
    }

    private func bind(_ key: String, _ d: String) -> Binding<String> {
        Binding(get: { str(key).isEmpty ? d : str(key) }, set: { set([key: $0]) })
    }

    private var gridSteps: [(Double, String)] {
        metric ? [(1.0, "Every Metre"), (0.5, "Every 50 cm"), (0.1, "Every 10 cm")]
               : [(0.3048, "Every Foot"), (0.1524, "Every 6 Inches")]
    }
    private var gridChoice: Double {
        let steps = gridSteps.map(\.0), now = num("step", 0.3048)
        return steps.min { abs($0 - now) < abs($1 - now) } ?? steps[0]
    }

    private var colours: [String: String] { s["colours"] as? [String: String] ?? [:] }

    private func colour(_ role: String) -> Color {
        if let hex = colours[role] { return Color(hex: String(hex.dropFirst())) }
        return Color(hex: DiagramInk.light[role] ?? "17171A")
    }

    /// One color for every plan of the project, as the Mac sets them.
    private func setColour(_ role: String, _ hex: String?) {
        var now = colours
        now[role] = hex
        guard let data = try? JSONSerialization.data(withJSONObject: now), let text = String(data: data, encoding: .utf8) else { return }
        _ = session.engine?.raw("diagrameverywhere", plan, "colours", text)
        session.refresh()
        everywhere()
        reload()
    }
}
