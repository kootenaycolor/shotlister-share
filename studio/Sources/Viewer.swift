import AppKit
import AVKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// A file, big enough to actually read.
///
/// The gap this closes, in his words: "I can't read back files I upload like
/// PDFs or images, just leaves them as small thumbnails which is not helpful."
/// A thumbnail says a file is *there*; it never says what the file *says*. So
/// anything the project holds opens here at a size a person can read — a
/// picture zoomable, a PDF page by page, a clip playing in place.
///
/// A window of its own rather than a panel, for the old app's reason: a window
/// can live on the second monitor and stay there while the list is worked on
/// the first. It is a child of the main window, so it rides above the app
/// without floating over everything else on the Mac.
final class Viewer: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = Viewer()

    /// **One pop-out's own mind** — and the reason there can be more than one.
    ///
    /// His ask, 2026-08-28: *"one window that follows but if i click the pin
    /// button then its locked on that photo and a double click of another
    /// media brings up a new pop out."* Until now `Viewer` was a singleton
    /// that reused one content view, so `follow()` honoured the pin and
    /// `show()` walked straight over it: pinning a photograph and opening
    /// another **replaced the pinned one**. The frames window has been a set
    /// of windows since 2026-08-20 for exactly this reason; this is that,
    /// applied here.
    final class Eye: ObservableObject, Identifiable {
        let id = UUID()
        /// **Pinned means it stops following and stays on top.** You pin the
        /// photograph you are matching to, then go and work on the list.
        @Published var pinned = false { didSet { onPin?(pinned) } }
        /// Set by `Viewer` when the window is made, so the published flag can
        /// move the real window without the view knowing about windows.
        fileprivate var onPin: ((Bool) -> Void)?
    }

    private struct Open {
        let window: NSWindow
        let hosting: NSHostingView<ViewerContent>
        let eye: Eye
    }
    private var eyes: [UUID: Open] = [:]

    /// What is being looked at: the bytes, what they are, and what to call it.
    struct Subject {
        var hash: String
        var ext: String
        var filename: String
        var kind: String
        /// Where this same file also lives, as somewhere to be shown it. The
        /// project package holds the copy the app draws from; the Drive bridge
        /// keeps another where a producer can see it.
        ///
        /// **Asked, not carried.** Finding these walks the file system —
        /// including his Google Drive folders, which are network-backed — and
        /// building it into every subject put that walk on every double-click
        /// and every arrow key. The only moment the answer is wanted is when
        /// the ⋯ menu is opened, so that is when it is worked out.
        var places: () -> [Place] = { [] }
        /// "2 of 8", when the thing was opened from a set.
        var place: String?
        /// **What was said about this use of the picture.** A caption written
        /// on a wall is readable when the picture is opened, not only in the
        /// tile it was typed under.
        var caption: String = ""
        /// **This use's own id**, so the viewer can save a trim against it.
        var ref: String?
        /// The remembered in/out range, in seconds. Both nil plays the whole
        /// clip.
        var trimStart: Double?
        var trimEnd: Double?
        /// **Which part of this use of the picture is kept where it is drawn
        /// cropped.** The middle at full width is what everything drew before
        /// 2026-08-30, and it is what nothing means.
        var framing: ViewModel.Framing = .middle
        /// Set by a **Print Frame** button elsewhere (the frames window): opens
        /// straight into Print Frame mode. A fresh value each time, so a window
        /// being reused for it switches too.
        var printToken: UUID?
    }

    struct Place: Identifiable {
        var label: String
        var url: URL
        var id: String { url.path }
    }

    /// **The one place a subject is built.**
    ///
    /// There were three, and they disagreed: a double-click on a wall gave the
    /// bar a count, a caption and *Show in Finder*; `Attachments.read` — the
    /// same picture's *Open here* menu item — gave it none of the three; and
    /// `LocationPage.subject`, the only one that offered Google Drive, stopped
    /// being reached by any click at all when the locations wall moved onto
    /// the shared `PictureWall`. So the same photograph opened two different
    /// windows depending on which way you asked for it, and a menu item the
    /// checks still verified was gone from the app.
    ///
    /// `alsoAt` is for an owner that knows somewhere else its files really
    /// live — a location knows its Google Drive folder; a mood board does not.
    /// **Passed as already-built places rather than looked up here**, because
    /// finding them walks a network-backed folder and this must stay cheap
    /// enough to call on every arrow key.
    static func subject(_ picture: ViewModel.Attachment,
                        among all: [ViewModel.Attachment],
                        alsoAt extra: @escaping () -> [Place] = { [] },
                        state: ShellState) -> Subject {
        let at = all.firstIndex { $0.ref == picture.ref }
        return subject(hash: picture.hash, ext: picture.ext,
                       filename: picture.filename, kind: picture.kind,
                       caption: picture.caption, ref: picture.ref,
                       place: at.map { "\($0 + 1) of \(all.count)" },
                       trimStart: picture.trimStart, trimEnd: picture.trimEnd,
                       framing: picture.framing,
                       alsoAt: extra, state: state)
    }

    /// The same builder, for a caller holding the pieces rather than an
    /// attachment — the picture picker, which lists a project's whole store
    /// and has no `ViewModel.Attachment` to hand.
    static func subject(hash: String, ext: String, filename: String, kind: String,
                        caption: String = "", ref: String? = nil,
                        place: String? = nil,
                        trimStart: Double? = nil, trimEnd: Double? = nil,
                        framing: ViewModel.Framing = .middle,
                        alsoAt extra: @escaping () -> [Place] = { [] },
                        state: ShellState) -> Subject {
        let places: () -> [Place] = { [weak state] in
            var found = extra()
            // Only when the owner had nothing better: the project stores every
            // picture by its content hash, which `storage::proxy_name` decides
            // and this matches rather than asking the engine to hand the path
            // across.
            if found.isEmpty, let root = state?.projectPath {
                let short = String(hash.prefix(32))
                let url = root.appendingPathComponent("media/proxies/\(short).\(ext)")
                if FileManager.default.fileExists(atPath: url.path) {
                    found.append(Place(label: "Finder", url: url))
                }
            }
            return found
        }
        return Subject(hash: hash, ext: ext, filename: filename, kind: kind,
                       places: places, place: place, caption: caption,
                       ref: ref, trimStart: trimStart, trimEnd: trimEnd,
                       framing: framing)
    }

    /// **The bytes, as a file on disk** — content-addressed, so the same
    /// picture always lands at the same path and asking twice costs nothing.
    ///
    /// PDFKit, AVKit and `NSImageView`'s gif animation all want a file rather
    /// than bytes in hand, and the project keeps its media inside the package.
    static func onDisk(hash: String, ext: String, from engine: Engine?) -> URL? {
        guard let found = engine?.stored(hash: hash, ext: ext) else { return nil }
        let bytes = found.data
        let real = actually(bytes, storedAs: found.ext, called: ext)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shotlister-viewer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(hash).\(real)")
        if !FileManager.default.fileExists(atPath: file.path) {
            do { try bytes.write(to: file) } catch { return nil }
        }
        return file
    }

    /// Whether any pop-out is on screen.
    var isOpen: Bool { eyes.values.contains { $0.window.isVisible } }

    /// How many, for a checking run — the pin's whole claim is that a second
    /// one appears, and a screenshot of two overlapping windows cannot say so.
    var openCount: Int { eyes.values.filter { $0.window.isVisible }.count }

    /// **Pin whichever pop-out is in front**, for a checking run. The pin is a
    /// button in a title-less window and nothing else can reach it, so without
    /// this door the one behaviour he actually asked for is unverifiable.
    func pinFront() {
        let front = eyes.values.first { $0.window.isKeyWindow } ?? eyes.values.first
        front?.eye.pinned.toggle()
    }

    /// Escape puts away the one in front, not all of them.
    func close() {
        (eyes.values.first { $0.window.isKeyWindow } ?? eyes.values.first)?.window.close()
    }

    /// **Change what is being looked at, but only in the windows that follow.**
    ///
    /// This is what makes the arrow keys feel like Finder: the selection moves
    /// whether or not a pop-out is up, and any unpinned pop-out follows it.
    /// Opening one because an arrow key was pressed would be the opposite of
    /// what he asked for.
    ///
    /// **The subject is not built unless somebody is looking.** Working out
    /// where a photograph also lives means asking the file system — including
    /// walking his Google Drive folders, which are network-backed — so a click
    /// that changes nothing costs nothing.
    func follow(_ subject: @autoclosure () -> Subject, state: ShellState) {
        let loose = eyes.values.filter { !$0.eye.pinned }
        guard !loose.isEmpty else { return }
        guard let ready = prepare(subject(), state: state) else { return }
        for one in loose { draw(ready.subject, file: ready.file, into: one, state: state) }
    }

    /// **A new window only when every open one is pinned.**
    ///
    /// An unpinned window is already following, so it is already showing what
    /// was just double-clicked; opening a second loose one beside it would be
    /// two windows showing the same picture. So: nothing open → open one. A
    /// loose one open → it has it already, bring it forward. All pinned → he
    /// has deliberately parked them and wants a fresh pair of eyes. The frames
    /// window has decided it this way since 2026-08-20.
    func show(_ subject: Subject, state: ShellState) {
        guard let ready = prepare(subject, state: state) else { return }
        if let loose = eyes.values.first(where: { !$0.eye.pinned }) {
            draw(ready.subject, file: ready.file, into: loose, state: state)
            loose.window.makeKeyAndOrderFront(nil)
            return
        }
        let eye = Eye()
        let view = ViewerContent(subject: ready.subject, file: ready.file,
                                 state: state, eye: eye)
        // **A pop-out, not a document window** — his ask: *"It should feel
        // like a pop-out, almost like hitting the space bar in preview in
        // Finder."* Quick Look's whole trick is that the chrome gets out of
        // the way: no title bar of its own, the picture running to the edges.
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable,
                        .fullSizeContentView],
            backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 420, height: 320)
        w.delegate = self
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        // **Not draggable by its background.** AppKit does not ask a SwiftUI
        // gesture's permission first, and a clip's own scrubber or the trim
        // handles lost that race every time. `bar` claims the drag itself.
        // Named, so a checking run can photograph it.
        w.identifier = NSUserInterfaceItemIdentifier("viewer")
        let host = NSHostingView(rootView: view)
        // **The window owns its size; what is inside never argues.** Left at
        // the default, the hosting view turns the content's own min, max and
        // ideal sizes into constraints on the window, re-derived on every
        // layout pass. A picture fitted to a `GeometryReader`, a bar whose
        // title changes with the file, a player that learns the clip's size
        // once it loads — any of them can move those numbers in answer to
        // the window moving, and AppKit throws when the passes never settle.
        // His report, 2026-09-27: Labs crashed twice opening a photo in a
        // location on *Mirrorland* (`_postWindowNeedsUpdateConstraints`,
        // raised from `NSHostingView.layout`). `minSize` above is the floor.
        host.sizingOptions = []
        w.contentView = host
        // His window position is his — remembered between opens, but never
        // written by a checking run. Only the first window autosaves; the rest
        // cascade off it, since two windows cannot share one saved frame.
        if !Launch.checking, eyes.isEmpty { w.setFrameAutosaveName("viewerWindow") }
        adopt(w)
        if !eyes.isEmpty {
            let step = CGFloat(eyes.count) * 28
            w.setFrameOrigin(NSPoint(x: w.frame.minX + step, y: w.frame.minY - step))
        }
        let open = Open(window: w, hosting: host, eye: eye)
        eyes[eye.id] = open
        eye.onPin = { [weak self, weak w] pinned in
            guard let self, let w else { return }
            self.float(w, pinned)
        }
        w.title = ready.subject.filename.isEmpty ? "File" : ready.subject.filename
        w.makeKeyAndOrderFront(nil)
        if Launch.checking { Self.report(ready.subject, file: ready.file) }
    }

    /// The bytes read, the type settled, and a scratch copy on disk.
    private func prepare(_ subject: Subject,
                         state: ShellState) -> (subject: Subject, file: URL)? {
        guard let found = state.engine?.stored(hash: subject.hash, ext: subject.ext) else {
            state.say("Couldn't read that file")
            return nil
        }
        let bytes = found.data
        // **What it is, not what it is called.** His deck was pinned by an
        // earlier build that flattened PDFs to a picture of page one: it is
        // still named `.pdf`, so a viewer trusting the name asked PDFKit to
        // open a PNG and drew an empty black page. The first four bytes cannot
        // lie.
        var subject = subject
        subject.ext = Self.actually(bytes, storedAs: found.ext, called: subject.ext)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shotlister-viewer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(subject.hash).\(subject.ext)")
        if !FileManager.default.fileExists(atPath: file.path) {
            do { try bytes.write(to: file) } catch {
                state.say("Could not open that file.")
                return nil
            }
        }
        return (subject, file)
    }

    private func draw(_ subject: Subject, file: URL, into open: Open, state: ShellState) {
        open.hosting.rootView = ViewerContent(subject: subject, file: file,
                                              state: state, eye: open.eye)
        open.window.title = subject.filename.isEmpty ? "File" : subject.filename
        if Launch.checking { Self.report(subject, file: file) }
    }

    /// Whether a sheet is up anywhere in the app.
    private var underASheet: Bool {
        NSApp.windows.contains { $0.isSheet && $0.isVisible }
    }

    /// A child window rides above the main one and follows it, without
    /// floating over every other app on the Mac.
    ///
    /// **Except under a sheet, where being a child is being buried.** A sheet
    /// is modal to its parent and sits above it, so a pop-out adopted by that
    /// same parent opens *behind* the sheet — the window is really there, and
    /// what he sees is nothing at all. His report, 2026-08-29: *"double click
    /// in locations and boards isnt working"* — both are places the picture
    /// picker is opened from, and the picker is a sheet.
    ///
    /// So while a sheet is up the pop-out floats instead, parentless, and
    /// `windowDidBecomeKey` puts it back into the family once the sheet has
    /// gone. **This is why "the window was created" was not enough proof** and
    /// the check below now reads its level.
    private func adopt(_ w: NSWindow) {
        guard !underASheet else {
            w.level = .floating
            if w.frame.origin == .zero { w.center() }
            return
        }
        if let main = NSApp.windows.first(where: {
            $0.identifier?.rawValue == "main" && $0.isVisible
        }) ?? NSApp.windows.first(where: { $0.isVisible && $0 != w }) {
            main.addChildWindow(w, ordered: .above)
            if w.frame.origin == .zero { w.center() }
        }
    }

    /// Once the sheet it was opened over has gone, an unpinned pop-out goes
    /// back to being a child that follows the main window.
    func windowDidBecomeKey(_ notification: Notification) {
        guard let w = notification.object as? NSWindow,
              let found = eyes.values.first(where: { $0.window === w }),
              !found.eye.pinned, w.parent == nil, !underASheet
        else { return }
        w.level = .normal
        adopt(w)
    }

    /// Pinned: out of the parent's hands and above everything. Unpinned: back
    /// to being a child that follows the main window around.
    private func float(_ w: NSWindow, _ pinned: Bool) {
        if pinned {
            w.parent?.removeChildWindow(w)
            w.level = .floating
        } else {
            w.level = .normal
            if w.parent == nil { adopt(w) }
        }
    }

    /// The extension the bytes deserve: their own signature first, then what
    /// they were stored under, and only then the name they carry.
    static func actually(_ bytes: Data, storedAs: String, called: String) -> String {
        let head = bytes.prefix(4)
        if head.starts(with: [0x25, 0x50, 0x44, 0x46]) { return "pdf" }       // %PDF
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }       // PNG
        if head.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }             // JPEG
        if head.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "gif" }       // GIF8
        if bytes.count > 8,
           bytes[4..<8].elementsEqual([0x66, 0x74, 0x79, 0x70]) { return "mov" }  // ftyp
        return storedAs.isEmpty ? called : storedAs
    }

    /// What the picture was given and what it did with it — a screenshot of a
    /// scroll view renders its content unclipped, so it cannot answer "did
    /// this fit?". Arithmetic can.
    static func measured(room: CGSize, picture: CGSize) {
        guard Launch.checking else { return }
        let fit = min(room.width / max(picture.width, 1), room.height / max(picture.height, 1))
        FileHandle.standardError.write(Data(String(
            format: "picture: %.0f\u{00D7}%.0f in %.0f\u{00D7}%.0f  fits at %.2f \u{2192} %.0f\u{00D7}%.0f\n",
            picture.width, picture.height, room.width, room.height, fit,
            picture.width * fit, picture.height * fit).utf8))
    }

    private static func report(_ subject: Subject, file: URL) {
        var said = "viewer: \(subject.filename) as \(subject.ext)"
        said += "  windows: \(Viewer.shared.openCount)"
        said += "  pinned: \(Viewer.shared.eyes.values.filter { $0.eye.pinned }.count)"
        // **Above whatever is in front of it, or it may as well not be open.**
        // A window opened behind a sheet reports as open and shows nothing.
        let front = Viewer.shared.eyes.values
            .max { ($0.window.level.rawValue) < ($1.window.level.rawValue) }
        said += "  floating: \(front.map { $0.window.level != .normal } ?? false ? "yes" : "no")"
        said += "  sheet up: \(Viewer.shared.underASheet ? "yes" : "no")"
        switch subject.ext.lowercased() {
        case "pdf":
            if let doc = PDFDocument(url: file) {
                let words = (0..<doc.pageCount)
                    .compactMap { doc.page(at: $0)?.string }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                said += "  pages: \(doc.pageCount)  reads: \"\(words.prefix(60))\""
            } else {
                said += "  UNREADABLE"
            }
        case let ext where Ingest.isMovie(ext, kind: subject.kind):
            let asset = AVURLAsset(url: file)
            said += String(format: "  seconds: %.1f  playable: %@",
                           CMTimeGetSeconds(asset.duration),
                           asset.isPlayable ? "yes" : "no")
        default:
            if let picture = NSImage(contentsOf: file) {
                said += "  \(Int(picture.size.width))\u{00D7}\(Int(picture.size.height))"
            } else {
                said += "  UNREADABLE"
            }
        }
        FileHandle.standardError.write(Data((said + "\n").utf8))
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow,
              let found = eyes.first(where: { $0.value.window === w })
        else { return }
        eyes.removeValue(forKey: found.key)
    }
}

