import AppKit
import SwiftUI

/// **Every wall of pictures in this app, and the rules they all obey.**
///
/// His instruction, 2026-08-24, and it is the reason this file exists rather
/// than a fourth copy of a grid:
///
/// > *"all media galleries should borrow these same principles (as well as the
/// > ones you've built) and i shouldn't have to repeat it everytime we make a
/// > new one."*
///
/// So the behaviours below are **not** a mood board feature. They are what a
/// wall of pictures does in Shotlister, wherever it is drawn:
///
/// - **A click picks**, and draws the blue box. ⌘ adds or takes away, ⇧ reaches
///   from the last one picked to this one. Finder's grammar, which his hands
///   already know.
/// - **Double-click opens** the picture, big enough to read.
/// - **Arrow keys walk** the wall — ← → by one, ↑ ↓ by a row — and the viewer
///   follows if it is open. Space or Return opens; Escape closes.
/// - **A picture can be carried** to a new place in the order, and the wall
///   *shuffles under the hand* to show where it will land.
/// - **A picture can be dragged to another owner** — one board to another —
///   carrying its caption and its name, because it is the same use of the file.
/// - **A caption sits under it** when it has one, and travels into the viewer.
/// - **Right-click acts on everything picked**, not just the one under the
///   cursor, and says how many.
/// - **The filename is the tooltip.** No picture is a mystery on hover.
/// - **A missing file says so** through `Frames.gap` — never a bare grey
///   rectangle, which is how real photographs once got deleted (Ref 224).
///
/// **If you are building a new gallery: use this.** Do not write a grid, a
/// selection outline, or a key monitor of your own — they will drift, and he
/// will have to ask for the same nine things again. What a caller supplies is
/// *what the pictures are and who owns them*; everything above comes free.
///
/// The one thing deliberately left out is **sizing per picture**. It was built
/// and he had it taken out again on 2026-08-24: a wall reads as one thing, and
/// four sizes of tile made it read as a mess. A wall has one tile size, which
/// the caller scales.

// MARK: - which wall the keyboard is talking to

/// **Only one wall answers the arrow keys**: the one last pointed at.
///
/// A single monitor installed once at launch, rather than one per wall
/// appearing and disappearing. Two local `keyDown` monitors race — the
/// references panel and the table have been fighting over ← → for weeks
/// (`checks.sh` records that the board wins about half of runs) — so this
/// registers walls in a table and asks the frontmost one.
@MainActor
final class WallKeys {
    static let shared = WallKeys()
    private var installed = false

    /// **The wall last pointed at** — which is what the line above has always
    /// claimed, and what the code did not do until 2026-08-29. `active` was
    /// *cleared* the moment the pointer left the grid, so moving the mouse onto
    /// the pop-out you were looking at — or onto the wall's own size slider —
    /// stopped the arrow keys dead while a picture was still visibly selected.
    /// The keyboard belongs to the wall you are working, not to wherever the
    /// mouse happens to be resting.
    ///
    /// It is given up when that wall goes away (`forget`) or when another wall
    /// is pointed at, and not before.
    var active: String?
    private var walls: [String: Wall] = [:]

    struct Wall {
        var refs: [String]
        var across: () -> Int
        var open: (String) -> Void
        var follow: (String) -> Void
        /// **⌫ asks first.** His ask, Ref 388. The wall owns the asking,
        /// because an alert is a view's to put up, not a monitor's.
        var remove: () -> Void = {}
        /// Escape, when this wall has something of its own to put away.
        /// **True means handled**; false falls through to closing the pop-out.
        var escape: () -> Bool = { false }
    }

    func register(_ id: String, _ wall: Wall) { walls[id] = wall }
    func forget(_ id: String) {
        walls.removeValue(forKey: id)
        if active == id { active = nil }
    }

