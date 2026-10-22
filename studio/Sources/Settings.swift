import SwiftUI

/// The project's own facts — what it is called, whose film it is, and the
/// shape of the frame.
///
/// These were readable everywhere and writable nowhere: the document page
/// prints "DIR. …  PROD. …" in its footer from fields nothing could set, and
/// a project took its name from the filename it was created with and kept it
/// forever. The ratio had exactly one control, tucked in the storyboard's
/// footer, which is a strange place to keep a fact about the whole film.
///
/// No new engine work: these are ordinary fields on the project record, and
/// they go through the same `set` every cell uses — so they undo, save and
/// sync like everything else.
struct ProjectSettingsSheet: View {
    @ObservedObject var state: ShellState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    private var dark: Bool { scheme == .dark }
    private var project: ViewModel.Project? { state.view?.project }

    @State private var title = ""
    @State private var director = ""
    @State private var producer = ""
    /// **What sort of film this is** — `film` or `commercial`. Written the
    /// moment it is switched, because it changes what every other screen
    /// draws; see the engine's `kind` module.
    @State private var kind = "film"
    @State private var client = ""
    @State private var agency = ""
    /// Which page of the settings is showing: the film's own facts, one of
    /// its lists, or its sequences.
    @State private var page: SettingsPage = .project


