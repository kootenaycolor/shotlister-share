import AppKit
import SwiftUI

/// **Mood boards** — Ref 58, and the third thing the sidebar has always
/// promised. It said *Not built yet* until 2026-08-23, on both the Mac and the
/// phone, because there was no board record anywhere in the engine.
///
/// A board is a name and a wall of pictures. That is the whole of it.
///
/// **Almost none of this is new machinery.** A board is an owner, and every
/// owner in this app already holds pictures the same way — `Kind::Media`
/// reached through `Kind::MediaRef`. So the drop target is `Attachments.take`,
/// the second door is `PicturePicker`, the tiles are `Frames.view` and the
/// missing-file answer is `Frames.gap`, all of them written for a scene or a
/// location and none of them caring which. The engine work was a record kind
/// and three commands.
///
/// **A board itself is not tied to a scene** — a mood board is usually about
/// a look rather than a moment — *Night Exteriors*, *Anya*, *The Diner* — and
/// one board serves twenty scenes. But a *scene* can link the boards that
/// apply to it (Ref SL-348, his call, 2026-08-23): the chip lives on the
/// scene, in `SceneDetails.swift` and in the References panel
/// (`SidePanel.swift`), the same grammar the Locations chip already used.

// ------------------------------------------------------------------ the list

/// The sidebar on the Boards tab.
struct BoardList: View {
    @ObservedObject var state: ShellState
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    /// **The search box over this list actually searches now.** It has been
    /// drawn on every tab since the sidebar was built and said "Search boards"
    /// on this one while doing nothing at all. One road, on `ShellState`, so a
    /// checking run reads the same list the sidebar draws.
    private var boards: [ViewModel.MoodBoard] { state.boardsShown }

    /// The board a carried picture is currently over, so the row can say so.
    @State private var landingOn: String?
    /// **A board carried to a new place in the list** — his ask, 2026-09-29:
    /// "need to be able to re-order reference boards, the order that they are
    /// in." The same hand the Schedule uses (`ScheduleHands.swift`): a press
    /// and a pull picks a row up and a line shows where it will go; a click
    /// stays the list's own and picks the board. It never starts a system drag,
    /// so it cannot be mistaken for a picture carried in from a wall — that
    /// drop, below, is a system drag and is left exactly as it was.
    @ObservedObject private var hands = BoardHands.shared