/// What the viewer draws, chosen by what the file is.
struct ViewerContent: View {
    let subject: Viewer.Subject
    let file: URL
    @ObservedObject var state: ShellState
    /// **This window's own mind**, not a shared one — pinning one pop-out
    /// must not pin the others.
    @ObservedObject var eye: Viewer.Eye
    @Environment(\.colorScheme) private var scheme

    /// **What is actually saved**, seeded from the subject once and from then
    /// on kept here — a save has nowhere else to write itself back to, since
    /// `subject` is a snapshot handed in when the window opened.
    @State private var committedStart: Double?
    @State private var committedEnd: Double?
    /// Same arrangement for the framing: the window was handed a snapshot, so
    /// what has been saved since lives here.
    @State private var committedFraming: ViewModel.Framing?
    @State private var cropping = false
    /// **Whether arrows are being drawn**, and which one is picked up — a mode
    /// on this window rather than a sheet, so it can be checked and so the
    /// picture stays where it is while it is marked.
    @State private var drawingArrows = false
    @State private var pickedArrow: Int?
    /// **Print Frame mode** — the same window turned into the shot's Print
    /// Frame editor (`PrintFrameEditor`), for a picture or clip on a shot.
    @State private var printing = Launch.printFrame
    /// **The player, owned here rather than inside the view that draws it.**
    /// See `ClipView` for why that distinction is the whole of an earlier bug.
    @StateObject private var clip = ClipView()

