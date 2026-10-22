import SwiftUI

/// **The shape of the project** — which columns it has, what they are called,
/// what order they sit in, and which of them are showing.
///
/// Ref 253. This belonged to the Mac alone: the phone could read a column and
/// write into it, but not make one, rename one, move one or take one away. On a
/// scout that meant the one thing he could not do was the thing a scout turns
/// up — a field the project needs and does not have.
///
/// The order here is not decoration. It is the order of the Mac's table *and*
/// the order the shot's own page reads in, which is why dragging a row here
/// rearranges the page he was just looking at.
struct ColumnsView: View {
    @EnvironmentObject private var session: Session

    /// The shapes a person can pick. The engine also knows media and location;
    /// they join this list when the phone can draw them. The words are the
    /// Mac's own, in the phone's sentence case.
    private static let kinds: [(String, String)] = [
        ("text", "Text"),
        ("single", "Single Choice"),
        ("multi", "Multiple Choice"),
        ("check", "Checkmark"),
    ]

    @State private var name = ""
    @State private var kind = "single"
    @State private var renaming: Engine.Column?
    @State private var renamed = ""
    @State private var deleting: Engine.Column?

    var body: some View {
        List {
            Section {
                ForEach(session.columns) { column in
                    Row(column: column)
                        .swipeActions(edge: .trailing) {
                            // **Only a column the project made.** The engine
                            // refuses to delete a built-in, and offering a
                            // button that will be refused is worse than not
                            // offering one.
                            if column.kind != nil {
                                Button(role: .destructive) { deleting = column } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            Button { renaming = column; renamed = column.shown } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.indigo)
                        }
                }
                .onMove(perform: reorder)
            }

            // **The new column is made here rather than behind a button**, because
            // an alert on iOS holds text fields and buttons and nothing else —
            // and a column needs a shape as well as a name. Two sheets deep to
            // add a column is the tap count this app was built to avoid.
            Section("New Column") {
                TextField("Name", text: $name)
                Picker("Kind", selection: $kind) {
                    ForEach(Self.kinds, id: \.0) { kind, said in
                        Text(said).tag(kind)
                    }
                }
                Button("Add Column") {
                    session.addColumn(kind: kind, label: name)
                    name = ""
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // **Ready-made, the Mac's list** (`shared/ColumnTemplates.swift`):
            // a name and a shape in one tap, some with their list filled.
            ForEach(ColumnTemplates.groups, id: \.0) { group, readies in
                let offered = readies.filter { !session.hasColumn(named: $0.label) }
                if !offered.isEmpty {
                    Section("Ready-Made · \(group)") {
                        ForEach(offered, id: \.label) { ready in
                            Button { session.addColumn(ready) } label: {
                                HStack {
                                    Text(ready.label).foregroundStyle(.primary)
                                    Spacer()
                                    Text(said(ready.kind)).foregroundStyle(.secondary)
                                    Image(systemName: "plus.circle.fill")
                                }
                            }
                            .accessibilityIdentifier("ready." + ready.label)
                        }
                    }
                }
            }
        }
        .navigationTitle("Columns")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .alert("Rename \(renaming?.shown ?? "")", isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } }
        )) {
            TextField("Name", text: $renamed)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let column = renaming { session.renameColumn(column.name, to: renamed) }
                renaming = nil
            }
        } message: {
            Text("Keeps contents")
        }
        .confirmationDialog("Delete \(deleting?.shown ?? "")",
                            isPresented: Binding(get: { deleting != nil },
                                                 set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let column = deleting { session.deleteColumn(column.name) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            // What a delete will cost, which the copy law keeps a sentence for.
            Text("Deletes contents")
        }
    }

    private func said(_ kind: String) -> String {
        Self.kinds.first { $0.0 == kind }?.1 ?? kind.capitalized
    }

    /// **The whole order, not the move.** The engine is told what the order now
    /// is rather than which row went where, so a drag that SwiftUI and the
    /// engine would count differently cannot leave them disagreeing.
    private func reorder(_ from: IndexSet, _ to: Int) {
        var names = session.columns.map(\.name)
        names.move(fromOffsets: from, toOffset: to)
        session.setColumnOrder(names)
    }

    /// One column: what it is called, and whether it is on screen.
    private struct Row: View {
        @EnvironmentObject private var session: Session
        let column: Engine.Column

        var body: some View {
            Toggle(isOn: Binding(
                get: { column.visible },
                set: { session.showColumn(column.name, $0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(column.shown)
                    // Only a column the project made says what shape it is —
                    // a built-in's is known, and saying it would be noise on
                    // every row.
                    if let kind = column.kind, !kind.isEmpty {
                        Text(said(kind))
                            .font(.kitLabel)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        private func said(_ kind: String) -> String {
            ColumnsView.kinds.first { $0.0 == kind }?.1 ?? kind.capitalized
        }
    }
}