    /// Installed once, from `applicationWillFinishLaunching`. The pattern is
    /// `BoardFocus.install`'s (Ref 268) and for the same reason: a monitor
    /// installed when a view appears can be too late for the first key, and
    /// SwiftUI can call `onAppear` before the previous `onDisappear`, which
    /// leaks a monitor per scroll.
    func install() {
        guard !installed else { return }
        installed = true
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.handle(event) }
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        // Anything with a keyboard of its own keeps it — a name being typed, a
        // caption being written, a search being narrowed.
        if let responder = NSApp.keyWindow?.firstResponder,
           responder is NSTextView || responder is NSTextField {
            return event
        }
        // **The wall last pointed at — or the only one there is.**
        //
        // A wall that has never been pointed at still answers when it is the
        // only one registered, which is how the references board worked before
        // it joined this monitor: it was gated on the panel being out, not on
        // the mouse, and `--panel references --type "\u{2192}"` drives it with
        // no pointer at all. With more than one wall on screen and none pointed
        // at, nothing answers — that is **Ref 333**, and it is his question to
        // settle, not one to guess at by taking whichever registered last.
        let only = walls.count == 1 ? walls.first?.key : nil
        guard let id = active.flatMap({ walls[$0] != nil ? $0 : nil }) ?? only,
              let wall = walls[id], !wall.refs.isEmpty else { return event }
        let here = ShellState.shared
        let refs = wall.refs
        let at = refs.firstIndex { $0 == here.pickedPhoto }

        func land(_ index: Int) -> NSEvent? {
            let clamped = min(max(index, 0), refs.count - 1)
            // An arrow means *this one*, so it also lets go of a set.
            here.pickedPhotos = []
            here.pickedPhoto = refs[clamped]
            wall.follow(refs[clamped])
            return nil
        }

        let across = max(wall.across(), 1)
        // **Matched on the letter as well as the key code.** A real space bar
        // arrives as key 49; a checking typist sends every ordinary character
        // with a key code of 0 and the letter in hand, so a rule written on the
        // code alone works under a finger and silently does nothing under a
        // check — the worst of the two ways round.
        let typed = event.charactersIgnoringModifiers ?? ""
        // **Matched on the arrow's own character as well as its key code**, for
        // the reason written under the space bar below: a hand sends key 123,
        // a checking typist can send the character with a key code of nought,
        // and a rule written on one of the two works under exactly one of them.
        switch (event.keyCode, typed) {
        case (123, _), (_, "\u{F702}"), (_, "←"): return land((at ?? 0) - 1)
        case (124, _), (_, "\u{F703}"), (_, "→"): return land(at == nil ? 0 : at! + 1)
        case (126, _), (_, "\u{F700}"), (_, "↑"): return land((at ?? 0) - across)
        case (125, _), (_, "\u{F701}"), (_, "↓"): return land(at == nil ? 0 : at! + across)
        case (51, _), (117, _):                              // ⌫ and ⌦
            wall.remove()
            return nil
        case (53, _):                                        // Escape
            if wall.escape() { return nil }
            if Viewer.shared.isOpen { Viewer.shared.close(); return nil }
            return event
        default:
            guard event.keyCode == 49 || event.keyCode == 36
                    || typed == " " || typed == "\r" else { return event }
            guard let at, at < refs.count else { return event }
            wall.open(refs[at])
            return nil
        }
    }
}

// MARK: - the wall

/// One wall of pictures. See the note at the top of this file before changing
/// anything here — these behaviours are shared by every gallery in the app.
struct PictureWall: View {
    /// What is on the wall, in the order it hangs.
    let pictures: [ViewModel.Attachment]
    /// Who owns these uses — a board, a location, a scene, a shot. Used for
    /// drops, and as the wall's identity for the keyboard.
    let owner: String
    @ObservedObject var state: ShellState

