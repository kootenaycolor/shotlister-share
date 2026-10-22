import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// **The frames windows** — plural, since 2026-08-20.
///
/// Cadrage draws this as a page that takes the whole content area (reference:
/// `cadrage-studio-references`, 12.21.59). Nathaniel's call improved on that
/// with a floating window he can move and size, never a takeover. His three
/// notes today improve on it again, and they are all one idea: *a frames window
/// is a pair of eyes, not a document.*
///
/// - **It follows what you are looking at.** An open window shows the shot the
///   cursor is on and changes when the cursor does. It was pinned to whichever
///   shot happened to open it, which meant walking the list left it showing
///   something you had stopped caring about.
/// - **Unless you pin it.** One button, and it stops following.
/// - **So there can be more than one.** Pin the frame you are matching to,
///   then let a second window follow you down the list. That is the whole
///   reason the first two changes are worth having, and it is why this is a
///   *set* of windows now rather than a singleton.
final class FrameWindows: NSObject, NSWindowDelegate {
    static let shared = FrameWindows()

    /// One window's own mind.
    final class Eye: ObservableObject, Identifiable {
        let id = UUID()
        /// The shot this window has been pinned to. **Nil means it follows the
        /// cursor** — the default, because following is the common case and
        /// pinning is the deliberate one.
        @Published var pinned: String?
        /// Which of that shot's frames is being looked at.
        @Published var selected: String?
        /// **Print Frame mode**: this same window turned into the shot's
        /// Print Frame editor. One window, his note 2026-10-14: it opened a
        /// second one, and leaving meant closing two.
        @Published var printing = false

        /// The shot on screen: the pin if there is one, the cursor otherwise.
        func shot(_ state: ShellState) -> String? { pinned ?? state.cursorShot }
    }

    private var eyes: [UUID: (window: NSWindow, eye: Eye)] = [:]
    /// The size a window had before Print Frame grew it, to go back to.
    private var before: [UUID: NSRect] = [:]

