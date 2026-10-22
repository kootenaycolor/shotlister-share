import SwiftUI
import AppKit

// What is picked on the plan, and everything about it.
//
// A camera that stands for a shot shows **that shot's** fields — its frame,
// its description, size, angle, movement, lens, equipment — and edits them
// where they live, on the shot. Cadrage's gesture, and the heart of SL-60:
// the diagram and the shot list are two ways of looking at one thing. The
// camera's own facts (its colour, sensor, cone, beats) sit under them.

struct DiagramInspector: View {
    @ObservedObject var state: ShellState
    @ObservedObject var model: DiagramModel
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.selection.isEmpty {
                // Light Levels were all the plan's own Details held; they
                // are off with the beams (`render::LAMP_BEAMS`). Open
                // between picks (2026-10-17), it says so and shuts here too.
                HStack {
                    Text("Details").sans(Brand.Size.title, weight: .bold)
                    Spacer(minLength: 4)
                    Button("Close") { model.toggleDetails() }.buttonStyle(.rowAction)
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                Rectangle().fill(Brand.rule(dark)).frame(height: 1)
                EmptyState(title: "No Selection", compact: true)
            } else if model.shownPicked.count == 1, let e = model.shownPicked.first {
                One(state: state, model: model, e: e)
            } else {
                Many(model: model)
            }
        }
        // The Details tab of the right sidebar (`DiagramRightPanel`).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - one thing

private struct One: View {
    @ObservedObject var state: ShellState
    @ObservedObject var model: DiagramModel
    let e: DiagramEl
    /// The library open beside Fixture or Kind, to swap this piece.
    @State private var swapping = false
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            Rectangle().fill(Brand.rule(dark)).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    fields
                    common
                }
                .padding(14)
            }
        }
    }

    private var row: ViewModel.Row? {
        guard e.kind == "camera", !e.shot.isEmpty else { return nil }
        return state.view?.allRows.first { $0.shot == e.shot }
    }

    private var title: String {
        switch e.kind {
        case "camera":
            if let row { return "Shot \(row.number)" }
            return e.label.isEmpty ? "Camera" : e.label
        case "cast": return e.label.isEmpty ? (e.cast.isEmpty ? "Cast" : e.cast) : e.label
        case "light" where DiagramMarks.isLamp(e, model):
            // A lamp by its Name, its symbol's (Back to Paper, Batch 2).
            let n = e.lamp_name ?? ""
            return n.isEmpty ? (DiagramItems.symName(e, model) ?? "Lamp") : n
        case "light", "set":
            return e.label.isEmpty ? (DiagramItems.symName(e, model) ?? (e.kind == "light" ? "Grip" : "Set Piece")) : e.label
        case "wall": return "Wall"
        case "door": return DoorStyle.of(e).name
        case "window": return "Window"
        case "opening": return "Opening"
        case "track": return "Track"
        case "road": return "Road"
        case "text": return "Text"
        case "measure": return "Ruler"
        case "arrow": return "Arrow"
        case "shape": return "Shape"
        case "cable": return "Cable"
        case "stroke": return "Drawing"
        case "note": return "Note"
        case "image": return "Picture"
        default: return e.kind.capitalized
        }
    }

    private var head: some View {
        HStack(spacing: 8) {
            if e.kind == "camera" {
                Circle().fill(colour).frame(width: 10, height: 10)
            }
            Text(title).sans(Brand.Size.title, weight: .bold).lineLimit(1)
            Spacer(minLength: 4)
            // Shut, the bar at the foot comes back.
            Button("Close") { model.toggleDetails() }
                .buttonStyle(.rowAction)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private func aimName(_ t: DiagramEl) -> String {
        if !t.label.trimmingCharacters(in: .whitespaces).isEmpty { return t.label }
        if !t.cast.isEmpty { return t.cast }
        return model.library?.symbols.first { $0.id == t.sym }?.name ?? t.kind.capitalized
    }

    private var colour: Color {
        e.color.hasPrefix("#") ? Brand.hex(String(e.color.dropFirst())) : Brand.ink(dark)
    }

    // MARK: the kind's own fields

    @ViewBuilder private var fields: some View {
        if !e.aim.isEmpty, let t = model.el(e.aim) {
            Field("Aimed At") {
                HStack {
                    Text(aimName(t)).sans(Brand.Size.body).lineLimit(1)
                    Spacer(minLength: 4)
                    Button("Stop Aiming") { model.update([e.id], ["aim": ""]) }
                        .buttonStyle(.rowAction)
                }
            }
        }
        switch e.kind {
        case "camera": camera
        case "cast": cast
        case "light": light
        case "set": setPiece
        case "wall": wall
        case "door", "window", "opening": opening
        case "track": track
        case "road": road
        case "text": words
        case "note": words
        case "arrow": arrow
        case "measure": measure
        case "shape": shape
        case "stroke" where e.isPath: path
        case "cable", "stroke": strokeFields
        case "image": picture
        default: EmptyView()
        }
    }

    // ---- a picture under the plan

    @ViewBuilder private var picture: some View {
        Field("Show As") {
            Segmented(selection: Binding(get: { e.role == "photo" },
                                         set: { photo in
                                             model.update([e.id], ["role": photo ? "photo" : "", "opacity": photo ? 1.0 : 0.85])
                                         }),
                      items: [.init(value: false, title: "Background"), .init(value: true, title: "Photo")],
                      quiet: true)
        }
        size
        Field("Opacity") { OpacitySlider(value: e.opacity) { model.update([e.id], ["opacity": $0]) } }
    }

    // ---- a camera

    @ViewBuilder private var camera: some View {
        // **A camera on the plan is its shot** (his design, 2026-10-01). Its
        // Shot, Camera, Lens and Focal are the bar's (Back to Paper, Batch
        // 2); here, the shot's own words and the exact numbers.
        if let row {
            if row.frame != nil {
                Thumbnail(row: row, engine: state.engine, ratio: 16 / 9, dark: dark, width: 264 + 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Field("Title") {
                Committing(text: row.title) { setShot("title", $0) }
            }
            ShotWords(state: state, row: row)
            shotChoice("Shot Size", field: "size", value: row.size)
            shotChoice("Shot Angle", field: "angle", value: row.angle.first ?? "")
            shotChoice("Movement", field: "movement", value: row.movement)
            shotChoice("Equipment", field: "support", value: row.support)
            shotCast(row)
        }
        // His own label wins over the shot's number (2026-10-17).
        Field("Name") { Committing(text: e.label, multiline: true) { model.update([e.id], ["label": $0]) } }
        if (e.lens_text ?? "").isEmpty, !(e.zoom.map { $0.count == 2 && $0[1] > $0[0] } ?? false) {
            Field("Focal Length") {
                Committing(text: e.lens > 0 ? "\(Int(e.lens))mm" : "") { text in
                    model.setFocal(e, mm: Double(text.filter { $0.isNumber || $0 == "." }) ?? 0)
                }
            }
        }
        Field("View") {
            HStack(spacing: 8) {
                Text(e.aov.map { String(format: "%.1f°", $0) } ?? "—")
                    .sans(Brand.Size.body, weight: .semibold).monospacedDigit()
                Text(e.sensor_set == true ? (e.gate_name ?? "") : "Super 35")
                    .sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .help(e.gate_w.map { w in
                (e.gate_h ?? 0) > 0 ? String(format: "%.2f × %.2f mm", w, e.gate_h!) : String(format: "%.2f mm", w)
            } ?? "")
        }
    }

    private func shotChoice(_ label: String, field: String, value: String) -> some View {
        Field(label) {
            Menu {
                ForEach(state.engine?.vocabulary(field) ?? [], id: \.self) { v in
                    Button(v) { setShot(field, v) }
                }
                if !value.isEmpty {
                    Divider()
                    Button("Clear") { setShot(field, "") }
                }
            } label: {
                HStack {
                    if value.isEmpty {
                        Text("—").sans(Brand.Size.body).foregroundStyle(Brand.ink2(dark))
                    } else {
                        Chip(text: value, colour: Brand.chipInk(field, value, dark))
                    }
                    Spacer(minLength: 0)
                }
                .field(dark)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        }
    }

    /// Who is in the shot — the project's own Cast column, several names.
    @ViewBuilder private func shotCast(_ row: ViewModel.Row) -> some View {
        let field = castField
        let names = row.custom?[field] ?? []
        if state.view?.columns.contains(where: { $0.name == field }) == true {
            Field("Cast") {
                Menu {
                    ForEach(state.engine?.vocabulary(field) ?? [], id: \.self) { n in
                        Button(names.contains(n) ? "✓ \(n)" : n) {
                            let next = names.contains(n) ? names.filter { $0 != n } : names + [n]
                            setShot(field, next.joined(separator: ", "))
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if names.isEmpty {
                            Text("—").sans(Brand.Size.body).foregroundStyle(Brand.ink2(dark))
                        } else {
                            ForEach(names, id: \.self) { n in Chip(text: n, colour: Brand.chipInk(field, n, dark)) }
                        }
                        Spacer(minLength: 0)
                    }
                    .field(dark)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            }
        }
    }

    private func setShot(_ field: String, _ value: String) {
        guard let engine = state.engine, let row else { return }
        state.replace(engine.set(shot: row.shot, field: field, value: value))
        model.reload()
    }

    // ---- cast

    @ViewBuilder private var cast: some View {
        Field("Name") { Committing(text: e.label, multiline: true) { model.update([e.id], ["label": $0]) } }
        Field("Pose") {
            Segmented(selection: Binding(get: { e.pose.isEmpty ? "standing" : e.pose },
                                         set: { model.update([e.id], ["pose": $0]) }),
                      items: [.init(value: "standing", title: "Standing"),
                              .init(value: "seated", title: "Seated"),
                              .init(value: "lying", title: "Lying")],
                      quiet: true)
        }
        // **One color per person, for the whole project** (his ask,
        // 2026-10-17): every piece of them on every plan wears it; this
        // piece alone can still wear its own.
        let who = (e.cast.isEmpty ? e.label : e.cast).trimmingCharacters(in: .whitespaces)
        if !who.isEmpty, !model.readOnly {
            let now = Brand.termInks[Brand.termKey(castField, who)].map { "#" + $0 } ?? ""
            Field("Color for \(who)") {
                ColourRow(selected: now) { hex in
                    state.colourTerm(field: castField, value: who, hex: String(hex.dropFirst()))
                    model.reload()
                }
            }
        }
        Field(who.isEmpty ? "Color" : "This Piece") {
            ColourRow(selected: e.color, allowNone: !who.isEmpty) { model.update([e.id], ["color": $0]) }
        }
    }

    /// The project's Cast column, whatever it is called underneath.
    private var castField: String {
        state.view?.columns.first { ($0.label ?? "").lowercased() == "cast" }?.name ?? "cast"
    }

    // ---- a light

    @ViewBuilder private var light: some View {
        if e.sym == DiagramFrames.sym {
            DiagramPlotFrameFields(model: model, e: e)
        } else if DiagramMarks.isLamp(e, model) {
            DiagramLampFields(model: model, e: e)
        } else {
            // **Grip** — a flag, a net, a stand: what it is and its name,
            // never a lamp's form (Back to Paper, Batch 2).
            Field("Kind") { swapField(model.library?.symbols.first { $0.id == e.sym }) }
            Field("Name") { Committing(text: e.label, multiline: true) { model.update([e.id], ["label": $0]) } }
        }
    }

    // ---- a set piece

    @ViewBuilder private var setPiece: some View {
        let sym = model.library?.symbols.first { $0.id == e.sym }
        Field("Kind") { swapField(sym) }
        Field("Name") { Committing(text: e.label, multiline: true) { model.update([e.id], ["label": $0]) } }
        size
    }

    /// **What it is, and swapping it** (design/26): the field opens the
    /// toolbar's own library — search, sections, Maker, what it is now on
    /// top — and a click there swaps this piece, keeping where it stands,
    /// its turn, its name and its colour.
    private func swapField(_ sym: DiagramSymbol?) -> some View {
        Button { swapping = true } label: {
            FieldFace(text: sym?.name ?? DiagramItems.symName(e, model) ?? e.sym, chevron: false, dark: dark)
        }
        .buttonStyle(.plain)
        .disabled(model.readOnly || e.locked)
        .popover(isPresented: $swapping, arrowEdge: .leading) {
            DiagramLibraryPanel(model: model, height: 460, swap: e, chrome: false) { swapping = false }
        }
    }

    @ViewBuilder private var size: some View {
        HStack(spacing: 10) {
            Field("Width") { LengthField(model: model, value: e.w) { model.update([e.id], ["w": max($0, 0.02)]) } }
            Field("Depth") { LengthField(model: model, value: e.h) { model.update([e.id], ["h": max($0, 0.02)]) } }
        }
    }

    // ---- walls and what is in them

    @ViewBuilder private var wall: some View {
        kindField
        fillFields
        let st = e.stretches
        // The stretch picked on the plan, or a plain wall's only one: its
        // length typed moves its far corner (a room's is its inside face).
        let s: Int? = model.pickedStretch.flatMap { $0 < st.count ? $0 : nil } ?? (st.count == 1 ? 0 : nil)
        HStack(spacing: 10) {
            if let s {
                Field(e.isClosed ? "Inside Length" : "Length") {
                    LengthField(model: model, value: model.shownLength(e, s)) { model.setWallLength(e, $0, stretch: s) }
                }
            } else {
                Field("Length") {
                    Text(model.length(zip(e.run, e.run.dropFirst()).reduce(0) { $0 + Double(hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y)) }))
                        .sans(Brand.Size.body).field(dark)
                }
            }
            Field("Thickness") { LengthField(model: model, value: e.thick) { model.update([e.id], ["thick": max($0, 0.005)]) } }
        }
        if let i = model.pickedCorner, i < e.corners.count {
            let c = e.corners[i]
            PositionFields(model: model, at: c) { to in
                model.edit(model.wallOp("wall_corner", e, ["corner": i, "x": to.x, "y": to.y]))
            }
        }
        Field("Name") { Committing(text: e.label, multiline: true) { model.update([e.id], ["label": $0]) } }
        Field("Color") { ColourRow(selected: e.color, allowNone: true) { model.update([e.id], ["color": $0]) } }
    }

    @ViewBuilder private var opening: some View {
        Field("Width") { LengthField(model: model, value: e.w) { model.update([e.id], ["w": max($0, 0.2)]) } }
        if e.kind == "door" {
            let style = DoorStyle.of(e)
            let slides = style.slides
            // Five kinds: a menu, so the panel never has to be wide enough
            // for five pills.
            Field("Style") {
                Menu {
                    ForEach(DoorStyle.allCases) { k in
                        Button(k == style ? "✓ \(k.title)" : k.title) { model.update([e.id], k.change(e)) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(style.title).sans(Brand.Size.body)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Brand.ink2(dark))
                    }
                    .field(dark)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            }
            // Shut is no swing, no slide; a sliding door also stops halfway.
            let state = e.swing <= 0.5 ? "closed" : (slides && e.swing < 89.5 ? "half" : "open")
            let states: [Segmented<String>.Item] = slides
                ? [.init(value: "closed", title: "Closed"), .init(value: "half", title: "Half"), .init(value: "open", title: "Open")]
                : [.init(value: "closed", title: "Closed"), .init(value: "open", title: "Open")]
            Field("State") {
                Segmented(selection: Binding(get: { state }, set: { new in
                    model.update([e.id], ["swing": new == "closed" ? 0 : new == "half" ? 45 : 90])
                }), items: states, quiet: true)
            }
            if !slides, e.swing > 0.5 {
                Field("Swing") { NumberField(value: e.swing, unit: "°") { model.update([e.id], ["swing": min(max($0, 0), 180)]) } }
            }
            HStack(spacing: 8) {
                if !style.paired {
                    Button(style == .pocket ? "Flip Pocket" : slides ? "Flip Direction" : "Flip Hinge") { model.update([e.id], ["hinge": e.hinge == "right" ? "" : "right"]) }
                        .buttonStyle(.capsule)
                }
                Button("Flip Side") { model.update([e.id], ["flip": !e.flip]) }
                    .buttonStyle(.capsule)
            }
        }
    }

    @ViewBuilder private var track: some View {
        Field("Length") { Text(model.length(hypot(e.x2 - e.x, e.y2 - e.y))).sans(Brand.Size.body).field(dark) }
        Field("Gauge") { LengthField(model: model, value: e.thick) { model.update([e.id], ["thick": max($0, 0.1)]) } }
        Field("Name") { Committing(text: e.label, multiline: true) { model.update([e.id], ["label": $0]) } }
    }

    /// **A road on a plot** (his ask, 2026-10-04): two kerbs and a name.
    /// Its kind is only a width to start from; Width says exactly.
    @ViewBuilder private var road: some View {
        Field("Name") { Committing(text: e.label, multiline: true) { model.update([e.id], ["label": $0]) } }
        Field("Kind") {
            HStack(spacing: 4) {
                ForEach(DiagramActions.roadKinds, id: \.0) { k in
                    ChoicePill(title: k.0, on: abs(e.thick - k.1) < 0.05, dark: dark) { model.update([e.id], ["thick": k.1]) }
                }
            }
        }
        Field("Width") { LengthField(model: model, value: e.thick) { model.update([e.id], ["thick": max($0, 0.5)]) } }
    }

    // ---- words and lines

    @ViewBuilder private var words: some View {
        let lamps = model.tied(to: e.id)
        if e.kind == "text", !lamps.isEmpty {
            // **A shared label** (his ask, 2026-10-04): its Name and Note are
            // its lamps', typed on the plan or set from the bar.
            Field("Shared Label") {
                HStack(spacing: 6) {
                    Text(DiagramActionBar.heldCount(lamps, model)).sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark))
                    Spacer(minLength: 4)
                    Button("Own Label") { _ = model.edit(["op": "own_label", "ids": [e.id]]) }.buttonStyle(.rowAction)
                }
            }
        } else {
            // **Words**: typed on the plan; here, their exact size and colour.
            Field("Size") {
                NumberField(value: (e.size * 1.5).rounded(), unit: "pt") { model.update([e.id], ["size": min(max($0, 4), 200) / 1.5]) }
            }
            Field("Color") { ColourRow(selected: e.color, allowNone: true) { model.update([e.id], ["color": $0]) } }
        }
    }

    @ViewBuilder private var arrow: some View {
        Field("Name") { Committing(text: e.label, multiline: true) { model.update([e.id], ["label": $0]) } }
        Field("Heads") {
            Segmented(selection: Binding(get: { e.head.isEmpty ? "end" : e.head }, set: { model.update([e.id], ["head": $0]) }),
                      items: [.init(value: "end", title: "One"), .init(value: "both", title: "Both"), .init(value: "none", title: "None")],
                      quiet: true)
        }
        strokeFields
    }

    /// **The Ruler**: its whole length, then each marker — what it is locked
    /// to, or Free — and how far it is to the next one.
    @ViewBuilder private var measure: some View {
        let c = e.corners
        let total = zip(c, c.dropFirst()).reduce(0.0) { $0 + Double(hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y)) }
        Field("Length") { Text(model.length(total)).sans(Brand.Size.body).field(dark) }
        Toggle(isOn: Binding(get: { e.under ?? false }, set: { model.update([e.id], ["under": $0]) })) {
            Text("Behind Everything").sans(Brand.Size.body)
        }
        .toggleStyle(.switch).controlSize(.mini)
        Field("Markers") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(c.enumerated()), id: \.offset) { i, p in
                    HStack(spacing: 8) {
                        Text("\(i + 1)").sans(Brand.Size.small, weight: .semibold).monospacedDigit()
                            .foregroundStyle(Brand.ink3(dark)).frame(width: 14, alignment: .leading)
                        Menu {
                            let pieces = model.plan.els.filter { !$0.isLine && !$0.isPolyline && !["image", "text", "note", "shape"].contains($0.kind) && !$0.hidden }
                            ForEach(pieces) { t in
                                Button(model.lockName(t)) { model.pickedCorner = i; model.lockMarker(e, to: t.id) }
                            }
                            if e.lock(i) != nil {
                                Divider()
                                Button("Unlock") { model.pickedCorner = i; model.lockMarker(e, to: nil) }
                            }
                        } label: {
                            FieldFace(text: e.lock(i).flatMap { model.el($0) }.map { model.lockName($0) } ?? "Free",
                                      empty: e.lock(i) == nil, chevron: false, dark: dark)
                        }
                        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                        if i + 1 < c.count {
                            Text(model.length(Double(hypot(c[i + 1].x - p.x, c[i + 1].y - p.y))))
                                .sans(Brand.Size.small).monospacedDigit().foregroundStyle(Brand.ink3(dark))
                                .frame(width: 64, alignment: .trailing)
                        } else {
                            Spacer().frame(width: 64)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var shape: some View {
        Field("Name") { Committing(text: e.label, multiline: true) { model.update([e.id], ["label": $0]) } }
        Toggle(isOn: Binding(get: { e.fill }, set: { model.update([e.id], ["fill": $0]) })) {
            Text("Fill").sans(Brand.Size.body)
        }
        .toggleStyle(.switch).controlSize(.mini)
        strokeFields
        size
    }

    /// **What a drawn path is** (his ask, 2026-10-02): a plain line, a wall
    /// with thickness and doors, or a filled object. Same points either way.
    private var kindField: some View {
        Field("Type") {
            Segmented(selection: Binding(get: { e.isWall ? "wall" : (e.fill && e.isClosed ? "object" : "line") },
                                         set: { model.setPathKind(e, $0) }),
                      items: [.init(value: "line", title: "Line"), .init(value: "wall", title: "Wall"), .init(value: "object", title: "Object")],
                      quiet: true)
        }
    }

    /// **A fill out of the shape**: on or off, its colour (none is the plan's
    /// tint) and how solid it is. For a closed path or a room.
    @ViewBuilder private var fillFields: some View {
        if e.isClosed {
            Toggle(isOn: Binding(get: { e.isFilled }, set: { model.setFilled(e, $0) })) {
                Text("Fill").sans(Brand.Size.body)
            }
            .toggleStyle(.switch).controlSize(.mini)
            if e.isFilled {
                let hex = (e.fill_color ?? "").hasPrefix("#")
                Field("Fill Color") { ColourRow(selected: hex ? (e.fill_color ?? "") : "", allowNone: true) { model.setFillColour(e, $0) } }
                Field("Fill Opacity") {
                    NumberField(value: ((e.fill_alpha ?? 0) > 0 ? (e.fill_alpha ?? 0) : (hex ? 0.55 : 0.16)) * 100, unit: "%") {
                        model.update([e.id], ["fill_alpha": min(max($0, 2), 100) / 100])
                    }
                }
            }
        }
    }

    @ViewBuilder private var path: some View {
        kindField
        strokeFields
        fillFields
        if e.isClosed {
            Field("Name") { Committing(text: e.label, multiline: true) { model.update([e.id], ["label": $0]) } }
        }
    }

    @ViewBuilder private var strokeFields: some View {
        Field("Color") { ColourRow(selected: e.color, allowNone: true) { model.update([e.id], ["color": $0]) } }
        HStack(spacing: 10) {
            Field("Weight") { NumberField(value: e.weight, unit: "pt") { model.update([e.id], ["weight": min(max($0, 0.5), 20)]) } }
            Field("Line") {
                pickMenu(["Solid", "Dashed", "Dotted"], value: e.dash.isEmpty ? "Solid" : e.dash.capitalized, empty: "Solid") {
                    model.update([e.id], ["dash": $0 == "Solid" ? "" : $0.lowercased()])
                }
            }
        }
        if e.kind == "cable" {
            Field("Name") { Committing(text: e.label, multiline: true) { model.update([e.id], ["label": $0]) } }
        }
    }

    // ---- what everything has

    /// Where it stands and how it shows. The verbs on a piece (duplicate,
    /// lock, order, flip, hide, delete) live in its right-click menu.
    @ViewBuilder private var common: some View {
        DiagramLayerButtons(model: model, ids: [e.id])
        Fold("Position", key: "position") {
            // **Exact spots** (master list 3): where it stands, in the film's
            // units, typed or stepped a grid step at a time.
            if !e.isLine && !e.isPolyline {
                let now = e.at(beat: model.beat)
                PositionFields(model: model, at: CGPoint(x: now.x, y: now.y)) { to in model.place(e, at: to) }
            }
            if !e.isPolyline && e.kind != "note" {
                Field("Rotation") {
                    NumberField(value: model.heading(e), unit: "°") { deg in
                        let r = (deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
                        if e.isLine {
                            // A wall turns about its middle, on the grid.
                            model.edit(model.turnPickOp(by: r - model.heading(e)))
                        } else {
                            model.edit(model.turnOp(e, to: r))
                        }
                    }
                }
            }
            // **See through it** (SL-1334, his ask 2026-10-01: an overhead light
            // over the set must not hide what is under it). Every piece fades,
            // lamps and frames too (Ref 1505: "opacity is good, more for
            // frames though because they cover a large area"); never its name.
            if e.kind != "image" {
                Field("Opacity") { OpacitySlider(value: e.opacity) { model.update([e.id], ["opacity": $0]) } }
            }
        }
    }

    private func pickMenu(_ options: [String], value: String, empty: String, _ set: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(options, id: \.self) { o in Button(o) { set(o) } }
            if !value.isEmpty {
                Divider()
                Button("Clear") { set("") }
            }
        } label: {
            FieldFace(text: value.isEmpty ? empty : value, empty: value.isEmpty, chevron: false, dark: dark)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
    }
}

// MARK: - several things

private struct Many: View {
    @ObservedObject var model: DiagramModel
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(model.picked.count) Selected").sans(Brand.Size.title, weight: .bold)
                Spacer()
                Button("Close") { model.toggleDetails() }
                    .buttonStyle(.rowAction)
            }
            // The pick turns as one, about a point on the grid; the angle
            // shown is its first piece's.
            if let first = model.picked.first {
                Field("Rotation") {
                    NumberField(value: model.heading(first), unit: "°") { deg in
                        let r = (deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
                        model.edit(model.turnPickOp(by: r - model.heading(first)))
                    }
                }
            }
            if let first = model.picked.first, !model.picked.allSatisfy({ DiagramMarks.isLamp($0, model) }) {
                Field("Opacity") { OpacitySlider(value: first.opacity) { v in model.update(model.picked.map(\.id), ["opacity": v]) } }
            }
            // **One Color for all of them** (his ask, 2026-10-17); none
            // ringed while they differ.
            if !model.readOnly {
                let now = Set(model.picked.map { $0.color.uppercased() })
                Field(now.count > 1 ? "Color · Mixed" : "Color") {
                    ColourRow(selected: now.count == 1 ? (now.first ?? "") : "mixed", allowNone: true) { c in
                        model.update(model.picked.map(\.id), ["color": c])
                    }
                }
            }
            DiagramLayerButtons(model: model, ids: model.picked.map(\.id))
            Text("Align").fieldLabel(dark)
            HStack(spacing: 4) {
                ForEach([("left", "Left"), ("hcentre", "Centre"), ("right", "Right")], id: \.0) { k, t in
                    Button(t) { model.align(k) }.buttonStyle(.capsule)
                }
            }
            HStack(spacing: 4) {
                ForEach([("top", "Top"), ("vcentre", "Middle"), ("bottom", "Bottom")], id: \.0) { k, t in
                    Button(t) { model.align(k) }.buttonStyle(.capsule)
                }
            }
            if model.picked.count > 2 {
                Text("Space Evenly").fieldLabel(dark)
                HStack(spacing: 4) {
                    Button("Across") { model.distribute("x") }.buttonStyle(.capsule)
                    Button("Down") { model.distribute("y") }.buttonStyle(.capsule)
                }
            }
            HStack(spacing: 4) {
                Button("Group") { model.group() }.buttonStyle(.capsule)
                if model.picked.filter({ DiagramMarks.canShare($0) }).count >= 2 {
                    Button("Share Label") { model.shareLabel() }.buttonStyle(.capsule)
                }
                if model.picked.contains(where: { !$0.group.isEmpty }) {
                    Button("Ungroup") { model.ungroup() }.buttonStyle(.capsule)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

// MARK: - small fields

/// **Send to Set / Copy to Set** (or Plot), in Details (2026-10-17).
struct DiagramLayerButtons: View {
    @ObservedObject var model: DiagramModel
    let ids: [String]

    var body: some View {
        let ok = ids.filter { model.el($0).map(DiagramModel.canSend) ?? false }
        if !ok.isEmpty, !model.readOnly {
            let to = DiagramModel.otherLayer(ok.compactMap(model.el), model)
            let name = to == "set" ? "Set" : "Plot"
            HStack(spacing: 4) {
                Button("Send to \(name)") { model.sendLayer(ok, to: to, copy: false) }.buttonStyle(.capsule)
                Button("Copy to \(name)") { model.sendLayer(ok, to: to, copy: true) }.buttonStyle(.capsule)
            }
        }
    }
}

/// **A section the panel keeps shut until it is wanted.** The top of the
/// panel is what the piece is; the rest folds under a name, and stays open or
/// shut the way he left it.
struct Fold<Content: View>: View {
    let title: String
    var detail: String
    let content: Content
    @AppStorage private var open: Bool
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    init(_ title: String, key: String, detail: String = "", @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
        _open = AppStorage(wrappedValue: false, "diagramFold." + key)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Brand.rule(dark)).frame(height: 1)
            Button { withAnimation(.easeOut(duration: 0.12)) { open.toggle() } } label: {
                HStack(spacing: 6) {
                    Text(title).fieldLabel(dark)
                    if !detail.isEmpty { Text(detail).sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark)) }
                    Spacer(minLength: 0)
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: Brand.Icon.tiny, weight: .semibold))
                        .foregroundStyle(Brand.ink4(dark))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open { content }
        }
    }
}

/// A shot's description, typed where it lives.
private struct ShotWords: View {
    @ObservedObject var state: ShellState
    let row: ViewModel.Row
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Field("Description") {
            Committing(text: row.description, multiline: true) { text in
                guard let engine = state.engine else { return }
                state.replace(engine.set(shot: row.shot, field: "description", value: text))
            }
        }
    }
}

/// A field that writes when you finish with it — Return, or leaving it — not
/// on every keystroke, so one edit is one undo.
struct Committing: View {
    let text: String
    var multiline = false
    /// Asked for the cursor (a new piece of text): it takes it, then says so.
    var focusNow = false
    var gotFocus: () -> Void = {}
    let commit: (String) -> Void
    @State private var draft = ""
    @State private var editing = false
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        Group {
            if multiline {
                TextField("", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
            } else {
                TextField("", text: $draft)
            }
        }
        .textFieldStyle(.plain)
        .sans(Brand.Size.body)
        .focused($focused)
        .onSubmit { finish() }
        .field(dark)
        .onAppear { draft = text; takeFocus() }
        .onChange(of: focusNow) { _, _ in takeFocus() }
        .onChange(of: text) { _, new in if !focused { draft = new } }
        .onChange(of: focused) { _, now in if !now { finish() } }
    }

    private func finish() {
        if draft != text { commit(draft) }
    }

    private func takeFocus() {
        guard focusNow else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true; gotFocus() }
    }
}

struct NumberField: View {
    let value: Double
    let unit: String
    let commit: (Double) -> Void

    var body: some View {
        let shown = value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        Committing(text: shown + unit) { text in
            let cleaned = text.filter { $0.isNumber || $0 == "." || $0 == "-" }
            if let v = Double(cleaned) { commit(v) }
        }
    }
}

/// A length in his units: `12 ft 3 in`, `3' 6"`, `2.5m`, `80cm`, a bare number
/// in feet (or metres, in a metric plan).
/// **X and Y**, in the film's units, each typed or stepped one grid step at
/// a time (Scenario's position steps).
struct PositionFields: View {
    @ObservedObject var model: DiagramModel
    let at: CGPoint
    let set: (CGPoint) -> Void

    var body: some View {
        let step = model.snapStep
        HStack(spacing: 10) {
            Field("X") { axis(Double(at.x), step: step) { set(CGPoint(x: $0, y: at.y)) } }
            Field("Y") { axis(Double(at.y), step: step) { set(CGPoint(x: at.x, y: $0)) } }
        }
    }

    private func axis(_ v: Double, step: Double, _ commit: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 2) {
            Committing(text: (v < -0.0005 ? "-" : "") + model.length(abs(v))) { text in
                let t = text.trimmingCharacters(in: .whitespaces)
                guard let m = LengthField.parse(t, metric: model.settings.units == "m") else { return }
                commit(t.hasPrefix("-") || t.hasPrefix("−") ? -m : m)
            }
            Stepper("", onIncrement: { commit(((v + step) / step).rounded() * step) },
                    onDecrement: { commit(((v - step) / step).rounded() * step) })
                .labelsHidden().controlSize(.mini)
        }
    }
}

struct LengthField: View {
    @ObservedObject var model: DiagramModel
    let value: Double
    let commit: (Double) -> Void

    var body: some View {
        Committing(text: model.length(value)) { text in
            if let m = LengthField.parse(text, metric: model.settings.units == "m") { commit(m) }
        }
    }

    /// `12 ft 3 in`, `12' 3"`, `5 ft 6`, `1.2 m`, `1 m 5 cm`, `450 mm` — every
    /// part added up. A bare number takes the next unit down after a part that
    /// had one (`5 ft 6` is six inches), otherwise the plan's own unit.
    /// A fraction is one number with what comes before it: `6 1/2"` is six
    /// and a half inches, `36' 6 1/2"` thirty-six feet six and a half.
    static func parse(_ raw: String, metric: Bool) -> Double? {
        let s = raw.lowercased().replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2032}", with: "'").replacingOccurrences(of: "\u{2033}", with: "\"")
        let pattern = #"(\d+\s+\d+\s*/\s*\d+|\d+\s*/\s*\d+|\d*\.?\d+)\s*(mm|cm|m|ft|feet|foot|'|inches|inch|in|\")?"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        let parts = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
        guard !parts.isEmpty else { return nil }
        let per: [String: Double] = ["mm": 0.001, "cm": 0.01, "m": 1, "ft": 0.3048, "feet": 0.3048, "foot": 0.3048,
                                     "'": 0.3048, "inches": 0.0254, "inch": 0.0254, "in": 0.0254, "\"": 0.0254]
        let below: [Double: Double] = [1: 0.01, 0.3048: 0.0254]
        /// `6 1/2`, `1/2` or `6.5`.
        func number(_ text: String) -> Double? {
            let t = text.trimmingCharacters(in: .whitespaces)
            guard t.contains("/") else { return Double(t) }
            let halves = t.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            guard halves.count == 2, let den = Double(halves[1]), den > 0 else { return nil }
            let lead = halves[0].split(separator: " ").compactMap { Double($0) }
            guard let num = lead.last else { return nil }
            return (lead.count > 1 ? lead[0] : 0) + num / den
        }
        var total = 0.0, last: Double? = nil
        for part in parts {
            guard let v = number(ns.substring(with: part.range(at: 1))) else { return nil }
            let unit = part.range(at: 2).location == NSNotFound ? nil : ns.substring(with: part.range(at: 2))
            let each = unit.flatMap { per[$0] } ?? last.flatMap { below[$0] } ?? (metric ? 1 : 0.3048)
            total += v * each
            last = each
        }
        return total
    }
}

/// His colours: the six a shot can wear, and any other from the picker.
struct ColourRow: View {
    let selected: String
    var allowNone = false
    let pick: (String) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        HStack(spacing: 7) {
            if allowNone {
                Circle().strokeBorder(Brand.ink3(dark), lineWidth: 1)
                    .overlay(Rectangle().fill(Brand.ink3(dark)).frame(width: 1).rotationEffect(.degrees(45)))
                    .frame(width: 18, height: 18)
                    .overlay(ring(selected.isEmpty))
                    .onTapGesture { pick("") }
                    .help("None")
            }
            ForEach(Array(Columns.palette.enumerated()), id: \.offset) { i, hex in
                Circle().fill(Brand.hex(hex))
                    .frame(width: 18, height: 18)
                    .overlay(ring(selected.uppercased() == "#" + hex.uppercased()))
                    .onTapGesture { pick("#" + hex) }
                    .help(Columns.paletteNames[i])
            }
            let custom = selected.hasPrefix("#") && !Columns.palette.contains { "#" + $0.uppercased() == selected.uppercased() }
            Circle()
                .fill(custom ? AnyShapeStyle(Brand.hex(String(selected.dropFirst())))
                             : AnyShapeStyle(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                                                             center: .center)))
                .frame(width: 18, height: 18)
                .overlay(ring(custom))
                .onTapGesture { ColourPanel.shared.open(selected) { pick($0) } }
                .help("Other Color")
        }
    }

    private func ring(_ on: Bool) -> some View {
        Circle().strokeBorder(Color(nsColor: DiagramInk.pick), lineWidth: on ? 2 : 0).padding(-3)
    }

    static func hex(_ c: Color) -> String? {
        guard let ns = NSColor(c).usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int(ns.redComponent * 255), Int(ns.greenComponent * 255), Int(ns.blueComponent * 255))
    }
}

/// The Mac's colour panel, reporting back to whoever opened it last.
final class ColourPanel: NSObject {
    static let shared = ColourPanel()
    private var report: ((String) -> Void)?

    func open(_ current: String, report: @escaping (String) -> Void) {
        self.report = report
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        if current.hasPrefix("#") { panel.color = Brand.nsHex(String(current.dropFirst())) }
        panel.orderFront(nil)
    }

    @objc private func changed(_ panel: NSColorPanel) {
        guard let c = panel.color.usingColorSpace(.sRGB) else { return }
        report?(String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255)))
    }
}

/// A slider that writes once, when it is let go — one undo, not a hundred.
struct OpacitySlider: View {
    let value: Double
    let commit: (Double) -> Void
    @State private var now: Double = 1
    @State private var moving = false

    var body: some View {
        HStack(spacing: 8) {
            Slider(value: $now, in: 0.1...1) { editing in
                moving = editing
                if !editing, abs(now - value) > 0.001 { commit(now) }
            }
            Text("\(Int((moving ? now : value) * 100))%").sans(Brand.Size.small).monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
        .onAppear { now = value }
        .onChange(of: value) { _, v in if !moving { now = v } }
    }
}