    var body: some View {
        // **The sheet says "Project Settings"**; the pane says which page.
        // The film's folder left the footer for the Project pane, where it is
        // a labelled value like the title and the frame. 2026-09-14.
        Sheet(title: "Project Settings", width: .wide, height: 520, scrolls: false) {
            HStack(spacing: 0) {
                rail
                Divider().overlay(Brand.rule(dark))
                VStack(spacing: 0) {
                    HStack {
                        Text(pageTitle(page)).sans(Brand.Size.title, weight: .semibold)
                            .foregroundStyle(Brand.ink(dark))
                        Spacer()
                        if state.view?.project.readOnly == true {
                            Text("Read Only. Made by a newer Studio.")
                                .sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, page.fromSpecSheet ? 2 : 8)
                    // **One status line for the whole Spec Sheet group.**
                    if page.fromSpecSheet {
                        SpecStatus(state: state)
                            .padding(.horizontal, 18).padding(.bottom, 10)
                    }

                    Group {
                        switch page {
                        case .project: general
                        case .folder: folderPage
                        case .aspect: AspectRatioPage(state: state)
                        case .columns: ColumnsPage(state: state, close: { dismiss() })
                        case .lists: ListsPage(state: state, fields: listFields.filter {
                            !SpecSheets.kitLists.contains($0) && $0 != "tags" })
                        case .script:
                            if state.view?.project.isCommercial == true {
                                BeatScriptsPage(state: state)
                            } else {
                                ScriptRevisionsPage(state: state)
                            }
                        case .specSheet: SpecSheetPage(state: state)
                        case .list("camera"): CameraPage(state: state)
                        case .list(let field): ListPage(state: state, field: field, openSpecSheet: { page = .specSheet })
                        case .sequences: SequencesPage(state: state)
                        case .mods: ModsPage(state: state)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } trailing: {
            Button("Done") { commitAll(); dismiss() }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
        }
        .onAppear {
            if let wanted = state.settingsPage { page = wanted; state.settingsPage = nil }
            title = project?.title ?? ""
            director = project?.director ?? ""
            producer = project?.producer ?? ""
            kind = project?.kind ?? "film"
            client = project?.client ?? ""
            agency = project?.agency ?? ""
            // `script` is not a list, but it is the other page anything might
            // want to open straight onto — the File menu's import and a
            // checking run both ask for it by name.
            if let wanted = state.settingsList {
                page = SettingsPage.named(wanted) ?? .list(wanted)
            }
            if Launch.checking, CommandLine.arguments.contains("--settingsend") { page = .folder }
        }
    }

    /// **Everything the project owns, down one side.** His ask: one place to
    /// adjust the lists behind every column, and the sequences too — reachable
    /// from a column's own page *and* from here, because the two are the same
    /// list and a person looking for "where do I fix my lens list" should find
    /// it under the film's settings.
    private var rail: some View {
        // **Three groups** (his approved mockup, 2026-10-16, "Studio settings,
        // sorted"): the project's own facts; everything that comes from the
        // spec sheet, together; and what only Studio keeps.
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Nothing in a rounded container may sit in the corner's radius.
                Spacer().frame(height: 10)
                railHead("Project")
                railItem(.project, icon: "info.circle")
                railItem(.folder, icon: "folder")
                railItem(.mods, icon: "puzzlepiece.extension")
                specGroup
                railHead("In Studio")
                railItem(.columns, icon: "tablecells", count: state.view?.columns.filter(\.visible).count)
                railItem(.list("tags"), icon: "tag", title: "Tags")
                railItem(.lists, icon: "list.bullet")
                railItem(.script, icon: "doc.text")
                railItem(.sequences, icon: "square.stack")
                Spacer().frame(height: 12)
            }
        }
        .frame(width: 214)
        .background(Brand.ground(dark))
    }

    private func railHead(_ words: String, dot: Color? = nil) -> some View {
        HStack(spacing: 5) {
            Text(words).fieldLabel(dark)
            if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
    }

    /// What the spec sheet feeds: the sheet's lists and the cameras.
    static let kitFields = SpecSheets.kitLists + ["camera"]

    /// **The Spec Sheet group**: everything that comes from the spec sheet,
    /// one group, a green dot while the lists follow it.
    private var specGroup: some View {
        let linked = SpecSheets.linked(state)
        let counts = Dictionary((state.engine?.lists() ?? []).map { ($0.field, $0.values.count) },
                                uniquingKeysWith: { a, _ in a })
        return VStack(alignment: .leading, spacing: 0) {
            railHead("Spec Sheet", dot: linked ? SpecStatus.green(dark) : nil)
            railItem(.aspect, icon: "rectangle.ratio.16.to.9", trailing: AspectRatioPage.face(project))
            railItem(.specSheet, icon: "video", title: "Camera")
            railItem(.list("lens"), icon: "camera.aperture", count: linked ? counts["lens"] : nil, title: "Lenses")
            railItem(.list("lens_filters"), icon: "circle.lefthalf.filled", count: linked ? counts["lens_filters"] : nil, title: "Filters")
            railItem(.list("modifiers"), icon: "light.max", count: linked ? counts["modifiers"] : nil, title: "Modifiers")
        }
    }

    /// Every list the project keeps — the built-in ones and the choice columns
    /// it made for itself, in the order the table has them.
    private var listFields: [String] {
        let columns = (state.view?.columns ?? [])
            .map(\.name)
            // **Camera is in the rail now** — his report, 2026-08-23:
            // *"there are still columns missing here — like Camera."*
            //
            // It was excluded for a real reason. A camera is not a term, it is
            // a *record* with a colour and a body, and the engine only knew how
            // to add one — so a Camera page could not have renamed or removed
            // anything, and the note here said it would arrive "when units get
            // one". They have one now (`unit name|colour|remove`), so it does.
            // It gets `CameraPage` rather than `ListPage`, because the two are
            // editing different kinds of thing.
            .filter { Columns.isVocabulary($0) }
        // Tags, POV and priority are lists too, whether or not their column is
        // on screen: a list is a fact about the project, not about the view.
        let always = ["tags", "priority", "pov", "modifiers", "lens_filters"]
        return columns + always.filter { !columns.contains($0) }
    }

    /// **No field-type glyph, and the chosen row is the quiet grey block** —
    /// the same one the scene sidebar uses. A list's chosen row is never the
    /// film's colour; that is the top bar's alone. The lock stays: it carries
    /// a fact.
    private func railItem(_ item: SettingsPage, icon: String? = nil, count: Int? = nil,
                          title: String? = nil, trailing: String? = nil) -> some View {
        let on = item == page
        return Button {
            page = item
        } label: {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 11))
                        .frame(width: 16)
                        .foregroundStyle(on ? Brand.ink(dark) : Brand.ink3(dark))
                }
                Text(title ?? pageTitle(item)).sans(Brand.Size.body, weight: on ? .semibold : .regular)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let count, count > 0 {
                    Text("\(count)").sans(Brand.Size.small).monospacedDigit()
                        .foregroundStyle(Brand.ink3(dark))
                }
                if let trailing, !trailing.isEmpty {
                    Text(trailing).sans(Brand.Size.small).monospacedDigit()
                        .foregroundStyle(Brand.ink3(dark)).lineLimit(1)
                }
                if case .list(let field) = item, locked.contains(field) {
                    Image(systemName: "lock.fill").font(.system(size: Brand.Icon.small))
                        .foregroundStyle(Brand.ink4(dark))
                }
            }
            .foregroundStyle(on ? Brand.ink(dark) : Brand.ink2(dark))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
                    .fill(on ? Brand.selectionQuiet(dark) : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
    }

    /// Which lists are closed, so the rail can show a padlock beside them.
    private var locked: Set<String> {
        Set((state.engine?.lists() ?? []).filter(\.locked).map(\.field))
    }

    /// **A check can send this pane to its foot.**
    ///
    /// Ref 366 said a sheet cannot be photographed at all; that is not true of
    /// this one — it comes out fine. But the sheet is a fixed 520 points and
    /// this pane scrolls, so everything below the fold was unphotographable
    /// anyway. Three pieces of work in a row have now ended with *"could not
    /// verify the control's appearance"*, which is three times too many.
    private var general: some View {
        ScrollViewReader { _ in
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // **A film linked to his project record shows its facts and
                // does not take them** (one-record plan, 2026-10-05). They are
                // changed in Projects Console, which keeps the one copy; the
                // film is handed them. A film that is not linked keeps its own,
                // typed here as before.
                if fromRecord {
                    recordFact("Title", project?.shownTitle ?? "")
                    // **Icon and color from the record too** (2026-10-16),
                    // changed in Console with the rest.
                    if onRecord { recordMark }
                } else {
                    field("Title", text: $title) { write("title", title) }
                }

                // **Kind.** Not *Mode* — the four things across the top bar
                // are the program's modes, and one word for two things is how
                // an afternoon goes missing. A commercial changes what a scene
                // needs (a title, not a number), what leads (title, Video and
                // Audio; the slugline folded away) and what a sequence is
                // called. Switching changes no data: a film can go there and
                // back and every scene is as it was.
                // **Kind follows Type** while the project's card is laid
                // on (stage 5 step 4): Commercial and Music Video are
                // commercials. Shown, not chosen; the Type is the console's.
                if project?.card == true {
                    recordFact("Kind", project?.isCommercial == true ? "Commercial" : "Film")
                } else {
                Field("Kind") {
                    Segmented(selection: $kind, items: [
                        .init(value: "film", title: "Film"),
                        .init(value: "commercial", title: "Commercial"),
                    ], quiet: true)
                    .fixedSize()
                    .onChange(of: kind) { _, now in
                        guard now != project?.kind else { return }
                        state.replace(state.engine?.setKind(now))
                    }
                }
                }

                if fromRecord {
                    recordFact("Director", project?.director ?? "")
                    recordFact("Producer", project?.producer ?? "")
                    if kind == "commercial" {
                        recordFact("Client", project?.client ?? "")
                        recordFact("Agency", project?.agency ?? "")
                    }
                    Button("Change in Console") {
                        Console.openProject(page: project?.consolePage ?? "")
                    }
                } else {
                    field("Director", text: $director) { write("director", director) }
                    field("Producer", text: $producer) { write("producer", producer) }
                    if kind == "commercial" {
                        field("Client", text: $client) { write("client", client) }
                        field("Agency", text: $agency) { write("agency", agency) }
                    }
                }

                // **Aspect Ratio and Guides moved to Settings ▸ Aspect Ratio**
                // (⌘,, 2026-10-15); the storyboard's ratio pill still picks it.

                // **The film's icon and colour**, only for a Studio-only
                // film; a project on the record shows the record's, above.
                if !onRecord {
                    GroupGap()
                    FilmsMark(state: state)
                }

                Spacer(minLength: 0)
                    .id("foot")
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        }
    }

    /// **Folder** (2026-10-16 mockup): where the film is, its Drive folder,
    /// and the spreadsheet it keeps current.
    private var folderPage: some View {
        ScrollViewReader { pane in
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Where the file actually is — the one question a person asks
                // of a settings panel that nothing else answers. A labelled
                // value here, not small print in the footer.
                if let path = state.projectPath {
                    Field("Folder") {
                        Text(path.deletingLastPathComponent().path)
                            .sans(Brand.Size.small)
                            .foregroundStyle(Brand.ink2(dark))
                            .lineLimit(1)
                            .truncationMode(.head)
                            .help(path.path)
                    }
                }

                GroupGap()
                // The same two rows the setup screen shows, from the same
                // view — his ask: the Drive folder is a choice that has to be
                // available here too, and two ways of making it would be two
                // answers waiting to disagree.
                // **No Notion row for a project on the shared record**
                // (2026-10-16): the record is which project this is, so only
                // the Drive folder is left to choose.
                ProjectLink(state: state, notion: !onRecord)

                // **The workbook this film can keep current** — SL-375, and
                // his follow-up, 2026-08-27: where it lives and whether it
                // updates itself are two separate questions, both of which
                // belong here rather than behind a save-panel checkbox. Shown
                // always, not only once linked — choosing to start is as much
                // this screen's job as everything after.
                GroupGap()
                linkedWorkbook

                Spacer(minLength: 0)
                    .id("foot")
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            guard Launch.checking, CommandLine.arguments.contains("--settingsend") else { return }
            // **One hop after the first draw.** The pane has no scrollable
            // height until it has been laid out, and scrolling to a foot that
            // is not there yet does nothing at all — silently, which is exactly
            // the shape of the `--scroll` bug that went unnoticed for weeks.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                pane.scrollTo("foot", anchor: .bottom)
            }
        }
        }
    }

