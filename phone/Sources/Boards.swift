import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// **Mood boards on the phone** — Ref 347, the tab that said *Not built yet*
/// from the day the bottom bar was drawn.
///
/// A board is a name and a wall of pictures, and it belongs to the film rather
/// than to any one scene: one board — *Night Exteriors*, *The Diner* — serves
/// twenty scenes, and a scene links the boards that apply to it.
///
/// **Pictures first, and that is the whole difference from Locations.** His
/// instruction, 2026-08-30: a location's photographs are a utility — proof of
/// what a room looks like, filed under an address — so they sit in a section of
/// a form. A mood board *is* its pictures. So the list is a wall of covers
/// rather than rows of text, a board opens straight onto its own wall, and
/// everything that is not a picture — the name, the tags, the scenes it serves,
/// the shape it hangs in — waits behind the ⋯ where it cannot crowd the look.
///
/// **Almost none of this is new machinery.** A board is an owner, and every
/// owner in this app already holds pictures the same way, so the wall is
/// `MediaGallery`, the full-screen page is `StillViewer`, the tiles are
/// `Frames` and the tags are `PillField` — every one of them written for a
/// location or a shot and none of them caring which owner it is drawing.

// ------------------------------------------------------------------ the walls

struct MoodBoardsView: View {
    @EnvironmentObject private var session: Session
    @State private var naming = false
    @State private var newName = ""
    @State private var renaming: Engine.Board?
    @State private var removing: Engine.Board?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    @State private var query = ""