    var body: some View {
        List(selection: Binding(
            get: { state.board?.id },
            set: { state.boardId = $0 }
        )) {
            ForEach(Array(boards.enumerated()), id: \.element.id) { at, board in
                HStack(spacing: 8) {
                    Text(board.name.isEmpty ? "Untitled" : board.name)
                        .sans(11, weight: .semibold)
                        .foregroundStyle(Brand.ink(dark))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if !board.media.isEmpty {
                        Text("\(board.media.count)").sans(Brand.Size.tiny).monospacedDigit()
                            .foregroundStyle(Brand.ink4(dark))
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(BoardMarkTag(.boardRow(board.id)))
                .opacity(hands.holds(board: board.id) ? 0.4 : 1)
                .overlay(alignment: .top) {
                    if hands.spot == .boardAt(at) { orderLine.offset(y: -1) }
                }
                .overlay(alignment: .bottom) {
                    if at == boards.count - 1, hands.spot == .boardAt(boards.count) { orderLine.offset(y: 1) }
                }
                .tag(board.id)
                .sidebarRow(picked: state.board?.id == board.id, dark: dark)
                // **A picture dragged out of one wall lands on another** — his
                // ask, 2026-08-24. The row lights up while a picture is over
                // it, the same accent every other drop target uses.
                //
                // What travels is the *use* of the picture, not a copy: the
                // engine rewrites its owner, so the caption written under it
                // and the name it wears come with it. The context menu on the
                // picture itself does the same thing for a hand that would
                // rather not drag — and is the half a check can press, because
                // no synthetic mouse can start a drag session.
                .onDrop(of: [.text], isTargeted: Binding(
                    get: { landingOn == board.id },
                    set: { landingOn = $0 ? board.id : nil }
                )) { providers in
                    guard board.id != state.boardId else { return false }
                    for provider in providers {
                        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                            guard let ref = object as? String else { return }
                            DispatchQueue.main.async {
                                for moving in state.photosActedOn(ref) {
                                    state.replace(state.engine?.movePicture(moving, to: board.id))
                                }
                            }
                        }
                    }
                    return true
                }
                .background {
                    if landingOn == board.id {
                        RoundedRectangle(cornerRadius: Brand.radiusChip)
                            .fill(Brand.accent(dark).opacity(0.18))
                    }
                }
                .contextMenu {
                    Button("Rename…") { state.renamingBoard = board.id }
                    Divider()
                    Button("Delete board", role: .destructive) { remove(board) }
                }
            }
        }
        .sidebarList()
        .environment(\.defaultMinListRowHeight, 30)
        .background(BoardMarkTag(.boardList))
        // **The same empty state the locations sidebar has**, one tab along.
        // This one had none at all: an empty film showed a heading, a search
        // box and a field of nothing between them, while the pane beside it
        // said what was missing and offered the way in.
        .overlay { if boards.isEmpty { empty } }
    }

    /// Where a carried board will go — the same accent line the Schedule
    /// draws between strips.
    private var orderLine: some View {
        Capsule().fill(Brand.accent(dark)).frame(height: 2)
            .allowsHitTesting(false)
    }

    @ViewBuilder private var empty: some View {
        EmptyState(title: state.search.isEmpty
                        ? "No reference boards yet"
                        : "Nothing matches “\(state.search)”",
                   compact: true) {
            if state.search.isEmpty {
                Button("+ Add reference board…") { state.addingBoard = true }
            }
        }
    }

    /// **The pictures stay.** A board is a wall, and taking the wall down does
    /// not throw away what hung on it: a picture is addressed by its contents
    /// and may be on a shot and a location too. Said out loud rather than
    /// asked as a bare yes/no, the way deleting a location says what it costs.
    private func remove(_ board: ViewModel.MoodBoard) {
        let alert = NSAlert()
        alert.messageText = "Delete “\(board.name)”?"
        alert.informativeText = board.media.isEmpty
            ? ""
            : "\(board.media.count) picture\(board.media.count == 1 ? "" : "s") come off this board and stay in the project — anywhere else they hang keeps them."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if state.boardId == board.id { state.boardId = nil }
        state.replace(state.engine?.deleteBoard(board.id))
    }
}

// ------------------------------------------------------------------ the wall

/// One board, filling the window: its name, its pictures, and the two doors a
/// picture comes in by.
struct BoardWall: View {
    @ObservedObject var state: ShellState
    let board: ViewModel.MoodBoard
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    @State private var over = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            ScrollView {
                wall
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
                    .padding(.bottom, 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // The same generic door a scene's references and a location's
            // photographs use. A board that took files its own way would be a
            // second answer to a question already answered.
            .onDrop(of: [.fileURL, .image, .movie], isTargeted: $over) { providers in
                Attachments.take(providers, ownedBy: board.id, state: state)
            }
            .overlay {
                if over {
                    RoundedRectangle(cornerRadius: Brand.radius)
                        .strokeBorder(Brand.accent(dark),
                                      style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        .padding(10)
                }
            }
        }
    }

    /// The name, what is on the wall, and the two things a board belongs to —
    /// its tags and the scenes that hang it.
    private var head: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
            HStack(spacing: 6) {
                tagRow
                sceneChip
                Spacer(minLength: 0)
                driveRow
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 10)
        }
    }

