import SwiftUI
import PhotosUI

/// **Editing: the shot list for putting information in.** His words,
/// 2026-10-07: *"there should be an overall editing mode and then 'display'
/// mode for shot lists - editng more is more about information input, it is
/// not the default mode but something you turn on"*. Explored in Ref 1615
/// (`design/38-editing`, `design/39-one-shot`); his picks were one shot at a
/// time, words typed straight onto it, and **"scroll down"** to the next.
///
/// So every shot in the film, one after another, each drawn as a page you
/// write on: the frame edge to edge, then the title, description and notes
/// typed in place with no boxes round them, then size, lens and move large
/// and the rest quiet. A camera value opens the film's own list.
///
/// Two things scrolling down has to get right, named when he chose it:
/// - **Never typing into the wrong shot.** The bar always names the shot the
///   cursor is in, and while typing every other shot dims.
/// - **Never mistaking it for Display.** Editing in the film's colour, Done,
///   no tab bar, and every empty field saying its own name.
///
/// **Never stored.** The switch is plain `@State` on the shot list, not
/// `@AppStorage` like List and Storyboard: the app always opens in Display,
/// so it is never found in Editing at call time.
struct EditingShotList: View {
    @EnvironmentObject private var session: Session
    /// The shot to start at: the one whose Edit was tapped, or the open one
    /// when the pencil was. One Editing, whichever way in (2026-10-09).
    var start: Engine.Row.ID? = nil
    @FocusState private var focus: EditField?
    /// The shot at the top of the screen, for the bar.
    @State private var current: String?
    @State private var picking: EditField?

    private var rows: [Engine.Row] { session.scenes.flatMap { session.rows(inScene: $0.id) } }

