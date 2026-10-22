import SwiftUI

/// **The film's settings, on the phone** — Ref 466. Until now columns were
/// the only thing editable here; the Mac's Project Settings also holds the
/// film's own facts, its frame, and the lists behind every column.
///
/// The standing spreadsheet link stays a Mac thing: a phone exports a file
/// and hands it to the share sheet, and a workbook that keeps itself current
/// on disk has nowhere to live here.
///
/// **One Settings screen** (2026-10-15, mockup "Two Settings screens"): this
/// is no longer a sheet of its own. It is the project's page inside Settings,
/// pushed from the project row at the top, and opened straight onto by the
/// project sheet's Project Settings row. `close` shuts the whole Settings sheet.
struct ProjectSettingsForm: View {
    @EnvironmentObject private var session: Session
    var close: () -> Void = {}

    @State private var title = ""
    @State private var director = ""
    @State private var producer = ""
    @State private var client = ""
    @State private var agency = ""
    /// **Kind.** A commercial changes what a scene needs (a title, not a
    /// number), what leads (title; the slugline folded away) and what a
    /// sequence is called. Switching changes no data.
    @State private var kind = "film"
    @State private var ratio = 1.85
    @State private var loaded = false
    @State private var consoleMissing = false

    private var project: Engine.Project? { session.view?.project }
    /// Whether the project record owns the film's facts.
    private var fromRecord: Bool { project?.factsFromRecord == true }
    /// Whether the shared record's card is laid on (its icon, kind and title).
    private var onRecord: Bool { project?.card == true }

    var body: some View {
            Form {
                // **Three groups** (the Mac's Project Settings, sorted,
                // 2026-10-16): the project's own facts; everything from the
                // spec sheet, together; and what only Studio keeps.
                Section {
                    if fromRecord {
                        fact("Title", project?.shownTitle ?? "")
                    } else {
                        typed("Title", $title, "title")
                    }
                    if onRecord {
                        fact("Kind", project?.isCommercial == true ? "Commercial" : "Film")
                    } else {
                        Picker("Kind", selection: $kind) {
                            Text("Film").tag("film")
                            Text("Commercial").tag("commercial")
                        }
                        .onChange(of: kind) { _, now in
                            guard loaded, now != project?.kind else { return }
                            session.setKind(now)
                        }
                    }
                    if fromRecord {
                        fact("Director", project?.director ?? "")
                        fact("Producer", project?.producer ?? "")
                        if project?.isCommercial == true {
                            fact("Client", project?.client ?? "")
                            fact("Agency", project?.agency ?? "")
                        }
                    } else {
                        typed("Director", $director, "director")
                        typed("Producer", $producer, "producer")
                        if kind == "commercial" {
                            typed("Client", $client, "client")
                            typed("Agency", $agency, "agency")
                        }
                    }
                    if !onRecord {
                        NavigationLink {
                            IconColorPage().environmentObject(session)
                        } label: {
                            LabeledContent("Icon & Color") {
                                if let mark = project?.mark { FilmIcon(mark: mark, size: 18) } else { Text("None") }
                            }
                        }
                        .accessibilityIdentifier("settings.icon")
                    }
                    if onRecord {
                        LabeledContent("Icon") {
                            if let mark = project?.mark {
                                FilmIcon(mark: mark, size: 18)
                            } else {
                                Text("None").foregroundStyle(.secondary)
                            }
                        }
                    }
                    if fromRecord {
                        Button("Change in Console") { ConsoleLink.open(session) { consoleMissing = true } }
                    }
                    driveRow
                } header: {
                    Text("Project")
                }

                if onRecord { ModsSection() }

                Section {
                    NavigationLink {
                        AspectRatioView().environmentObject(session)
                    } label: {
                        LabeledContent("Aspect Ratio") { Text(AspectRatioView.face(project)) }
                    }
                    .accessibilityIdentifier("settings.aspect")
                    NavigationLink {
                        SpecSheetView(sheet: session.specSheet).environmentObject(session)
                    } label: {
                        LabeledContent("Camera") { Text(PhoneSpecSheet.modeName(project?.kitMode ?? "off")) }
                    }
                    .accessibilityIdentifier("settings.specsheet")
                    ForEach(PhoneSpecSheet.kitLists, id: \.self) { field in
                        NavigationLink(value: field) { listRow(field, title: kitTitle(field)) }
                    }
                } header: {
                    Text("Spec Sheet")
                } footer: {
                    SpecStatusLine(sheet: session.specSheet)
                }

                Section {
                    NavigationLink {
                        ColumnsView().environmentObject(session)
                    } label: {
                        LabeledContent("Columns") { Text("\(session.columns.filter(\.visible).count) Shown") }
                    }
                    NavigationLink(value: "tags") { listRow("tags", title: "Tags") }
                    NavigationLink {
                        ListsView().environmentObject(session)
                    } label: {
                        Text("Lists")
                    }
                    .accessibilityIdentifier("settings.lists")
                    NavigationLink {
                        SequencesView().environmentObject(session)
                    } label: {
                        LabeledContent(project?.sequencesWord ?? "Sequences") { Text("\(session.sequences.count)") }
                    }
                    .accessibilityIdentifier("settings.sequences")
                } header: {
                    Text("In Studio")
                }

                // **Media** (SL-1687): every picture and clip, where each is
                // used, Delete and Delete Unused. `MediaLibrary.swift`.
                Section {
                    MediaRow().environmentObject(session)
                }

                if project?.readOnly == true {
                    Section { Text("Read Only. Made by a newer Studio.").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(project?.shownTitle ?? session.entry.name)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { field in
                ListView(field: field).environmentObject(session)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { commit(); close() }
                }
            }
            .alert("Projects Console isn't on this iPhone", isPresented: $consoleMissing) {
                Button("OK", role: .cancel) {}
            }
            // Back to Settings keeps what was typed, the same as Done.
            .onDisappear { if loaded { commit() } }
            .onAppear {
                if session.specSheet.hasSheet, !session.specSheet.read { session.specSheet.refresh() }
                // Coming back from a column's list re-reads nothing: the
                // fields hold what was typed and not yet sent.
                guard !loaded else { return }
                title = project?.title ?? ""
                director = project?.director ?? ""
                producer = project?.producer ?? ""
                client = project?.client ?? ""
                agency = project?.agency ?? ""
                kind = project?.kind ?? "film"
                ratio = project?.ratio ?? 1.85
                loaded = true
            }
    }

    /// One of the record's facts, shown and not taken; selectable to copy.
    private func fact(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value.isEmpty ? "None" : value)
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
        }
    }