    private var topRow: some View {
        HStack(spacing: 10) {
            Text(board.name.isEmpty ? "Untitled" : board.name)
                .sans(15, weight: .semibold)
                .foregroundStyle(Brand.ink(dark))
            Text(board.media.count == 1 ? "1 picture" : "\(board.media.count) pictures")
                .sans(Brand.Size.small)
                .foregroundStyle(Brand.ink3(dark))
            Spacer(minLength: 0)
            // **The same three controls every wall's header wears now** —
            // his instruction, 2026-08-24: one shared look, Locations as the
            // reference. `RatioMenu` and `AddPicturesMenu` replace what used
            // to be built here twice, once per screen, in two different
            // styles — the filled pills this file first tried, and the plain
            // icon Locations already had. Locations was the one he named.
            if !board.media.isEmpty {
                TileSizeSlider(value: $state.boardUnit)
            }
            RatioMenu(mode: Binding(
                get: { board.ratioMode },
                set: { state.replace(state.engine?.set(shot: board.id, field: "board_ratio", value: $0)) }
            ))
            AddPicturesMenu(owner: board.id, ownerName: board.name.isEmpty ? "this board" : board.name,
                            state: state)
            Button("Rename") { state.renamingBoard = board.id }
                .buttonStyle(.capsule)
                .help("Rename board")
        }
        .padding(.horizontal, 22)
        .frame(height: 46)
    }

    /// **Sync with Drive, on a board** — Ref 229's second half, and the same
    /// control a location wears. His answer, 2026-08-30: an opted-in board's
    /// pictures live in `1-creative/reference/<board>` inside the film, and a
    /// board is **off until he switches it on**.
    ///
    /// It sits on the second row rather than in the header beside the ratio and
    /// the picture menus: those three say how this wall is *drawn*, and this
    /// says where its pictures *go*, which is not the same kind of thing.
    private var driveRow: some View {
        DriveSwitch(
            on: board.syncsWithDrive,
            filmIsLinked: !(state.view?.project.driveFolder ?? "")
                .trimmingCharacters(in: .whitespaces).isEmpty
        ) { want in
            // The generic `set`, the same door the board's shape and its tags
            // go through — a board has no `setboard` of its own on purpose.
            state.replace(state.engine?.set(shot: board.id, field: "sync_with_drive",
                                            value: want ? "1" : "0"))
        }
    }

    /// **The film's one tag list, on a board.** His call, 2026-08-23: one
    /// vocabulary for the whole project rather than a second one for
    /// references. So this writes through the same generic `set` a scene's tags
    /// go through — which splits the list, teaches any new term to the project
    /// permanently, and gives it the colour every other chip of that term
    /// already wears.
    private var tagRow: some View {
        // `SceneTags` is this control, already written and already generic over
        // whichever list it is handed — pills off the project's own vocabulary,
        // never free text that drifts from what the shots use. A second tag row
        // would be a second answer to a question already answered.
        SceneTags(held: board.tagList,
                  options: state.engine?.vocabulary("tags") ?? [],
                  dark: dark) { write(tags: $0) }
    }

    private func write(tags: [String]) {
        state.replace(state.engine?.set(shot: board.id, field: "tags",
                                        value: tags.joined(separator: ", ")))
    }