    var body: some View {
        let rows = self.rows
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        EditingShot(row: row, focus: $focus) { column in
                            // A camera value is chosen, not typed: the
                            // keyboard goes, and does not come back after.
                            focus = nil
                            picking = EditField(row: row.id, column: column)
                        }
                            // The shot being written is lit; the rest step back.
                            .opacity(focus == nil || focus?.row == row.id ? 1 : 0.3)
                            .animation(.easeOut(duration: 0.2), value: focus)
                            .id(row.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.bottom, 40)
            }
            .scrollPosition(id: $current, anchor: .top)
            .scrollDismissesKeyboard(.interactively)
            // **The line being typed sits above the keyboard**, not behind it.
            // Asked for once the keyboard is up, when the room is known.
            .onChange(of: focus) { _, field in
                guard let field else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.snappy) { reader.scrollTo(field, anchor: UnitPoint(x: 0.5, y: 0.2)) }
                }
            }
            .background(Style.page)
            .onAppear {
                guard let start else { return }
                // The bar names the shot at the top, and a scroll made in code
                // does not tell it; say it here as well.
                current = start
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    reader.scrollTo(start, anchor: .top)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { bar(rows) }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) { keys(rows, reader) }
            }
            .sheet(item: $picking) { field in
                ChoiceSheet(rowId: field.row, field: field.column)
                    .environmentObject(session)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    /// Editing, and which shot: "10D  19 of 69".
    private func bar(_ rows: [Engine.Row]) -> some View {
        let id = focus?.row ?? current ?? rows.first?.id
        let index = rows.firstIndex { $0.id == id }
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("EDITING")
                .font(.system(size: 13, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(Color.accentColor)
            Spacer(minLength: 8)
            if let index {
                Text(rows[index].number)
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                Text("\(index + 1) of \(rows.count)")
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(Style.ink2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Style.page)
        .overlay(alignment: .bottom) { Rectangle().fill(Style.rule).frame(height: 1) }
        .accessibilityIdentifier("editing.bar")
    }

    // ---- the bar over the keyboard -----------------------------------------

    /// Every typed field, shown in the Columns tab or not: Editing is where
    /// all of them are filled in (his rule, 2026-10-09).
    private var written: [String] {
        let own = (session.view?.columns ?? [])
            .filter { $0.name.hasPrefix("c_") && $0.shape == "text" }
            .map(\.name)
        return ["title", "description", "notes"] + own
    }

    @ViewBuilder
    private func keys(_ rows: [Engine.Row], _ reader: ScrollViewProxy) -> some View {
        let fields = written
        Button { step(-1, fields) } label: { Image(systemName: "chevron.up") }
            .accessibilityLabel("Previous Field")
        Button { step(1, fields) } label: { Image(systemName: "chevron.down") }
            .accessibilityLabel("Next Field")
        Spacer()
        Text(focus.map { name(of: $0.column) } ?? "")
            .font(.footnote)
            .foregroundStyle(.secondary)
        Spacer()
        Button("Next Shot") { nextShot(rows, reader) }
            .fontWeight(.semibold)
    }

    private func step(_ by: Int, _ fields: [String]) {
        guard let now = focus, let at = fields.firstIndex(of: now.column) else { return }
        let to = (at + by + fields.count) % fields.count
        focus = EditField(row: now.row, column: fields[to])
    }

    /// The next shot, with the cursor in the same field: a run of titles is
    /// type, Next Shot, type.
    private func nextShot(_ rows: [Engine.Row], _ reader: ScrollViewProxy) {
        guard let now = focus, let at = rows.firstIndex(where: { $0.id == now.row }),
              at + 1 < rows.count else { return }
        let next = rows[at + 1].id
        withAnimation(.snappy) { reader.scrollTo(next, anchor: .top) }
        // After the scroll, or the field is not there yet to take the cursor.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            focus = EditField(row: next, column: now.column)
        }
    }

    private func name(of column: String) -> String {
        session.view?.columns.first { $0.name == column }?.shown ?? column.capitalized
    }
}

/// A field of a shot: which shot, which column.
struct EditField: Hashable, Identifiable {
    let row: String
    let column: String
    var id: String { row + "\u{1}" + column }
}

/// **One shot as a page you write on.**
struct EditingShot: View {
    @EnvironmentObject private var session: Session
    let row: Engine.Row
    var focus: FocusState<EditField?>.Binding
    let pick: (String) -> Void

    /// Held here while he types, and written on every change. Reading each
    /// keystroke back from the engine would fight the cursor.
    @State private var title = ""
    @State private var description = ""
    @State private var notes = ""
    @State private var loaded = ""
    @State private var choosing = false
    @State private var picked: [PhotosPickerItem] = []

    private var columns: [Engine.Column] { session.view?.columns ?? [] }

    /// **A thumbnail, whatever Picture Size says** (his note, 2026-10-09:
    /// "in editing mode the pictures should not be full frame, this needs to
    /// be optimized for data input"). The picture names the shot; the room
    /// goes to the fields.
    private let width: CGFloat = 104
    @EnvironmentObject private var frames: Frames
    @State private var viewing: Engine.Still?

    /// **Drawn the way the list draws an opened shot** (his ruling,
    /// 2026-10-09: "the editing too needs to follow the design principles"):
    /// the picture beside the words at the list's Picture Size, the title
    /// typed next to it, every camera column as the Mac's pills under its
    /// label, then the description and notes. An empty value is a dashed pill
    /// saying its own name.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                frame
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.number)
                        .font(.system(size: 15, weight: .heavy).monospacedDigit())
                        .frame(minHeight: 28, alignment: .leading)
                    if !sceneLine.isEmpty {
                        Text(sceneLine)
                            .font(.system(size: 13))
                            .foregroundStyle(Style.ink3)
                            .lineLimit(1)
                    }
                    if shows("title") {
                        write("title", $title, .system(size: 15, weight: .semibold), Color(.label))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 0) {
                if !craft.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .topLeading),
                                        GridItem(.flexible(), alignment: .topLeading)],
                              alignment: .leading, spacing: 14) {
                        ForEach(craft, id: \.self) { name in field(name) }
                    }
                    .padding(.bottom, 4)
                }
                if shows("description") { said("description", $description, Color(.label)) }
                if shows("notes") { said("notes", $notes, Style.ink2) }
                ForEach(ownTexts, id: \.self) { name in
                    OwnText(row: row, column: name, label: label(name), focus: focus)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Style.page, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 12)
        }
        .padding(12)
        .background(Style.card, in: RoundedRectangle(cornerRadius: Style.Radius.group, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .onAppear { load() }
        .onChange(of: row.id) { _, _ in load() }
        .onChange(of: mirror) { _, _ in adopt() }
        // **Written as he types**, the way the scene's own page writes its
        // title. Skipped when the change is the engine's own answer arriving.
        .onChange(of: title) { _, new in if new != row.title { session.set(row, "title", to: new) } }
        .onChange(of: description) { _, new in
            if new != row.description { session.set(row, "description", to: new) }
        }
        .onChange(of: notes) { _, new in if new != row.notes { session.set(row, "notes", to: new) } }
        .photosPicker(isPresented: $choosing, selection: $picked, matching: .any(of: [.images, .videos]))
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task { await bringIn(items) }
        }
    }

    // ---- the frame ------------------------------------------------------------

    /// The thumbnail, and what can be done to the shot's media from it:
    /// a frame from Photos or a viewfinder app, or the viewer, where a frame
    /// is cropped, deleted or trimmed.
    private var frame: some View {
        Menu {
            Button { choosing = true } label: {
                Label("Photos Library", systemImage: "photo.on.rectangle")
            }
            if !Viewfinders.installed.isEmpty {
                Section("Shoot a Frame") {
                    ForEach(Viewfinders.installed) { app in
                        Button { app.open() } label: { Label(app.name, systemImage: "camera.viewfinder") }
                    }
                }
            }
            if !row.stills.isEmpty {
                Divider()
                Button {
                    viewing = row.stills.first { $0.key == true } ?? row.stills.first
                } label: {
                    Label(row.stills.count > 1 ? "View \(row.stills.count) Frames" : "View Frame",
                          systemImage: "eye")
                }
            }
        } label: {
            Group {
                if row.stills.isEmpty {
                    Rectangle()
                        .fill(Color(.tertiarySystemFill))
                        .aspectRatio(session.ratio, contentMode: .fit)
                        .overlay {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(Style.ink3)
                        }
                } else {
                    FramePlate(frame: row.frame, ratio: session.ratio, board: row.board)
                }
            }
            .frame(width: width)
            .overlay(alignment: .bottomTrailing) {
                if row.stills.count > 1 {
                    Text("\(row.stills.count)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(session.isReadOnly)
        .accessibilityLabel("Frame for \(row.number)")
        .fullScreenCover(item: $viewing) { still in
            StillViewer(still: still, all: row.stills, onDelete: { session.detach($0) },
                        cropTo: session.ratio)
                .environmentObject(session)
                .environmentObject(frames)
        }
    }

    private func bringIn(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let file = try? await item.loadTransferable(type: Picked.self) {
                defer { file.discard() }
                if file.isClip {
                    await session.attach(clipAt: file.url, to: row.shot)
                } else if let data = try? Data(contentsOf: file.url) {
                    session.attach(data, named: file.url.lastPathComponent, to: row)
                }
            } else if let data = try? await item.loadTransferable(type: Data.self) {
                session.attach(data, to: row)
            }
        }
        picked = []
    }

    // ---- the words, typed in place -------------------------------------------

    /// A field with no box: the words sit on the page, and an empty one says
    /// its own name, dim, where they will go.
    private func write(_ name: String, _ text: Binding<String>, _ font: Font, _ ink: Color) -> some View {
        TextField("", text: text, prompt: Text(label(name)).foregroundStyle(Style.ink3.opacity(0.55)),
                  axis: .vertical)
            .font(font)
            .foregroundStyle(ink)
            .lineLimit(1...12)
            .focused(focus, equals: EditField(row: row.id, column: name))
            .id(EditField(row: row.id, column: name))
            .disabled(session.isReadOnly)
            .accessibilityIdentifier("edit.\(row.number).\(name)")
    }

    // ---- the camera ----------------------------------------------------------

    /// **Every column the film has, in its own order, shown in the Columns
    /// tab or hidden** (his rule, 2026-10-09: "in editing mode all columns
    /// should be visible to edit"). The Columns tab says what Display shows;
    /// Editing is where everything is filled in. Left out: the frame (at the
    /// top), the typed fields (below), the script (tied in the script itself),
    /// and pictures and places in a column of his own, which have their own
    /// screens.
    private var craft: [String] {
        columns.filter { column in
            switch column.name {
            case "image", "title", "description", "notes", "script": return false
            default:
                if column.name.hasPrefix("c_") {
                    // A checkmark too (2026-10-09): the Mac flips one with a
                    // click, and the phone had left it out of Editing.
                    return ["single", "multi", "check"].contains(column.shape)
                }
                return true
            }
        }.map(\.name)
    }

    /// His own typed columns, under the description and notes.
    private var ownTexts: [String] {
        columns.filter { $0.name.hasPrefix("c_") && $0.shape == "text" }.map(\.name)
    }

    /// One column: its label, then its values as pills, or a dashed pill with
    /// its name when it has none. A column that holds several takes a +.
    @ViewBuilder
    private func field(_ name: String) -> some View {
        switch name {
        case "day": dayField(name)
        case "struck": shotField(name)
        default:
            if columns.first(where: { $0.name == name })?.shape == "check" {
                checkField(name)
            } else {
                pickField(name)
            }
        }
    }

    /// The column's label, small, over its pills.
    private func head(_ name: String) -> some View {
        Text(label(name))
            .font(.system(size: Kit.Size.label, weight: .semibold))
            .foregroundStyle(Style.ink3)
    }

    /// **The shoot day**, from the real days, never typed, the way the shot's
    /// page sets it: the shot goes to the end of that day's order.
    private func dayField(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            head(name)
            Menu {
                ForEach(session.pickableDays(keeping: row.dayId)) { day in
                    Button { session.shoot(row, day: day.id, before: nil) } label: {
                        if row.dayId == day.id { Label(day.label, systemImage: "checkmark") } else { Text(day.label) }
                    }
                }
                if !session.days.isEmpty { Divider() }
                Button { session.shoot(row, day: nil, before: nil) } label: {
                    if (row.dayId ?? "").isEmpty { Label("Not Scheduled", systemImage: "checkmark") } else { Text("Not Scheduled") }
                }
            } label: {
                if let day = row.day, !day.isEmpty {
                    solid(day, TagInk.own.word, TagInk.own.ground)
                } else {
                    DashedPill(text: session.days.isEmpty ? "No Shoot Days" : label(name))
                }
            }
            .disabled(session.isReadOnly)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("edit.\(row.number).\(name)")
    }

    /// **Shot**, one tap: the same mark the list strikes with.
    private func shotField(_ name: String) -> some View {
        Button { session.strike(row, !row.struck) } label: {
            VStack(alignment: .leading, spacing: 6) {
                head(name)
                if row.struck {
                    solid(label(name), .white, Color.accentColor)
                } else {
                    DashedPill(text: label(name))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(session.isReadOnly)
        .accessibilityIdentifier("edit.\(row.number).\(name)")
    }

    /// His own checkmark column: a tap flips it, written as the Mac writes
    /// it (`1`, or empty).
    private func checkField(_ name: String) -> some View {
        let ticked = !row.cell(name).isEmpty
        return Button { session.set(row, name, to: ticked ? "" : "1") } label: {
            VStack(alignment: .leading, spacing: 6) {
                head(name)
                if ticked {
                    solid("✓ " + label(name), .white, Color.accentColor)
                } else {
                    DashedPill(text: label(name))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(session.isReadOnly)
        .accessibilityIdentifier("edit.\(row.number).\(name)")
    }

    private func solid(_ text: String, _ word: Color, _ ground: Color) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(word)
            .background(ground, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    /// A value chosen from a list: its pills, or a dashed one, and a tap brings
    /// the list up. A camera wears its own colour, the way the Mac shows it.
    private func pickField(_ name: String) -> some View {
        let column = columns.first { $0.name == name }
        let ink = Chips.ink(name, kind: column?.kind) ?? .own
        let cameraTint = name == "camera" ? row.unit?.tint : nil
        let values = row.cell(name)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Button { pick(name) } label: {
            VStack(alignment: .leading, spacing: 6) {
                head(name)
                if values.isEmpty {
                    DashedPill(text: label(name))
                } else {
                    Wrap(spacing: 5) {
                        ForEach(values, id: \.self) { value in
                            if let cameraTint {
                                solid(value, cameraTint, cameraTint.opacity(0.24))
                            } else {
                                solid(value, ink.word, ink.ground)
                            }
                        }
                        if column?.shape == "multi" { DashedPill(text: "+") }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(session.isReadOnly)
        .accessibilityIdentifier("edit.\(row.number).\(name)")
    }

    /// The description or the notes: a small label, then the words typed in
    /// place with no box.
    private func said(_ name: String, _ text: Binding<String>, _ ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.bottom, 6)
            Text(label(name))
                .font(.system(size: Kit.Size.label, weight: .semibold))
                .foregroundStyle(Style.ink3)
            write(name, text, .system(size: 14.5), ink)
        }
        .padding(.top, 10)
    }

    // ---- small things ----------------------------------------------------------

    private var sceneLine: String {
        guard let id = row.sceneId, let scene = session.scene(id) else { return "" }
        let name = session.isCommercial && !scene.title.isEmpty ? scene.title : scene.heading
        return name.isEmpty ? scene.number : "\(scene.number) \u{00B7} \(name)"
    }

    private func shows(_ name: String) -> Bool {
        // Hidden in the Columns tab still shows here: Editing fills in everything.
        columns.contains { $0.name == name }
    }

    private func label(_ name: String) -> String {
        columns.first { $0.name == name }?.shown ?? name.capitalized
    }

    private var mirror: String {
        [row.title, row.description, row.notes].joined(separator: "\u{1}")
    }

    private func adopt() {
        let typing = focus.wrappedValue?.row == row.id ? focus.wrappedValue?.column : nil
        if typing != "title", row.title != title { title = row.title }
        if typing != "description", row.description != description { description = row.description }
        if typing != "notes", row.notes != notes { notes = row.notes }
    }

    private func load() {
        guard loaded != row.id else { return }
        loaded = row.id
        title = row.title
        description = row.description
        notes = row.notes
    }
}

/// **The film's own list for one camera field**, rising from the bottom: the
/// ones this film uses most first, then the whole list in its order. One tap
/// sets a single choice and closes; Angle and Tags hold several, so a tap
/// adds or takes away and Done closes.
struct ChoiceSheet: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    let rowId: String
    let field: String

    @State private var adding = false
    @State private var fresh = ""

    private var row: Engine.Row? { session.row(rowId) }
    private var column: Engine.Column? { session.view?.columns.first { $0.name == field } }
    private var multiple: Bool { column?.shape == "multi" }
    private var chosen: [String] { row?.cell(field) ?? [] }
    /// A camera and a sequence are records, not words: their lists are the
    /// project's cameras and sequences, by name.
    private var terms: [String] {
        switch field {
        case "camera": return session.units.map(\.label)
        case "sequence": return session.sequences.map(\.title)
        default: return session.vocabulary(field)
        }
    }

    /// How many shots in the film use each term.
    private var used: [(String, Int)] {
        var count: [String: Int] = [:]
        for scene in session.scenes {
            for shot in session.rows(inScene: scene.id) {
                for value in shot.cell(field) { count[value, default: 0] += 1 }
            }
        }
        return terms.compactMap { term in count[term].map { (term, $0) } }
            .sorted { $0.1 > $1.1 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    let top = Array(used.prefix(6))
                    if !top.isEmpty, terms.count > 8 {
                        Kicker("Most Used")
                        Wrap(spacing: 7) {
                            ForEach(top, id: \.0) { term, count in
                                pill(term, count: count, large: true)
                            }
                        }
                        Kicker("All").padding(.top, 8)
                    }
                    Wrap(spacing: 7) {
                        ForEach(terms, id: \.self) { term in pill(term, count: nil, large: false) }
                        if column?.locked != true {
                            Button { fresh = ""; adding = true } label: {
                                Text("New\u{2026}")
                                    .font(.system(size: 15, weight: .medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Style.ink3.opacity(0.5)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(18)
            }
            .navigationTitle(column?.shown ?? field.capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { write(""); dismiss() }
                        .disabled(chosen.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .alert("New \(column?.shown ?? field)", isPresented: $adding) {
                TextField("Value", text: $fresh)
                Button("Cancel", role: .cancel) {}
                Button("Add") {
                    let value = fresh.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { return }
                    if field == "camera" {
                        session.addUnit(named: value)
                    } else if field == "sequence" {
                        _ = session.addSequence(named: value)
                    }
                    write(multiple ? (chosen + [value]).joined(separator: ", ") : value)
                    if !multiple { dismiss() }
                }
            }
        }
    }

    private func pill(_ term: String, count: Int?, large: Bool) -> some View {
        let on = chosen.contains(term)
        let ink = Chips.ink(field, kind: column?.kind) ?? .own
        return Button { tapped(term) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(term)
                    .font(.system(size: large ? 17 : 15, weight: large ? .semibold : .medium))
                if let count {
                    Text("\(count)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(on ? ink.word.opacity(0.75) : Style.ink3)
                }
            }
            // **The pill it will be in the list**: the column's own colour
            // when chosen, the same box, so choosing looks like the result.
            .foregroundStyle(on ? ink.word : Color(.label))
            .padding(.horizontal, large ? 13 : 12)
            .padding(.vertical, large ? 9 : 7)
            .background(on ? ink.ground : Color(.tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(on ? ink.word.opacity(0.7) : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("choice.\(term)")
    }

    private func tapped(_ term: String) {
        if multiple {
            var now = chosen
            if let at = now.firstIndex(of: term) { now.remove(at: at) } else { now.append(term) }
            write(now.joined(separator: ", "))
        } else {
            write(chosen == [term] ? "" : term)
            dismiss()
        }
    }

    private func write(_ value: String) {
        guard let row else { return }
        switch field {
        case "camera":
            // The field takes the camera's id; its name is what was tapped.
            session.set(row, "camera", to: session.units.first { $0.label == value }?.id ?? "")
        case "sequence":
            // It hangs on the scene, so the whole scene moves with it.
            guard let scene = row.sceneId else { return }
            session.setSequence(ofScene: scene, to: session.sequences.first { $0.title == value }?.id ?? "")
        default:
            session.set(row, field, to: value)
        }
    }
}

/// A value not set yet: its name in a dashed box, the shape a pill will take.
struct DashedPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Style.ink3)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Style.ink3.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
    }
}

/// **One of his own typed columns**, typed in place like the description:
/// held while he types, written on every change.
private struct OwnText: View {
    @EnvironmentObject private var session: Session
    let row: Engine.Row
    let column: String
    let label: String
    var focus: FocusState<EditField?>.Binding
    @State private var text = ""
    @State private var loaded = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.bottom, 6)
            Text(label)
                .font(.system(size: Kit.Size.label, weight: .semibold))
                .foregroundStyle(Style.ink3)
            TextField("", text: $text, prompt: Text(label).foregroundStyle(Style.ink3.opacity(0.55)),
                      axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(1...8)
                .focused(focus, equals: EditField(row: row.id, column: column))
                .id(EditField(row: row.id, column: column))
                .disabled(session.isReadOnly)
                .accessibilityIdentifier("edit.\(row.number).\(column)")
        }
        .padding(.top, 10)
        .onAppear {
            guard loaded != row.id else { return }
            loaded = row.id
            text = row.cell(column).first ?? ""
        }
        .onChange(of: text) { _, new in
            if new != (row.cell(column).first ?? "") { session.set(row, column, to: new) }
        }
    }
}