    private func typed(_ label: String, _ text: Binding<String>, _ field: String) -> some View {
        LabeledContent(label) {
            TextField(label, text: text)
                .multilineTextAlignment(.trailing)
                .onSubmit { session.setProject(field, to: text.wrappedValue) }
        }
    }

    /// The project's Drive folder, set on the Mac or in Console.
    @ViewBuilder
    private var driveRow: some View {
        let folder = (project?.driveFolder ?? "").trimmingCharacters(in: .whitespaces)
        if folder.isEmpty {
            LabeledContent("Drive Folder") { Text("None").foregroundStyle(.secondary) }
        } else if let url = URL(string: folder.hasPrefix("http") ? folder : "https://drive.google.com/drive/folders/" + folder) {
            Link(destination: url) {
                LabeledContent("Drive Folder") { Image(systemName: "arrow.up.forward") }
                    .foregroundStyle(Color(.label))
            }
        }
    }

    private func kitTitle(_ field: String) -> String {
        field == "lens" ? "Lenses" : field == "lens_filters" ? "Filters" : "Modifiers"
    }

    private func listRow(_ field: String, title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            if session.isListLocked(field) {
                Image(systemName: "lock.fill").font(.kitLabel).foregroundStyle(.secondary)
            }
            Text("\(session.vocabulary(field).count)").foregroundStyle(.secondary)
        }
    }

    /// Whatever is in the fields when Done is pressed, whether or not Return
    /// was — the Mac does the same.
    private func commit() {
        // The record's facts are shown, not typed — nothing to write back.
        guard !fromRecord else { return }
        if title != project?.title { session.setProject("title", to: title) }
        if director != project?.director { session.setProject("director", to: director) }
        if producer != project?.producer { session.setProject("producer", to: producer) }
        if client != project?.client { session.setProject("client", to: client) }
        if agency != project?.agency { session.setProject("agency", to: agency) }
    }
}

