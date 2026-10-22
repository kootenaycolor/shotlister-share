import SwiftUI

extension ColumnTemplates {
    /// Every ready-made column, ungrouped — for looking one up by name.
    static var all: [Ready] { groups.flatMap(\.1) }

    static func named(_ label: String) -> Ready? {
        all.first { $0.label.compare(label, options: .caseInsensitive) == .orderedSame }
    }

    /// Whether the project already has a column by this name. Compared against
    /// the **label** a person reads, not the slug underneath, and case-blind:
    /// a project with "cast" should not be offered "Cast".
    static func has(_ label: String, in columns: [ViewModel.Column]) -> Bool {
        columns.contains { column in
            Columns.label(column.name).compare(label, options: .caseInsensitive) == .orderedSame
        }
    }

    /// **The same door the sheet's text field uses.** A template that wrote
    /// columns its own way would be a second way to make one, and two ways to
    /// do a thing is how they drift apart.
    @discardableResult
    static func add(_ ready: Ready, state: ShellState) -> String? {
        guard let engine = state.engine else { return nil }
        let before = Set((state.view?.columns ?? []).map(\.name))
        state.replace(engine.addColumn(label: ready.label, kind: ready.kind))
        // Asked of the engine's answer rather than guessed at from the order.
        let landed = (state.view?.columns ?? []).first { !before.contains($0.name) }?.name
        // **And the list it arrives knowing** — Ref 346. Through `list add`,
        // the same door the list's own page uses, so a term learned here is a
        // term learned any other way; nothing about a template is special once
        // the column exists.
        if let landed {
            for value in ready.values {
                engine.addValue(field: landed, value: value)
            }
            // The values went in behind the view model's back — `list add`
            // answers `ok`, not a document — so ask for a fresh one or the
            // dropdown draws empty until something else forces a repaint.
            if !ready.values.isEmpty { state.replace(engine.view()) }
        }
        state.columnLanded = landed
        return landed
    }
}

/// The Edit Columns sheet — Cadrage's form, the engine's truth.
///
/// Every column the document has, in the order the table (and the document
/// page's technical line) reads them: drag a row to rearrange, click the eye
/// to show or hide. **Visibility is whole-project** — Nathaniel's call after
/// per-scene turned out not to fit the engine (see `DECISIONS.md`); the sheet
/// is drawn honestly against that, saying "in every scene" rather than
/// pretending a scene switch it does not have.
///
/// A new column is made here too — name it, say its shape (text, a choice
/// list, several choices, a checkmark), and it appears at the end of the
/// table, project-wide, in the file. Media and location columns are declared
/// in the document schema already but arrive with the Storyboard and
/// Locations work — offering them now would draw a cell nothing can fill.
/// Hiding is how a list gets shorter; showing one puts it back where it was,
/// because hidden columns keep their place.
struct EditColumnsSheet: View {
    @ObservedObject var state: ShellState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    private var dark: Bool { scheme == .dark }

    private var columns: [ViewModel.Column] { state.view?.columns ?? [] }
    private var hidden: [ViewModel.Column] { columns.filter { !$0.visible } }

    @State private var newName = ""
    @State private var newKind = "text"
    /// The column being looked at closely, if any — the per-column page.
    /// The shell holds it (`state.editingColumn`) so a check can open it.
    private var opened: Binding<ViewModel.Column?> {
        Binding(
            get: { columns.first { $0.name == state.editingColumn } },
            set: { state.editingColumn = $0?.name }
        )
    }

    /// The shapes a person can pick today. The engine also knows media and
    /// location; they join this menu when something can draw them.
    private static let kinds: [(String, String)] = [
        ("text", "Text"),
        ("single", "Single Choice"),
        ("multi", "Multiple Choice"),
        ("check", "Checkmark"),
    ]