    /// Print Frame wants a board, a strip and an inspector: the window grows
    /// to fit them on its own screen, and goes back to its size after.
    func fit(_ eye: Eye, printing: Bool) {
        DispatchQueue.main.async { [self] in
            guard let w = eyes[eye.id]?.window else { return }
            if !printing {
                if let was = before.removeValue(forKey: eye.id) {
                    w.setFrame(was, display: true, animate: false)
                }
                return
            }
            guard let screen = w.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
            let want = CGSize(width: min(max(w.frame.width, 1180), screen.width),
                              height: min(max(w.frame.height, 780), screen.height))
            if before[eye.id] == nil { before[eye.id] = w.frame }
            guard want != w.frame.size else { return }
            var frame = CGRect(x: w.frame.midX - want.width / 2, y: w.frame.maxY - want.height,
                               width: want.width, height: want.height)
            frame.origin.x = min(max(frame.minX, screen.minX), screen.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, screen.minY), screen.maxY - frame.height)
            w.setFrame(frame, display: true, animate: false)
        }
    }

    /// Double-click a frame and you get a window on it.
    ///
    /// **A new window only when every open one is pinned.** An unpinned window
    /// is already following the cursor, so it is *already* showing the frame
    /// just double-clicked; opening a second loose window beside it would be
    /// two windows showing the same thing. So: nothing open → open one. A loose
    /// one open → it has it already, bring it forward. All pinned → he has
    /// deliberately parked them, and wants a fresh pair of eyes.
    @discardableResult
    func open(for rowId: String, state: ShellState) -> Eye {
        state.cursorShot = rowId
        if let loose = eyes.values.first(where: { $0.eye.pinned == nil }) {
            loose.eye.selected = nil
            retitle(loose.window, loose.eye, state)
            loose.window.makeKeyAndOrderFront(nil)
            note(state)
            return loose.eye
        }
        let eye = Eye()
        // `--frameswidth <points>` opens it narrower, to photograph the arrow
        // bar at a width it has to wrap for.
        let args = CommandLine.arguments
        let opened = args.firstIndex(of: "--frameswidth").flatMap { at in
            at + 1 < args.count ? Double(args[at + 1]) : nil
        } ?? 760
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: opened, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable,
                        .fullSizeContentView],
            backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: min(460, opened), height: 340)
        // The picture runs under the title bar: the window is a frame to look
        // through, and a bar of chrome across the top of it is in the way.
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        // **Not draggable by its background any more.** `head` claims the
        // drag itself instead — see `WindowDragArea` in Viewer.swift. Left on
        // here, a drag meant for the clip's own scrubber or the trim handles
        // moved the window instead: his report, 2026-08-28.
        w.delegate = self
        w.identifier = NSUserInterfaceItemIdentifier("frames")
        w.contentView = NSHostingView(rootView: FramesView(state: state, eye: eye))
        // His window position is his — remembered between opens, but never
        // written by a checking run. Only the first window autosaves; the rest
        // are cascaded off it, since two windows cannot share one saved frame.
        if !Launch.checking, eyes.isEmpty { w.setFrameAutosaveName("framesWindow") }
        if let main = NSApp.windows.first(where: { $0.isVisible && $0 != w }) {
            // A child window rides above the main one and follows it, without
            // floating over every other app on the Mac.
            main.addChildWindow(w, ordered: .above)
            if w.frame.origin == .zero { w.center() }
        }
        if !eyes.isEmpty {
            // Offset, so a second window does not land exactly on the first.
            let step = CGFloat(eyes.count) * 28
            w.setFrameOrigin(NSPoint(x: w.frame.minX + step, y: w.frame.minY - step))
        }
        eyes[eye.id] = (w, eye)
        retitle(w, eye, state)
        w.makeKeyAndOrderFront(nil)
        note(state)
        return eye
    }

    private func retitle(_ window: NSWindow, _ eye: Eye, _ state: ShellState) {
        guard let row = state.view?.allRows.first(where: { $0.id == eye.shot(state) })
        else { window.title = "Frames"; return }
        let pin = eye.pinned == nil ? "" : "  📌"
        window.title = row.description.isEmpty
            ? "Shot \(row.number)\(pin)"
            : "\(row.number) · \(row.description)\(pin)"
    }

    /// Every open window re-reads itself: titles follow the cursor, and the
    /// shell's own `mediaShown` mirrors whichever window has the keyboard so
    /// the table's key monitor and the checking reports keep working unchanged.
    func refresh(_ state: ShellState) {
        for (window, eye) in eyes.values { retitle(window, eye, state) }
        note(state)
    }

    private func note(_ state: ShellState) {
        let key = eyes.values.first { $0.window.isKeyWindow } ?? eyes.values.first
        state.mediaShown = key?.eye.shot(state)
        state.frameSelected = key?.eye.selected
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow,
              let found = eyes.first(where: { $0.value.window === w })
        else { return }
        // Closed in Print Frame: its saved size is the picture size, not the
        // grown one.
        if let was = before.removeValue(forKey: found.key) {
            w.setFrame(was, display: false, animate: false)
        }
        eyes.removeValue(forKey: found.key)
        note(ShellState.shared)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        note(ShellState.shared)
    }

    /// Whether one of ours holds the keyboard, for the table's monitor.
    func isKey() -> Bool { eyes.values.contains { $0.window.isKeyWindow } }

    /// The window with the keyboard, so the arrow keys walk *its* filmstrip.
    func keyEye() -> Eye? {
        (eyes.values.first { $0.window.isKeyWindow } ?? eyes.values.first)?.eye
    }

    /// Escape closes the one in front, not all of them.
    func close() {
        (eyes.values.first { $0.window.isKeyWindow } ?? eyes.values.first)?.window.close()
    }
}