    private var linkedWorkbook: some View {
        let path = project?.excelPath ?? ""
        return VStack(alignment: .leading, spacing: 6) {
            // **Not "(Excel)" any more.** A heading naming one of the two
            // programs, directly above a control for choosing between them,
            // says the file is an Excel file — which is the exact thing his
            // correction of 2026-09-04 was about. It is one `.xlsx` laid out
            // for one program or the other.
            Text("Spreadsheet").fieldLabel(dark)
            if path.isEmpty {
                HStack(spacing: 8) {
                    Text("None").sans(Brand.Size.body).foregroundStyle(Brand.ink3(dark))
                    Spacer(minLength: 6)
                    Button("Choose…") { chooseWorkbook() }
                }
            } else {
                HStack(spacing: 8) {
                    Text((path as NSString).lastPathComponent)
                        .sans(Brand.Size.body).foregroundStyle(Brand.ink(dark))
                        .lineLimit(1).truncationMode(.middle)
                        .help(path)
                    Spacer(minLength: 6)
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                    .buttonStyle(.rowAction)
                    Button("Choose…") { chooseWorkbook() }
                        .buttonStyle(.rowAction)
                    Button("Clear") {
                        Exporting.link("", state: state)
                        Exporting.setAutoUpdate(false, state: state)
                    }
                    .buttonStyle(.rowAction)
                }
                Text((path as NSString).deletingLastPathComponent)
                    .sans(Brand.Size.tiny).foregroundStyle(Brand.ink4(dark))
                    .lineLimit(1).truncationMode(.head)
                Toggle("Update automatically", isOn: Binding(
                    get: { Exporting.autoUpdateEnabled(for: project) },
                    set: { Exporting.setAutoUpdate($0, state: state) }
                ))
                .toggleStyle(.checkbox).sans(11)
                // **One file, laid out for one program or the other.** His
                // correction, 2026-09-04: the file does not change, the frames
                // do. Captioned like FRAME and PROJECT above it rather than
                // with an inline label, so the pane reads as one thing.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Format For").fieldLabel(dark)
                    Dropdown(selection: Binding(
                        get: { Exporting.frameStyle(for: project) },
                        set: { Exporting.setFrameStyle($0, state: state) }
                    ), items: FrameStyle.choices, width: 220)
                    // The one sentence that earns its place: it says the file is
                    // the same either way, and then the only thing that is not.
                    Text(Exporting.frameStyle(for: project).difference)
                        .sans(10).foregroundStyle(Brand.ink4(dark))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 6)
                Button("Export Now") { Exporting.exportLinkedWorkbookNow(state: state) }
            }
        }
    }

    /// Pick where the workbook lives, write it once so the location is never
    /// a promise about a file that does not exist yet, and turn the switch
    /// on — choosing a location is the moment he means to start following it.
    private func chooseWorkbook() {
        guard let engine = state.engine else { return }
        let panel = NSSavePanel()
        panel.title = "Spreadsheet"
        let title = project?.shownTitle ?? ""
        panel.nameFieldStringValue = title.isEmpty ? "Shot List.xlsx" : "\(title) – Shot List.xlsx"
        let folder = project?.driveFolder ?? ""
        if let live = Exporting.liveSheetDirectory(driveFolder: folder) {
            // The always-updating sheet gets its own folder, apart from his own spreadsheets.
            try? FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
            panel.directoryURL = live
        } else if !folder.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: folder, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard engine.exportExcel(path: url.path,
                                 frames: Exporting.frameStyle(for: project)) != nil else {
            state.say("Could not save the shot list")
            return
        }
        Exporting.link(url.path, state: state)
        Exporting.setAutoUpdate(true, state: state)
    }

    /// Whether the project record owns this film's facts.
    private var fromRecord: Bool { project?.factsFromRecord == true }

    /// Whether the shared project record's card is laid on this film (stage 5):
    /// its title, icon and color are the record's.
    private var onRecord: Bool { project?.card == true }

    /// **The record's icon, in its color**, shown and not taken. A mark set
    /// by hand in Studio before the record still wins over the card, so it
    /// can be put back to the record's from here.
    private var recordMark: some View {
        Field("Icon") {
            HStack(spacing: 8) {
                if let mark = project?.mark {
                    FilmIcon(mark: mark, size: 18)
                    Text(Marks.hues.first { $0.hex.uppercased() == mark.colour.uppercased() }?.name ?? mark.colour)
                        .sans(Brand.Size.body).foregroundStyle(Brand.ink(dark))
                } else {
                    Text("None").sans(Brand.Size.body).foregroundStyle(Brand.ink3(dark))
                }
                Spacer(minLength: 0)
                if project?.mark != nil, Marks.source(project?.markSource ?? "") == .hand {
                    Button("Use Record's") { state.clearTheMark() }
                        .buttonStyle(.rowAction)
                }
            }
        }
    }

    /// **One of the record's facts, shown and not taken.** Selectable, so a
    /// name can still be copied out.
    private func recordFact(_ label: String, _ value: String) -> some View {
        Field(label) {
            Text(value.isEmpty ? "None" : value)
                .sans(Brand.Size.body)
                .foregroundStyle(value.isEmpty ? Brand.ink3(dark) : Brand.ink(dark))
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func field(_ label: String, text: Binding<String>,
                       commit: @escaping () -> Void) -> some View {
        Field(label) {
            FieldText(placeholder: "", text: text, onSubmit: commit)
        }
    }

    /// A page's name, as this film says it — a commercial's sequences are
    /// Sections.
    private func pageTitle(_ page: SettingsPage) -> String {
        if case .sequences = page { return project?.sequencesWord ?? "Sequences" }
        return page.title
    }

    private func commitAll() {
        write("title", title)
        write("director", director)
        write("producer", producer)
        write("client", client)
        write("agency", agency)
    }

    /// Straight to the project record, through the same door a cell uses.
    private func write(_ field: String, _ value: String) {
        guard let engine = state.engine, let id = project?.id else { return }
        // The record's facts are the console's to change — the engine
        // refuses them too; this keeps Done from asking.
        if fromRecord, ["director", "producer", "client", "agency"].contains(field) { return }
        let held: String
        switch field {
        case "title": held = project?.title ?? ""
        case "director": held = project?.director ?? ""
        case "producer": held = project?.producer ?? ""
        case "client": held = project?.client ?? ""
        case "agency": held = project?.agency ?? ""
        default: held = ""
        }
        if field != "aspect_ratio", value.trimmingCharacters(in: .whitespaces) == held { return }
        state.replace(engine.set(shot: id, field: field,
                                 value: value.trimmingCharacters(in: .whitespaces)))
    }
}

// ------------------------------------------------------------------ pages

/// Which page of the project's settings is showing.
enum SettingsPage: Hashable {
    case project
    /// Where the film is, its Drive folder, its spreadsheet.
    case folder
    /// The spec sheet's aspect ratios and the one Studio draws at.
    case aspect
    /// The shot list's columns.
    case columns
    /// Every other list, one at a time.
    case lists
    /// Every draft the project has taken in. Cadrage keeps its own beside the
    /// project's facts, and it is the right place: a script is a fact about
    /// the film, not a thing you did one afternoon.
    case script
    /// The Camera Spec Sheet, each shoot's (Ref 1627) — `SpecSheet.swift`.
    case specSheet
    case list(String)
    case sequences
    /// The shelf's mods, each switched for this project (Mods.swift).
    case mods

    /// A page by the name a door asks for it (`--settings <name>`, a
    /// settings button): nil for a list's own field name.
    static func named(_ name: String) -> SettingsPage? {
        switch name {
        case "details", "project": return .project
        case "folder": return .folder
        case "aspect": return .aspect
        case "columns": return .columns
        case "lists": return .lists
        case "script": return .script
        case "specsheet", "camera-sheet": return .specSheet
        case "sequences": return .sequences
        case "mods": return .mods
        default: return nil
        }
    }

    /// A page in the Spec Sheet group, which wears its one status line.
    var fromSpecSheet: Bool {
        switch self {
        case .aspect, .specSheet: return true
        case .list(let field): return SpecSheets.kitLists.contains(field)
        default: return false
        }
    }

    var title: String {
        switch self {
        case .project: return "Details"
        case .folder: return "Folder"
        case .aspect: return "Aspect Ratio"
        case .columns: return "Columns"
        case .lists: return "Lists"
        case .script: return "Script"
        case .specSheet: return "Camera"
        case .list("lens"): return "Lenses"
        case .list("lens_filters"): return "Filters"
        case .list("modifiers"): return "Modifiers"
        case .list(let field): return Columns.label(field)
        case .sequences: return "Sequences"
        case .mods: return "Mods"
        }
    }
}

/// **One list, close up** — and the lock.
///
/// The two things a person actually needs to do to a list they have been
/// typing into for weeks: fix a typo (renaming a term rewrites it on every
/// shot that used it) and take a term out (which clears it from the shots that
/// had it). Plus the two his ask added: put a term on the list deliberately,
/// rather than by typing it into a cell — and **close the list** so nothing
/// else can get on it by accident.
/// Used from two doors, deliberately — his ask: *"you can adjust it in the
/// list but you could also adjust in project settings"*. One editor, so the
/// two can never disagree about what a list is.
struct ListPage: View {
    @ObservedObject var state: ShellState
    let field: String
    /// Kit lists' Open Spec Sheet, where the page is in Project Settings.
    var openSpecSheet: () -> Void = {}
    @ObservedObject private var sheets = SpecSheets.shared
    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }

    @State private var terms: [ListModel.Entry] = []
    @State private var locked = false
    @State private var renaming: String?
    @State private var renamed = ""
    @State private var adding = ""
    @State private var said = ""

    /// **A list the spec sheet feeds** (Kit Links, 2026-10-14): lenses,
    /// modifiers, filters.
    private var isKit: Bool { SpecSheets.kitLists.contains(field) }
    /// Fed and following: the sheet is its one home, so the lock, adding and
    /// taking off go through the sheet.
    private var fromSheet: Bool { isKit && SpecSheets.linked(state) }
    private var kit: [ViewModel.KitShoot] { state.view?.project.kit ?? [] }
    private var noun: String { field == "lens" ? "Lens" : field == "modifiers" ? "Modifier" : "Filter" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // A Spec Sheet list's head is the group's one status line, above.
            if !fromSheet {
            HStack(spacing: 8) {
                Toggle(isOn: Binding(get: { locked }, set: { on in
                    locked = on
                    state.engine?.lockList(field: field, on: on)
                    state.replace(state.engine?.view())
                    said = on
                        ? "Locked"
                        : "Open"
                })) {
                    HStack(spacing: 6) {
                        Image(systemName: locked ? "lock.fill" : "lock.open")
                            .font(.system(size: 10))
                        Text("Locked").sans(13, weight: .medium)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .foregroundStyle(Brand.ink2(dark))
                Text(locked
                     ? "Only these terms"
                     : "New terms are added")
                    .sans(11).foregroundStyle(Brand.ink4(dark))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            }

            Divider().overlay(Brand.rule(dark))

            if terms.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Text("Nothing on the list")
                        .sans(13).foregroundStyle(Brand.ink3(dark))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(terms) { term in
                            row(term)
                            Divider().overlay(Brand.ruleFaint(dark))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                }
            }

            Divider().overlay(Brand.rule(dark))

            HStack(spacing: 8) {
                if fromSheet {
                    // **One home** — a new lens goes on the sheet, and the
                    // list follows it there.
                    FieldText(placeholder: "Add \(noun) to Sheet…", text: $adding, onSubmit: addToSheet)
                        .frame(width: 220)
                    Button("Add to Sheet", action: addToSheet)
                        .disabled(adding.trimmingCharacters(in: .whitespaces).isEmpty || sheets.busy)
                } else {
                FieldText(placeholder: locked ? "This list is locked" : "Add a term…",
                          text: $adding, onSubmit: add)
                    .frame(width: 200)
                    .disabled(locked)
                Button("Add", action: add)
                    .disabled(locked || adding.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Spacer(minLength: 0)
                Text(said).sans(11).foregroundStyle(Brand.ink3(dark))
                    .lineLimit(1)
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
        }
        .onAppear {
            reload()
            if isKit && SpecSheets.linked(state) { sheets.refresh(state) }
        }
        .onChange(of: state.view?.project.kit) { _, _ in reload() }
        .onChange(of: field) { _, _ in
            renaming = nil
            adding = ""
            said = ""
            reload()
        }
    }

    private func row(_ term: ListModel.Entry) -> some View {
        HStack(spacing: 8) {
            if renaming == term.value {
                FieldText(placeholder: "", text: $renamed)
                    .onSubmit { finishRename(term.value) }
                Button("Save") { finishRename(term.value) }
                    .buttonStyle(.rowAction)
                Button("Cancel") { renaming = nil }
                    .buttonStyle(.rowAction)
            } else {
                let off = fromSheet && !SpecSheets.onSheet(field, term.value, kit: kit)
                let amber = Brand.data(KitLinks.amber, dark)
                Chip(text: term.value,
                     colour: off ? amber : (isKit ? Brand.data(SpecSheets.ink(field), dark)
                                                  : Columns.chipColour(field, term.value, state: state, dark: dark)))
                if off { Chip(text: "Not on Sheet", colour: amber) }
                // What it would cost to take this one away, said before you do.
                Text(term.used == 0
                     ? "on no shots"
                     : "on \(term.used) shot\(term.used == 1 ? "" : "s")")
                    .sans(11).foregroundStyle(Brand.ink4(dark))
                Spacer(minLength: 0)
                if off {
                    Button("Add to Sheet") {
                        sheets.addToLead(field: field, name: term.value, state: state)
                    }
                    .buttonStyle(.rowAction)
                    .disabled(sheets.busy)
                }
                // On the sheet and following it, a term is the sheet's:
                // renamed or taken off there, never here.
                if !fromSheet || off {
                Button {
                    renaming = term.value
                    renamed = term.value
                } label: {
                    Image(systemName: "pencil").font(.system(size: 11))
                        .foregroundStyle(Brand.ink3(dark))
                        .frame(width: 22, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Rename everywhere")
                }
                // **Recolour** — Ref 55. Beside rename, because Cadrage's menu
                // on a term offers the two together and they are the two things
                // you can do to a term without touching a single shot.
                Menu {
                    Button("Automatic") {
                        state.colourTerm(field: field, value: term.value, hex: "")
                        reload()
                    }
                    Divider()
                    ForEach(Array(Brand.chipInks.enumerated()), id: \.offset) { at, hex in
                        let current = Brand.termInks[Brand.termKey(field, term.value)]?
                            .uppercased().hasSuffix(hex) == true
                        Button(Swatches.inkNames[at] + (current ? "  ✓" : "")) {
                            state.colourTerm(field: field, value: term.value, hex: hex)
                            reload()
                        }
                    }
                } label: {
                    Image(systemName: "paintpalette").font(.system(size: 11))
                        .foregroundStyle(Brand.ink3(dark))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                // **A `.borderlessButton` menu throws away everything but its
                // label's words** — its background *and* its size — so the
                // frame goes here, on the menu, outside the label. Three faults
                // have come from learning that the other way round.
                .frame(width: 22, height: 20)
                .help("Color")
                if !fromSheet || off {
                Button {
                    remove(term.value)
                } label: {
                    Image(systemName: "minus.circle").font(.system(size: 11))
                        .foregroundStyle(Brand.ink3(dark))
                        .frame(width: 22, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete from the list")
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func reload() {
        let all = state.engine?.lists() ?? []
        let mine = all.first { $0.field == field }
        terms = mine?.values ?? []
        locked = mine?.locked ?? false
        // A column the project made for itself is not one of the engine's
        // eight named lists, so its terms come from where the pickers read
        // them — one list either way, just two doors to it.
        if mine == nil {
            terms = Columns.options(field, state: state)
                .map { ListModel.Entry(value: $0, used: 0) }
        }
    }

    private func add() {
        let next = adding.trimmingCharacters(in: .whitespaces)
        guard !next.isEmpty, let engine = state.engine else { return }
        engine.addValue(field: field, value: next)
        state.replace(engine.view())
        adding = ""
        said = "Added"
        reload()
    }

    private func addToSheet() {
        sheets.addToLead(field: field, name: adding, state: state)
        adding = ""
    }

    private func finishRename(_ term: String) {
        let next = renamed.trimmingCharacters(in: .whitespaces)
        renaming = nil
        guard !next.isEmpty, next != term, let engine = state.engine else { return }
        let changed = engine.renameValue(field: field, from: term, to: next)
        state.replace(engine.view())
        said = changed == 1 ? "Renamed on 1 shot" : "Renamed on \(changed) shots"
        reload()
    }

    private func remove(_ term: String) {
        guard let engine = state.engine else { return }
        let changed = engine.removeValue(field: field, value: term)
        state.replace(engine.view())
        said = changed == 0
            ? "Removed"
            : (changed == 1 ? "Cleared from 1 shot" : "Cleared from \(changed) shots")
        reload()
    }
}

/// **The cameras** — the one list in this rail whose entries are records.
///
/// It looks like `ListPage` on purpose and is not one underneath. A term is a
/// word, and renaming it rewrites every shot that ever typed it; a camera is a
/// record with a colour, and a shot points *at* it — so renaming is one write
/// and every cell follows by itself. Removing is the same bargain everything
/// else here strikes: the camera goes, the shots keep everything of their own.
///
/// **No lock switch.** Closing a list stops a stray word teaching the project.
/// A camera cannot be created by typing a stray word — it is born by name and
/// colour — so there is nothing here for a lock to stop.
struct CameraPage: View {
    @ObservedObject var state: ShellState
    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }

    @State private var renaming: String?
    @State private var renamed = ""
    @State private var adding = ""
    @State private var said = ""
    /// The camera whose New Sensor form is open.
    @State private var sensorFor: String?

    private var cameras: [ViewModel.Unit] { state.view?.units ?? [] }

    /// How many shots name this camera — counted off the shots themselves
    /// rather than asked of the engine, because a shot already carries the unit
    /// it points at and a second door to the same number is a second door that
    /// can disagree.
    private func uses(_ unit: ViewModel.Unit) -> Int {
        (state.view?.allRows ?? []).filter { $0.unit?.id == unit.id }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if cameras.isEmpty {
                EmptyState(title: "No cameras yet")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(cameras) { unit in
                            row(unit)
                            Divider().overlay(Brand.rule(dark))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                }
            }

            Divider().overlay(Brand.rule(dark))
            HStack(spacing: 8) {
                FieldText(placeholder: "Add a camera…", text: $adding, onSubmit: add)
                    .frame(width: 220)
                Button("Add", action: add)
                    .disabled(adding.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer(minLength: 0)
                Text(said).sans(11).foregroundStyle(Brand.ink3(dark))
                    .lineLimit(1)
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
        }
    }

    private func row(_ unit: ViewModel.Unit) -> some View {
        HStack(spacing: 8) {
            if renaming == unit.id {
                FieldText(placeholder: "", text: $renamed)
                    .onSubmit { finishRename(unit) }
                Button("Save") { finishRename(unit) }
                    .buttonStyle(.rowAction)
                Button("Cancel") { renaming = nil }
                    .buttonStyle(.rowAction)
            } else {
                Chip(text: unit.label,
                     colour: unit.colour.isEmpty ? nil : Brand.hex(unit.colour))
                let count = uses(unit)
                // What it would cost to take this one away, said before you do.
                Text(count == 0
                     ? "on no shots"
                     : "on \(count) shot\(count == 1 ? "" : "s")")
                    .sans(11).foregroundStyle(Brand.ink4(dark))
                Spacer(minLength: 0)
                sensorMenu(unit)
                // **The colours are the palette the table already uses**, so a
                // camera cannot be given one the chips cannot draw.
                Menu {
                    ForEach(Array(Columns.palette.enumerated()), id: \.offset) { at, hex in
                        Button(Columns.paletteNames[at]) { recolour(unit, hex) }
                    }
                } label: {
                    Circle()
                        .fill(unit.colour.isEmpty
                              ? Brand.ink4(dark) : Brand.hex(unit.colour))
                        .frame(width: 11, height: 11)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Color")
                Button {
                    renaming = unit.id
                    renamed = unit.label
                } label: {
                    Image(systemName: "pencil").font(.system(size: 11))
                        .foregroundStyle(Brand.ink3(dark))
                        .frame(width: 22, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Rename everywhere")
                Button {
                    remove(unit)
                } label: {
                    Image(systemName: "minus.circle").font(.system(size: 11))
                        .foregroundStyle(Brand.ink3(dark))
                        .frame(width: 22, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete this camera")
            }
        }
        .padding(.vertical, 6)
    }

    private func add() {
        let next = adding.trimmingCharacters(in: .whitespaces)
        guard !next.isEmpty, let engine = state.engine else { return }
        // Round the palette in turn, the way a new camera born in a cell does,
        // so two cameras never arrive wearing one colour.
        let colour = Columns.palette[cameras.count % Columns.palette.count]
        state.replace(engine.addUnit(label: next, colour: colour))
        adding = ""
        said = "Added"
    }

    /// **The sensor this camera reads** — typed by him, kept on the camera,
    /// and remembered on this Mac as a preset for the next film. Every shot
    /// on the camera, and its cone on a plan, reads it (his design,
    /// 2026-10-01).
    @ViewBuilder
    private func sensorMenu(_ unit: ViewModel.Unit) -> some View {
        // **The spec sheet's sensor mode** (piece E): shown, never typed.
        if state.view?.project.sensorsFromSheet == true {
            Text(unit.sensorText ?? "No Sensor").sans(11)
                .foregroundStyle(unit.sensorText == nil ? Brand.ink4(dark) : Brand.ink2(dark))
                .lineLimit(1)
                .fixedSize()
                .help(unit.sensor_sheet == true ? "From Spec Sheet" : "Set in Spec Sheet")
        } else {
            typedSensorMenu(unit)
        }
    }

    private func typedSensorMenu(_ unit: ViewModel.Unit) -> some View {
        Menu {
            let presets = SensorPresets.all()
            if !presets.isEmpty {
                Section("Presets") {
                    ForEach(presets) { p in
                        Button("\(p.name)  \(p.size)") { setSensor(unit, p.name, p.w, p.h) }
                    }
                }
            }
            Button("New Sensor…") { sensorFor = unit.id }
            if unit.sensorText != nil {
                Divider()
                Button("No Sensor") { setSensor(unit, "", 0, 0) }
            }
            if !presets.isEmpty {
                Menu("Remove Preset") {
                    ForEach(presets) { p in
                        Button(p.name) { SensorPresets.forget(p.id); said = "Removed" }
                    }
                }
            }
        } label: {
            Text(unit.sensorText ?? "No Sensor").sans(11)
                .foregroundStyle(unit.sensorText == nil ? Brand.ink4(dark) : Brand.ink2(dark))
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sensor")
        .popover(isPresented: Binding(get: { sensorFor == unit.id }, set: { if !$0 { sensorFor = nil } }),
                 arrowEdge: .bottom) {
            NewSensorForm(save: { name, w, h in
                SensorPresets.keep(DiagramFilmSensor(id: SensorPresets.id(for: name), name: name, w: w, h: h))
                setSensor(unit, name, w, h)
                sensorFor = nil
            }, cancel: { sensorFor = nil })
        }
    }

    private func setSensor(_ unit: ViewModel.Unit, _ name: String, _ w: Double, _ h: Double) {
        guard let engine = state.engine else { return }
        state.replace(engine.setUnitSensor(id: unit.id, name: name, w: w, h: h))
        said = w > 0 ? "Sensor set" : "Sensor cleared"
    }

    private func finishRename(_ unit: ViewModel.Unit) {
        let next = renamed.trimmingCharacters(in: .whitespaces)
        renaming = nil
        guard !next.isEmpty, next != unit.label, let engine = state.engine else { return }
        state.replace(engine.renameUnit(id: unit.id, label: next))
        // No count: renaming a camera touches no shot at all. Every cell that
        // names it is reading the record, so they all just say the new word.
        said = "Renamed"
    }

    private func recolour(_ unit: ViewModel.Unit, _ hex: String) {
        guard let engine = state.engine else { return }
        state.replace(engine.recolourUnit(id: unit.id, colour: hex))
    }

    private func remove(_ unit: ViewModel.Unit) {
        guard let engine = state.engine else { return }
        let count = uses(unit)
        state.replace(engine.removeUnit(id: unit.id))
        said = count == 0
            ? "Taken away — no shot was using it"
            : (count == 1 ? "Cleared from 1 shot" : "Cleared from \(count) shots")
    }
}

/// The project's sequences: the one grouping the script does not hand out.
private struct SequencesPage: View {
    @ObservedObject var state: ShellState
    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }
    private var sequences: [ViewModel.Sequence] { state.view?.sequences ?? [] }

    @State private var making = ""
    @State private var renaming: String?
    @State private var renamed = ""

    /// How many scenes are standing in each one — the same "what would this
    /// cost" the term list shows.
    private func scenes(in sequence: String) -> Int {
        (state.view?.scenes ?? []).filter { $0.sequence == sequence }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if sequences.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Text(state.view?.project.isCommercial == true ? "No sections yet" : "No sequences yet")
                        .sans(13).foregroundStyle(Brand.ink3(dark))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(sequences) { sequence in
                            row(sequence)
                            Divider().overlay(Brand.ruleFaint(dark))
                        }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 6)
                }
            }

            Divider().overlay(Brand.rule(dark))

            HStack(spacing: 8) {
                FieldText(placeholder: "New sequence…", text: $making, onSubmit: make)
                    .frame(width: 220)
                Button("Add", action: make)
                    .disabled(making.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
        }
    }

    private func row(_ sequence: ViewModel.Sequence) -> some View {
        HStack(spacing: 8) {
            // **The dot is the colour menu** — the same eight a section is
            // born with, chosen the way a camera's is. His ask, 2026-09-19:
            // "i also want to be able to choose a sections color".
            Menu {
                ForEach(Array(Brand.chipInks.enumerated()), id: \.offset) { at, hex in
                    Button(Swatches.inkNames[at] + (sequence.colour.uppercased().hasSuffix(hex) ? "  ✓" : "")) {
                        state.colourSection(sequence, hex: hex)
                    }
                }
            } label: {
                Circle()
                    .fill(sequence.colour.isEmpty
                          ? Brand.ink4(dark) : Brand.hex(sequence.colour))
                    .frame(width: 11, height: 11)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Color")
            if renaming == sequence.id {
                FieldText(placeholder: "", text: $renamed)
                    .onSubmit { finishRename(sequence) }
                Button("Save") { finishRename(sequence) }
                    .buttonStyle(.rowAction)
                Button("Cancel") { renaming = nil }
                    .buttonStyle(.rowAction)
            } else {
                Text(sequence.title).sans(13, weight: .medium)
                    .foregroundStyle(Brand.ink(dark))
                let count = scenes(in: sequence.id)
                Text(count == 0 ? "no scenes" : "\(count) scene\(count == 1 ? "" : "s")")
                    .sans(11).foregroundStyle(Brand.ink4(dark))
                Spacer(minLength: 0)
                Button {
                    renaming = sequence.id
                    renamed = sequence.title
                } label: {
                    Image(systemName: "pencil").font(.system(size: 11))
                        .foregroundStyle(Brand.ink3(dark))
                        .frame(width: 22, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Rename")
                Button {
                    state.askToDeleteSection(sequence)
                } label: {
                    Image(systemName: "trash").font(.system(size: 11))
                        .foregroundStyle(Brand.ink3(dark))
                        .frame(width: 22, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
        }
        .padding(.vertical, 6)
    }

    private func make() {
        let title = making.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, let engine = state.engine else { return }
        state.replace(engine.addSequence(title: title))
        making = ""
    }

    private func finishRename(_ sequence: ViewModel.Sequence) {
        let next = renamed.trimmingCharacters(in: .whitespaces)
        renaming = nil
        guard !next.isEmpty, next != sequence.title, let engine = state.engine else { return }
        // A sequence is a record like any other; its name is a field on it.
        state.replace(engine.set(shot: sequence.id, field: "title", value: next))
    }
}


/// **The scripts, as text, to paste and edit by hand.** His ask, 2026-09-19:
/// *"I need a place I can just paste in the scripts and edit them myself
/// outside of the side panel, probably in the script tab in project
/// settings."* One script per section, plain text, nothing parsed. Save
/// keeps every shot's tie whose words are still there and says how many
/// were lost.
struct BeatScriptsPage: View {
    @ObservedObject var state: ShellState
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    @State private var section = ""
    @State private var text = ""
    /// An AV script's rows, while it is being edited.
    @State private var rows: [AVScript.Row] = []
    @State private var said = ""
    @State private var making = ""

    private var sections: [ViewModel.Sequence] { state.view?.sequences ?? [] }
    private var sectionWord: String { state.view?.project.sequenceWord ?? "Section" }
    private var held: String { state.view?.scripts.first { $0.section == section }?.text ?? "" }
    /// **Plain or AV** — his ask, 2026-09-30. What the held script is.
    private var av: Bool { AVScript.isAV(held) }
    private var written: String { av ? AVScript.text(rows) : text }
    private var dirty: Bool { written != held }
    private var quoting: Int {
        (state.view?.allRows ?? []).filter { ($0.scriptOf ?? "") == section && $0.scriptFrom != nil }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Dropdown(selection: $section,
                         items: [Dropdown.Item("", "Film")]
                            + sections.map { Dropdown.Item($0.id, $0.title) },
                         width: 220)
                FieldText(placeholder: "New \(sectionWord.lowercased())", text: $making, onSubmit: make)
                    .frame(width: 180)
                Button("Add", action: make)
                    .buttonStyle(.capsule)
                    .disabled(making.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer(minLength: 0)
                Segmented(selection: Binding(get: { av }, set: { lay(av: $0) }),
                          items: [.init(value: false, title: "Plain"), .init(value: true, title: "AV")],
                          quiet: true)
                    .disabled(state.engine == nil || state.view?.project.readOnly == true)
            }
            if av { avEditor } else { plainEditor }
            HStack(spacing: 10) {
                Text(said.isEmpty ? "\(quoting) shot\(quoting == 1 ? "" : "s") quote this" : said)
                    .sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark))
                Spacer(minLength: 0)
                Button("Revert") { load() }.disabled(!dirty)
                Button("Save") { save() }.buttonStyle(.primary).disabled(!dirty)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .onAppear {
            if section.isEmpty, let first = state.view?.scripts.first?.section { section = first }
            load()
        }
        .onChange(of: section) { _, _ in load() }
    }

    private var plainEditor: some View {
        TextEditor(text: $text)
            .font(.custom("Courier", size: 12))
            .scrollContentBackground(.hidden)
            .padding(10)
            .background(Brand.menu(dark), in: RoundedRectangle(cornerRadius: Brand.radius, style: .continuous))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Paste the script here").sans(Brand.Size.body)
                        .foregroundStyle(Brand.ink4(dark))
                        .padding(.leading, 16).padding(.top, 16)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// **Video beside Audio, a row at a time.** Each cell grows with its
    /// words; a row goes with its ×, a new one with + Add Row.
    private var avEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Video").fieldLabel(dark).frame(maxWidth: .infinity, alignment: .leading)
                Text("Audio").fieldLabel(dark).frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: 18, height: 1)
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach($rows) { $row in
                        HStack(alignment: .top, spacing: 8) {
                            cell($row.video)
                            cell($row.audio)
                            ToolButton(icon: "xmark", size: 10, help: "Delete row") {
                                rows.removeAll { $0.id == row.id }
                            }
                            .frame(width: 18).padding(.top, 6)
                        }
                    }
                    HStack {
                        Button("+ Add Row") { rows.append(AVScript.Row(video: "", audio: "")) }
                            .buttonStyle(.capsule)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func cell(_ words: Binding<String>) -> some View {
        TextField("", text: words, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.custom("Courier", size: 12))
            .lineLimit(2...)
            .padding(8)
            .background(Brand.menu(dark), in: RoundedRectangle(cornerRadius: Brand.radius, style: .continuous))
            .frame(maxWidth: .infinity)
    }

    private func load() {
        text = held
        rows = AVScript.rows(held)
        if av, rows.isEmpty { rows = [AVScript.Row(video: "", audio: "")] }
        said = ""
    }

    private func save() {
        guard let engine = state.engine else { return }
        let edit = engine.setScript(written, section: section.isEmpty ? nil : section)
        state.replace(engine.view())
        if let edit {
            said = edit.kept + edit.lost == 0 ? "Saved"
                : "Saved · \(edit.kept) tie\(edit.kept == 1 ? "" : "s") kept"
                  + (edit.lost > 0 ? " · \(edit.lost) lost" : "")
            if Launch.checking {
                FileHandle.standardError.write(Data(("script saved: \(said)\n").utf8))
            }
        }
        load()
    }

    /// Plain ⇄ AV. What is typed is saved first, then the engine lays the
    /// words out the other way; every tie follows its words.
    private func lay(av wanted: Bool) {
        guard wanted != av, let engine = state.engine else { return }
        if dirty { save() }
        let edit = engine.scriptLayout(section: section.isEmpty ? nil : section, av: wanted)
        state.replace(engine.view())
        load()
        if let edit, edit.lost > 0 { said = "\(edit.lost) tie\(edit.lost == 1 ? "" : "s") lost" }
        if Launch.checking {
            FileHandle.standardError.write(Data(("script layout: \(wanted ? "av" : "plain") rows \(rows.count)\n").utf8))
        }
    }

    private func make() {
        let title = making.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, let engine = state.engine else { return }
        state.replace(engine.addSequence(title: title))
        making = ""
        if let made = state.view?.sequences.first(where: { $0.title == title }) { section = made.id }
    }
}
