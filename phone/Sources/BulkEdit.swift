import SwiftUI

/// **One value onto every picked shot.** Ref 253.
///
/// The Mac has had this since the beginning and the phone had nothing like it,
/// so putting the same lens on six shots meant opening six shots. What makes it
/// worth having is not the typing saved — it is that the engine writes the whole
/// selection in **one transaction**, so it is one thing to take back rather than
/// six. That is also why nothing here loops: looping would be six undo steps.
///
/// Two columns are deliberately not offered:
///
/// - **Storyboard**, because a picture is put on a shot rather than typed into
///   one, and putting the same frame on six shots is not a thing anybody means.
/// - **Shoot day and sequence**, because neither belongs to a shot. A day is
///   scheduled on the Mac's board; a sequence belongs to the scene, so writing
///   it across a selection would quietly move whole scenes that happen to have
///   a picked shot in them.
struct BulkField: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss

    let rows: [Engine.Row]
    var done: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(offered) { column in
                    NavigationLink(column.shown) {
                        Values(rows: rows, column: column, finish: finish)
                            .environmentObject(session)
                    }
                }
            }
            .navigationTitle(count)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var count: String {
        "\(rows.count) shot\(rows.count == 1 ? "" : "s")"
    }

    /// The columns a selection can be written into: what is on screen, less the
    /// three that are not a shot's own to give.
    private var offered: [Engine.Column] {
        session.columns.filter { column in
            column.visible && !["image", "struck", "day", "sequence"].contains(column.name)
        }
    }

    private func finish() {
        dismiss()
        done()
    }

    /// The values for one column, laid out the way the shot's own page lays
    /// them out — every answer the project has used, one tap each.
    private struct Values: View {
        @EnvironmentObject private var session: Session
        let rows: [Engine.Row]
        let column: Engine.Column
        var finish: () -> Void

        @State private var typed = ""

        var body: some View {
            Form {
                // What is already there, so it is plain whether this is a
                // change or a tidy-up. Two shots that disagree say so.
                Section {
                    Text(standing)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if column.shape == "text" {
                    Section {
                        TextField(column.shown, text: $typed, axis: .vertical)
                            .lineLimit(1...6)
                        Button("Set \(rows.count) Shot\(rows.count == 1 ? "" : "s")") {
                            session.set(rows, column.name, to: typed)
                            finish()
                        }
                        .disabled(typed.isEmpty)
                    }
                } else if column.name == "camera" {
                    Section {
                        if session.units.isEmpty {
                            Text("No cameras yet").foregroundStyle(.secondary)
                        }
                        ForEach(session.units) { unit in
                            Button {
                                session.set(rows, "camera", to: unit.id)
                                finish()
                            } label: {
                                Label(unit.label, systemImage: "camera")
                                    .foregroundStyle(unit.tint)
                            }
                        }
                    }
                } else {
                    Section {
                        if choices.isEmpty {
                            Text("Nothing in this list yet").foregroundStyle(.secondary)
                        }
                        ForEach(choices, id: \.self) { value in
                            Button(value) {
                                session.set(rows, column.name, to: value)
                                finish()
                            }
                        }
                    }
                    // **A value the project has not used yet.** Without this a
                    // column whose list is still empty had nothing to tap and
                    // no way to type — which is every column on the first day
                    // of a project, and exactly when a scout is standing there.
                    // Nothing where the list has been closed: offering a term
                    // the engine would then refuse is worse than not offering.
                    if column.locked != true {
                        Section {
                            TextField("New Value", text: $typed)
                            Button("Set \(rows.count) Shot\(rows.count == 1 ? "" : "s")") {
                                session.set(rows, column.name, to: typed)
                                finish()
                            }
                            .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }

                Section {
                    Button("Clear \(rows.count) Shot\(rows.count == 1 ? "" : "s")",
                           role: .destructive) {
                        session.clear(column.name, on: rows)
                        finish()
                    }
                }
            }
            .navigationTitle(column.shown)
            .navigationBarTitleDisplayMode(.inline)
        }

        private var choices: [String] {
            let known = session.vocabulary(column.name)
            let already = rows.flatMap { $0.cell(column.name) }
            return known + already.filter { !$0.isEmpty && !known.contains($0) }
        }

        /// What the picked shots say now — one value, or a count of how many
        /// different ones. A bulk edit that silently overwrote six different
        /// lenses with one would be the kind of loss nothing warns about.
        private var standing: String {
            let values = Set(rows.flatMap { $0.cell(column.name) }.filter { !$0.isEmpty })
            if values.isEmpty { return "Empty on all of them" }
            if values.count == 1 { return "All of them: \(values.first!)" }
            return "\(values.count) different values"
        }
    }
}
