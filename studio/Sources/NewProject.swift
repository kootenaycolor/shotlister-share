import AppKit
import SwiftUI

/// The first thing a new film asks — its name, whose it is, its frame, and
/// which of his projects it belongs to — and then where its scenes come from.
///
/// The one anatomy: title top-left, one column (a director and a producer are
/// not one fact), the frame in the sans with tabular numerals, the folder a
/// field that opens the picker. Continue disabled is the tint capsule at
/// reduced opacity.
struct NewProjectSheet: View {
    @ObservedObject var state: ShellState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    enum Step { case film, start }

    @State private var step: Step = .film
    @State private var title = ""
    @State private var director = ""
    @State private var producer = ""
    @State private var ratio = 2.39
    @State private var kind = "film"
    @State private var client = ""
    @State private var agency = ""
    @State private var linkAnswered = false
    @FocusState private var naming: Bool

    private var project: ViewModel.Project? { state.view?.project }

    var body: some View {
        Sheet(title: step == .film ? "New Project" : "Start With",
              width: .standard, height: 520, scrolls: step == .film) {
            switch step {
            case .film: film
            case .start: start
            }
        } leading: {
            if step == .start {
                Button("Back") { step = .film }
            }
        } trailing: {
            if step == .film {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                // **The one thing this screen will not let him skip.** A film
                // that never said which project it belongs to is matched to a
                // Notion row by its title, word for word, and the day either
                // is renamed every update stops with nothing said. So the
                // choice is made here, once, where he is already naming things.
                Button("Continue") { commit(); step = .start }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!linkAnswered)
            }
        }
        .onAppear {
            title = project?.title ?? ""
            director = project?.director ?? ""
            producer = project?.producer ?? ""
            ratio = project?.ratio ?? 2.39
            naming = true
            announce()
        }
    }

    // ---- the film -------------------------------------------------------

    private var film: some View {
        Group {
            field("Title", $title, focus: true)
            // **Kind.** Not *Mode* — the four things across the top bar are
            // the program's modes. A commercial changes what a scene needs (a
            // title, not a number), what leads, and what a sequence is called.
            Field("Kind") {
                Segmented(selection: $kind, items: [
                    .init(value: "film", title: "Film"),
                    .init(value: "commercial", title: "Commercial"),
                ], quiet: true)
                .fixedSize()
            }
            field("Director", $director)
            field("Producer", $producer)
            if kind == "commercial" {
                field("Client", $client)
                field("Agency", $agency)
            }
            Field("Aspect Ratio", width: 220) {
                FrameRatioMenu(current: ratio, choose: { ratio = $0 }) {
                    FieldFace(text: Ratios.title(ratio), dark: dark)
                }
            }
            GroupGap()
            ProjectLink(state: state, answered: $linkAnswered) { named in
                // A film linked to *Call Her Back* is called Call Her Back —
                // unless he has already typed something else, in which case
                // what he typed wins.
                let typed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if typed.isEmpty || typed == project?.title { title = named }
            }
        }
    }

    private func field(_ label: String, _ text: Binding<String>,
                       focus: Bool = false) -> some View {
        Field(label) {
            TextField("", text: text)
                .textFieldStyle(.plain)
                .sans(Brand.Size.body)
                .foregroundStyle(Brand.ink(dark))
                .focused($naming, equals: focus ? true : false)
                .onSubmit { if step == .film { step = .start } }
                .field(dark)
        }
    }

    // ---- where the scenes come from -------------------------------------

    private var start: some View {
        HStack(spacing: 12) {
            way("Import script…", loud: true) {
                commit()
                dismiss()
                ScriptImport.pick(state: state)
            }
            way("Add scene…") {
                commit()
                dismiss()
                state.addingScene = true
            }
            way("Nothing yet") {
                commit()
                dismiss()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A door, drawn as a card: words only — no glyph, his call of 2026-09-15.
    private func way(_ label: String, loud: Bool = false,
                     _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            Text(label).sans(Brand.Size.title, weight: loud ? .semibold : .regular)
                .foregroundStyle(loud ? Brand.accent(dark) : Brand.ink(dark))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
                .background {
                    RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
                        .fill(loud ? Brand.accentTint(dark) : .clear)
                }
                .overlay {
                    if !loud {
                        RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
                            .strokeBorder(Brand.rule2(dark), lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    // ---- writing it down ------------------------------------------------

    private func commit() {
        guard let engine = state.engine, let id = project?.id else { return }
        let wanted = title.trimmingCharacters(in: .whitespacesAndNewlines)
        state.replace(engine.set(shot: id, field: "title", value: wanted))
        // A film already taking its facts from the project record has them;
        // the engine would refuse these, and the console is where they change.
        let fromRecord = project?.factsFromRecord == true
        if !fromRecord {
            state.replace(engine.set(shot: id, field: "director",
                                     value: director.trimmingCharacters(in: .whitespaces)))
            state.replace(engine.set(shot: id, field: "producer",
                                     value: producer.trimmingCharacters(in: .whitespaces)))
        }
        if kind == "commercial" {
            state.replace(engine.setKind("commercial"))
            if !fromRecord {
                state.replace(engine.set(shot: id, field: "client",
                                         value: client.trimmingCharacters(in: .whitespaces)))
                state.replace(engine.set(shot: id, field: "agency",
                                         value: agency.trimmingCharacters(in: .whitespaces)))
            }
        }
        state.replace(engine.set(shot: id, field: "aspect_ratio",
                                 value: String(format: "%.4f", ratio)))
        state.renameFileToTitle()
        announce()
    }

    private func announce() {
        guard Launch.checking else { return }
        FileHandle.standardError.write(Data((
            "setup: step \(step == .film ? "film" : "start")"
            + "  title \"\(state.view?.project.title ?? "")\""
            + "  director \"\(state.view?.project.director ?? "")\""
            + String(format: "  ratio %.2f", state.view?.project.ratio ?? 0)
            + "  file \"\(state.projectPath?.deletingPathExtension().lastPathComponent ?? "")\""
            + "\n").utf8))
    }
}

// ------------------------------------------------- where this film lives

/// Which of his projects this film is, and where its Drive folder is. The
/// same two rows on the new-project sheet and in Settings, from one view, so
/// two ways of making the choice cannot disagree.
struct ProjectLink: View {
    @ObservedObject var state: ShellState
    var answered: Binding<Bool>? = nil
    var naming: ((String) -> Void)? = nil
    /// Whether to offer the Notion project row. Off for a project on the
    /// shared record (2026-10-16): the record already says which it is.
    var notion = true

    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    @State private var projects: [Console.Project] = []
    @State private var looking = false
    @State private var picked: String?

    private static let noneChosen = "\u{1}none"

    private var project: ViewModel.Project? { state.view?.project }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if notion, !projects.isEmpty {
                Field("Notion Project") {
                    Dropdown(selection: Binding(
                        get: { picked ?? project?.consolePage ?? "" },
                        set: { choose($0) }
                    ), items: items)
                }
            }

            // **The folder is a field that opens the picker** — the one field
            // shape, with "…" where a list would show its chevron.
            Field("Drive Folder") {
                HStack(spacing: 8) {
                    let path = project?.driveFolder ?? ""
                    Button { choose() } label: {
                        FieldFace(text: looking ? "Looking…"
                                        : (path.isEmpty ? "None" : Console.shortPath(path)),
                                  empty: looking || path.isEmpty,
                                  chevron: false, trailing: "…", dark: dark)
                    }
                    .buttonStyle(.plain)
                    .help(path.isEmpty ? "Pick the Google Drive folder for this project" : path)
                    if looking {
                        ProgressView().controlSize(.small)
                    }
                    if canFind, !looking {
                        Button { find() } label: { PlusLabel(text: "Find", dark: dark) }
                            .buttonStyle(.rowAction)
                    }
                    if !path.isEmpty {
                        Button("Clear") { Linking.setFolder("", state: state) }
                            .buttonStyle(.rowAction)
                    }
                }
            }
        }
        .task {
            projects = Console.projects()
            settle()
            // **`--setuppick <name|none>` picks for a checking run**, the same
            // way `--addscene` and `--settingsend` reach into their own
            // screens. The escape — saying a film is NOT one of his projects
            // — is the one answer that leaves the record looking exactly like
            // no answer at all. Unprovable by looking at the film afterwards;
            // so it is driven.
            if Launch.checking, answered != nil,
               let at = CommandLine.arguments.firstIndex(of: "--setuppick"),
               at + 1 < CommandLine.arguments.count {
                let wanted = CommandLine.arguments[at + 1]
                choose(wanted == "none" ? Self.noneChosen
                       : (projects.first { $0.name == wanted }?.pageId ?? ""))
            }
        }
    }

    private var canFind: Bool {
        !(project?.driveUrl ?? "").isEmpty
    }

    // ---- doing it -------------------------------------------------------

    private var items: [Dropdown<String>.Item] {
        let mine = projects.map {
            Dropdown<String>.Item($0.pageId,
                          $0.line.isEmpty ? $0.name : "\($0.name)   \($0.line)")
        }
        guard answered != nil else {
            return [Dropdown<String>.Item("", "Not linked")] + mine
        }
        return [Dropdown<String>.Item("", "Choose…")] + mine
            + [Dropdown<String>.Item(Self.noneChosen, "Not one of my projects")]
    }

    private func choose(_ id: String) {
        picked = id
        // Anything but the empty entry is a real answer — including saying
        // plainly that this film is not one of his projects.
        if !id.isEmpty { answered?.wrappedValue = true }
        report(answered?.wrappedValue ?? true)
        link(to: id == Self.noneChosen ? "" : id)
    }

    private func settle() {
        guard let answered else { return }
        if projects.isEmpty || !(project?.consolePage ?? "").isEmpty {
            answered.wrappedValue = true
        }
        report(answered.wrappedValue)
    }

    private func report(_ open: Bool) {
        guard answered != nil else { return }
        FileHandle.standardError.write(Data((
            "setup: \(projects.count) console projects, "
            + "continue \(open ? "open" : "held")\n").utf8))
    }

    private func link(to page: String) {
        let one = projects.first { $0.pageId == page }
        Linking.link(one, state: state)
        guard let one else { return }
        naming?(one.name)
        // Linking is the moment the folder is knowable, so that is when it is
        // looked for — rather than making him press a button whose answer was
        // already available.
        if (project?.driveFolder ?? "").isEmpty { find() }
    }

    private func find() {
        guard canFind else { return }
        looking = true
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Linking.findFolder(state: state)
            DispatchQueue.main.async {
                looking = false
                guard let found else {
                    state.say("That folder isn’t on this Mac yet.")
                    return
                }
                Linking.setFolder(found.path, state: state)
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Pick the Google Drive folder for this project"
        let start = project?.driveFolder ?? ""
        if !start.isEmpty { panel.directoryURL = URL(fileURLWithPath: start) }
        guard panel.runModal() == .OK, let picked = panel.url else { return }
        Linking.setFolder(picked.path, state: state)
    }
}