    /// **Which scenes hang this board**, from the board's own side. The link
    /// itself is the one a scene already makes (Ref 348) — this is the other
    /// end of it, so it can be made here too rather than only from the scene.
    private var sceneChip: some View {
        Menu {
            ForEach(state.view?.scenes ?? []) { scene in
                Button {
                    let on = board.scenes.contains(scene.id)
                    state.replace(on ? state.engine?.removeSceneBoard(scene.id, board.id)
                                     : state.engine?.addSceneBoard(scene.id, board.id))
                } label: {
                    if board.scenes.contains(scene.id) {
                        Label("\(scene.number)  \(scene.heading)", systemImage: "checkmark")
                    } else {
                        Text("\(scene.number)  \(scene.heading)")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(board.scenes.isEmpty ? "No scenes"
                     : board.scenes.count == 1 ? "1 scene" : "\(board.scenes.count) scenes")
                    .sans(Brand.Size.small)
                MenuMark()
            }
            .foregroundStyle(Brand.ink2(dark))
        }
        // **`.button` and a plain button** — a borderless menu is drawn by
        // AppKit and throws the label's font and ink away, which is why this
        // came out bold and white: louder than the real tags beside it, for
        // the one thing on the line that means *nothing here*. His report,
        // 2026-09-08. See the sidebar heading in `Shell.swift` for the whole
        // story.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .focusEffectDisabled()
        .fixedSize()
        // **Outside the `Menu`, or it is thrown away.** A `.borderlessButton`
        // menu draws its label's *content* and drops what the label puts around
        // it. The background went outside for exactly that reason; the padding
        // never followed, so this chip has been cramped since the day it was
        // written and the comment that used to sit here claimed the opposite.
        // Filter and Sort had the identical fault — see `barFace`.
        .padding(.horizontal, Brand.barPadding)
        .frame(height: Brand.barHeight)
        .barPill(dark, on: false)
        .help("Scenes this board is for")
    }

    @ViewBuilder private var wall: some View {
        if board.media.isEmpty {
            // The empty state names the way in rather than describing what a
            // reference board is for. Drag still works and always did; this is
            // the door for a hand that is not holding a file.
            EmptyState(title: "No pictures yet") {
                AddPicturesMenu(owner: board.id, ownerName: board.name.isEmpty ? "this board" : board.name,
                                state: state)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 46)
        } else {
            // **The wall is `PictureWall` now**, which every gallery in the app
            // shares — his instruction, 2026-08-24: *"all media galleries should
            // borrow these same principles … i shouldn't have to repeat it
            // everytime we make a new one."* Clicking, ⇧ and ⌘, the arrows,
            // carrying, the live shuffle, captions and the tooltip all live
            // there. What a board adds is which pictures, how big, and which
            // other boards one can be moved to.
            PictureWall(pictures: board.media,
                        owner: board.id,
                        state: state,
                        tile: state.boardUnit,
                        ratioMode: board.ratioMode,
                        otherHomes: otherBoards,
                        removeVerb: "Remove from board")
        }
    }

    /// The other boards this picture could hang on instead — the menu half of
    /// dragging one wall's picture onto another.
    private var otherBoards: [(id: String, label: String)] {
        (state.view?.boards ?? [])
            .filter { $0.id != board.id }
            .map { ($0.id, $0.name.isEmpty ? "Untitled" : $0.name) }
    }

}

// ----------------------------------------------------------------- the sheets

/// Naming a board — on the way in, and again when it is renamed.
struct NameBoard: View {
    @ObservedObject var state: ShellState
    /// The board being renamed, or nil when this is a new one.
    var renaming: ViewModel.MoodBoard?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    @State private var name = ""

    var body: some View {
        Sheet(title: renaming == nil ? "Add Reference Board" : "Rename Reference Board",
              width: .narrow) {
            Field("Name") {
                FieldText(placeholder: "Name", text: $name, onSubmit: commit)
            }
        } trailing: {
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button(renaming == nil ? "Add" : "Rename", action: commit)
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear { name = renaming?.name ?? "" }
    }

    private func commit() {
        let wanted = name.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty, let engine = state.engine else { return }
        if let renaming {
            state.replace(engine.renameBoard(renaming.id, name: wanted))
        } else {
            let before = Set((state.view?.boards ?? []).map(\.id))
            state.replace(engine.addBoard(name: wanted))
            // Asked of the engine's answer rather than guessed at from the
            // order — the same way adding a location finds the one it made.
            if let made = (state.view?.boards ?? []).first(where: { !before.contains($0.id) }) {
                state.boardId = made.id
            }
        }
        dismiss()
    }
}