/// One window's content: the frame large and whole, with everything else
/// floating over it.
///
/// The old layout was three stacked bands — picture, filmstrip, a row of eight
/// labelled buttons — which is what made it feel, in his words, the least
/// thought-through panel in the app. A window whose job is *looking* should be
/// mostly the thing being looked at. So the picture fills it, and the controls
/// are glass laid over the picture: a label and a pin at the top, one bar at
/// the foot holding the strip and the few actions that earn a button. The rest
/// live in a "…", where a rarely-used thing belongs.
struct FramesView: View {
    @ObservedObject var state: ShellState
    @ObservedObject var eye: FrameWindows.Eye
    @Environment(\.colorScheme) private var scheme
    /// The frame being carried along the strip, and how far it has come.
    @State private var carrying: String?
    @State private var carried: CGFloat = 0
    /// The frame being framed, if one is.
    @State private var cropping: ViewModel.Still?
    /// **Whether arrows are being drawn**, and which one is picked up. A mode
    /// on this window rather than a sheet: a sheet in this app cannot be
    /// photographed, so it could never be checked — and this window is
    /// already where a shot's pictures are looked at whole.
    @State private var drawingArrows = Launch.drawingArrows
    /// Pre-picked under `--drawarrows` so the handles are on screen in a
    /// photograph: choosing one is a click, and a click cannot run alongside
    /// a snapshot (Ref 369).
    @State private var pickedArrow: Int? = Launch.drawingArrows ? 0 : nil

    /// **The player, owned here rather than inside the view that draws it.**
    /// See `ClipView` in Viewer.swift — it carries Apple's own transport and
    /// Apple's own trim bar, so this window keeps no range of its own: the
    /// engine's `shown` is the only copy.
    @StateObject private var clip = ClipView()

    private var dark: Bool { scheme == .dark }

    /// The film's own shape, which is what a frame is looked at in.
    private var ratio: CGFloat { CGFloat(state.view?.project.ratio ?? 2.39) }

    /// The part of this picture the frame shows — where a preset arrow goes.
    private func frameOf(_ still: ViewModel.Still) -> CGRect {
        let frame = ViewModel.Frame(hash: still.hash, filename: still.filename,
                                    kind: still.kind)
        guard let picture = Thumbs.shared.image(frame, from: state.engine) else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        return Plate.visible(picture: picture.size, ratio: ratio,
                             framing: still.framing)
    }

    private var row: ViewModel.Row? {
        state.view?.allRows.first { $0.id == eye.shot(state) }
    }

    /// Whether this shot has a picture or clip a Print Frame can be made of.
    private var canPrint: Bool {
        row?.stills.contains(where: PrintFrameSpec.usable) ?? false
    }