    var body: some View {
        // The one anatomy at the narrow width: the list, then the row that
        // makes a column, then the two other ways the list grows as row
        // actions — "+ Show a column", "+ From template" — and a footer that
        // holds Done alone. No accent circle, no field-type glyphs. 2026-09-14.
        Sheet(title: "Columns", width: .narrow, height: 560, scrolls: false) {
            VStack(spacing: 0) {
                // **A new column lands at the end, which is off the bottom of
                // this list.** So the list is scrolled to it — otherwise adding
                // one looks exactly like nothing happening. His words,
                // 2026-08-22: *"I just see a hide feature — not delete."*
                ScrollViewReader { hand in
                    List {
                        ForEach(columns) { column in
                            row(column)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .id(column.name)
                        }
                        .onMove { from, to in
                            guard let engine = state.engine else { return }
                            var order = columns.map(\.name)
                            order.move(fromOffsets: from, toOffset: to)
                            state.replace(engine.columnOrder(order))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onChange(of: state.columnLanded) { _, name in
                        guard let name else { return }
                        withAnimation { hand.scrollTo(name, anchor: .center) }
                    }
                    // **After a beat, not on appear.** `scrollTo` on appear
                    // does nothing at all: the list has not laid its rows out
                    // yet, so there is no row with that id to scroll to.
                    .task {
                        guard let name = state.columnLanded else { return }
                        try? await Task.sleep(nanoseconds: 120_000_000)
                        withAnimation { hand.scrollTo(name, anchor: .center) }
                    }
                }

                Divider().overlay(Brand.rule(dark))

                // A column of the project's own: a name and a shape. It lands
                // at the end of the table, in every scene, in the file.
                HStack(spacing: 8) {
                    FieldText(placeholder: "New column name", text: $newName,
                              onSubmit: addColumn)
                    Dropdown(selection: $newKind,
                             items: Self.kinds.map { Dropdown.Item($0.0, $0.1) },
                             width: 150)
                    Button("Add", action: addColumn)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 8)

                HStack(spacing: 14) {
                    // Showing a hidden column is the other way the list grows.
                    Menu {
                        if hidden.isEmpty {
                            Button("All columns shown") {}.disabled(true)
                        }
                        ForEach(hidden) { column in
                            Button(Columns.label(column.name)) {
                                guard let engine = state.engine else { return }
                                state.replace(engine.column(column.name, visible: true))
                            }
                        }
                    } label: {
                        PlusLabel(text: "Show a column", dark: dark).rowAction(dark)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()

                    // **The third way the list grows.** A column the project
                    // already has is shown greyed rather than dropped, so the
                    // list is the same list every time.
                    Menu {
                        ForEach(ColumnTemplates.groups, id: \.0) { title, ready in
                            Section(title) {
                                ForEach(ready, id: \.label) { one in
                                    Button(one.label) { ColumnTemplates.add(one, state: state) }
                                        .disabled(ColumnTemplates.has(one.label, in: columns))
                                }
                            }
                        }
                    } label: {
                        PlusLabel(text: "From template", dark: dark).rowAction(dark)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        } trailing: {
            Button("Done") { dismiss() }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
        }
        .sheet(item: opened) { column in
            ColumnPage(state: state, column: column)
        }
    }

    private func addColumn() {
        let label = newName.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, let engine = state.engine else { return }
        let before = Set((state.view?.columns ?? []).map(\.name))
        state.replace(engine.addColumn(label: label, kind: newKind))
        // Asked of the engine's answer rather than guessed at from the order
        // — the same way adding a location finds the one it just made.
        state.columnLanded = (state.view?.columns ?? []).first { !before.contains($0.name) }?.name
        newName = ""
    }

    /// The same warning the column's own page gives, said in one place so the
    /// two doors cannot come to disagree about what a delete costs.
    private func remove(_ column: ViewModel.Column) {
        guard let engine = state.engine else { return }
        let written = (state.view?.allRows ?? [])
            .filter { !($0.custom?[column.name] ?? []).isEmpty }
            .count
        let ask = NSAlert()
        ask.messageText = "Delete “\(Columns.label(column.name))”?"
        ask.informativeText = written == 0
            ? "Nothing is written in it."
            : "\(written) shot\(written == 1 ? "" : "s") ha\(written == 1 ? "s" : "ve") something written in it. That goes too."
        ask.addButton(withTitle: "Delete")
        ask.addButton(withTitle: "Cancel")
        ask.alertStyle = .warning
        guard ask.runModal() == .alertFirstButtonReturn else { return }
        state.replace(engine.deleteColumn(field: column.name))
    }

    private func row(_ column: ViewModel.Column) -> some View {
        HStack(spacing: 10) {
            // The handle carries a fact — this row moves — so it stays; the
            // field-type glyph beside it does not. 2026-09-15.
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(Brand.ink4(dark))
            Text(Columns.label(column.name))
                .sans(Brand.Size.body)
                .foregroundStyle(column.visible ? Brand.ink(dark) : Brand.ink3(dark))
            Spacer()
            // The way into the column itself: its name, and — for a list
            // column — the list. Cadrage puts a page behind each column;
            // this is ours.
            Button {
                state.editingColumn = column.name
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.ink3(dark))
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Rename column")
            Button {
                guard let engine = state.engine else { return }
                state.replace(engine.column(column.name, visible: !column.visible))
            } label: {
                Image(systemName: column.visible ? "eye" : "eye.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(column.visible ? Brand.ink2(dark) : Brand.ink4(dark))
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(column.visible ? "Hide in every scene" : "Show in every scene")
            // **A column the project made can be thrown away, here.** His
            // report, 2026-08-22: *"I just see a hide feature — not delete."*
            // Deleting was two clicks deep, on the column's own page, and a
            // thing nobody finds is a thing that does not exist. A built-in
            // column has no bin because it cannot go — which also says, at a
            // glance, which of these are yours.
            if Columns.custom[column.name] != nil {
                Button { remove(column) } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.ink3(dark))
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete column")
            } else {
                // The space is held, so the eyes stay in one column down the
                // list rather than jumping where a bin is missing.
                Color.clear.frame(width: 24, height: 20)
            }
        }
        .padding(.vertical, 2)
    }
}


/// One column, close up: what it is called, and — when it is a list column —
/// every term the project has learned, with the two things a person actually
/// needs to do to a list they have been typing into for weeks: **fix a typo**
/// (renaming a term rewrites it on every shot that used it) and **take a term
/// out** (which clears it from the shots that had it).
///
/// Deleting the column itself is deliberately not here. Undo already husks an
/// accidental new column, and a real delete has to say what it will take with
/// it — the values on every shot in every scene — which is a design worth
/// doing properly rather than a button worth adding quickly.
private struct ColumnPage: View {
    @ObservedObject var state: ShellState
    let column: ViewModel.Column
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    private var dark: Bool { scheme == .dark }

    @State private var name = ""
    @State private var said = ""

    private var isList: Bool { Columns.isVocabulary(column.name) }

    var body: some View {
        Sheet(title: Columns.label(column.name), width: .narrow, height: 480, scrolls: false) {
            VStack(spacing: 0) {
                Field("Name") {
                    FieldText(placeholder: "Column Name", text: $name, onSubmit: rename)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

                Divider().overlay(Brand.rule(dark))

                if isList {
                    // **The same editor the project's settings use.** Two
                    // doors to one list — his ask — and one piece of code, so
                    // they cannot come to disagree about what the list is.
                    ListPage(state: state, field: column.name)
                } else {
                    VStack(spacing: 6) {
                        Spacer()
                        Text("No list on this column")
                            .sans(Brand.Size.body).foregroundStyle(Brand.ink3(dark))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        } leading: {
            if !said.isEmpty {
                Text(said).sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark))
            }
            // **Only a column the project made.** Shot Size is the app's
            // shape, not this film's.
            if Columns.custom[column.name] != nil {
                Button("Delete Column…") { remove() }
            }
        } trailing: {
            Button("Done") { rename(); dismiss() }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
        }
        .onAppear { name = Columns.label(column.name) }
    }

    private func remove() {
        let written = (state.view?.allRows ?? [])
            .filter { !($0.custom?[column.name] ?? []).isEmpty }
            .count
        let ask = NSAlert()
        ask.messageText = "Delete “\(Columns.label(column.name))”?"
        ask.informativeText = written == 0
            ? "Nothing is written in it."
            : (written == 1
               ? "1 shot has something written in it, and loses it."
               : "\(written) shots have something written in it, and lose it.")
        ask.alertStyle = .warning
        ask.addButton(withTitle: "Delete column")
        ask.addButton(withTitle: "Cancel")
        guard ask.runModal() == .alertFirstButtonReturn else { return }
        state.replace(state.engine?.deleteColumn(field: column.name))
        dismiss()
    }

    private func rename() {
        let label = name.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, label != Columns.label(column.name),
              let engine = state.engine else { return }
        state.replace(engine.renameColumn(field: column.name, label: label))
    }
}
