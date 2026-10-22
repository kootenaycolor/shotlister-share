import SwiftUI
import UniformTypeIdentifiers

/// **Layers** — every piece on the plan, top of the stack first: Scenario's
/// Layers sidebar, which he called "the most robust way to keep track of a
/// complicated scene" (2026-09-28). A tab of the app's left sidebar
/// (`DiagramSidebar`), laid out as Scenario's is: Sort By and Search on top,
/// a picture of each kind, drag handles, groups that open with a chevron,
/// the picked row in blue. Every piece has its own row and its real name —
/// "every unit — every set piece", his words.
///
/// Click picks, ⌘- or ⇧-click adds or takes away — no Multi-select button to
/// turn on first (his note, 2026-09-29) — double-click renames, a
/// drag moves a piece over or under another in the stack, and onto or off a
/// group. Nothing here holds the plan: it reads the model's and asks the
/// engine for every change.
struct DiagramLayers: View {
    @ObservedObject var model: DiagramModel
    @State private var search = ""
    /// Manual (the stack), Name, or Type.
    @State private var sort = "manual"
    /// Groups shut by hand; a group is open until it is.
    @State private var shut: Set<String> = []
    @State private var renaming: String?
    @State private var newName = ""
    @State private var hovered: String?
    @State private var dropAt: (id: String, above: Bool)?
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    static let rowHeight: CGFloat = 36

    /// One line in the list: a piece, or a group standing for its members.
    private struct Line: Identifiable {
        var id: String
        var el: DiagramEl?
        var group: String?
        var members: [DiagramEl] = []
        var indent = 0
    }

    private var els: [DiagramEl] { model.shown.els }

    private var searching: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