    /// How wide one tile is.
    var tile: CGFloat = 152
    /// `original` keeps each picture's own shape; `square` and `project` fill
    /// and crop, the trade the storyboard's cards already make.
    var ratioMode: String = "original"
    /// Whether the words under a picture are drawn. A strip 72 points tall has
    /// no room for them; a wall does.
    var showCaptions: Bool = true
    /// Where else this same use could be hung, offered in the context menu and
    /// as a drop target. Empty means it cannot be moved.
    var otherHomes: [(id: String, label: String)] = []
    /// What to say in the alert when a picture is taken off this wall.
    var removeVerb: String = "Remove from board"
    /// **Somewhere else this owner's files really live**, offered in the
    /// viewer's menu. A location knows its Google Drive folder; a mood board
    /// has nothing to add and leaves this alone. Called only when a subject is
    /// actually built, because finding them walks a network-backed folder.
    var alsoAt: (ViewModel.Attachment) -> [Viewer.Place] = { _ in [] }

    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    /// Where each tile is sitting, so a carried picture can be dropped **on**
    /// another rather than guessed at from how far the hand travelled.
    @State private var places: [String: CGRect] = [:]
    @State private var carrying: String?
    @State private var carried: CGSize = .zero
    /// The picture the hand is currently over while carrying — what the wall
    /// shuffles around to show where the drop will land.
    @State private var hoveringOver: String?
    /// The pictures ⌫ is asking about. Empty when it is not asking.
    @State private var removing: [String] = []
    @State private var captioning: String?
    @State private var written = ""
    @State private var across = 1

