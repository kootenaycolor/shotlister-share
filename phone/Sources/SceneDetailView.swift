import SwiftUI

/// **A scene's own facts, on the phone.**
///
/// The phone could open a scene and see its shots, and that was all: the
/// number, the slugline, what happens in it, the places it is shot at and the
/// mood boards it hangs were readable on the Mac and nowhere here. This is the
/// Mac's scene editor, in a shape a thumb can reach.
///
/// Nothing new underneath. A scene is a record like any other, so every line
/// goes through the same `set` a cell uses — undoable, saved as it lands, and
/// merged between devices. Only the shoot day is a command of its own, because
/// a day is an assignment rather than a word.
///
/// **The number is editable, deliberately.** The law is that the *app* never
/// renumbers. A person fixing their own typo is not the app renumbering.
struct SceneDetailView: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss

    let id: String

    /// Typed here and written as it changes, so the cursor is not fighting the
    /// engine's answer arriving on every keystroke.
    @State private var number = ""
    @EnvironmentObject private var frames: Frames
    @State private var pinning = false
    @State private var viewing: Engine.Still?
    @State private var sharing: Engine.Still?
    @State private var title = ""
    @State private var location = ""
    @State private var synopsis = ""
    @State private var notes = ""
    @State private var filming = ""
    @State private var loaded = ""
    /// Which field has focus, so its own answer is never yanked out from under
    /// him while he is in it.
    @FocusState private var editing: String?

    @State private var addingPlace = false
    @State private var addingBoard = false
    /// A term the film has never used, being typed.
    @State private var adding: String?
    @State private var fresh = ""

    private var scene: Engine.Scene? { session.scene(id) }
    /// **A commercial scene: title first, then the number beside it.** The
    /// number is still editable — a person fixing one is not the app
    /// renumbering — but it sits second rather than leading. The slugline is
    /// an optional fact underneath; there is no synopsis, the script is.
    private var commercial: Bool { session.isCommercial }

    /// What a slugline actually says. Free text is allowed too — a script can
    /// say anything — but these are the ones worth one tap.
    private static let insideOut = ["INT", "EXT", "INT/EXT"]
    private static let times = TimeOfDay.all + ["CONTINUOUS"]

    var body: some View {
        Group {
            if let scene {
                Form {
                    if commercial {
                        Section("Title") {
                            TextField("Hero Unboxes the Camera", text: $title)
                                .focused($editing, equals: "title")
                                .onChange(of: title) { _, new in session.setScene(id, "title", to: new) }
                        }
                    }
                    Section("Number") {
                        TextField("Number", text: $number)
                            .font(.kitRow.monospaced())
                            .focused($editing, equals: "number")
                            .onChange(of: number) { _, new in session.setScene(id, "number", to: new) }
                    }

                    Section {
                        PillField(
                            label: "Inside / Outside",
                            options: Self.insideOut,
                            selected: scene.intExt.isEmpty ? [] : [scene.intExt],
                            onChange: { session.setScene(id, "int_ext", to: $0.first ?? "") },
                            // Any word, as on the Mac: a script can say anything.
                            onNew: { fresh = ""; adding = "int_ext" },
                            drawn: { $0.uppercased() == "INT/EXT" ? "I/E" : $0 }
                        )
                        TextField("Location", text: $location)
                            .focused($editing, equals: "location")
                            .onChange(of: location) { _, new in session.setScene(id, "location", to: new) }
                        PillField(
                            label: "Time of Day",
                            options: Self.times,
                            selected: scene.timeOfDay.isEmpty ? [] : [scene.timeOfDay],
                            onChange: { session.setScene(id, "time_of_day", to: $0.first ?? "") },
                            onNew: { fresh = ""; adding = "time_of_day" }
                        )
                    } header: {
                        Text("Slugline")
                    }

                    if !commercial {
                        Section("Synopsis") {
                            TextField("Synopsis", text: $synopsis, axis: .vertical)
                                .lineLimit(3...12)
                                .focused($editing, equals: "synopsis")
                                .onChange(of: synopsis) { _, new in session.setScene(id, "description", to: new) }
                        }
                    }

                    Section {
                        PillField(
                            label: "Tags",
                            options: session.vocabulary("tags"),
                            selected: scene.tagList,
                            multiple: true,
                            onChange: { session.setScene(id, "tags", to: $0.joined(separator: ", ")) },
                            onNew: { fresh = ""; adding = "tags" }
                        )
                        PillField(
                            label: "Priority",
                            options: session.vocabulary("priority"),
                            selected: scene.priority.isEmpty ? [] : [scene.priority],
                            onChange: { session.setScene(id, "priority", to: $0.first ?? "") },
                            onNew: { fresh = ""; adding = "priority" }
                        )
                        PillField(
                            label: "Point of View",
                            options: session.vocabulary("pov"),
                            selected: scene.povList,
                            multiple: true,
                            onChange: { session.setScene(id, "pov", to: $0.joined(separator: ", ")) },
                            onNew: { fresh = ""; adding = "pov" }
                        )
                    }

                    scheduleSection(scene)
                    placesSection(scene)
                    boardsSection(scene)

                    Section("Notes") {
                        TextField("Notes", text: $notes, axis: .vertical)
                            .lineLimit(3...12)
                            .focused($editing, equals: "notes")
                            .onChange(of: notes) { _, new in session.setSceneNotes(id, to: new) }
                    }

                    // **Pinned** (the Mac's Notes tab): files on the scene itself.
                    Section("Pinned") {
                        ForEach(scene.attachments) { file in
                            Button {
                                if file.kind == .other { sharing = file } else { viewing = file }
                            } label: {
                                HStack(spacing: 12) {
                                    if file.kind == .other {
                                        Image(systemName: "doc").frame(width: 44, height: 44)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        FrameThumbnail(frame: file.frame, side: 44)
                                    }
                                    Text(file.filename).foregroundStyle(Color(.label)).lineLimit(1)
                                }
                            }
                            .swipeActions { Button("Unpin", role: .destructive) { session.detach(file) } }
                        }
                        Button("Pin File…") { pinning = true }
                    }
                    .fileImporter(isPresented: $pinning, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                        guard case .success(let urls) = result else { return }
                        Task {
                            for url in urls {
                                let scoped = url.startAccessingSecurityScopedResource()
                                await session.pin(fileAt: url, toScene: id)
                                if scoped { url.stopAccessingSecurityScopedResource() }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("This scene is gone", systemImage: "film")
            }
        }
        .navigationTitle(commercial && scene?.title.isEmpty == false ? scene!.title
                         : scene?.number.isEmpty == false ? "Scene \(scene!.number)" : "Scene")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .task { load() }
        .onChange(of: mirror) { _, _ in adopt() }
        .fullScreenCover(item: $viewing) { still in
            StillViewer(still: still, all: (scene?.attachments ?? []).filter { $0.kind != .other },
                        onDelete: { session.detach($0) }, cropTo: session.ratio)
                .environmentObject(session)
                .environmentObject(frames)
        }
        .sheet(item: $sharing) { file in
            if let url = Frames.proxyFile(file.hash, wanting: file.ext, in: session.folder.url) {
                ShareSheetView(items: [url])
            } else {
                ContentUnavailableView("Not on This iPhone", systemImage: "doc")
            }
        }
        .sheet(isPresented: $addingPlace) {
            Picking(title: "Add place",
                    choices: session.locations
                        .filter { !(scene?.locations.contains($0.id) ?? false) }
                        .map { (id: $0.id, name: $0.fullName?.isEmpty == false ? $0.fullName! : $0.name) }) { place in
                session.link(scene: id, toLocation: place)
                addingPlace = false
            }
        }
        .sheet(isPresented: $addingBoard) {
            Picking(title: "Add Board",
                    choices: session.boards
                        .filter { !(scene?.boards.contains($0.id) ?? false) }
                        .map { (id: $0.id, name: $0.shown) }) { board in
                session.link(scene: id, to: board)
                addingBoard = false
            }
        }
        .alert(Self.newTitle(adding), isPresented: Binding(
            get: { adding != nil }, set: { if !$0 { adding = nil } }
        )) {
            TextField("Value", text: $fresh)
            Button("Cancel", role: .cancel) { adding = nil }
            Button("Add") {
                let value = fresh.trimmingCharacters(in: .whitespacesAndNewlines)
                if let field = adding, !value.isEmpty, let scene {
                    switch field {
                    case "tags":
                        session.setScene(id, "tags", to: (scene.tagList + [value]).joined(separator: ", "))
                    case "pov":
                        session.setScene(id, "pov", to: (scene.povList + [value]).joined(separator: ", "))
                    default:
                        session.setScene(id, field, to: value)
                    }
                }
                adding = nil
            }
        }
    }

    /// The prompt's title, in the field's own name.
    private static func newTitle(_ field: String?) -> String {
        switch field {
        case "tags": return "New Tag"
        case "priority": return "New Priority"
        case "pov": return "New Point of View"
        case "int_ext": return "Inside / Outside"
        case "time_of_day": return "Time of Day"
        default: return "New Value"
        }
    }

    // ---- where it sits in the shoot -----------------------------------------

    private func scheduleSection(_ scene: Engine.Scene) -> some View {
        Section("Shoot Day") {
            Picker("Day", selection: Binding(
                get: { onDay(scene)?.id ?? "" },
                set: { session.assign(scene: id, toDay: $0.isEmpty ? nil : $0) }
            )) {
                Text("None").tag("")
                ForEach(session.pickableDays(keeping: onDay(scene)?.id)) { day in
                    Text(day.label).tag(day.id)
                }
            }
            Picker(session.sequenceWord, selection: Binding(
                get: { session.sequence(ofScene: id)?.id ?? "" },
                set: { session.setSequence(ofScene: id, to: $0) }
            )) {
                Text("None").tag("")
                ForEach(session.sequences) { run in
                    Text(run.title).tag(run.id)
                }
            }
        }
    }

    /// The day this scene is on, matched by the label the engine wrote — a
    /// scene carries the day's *name*, not its id, because a scene can sit on
    /// more than one and the table draws them as words.
    private func onDay(_ scene: Engine.Scene) -> Engine.Day? {
        session.days.first { $0.label == scene.day }
    }

    // ---- the real places ----------------------------------------------------

    private func placesSection(_ scene: Engine.Scene) -> some View {
        let places = session.locations(ofScene: id)
        return Section {
            ForEach(places) { place in
                Text(place.fullName?.isEmpty == false ? place.fullName! : place.name)
                    .lineLimit(1)
            }
            .onDelete { indexes in
                indexes.map { places[$0] }.forEach { session.unlink(scene: id, fromLocation: $0.id) }
            }
            if places.isEmpty {
                Text("No places").font(.kitLabel).foregroundStyle(.secondary)
            }
            // Older projects wrote the real place as words, before there were
            // location records to point at. Shown only where there is one, so
            // it can be read and cleared rather than quietly outliving itself.
            if !filming.isEmpty || editing == "filming" {
                TextField("Filming Location", text: $filming)
                    .focused($editing, equals: "filming")
                    .onChange(of: filming) { _, new in
                        session.setScene(id, "shooting_location", to: new)
                    }
            }
        } header: {
            HStack {
                Label("Places", systemImage: "mappin.and.ellipse")
                Spacer()
                Button { addingPlace = true } label: { Image(systemName: "plus") }
            }
        }
    }

    // ---- the boards it hangs -------------------------------------------------

    private func boardsSection(_ scene: Engine.Scene) -> some View {
        let hung = session.boards(ofScene: id)
        return Section {
            ForEach(hung) { board in
                HStack(spacing: 10) {
                    Text(board.shown).lineLimit(1)
                    Spacer(minLength: 0)
                    if !board.media.isEmpty {
                        Text("\(board.media.count)")
                            .font(.kitLabel).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { indexes in
                indexes.map { hung[$0] }.forEach { session.unlink(scene: id, from: $0.id) }
            }
            if hung.isEmpty {
                Text("No boards").font(.kitLabel).foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Label("Reference Boards", systemImage: "square.grid.2x2")
                Spacer()
                Button { addingBoard = true } label: { Image(systemName: "plus") }
            }
        }
    }

    // ---- keeping up with the other device -----------------------------------

    /// The five fields held locally, as one string. When the engine's answer
    /// differs from what was last taken up, take it up again.
    private var mirror: String {
        guard let scene else { return "" }
        return [scene.number, scene.title, scene.location, scene.description,
                scene.notes, scene.shootingLocation].joined(separator: "\u{1F}")
    }

    private func load() {
        guard let scene else { return }
        number = scene.number
        title = scene.title
        location = scene.location
        synopsis = scene.description
        notes = scene.notes
        filming = scene.shootingLocation
        loaded = mirror
    }

    private func adopt() {
        guard let scene, mirror != loaded else { return }
        if editing != "number" { number = scene.number }
        if editing != "title" { title = scene.title }
        if editing != "location" { location = scene.location }
        if editing != "synopsis" { synopsis = scene.description }
        if editing != "notes" { notes = scene.notes }
        if editing != "filming" { filming = scene.shootingLocation }
        loaded = mirror
    }
}

/// One thing out of a list, by name. Used for the two things a scene points
/// at — a place and a mood board — so both ask the same question the same way.
private struct Picking: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let choices: [(id: String, name: String)]
    let onPick: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(choices, id: \.id) { choice in
                    Button {
                        onPick(choice.id)
                        dismiss()
                    } label: {
                        Text(choice.name.isEmpty ? "Untitled" : choice.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if choices.isEmpty {
                    Text("Nothing to add").font(.kitLabel).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