    private var shown: [Engine.Board] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? session.boards : session.boards.filter { $0.shown.lowercased().contains(q) }
    }

    var body: some View {
        Group {
            if session.boards.isEmpty {
                ContentUnavailableView {
                    Label("No reference boards yet", systemImage: "square.grid.2x2")
                } actions: {
                    Button("Add Board") { startNaming() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(shown) { board in
                            NavigationLink(value: board) {
                                BoardCover(board: board)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                // **Order** (the Mac drags its board list).
                                if let at = session.boards.firstIndex(where: { $0.id == board.id }) {
                                    if at > 0 {
                                        Button { session.moveBoard(board.id, to: at - 1) } label: {
                                            Label("Move Earlier", systemImage: "arrow.left")
                                        }
                                    }
                                    if at < session.boards.count - 1 {
                                        Button { session.moveBoard(board.id, to: at + 1) } label: {
                                            Label("Move Later", systemImage: "arrow.right")
                                        }
                                    }
                                }
                                Button { startRenaming(board) } label: {
                                    Label("Rename…", systemImage: "pencil")
                                }
                                Button(role: .destructive) { removing = board } label: {
                                    Label("Delete Board", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
        }
        .searchable(text: $query, prompt: "Search")
        .leadingTitle("Reference Images")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { startNaming() } label: { Label("Add", systemImage: "plus") }
            }
        }
        .navigationDestination(for: Engine.Board.self) { board in
            BoardDetailView(id: board.id).environmentObject(session)
        }
        .alert("New Board", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) { newName = "" }
            Button("Add") {
                let named = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                newName = ""
                guard !named.isEmpty else { return }
                session.addBoard(named: named)
            }
        }
        .alert("Rename Board", isPresented: Binding(get: { renaming != nil },
                                                    set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) { renaming = nil; newName = "" }
            Button("Rename") {
                let named = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                let board = renaming
                renaming = nil
                newName = ""
                guard let board, !named.isEmpty else { return }
                session.renameBoard(board.id, to: named)
            }
        }
        .confirmationDialog("Delete \(removing?.shown ?? "this board")?",
                            isPresented: Binding(get: { removing != nil },
                                                 set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let board = removing { session.deleteBoard(board.id) }
                removing = nil
            }
            Button("Keep It", role: .cancel) { removing = nil }
        }
    }

    private func startNaming() {
        newName = ""
        naming = true
    }

    private func startRenaming(_ board: Engine.Board) {
        newName = board.name
        renaming = board
    }
}

/// One board as a wall in miniature — four pictures, its name underneath.
///
/// Four rather than one: a board is a *set* of pictures, and a single cover
/// says no more about it than a filename would.
struct BoardCover: View {
    @EnvironmentObject private var frames: Frames
    @Environment(\.displayScale) private var scale
    /// Half the screen — what one tile in this two-column grid is actually
    /// drawn at, and therefore what its picture should be decoded at.
    private var cellSide: CGFloat { UIScreen.main.bounds.width / 2 }
    let board: Engine.Board

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            mosaic
                .aspectRatio(1, contentMode: .fit)
                .clipShape(Rectangle())
                .overlay {
                    Rectangle()
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(board.shown)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if !board.media.isEmpty { Text("\(board.media.count)") }
                    if !board.scenes.isEmpty {
                        Label("\(board.scenes.count)", systemImage: "film")
                    }
                }
                .font(.kitLabel)
                .foregroundStyle(.secondary)
            }
        }
        // **A tile is exactly its own cell, and nothing either side of it.**
        // His report, 2026-08-31: tapping the right-hand edge of *General Mood
        // Board* opened *Composition*. A cover left to size itself hands the
        // grid a width of its own, and the tap area of one tile then reaches
        // over its neighbour — invisibly, because what is *drawn* is clipped to
        // the column and only the touches are wrong. Pinned to the column and
        // given its own shape, a tile can only ever open itself.
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var mosaic: some View {
        let four = Array(board.media.prefix(4))
        if four.isEmpty {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "square.grid.2x2")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
        } else if four.count == 1 {
            tile(four[0])
        } else {
            // Two across, and **three pictures fill the wall** — the third
            // spans the bottom rather than sitting beside a blank square,
            // which read as a picture that had failed to load.
            Grid(horizontalSpacing: 1.5, verticalSpacing: 1.5) {
                GridRow {
                    tile(four[0])
                    tile(four[1])
                }
                if four.count == 3 {
                    GridRow {
                        tile(four[2]).gridCellColumns(2)
                    }
                } else if four.count > 3 {
                    GridRow {
                        tile(four[2])
                        tile(four[3])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tile(_ still: Engine.Still) -> some View {
        if let shown = frames.shown(still, atMost: Thumbnails.bucket(forSide: cellSide, scale: scale)) {
            Color.clear.overlay { Picture(shown, framing: still.framing, arrows: still.arrows) }.clipped()
        } else {
            Rectangle().fill(.quaternary)
        }
    }
}

// ------------------------------------------------------------------ one board

struct BoardDetailView: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var frames: Frames

    let id: String

    @State private var picked: [PhotosPickerItem] = []
    @State private var pickingFromLibrary = false
    @State private var takingPhoto = false
    @State private var importing = false
    @State private var fromProject = false
    @State private var browsing: Engine.Still?
    @State private var showingScenes = false
    @State private var showingTags = false
    @State private var renaming = false
    @State private var newName = ""
    /// Held out here, not inside the gallery: this screen is rebuilt on every
    /// answer the engine hands back, and a selection kept in the gallery is
    /// thrown away and duplicated by that.
    @StateObject private var gallery = GallerySelection()

    private var board: Engine.Board? { session.board(id) }

    var body: some View {
        Group {
            if let board {
                if board.media.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing on this board", systemImage: "photo.on.rectangle")
                    } actions: {
                        Button("Add Pictures") { pickingFromLibrary = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ScrollView {
                        MediaGallery(
                            media: board.media,
                            selection: gallery,
                            onOpen: { browsing = $0 },
                            onRemove: { chosen in chosen.forEach(session.detach) },
                            onMove: { still, index in session.move(still, to: index) },
                            shape: board.ratioMode,
                            ratio: session.ratio,
                            moveTargets: session.boards.filter { $0.id != board.id }.map { ($0.id, $0.shown) },
                            onMoveTo: { chosen, to in chosen.forEach { session.movePicture($0, toOwner: to) } }
                        )
                        .padding(.horizontal, 10)
                        .padding(.bottom, 16)
                    }
                }
            } else {
                ContentUnavailableView("This board is gone", systemImage: "square.grid.2x2")
            }
        }
        .navigationTitle(board?.shown ?? "Board")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { takingPhoto = true } label: { Label("Take a Photo", systemImage: "camera") }
                    Button { pickingFromLibrary = true } label: {
                        Label("Photos Library", systemImage: "photo.on.rectangle")
                    }
                    Button { importing = true } label: { Label("Files", systemImage: "folder") }
                    Button { fromProject = true } label: { Label("From Project", systemImage: "square.stack") }
                } label: { Image(systemName: "plus") }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { newName = board?.name ?? ""; renaming = true } label: {
                        Label("Rename…", systemImage: "pencil")
                    }
                    Button { showingScenes = true } label: { Label("Scenes…", systemImage: "film") }
                    Button { showingTags = true } label: { Label("Tags…", systemImage: "tag") }
                    // The wall's own shape, where the wall is: a board of stills
                    // he wants square is a decision about the look, and the look
                    // is this screen.
                    Picker("Shape", selection: Binding(
                        get: { board?.ratioMode ?? "original" },
                        set: { session.setBoard(id, "board_ratio", to: $0) }
                    )) {
                        Text("Original").tag("original")
                        Text("Square").tag("square")
                        Text("Project").tag("project")
                    }
                    // **Sync with Drive** — Ref 229's second half. Off until
                    // he switches it on, and it means nothing until the film
                    // itself carries a Drive folder, which is set on the Mac.
                    Toggle("Sync with Drive", isOn: Binding(
                        get: { board?.syncsWithDrive ?? false },
                        set: { session.setBoard(id, "sync_with_drive", to: $0 ? "1" : "0") }
                    ))
                    .disabled((session.view?.project.driveFolder ?? "")
                        .trimmingCharacters(in: .whitespaces).isEmpty)
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .fullScreenCover(isPresented: $takingPhoto) {
            CameraCapture { image in session.attach(image, toBoard: id) }
                .ignoresSafeArea()
        }
        .fullScreenCover(item: $browsing) { still in
            StillViewer(still: still, all: board?.media ?? [],
                        onDelete: { session.detach($0) },
                        cropTo: board?.ratioMode == "square" ? 1 : session.ratio)
                .environmentObject(session)
                .environmentObject(frames)
        }
        .sheet(isPresented: $showingScenes) {
            BoardScenes(id: id).environmentObject(session)
        }
        .sheet(isPresented: $showingTags) {
            BoardTags(id: id).environmentObject(session)
        }
        .alert("Rename Board", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) { newName = "" }
            Button("Rename") {
                let named = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                newName = ""
                guard !named.isEmpty else { return }
                session.renameBoard(id, to: named)
            }
        }
        .sheet(isPresented: $fromProject) { FromProjectPicker(owner: id).environmentObject(session) }
        .photosPicker(isPresented: $pickingFromLibrary, selection: $picked,
                      matching: .any(of: [.images, .videos]))
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            bringIn(files: result)
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task { await bringIn(items) }
        }
    }

    // ---- doing things -------------------------------------------------------

    private func bringIn(files result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            let allowed = url.startAccessingSecurityScopedResource()
            defer { if allowed { url.stopAccessingSecurityScopedResource() } }
            if Engine.Kind(url.pathExtension) == .clip {
                // Copied while permission to read it is still held: the
                // re-encode happens later, by which time this URL is closed.
                let named = url.lastPathComponent
                let copy = URL.temporaryDirectory.appending(path: "picked-\(UUID().uuidString)-\(named)")
                if (try? FileManager.default.copyItem(at: url, to: copy)) != nil {
                    Task {
                        await session.attach(clipAt: copy, to: id, named: named)
                        try? FileManager.default.removeItem(at: copy)
                    }
                }
            } else if let data = try? Data(contentsOf: url), UIImage(data: data) != nil {
                session.attach(data, named: url.lastPathComponent, toBoard: id)
            }
        }
        session.refresh()
    }

    private func bringIn(_ items: [PhotosPickerItem]) async {
        for item in items {
            // As a file, not as bytes — a clip needs a path and a photograph
            // needs its name. See `Picked`.
            if let file = try? await item.loadTransferable(type: Picked.self) {
                defer { file.discard() }
                if file.isClip {
                    await session.attach(clipAt: file.url, to: id)
                } else if let data = try? Data(contentsOf: file.url) {
                    session.attach(data, named: file.url.lastPathComponent, toBoard: id)
                }
            } else if let data = try? await item.loadTransferable(type: Data.self) {
                session.attach(data, toBoard: id)
            }
        }
        picked = []
    }
}