    init(subject: Viewer.Subject, file: URL, state: ShellState, eye: Viewer.Eye) {
        self.subject = subject
        self.file = file
        self.state = state
        self.eye = eye
        _committedStart = State(initialValue: subject.trimStart)
        _committedEnd = State(initialValue: subject.trimEnd)
        _printing = State(initialValue: Launch.printFrame || subject.printToken != nil)
    }

    private var dark: Bool { scheme == .dark }

    private var isPDF: Bool { subject.ext.lowercased() == "pdf" }
    /// **A GIF moves, and it is not a clip.** Until 2026-08-29 this window
    /// asked one question — *does it move?* — and sent everything that did to
    /// `AVPlayerView`, which cannot decode a GIF at all: opening one gave a
    /// black rectangle with a transport under it. It also offered the GIF
    /// scissors and *use this frame as the still*, neither of which means
    /// anything to a GIF and neither of which could work, since there was no
    /// player item behind them. The frames window has branched on this since
    /// the day it was written; the viewer never did.
    ///
    /// The sniffed extension wins where it is decisive — this is the one
    /// window that reads the bytes themselves (`actually`) — and the engine's
    /// own judgement answers otherwise.
    private var isGif: Bool {
        subject.ext.lowercased() == "gif" || Ingest.isGif(subject.ext, kind: subject.kind)
    }
    private var isMovie: Bool {
        !isGif && Ingest.isMovie(subject.ext, kind: subject.kind)
    }
    /// A clip with nowhere on the project to remember a trim against — opened
    /// from somewhere that never attached it as a use of a file.
    private var trimmable: Bool { isMovie && subject.ref != nil }

