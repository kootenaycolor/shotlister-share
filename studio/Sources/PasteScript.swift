import SwiftUI
import AppKit

/// **A script, pasted in.** A commercial's script is plain text — an audio
/// script, an AV table, a treatment, whatever the job sent — and nothing is
/// parsed out of it (his ruling, 2026-09-19 night). It goes onto the section
/// chosen here; a section that already has a script gets this added at the
/// end, never overwritten. Editing lives in Project Settings → Script.
struct PasteScriptSheet: View {
    @ObservedObject var state: ShellState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    private var dark: Bool { scheme == .dark }

    @State private var text = ""
    @State private var section = ""
    @State private var newSection = ""
    /// Plain or AV, for a script with nothing in it yet. Nil until he picks:
    /// a table (anything with a tab) reads as AV, anything else as plain.
    @State private var chosenAV: Bool?
    private static let new = "NEW"
    private var av: Bool { chosenAV ?? text.contains("\t") }

    private var sectionWord: String { state.view?.project.sequenceWord ?? "Section" }
    private var sectionItems: [Dropdown<String>.Item] {
        [Dropdown.Item("", "Film")]
            + (state.view?.sequences ?? []).map { Dropdown.Item($0.id, $0.title) }
            + [Dropdown.Item(Self.new, "New \(sectionWord)…")]
    }
    private var held: String {
        state.view?.scripts.first { $0.section == section }?.text ?? ""
    }

    var body: some View {
        Sheet(title: "Paste Script", width: .wide, height: 520, scrolls: false) {
            HStack(spacing: 0) {
                TextEditor(text: $text)
                    .font(.custom("Courier", size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Brand.menu(dark))
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Paste the script here").sans(Brand.Size.body)
                                .foregroundStyle(Brand.ink4(dark))
                                .padding(.leading, 16).padding(.top, 16)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(minWidth: 380)
                Divider().overlay(Brand.rule(dark))
                VStack(alignment: .leading, spacing: 6) {
                    Text(sectionWord).fieldLabel(dark)
                    Dropdown(selection: $section, items: sectionItems, width: 272)
                    if section == Self.new {
                        FieldText(placeholder: "\(sectionWord) Name", text: $newSection)
                            .frame(width: 272)
                    }
                    if section != Self.new, !held.isEmpty {
                        Text("Added after what is there").sans(Brand.Size.small)
                            .foregroundStyle(Brand.ink3(dark))
                    } else {
                        Text("Layout").fieldLabel(dark).padding(.top, 8)
                        Segmented(selection: Binding(get: { av }, set: { chosenAV = $0 }),
                                  items: [.init(value: false, title: "Plain"), .init(value: true, title: "AV")],
                                  quiet: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(width: 300)
                .background(Brand.surface2(dark))
            }
        } trailing: {
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Add") { add() }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.engine == nil
                          || (section == Self.new && newSection.trimmingCharacters(in: .whitespaces).isEmpty))
        }
        .onAppear {
            if text.isEmpty, let held = NSPasteboard.general.string(forType: .string),
               !held.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                text = held
            }
            if section.isEmpty, let mine = state.scene?.sequence, !mine.isEmpty { section = mine }
        }
    }

    private func add() {
        guard let engine = state.engine else { return }
        let edit = section == Self.new
            ? engine.setScript(text, section: nil, newSection: newSection.trimmingCharacters(in: .whitespaces),
                               append: true, av: av)
            : engine.setScript(text, section: section.isEmpty ? nil : section, append: true, av: av)
        state.replace(engine.view())
        if Launch.checking, let edit {
            FileHandle.standardError.write(Data(("script pasted: kept \(edit.kept) lost \(edit.lost)\n").utf8))
        }
        dismiss()
    }
}