/// **Aspect Ratio** (the Mac's `AspectRatioPage`): the spec sheet's ratios,
/// and the one Studio draws storyboards at. The choices come only from the
/// sheet; with one there is nothing to choose, so the rows are not there. A
/// project with no spec sheet keeps its own ratio, picked freely.
struct AspectRatioView: View {
    @EnvironmentObject private var session: Session
    private var project: Engine.Project? { session.view?.project }

    /// The row's figure: the aspect ratio Studio draws at.
    static func face(_ project: Engine.Project?) -> String {
        guard let project else { return "" }
        if let frames = project.frames, let picked = frames.first(where: { $0.picked }) ?? frames.first {
            return short(picked.said)
        }
        return short(Ratios.name(project.ratio))
    }

    static func short(_ said: String) -> String {
        said.hasSuffix(":1") ? String(said.dropLast(2)).trimmingCharacters(in: .whitespaces) : said
    }

    var body: some View {
        Form {
            if let frames = project?.frames {
                Section("Aspect Ratios") {
                    ForEach(frames) { f in
                        HStack(spacing: 10) {
                            RatioShape(ratio: f.ratio)
                            Text(f.said).fontWeight(.medium)
                            if f.name != f.said, !f.name.isEmpty { Text(f.name).foregroundStyle(.secondary) }
                            Spacer()
                            if f.main {
                                Chips(tags: [.init(text: "Main", ink: .own)])
                            }
                        }
                    }
                }
                if frames.count > 1 {
                    Section("Working Aspect Ratio") {
                        Picker("Draw Storyboards At", selection: Binding(
                            get: { project?.frame ?? "" },
                            set: { session.pickFrame($0) })) {
                            ForEach(frames) { f in
                                Text(f.name == f.said || f.name.isEmpty ? f.said : "\(f.said)  \(f.name)").tag(f.name)
                            }
                        }
                        Toggle("Show Other Aspect Ratios as Guides", isOn: Binding(
                            get: { project?.frameGuides ?? false },
                            set: { session.setFrameGuides($0) }))
                    }
                }
            } else {
                Section {
                    RatioMenu(title: "Draw Storyboards At", current: project?.ratio ?? 1.85) { now in
                        session.setProject("aspect_ratio", to: String(format: "%.4f", now))
                    }
                } header: {
                    Text("Working Aspect Ratio")
                } footer: {
                    Text("Studio only")
                }
            }
        }
        .navigationTitle("Aspect Ratio")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A ratio's shape, small, beside its numbers.
private struct RatioShape: View {
    let ratio: Double
    var body: some View {
        let w: CGFloat = 22
        let h = max(6, min(22, w / CGFloat(max(ratio, 0.3))))
        RoundedRectangle(cornerRadius: 2)
            .strokeBorder(Color.secondary, lineWidth: 1)
            .frame(width: ratio >= 1 ? w : h * CGFloat(ratio), height: ratio >= 1 ? h : 22)
            .frame(width: 24, height: 24)
    }
}

/// **Lists**: every list that isn't the spec sheet's or Tags, and Camera.
struct ListsView: View {
    @EnvironmentObject private var session: Session

    var body: some View {
        List {
            Section {
                ForEach(session.listFields.filter { !PhoneSpecSheet.kitLists.contains($0) && $0 != "tags" }, id: \.self) { field in
                    NavigationLink(value: field) {
                        HStack {
                            Text(Engine.Column.name(of: field))
                            Spacer()
                            if session.isListLocked(field) {
                                Image(systemName: "lock.fill").font(.kitLabel).foregroundStyle(.secondary)
                            }
                            Text("\(session.vocabulary(field).count)").foregroundStyle(.secondary)
                        }
                    }
                }
                NavigationLink {
                    CamerasView().environmentObject(session)
                } label: {
                    LabeledContent("Camera") { Text("\(session.units.count)") }
                }
                .accessibilityIdentifier("settings.cameras")
            }
        }
        .navigationTitle("Lists")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// **Sequences** (Sections on a commercial), the Mac's page: each with its
/// colour and scene count, to rename, recolour, delete, or add.
struct SequencesView: View {
    @EnvironmentObject private var session: Session
    @State private var renaming: Engine.Sequence?
    @State private var renamed = ""
    @State private var removing: Engine.Sequence?
    @State private var adding = false
    @State private var fresh = ""

    private var word: String { session.view?.project.sequenceWord ?? "Sequence" }

    var body: some View {
        List {
            ForEach(session.sequences) { s in
                HStack(spacing: 10) {
                    Menu { colours(s) } label: {
                        Circle().fill(Color(markHex: s.colour.isEmpty ? "8E8E93" : s.colour)).frame(width: 14, height: 14)
                    }
                    .accessibilityLabel("Color \(s.title)")
                    Text(s.title)
                    Spacer()
                    let n = session.scenes.filter { $0.sequence == s.id }.count
                    Text(n == 0 ? "No scenes" : "\(n) scene\(n == 1 ? "" : "s")").foregroundStyle(.secondary)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { removing = s } label: { Label("Delete", systemImage: "trash") }
                    Button { renamed = s.title; renaming = s } label: { Label("Rename", systemImage: "pencil") }
                }
                .contextMenu {
                    Button { renamed = s.title; renaming = s } label: { Label("Rename…", systemImage: "pencil") }
                    Menu { colours(s) } label: { Label("Color", systemImage: "paintpalette") }
                    Button(role: .destructive) { removing = s } label: { Label("Delete…", systemImage: "trash") }
                }
            }
            if session.sequences.isEmpty {
                Text(session.view?.project.isCommercial == true ? "No sections yet" : "No sequences yet")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(session.view?.project.sequencesWord ?? "Sequences")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { fresh = ""; adding = true } label: { Label("Add \(word)", systemImage: "plus") }
            }
        }
        .alert("New \(word)", isPresented: $adding) {
            TextField("Name", text: $fresh)
            Button("Cancel", role: .cancel) {}
            Button("Add") { _ = session.addSequence(named: fresh) }
        }
        .alert("Rename \(renaming?.title ?? "")", isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renamed)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let s = renaming { session.renameSection(s, to: renamed) }
                renaming = nil
            }
        }
        .confirmationDialog("Delete \(removing?.title ?? "")?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let s = removing { session.deleteSection(s) }
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: {
            Text("Its scenes stay.")
        }
    }

    @ViewBuilder
    private func colours(_ s: Engine.Sequence) -> some View {
        ForEach(Session.sectionColours, id: \.hex) { c in
            Button(c.name + (s.colour.uppercased() == c.hex.uppercased() ? "  ✓" : "")) {
                session.colourSection(s, hex: c.hex)
            }
        }
    }
}

/// The film's frame as a menu: the Mac's presets in their two groups, the
/// ones he has typed on this phone, and `Custom…`. The list itself is
/// `Ratios` in `shared/`, which both apps compile, so they cannot disagree.
struct RatioMenu: View {
    let title: String
    let current: Double
    let choose: (Double) -> Void
    @AppStorage(Ratios.key) private var stored = ""
    @State private var typing = false
    @State private var said = ""

    /// `Custom…` as a row of the picker; choosing it opens the form and
    /// leaves the film's ratio where it was.
    private static let typeOne = -1.0
    /// `Clear Custom Ratios`, the Mac's, the same way.
    private static let clear = -2.0

    /// What the picker marks: the preset this film's number is close enough
    /// to (a film from before 2026-10-01 holds 1.78 for 16:9), else itself.
    private var selection: Binding<Double> {
        Binding(
            get: { Ratios.preset(for: current)?.value ?? current },
            set: { picked in
                switch picked {
                case Self.typeOne: said = ""; typing = true
                case Self.clear: stored = ""
                default: choose(picked)
                }
            })
    }

    var body: some View {
        // A Picker, not a Menu, so it wears Kind's face above it: the name
        // in ink, the value in the film's colour.
        Picker(title, selection: selection) {
            ForEach(Ratios.groups) { group in
                Section(group.title) {
                    ForEach(group.presets) { p in Text(p.title).tag(p.value) }
                }
            }
            let saved = Ratios.custom(stored)
            let own = saved + (Ratios.preset(for: current) == nil
                && !saved.contains { Ratios.same($0, current) } ? [current] : [])
            Section("Custom") {
                ForEach(own, id: \.self) { r in Text(Ratios.name(r)).tag(r) }
                Text("Custom…").tag(Self.typeOne)
                if !saved.isEmpty {
                    Text("Clear Custom Ratios").tag(Self.clear)
                }
            }
        }
        .accessibilityIdentifier("ratio-menu")
        .alert("Custom Ratio", isPresented: $typing) {
            TextField("2.55:1 or 9:16", text: $said)
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
            Button("Set") {
                guard let r = Ratios.parse(said) else { return }
                Ratios.remember(r)
                choose(r)
            }
            .disabled(Ratios.parse(said) == nil)
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// One list — the terms a column offers — with add, rename, remove and the
/// lock that closes it. Renaming reaches every shot using the old term.
struct ListView: View {
    @EnvironmentObject private var session: Session
    let field: String

    @State private var terms: [String] = []
    @State private var locked = false
    @State private var adding = false
    @State private var fresh = ""
    @State private var renaming: String?
    @State private var renamed = ""
    @State private var said = ""

    /// **A spec-sheet list following the sheet** (Lenses, Filters,
    /// Modifiers; the Mac's `ListPage` with `isKit`): no lock, adding goes
    /// onto the sheet, and only terms not on the sheet can be renamed or
    /// removed here.
    private var isKit: Bool { PhoneSpecSheet.kitLists.contains(field) }
    private var following: Bool { isKit && session.specSheet.linked }
    private var kit: [Engine.KitShoot] { session.view?.project.kit ?? [] }

    var body: some View {
        List {
            if !following {
                Section {
                    Toggle(isOn: $locked) {
                        Label("Locked", systemImage: locked ? "lock.fill" : "lock.open")
                    }
                    .onChange(of: locked) { _, on in
                        session.lockList(field, on)
                    }
                }
            }
            Section {
                ForEach(terms, id: \.self) { term in
                    let off = following && !PhoneSpecSheet.onSheet(field, term, kit: kit)
                    HStack {
                        if isKit {
                            Chips(tags: [.init(text: term, ink: .chosen(session.termColour(field, term)
                                ?? PhoneSpecSheet.ink(field)))], roomy: true)
                        } else {
                            Text(term)
                        }
                        Spacer()
                        if off {
                            Text("Not on Sheet").font(.caption2).foregroundStyle(Color(markHex: "D97706"))
                        }
                        // **Its colour**, the Mac's eight or Automatic (its
                        // column's own ink). Ref 55, on the phone at last.
                        Menu {
                            Button("Automatic") { session.colourTerm(field, term, hex: "") }
                            Divider()
                            ForEach(Array(Swatches.inks.enumerated()), id: \.offset) { at, hex in
                                Button { session.colourTerm(field, term, hex: hex) } label: {
                                    Label {
                                        Text(Swatches.inkNames[at])
                                    } icon: {
                                        Image(uiImage: Swatch.dot(hex, ticked: session.termColour(field, term)?
                                            .uppercased().hasSuffix(hex) == true))
                                    }
                                }
                            }
                        } label: {
                            if let hex = session.termColour(field, term) {
                                Image(uiImage: Swatch.dot(hex))
                            } else {
                                Image(systemName: "paintpalette").foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityLabel("Color \(term)")
                    }
                    .swipeActions(edge: .trailing) {
                        if !following || off {
                            Button(role: .destructive) {
                                let n = session.removeTerm(field, term)
                                said = n > 0 ? "Cleared on \(n) shot\(n == 1 ? "" : "s")" : ""
                                refresh()
                            } label: { Label("Delete", systemImage: "trash") }
                            Button {
                                renamed = term
                                renaming = term
                            } label: { Label("Rename", systemImage: "pencil") }
                            .tint(.blue)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if off {
                            Button { session.specSheet.addToLead(field: field, name: term) } label: {
                                Label("Add to Sheet", systemImage: "plus")
                            }
                        }
                    }
                    .contextMenu {
                        if off {
                            Button { session.specSheet.addToLead(field: field, name: term) } label: {
                                Label("Add to Sheet", systemImage: "plus")
                            }
                        }
                    }
                }
                if terms.isEmpty {
                    Text("Nothing in this list yet").foregroundStyle(.secondary)
                }
            } footer: {
                if following {
                    let note = session.specSheet.said
                    Text(note.isEmpty ? "From the Spec Sheet" : note)
                } else if !said.isEmpty { Text(said) }
            }
        }
        .navigationTitle(isKit ? (field == "lens" ? "Lenses" : field == "lens_filters" ? "Filters" : "Modifiers")
                         : Engine.Column.name(of: field))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { fresh = ""; adding = true } label: { Image(systemName: "plus") }
                    .disabled(locked && !following)
                    .accessibilityLabel(following ? "Add to Sheet" : "Add")
            }
        }
        .alert(following ? "Add to Sheet" : "New Value", isPresented: $adding) {
            TextField("Value", text: $fresh)
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                let value = fresh.trimmingCharacters(in: .whitespaces)
                guard !value.isEmpty else { return }
                if following {
                    session.specSheet.addToLead(field: field, name: value)
                } else {
                    session.addTerm(field, value)
                }
                refresh()
            }
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil },
                                              set: { if !$0 { renaming = nil } })) {
            TextField("Value", text: $renamed)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                guard let from = renaming else { return }
                let to = renamed.trimmingCharacters(in: .whitespaces)
                renaming = nil
                guard !to.isEmpty, to != from else { return }
                let n = session.renameTerm(field, from: from, to: to)
                said = n > 0 ? "Renamed on \(n) shot\(n == 1 ? "" : "s")" : ""
                refresh()
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: session.view?.project.kit) { _, _ in refresh() }
    }

    private func refresh() {
        terms = session.vocabulary(field)
        locked = session.isListLocked(field)
    }
}

/// **The film's cameras** — the Mac's Cameras page: each with its colour and
/// how many shots name it, to rename, recolour or take away. Renaming touches
/// no shot (each holds the camera, not its name); taking one away leaves the
/// shots everything else of their own.
struct CamerasView: View {
    @EnvironmentObject private var session: Session

    @State private var renaming: Engine.Unit?
    @State private var renamed = ""
    @State private var removing: Engine.Unit?
    @State private var adding = false
    @State private var fresh = ""
    /// The camera a new sensor is being typed for.
    @State private var sensorFor: Engine.Unit?
    @State private var sensorName = ""
    @State private var sensorW = ""
    @State private var sensorH = ""

    var body: some View {
        List {
            Section {
                ForEach(session.units) { unit in
                    row(unit)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { removing = unit } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button { renamed = unit.label; renaming = unit } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.indigo)
                        }
                        .contextMenu { menu(unit) }
                }
                if session.units.isEmpty {
                    Text("No cameras yet").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Camera")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { fresh = ""; adding = true } label: { Label("Add Camera", systemImage: "plus") }
            }
        }
        .alert("Add Camera", isPresented: $adding) {
            TextField("Name", text: $fresh)
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                let name = fresh.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { session.addUnit(named: name) }
            }
        }
        .alert("Rename \(renaming?.label ?? "")", isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renamed)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let unit = renaming { session.renameUnit(unit, to: renamed) }
                renaming = nil
            }
        }
        .alert("New Sensor", isPresented: Binding(
            get: { sensorFor != nil }, set: { if !$0 { sensorFor = nil } })) {
            TextField("Name", text: $sensorName)
            TextField("Width (mm)", text: $sensorW).keyboardType(.decimalPad)
            TextField("Height (mm)", text: $sensorH).keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) { sensorFor = nil }
            Button("Set") {
                let w = Double(sensorW.replacingOccurrences(of: ",", with: ".")) ?? 0
                let h = Double(sensorH.replacingOccurrences(of: ",", with: ".")) ?? 0
                if let unit = sensorFor, w > 0 {
                    let name = sensorName.trimmingCharacters(in: .whitespaces)
                    PhoneSensorPresets.keep(name: name, w: w, h: h)
                    session.setSensor(unit, name: name, w: w, h: h)
                }
                sensorFor = nil
            }
        }
        .confirmationDialog("Delete \(removing?.label ?? "")",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let unit = removing { session.removeUnit(unit) }
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: {
            // What a delete will cost, said before it happens.
            let n = removing.map(session.uses(of:)) ?? 0
            Text(n == 0 ? "No shot uses it." : "\(n) shot\(n == 1 ? "" : "s") will name no camera. They keep everything else.")
        }
    }