    /// **Decoded once, kept for the session.** His report, twice: a delay
    /// stepping between photos. The first cause was asking the filesystem
    /// where else a file lived on every click — fixed at `follow()` above. The
    /// second is this: `body` re-evaluates for reasons that have nothing to do
    /// with which picture is showing — the pin toggling, an unrelated engine
    /// update — and `NSImage(contentsOf:)` decoded straight from disk every
    /// single time. `Thumbs` solved this exact problem for the walls; the
    /// viewer wants the same answer, keyed by the file it already wrote once.
    private static var decoded: [String: NSImage] = [:]
    static func decoded(_ file: URL) -> NSImage? {
        if let held = decoded[file.path] { return held }
        guard let made = NSImage(contentsOf: file) else { return nil }
        decoded[file.path] = made
        return made
    }

    /// A file the Mac cannot draw is not a dead end: it is kept whole in the
    /// project, and the Mac's own apps can open it.
    private var unreadable: some View {
        EmptyState(title: "Can’t preview this \(subject.ext.uppercased()) file") {
            Button("Open in another app") { NSWorkspace.shared.open(file) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// **The shot this picture is on**, if it is on one — what offers the
    /// Print Frame switch. A location's or a board's picture has none.
    private var owner: ViewModel.Row? {
        guard let ref = subject.ref, !isPDF else { return nil }
        return state.view?.allRows.first { $0.stills.contains { $0.ref == ref } }
    }

    var body: some View {
        VStack(spacing: 0) {
            bar
            if printing, let row = owner {
                PrintFrameEditor(state: state, shot: row.shot, opened: subject.ref) {
                    printing = false
                }
            } else {
                media
            }
        }
        .background(Brand.surface(dark))
        // **Outside the view update**, which is the whole point: this writes
        // to an object the update cycle is not allowed to swallow.
        .task(id: file) {
            guard isMovie else { return }
            clip.show(file, start: committedStart, end: committedEnd)
        }
        .onChange(of: printing) { _, on in
            guard on else { return }
            clip.view.player?.pause()
            drawingArrows = false
            Self.roomForTheBoard()
        }
        .onAppear {
            if subject.printToken != nil, owner != nil { printing = true }
            if printing { Self.roomForTheBoard() }
        }
        .onChange(of: subject.printToken) { _, token in
            if token != nil, owner != nil { printing = true }
        }
        .sheet(isPresented: $cropping) {
            if let ref = subject.ref, let picture = ViewerContent.decoded(file) {
                CropSheet(state: state, ref: ref, picture: picture,
                          filename: subject.filename, start: framing)
            }
        }
    }

    /// The editor wants a board, a strip and an inspector: a pop-out left at
    /// its picture size grows to fit them, on its own screen.
    private static func roomForTheBoard() {
        DispatchQueue.main.async {
            guard let w = NSApp.windows.first(where: {
                $0.identifier?.rawValue == "viewer" && $0.isKeyWindow
            }) ?? NSApp.windows.first(where: { $0.identifier?.rawValue == "viewer" && $0.isVisible }),
                  let screen = w.screen?.visibleFrame else { return }
            let want = CGSize(width: min(max(w.frame.width, 1180), screen.width),
                              height: min(max(w.frame.height, 780), screen.height))
            guard want != w.frame.size else { return }
            var frame = CGRect(x: w.frame.midX - want.width / 2, y: w.frame.maxY - want.height,
                               width: want.width, height: want.height)
            frame.origin.x = min(max(frame.minX, screen.minX), screen.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, screen.minY), screen.maxY - frame.height)
            w.setFrame(frame, display: true, animate: false)
        }
    }

    /// The picture, the clip or the document, as the viewer always drew it.
    @ViewBuilder private var media: some View {
        VStack(spacing: 0) {
            if drawingArrows, let ref = subject.ref {
                ArrowTools(state: state, ref: ref, arrows: marks,
                           visible: Plate.visible(
                               picture: ViewerContent.decoded(file)?.size ?? .zero,
                               ratio: CGFloat(state.view?.project.ratio ?? 2.39),
                               framing: framing),
                           selected: $pickedArrow)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            Group {
                if isPDF, let document = PDFDocument(url: file) {
                    PDFPages(document: document, dark: dark)
                } else if isPDF {
                    // An empty PDFView is a black rectangle, which is how a
                    // deck that failed to open looked like a working window
                    // showing nothing.
                    unreadable
                } else if isGif {
                    // `NSImageView` animates one; SwiftUI's `Image` draws a
                    // single frame of it and stops.
                    Animated(file: file, fill: false)
                } else if isMovie {
                    Movie(view: clip.view)
                } else if let picture = ViewerContent.decoded(file) {
                    if drawingArrows, let ref = subject.ref {
                        // **Composed in the film's frame, not on the whole
                        // photograph** — his instruction, 2026-08-31. This
                        // window still *shows* a picture whole when it is not
                        // being marked, because it is the viewer for boards
                        // and locations too, and a scouting photograph is not
                        // a shot.
                        ArrowBoard(state: state, ref: ref, picture: picture,
                                   framing: framing,
                                   ratio: CGFloat(state.view?.project.ratio ?? 2.39),
                                   stored: marks, selected: $pickedArrow)
                    } else {
                        Picture(image: picture, dark: dark, arrows: marks)
                    }
                } else {
                    unreadable
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// **The arrows on this picture now.** `subject` is a snapshot handed in
    /// when the window opened, so the engine's live view is asked first — the
    /// same arrangement `framing` uses just below, and the reason a mark made
    /// here appears without the window being reopened.
    private var marks: [ViewModel.Arrow] {
        guard let ref = subject.ref else { return [] }
        if let found = state.view?.allRows
            .flatMap({ $0.stills })
            .first(where: { $0.ref == ref }) {
            return found.marks
        }
        return []
    }

    /// **What the framing is now**, which is not what the window was opened
    /// with once he has saved one: `subject` is a snapshot. The live view is
    /// asked first and the snapshot is the fallback — the same arrangement the
    /// trim uses two fields above.
    private var framing: ViewModel.Framing {
        if let committedFraming { return committedFraming }
        guard let ref = subject.ref else { return subject.framing }
        if let found = state.view?.allRows
            .flatMap({ $0.stills })
            .first(where: { $0.ref == ref }) {
            return found.framing
        }
        return subject.framing
    }

    /// Hands the clip to Apple's own trim bar, and files whatever comes back.
    private func startTrimming() {
        guard let ref = subject.ref else { return }
        clip.trim(from: committedStart, to: committedEnd,
                  whenStuck: { state.say($0) }) { start, end in
            committedStart = start
            committedEnd = end
            state.replace(state.engine?.trim(ref, start: start, end: end))
            clip.show(file, start: start, end: end, force: true)
        }
    }

    /// Back to playing the whole clip — his rule holds here too: the file was
    /// never touched, so there is nothing to undo, only a range to forget.
    private func resetTrim() {
        guard let ref = subject.ref else { return }
        state.replace(state.engine?.clearTrim(ref))
        committedStart = nil
        committedEnd = nil
        clip.show(file, start: nil, end: nil, force: true)
    }

    /// **The bar, and only the bar, is shared** — `PopoutBar` in `Controls.swift`.
    /// His note, before any of this existed: *"the scene diagram viewer and the
    /// media viewer have different designs in general. One's all black, and
    /// one's gray with the white grid. Can we just make them feel more
    /// similar."* They do different jobs and always will; what they can share
    /// is their chrome, and chrome is most of what makes two windows read as
    /// one app.
    ///
    /// What hangs on the right is this window's alone, and changes with the
    /// file: a picture gets zoom (drawn over the picture itself), a clip gets
    /// the poster grab and the trim, a GIF gets neither because neither means
    /// anything to one.
    private var bar: some View {
        PopoutBar(title: subject.filename,
                  count: subject.place,
                  caption: subject.caption) {
            // **Clip | Print Frame**, or **Picture | Print Frame** — the same
            // window, turned into the board that stands for the shot on paper.
            if owner != nil, !isPDF {
                Segmented(selection: $printing, items: [
                    .init(value: false, title: isMovie ? "Clip" : "Picture"),
                    .init(value: true, title: "Print Frame"),
                ], quiet: true)
                .fixedSize()
                .overlay { Capsule(style: .continuous).strokeBorder(Brand.rule2(dark), lineWidth: 1) }
            }
            if isMovie {
                ToolButton(icon: "camera.viewfinder", size: 11,
                           help: "Use this frame as the still",
                           action: useThisFrame)
                ToolButton(icon: "photo.badge.arrow.down", size: 11,
                           help: "Export this frame") {
                    FrameExport.save(clip.view.player?.currentItem,
                                     clip: subject.filename, offset: committedStart,
                                     say: { state.say($0) })
                }
            }
            // **A still gets the crop; a clip does not.** What draws a clip is
            // a player, and moving a player's picture inside its own layer is
            // a different job — noted on the phone too, not built on either.
            if !isMovie, !isGif, subject.ref != nil {
                ToolButton(icon: "crop", size: 11,
                           help: framing.isMiddle
                               ? "Crop"
                               : "Edit Crop",
                           lit: !framing.isMiddle) {
                    cropping = true
                }
            }
            // **Arrows on a still, and only a still** — a clip is drawn by a
            // player, and a mark laid over one would be on the window rather
            // than on the picture.
            if !isMovie, !isGif, subject.ref != nil, !printing {
                ToolButton(icon: "arrow.up.right", size: 11,
                           help: drawingArrows ? "Stop drawing arrows"
                               : (marks.isEmpty
                                  ? "Draw storyboard arrows on this picture"
                                  : "Edit Arrows"),
                           lit: drawingArrows || !marks.isEmpty) {
                    drawingArrows.toggle()
                    pickedArrow = nil
                }
            }
            if trimmable {
                let trimmed = committedStart != nil || committedEnd != nil
                ToolButton(icon: "scissors", size: 11,
                           help: trimmed
                               ? "Edit Trim"
                               : "Trim this clip's in and out points",
                           lit: trimmed,
                           action: startTrimming)
            }
            ToolButton(icon: eye.pinned ? "pin.fill" : "pin", size: 11,
                       help: eye.pinned
                           ? "Pinned"
                           : "Pin",
                       lit: eye.pinned) {
                eye.pinned.toggle()
            }
            ToolMenu(help: "More") {
                // **Where else this exact file lives.** A photograph is in the
                // project package and, once the Drive bridge has run, in
                // Google Drive as well — and "where is it really" is a question
                // a producer asks him, not a question about software.
                // Worked out here, as the menu opens — see `Subject.places`.
                let places = subject.places()
                ForEach(places) { place in
                    Button("Show in \(place.label)") {
                        NSWorkspace.shared.activateFileViewerSelecting([place.url])
                    }
                }
                if !places.isEmpty { Divider() }
                Button("Open in another app") { NSWorkspace.shared.open(file) }
                Button("Save a copy…", action: saveACopy)
                // Only worth offering once there is a trim to undo, and the
                // one thing the native trim bar has no button for.
                if trimmable, committedStart != nil || committedEnd != nil {
                    Divider()
                    Button("Play the whole clip", action: resetTrim)
                }
            }
        }
    }

    private func useThisFrame() {
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
        state.engine?.poster(hash: subject.hash, data: made)
        // The picture just changed under a hash the app may already have
        // decoded and held onto — forget it, or the old one keeps drawing.
        Thumbs.shared.forget(subject.hash)
        state.replace(state.engine?.view())
        state.say("Using this frame as the still")
    }

    private func saveACopy() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = subject.filename.isEmpty
            ? "\(subject.hash).\(subject.ext)" : subject.filename
        guard panel.runModal() == .OK, let to = panel.url else { return }
        try? FileManager.default.removeItem(at: to)
        try? FileManager.default.copyItem(at: file, to: to)
    }
}

/// **One frame of a clip, out to a file of his own** — his ask, 2026-10-13:
/// *"an ability to export any frame from a video at the click of a button."*
///
/// The exact frame the player is paused on, not the nearest keyframe, at the
/// clip's full stored size, as a PNG. Shared by the pop-out viewer and the
/// frames window, the two places a clip plays.
enum FrameExport {
    static func save(_ item: AVPlayerItem?, clip: String, offset: Double?,
                     say: (String) -> Void) {
        guard let item else { return }
        let generator = AVAssetImageGenerator(asset: item.asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let at = item.currentTime()
        guard let cg = try? generator.copyCGImage(at: at, actualTime: nil),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
        else {
            say("Could not read that frame")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = name(clip: clip,
                                          seconds: (offset ?? 0) + max(at.seconds, 0))
        guard panel.runModal() == .OK, let to = panel.url else { return }
        do {
            try png.write(to: to, options: .atomic)
            say("Frame exported")
        } catch {
            say("Could not save that frame")
        }
    }

    /// `IMG_2210 0m27.40s.png`: the clip's own name and where in it, counted
    /// from the start of the whole clip even when it is trimmed, so two
    /// frames from one clip never come out with the same name.
    static func name(clip: String, seconds: Double) -> String {
        let stem = clip.isEmpty ? "Frame"
            : (clip as NSString).deletingPathExtension
        let whole = Int(seconds)
        let rest = seconds - Double(whole)
        let tail = String(format: "%dm%05.2fs", whole / 60, Double(whole % 60) + rest)
        return "\(stem) \(tail).png"
    }
}

/// **A strip that moves the window when dragged, and does nothing else.**
///
/// `NSWindow.isMovableByWindowBackground` used to do this job for these
/// titleless windows, and it did it for the *whole* window — which meant a
/// clip's own scrubber and the trim handles were fighting AppKit for every
/// drag, and losing: AppKit decides whether a mouse-down moves the window
/// before asking whether a SwiftUI gesture wanted it, so a drag begun on a
/// handle could still end up moving the window instead of the handle. This
/// claims the drag itself, deliberately, only where it is laid down — the
/// bar and the head, neither of which needs a drag for anything of its own —
/// so nothing below it has to win a race it was never going to win.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}
}

/// A picture, fit to the window and zoomable.
///
/// Fit is the resting state, and it has to be *computed*: inside a scroll view
/// a picture is offered unbounded space and takes its full pixel size, which
/// is why a 4K still opened looking like a close-up of somebody's shoulder.
/// The window's own size is measured and the picture scaled to it; zoom is a
/// multiplier on top of that, and only then does it need scrolling.
private struct Picture: View {
    let image: NSImage
    let dark: Bool
    /// **The storyboard arrows, painted on.** They belong to the photograph,
    /// so they zoom with it rather than floating over the window.
    var arrows: [ViewModel.Arrow] = []
    @State private var zoom: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let room = geo.size
            Group {
                if zoom <= 1.0001 {
                    // Fit, and nothing else in the way. `scaledToFit` inside a
                    // plain frame cannot be talked out of it; a scroll view
                    // offers unbounded space and the picture takes its full
                    // pixel size, which is what opened a 4K still looking like
                    // somebody's shoulder.
                    Fitted(picture: image, arrows: arrows)
                        .frame(width: room.width, height: room.height)
                } else {
                    let size = image.size
                    let fit = min(room.width / max(size.width, 1),
                                  room.height / max(size.height, 1))
                    ScrollView([.horizontal, .vertical]) {
                        ZStack {
                            Image(nsImage: image).resizable()
                            if !arrows.isEmpty { ArrowMarks(arrows: arrows) }
                        }
                        .frame(width: size.width * fit * zoom,
                               height: size.height * fit * zoom)
                    }
                }
            }
            .frame(width: room.width, height: room.height)
            .background(Color.black.opacity(dark ? 0.45 : 0.82))
            .onAppear { Viewer.measured(room: room, picture: image.size) }
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 6) {
                Button { zoom = max(1, zoom - 0.25) } label: { Image(systemName: "minus") }
                Button { zoom = 1 } label: { Text("Fit").sans(11) }
                Button { zoom = min(8, zoom + 0.25) } label: { Image(systemName: "plus") }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Brand.onImage)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .padding(12)
        }
    }
}

/// A PDF, page by page, with PDFKit's own scrolling and text selection — a
/// call sheet or a permit is read, not glanced at.
private struct PDFPages: NSViewRepresentable {
    let document: PDFDocument
    let dark: Bool

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        // The document goes on **before** autoScales: PDFKit computes the fit
        // from whatever it is holding at the moment the flag is set, and a
        // view told to auto-scale nothing keeps that scale when a document
        // arrives — which draws a page somewhere off in the dark.
        view.document = document
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.backgroundColor = dark ? NSColor.black.withAlphaComponent(0.45)
                                    : NSColor.black.withAlphaComponent(0.82)
        view.goToFirstPage(nil)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
            view.autoScales = true
            view.goToFirstPage(nil)
        }
    }
}

/// **One clip, played and trimmed by AVKit — not by us.**
///
/// Three rounds of hand-rolled transport went badly, and every fault was the
/// same shape: a control we wrote had to keep itself in step with a player
/// it did not own. His verdict, 2026-08-28 — *"the backend can't really be
/// dragged or trimmed. Playback is really funky, and the progress bar
/// doesn't reset to take up the full screen. It's kind of a mess"* — and his
/// instruction, to use *"Apple's native player with the trim feature built
/// in."* That is exactly what `AVPlayerView` is: the transport is Apple's,
/// and `beginTrimming` is the very trim bar QuickTime uses, both handles
/// draggable, already tested by somebody else.
///
/// **The trim is still non-destructive, and now it also *reads* right.** A
/// trimmed clip is shown as an `AVMutableComposition` holding only the
/// chosen range, so the item's own duration **is** the trimmed length: the
/// scrubber spans it end to end, playback starts at the in point and stops
/// at the out point, with no bounds arithmetic of ours anywhere. The file on
/// disk is never read for anything but its bytes, and pulling the handles
/// back out restores what was cut, because the composition is only ever a
/// window onto the whole asset.
///
/// The view is owned **here**, above SwiftUI, for the reason the last round
/// taught: anything handed upward out of `makeNSView` is written during a
/// view update, and SwiftUI discards that.
final class ClipView: ObservableObject {
    let view = AVPlayerView()

    /// What is on screen, as file and range — so asking twice costs nothing
    /// and a changed trim rebuilds.
    private var applied: String?
    private var file: URL?
    private var whole: AVURLAsset?

    init() {
        // The real thing: play/pause, a scrubber, volume, full screen. It is
        // also the precondition for trimming — `canBeginTrimming` is false
        // when the controls are hidden.
        view.controlsStyle = .inline
        view.player = AVPlayer()
    }

    var length: Double { whole.map { CMTimeGetSeconds($0.duration) } ?? 0 }

    /// Show a clip, trimmed to `start`–`end` when it has been.
    func show(_ file: URL, start: Double?, end: Double?, force: Bool = false) {
        let key = "\(file.path)|\(start ?? -1)|\(end ?? -1)"
        guard force || key != applied else { return }
        applied = key
        if self.file != file {
            self.file = file
            whole = AVURLAsset(url: file)
        }
        guard let whole else { return }
        view.player?.replaceCurrentItem(with: Clips.item(of: whole, from: start, to: end))
        Self.live = self
        say()
    }

    /// **Apple's own trim bar.** Trimming runs against the *whole* clip, with
    /// the existing range set as the handles' starting position — which is
    /// what lets a trim be widened again, not just narrowed.
    ///
    /// `whenStuck` is called if the player never offers to trim, so the app
    /// can say so out loud. The first version wrote that to stderr and
    /// returned, which is indistinguishable from a dead button — *"the
    /// scissors dont open the trim bar"* (2026-08-28).
    func trim(from: Double?, to: Double?,
              whenStuck: @escaping (String) -> Void = { _ in },
              done: @escaping (Double, Double) -> Void) {
        guard let whole, let player = view.player else { return }
        let full = AVPlayerItem(asset: whole)
        let length = CMTimeGetSeconds(whole.duration)
        full.reversePlaybackEndTime = CMTime(seconds: from ?? 0, preferredTimescale: 600)
        full.forwardPlaybackEndTime = CMTime(seconds: to ?? length, preferredTimescale: 600)
        player.replaceCurrentItem(with: full)
        // What is on screen is no longer the resting state.
        applied = nil
        offerToTrim(full, length: length, from: from, to: to,
                    waited: 0, whenStuck: whenStuck, done: done)
    }

    /// **Wait for the player to be willing.** `replaceCurrentItem` is
    /// asynchronous, and AVKit will not offer to trim an item it has not
    /// finished preparing — so `canBeginTrimming` is false for a few frames
    /// after a swap. Asking once, on the next runloop turn, is the whole
    /// reason the scissors appeared to do nothing at all.
    private func offerToTrim(_ full: AVPlayerItem, length: Double,
                             from: Double?, to: Double?, waited: Int,
                             whenStuck: @escaping (String) -> Void,
                             done: @escaping (Double, Double) -> Void) {
        if view.canBeginTrimming {
            if Launch.checking {
                FileHandle.standardError.write(Data(
                    "trim: bar opened after \(waited * 50)ms\n".utf8))
            }
            view.beginTrimming { [weak self] result in
                guard let self else { return }
                guard result == .okButton else {
                    // Cancelled — put back what was showing before.
                    if let file = self.file {
                        self.show(file, start: from, end: to, force: true)
                    }
                    return
                }
                // An untouched handle reads back as invalid, meaning "the
                // clip's own edge" — not as nought, which would silently
                // trim the wrong way.
                let s = full.reversePlaybackEndTime.isNumeric
                    ? CMTimeGetSeconds(full.reversePlaybackEndTime) : 0
                let e = full.forwardPlaybackEndTime.isNumeric
                    ? CMTimeGetSeconds(full.forwardPlaybackEndTime) : length
                done(s, e)
            }
            return
        }
        // Two seconds of asking, then give up and say so rather than
        // leaving a button that does nothing.
        guard waited < 40 else {
            if let file { show(file, start: from, end: to, force: true) }
            whenStuck("This clip can’t be trimmed")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.offerToTrim(full, length: length, from: from, to: to,
                              waited: waited + 1, whenStuck: whenStuck, done: done)
        }
    }

    /// **A console door onto the trim bar** — his standing rule, and this
    /// feature is the reason for it: the bar is reachable only by clicking,
    /// so without this nothing could ever check that it opens.
    static weak var live: ClipView?

    /// **What the player is actually holding**, for a checking run. A
    /// screenshot cannot tell a playing clip from a still of one frame, nor
    /// a trimmed item from an untrimmed one — and both shipped looking fine
    /// once. The item's own duration is the whole claim about trimming.
    private func say() {
        guard Launch.checking else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, let item = self.view.player?.currentItem else { return }
            FileHandle.standardError.write(Data(String(
                format: "clip: plays %.2fs of %.2fs  rate %.1f  playhead %.2f  trimmable %@\n",
                CMTimeGetSeconds(item.duration), self.length,
                self.view.player?.rate ?? 0, CMTimeGetSeconds(item.currentTime()),
                self.view.canBeginTrimming ? "yes" : "no").utf8))
        }
    }
}

/// The clip on screen. All behaviour lives in `ClipView` above; this only
/// puts its view where SwiftUI wants it.
struct Movie: NSViewRepresentable {
    let view: AVPlayerView
    func makeNSView(context: Context) -> AVPlayerView { view }
    func updateNSView(_ view: AVPlayerView, context: Context) {}
}