    /// **The order the wall draws while a picture is in the hand.**
    ///
    /// His ask: *"when reordering you should see the shuffle of the images move
    /// in response to where you are hovering."* So the wall does not wait for
    /// the drop — it lays itself out as though the drop had already happened,
    /// and animates into it. The engine is not told anything until the hand
    /// lets go.
    private var order: [ViewModel.Attachment] {
        guard let carrying, let hoveringOver, carrying != hoveringOver,
              let from = pictures.firstIndex(where: { $0.ref == carrying })
        else { return pictures }
        var shuffled = pictures
        let moving = shuffled.remove(at: from)
        guard let onto = shuffled.firstIndex(where: { $0.ref == hoveringOver })
        else { return pictures }
        shuffled.insert(moving, at: onto)
        return shuffled
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: tile), spacing: 10, alignment: .top)],
                  alignment: .leading, spacing: 10) {
            ForEach(order) { picture in
                cell(picture)
            }
        }
        .coordinateSpace(name: wallSpace)
        .onPreferenceChange(TileFrames.self) { places = $0 }
        .background(
            GeometryReader { box in
                Color.clear
                    .onAppear { measure(box.size.width) }
                    .onChange(of: box.size.width) { measure($0) }
            }
        )
        // The wall the arrows are talking to is the one the pointer is in.
        // Pointing at a wall hands it the keyboard. **Pointing away does not
        // take it back** — see `WallKeys.active`.
        .onHover { inside in
            if inside { WallKeys.shared.active = owner }
        }
        .onAppear { registerKeys() }
        .onChange(of: pictures.map(\.ref)) { _ in registerKeys() }
        .onDisappear { WallKeys.shared.forget(owner) }
        .animation(.easeOut(duration: 0.16), value: order.map(\.ref))
        .sheet(isPresented: Binding(get: { captioning != nil },
                                   set: { if !$0 { captioning = nil } })) {
            captionSheet
        }
        // **Backspace asks before it takes anything off the wall** — Ref 388,
        // his ask. The sentence earns its place under the copy law: it says
        // what the delete costs, which is the one thing a button label cannot.
        .alert(removing.count == 1 ? "Remove this picture?"
                                   : "Remove \(removing.count) pictures?",
               isPresented: Binding(get: { !removing.isEmpty },
                                    set: { if !$0 { removing = [] } })) {
            Button("Cancel", role: .cancel) { removing = [] }
            Button(removeVerb, role: .destructive) {
                state.removePhotos(removing)
                removing = []
            }
        }
    }

    private var wallSpace: String { "wall-\(owner)" }

    private func measure(_ width: CGFloat) {
        guard width.isFinite, width > 0 else { return }
        across = max(1, Int((width + 10) / (tile + 10)))
        // **Said out loud, or the report lies.** `--locations` prints this and
        // it was never written by anybody, so it printed `across: 1` whatever
        // the wall was doing. A green check that cannot change is worse than
        // no check.
        state.photosAcross = across
    }

    private func registerKeys() {
        WallKeys.shared.register(owner, WallKeys.Wall(
            refs: pictures.map(\.ref),
            across: { across },
            open: { ref in
                guard let picture = pictures.first(where: { $0.ref == ref }) else { return }
                Viewer.shared.show(subject(picture), state: state)
            },
            follow: { ref in
                guard let picture = pictures.first(where: { $0.ref == ref }) else { return }
                Viewer.shared.follow(subject(picture), state: state)
            },
            remove: {
                guard let one = state.pickedPhoto else { return }
                let acting = state.photosActedOn(one)
                if !acting.isEmpty { removing = acting }
            }))
    }

    /// What the viewer is asked to show. **Built by `Viewer.subject`, which is
    /// the only builder now** — there were three and they disagreed about
    /// whether the bar got a count, a caption or a Show-in-Finder item.
    private func subject(_ picture: ViewModel.Attachment) -> Viewer.Subject {
        // `alsoAt` is handed over **unevaluated**: a location's answer walks
        // Google Drive, and building it here would put that walk on every
        // double-click and every arrow key.
        Viewer.subject(picture, among: pictures,
                       alsoAt: { alsoAt(picture) }, state: state)
    }

    // MARK: one picture

    private func cell(_ picture: ViewModel.Attachment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            frame(picture)
            if showCaptions && !picture.caption.isEmpty {
                Text(picture.caption)
                    .sans(11)
                    .foregroundStyle(Brand.ink3(dark))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(
            GeometryReader { box in
                Color.clear.preference(key: TileFrames.self,
                                       value: [picture.ref: box.frame(in: .named(wallSpace))])
            }
        )
    }

    private func frame(_ picture: ViewModel.Attachment) -> some View {
        // The sizer is a `Color.clear` and the picture an overlay, which is the
        // whole trick: a 4000-pixel photograph inside a stack decides the stack
        // is 4000 points wide and bursts out of its column. An overlay cannot
        // vote on size; it is handed one.
        Color.clear
            .aspectRatio(shape(picture), contentMode: .fit)
            .overlay {
                if Frames.something(picture.hash, picture.filename, state.engine,
                                    kind: picture.kind) {
                    Frames.view(picture.hash, picture.filename,
                                engine: state.engine, fill: ratioMode != "original",
                                trimStart: picture.trimStart, trimEnd: picture.trimEnd,
                                kind: picture.kind, framing: picture.framing, arrows: picture.marks)
                } else {
                    // The one answer to "no picture here" — Ref 224.
                    Frames.gap(picture.hash, dark: dark)
                }
            }
            .background(Brand.surface2(dark))
            .clipped()
            .overlay {
                Rectangle().strokeBorder(
                    state.isPicked(picture.ref) ? Brand.accent(dark) : Brand.rule(dark),
                    lineWidth: state.isPicked(picture.ref) ? 2.5 : 1)
            }
            .overlay {
                if state.isPicked(picture.ref) {
                    Rectangle().strokeBorder(Brand.accent(dark).opacity(0.35), lineWidth: 1)
                        .padding(-3)
                }
            }
            .contentShape(Rectangle())
            .offset(carrying == picture.ref ? carried : .zero)
            .zIndex(carrying == picture.ref ? 1 : 0)
            .opacity(carrying == picture.ref ? 0.75 : 1)
            // **One gesture decides click, shift-click and carry.**
            //
            // It was three, and shift-click did not work: a `DragGesture` and
            // two `onTapGesture`s on one view leave SwiftUI to guess which owns
            // the press, and with a modifier held it guessed wrong — his
            // report, *"click then hold shift and click again should select
            // multiple images"*. A single drag gesture with no minimum distance
            // sees every press itself: it is a click if the hand did not
            // travel, and a carry if it did. Nothing to arbitrate.
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(wallSpace))
                    .onChanged { drag in
                        guard hypot(drag.translation.width, drag.translation.height) > 5
                        else { return }
                        carrying = picture.ref
                        carried = drag.translation
                        hoveringOver = places.first { $0.value.contains(drag.location) }?.key
                    }
                    .onEnded { drag in
                        let travelled = hypot(drag.translation.width, drag.translation.height)
                        defer { carrying = nil; carried = .zero; hoveringOver = nil }
                        guard travelled > 5 else {
                            // **The second press opens it.** This gesture sees
                            // every press itself, so the count has to be read
                            // here — see the note under `.onTapGesture` below
                            // for why a count-2 tap alongside it never fired.
                            if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
                                state.pickedPhoto = picture.ref
                                Viewer.shared.show(subject(picture), state: state)
                            } else {
                                click(picture)
                            }
                            return
                        }
                        guard let onto = places.first(where: { $0.value.contains(drag.location) })?.key,
                              onto != picture.ref else { return }
                        state.moveWallPicture(picture.ref, before: onto,
                                              among: pictures.map(\.ref))
                    }
            )
            // **There is no count-2 tap here any more, and there never could
            // have been.** The comment that used to sit here said a count-2 tap
            // and the drag above "do not fight". They do: a `DragGesture` with
            // `minimumDistance: 0` recognises on mouse-*down* and takes the
            // press, so the second click never reached the tap and
            // double-clicking a photograph on a wall did nothing at all.
            //
            // Nobody caught it because nothing could: `--openphoto` calls
            // `Viewer.show` directly and the space bar goes through `WallKeys`,
            // so both halves of the *code* were green while the **gesture** was
            // dead. Found 2026-08-29 by posting a real double-click with
            // `--tap "x,y,2"`, and confirmed against the build from before any
            // of this work — it failed there too, so it had been broken for as
            // long as the shared wall has existed (Ref 150 says otherwise).
            //
            // The click count is read inside the drag instead, which is the
            // idiom the storyboard card already uses and which works.
            // **Out of this wall and onto another** — his ask. Real
            // drag-and-drop, because the destination is a different view
            // altogether (a row in the sidebar), which a `DragGesture` inside
            // this one can never reach. The context menu below does the same
            // job for a hand that would rather not drag, and is the half a
            // check can press: a synthetic mouse cannot start a drag session.
            .onDrag {
                state.pickedPhoto = picture.ref
                return NSItemProvider(object: picture.ref as NSString)
            }
            .contextMenu { menu(picture) }
            .help(picture.filename)
    }

    private func shape(_ picture: ViewModel.Attachment) -> CGFloat {
        switch ratioMode {
        case "square": return 1.0
        case "project": return CGFloat(state.view?.project.ratio ?? 2.39)
        default: return picture.shape ?? 4.0 / 3.0
        }
    }

    /// A press that did not travel. ⌘ and ⇧ are read here, off the event
    /// system, because a gesture does not carry them.
    private func click(_ picture: ViewModel.Attachment) {
        state.pick(photo: picture.ref, among: pictures.map(\.ref))
        Viewer.shared.follow(subject(picture), state: state)
    }

    @ViewBuilder private func menu(_ picture: ViewModel.Attachment) -> some View {
        // **The same window a double-click gives.** This went through
        // `Attachments.read`, which built a bare subject — so *Open here* and
        // a double-click on the same photograph opened two different-looking
        // windows, one with the count, the caption and Show in Finder and one
        // with none of them.
        Button("Open here") {
            state.pickedPhoto = picture.ref
            Viewer.shared.show(subject(picture), state: state)
        }
        Button("Open in another app") { Attachments.open(picture, state: state) }
        Divider()
        Button(picture.caption.isEmpty ? "Add caption…" : "Edit caption…") {
            captioning = picture.ref
            written = picture.caption
        }
        if !otherHomes.isEmpty {
            Divider()
            Menu("Move to") {
                ForEach(otherHomes, id: \.id) { home in
                    Button(home.label) {
                        for ref in state.photosActedOn(picture.ref) {
                            state.replace(state.engine?.movePicture(ref, to: home.id))
                        }
                    }
                }
            }
        }
        Divider()
        // What "these" means is decided in one place — right-clicking a picture
        // outside the picked set acts on that one.
        let acting = state.photosActedOn(picture.ref)
        Button(acting.count == 1 ? removeVerb : "Remove \(acting.count) pictures",
               role: .destructive) {
            state.removePhotos(acting)
        }
    }

    private var captionSheet: some View {
        Sheet(title: "Caption", width: .narrow) {
            Field("Caption") {
                FieldText(placeholder: "", text: $written)
            }
        } trailing: {
            Button("Cancel") { captioning = nil }.keyboardShortcut(.cancelAction)
            Button("Save") {
                if let ref = captioning {
                    state.replace(state.engine?.caption(ref, written))
                }
                captioning = nil
            }
            .buttonStyle(.primary)
            .keyboardShortcut(.defaultAction)
        }
    }
}

