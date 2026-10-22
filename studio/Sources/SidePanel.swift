import SwiftUI
import AppKit

/// The side panel — script, references and notes, beside the list rather
/// than instead of it.
///
/// His finding: the Notes tab felt wrong, and he was right about why. A tab
/// takes the shot list *away* in order to show you a reference, which is the
/// opposite of what a reference is for — you want the overhead next to the
/// shot it explains. So the three scene-side things share one panel that
/// slides out on the right, opposite the scene list, and **pushes the table
/// aside** rather than floating over the rows you are reading (his call).
///
/// Script was the empty one until 2026-08-22 and is now the scene's own pages,
/// which is why the panel was built around three sections from the start.
struct SidePanel: View {
    @ObservedObject var state: ShellState
    let scene: ViewModel.Scene
    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }

    var body: some View {
        VStack(spacing: 0) {
            head
            Group {
                switch state.panel {
                case .references: ReferenceBoard(state: state, scene: scene)
                case .notes: PanelNotes(state: state, scene: scene)
                case .script: ScriptPane(state: state, scene: scene)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // **Tell the table not to read clicks that land in here** — the same
        // fence the script pane put round itself in Ref 271, moved up to the
        // whole panel because only that one section had it. The table watches
        // the mouse through a monitor that sees the entire window, so a button
        // in References or Notes did its own job *and* whatever sat behind it
        // in the table — sorting a column, most visibly. His report: "certain
        // fields will trigger things behind them like table sorting."
        .background {
            GeometryReader { geo in
                let frame = geo.frame(in: .global)
                Color.clear
                    .onAppear { state.panelFrames["side"] = frame }
                    .onChange(of: frame) { _, now in state.panelFrames["side"] = now }
                    .onDisappear { state.panelFrames.removeValue(forKey: "side") }
            }
        }
    }

    private var head: some View {
        // **The same pills as the sidebar's**, his ask, and it is the right
        // one: two tab strips six inches apart that differ in weight, padding
        // and whether they carry icons read as two different kinds of control
        // when they are the same kind. Label-only, equal widths, the chosen one
        // filled — the sidebar settled on that for the reason it applies here
        // too: three words in a row of capsules read faster than three little
        // pictures, and the icons were doing no work the words were not.
        //
        // **And no close button.** There is one in the top bar, directly above
        // this and always in the same place whether the panel is open or shut.
        // A second one inside the thing it closes is the same fact twice — the
        // count of those cut today is now four.
        HStack(spacing: 4) {
            ForEach(PanelSection.allCases) { section in
                let on = state.panel == section
                Button {
                    state.panel = section
                } label: {
                    // **A sub-tab is a soft-fill pill**, never the top bar's
                    // solid colour — a tab is not a mode. 2026-09-14.
                    Text(section.title)
                        .sans(Brand.Size.body, weight: on ? .semibold : .regular)
                        .foregroundStyle(on ? Brand.ink(dark) : Brand.ink2(dark))
                        .frame(maxWidth: .infinity)
                        .frame(height: Brand.barHeight)
                        .background {
                            Capsule(style: .continuous)
                                .fill(on ? Brand.cellHover(dark) : .clear)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

}

/// **Where "look at this one" lives, and why it is not the view's own.**
/// Ref 268.
///
/// The board's keyboard is installed before the board is on screen — it has to
/// be, or a key pressed first thing lands nowhere — so the closure that
/// handles a key holds a copy of the view that is out of date by the time
/// anybody presses anything. A `@State` on that copy is written by one end and
/// read by nobody. This is the one small place both ends can agree on.
final class BoardFocus: ObservableObject {
    static let shared = BoardFocus()
    @Published var looking: String?
    /// **Which reference sections are shut**, by board id — and `scene` for
    /// the scene's own pictures. It lives here rather than on the view for the
    /// reason `looking` does: a `@State` inside the panel is reachable by
    /// nothing outside it, and a checking run cannot click this panel at all
    /// (its taps land on the container, which is why the picking check drives
    /// `--reference` instead). Out here, `--shutsection` can press it.
    @Published var shut: Set<String> = []


    /// **Installed at app launch, once, and never taken away** — Ref 268.
    ///
    /// Three homes were tried and two were wrong, which is worth writing down
    /// because the second looks right:
    ///
    /// 1. **On the board's `onAppear`** — the original. A key posted before
    ///    the panel had been drawn landed nowhere, so the arrows worked by
    ///    hand and could not be checked. It failed at a one-second settle and
    ///    again at 1.8, which is what says the answer was never a longer wait.
    /// 2. **On the board's `init`** — earlier, and still tied to the view. It
    ///    worked most of the time and dropped the first key or two of a run,
    ///    which is worse than failing: an intermittent check is a check
    ///    nobody can trust.
    /// 3. **Here.** Nothing about it depends on anything being drawn.
    ///
    /// That is only safe because the handler reads nothing from a view: the
    /// current scene, what is picked and what is being looked at all come from
    /// state that outlives any particular drawing of the board. The guard at
    /// the top is what keeps it from answering for a surface nobody is
    /// looking at — not when it was installed.
    /// **Nothing to install any more.** This class carried the second of the
    /// app's two arrow-key monitors, and `WallKeys` — written afterwards, and
    /// saying so in its own header — exists to end exactly that: two local
    /// `keyDown` monitors both claiming ← →, with AppKit handing the event to
    /// whichever was registered later. `checks.sh` measured it at about half
    /// of runs and filed **Ref 333** rather than write a check that asserts a
    /// race.
    ///
    /// The board registers with `WallKeys` like every other wall now. What it
    /// keeps is its own idea of *open*: a reference fills the panel rather than
    /// opening a window, which is the right gesture for a strip this narrow and
    /// is not a thing to tidy away.
    ///
    /// **This does not close Ref 333, and measuring said so.** Three monitors
    /// became two, not one — the table's own is still live on this screen and
    /// still claims ← →, and AppKit hands the event to whichever was installed
    /// later, which depends on when the table happened to be drawn. Measured
    /// 2026-08-29 on five runs of `--panel references --type "→→"`: **three
    /// landed on the second reference and two landed nowhere.** That is the
    /// same coin-flip `checks.sh` recorded, unchanged by this. The question it
    /// is waiting on is still his: with the panel out on References and the
    /// cursor in the table, whose arrows are they?
    static func install() {}
}

/// The scene's references, as a board.
///
/// Images, not files: lighting references, overheads, frames — the things he
/// actually pins to a scene. They read as a wall of pictures you can scan,
/// which is what a mood board is, and this is that scoped to one scene. Click
/// one to fill the panel with it; click again for the wall back.
///
/// **And the boards this scene links, wall and all** — his ask, 2026-08-30:
///
/// > *"right now it just shows a pill that they are linked but the idea is
/// > that the images of that board would appear there. Images from multiple
/// > boards can show up there as well as images that are just assigned to
/// > that and dropped in that window. There should be little headers
/// > separating where the images are from, like the gallery picker window."*
///
/// So the pills are gone and the panel is the picker's shape scoped to one
/// scene: the pictures dropped straight here first, then a section per linked
/// board, each headed by the board's name and its count and shuttable by its
/// heading. The headings appear only when there is more than one place a
/// picture can be from — a scene with no board linked is the wall it always
/// was.
private struct ReferenceBoard: View {
    @ObservedObject var state: ShellState
    let scene: ViewModel.Scene
    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }
    @ObservedObject private var focus = BoardFocus.shared
    @State private var over = false
    /// How many tiles share a row, so ↑ and ↓ can mean something. The board
    /// had ← → only, because nothing measured this.
    @State private var across = 1

    private var pinned: [ViewModel.Attachment] {
        (state.view?.scenes.first { $0.id == scene.id } ?? scene).attachments
    }

    /// This wall's name to the keyboard.
    private var owner: String { "references-" + scene.id }

    private func measure(_ width: CGFloat) {
        guard width.isFinite, width > 0 else { return }
        // 96-point tiles, 8 apart, inside 10 points of padding each side.
        across = max(1, Int((width - 20 + 8) / (96 + 8)))
    }

    /// **What the arrows do here.** Walking and picking are every wall's;
    /// *opening* is this one's own — a reference fills the panel rather than
    /// opening a window.
    private func registerKeys() {
        let refs = shown.map(\.ref)
        WallKeys.shared.register(owner, WallKeys.Wall(
            refs: refs,
            across: { across },
            open: { ref in focus.looking = ref },
            follow: { ref in
                // Only when the panel is already filled with one: an arrow
                // moves what is picked whether or not anything is open, and
                // opening because of an arrow is the opposite of the rule.
                if focus.looking != nil { focus.looking = ref }
            },
            remove: {
                // **Only ever the scene's own.** A linked board's picture is
                // drawn here but belongs to the board, and unpinning it would
                // take it off that wall for every scene hanging it — so Delete
                // skips anything this panel does not own rather than quietly
                // editing a board from the side.
                guard let one = state.pickedPhoto, mine(one) else { return }
                let acting = state.photosActedOn(one).filter(mine)
                if !acting.isEmpty { state.removePhotos(acting) }
            },
            escape: {
                guard focus.looking != nil else { return false }
                focus.looking = nil
                return true
            }))
    }

    var body: some View {
        Group {
            if let ref = focus.looking,
               let one = sections.flatMap(\.items).first(where: { $0.ref == ref }) {
                whole(one)
            } else {
                board
            }
        }
        // **No ground of its own.** This painted `surface` over the panel's
        // glass — and only as wide as its content, so an empty board stood
        // as a white column down the middle of a panel that was not quite
        // white. His report, 2026-09-15: "an off-colored internal panel".
        // The panel is the ground; this draws on it.
        // **One keyboard, shared with every other wall** — see `BoardFocus`.
        .onHover { inside in
            if inside { WallKeys.shared.active = owner }
        }
        .onAppear { registerKeys() }
        .onChange(of: shown.map(\.ref)) { _, _ in registerKeys() }
        .onChange(of: focus.looking) { _, _ in registerKeys() }
        .onDisappear { WallKeys.shared.forget(owner) }
        .onDrop(of: [.fileURL, .image, .movie], isTargeted: $over) { providers in
            Attachments.take(providers, onto: scene, state: state)
        }
        .overlay {
            if over {
                RoundedRectangle(cornerRadius: Brand.radiusChip)
                    .strokeBorder(Brand.accent(dark), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .padding(6)
            }
        }
    }

    /// ← → walk the board, space opens what is picked, Escape puts it away.
    /// The same grammar as the photograph wall, because they are the same
    /// gesture on two walls and his hands should not have to know which. The
    /// keyboard itself lives on `BoardFocus`, installed at launch — see there
    /// for why it cannot live on this view.

    /// The scene's own linked mood boards — his call, 2026-08-23 (Ref
    /// SL-348). This panel is the working surface beside the shot list, so
    /// this is where a link gets made or jumped to day to day; the scene
    /// editor sheet carries the same list for when the details are open
    /// anyway.
    private var linkedBoards: [ViewModel.MoodBoard] {
        let ids = (state.view?.scenes.first { $0.id == scene.id } ?? scene).boards
        let all = state.view?.boards ?? []
        return ids.compactMap { id in all.first { $0.id == id } }
    }

    /// One heading and the pictures under it. Either the scene's own — the
    /// only ones this panel may edit — or a board it links.
    private struct Wall: Identifiable {
        let id: String
        let label: String
        let items: [ViewModel.Attachment]
        /// The board this is a wall of; nothing for the scene's own pictures.
        let board: ViewModel.MoodBoard?
        var own: Bool { board == nil }
    }

    private var sections: [Wall] {
        [Wall(id: "scene", label: "This scene", items: pinned, board: nil)]
        + linkedBoards.map {
            Wall(id: $0.id, label: $0.name.isEmpty ? "Untitled" : $0.name,
                 items: $0.media, board: $0)
        }
    }

    /// **A heading earns its place only when there is more than one source.**
    /// A scene with no board linked has nothing to separate, and a lone
    /// "This scene" over the only wall in the panel is a label naming the
    /// thing you are already standing in.
    private var headed: Bool { sections.count > 1 }

    /// Everything starts open — he linked the board in order to see it. What
    /// a hand has shut lives on `BoardFocus`; see there for why.
    private func open(_ wall: Wall) -> Bool { !focus.shut.contains(wall.id) }
    private func flip(_ wall: Wall) {
        if focus.shut.contains(wall.id) {
            focus.shut.remove(wall.id)
        } else {
            focus.shut.insert(wall.id)
        }
    }

    /// Every picture on screen, in the order they are drawn — what the arrows
    /// walk, and what a ⇧-click reaches across.
    private var shown: [ViewModel.Attachment] {
        sections.filter(open).flatMap(\.items)
    }

    /// Whether a picture is the scene's own, which is the only kind this panel
    /// is allowed to take away.
    private func mine(_ ref: String) -> Bool { pinned.contains { $0.ref == ref } }

    /// Linking a board is still done from here — it is the surface beside the
    /// shot list, where the day-to-day linking happens.
    /// **Left-aligned, where every other line in this panel starts.** It was
    /// pushed to the right edge on a line of its own with nothing beside it
    /// and a gap under it before the empty state — his report, 2026-09-08:
    /// *"the link board button … is in a strange place and not in line with
    /// the rest of the stuff."* When there is nothing here at all it does not
    /// get a line: it is the empty state's own action, like every other empty
    /// state in the app.
    private var linkRow: some View {
        HStack(spacing: 6) {
            linkMenu
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    private var linkMenu: some View {
        let linkedIds = Set(linkedBoards.map(\.id))
        let rest = (state.view?.boards ?? []).filter { !linkedIds.contains($0.id) }
        return Group {
            Menu {
                ForEach(rest) { candidate in
                    Button(candidate.name.isEmpty ? "Untitled" : candidate.name) {
                        state.replace(state.engine?.addSceneBoard(scene.id, candidate.id))
                    }
                }
                if rest.isEmpty {
                    Text(linkedBoards.isEmpty ? "No reference boards yet" : "All boards linked")
                }
            } label: {
                PlusLabel(text: "Link board", dark: dark, size: Brand.Size.small)
                    .rowAction(dark)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .focusEffectDisabled()
            .fixedSize()
            .help("Link a reference board")
        }
    }

    /// **The picker's heading, at this size.** Chevron, what kind of thing it
    /// is, its name, its count — and the whole row is the hit target, because
    /// a chevron this small is a miss waiting to happen.
    private func heading(_ wall: Wall) -> some View {
        let showing = open(wall)
        return HStack(spacing: 6) {
            Image(systemName: showing ? "chevron.down" : "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Brand.ink4(dark))
                .frame(width: 9)
            Text(wall.label)
                .fieldLabel(dark)
                .lineLimit(1).truncationMode(.middle)
            Text("\(wall.items.count)").sans(Brand.Size.tiny).monospacedDigit()
                .foregroundStyle(Brand.ink4(dark))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        // A pinned head needs something under it as rows scroll past —
        // the glass's own tone (measured: F9F9F9 / 171719), not the well's
        // white.
        .background(Brand.surface3(dark))
        .contentShape(Rectangle())
        .onTapGesture { flip(wall) }
        .contextMenu {
            if let moodBoard = wall.board {
                Button("Open this board") {
                    state.boardId = moodBoard.id
                    state.sideTab = .boards
                }
                Button("Unlink", role: .destructive) {
                    state.replace(state.engine?.removeSceneBoard(scene.id, moodBoard.id))
                }
            }
        }
    }

    private func grid(_ wall: Wall) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
            ForEach(wall.items) { one in
                tile(one, own: wall.own)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, headed ? 2 : 10)
    }

    private var board: some View {
        ScrollView {
            if !headed && pinned.isEmpty {
                // Full width, so the empty state is centred in the panel and
                // not in a column the width of its own words.
                EmptyState(title: "Drop references here", compact: true) {
                    linkMenu
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
                linkRow
                LazyVStack(alignment: .leading, spacing: 8,
                           pinnedViews: headed ? [.sectionHeaders] : []) {
                    ForEach(sections) { wall in
                        SwiftUI.Section {
                            if open(wall) {
                                if wall.items.isEmpty {
                                    Text(wall.own ? "Drop references here" : "Nothing on this board")
                                        .sans(11).foregroundStyle(Brand.ink4(dark))
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                } else {
                                    grid(wall)
                                }
                            }
                        } header: {
                            if headed { heading(wall) }
                        }
                    }
                }
                .padding(.top, headed ? 6 : 0)
                .padding(.bottom, 10)
                .background(
                    GeometryReader { box in
                        Color.clear
                            .onAppear { measure(box.size.width) }
                            .onChange(of: box.size.width) { _, now in measure(now) }
                    }
                )
            }
        }
        .frame(maxWidth: .infinity)
        .onChange(of: focus.shut) { _, _ in registerKeys() }
    }

    private func tile(_ one: ViewModel.Attachment, own: Bool = true) -> some View {
        VStack(spacing: 4) {
            ZStack {
                // A picture is never rounded (his rule, 2026-10-07).
                Rectangle().fill(Brand.surface2(dark))
                if Frames.something(one.hash, one.filename, state.engine,
                                    kind: one.kind) {
                    Frames.view(one.hash, one.filename, engine: state.engine,
                                trimStart: one.trimStart, trimEnd: one.trimEnd,
                                kind: one.kind, framing: one.framing, arrows: one.marks)
                } else {
                    // **The one answer to "no picture here"** — Ref 224. This
                    // drew a plain `doc` glyph until 2026-08-29, which is the
                    // shape of the bug that had him deleting real photographs:
                    // a frame with a record and no file looked exactly like one
                    // still coming down from iCloud. `Frames.gap` tells them
                    // apart, and every other wall in the app already used it.
                    Frames.gap(one.hash, dark: dark, small: true)
                }
            }
            .frame(height: 72)
            .clipShape(Rectangle())
            Text(one.filename).sans(10).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(Brand.ink3(dark))
        }
        // **The same hands as the photograph wall.** His ask (Ref 151): a click
        // points, a double-click looks, the arrows walk, ⌘ and ⇧ build a set.
        // Two before one, because SwiftUI hands a tap to the first recogniser
        // that can take it and a single-tap declared first swallows the first
        // half of every double-click.
        .overlay {
            Rectangle()
                .strokeBorder(state.isPicked(one.ref) ? Brand.accent(dark) : .clear,
                              lineWidth: 2.5)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            state.pick(photo: one.ref, among: shown.map(\.ref))
            focus.looking = one.ref
        }
        .onTapGesture {
            state.pick(photo: one.ref, among: shown.map(\.ref))
        }
        .contextMenu {
            Button("Open in another app") { Attachments.open(one, state: state) }
            if own {
                Divider()
                let acting = state.photosActedOn(one.ref).filter(mine)
                Button(acting.count <= 1 ? "Unpin" : "Unpin \(acting.count) references",
                       role: .destructive) {
                    state.removePhotos(acting.isEmpty ? [one.ref] : acting)
                }
            }
        }
        .help(one.filename)
    }

    /// One reference filling the panel — the whole picture, never cropped,
    /// with the way back where a hand expects it.
    private func whole(_ one: ViewModel.Attachment) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    focus.looking = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                        Text("All references").sans(11)
                    }
                    .foregroundStyle(Brand.ink2(dark))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Text(one.filename).sans(11).foregroundStyle(Brand.ink3(dark))
                    .lineLimit(1).truncationMode(.middle)
                // Anything our own board cannot draw well — a PDF, a clip —
                // is the Mac's job, not ours. We had a whole reader for this
                // once; it was more app than the job deserves.
                Button {
                    Attachments.open(one, state: state)
                } label: {
                    Image(systemName: "arrow.up.forward.app").font(.system(size: 11))
                        .foregroundStyle(Brand.ink3(dark))
                }
                .buttonStyle(.plain)
                .help("Open in another app")
            }
            .padding(.horizontal, 10).padding(.vertical, 8)

            if Frames.something(one.hash, one.filename, state.engine) {
                Frames.view(one.hash, one.filename, engine: state.engine, fill: false,
                            trimStart: one.trimStart, trimEnd: one.trimEnd)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(8)
            } else {
                Text("Not a picture")
                    .sans(Brand.Size.small).foregroundStyle(Brand.ink4(dark))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// The scene's words, in the panel. The same two-fields-together writing the
/// tab did: plain for everything else to read, rich for here.
private struct PanelNotes: View {
    @ObservedObject var state: ShellState
    let scene: ViewModel.Scene
    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }
    private var font: NSFont { .systemFont(ofSize: 12.5) }
    private var ink: NSColor { dark ? .white : .black }

    @State private var words = NSAttributedString(string: "")
    @State private var filledFrom: String?

    var body: some View {
        RichText(attributed: $words, font: font, colour: ink, onCommit: { write($0) })
            .padding(10)
            .overlay(alignment: .topLeading) {
                if words.string.isEmpty {
                    Text("Add a note")
                        .sans(13).foregroundStyle(Brand.ink4(dark))
                        .padding(.horizontal, 14).padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .onAppear { fill() }
            .onChange(of: scene.id) { _, _ in fill() }
    }

    private func fill() {
        let live = state.view?.scenes.first { $0.id == scene.id } ?? scene
        words = Rich.decode(live.notesRich ?? "", plain: live.notes, font: font, colour: ink)
        filledFrom = scene.id
    }

    private func write(_ text: NSAttributedString) {
        guard let engine = state.engine, filledFrom == scene.id else { return }
        state.replace(engine.setMany(shots: [scene.id], field: "notes", value: text.string))
        state.replace(engine.setMany(shots: [scene.id], field: "notes_rich",
                                     value: text.length == 0 ? "" : Rich.encode(text)))
    }
}