    var body: some View {
        let stills = row?.stills ?? []
        let shown = stills.first { $0.ref == eye.selected }
            ?? stills.first { $0.key }
            ?? stills.first

        VStack(spacing: 0) {
            head(stills, shown)
            if eye.printing, let row, canPrint {
                PrintFrameEditor(state: state, shot: row.shot, opened: shown?.ref) {
                    eye.printing = false
                }
                .id(row.shot)
            } else {
                picture(shown)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !stills.isEmpty || row != nil {
                    foot(stills, shown)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $cropping) { still in
            if let file = fileOf(still), let picture = ViewerContent.decoded(file) {
                CropSheet(state: state, ref: still.ref, picture: picture,
                          filename: still.filename, start: still.framing)
            }
        }
        // **The app's own ground, not black.** This window forced its whole
        // background to black and drew every control white-on-black, which is
        // why it read as a different program from the other two pop-outs. The
        // picture still sits on a dark wash — that is what a frame wants
        // behind it — but the chrome is the app's.
        .background(Brand.surface(dark))
        // **Outside the view update**, which is the whole point: this writes
        // to an object the update cycle is not allowed to swallow. Keyed on
        // the ref *and* the range, so walking the filmstrip loads a
        // different clip and saving a trim re-cuts this one.
        .task(id: "\(shown?.ref ?? "")|\(shown?.trimStart ?? -1)|\(shown?.trimEnd ?? -1)") {
            guard let shown, shown.movie, let file = fileOf(shown) else { return }
            clip.show(file, start: shown.trimStart, end: shown.trimEnd)
        }
        // A picture dropped anywhere on the window lands on the shot.
        .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
            guard let row else { return false }
            return Drops.take(providers, onto: row, state: state)
        }
        // **Following.** The cursor moved, so an unpinned window is looking at
        // something else now: its chosen frame means nothing on the new shot.
        .onChange(of: state.cursorShot) { _, _ in
            guard eye.pinned == nil else { return }
            eye.selected = nil
            FrameWindows.shared.refresh(state)
        }
        .onChange(of: eye.pinned) { _, _ in FrameWindows.shared.refresh(state) }
        .onChange(of: eye.printing) { _, on in
            if on {
                clip.view.player?.pause()
                drawingArrows = false
                pickedArrow = nil
            }
            FrameWindows.shared.fit(eye, printing: on)
        }
        // Nothing left to make a Print Frame from: back to the pictures.
        .onChange(of: canPrint) { _, can in if !can { eye.printing = false } }
        .onAppear { if eye.printing { FrameWindows.shared.fit(eye, printing: true) } }
        .onChange(of: eye.selected) { _, _ in
            // The arrows belong to *this* picture; walking to the next one and
            // finding the pen still down would draw on the wrong frame.
            drawingArrows = false
            pickedArrow = nil
            FrameWindows.shared.refresh(state)
        }
    }

    /// Hands the clip to Apple's own trim bar, and files whatever comes back.
    private func startTrimming(_ shown: ViewModel.Still) {
        guard let file = fileOf(shown) else { return }
        clip.trim(from: shown.trimStart, to: shown.trimEnd,
                  whenStuck: { state.say($0) }) { start, end in
            state.replace(state.engine?.trim(shown.ref, start: start, end: end))
            clip.show(file, start: start, end: end, force: true)
        }
    }

    /// Back to playing the whole clip — the file was never touched, so there
    /// is nothing to undo, only a range to forget.
    private func resetTrim(_ shown: ViewModel.Still) {
        state.replace(state.engine?.clearTrim(shown.ref))
        if let file = fileOf(shown) { clip.show(file, start: nil, end: nil, force: true) }
    }

    /// Grabs the exact frame the player is paused on and stores it as this
    /// clip's poster — the same file a PDF, a spreadsheet, and every
    /// thumbnail in the app all ask for first. His ask, 2026-08-28: video
    /// can't play in a static export, and the frame the app picks on its own
    /// is not always the one that reads best.
    private func useThisFrame(_ shown: ViewModel.Still) {
        // **The item, not the file.** On a trimmed clip the item is a
        // composition of the chosen range, so its clock starts at the in
        // point — asking the original file for that same number would hand
        // back a frame from somewhere else entirely.
        guard let item = clip.view.player?.currentItem else { return }
        let generator = AVAssetImageGenerator(asset: item.asset)
        generator.appliesPreferredTrackTransform = true
        guard let cg = try? generator.copyCGImage(at: item.currentTime(), actualTime: nil) else {
            state.say("Could not read that frame")
            return
        }
        let image = NSImage(cgImage: cg, size: .zero)
        guard let made = Ingest.poster(image) else { return }
        state.engine?.poster(hash: shown.hash, data: made)
        Thumbs.shared.forget(shown.hash)
        state.replace(state.engine?.view())
        state.say("Using this frame as the still")
    }

    /// Where the real file lives, when there is one — a clip has to be played
    /// from disk and a gif has to be animated from disk; only a still can be
    /// drawn from the thumbnail cache.
    ///
    /// **Through `Clips`, not `Viewer.onDisk` directly.** This is reached from
    /// `showing(_:)` inside `body`, and `Viewer.onDisk` reads the whole file
    /// back out of the engine *before* it notices the scratch copy is already
    /// there — so a frames window showing a clip was pulling megabytes across
    /// the ffi on every redraw. `Clips` exists precisely to remember the
    /// answer; this window was the one place that asked around it.
    private func fileOf(_ still: ViewModel.Still) -> URL? {
        Clips.file(hash: still.hash, ext: still.ext, from: state.engine)
    }

    /// What the middle of the window is showing, decided once rather than in
    /// four `if let` branches — the type checker gave up on those.
    private enum Showing {
        case clip(URL), moving(URL), still(NSImage), nothing
    }

    private func showing(_ shown: ViewModel.Still?) -> Showing {
        guard let shown else { return .nothing }
        if shown.movie, let file = fileOf(shown) { return .clip(file) }
        if shown.gif, let file = fileOf(shown) { return .moving(file) }
        if let picture = Thumbs.shared.image(
            ViewModel.Frame(hash: shown.hash, filename: shown.filename, kind: shown.kind),
            from: state.engine) { return .still(picture) }
        return .nothing
    }

    @ViewBuilder
    private func picture(_ shown: ViewModel.Still?) -> some View {
        Group {
            switch showing(shown) {
            case .clip:
                // **A clip plays here.** It used to hand itself to a viewer
                // window, which meant leaving what you were doing to watch
                // three seconds of footage. `.task` above is what loads it.
                Movie(view: clip.view)
            case .moving(let file):
                // A gif that is actually going round — his ask. SwiftUI's own
                // `Image` draws one frame of one and stops.
                Animated(file: file, fill: false)
            case .still(let picture):
                if drawingArrows, let shown {
                    ArrowBoard(state: state, ref: shown.ref, picture: picture,
                               framing: shown.framing, ratio: ratio,
                               stored: shown.marks, selected: $pickedArrow)
                } else if let shown, shown.kind != "other" {
                    // **The frame, not the photograph** — his instruction,
                    // 2026-08-31. This window used to show a still whole and
                    // said so in a comment; see `Plate` for why that was the
                    // wrong call for a shot.
                    Plate(picture: picture, ratio: ratio,
                          framing: shown.framing, arrows: shown.marks,
                          guides: FramePicker.guides(state.view?.project))
                } else {
                    // A PDF or anything else that is not a frame of the film
                    // has no business being cut to the film's shape.
                    Fitted(picture: picture)
                }
            case .nothing:
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A frame is looked at against dark, the same wash the viewer puts
        // behind a picture — but it is a wash behind the *picture*, not a
        // black window.
        .background(Color.black.opacity(dark ? 0.45 : 0.82))
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }

    private var empty: some View {
        EmptyState(title: row == nil ? "No shot selected" : "No frames yet")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// **The same bar the viewer and the scan window wear** — `PopoutBar`.
    /// This was 52 points tall with no fill and no hairline, 74 points of room
    /// for the traffic lights against everyone else's 68, and its own pin
    /// drawn 30 points across and lit *yellow*. None of that was a decision
    /// about a frames window; it was three windows drifting.
    private func head(_ stills: [ViewModel.Still], _ shown: ViewModel.Still?) -> some View {
        let at = stills.firstIndex { $0.ref == shown?.ref }
        return PopoutBar(
            title: row.map { r in
                r.title.isEmpty
                    ? (r.description.isEmpty ? "Shot \(r.number)" : "\(r.number) · \(r.description)")
                    : "\(r.number) · \(r.title)"
            } ?? "Frames",
            count: eye.printing ? nil : at.map { "\($0 + 1) of \(stills.count)" }
        ) {
            // **Pictures | Print Frame** — the same switch the viewer wears,
            // turning this window into the shot's Print Frame and back.
            if canPrint {
                Segmented(selection: $eye.printing, items: [
                    .init(value: false, title: "Pictures"),
                    .init(value: true, title: "Print Frame"),
                ], quiet: true)
                .fixedSize()
                .overlay { Capsule(style: .continuous).strokeBorder(Brand.rule2(dark), lineWidth: 1) }
            }
            ToolButton(icon: eye.pinned == nil ? "pin" : "pin.fill", size: 11,
                       help: eye.pinned == nil
                           ? "Pin"
                           : "Pinned",
                       lit: eye.pinned != nil) {
                eye.pinned = eye.pinned == nil ? row?.id : nil
            }
        }
    }

    /// One glass bar at the foot: the strip, and the few things worth a button.
    private func foot(_ stills: [ViewModel.Still], _ shown: ViewModel.Still?) -> some View {
        VStack(spacing: 8) {
            if !stills.isEmpty { filmstrip(stills, shown) }
            actions(stills, shown)
            if drawingArrows, let shown, !shown.moving {
                ArrowTools(state: state, ref: shown.ref, arrows: shown.marks,
                           visible: frameOf(shown), selected: $pickedArrow)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: Brand.radiusCard, style: .continuous)
                .fill(Brand.panel(dark))
        }
        .systemGlass(RoundedRectangle(cornerRadius: Brand.radiusCard, style: .continuous), dark: dark)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    private func filmstrip(_ stills: [ViewModel.Still],
                           _ shown: ViewModel.Still?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(stills) { still in
                    strip(still, shownRef: shown?.ref, all: stills)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 58)
    }

    @ViewBuilder
    private func actions(_ stills: [ViewModel.Still],
                         _ shown: ViewModel.Still?) -> some View {
        HStack(spacing: 8) {
            round("plus", "Add a frame from a file") {
                if let row { Ingest.addViaPanel(to: row, state: state) }
            }
            // **The second door** — Ref 228. A picture the project already
            // holds, rather than one off the disk.
            round("photo.on.rectangle", "Add From Project") {
                if let row { state.pickingPictureFor = row.shot }
            }
            round("doc.on.clipboard", "Paste whatever is on the clipboard") {
                if let row, !Ingest.fromPasteboard(onto: [row], state: state) {
                    state.say("Nothing to paste")
                }
            }
            // **Remove, beside Add** — his call, and the right place: the two
            // ends of one job belong together rather than at opposite ends of
            // the bar. And "Remove" rather than "Detach", which was the
            // engine's word for it, not a person's.
            if let shown {
                round("minus", "Remove this frame from the shot") {
                    remove(shown, from: stills)
                }
            }
            // A still can be told which part of it to keep; a clip cannot —
            // what draws one is a player, not an image.
            if let shown, !shown.moving {
                let framed = !shown.framing.isMiddle
                round("crop",
                      framed ? "Edit Crop"
                             : "Crop",
                      lit: framed) {
                    cropping = shown
                }
            }
            // **Arrows on a still, and only a still.** A clip is drawn by a
            // player and a gif by its own view; marking either would put the
            // arrow on the window rather than on the picture.
            if let shown, !shown.moving {
                let marked = !shown.marks.isEmpty
                round("arrow.up.right",
                      drawingArrows ? "Stop drawing arrows"
                          : (marked ? "Edit Arrows"
                                    : "Draw storyboard arrows on this picture"),
                      lit: drawingArrows || marked) {
                    drawingArrows.toggle()
                    pickedArrow = nil
                }
            }
            if let shown, shown.movie {
                round("camera.viewfinder", "Use this frame as the still") {
                    useThisFrame(shown)
                }
                round("photo.badge.arrow.down", "Export this frame") {
                    FrameExport.save(clip.view.player?.currentItem,
                                     clip: shown.filename, offset: shown.trimStart,
                                     say: { state.say($0) })
                }
                // Lit while a trim is in force — the only standing sign that
                // this clip is playing less than all of itself.
                let trimmed = shown.trimStart != nil || shown.trimEnd != nil
                round("scissors",
                      trimmed ? "Edit Trim"
                              : "Trim this clip's in and out points",
                      lit: trimmed) {
                    startTrimming(shown)
                }
            }
            Spacer(minLength: 0)
            if let shown { rightHand(stills, shown) }
        }
    }

    @ViewBuilder
    private func rightHand(_ stills: [ViewModel.Still],
                           _ shown: ViewModel.Still) -> some View {
        let at = stills.firstIndex { $0.ref == shown.ref } ?? 0
        round(shown.key ? "star.fill" : "star",
              "The frame the table and storyboard show", lit: shown.key) {
            guard !shown.key, let engine = state.engine, let row else { return }
            state.replace(engine.keyFrame(shot: row.shot, ref: shown.ref))
        }
        ToolMenu(help: "\(at + 1) of \(stills.count) — more") {
            // **Save a Copy stays; the full-screen viewer goes.** His verdict
            // on it: opening a whole window to look at the same picture bigger
            // "doesn't really help me in any way". Getting the original file
            // back out of the project does.
            Button("Save a copy…") { saveACopy(shown) }
            Button("Open in another app") {
                if let file = fileOf(shown) { NSWorkspace.shared.open(file) }
            }
            // Only worth offering once there is a trim to undo, and the one
            // thing Apple's trim bar has no button for.
            if shown.trimStart != nil || shown.trimEnd != nil {
                Divider()
                Button("Play the whole clip") { resetTrim(shown) }
            }
            Divider()
            Button("Remove") { remove(shown, from: stills) }
        }
    }

    /// Take a frame off the shot. The picture itself is kept — nothing in
    /// this app deletes a person's media on a button press.
    private func remove(_ still: ViewModel.Still, from stills: [ViewModel.Still]) {
        guard let engine = state.engine else { return }
        // Land the eye on the neighbour rather than on nothing: removing the
        // third of five and being shown an empty window is a jolt.
        let at = stills.firstIndex { $0.ref == still.ref } ?? 0
        let next = stills.indices.contains(at + 1) ? stills[at + 1]
                 : (at > 0 ? stills[at - 1] : nil)
        eye.selected = next?.ref
        state.replace(engine.detach(frame: still.ref))
    }

    /// The original bytes, back out of the project and onto his disk.
    private func saveACopy(_ still: ViewModel.Still) {
        guard let file = fileOf(still) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = still.filename.isEmpty
            ? "\(still.hash).\(still.ext)" : still.filename
        guard panel.runModal() == .OK, let to = panel.url else { return }
        try? FileManager.default.removeItem(at: to)
        try? FileManager.default.copyItem(at: file, to: to)
    }

    /// **The app's round button**, not one of this window's own. Lit is the
    /// accent now rather than yellow — one colour for "in force", everywhere.
    private func round(_ icon: String, _ help: String,
                       lit: Bool = false, off: Bool = false,
                       action: @escaping () -> Void) -> some View {
        ToolButton(icon: icon, size: 11, help: help, lit: lit, action: action)
            .disabled(off)
            .opacity(off ? 0.4 : 1)
    }

    private func strip(_ still: ViewModel.Still, shownRef: String?,
                       all: [ViewModel.Still]) -> some View {
        let on = still.ref == shownRef
        return ZStack(alignment: .topTrailing) {
            Group {
                if Frames.something(still.hash, still.filename, state.engine,
                                    kind: still.kind) {
                    Frames.view(still.hash, still.filename, engine: state.engine,
                                trimStart: still.trimStart, trimEnd: still.trimEnd,
                                kind: still.kind, framing: still.framing, arrows: still.marks)
                } else {
                    Rectangle().fill(Brand.frameEmpty(dark))
                        .overlay { Frames.gap(still.hash, dark: dark, small: true) }
                }
            }
            .frame(width: 92, height: 52)
            .clipped()
            if still.movie {
                Image(systemName: "play.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Brand.onImage)
                    .padding(4)
                    .background(Circle().fill(Color.black.opacity(0.55)))
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .bottomLeading)
            }
            if still.key {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow)
                    .padding(4)
                    .background(Circle().fill(Color.black.opacity(0.55)))
                    .padding(4)
            }
        }
        // Square, like every other photograph in this build: the slab rounds,
        // the picture does not.
        .overlay { Rectangle().strokeBorder(on ? .clear : Brand.rule(dark),
                                            lineWidth: 1) }
        .overlay {
            if on { Rectangle().strokeBorder(Brand.accent(dark), lineWidth: 2) }
        }
        .contentShape(Rectangle())
        .onTapGesture { eye.selected = still.ref }
        // **Carry a frame to reorder it** — his ask, and the arrows stay
        // because a check can press an arrow and cannot drag. A plain
        // `DragGesture` rather than macOS drag-and-drop, for the same reason
        // the table's row carry is one: a gesture the checks cannot reach is
        // how a broken feature ships looking fine.
        .offset(x: carrying == still.ref ? carried : 0)
        .zIndex(carrying == still.ref ? 1 : 0)
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { drag in
                    carrying = still.ref
                    carried = drag.translation.width
                    eye.selected = still.ref
                }
                .onEnded { drag in
                    defer { carrying = nil; carried = 0 }
                    guard let from = all.firstIndex(where: { $0.ref == still.ref }),
                          let engine = state.engine else { return }
                    // One thumbnail plus its gap is 99 points wide; how many
                    // of those the hand travelled is how far it moved.
                    let steps = Int((drag.translation.width / 99).rounded())
                    let to = min(max(from + steps, 0), all.count - 1)
                    guard to != from else { return }
                    state.replace(engine.moveFrame(still.ref, to: to))
                }
        )
    }
}