// ------------------------------------------------- what a board is also for

/// The scenes a board serves. Off the wall, because a board is about a look and
/// this is bookkeeping.
private struct BoardScenes: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    let id: String
    @State private var adding = false

    private var hung: [Engine.Scene] { session.scenes.filter { $0.boards.contains(id) } }

    var body: some View {
        NavigationStack {
            List {
                ForEach(hung) { scene in
                    HStack(spacing: 10) {
                        Text(scene.number.isEmpty ? "—" : scene.number)
                            .font(.subheadline.monospaced())
                            .foregroundStyle(.secondary)
                        Text(scene.heading.isEmpty ? scene.description : scene.heading)
                            .lineLimit(1)
                    }
                }
                .onDelete { indexes in
                    let list = hung
                    indexes.map { list[$0] }.forEach { session.unlink(scene: $0.id, from: id) }
                }
                if hung.isEmpty {
                    Text("No scenes").font(.kitLabel).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Scenes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $adding) {
                ScenePicker(title: "Add Scene", except: "",
                            hiding: Set(hung.map(\.id))) { scene in
                    session.link(scene: scene.id, to: id)
                    adding = false
                }
                .environmentObject(session)
            }
        }
    }
}

/// The board's words, out of the way of its pictures.
private struct BoardTags: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    let id: String
    @State private var adding = false
    @State private var fresh = ""

    private var board: Engine.Board? { session.board(id) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PillField(
                        label: "Tags",
                        options: session.vocabulary("tags"),
                        selected: board?.tagList ?? [],
                        multiple: true,
                        onChange: { session.setBoard(id, "tags", to: $0.joined(separator: ", ")) },
                        onNew: { fresh = ""; adding = true }
                    )
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .alert("New Tag", isPresented: $adding) {
                TextField("Tag", text: $fresh)
                Button("Cancel", role: .cancel) { fresh = "" }
                Button("Add") {
                    let value = fresh.trimmingCharacters(in: .whitespacesAndNewlines)
                    fresh = ""
                    guard !value.isEmpty, let board else { return }
                    session.setBoard(id, "tags", to: (board.tagList + [value]).joined(separator: ", "))
                }
            }
        }
    }
}