/// Where every tile on a wall is, gathered as it lays out. One dictionary
/// rather than a preference per tile, so a wall of two hundred pictures is one
/// read when a picture is let go.
struct TileFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - the controls every wall's header wears

/// **One shared look for what sits above a wall.** His instruction,
/// 2026-08-24: *"galleries across the board should share same button type…
/// let's use Locations and its layout as our go-to."* Locations had the
/// quieter of the two looks already — an icon, no filled well — so these
/// three are built to it rather than to the pills mood boards tried first.
///
/// A caller supplies the state; nothing here reads or writes it. `RatioMenu`
/// and `AddPicturesMenu` both take a plain closure for the same reason
/// `PictureWall` takes `pictures` and `owner` rather than reaching into
/// `ShellState` itself — a gallery header should not have to know which kind
/// of owner it is drawing for.
struct RatioMenu: View {
    @Binding var mode: String
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    static let choices: [(String, String)] = [
        ("original", "Original shape"),
        ("square", "Square"),
        ("project", "Project ratio"),
    ]

    var body: some View {
        Menu {
            Picker("", selection: $mode) {
                ForEach(Self.choices, id: \.0) { value, said in
                    Text(said).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Brand.ink2(dark))
                .frame(width: Brand.barHeight, height: Brand.barHeight)
                .overlay {
                    Capsule(style: .continuous).strokeBorder(Brand.rule2(dark), lineWidth: 1)
                }
                .contentShape(Capsule(style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .focusEffectDisabled()
        .fixedSize()
        .help("How pictures fill their tile")
    }
}

/// One tile size for the whole wall, scaled together — the storyboard's card
/// slider, doing the same job here. Per-picture sizing was built and taken
/// out again the same day: a wall reads as one thing.
struct TileSizeSlider: View {
    @Binding var value: CGFloat
    var range: ClosedRange<CGFloat> = 96...300
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        SizeSlider(small: "square.grid.3x3", large: "square.grid.2x2") {
            Slider(value: $value, in: range)
        }
        .help("How big the pictures are")
    }
}

/// **Both doors, in Locations' words.** A picture already in the film, or one
/// off the disk — Ref 228. Every gallery in the app takes both now.
struct AddPicturesMenu: View {
    let owner: String
    let ownerName: String
    @ObservedObject var state: ShellState
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        Menu {
            Button("Choose file…") {
                Attachments.addViaPanel(ownedBy: owner,
                                        message: "Add pictures to \(ownerName)",
                                        state: state)
            }
            Button("Already in this project") { state.pickingPictureFor = owner }
        } label: {
            PlusLabel(text: "Add pictures", dark: dark).rowAction(dark)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .focusEffectDisabled()
        .fixedSize()
    }
}