    private func row(_ unit: Engine.Unit) -> some View {
        HStack(spacing: 10) {
            Menu { colours(unit) } label: {
                Circle().fill(unit.tint).frame(width: 16, height: 16)
            }
            .accessibilityLabel("Color \(unit.label)")
            VStack(alignment: .leading, spacing: 2) {
                Text(unit.label)
                sensorLine(unit)
            }
            Spacer()
            let n = session.uses(of: unit)
            Text(n == 1 ? "1 shot" : "\(n) shots").foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera.\(unit.label)")
    }

    @ViewBuilder
    private func menu(_ unit: Engine.Unit) -> some View {
        Button { renamed = unit.label; renaming = unit } label: { Label("Rename…", systemImage: "pencil") }
        Menu { colours(unit) } label: { Label("Color", systemImage: "paintpalette") }
        if session.view?.project.sensorsFromSheet != true {
            Menu { sensorChoices(unit) } label: { Label("Sensor", systemImage: "camera.metering.matrix") }
        }
        Button(role: .destructive) { removing = unit } label: { Label("Delete…", systemImage: "trash") }
    }

    /// **The camera's sensor** (the Mac's `sensorMenu`): the spec sheet's
    /// sensor mode, shown and never typed; else one typed here.
    @ViewBuilder
    private func sensorLine(_ unit: Engine.Unit) -> some View {
        let words = Text(unit.sensorText ?? "No Sensor").font(.kitLabel).foregroundStyle(.secondary)
        if session.view?.project.sensorsFromSheet == true {
            words
        } else {
            Menu { sensorChoices(unit) } label: { words }
        }
    }

    @ViewBuilder
    private func sensorChoices(_ unit: Engine.Unit) -> some View {
        let presets = PhoneSensorPresets.all()
        if !presets.isEmpty {
            Section("Presets") {
                ForEach(presets, id: \.name) { p in
                    Button("\(p.name)  \(String(format: "%.2f × %.2f mm", p.w, p.h))") {
                        session.setSensor(unit, name: p.name, w: p.w, h: p.h)
                    }
                }
            }
        }
        Button("New Sensor…") {
            sensorName = ""; sensorW = ""; sensorH = ""
            sensorFor = unit
        }
        if unit.sensorText != nil {
            Button("No Sensor") { session.setSensor(unit, name: "", w: 0, h: 0) }
        }
    }

    /// The Mac's six, named, the palette the chips can draw.
    @ViewBuilder
    private func colours(_ unit: Engine.Unit) -> some View {
        ForEach(Array(Swatches.highlight.enumerated()), id: \.offset) { at, hex in
            Button { session.recolourUnit(unit, hex) } label: {
                Label {
                    Text(Swatches.highlightNames[at])
                } icon: {
                    Image(uiImage: Swatch.dot(hex, ticked: unit.colour.uppercased().hasSuffix(hex)))
                }
            }
        }
    }
}


/// Sensors typed on this phone, offered again — the Mac keeps its own.
enum PhoneSensorPresets {
    struct Preset: Codable { var name: String; var w: Double; var h: Double }
    private static let key = "sensorPresets"

    static func all() -> [Preset] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Preset].self, from: data) else {
            return [Preset(name: "Alexa Mini LF Open Gate", w: 36.70, h: 25.54)]
        }
        return list
    }

    static func keep(name: String, w: Double, h: Double) {
        guard !name.isEmpty else { return }
        var list = all().filter { $0.name != name }
        list.append(Preset(name: name, w: w, h: h))
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
    }
}