    private func matches(_ e: DiagramEl) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        return DiagramItems.name(e, model).lowercased().contains(q)
            || DiagramItems.kindWord(e.kind).lowercased().contains(q)
            // A row is named, not noted — so Search still reaches the Note.
            || model.noteOf(e).lowercased().contains(q)
    }

    /// Top of the stack first. A group shows where its topmost member is; a
    /// piece riding another (a lamp on its stand) shows under it, indented.
    private var stackLines: [Line] {
        var out: [Line] = []
        var seen = Set<String>()
        let nest = !searching
        let riding = nest ? DiagramRigs.riding(els) : []
        for e in els.reversed() where matches(e) && !riding.contains(e.id) {
            if e.group.isEmpty {
                out.append(Line(id: e.id, el: e))
                if nest { out += DiagramRigs.riders(of: e.id, in: els).map { Line(id: $0.0.id, el: $0.0, indent: $0.1) } }
            } else if seen.insert(e.group).inserted {
                let members = els.reversed().filter { $0.group == e.group }
                out.append(Line(id: "group:" + e.group, group: e.group, members: members))
                if !shut.contains(e.group) {
                    out += members.filter(matches).map { Line(id: $0.id, el: $0, indent: 1) }
                }
            }
        }
        return out
    }

    /// Every piece by its name, A to Z.
    private var nameLines: [Line] {
        els.filter(matches)
            .map { (e: $0, n: DiagramItems.name($0, model)) }
            .sorted { $0.n.localizedStandardCompare($1.n) == .orderedAscending }
            .map { Line(id: $0.e.id, el: $0.e) }
    }

    private static let kindOrder = ["camera", "cast", "light", "set", "wall", "door", "window", "opening",
                                    "track", "road", "image", "text", "note", "arrow", "measure", "shape",
                                    "cable", "stroke"]
    private static func heading(_ kind: String) -> String {
        switch kind {
        case "camera": return "Cameras"
        case "cast": return "Cast"
        case "light": return "Lights & Grip"
        case "set": return "Set Pieces"
        case "wall": return "Walls"
        case "door", "window", "opening": return "Doors & Windows"
        case "track", "road": return "Track & Roads"
        case "image": return "Pictures"
        case "text", "note": return "Words"
        default: return "Marks"
        }
    }

    private var kindSections: [(String, [DiagramEl])] {
        var order: [String] = []
        var by: [String: [DiagramEl]] = [:]
        let sorted = els.reversed().filter(matches).sorted {
            (Self.kindOrder.firstIndex(of: $0.kind) ?? 99) < (Self.kindOrder.firstIndex(of: $1.kind) ?? 99)
        }
        for e in sorted {
            let h = Self.heading(e.kind)
            if by[h] == nil { order.append(h) }
            by[h, default: []].append(e)
        }
        return order.map { ($0, by[$0] ?? []) }
    }

    private static let sorts: [(key: String, title: String)] = [("manual", "Manual"), ("name", "Name"), ("type", "Type")]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Menu {
                    Picker("Sort By", selection: $sort) {
                        ForEach(Self.sorts, id: \.key) { Text($0.title).tag($0.key) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    FieldFace(text: Self.sorts.first { $0.key == sort }?.title ?? "Manual", dark: dark)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                .frame(width: 96)
                .help("Sort By")
                FieldText(placeholder: "Search", text: $search)
            }
            .padding(.horizontal, 10).padding(.bottom, 8)
            Rectangle().fill(Brand.rule(dark)).frame(height: 1)
            if els.isEmpty {
                Text("Nothing on the plan").sans(Brand.Size.body).foregroundStyle(Brand.ink2(dark)).padding(12)
                Spacer(minLength: 0)
            } else {
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            switch sort {
                            case "type":
                                ForEach(kindSections, id: \.0) { heading, items in
                                    Text(heading).fieldLabel(dark).padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 2)
                                    ForEach(items) { row(Line(id: $0.id, el: $0), draggable: false) }
                                }
                            case "name":
                                ForEach(nameLines) { row($0, draggable: false) }
                            default:
                                ForEach(stackLines) { row($0, draggable: !searching) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.never)
                    .onChange(of: model.selection) { _, now in
                        guard let first = now.first else { return }
                        withAnimation(.easeOut(duration: 0.15)) { reader.scrollTo(first) }
                    }
                    // Opened on what is already picked: show it.
                    .onAppear {
                        if let first = model.selection.first {
                            DispatchQueue.main.async { reader.scrollTo(first, anchor: .center) }
                        }
                    }
                }
            }
        }
        // A tab of the left sidebar, filling it.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: a row

    @ViewBuilder
    private func row(_ line: Line, draggable: Bool) -> some View {
        let ids = line.el.map { [$0.id] } ?? line.members.map(\.id)
        let picked = !ids.isEmpty && ids.allSatisfy(model.selection.contains)
        let hidden = line.el?.hidden ?? line.members.allSatisfy(\.hidden)
        let locked = line.el?.locked ?? line.members.allSatisfy(\.locked)
        let over = hovered == line.id
        // White on the picked row's blue; the plan's own inks elsewhere.
        let ink = picked ? Color.white : (hidden ? Brand.ink3(dark) : Brand.ink(dark))
        let ink2 = picked ? Color.white.opacity(0.8) : Brand.ink2(dark)
        let base = HStack(spacing: 8) {
            if let g = line.group {
                Button {
                    if shut.contains(g) { shut.remove(g) } else { shut.insert(g) }
                } label: {
                    DiagramChevron(open: !shut.contains(g), ink: ink2).frame(width: 12, height: 12)
                        .frame(width: 14, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            icon(line, ink: ink2).frame(width: 22, height: 20)
            if renaming == line.id {
                TextField("", text: $newName)
                    .textFieldStyle(.plain)
                    .sans(Brand.Size.title)
                    .foregroundStyle(ink)
                    .onSubmit { commitName(line) }
                    .onExitCommand { renaming = nil }
            } else {
                Text(title(line)).sans(Brand.Size.title, weight: line.group != nil ? .semibold : .regular)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !over, let sub = detail(line) {
                    Text(sub).sans(Brand.Size.small).foregroundStyle(ink2).lineLimit(1)
                }
            }
            if over || hidden {
                small(hidden ? "Show" : "Hide", ink2) { model.update(ids, ["hidden": !hidden]) }
            }
            if over || locked {
                small(locked ? "Unlock" : "Lock", ink2) { model.update(ids, ["locked": !locked]) }
            }
            if draggable {
                DiagramDots(ink: ink2.opacity(picked ? 1 : 0.8), columns: 2, rows: 3, gap: 4.5)
                    .frame(width: 8, height: 13)
                    .padding(.leading, 2)
            }
        }
        .padding(.leading, 8 + CGFloat(line.indent) * 20).padding(.trailing, 6)
        .frame(height: Self.rowHeight)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(picked ? Color(nsColor: DiagramInk.pick) : (over ? Brand.glassHover(dark) : .clear)))
        .padding(.horizontal, 6)
        .overlay(alignment: dropAt?.above == true ? .top : .bottom) {
            if dropAt?.id == line.id {
                Rectangle().fill(Color(nsColor: DiagramInk.pick)).frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered = line.id } else if hovered == line.id { hovered = nil }
        }
        .onTapGesture(count: 2) {
            // A frame has no Name to type: it is its size and its cloth.
            guard !(line.el.map(DiagramFrames.isFrame) ?? false) else { return }
            newName = title(line)
            renaming = line.id
        }
        .onTapGesture { pick(ids) }
        .contextMenu { menu(line) }
        .id(line.el?.id ?? line.id)

        if draggable, let key = line.el?.id ?? line.members.first?.id {
            // Where a lone piece lands decides its group: on a group's row or
            // among its members, it joins; anywhere else, it leaves.
            let into = line.group ?? line.el?.group ?? ""
            base
                .onDrag { NSItemProvider(object: (DiagramLayers.dragPrefix + ids.joined(separator: ",")) as NSString) }
                .onDrop(of: [.text], delegate: Drop(key: key, group: into, height: Self.rowHeight, model: model, dropAt: $dropAt))
        } else {
            base
        }
    }

    /// A small picture of what the row is: a set piece or lamp by its own
    /// drawing, anything else by its tool's; a group, a dashed box.
    @ViewBuilder private func icon(_ line: Line, ink: Color) -> some View {
        if let e = line.el {
            if ["light", "set"].contains(e.kind), !e.sym.isEmpty {
                DiagramGlyph(kind: e.kind, sym: e.sym, w: e.w, h: e.h, rot: e.kind == "light" ? -90 : 0, engine: model.engine)
            } else {
                DiagramToolIcon(tool: Self.tool(for: e.kind), engine: model.engine, on: false, ink: ink)
                    .padding(1)
            }
        } else {
            Canvas { c, size in
                let r = CGRect(x: 2, y: 3, width: size.width - 4, height: size.height - 6)
                c.stroke(Path(roundedRect: r, cornerRadius: 2), with: .color(ink),
                         style: StrokeStyle(lineWidth: 1.2, dash: [2.5, 2]))
            }
        }
    }

    static func tool(for kind: String) -> DiagramTool {
        switch kind {
        case "camera": return .camera
        case "cast": return .cast
        case "light": return .light
        case "set": return .set
        case "wall": return .wall
        case "door": return .door
        case "window": return .window
        case "opening": return .opening
        case "track": return .track
        case "road": return .road
        case "text": return .text
        case "arrow": return .arrow
        case "measure": return .measure
        case "stroke": return .pen
        case "cable": return .cable
        case "note": return .note
        case "image": return .picture
        default: return .shape
        }
    }

    private func small(_ title: String, _ ink: Color, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(title).sans(Brand.Size.small, weight: .medium).foregroundStyle(ink)
                .padding(.horizontal, 3).frame(height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The right-click menu on a row: grouping, for what is picked.
    @ViewBuilder private func menu(_ line: Line) -> some View {
        let ids = line.el.map { [$0.id] } ?? line.members.map(\.id)
        let picked = ids.allSatisfy(model.selection.contains) ? model.selection : ids
        let pickedEls = model.plan.els.filter { picked.contains($0.id) }
        let groups = Set(pickedEls.map(\.group))
        if picked.count > 1, !(groups.count == 1 && !(groups.first ?? "").isEmpty) {
            Button("Group") { model.selection = picked; model.group() }
        }
        if let g = line.group {
            Button("Rename Group") { newName = title(line); renaming = line.id }
            Button("Ungroup") { model.selection = model.members(ofGroup: g).map(\.id); model.ungroup() }
        } else if let e = line.el, !e.group.isEmpty {
            Button("Remove from Group") { model.regroup([e.id], into: "") }
        }
        let others = Dictionary(grouping: model.plan.els.filter { !$0.group.isEmpty }, by: \.group)
            .filter { g, _ in line.el.map { $0.group != g } ?? false }
        if let e = line.el, !others.isEmpty {
            Menu("Add to Group") {
                ForEach(others.keys.sorted(), id: \.self) { g in
                    Button(others[g]?.first?.group_name.flatMap { $0.isEmpty ? nil : $0 } ?? "Group") {
                        model.regroup([e.id], into: g)
                    }
                }
            }
        }
    }

    static let dragPrefix = "shotlister-layer:"

    private func title(_ line: Line) -> String {
        if let e = line.el { return DiagramItems.name(e, model) }
        if let name = line.members.first?.group_name, !name.isEmpty { return name }
        return "Group"
    }

    /// What kind of thing it is, when the name does not already say — and
    /// what it is aimed at. A group: how many.
    private func detail(_ line: Line) -> String? {
        guard let e = line.el else { return "\(line.members.count)" }
        var parts: [String] = []
        let kind = kindWord(e)
        let name = DiagramItems.name(e, model)
        // A set piece called by its own drawing's name already says what it is.
        if name != kind, !(e.kind == "set" && name == DiagramItems.symName(e, model)) { parts.append(kind) }
        if !e.aim.isEmpty, let t = model.shown.els.first(where: { $0.id == e.aim }) {
            parts.append("→ " + DiagramItems.name(t, model))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Grip lives with the lights in the library but is not a light.
    private func kindWord(_ e: DiagramEl) -> String {
        // A frame is grip, but the tool that puts one down is called Frame.
        if DiagramFrames.isFrame(e) { return "Frame" }
        if e.kind == "light", let sym = model.library?.symbols.first(where: { $0.id == e.sym }), sym.beam <= 0 { return "Grip" }
        return DiagramItems.kindWord(e.kind)
    }

    private func pick(_ ids: [String]) {
        let mods = NSEvent.modifierFlags
        if mods.contains(.shift) || mods.contains(.command) {
            if ids.allSatisfy(model.selection.contains) {
                model.selection.removeAll { ids.contains($0) }
            } else {
                model.selection += ids.filter { !model.selection.contains($0) }
            }
        } else {
            model.selection = ids
        }
    }

    private func commitName(_ line: Line) {
        let name = newName.trimmingCharacters(in: .whitespaces)
        renaming = nil
        if let g = line.group {
            if name != title(line) { model.renameGroup(g, name) }
        } else if let e = line.el, name != DiagramItems.name(e, model), !DiagramFrames.isFrame(e) {
            // Written to the field that *is* its Name — a lamp's own Name,
            // anything else's `label` — never over its Note.
            model.update([e.id], [DiagramMarks.isLamp(e, model) ? "lamp_name" : "label": name])
        }
    }

    /// A row a dragged layer can land on: over its top half, just above it;
    /// its bottom half, just below.
    private struct Drop: DropDelegate {
        let key: String
        /// The group a lone piece dropped here belongs in — empty for none.
        let group: String
        let height: CGFloat
        let model: DiagramModel
        @Binding var dropAt: (id: String, above: Bool)?

        func dropUpdated(info: DropInfo) -> DropProposal? {
            dropAt = (key, info.location.y < height / 2)
            return DropProposal(operation: .move)
        }
        func dropExited(info: DropInfo) {
            if dropAt?.id == key { dropAt = nil }
        }
        func performDrop(info: DropInfo) -> Bool {
            let above = dropAt?.above ?? true
            dropAt = nil
            guard let item = info.itemProviders(for: [.text]).first else { return false }
            item.loadObject(ofClass: NSString.self) { obj, _ in
                guard let s = obj as? String, s.hasPrefix(DiagramLayers.dragPrefix) else { return }
                let ids = s.dropFirst(DiagramLayers.dragPrefix.count).split(separator: ",").map(String.init)
                DispatchQueue.main.async {
                    guard !ids.contains(key) else { return }
                    let order: [String: Any] = ["op": "order", "ids": ids, "to": above ? "above" : "below", "next": key]
                    // One piece moves in or out of a group with its drop; a
                    // whole group dragged keeps itself.
                    if ids.count == 1, let e = model.el(ids[0]), e.group != group {
                        model.regroup(ids, into: group, then: order)
                    } else {
                        model.restack(ids, next: key, above: above)
                    }
                }
            }
            return true
        }
    }
}

/// Dots in a grid — the drag handle (⋮⋮) and Multi-select's mark. Drawn, not
/// a stock glyph.
struct DiagramDots: View {
    let ink: Color
    var columns = 2
    var rows = 3
    var gap: CGFloat = 4.5
    var body: some View {
        Canvas { c, size in
            let r: CGFloat = 1.3
            let w = CGFloat(columns - 1) * gap, h = CGFloat(rows - 1) * gap
            let o = CGPoint(x: (size.width - w) / 2, y: (size.height - h) / 2)
            for i in 0..<columns {
                for j in 0..<rows {
                    let p = CGPoint(x: o.x + CGFloat(i) * gap, y: o.y + CGFloat(j) * gap)
                    c.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(ink))
                }
            }
        }
    }
}

/// A group's open-or-shut mark: pointing down when open, right when shut.
struct DiagramChevron: View {
    let open: Bool
    let ink: Color
    var body: some View {
        Canvas { c, size in
            var p = Path()
            let (w, h) = (size.width, size.height)
            if open {
                p.move(to: CGPoint(x: w * 0.22, y: h * 0.36)); p.addLine(to: CGPoint(x: w * 0.5, y: h * 0.64))
                p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.36))
            } else {
                p.move(to: CGPoint(x: w * 0.36, y: h * 0.22)); p.addLine(to: CGPoint(x: w * 0.64, y: h * 0.5))
                p.addLine(to: CGPoint(x: w * 0.36, y: h * 0.78))
            }
            c.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}
