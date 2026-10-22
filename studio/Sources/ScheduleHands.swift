import AppKit
import SwiftUI

/// **The hand that carries things on the Schedule** — and the reference
/// boards' list, which needed the same thing.
///
/// His report, 2026-09-29: *"when I try to drag scenes into the schedule,
/// reorder them etc, they just get stuck, won't come over, start multi
/// selecting, it all needs to get cleaned up to become usable."*
///
/// Every drag on this screen was a system drag session — `.onDrag` and
/// `.onDrop` — and that was the trouble in four ways at once:
///
/// - **"start multi selecting".** The scene list is an AppKit table. A press
///   that the drag source did not claim — the row's inset edges, a press a
///   hair too quick — went to the table instead, and a table answers a press
///   and a pull by selecting every row the pointer crosses.
/// - **"won't come over".** A drop could only read what it carried by
///   loading it asynchronously, so the card cached the first payload it saw
///   and kept it until a drop *landed* — a drag let go anywhere else left the
///   old one standing, and the next drag was drawn and judged as the last
///   one. Nested targets (card, strip, band) each lit and cleared on their own
///   schedule, and the line said one place while the drop went to another.
/// - **"stuck".** Nothing scrolled the board while a scene was held at its
///   edge, so a day below the fold could not be reached at all.
/// - **Nobody could check any of it.** No synthetic mouse can drive a drag
///   session, so every drop on this board was only ever tried by his hand.
///
/// So the board carries things itself. It watches every press and lets it
/// through untouched, so a click is exactly the click it always was — it
/// selects, ⌘ and ⇧ add, the chevron opens, a double-click opens the scene.
/// If a press on something that can be carried then moves four points, it is
/// a drag: the hand takes over, stops the list's own drag-selection in its
/// tracks, draws what it holds under the pointer, finds where it would land
/// from the frames of what is on screen, and on letting go makes **one engine
/// call**. Nothing picks up rows the pointer crosses.
///
/// **Watch, don't hold back.** The first version held a press back and
/// handed it on at release. On this macOS the list and SwiftUI's taps hear
/// the mouse through gesture recognizers, which get every event whether or
/// not a monitor keeps it — so a held-back click arrived twice, and a single
/// click on a strip's chevron read as a double-click and jumped to Shot List.
/// Measured 2026-09-29 with `--mouse`; don't go back to it.
///
/// Where things are is read from AppKit views laid behind each strip, card,
/// band, row and date (`BoardMarkTag`) — window coordinates, the same ones the
/// pointer arrives in, so scrolling, list recycling and SwiftUI's own
/// coordinate spaces cannot put the two out of step.
enum BoardMark: Hashable {
    /// A scene's strip on one day — carried, and measured for where a drop
    /// goes between strips.
    case strip(scene: String, day: String)
    /// One shot of an opened strip.
    case shot(placement: String, day: String)
    /// One shot in a day's running order, under Shooting Order.
    case run(placement: String, day: String)
    /// A day's band — the handle a whole day is carried by.
    case band(day: String)
    /// A day's whole card — where a scene is let go.
    case card(day: String)
    /// A scene in the sidebar list, on the Schedule tab.
    case row(scene: String)
    /// One shot of a scene opened in the sidebar list — a shot still on no
    /// day, which can be carried onto one by itself.
    case loose(placement: String)
    /// The little chevron on a scene's row that opens its shots still on no
    /// day. A click there is the hand's own: the list never hears it.
    case opener(scene: String)
    /// The sidebar's scene list, as a place to put a strip back.
    case list
    /// A date in the calendar panel — a day let go there takes the date.
    case date(String)
    /// The board's scrolling column, for edges that scroll while a thing is
    /// held at them.
    case board
    /// A reference board in the Boards tab's sidebar.
    case boardRow(String)
    /// That list, for where a board is let go.
    case boardList

    /// Whether SwiftUI's own layout says where this is (the board and the
    /// calendar), rather than an AppKit table cell (the two lists).
    var drawnBySwiftUI: Bool {
        switch self {
        case .row, .loose, .opener, .list, .boardRow, .boardList: return false
        default: return true
        }
    }

    /// Whether a press here can pick something up.
    var carries: Bool {
        switch self {
        case .strip, .shot, .run, .band, .row, .loose, .boardRow: return true
        default: return false
        }
    }
}

/// What the hand is holding.
enum BoardCarry: Equatable {
    /// Scenes — one strip, or every picked scene from the list. `from` is the
    /// day they were lifted off; `nil` from the scene list, which means whole.
    case scenes([String], from: String?)
    case shot(String, from: String)
    /// Shots still on no day, out of a scene opened in the scene list.
    case loose([String])
    case day(String)
    case board(String)
}

/// Where it would land if let go now.
enum BoardSpot: Equatable {
    /// On a day, ahead of the strip at `index` — or last, at `count`.
    case into(day: String, index: Int)
    /// A day, at this place among the days.
    case dayAt(Int)
    /// A day, onto a calendar date.
    case date(String)
    /// Off every day — let go on the scene list.
    case off
    /// A reference board, at this place in its list.
    case boardAt(Int)
}

/// The pointer and the words it carries, apart from `BoardHands` on purpose:
/// they change on every mouse movement, and the board redrawn at mouse rate is
/// the flicker this was written to end. Only the ghost reads them.
final class BoardPointer: ObservableObject {
    static let shared = BoardPointer()
    /// In the window's content, top-left origin — SwiftUI's global space.
    @Published var at: CGPoint = .zero
    @Published var words = ""
}

final class BoardHands: ObservableObject {
    static let shared = BoardHands()

    @Published private(set) var carry: BoardCarry?
    @Published private(set) var spot: BoardSpot?

    private let marks = NSHashTable<MarkView>.weakObjects()
    private var monitor: Any?
    /// A press on something carriable, watched until it is known to be a
    /// click (it lets go) or a drag (it moves four points).
    private var pending: (event: NSEvent, mark: BoardMark)?
    /// The list's own gesture recognizers, switched off for the length of a
    /// carry — see `quietTable`.
    private var silenced: [NSGestureRecognizer] = []
    /// The list a press on one of its rows was kept from — see `pressed`.
    private var heldFrom: NSTableView?
    /// A press and its release handed back to the list, let through when
    /// they come round again — known by type and time.
    private var givenBack: [(NSEvent.EventType, TimeInterval)] = []
    /// Which way a press on a list's row is handled — `hold` (the answer),
    /// or `resign` / `none` for a check comparing it with what came before.
    static let rowPress = ProcessInfo.processInfo.environment["SHOTLISTER_HANDFIX"] ?? "hold"
    private var window: NSWindow?
    private var lastPoint: CGPoint = .zero
    private var scrollTimer: Timer?
    /// Said by checks: what the last press did — "click", "carry …", "land …".
    private(set) var log: [String] = []

    // --------------------------------------------------------------- marks

    fileprivate func register(_ view: MarkView) {
        marks.add(view)
        install()
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown]
        ) { [weak self] event in
            self?.decide(event) ?? event
        }
        // Switched away from mid-drag, the release goes to another program
        // and this never hears it — so the thing in hand goes back where it
        // came from, rather than hanging under a pointer that has left.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.carry != nil { self.end(landing: false) }
            // A press held from the list, and the release gone elsewhere.
            if self.heldFrom != nil { self.heldFrom = nil; self.pending = nil; self.wake() }
        }
    }

    /// **Where SwiftUI drew each board mark**, in its global space — the
    /// window's content, top left. Written by `boardMark(_:)`.
    ///
    /// An AppKit view's own frame cannot be trusted for this inside the
    /// board: SwiftUI hosts it in a group container and places it by other
    /// means, so every strip's view reported its whole card's frame and every
    /// card the whole board's. Measured 2026-09-29 — a press on a strip
    /// picked up its day. The list rows are different: they sit in the
    /// table's own cells, whose AppKit frames are true, so those are read
    /// from AppKit (`BoardMark.drawnBySwiftUI`).
    fileprivate var drawn: [BoardMark: CGRect] = [:]

    /// A mark's frame in window coordinates, unclipped.
    private func frame(of view: MarkView, in window: NSWindow) -> CGRect {
        if view.mark.drawnBySwiftUI, let global = drawn[view.mark], let root = window.contentView {
            return root.convert(global, to: nil)
        }
        return view.convert(view.bounds, to: nil)
    }

    /// What a mark can be seen through: the board's scrolling column for
    /// everything on the board, nothing for the rest.
    private func clip(for mark: BoardMark, in window: NSWindow) -> CGRect? {
        switch mark {
        case .strip, .shot, .run, .band, .card: return boardFrame(in: window)
        default: return nil
        }
    }

    /// Every mark on screen in `window`, with its visible frame in window
    /// coordinates. Marks off screen, scrolled away or recycled out of a list
    /// are left out.
    private func placed(in window: NSWindow) -> [(mark: BoardMark, frame: CGRect)] {
        marks.allObjects.compactMap { view in
            guard view.window === window, !view.isHiddenOrHasHiddenAncestor else { return nil }
            var seen = frame(of: view, in: window)
            if view.mark.drawnBySwiftUI {
                if let clip = clip(for: view.mark, in: window) { seen = seen.intersection(clip) }
            } else {
                let visible = view.visibleRect
                guard !visible.isEmpty else { return nil }
                seen = view.convert(visible, to: nil)
            }
            guard !seen.isEmpty else { return nil }
            return (view.mark, seen)
        }
    }

    /// The whole frame, not only the visible part — for measuring where a
    /// strip's middle is when half of it has scrolled away.
    ///
    /// Scrolled-away strips count too: a day's cards all stay in the window
    /// whether or not they are in view, and a drop is counted against every
    /// strip above it, not only the ones on screen. Where a recycled list row
    /// leaves two views naming one thing, the one in view wins.
    private func whole(_ mark: BoardMark, in window: NSWindow) -> CGRect? {
        let named = marks.allObjects.filter {
            $0.window === window && $0.mark == mark && !$0.isHiddenOrHasHiddenAncestor
        }
        let view = named.first { !$0.visibleRect.isEmpty } ?? named.first
        return view.map { frame(of: $0, in: window) }
    }

    private func scroller(in window: NSWindow) -> NSScrollView? {
        marks.allObjects.first { $0.window === window && $0.mark == .board }?.enclosingScrollView
    }

    /// The board's scrolling column as it stands on screen — the scroll
    /// view's own frame, which AppKit does keep true.
    private func boardFrame(in window: NSWindow) -> CGRect? {
        scroller(in: window).map { $0.convert($0.bounds, to: nil) }
    }

    // --------------------------------------------------------------- events

    private func decide(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .leftMouseDown: return pressed(event)
        case .leftMouseDragged: return pulled(event)
        case .leftMouseUp: return released(event)
        case .keyDown:
            // Escape puts it down where it came from.
            if carry != nil, event.keyCode == 53 {
                end(landing: false)
                return nil
            }
            return undoKey(event)
        default: return event
        }
    }

    private func pressed(_ event: NSEvent) -> NSEvent? {
        if let at = givenBack.firstIndex(where: { $0.0 == event.type && $0.1 == event.timestamp }) {
            givenBack.remove(at: at)
            return event
        }
        // A press while something is still held means the release went
        // somewhere this never saw. Put it down rather than leave it stuck.
        if carry != nil { end(landing: false) }
        // Whatever the last press switched off is on again: that press is over.
        silenced.forEach { $0.isEnabled = true }
        silenced = []
        pending = nil
        guard let window = event.window,
              event.clickCount < 2,
              !event.modifierFlags.contains(.control),
              let mark = source(at: event.locationInWindow, in: window) else { return event }
        pending = (event, mark)
        self.window = window
        heldFrom = nil
        // **A press on a list's row is kept from the list until it is known
        // to be a click.** His report, 2026-09-30, on 0.6.1: the first scene
        // dragged over fine, the next "doesn't really move, and it ends up
        // highlighting the length of wherever my mouse went". Once the list
        // has the keyboard — which the first press gives it — a press and a
        // pull there is the list's own: it selects every row the pointer
        // crosses, in a loop of its own that takes the mouse and never lets
        // this monitor see it again. So the press goes nowhere yet. A pull
        // becomes a carry; a release hands the list the very press it would
        // have had, and its click — selection, ⌘ and ⇧ — is its own as ever.
        if case .row = mark, let list = table(at: event.locationInWindow, in: window) { hold(list, in: window) }
        if case .loose = mark, let list = table(at: event.locationInWindow, in: window) { hold(list, in: window) }
        if case .boardRow = mark, let list = table(at: event.locationInWindow, in: window) { hold(list, in: window) }
        if heldFrom != nil { return nil }
        if ProcessInfo.processInfo.environment["SHOTLISTER_HANDDEBUG"] != nil, let root = window.contentView {
            var node = root.hitTest(root.convert(event.locationInWindow, from: nil))
            var out = "handdebug: press on \(mark)\n"
            while let here = node {
                let gs = here.gestureRecognizers.map { "\(type(of: $0))[\($0.isEnabled ? "on" : "off") \($0.state.rawValue)]" }
                out += "  \(type(of: here))\(gs.isEmpty ? "" : " " + gs.joined(separator: ","))\(here === window.firstResponder ? " (first responder)" : "")\n"
                node = here.superview
            }
            FileHandle.standardError.write(Data(out.utf8))
        }
        return event
    }

    private func pulled(_ event: NSEvent) -> NSEvent? {
        if carry != nil {
            move(to: event.locationInWindow)
            return nil
        }
        guard let pending else { return event }
        let from = pending.event.locationInWindow, to = event.locationInWindow
        // Held from the list, the small pull before a carry is nobody's.
        guard hypot(to.x - from.x, to.y - from.y) >= 4 else { return heldFrom != nil ? nil : event }
        self.pending = nil
        guard let lifted = lift(pending.mark) else {
            giveBack(pending.event, then: nil)
            wake()
            return event
        }
        heldFrom = nil
        quietTable(at: from)
        carry = lifted.carry
        BoardPointer.shared.words = lifted.words
        log.append("carry \(lifted.words)")
        NSCursor.closedHand.push()
        startScrolling()
        move(to: to)
        return nil
    }

    private func released(_ event: NSEvent) -> NSEvent? {
        if let at = givenBack.firstIndex(where: { $0.0 == event.type && $0.1 == event.timestamp }) {
            givenBack.remove(at: at)
            return event
        }
        if carry != nil {
            move(to: event.locationInWindow)
            end(landing: true)
            return nil
        }
        if pending != nil { log.append("click") }
        // **Two clicks in the scene list are the hand's own**, because the
        // list's rows do not pass a click on to a button inside them: the
        // chevron that opens a scene's shots still on no day, and picking
        // one of those shots. Neither reaches the list, so neither selects.
        if let held = pending, let window = held.event.window ?? self.window {
            let p = held.event.locationInWindow
            if let scene = opener(at: p, in: window) {
                let state = ShellState.shared
                if state.openRemainders.contains(scene) { state.openRemainders.remove(scene) } else { state.openRemainders.insert(scene) }
                log.append("opened \(state.openRemainders.contains(scene) ? "on" : "off")")
                pending = nil; heldFrom = nil; wake()
                return nil
            }
            if case let .loose(placement) = held.mark {
                let flags = held.event.modifierFlags
                ShellState.shared.pickLoose(placement, adding: flags.contains(.command) || flags.contains(.shift))
                log.append("picked shot")
                pending = nil; heldFrom = nil; wake()
                return nil
            }
        }
        if let held = pending?.event, heldFrom != nil {
            pending = nil
            giveBack(held, then: event)
            wake()
            return nil
        }
        pending = nil
        return event
    }

    /// The list's own gestures back on — after this release has gone by, so
    /// the list does not take it for the end of a gesture of its own.
    private func wake() {
        let quiet = silenced
        silenced = []
        DispatchQueue.main.async { quiet.forEach { $0.isEnabled = true } }
    }

    /// The scene whose row chevron is under a point, if any.
    private func opener(at point: CGPoint, in window: NSWindow) -> String? {
        for item in placed(in: window) {
            if case let .opener(scene) = item.mark, item.frame.insetBy(dx: -4, dy: -4).contains(point) { return scene }
        }
        return nil
    }

    /// The list under a point, if any.
    private func table(at point: CGPoint, in window: NSWindow) -> NSTableView? {
        guard let root = window.contentView else { return nil }
        var node = root.hitTest(root.convert(point, from: nil))
        while let here = node {
            if let list = here as? NSTableView { return list }
            node = here.superview
        }
        return nil
    }

    private func hold(_ list: NSTableView, in window: NSWindow) {
        switch Self.rowPress {
        case "hold":
            heldFrom = list
            // …and the list's own pull and press-and-hold are switched off
            // for as long as the button is down, in case either is how it
            // takes the mouse: they hear a press whatever this monitor does
            // with it. Its clicks stay on — they are how a row answers one.
            for recognizer in list.gestureRecognizers
            where recognizer.isEnabled && !(recognizer is NSClickGestureRecognizer) {
                recognizer.isEnabled = false
                silenced.append(recognizer)
            }
        case "resign": if window.firstResponder === list { window.makeFirstResponder(nil) }
        default: break
        }
    }

    /// **The press, handed back to the list it was kept from** — a click
    /// after all. Both go round again, the press ahead of its release, so
    /// the list takes them the way it always has: the keyboard, the
    /// selection, ⌘ and ⇧ read off the press itself. (Handed straight to the
    /// list's `mouseDown`, ⌘ and ⇧ were lost: it reads the keys held at the
    /// moment, which by then belonged to the release.)
    private func giveBack(_ press: NSEvent, then release: NSEvent?) {
        guard heldFrom != nil else { return }
        heldFrom = nil
        givenBack.append((press.type, press.timestamp))
        if let release {
            givenBack.append((release.type, release.timestamp))
            NSApp.postEvent(release, atStart: true)
        }
        NSApp.postEvent(press, atStart: true)
    }

    /// **⌘Z takes back a drop, on the two screens this hand works.** The
    /// document's undo lives in the shot list's own keyboard
    /// (`Shortcuts.handle`), which only listens on the Shot List tab — so on
    /// the Schedule and the reference boards, one drop being one undo step
    /// meant nothing: ⌘Z did not reach the engine at all. It does here, as
    /// long as nobody is typing (the search box keeps its own ⌘Z).
    private func undoKey(_ event: NSEvent) -> NSEvent? {
        let state = ShellState.shared
        guard event.modifierFlags.contains(.command),
              event.charactersIgnoringModifiers?.lowercased() == "z",
              state.sideTab == .schedule || state.sideTab == .boards,
              let window = event.window, window.attachedSheet == nil,
              !(window.firstResponder is NSText) else { return event }
        if event.modifierFlags.contains(.shift) { state.redo() } else { state.undo() }
        return nil
    }

    /// **The list stops selecting the moment the hand takes over.** A table
    /// answers a press and a pull by selecting every row the pointer crosses
    /// — "start multi selecting" — and it hears the pull through its own
    /// gesture recognizers, which see every event whatever a monitor does
    /// with it. Switching them off cancels the gesture in flight; they come
    /// back on once the carry is put down. Only a list's: a strip, a band and
    /// a shot are SwiftUI's, and a press and a pull on them means nothing to
    /// anyone but the hand.
    private func quietTable(at point: CGPoint) {
        guard let root = window?.contentView else { return }
        var node = root.hitTest(root.convert(point, from: nil))
        while let here = node, here !== root {
            if here is NSTableView {
                for recognizer in here.gestureRecognizers where recognizer.isEnabled {
                    recognizer.isEnabled = false
                    silenced.append(recognizer)
                }
                return
            }
            node = here.superview
        }
    }

    /// The smallest carriable mark under the pointer — a shot inside an open
    /// strip wins over the strip. A scene row answers across the list's whole
    /// width, not only its words: the edges were where presses used to fall
    /// through to the table and select everything they crossed.
    private func source(at point: CGPoint, in window: NSWindow) -> BoardMark? {
        let all = placed(in: window)
        let list = all.first { $0.mark == .list }?.frame
        let boards = all.first { $0.mark == .boardList }?.frame
        return all
            .filter { $0.mark.carries }
            .map { item -> (BoardMark, CGRect) in
                var frame = item.frame
                if case .row = item.mark, let list {
                    frame = CGRect(x: list.minX, y: frame.minY, width: list.width, height: frame.height)
                }
                if case .loose = item.mark, let list {
                    // A hair narrower than a scene's row, so where the two
                    // share a line the shot, the smaller, wins.
                    frame = CGRect(x: list.minX + 1, y: frame.minY, width: list.width - 2, height: frame.height)
                }
                if case .boardRow = item.mark, let boards {
                    frame = CGRect(x: boards.minX, y: frame.minY, width: boards.width, height: frame.height)
                }
                return (item.mark, frame)
            }
            .filter { $0.1.contains(point) }
            .min { $0.1.width * $0.1.height < $1.1.width * $1.1.height }?
            .0
    }

    /// What pressing on `mark` picks up, and the words the ghost wears.
    private func lift(_ mark: BoardMark) -> (carry: BoardCarry, words: String)? {
        let state = ShellState.shared
        let days = state.stripBoard?.days ?? []
        switch mark {
        case let .strip(scene, day):
            let strip = days.first { $0.id == day }?.strips.first { $0.scene == scene }
            let words = strip.map { "\($0.number)  \($0.location.uppercased())" } ?? "Scene"
            return (.scenes([scene], from: day), words)
        case let .shot(placement, day):
            let shot = days.first { $0.id == day }?.strips.flatMap(\.shots).first { $0.placement == placement }
            return (.shot(placement, from: day), shot?.number ?? "Shot")
        case let .run(placement, day):
            let shot = days.first { $0.id == day }?.run.first { $0.placement == placement }
            return (.shot(placement, from: day), shot?.number ?? "Shot")
        case let .band(day):
            guard let lane = days.first(where: { $0.id == day }) else { return nil }
            return (.day(day), Schedule.dayName(lane))
        case let .row(scene):
            let scenes = state.dragScenes(for: scene)
            if scenes.count > 1 { return (.scenes(scenes, from: nil), "\(scenes.count) scenes") }
            // **What will travel, said on the chip** — his report,
            // 2026-10-17: a scene reading "Day 3 · 3 left" is carried as its
            // three, and the chip says so.
            let one = state.view?.scenes.first { $0.id == scene }
            return (.scenes([scene], from: nil), one.map { state.carryWords(for: $0) } ?? "Scene")
        case let .loose(placement):
            let shots = state.dragLoose(for: placement)
            return (.loose(shots), state.looseWords(shots))
        case let .boardRow(board):
            let name = state.view?.boards.first { $0.id == board }?.name ?? ""
            return (.board(board), name.isEmpty ? "Untitled" : name)
        default:
            return nil
        }
    }

    // -------------------------------------------------------------- moving

    private func move(to point: CGPoint) {
        lastPoint = point
        guard let window else { return }
        if let root = window.contentView {
            var at = root.convert(point, from: nil)
            if !root.isFlipped { at.y = root.bounds.height - at.y }
            BoardPointer.shared.at = at
        }
        let next = carry.flatMap { landing(for: $0, at: point, in: window) }
        if next != spot { spot = next }
    }

    /// **Where a thing would land**, from what is on screen now. One answer
    /// for the whole window, so two places can never light at once.
    private func landing(for carry: BoardCarry, at p: CGPoint, in window: NSWindow) -> BoardSpot? {
        let all = placed(in: window)
        func frame(_ mark: BoardMark) -> CGRect? { all.first { $0.mark == mark }?.frame }
        let state = ShellState.shared
        let days = state.stripBoard?.days ?? []

        switch carry {
        case .board:
            guard let list = frame(.boardList), list.insetBy(dx: 0, dy: -12).contains(p) else { return nil }
            let rows = state.boardsShown.map(\.id)
            // Above in the window is a larger y: count the rows whose middle
            // the pointer is below.
            let index = rows.filter { id in
                whole(.boardRow(id), in: window).map { $0.midY > p.y } ?? false
            }.count
            return .boardAt(index)

        case .day:
            for item in all where item.frame.contains(p) {
                if case let .date(date) = item.mark { return .date(date) }
            }
            guard let board = boardFrame(in: window), board.contains(p) else { return nil }
            let index = days.filter { day in
                whole(.card(day: day.id), in: window).map { $0.midY > p.y } ?? false
            }.count
            return .dayAt(index)

        case .scenes, .shot, .loose:
            let fromDay: Bool = {
                if case .scenes(_, let from) = carry { return from != nil }
                if case .loose = carry { return false }
                return true
            }()
            if fromDay, let list = frame(.list), list.contains(p) { return .off }
            guard let board = boardFrame(in: window), board.contains(p) else { return nil }
            // The card under the pointer — or, in the air between two, the
            // nearer one, so the gap between days is never a dead place.
            let cards = days.compactMap { day in whole(.card(day: day.id), in: window).map { (day, $0) } }
            let hit = cards.first { $0.1.contains(p) }
                ?? cards.filter { $0.1.minX <= p.x && p.x <= $0.1.maxX }
                    .map { ($0, min(abs($0.1.minY - p.y), abs($0.1.maxY - p.y))) }
                    .filter { $0.1 <= 14 }
                    .min { $0.1 < $1.1 }?.0
            guard let (day, _) = hit else { return nil }
            // Under Shooting Order the day is its shots, so the place is
            // counted among them.
            if state.stripRun {
                let index = day.run.filter { shot in
                    whole(.run(placement: shot.placement, day: day.id), in: window).map { $0.midY > p.y } ?? false
                }.count
                return .into(day: day.id, index: index)
            }
            let index = day.strips.filter { strip in
                whole(.strip(scene: strip.scene, day: day.id), in: window).map { $0.midY > p.y } ?? false
            }.count
            return .into(day: day.id, index: index)
        }
    }

    // ------------------------------------------------------------ letting go

    private func end(landing: Bool) {
        let held = carry, at = spot
        stopScrolling()
        carry = nil
        spot = nil
        pending = nil
        BoardPointer.shared.words = ""
        NSCursor.pop()
        // After this release has gone by, so the list does not take it for
        // the end of a click of its own.
        wake()
        guard landing, let held else {
            log.append("put back")
            return
        }
        guard let at else {
            log.append("let go nowhere")
            return
        }
        log.append("land \(Self.say(at))")
        Self.land(held, at: at, state: ShellState.shared)
    }

    /// **Every drop on the board, and the boards list, comes through here**,
    /// and each is one engine call — then a fresh board and a fresh view, the
    /// way every change in this app is drawn.
    static func land(_ carry: BoardCarry, at spot: BoardSpot, state: ShellState) {
        let days = state.stripBoard?.days ?? []
        func before(_ day: String, _ index: Int) -> String? {
            // Under Shooting Order the place is a shot's: scenes land ahead
            // of that shot's scene.
            if state.stripRun {
                let run = days.first { $0.id == day }?.run ?? []
                return index < run.count ? run[index].scene : nil
            }
            let strips = days.first { $0.id == day }?.strips ?? []
            return index < strips.count ? strips[index].scene : nil
        }
        switch (carry, spot) {
        case let (.shot(placement, _), .into(day, index)) where state.stripRun:
            state.seatShot(placement, on: day, at: index)
        case let (.scenes(scenes, from), .into(day, index)):
            state.putScenes(scenes, from: from, on: day, before: before(day, index))
        case let (.scenes(scenes, from?), .off):
            state.putScenes(scenes, from: from, on: nil, before: nil)
        case let (.shot(placement, _), .into(day, index)):
            state.afterBoard(state.engine?.putShot(placement, on: day, before: before(day, index)))
        case let (.loose(placements), .into(day, index)):
            state.putShots(placements, on: day, before: before(day, index))
        case let (.shot(placement, _), .off):
            state.assign(placement: placement, day: nil)
        case let (.day(day), .dayAt(index)):
            guard let from = days.firstIndex(where: { $0.id == day }) else { return }
            let to = index > from ? index - 1 : index
            if to != from { state.moveDay(day, to: to) }
        case let (.day(day), .date(date)):
            state.dropDay(day, onDate: date)
        case let (.board(board), .boardAt(index)):
            let rows = state.boardsShown.map(\.id)
            guard let from = rows.firstIndex(of: board) else { return }
            let to = index > from ? index - 1 : index
            guard to != from else { return }
            // The list may be narrowed by a search; the engine counts every
            // board, so the place is said as "before this one" in its terms.
            let others = (state.view?.boards ?? []).map(\.id).filter { $0 != board }
            let shown = rows.filter { $0 != board }
            let target: Int
            if to < shown.count {
                target = others.firstIndex(of: shown[to]) ?? others.count
            } else {
                target = shown.last.flatMap { others.firstIndex(of: $0) }.map { $0 + 1 } ?? others.count
            }
            state.replace(state.engine?.moveBoard(board, to: target))
        default:
            break
        }
    }

    static func say(_ spot: BoardSpot) -> String {
        switch spot {
        case let .into(day, index):
            let label = ShellState.shared.stripBoard?.days.first { $0.id == day }?.label ?? day
            return "\(label) at \(index)"
        case let .dayAt(index): return "day place \(index)"
        case let .date(date): return "date \(date)"
        case .off: return "off the board"
        case let .boardAt(index): return "board place \(index)"
        }
    }

    // ------------------------------------------------------------ scrolling

    /// **Held at the board's top or bottom edge, the board scrolls** — the
    /// "stuck" half of his report: a day below the fold could not be reached
    /// with a strip in hand, because nothing moved the board while one was.
    private func startScrolling() {
        stopScrolling()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            self?.scrollTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        scrollTimer = timer
    }

    private func stopScrolling() {
        scrollTimer?.invalidate()
        scrollTimer = nil
    }

    private func scrollTick() {
        guard carry != nil, let window, let scroll = scroller(in: window),
              let document = scroll.documentView else { return }
        let seen = scroll.convert(scroll.bounds, to: nil)
        guard seen.minX <= lastPoint.x, lastPoint.x <= seen.maxX else { return }
        let edge: CGFloat = 40
        // Window coordinates: the top edge is the larger y.
        var step: CGFloat = 0
        if lastPoint.y > seen.maxY - edge { step = -(edge - (seen.maxY - lastPoint.y)) }
        if lastPoint.y < seen.minY + edge { step = edge - (lastPoint.y - seen.minY) }
        guard step != 0 else { return }
        step = max(-edge, min(edge, step)) * 0.45
        let clip = scroll.contentView
        var origin = clip.bounds.origin
        let flipped = document.isFlipped
        let most = max(0, document.frame.height - clip.bounds.height)
        origin.y = max(0, min(most, origin.y + (flipped ? step : -step)))
        guard origin.y != clip.bounds.origin.y else { return }
        clip.scroll(to: origin)
        scroll.reflectScrolledClipView(clip)
        move(to: lastPoint)
    }

    // --------------------------------------------------------------- drawing

    /// Whether a strip is the one in hand, so it can stand dimmed where it was.
    func holds(scene: String, day: String) -> Bool {
        if case let .scenes(scenes, from) = carry, from == day { return scenes.contains(scene) }
        return false
    }

    func holds(day: String) -> Bool { carry == .day(day) }
    /// A scene carried out of the scene list.
    func holds(listScene scene: String) -> Bool {
        if case let .scenes(scenes, from) = carry, from == nil { return scenes.contains(scene) }
        return false
    }
    func holds(shot: String) -> Bool {
        if case let .shot(placement, _) = carry { return placement == shot }
        return false
    }
    func holds(board: String) -> Bool { carry == .board(board) }
    /// A shot carried out of an opened scene in the list.
    func holds(loose placement: String) -> Bool {
        if case let .loose(placements) = carry { return placements.contains(placement) }
        return false
    }

    /// Whether a scene held now would land on this day — the card's glow.
    func lights(day: String) -> Bool {
        if case let .into(d, _) = spot { return d == day }
        return false
    }

    // --------------------------------------------------------------- checks

    /// **A mouse a check can drive.** `--mouse "down 500 190; move 500 360 12;
    /// up 500 360"` — window points from the top left, the way `--tap` reads
    /// them, posted into the app's own queue so this hand sees them exactly
    /// as it sees his. Verbs: `down x y [cmd|shift]`, `move x y [steps]`,
    /// `up x y`, `click x y [cmd|shift]`, `key esc`, `wait s`, `snap path`,
    /// `say`. Then `then` runs.
    static func drive(_ script: String, in window: NSWindow, then: @escaping () -> Void) {
        let steps = script.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        var delay: TimeInterval = 0
        var last = CGPoint.zero
        func at(_ words: [String], _ i: Int) -> CGPoint? {
            guard words.count > i + 1, let x = Double(words[i]), let y = Double(words[i + 1]) else { return nil }
            return CGPoint(x: x, y: window.frame.height - y)
        }
        func flags(_ words: [String]) -> NSEvent.ModifierFlags {
            var f: NSEvent.ModifierFlags = []
            if words.contains("cmd") { f.insert(.command) }
            if words.contains("shift") { f.insert(.shift) }
            return f
        }
        func post(_ type: NSEvent.EventType, _ p: CGPoint, _ f: NSEvent.ModifierFlags = [], after: TimeInterval) {
            let timer = Timer(timeInterval: after, repeats: false) { _ in
                guard let e = NSEvent.mouseEvent(
                    with: type, location: p, modifierFlags: f,
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1
                ) else { return }
                NSApp.postEvent(e, atStart: false)
            }
            RunLoop.main.add(timer, forMode: .common)
        }
        func later(_ after: TimeInterval, _ work: @escaping () -> Void) {
            let timer = Timer(timeInterval: after, repeats: false) { _ in work() }
            RunLoop.main.add(timer, forMode: .common)
        }
        for step in steps where !step.isEmpty {
            let words = step.split(separator: " ").map(String.init)
            switch words[0] {
            case "wait":
                delay += Double(words.count > 1 ? words[1] : "0.3") ?? 0.3
            case "down":
                guard let p = at(words, 1) else { continue }
                post(.leftMouseDown, p, flags(words), after: delay); last = p; delay += 0.08
            case "up":
                let p = at(words, 1) ?? last
                post(.leftMouseUp, p, [], after: delay); last = p; delay += 0.12
            case "click":
                guard let p = at(words, 1) else { continue }
                post(.leftMouseDown, p, flags(words), after: delay)
                post(.leftMouseUp, p, flags(words), after: delay + 0.06)
                last = p; delay += 0.35
            case "move":
                guard let p = at(words, 1) else { continue }
                let n = words.count > 3 ? Int(words[3]) ?? 10 : 10
                let from = last
                for i in 1...max(n, 1) {
                    let k = CGFloat(i) / CGFloat(max(n, 1))
                    post(.leftMouseDragged,
                         CGPoint(x: from.x + (p.x - from.x) * k, y: from.y + (p.y - from.y) * k),
                         after: delay + 0.02 * Double(i))
                }
                delay += 0.02 * Double(max(n, 1)) + 0.1
                last = p
            case "key":
                // `key esc`, or `key undo` — ⌘Z, the way the menu takes it.
                let undo = words.count > 1 && words[1] == "undo"
                let timer = Timer(timeInterval: delay, repeats: false) { _ in
                    guard let e = NSEvent.keyEvent(
                        with: .keyDown, location: .zero, modifierFlags: undo ? [.command] : [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil,
                        characters: undo ? "z" : "\u{1b}", charactersIgnoringModifiers: undo ? "z" : "\u{1b}",
                        isARepeat: false, keyCode: undo ? 6 : 53) else { return }
                    NSApp.postEvent(e, atStart: false)
                }
                RunLoop.main.add(timer, forMode: .common)
                delay += 0.15
            case "snap":
                guard words.count > 1 else { continue }
                let path = words[1]
                later(delay) {
                    let view = window.contentView?.superview ?? window.contentView
                    if let view, let png = Launch.picture(of: view, in: window) {
                        try? png.write(to: URL(fileURLWithPath: path))
                        FileHandle.standardError.write(Data("snap: \(path)\n".utf8))
                    }
                }
                delay += 0.2
            case "say":
                later(delay) { report() }
                delay += 0.05
            default:
                continue
            }
        }
        later(delay + 0.6, then)
    }

    /// What a check reads back: every day's strips in order, the scene list's
    /// picked scenes, the boards in order, and what the hand did.
    static func report() {
        let state = ShellState.shared
        state.loadBoard()
        var out = ""
        for day in state.stripBoard?.days ?? [] {
            out += "strips: \(day.label) = " + day.strips.map(\.number).joined(separator: ",") + "\n"
        }
        for day in state.stripBoard?.days ?? [] {
            out += "run: \(day.label) = " + day.run.map(\.number).joined(separator: ",") + "\n"
        }
        let picked = state.scenes.filter { state.sceneSelection.contains($0.id) }.map(\.number)
        out += "picked: " + picked.joined(separator: ",") + "\n"
        let open = (state.view?.scenes ?? []).filter { state.openStrips.contains($0.id) }.map(\.number)
        out += "open: " + open.joined(separator: ",") + "\n"
        let remainders = (state.view?.scenes ?? []).filter { state.openRemainders.contains($0.id) }.map(\.number)
        out += "waiting: " + (state.stripBoard?.unscheduled ?? []).map { "\($0.number)x\($0.count)" }.joined(separator: ",") + "\n"
        out += "remainders open: " + remainders.joined(separator: ",") + "\n"
        let loose = (state.stripBoard?.unscheduled ?? []).flatMap(\.shots).filter { state.loosePicked.contains($0.placement) }.map(\.number)
        out += "shots picked: " + loose.joined(separator: ",") + "\n"
        out += "tab: \(state.sideTab.rawValue)\n"
        out += "boards: " + (state.view?.boards ?? []).map(\.name).joined(separator: " | ") + "\n"
        let rows = state.view?.allRows ?? []
        out += "shots: " + (state.view?.scenes ?? []).map { scene in
            "\(scene.number)=\(rows.filter { $0.sceneId == scene.id }.count)"
        }.joined(separator: " ") + "\n"
        out += "hand: " + shared.log.joined(separator: " · ") + "\n"
        out += "held: \(shared.carry == nil ? "nothing" : "something")\n"
        FileHandle.standardError.write(Data(out.utf8))
    }
}

// ---------------------------------------------------------------- the marks

/// An AppKit view laid behind something the hand can carry or put down on.
/// It draws nothing and answers no click — `hitTest` is nil — so it only
/// says where its thing is, in the window's own coordinates.
final class MarkView: NSView {
    var mark: BoardMark = .list
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { BoardHands.shared.register(self) }
    }
}

extension View {
    /// **Tell the hand where this is** — for the board and the calendar,
    /// whose frames only SwiftUI knows (see `BoardHands.drawn`). The AppKit
    /// view behind it says only that the thing is on screen, and in which
    /// window.
    func boardMark(_ mark: BoardMark) -> some View {
        background(BoardMarkTag(mark))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                BoardHands.shared.drawn[mark] = frame
            }
    }
}

struct BoardMarkTag: NSViewRepresentable {
    let mark: BoardMark
    init(_ mark: BoardMark) { self.mark = mark }
    func makeNSView(context: Context) -> MarkView {
        let view = MarkView()
        view.mark = mark
        return view
    }
    func updateNSView(_ view: MarkView, context: Context) { view.mark = mark }
}

// ---------------------------------------------------------------- the ghost

/// **What the hand is holding, under the pointer** — a chip with the scene's
/// number and place, a day's name, a board's name. Drawn over the whole
/// window, so it follows the pointer out of the sidebar and across the board.
struct BoardGhost: View {
    @ObservedObject private var pointer = BoardPointer.shared
    @ObservedObject private var hands = BoardHands.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { g in
            if hands.carry != nil, !pointer.words.isEmpty {
                let origin = g.frame(in: .global).origin
                let dark = scheme == .dark
                ZStack(alignment: .topLeading) {
                    Color.clear
                    chip(dark)
                        .offset(x: pointer.at.x - origin.x + 14, y: pointer.at.y - origin.y + 12)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func chip(_ dark: Bool) -> some View {
                Text(pointer.words)
                    .sans(Brand.Size.small, weight: .semibold)
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(Brand.ink(dark))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Brand.surface2(dark), in: RoundedRectangle(cornerRadius: Brand.radiusSmall, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Brand.radiusSmall, style: .continuous)
                            .strokeBorder(hands.spot == nil ? Brand.glassEdge(dark) : Brand.accent(dark), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(dark ? 0.35 : 0.15), radius: 6, y: 2)
                    .opacity(hands.spot == nil ? 0.7 : 0.95)
                    .fixedSize()
    }
}

extension ShellState {
    /// What a scene-list drag carries: the one scene under the pointer, or
    /// every picked scene when it is one of them — in the list's own order,
    /// so four picked scenes land in the order they are read, not in the
    /// order a set happens to hold them.
    func dragScenes(for scene: String) -> [String] {
        let acting = Set(scenesActedOn(scene))
        let ordered = scenes.map(\.id).filter { acting.contains($0) }
        return ordered.isEmpty ? [scene] : ordered
    }

    /// Scenes onto a day where the hand let go, or off it — one engine call.
    func putScenes(_ scenes: [String], from: String?, on day: String?, before: String?) {
        afterBoard(engine?.putScenes(scenes, from: from, on: day, before: before))
    }

    /// Shots still on no day onto a day — one engine call, one undo. The
    /// picks are spent: whatever was picked has gone where it was sent.
    func putShots(_ placements: [String], on day: String, before: String?) {
        guard !placements.isEmpty else { return }
        loosePicked.subtract(placements)
        afterBoard(engine?.putShots(placements, on: day, before: before))
    }

    /// A scene's shots still on no day, in scene order, off the board.
    func remainder(of scene: String) -> [BoardModel.StripShot] {
        stripBoard?.unscheduled.first { $0.scene == scene }?.shots ?? []
    }

    /// The chip under a scene carried from the list: `Scene 16 · 3 shots` —
    /// the shots that will travel, which is the remainder when part of the
    /// scene is already on a day.
    func carryWords(for scene: ViewModel.Scene) -> String {
        let book = booking(of: scene)
        let n = book.left > 0 ? book.left : book.total
        let number = scene.number.isEmpty ? "Scene" : "Scene \(scene.number)"
        return n == 0 ? number : "\(number) · \(n) shot\(n == 1 ? "" : "s")"
    }

    /// What a drag on an opened scene's shot carries: that shot, or every
    /// picked one when it is one of them, in the list's order.
    func dragLoose(for placement: String) -> [String] {
        guard loosePicked.contains(placement) else { return [placement] }
        let ordered = (stripBoard?.unscheduled ?? []).flatMap(\.shots).map(\.placement)
            .filter { loosePicked.contains($0) }
        return ordered.isEmpty ? [placement] : ordered
    }

    /// `16A`, or `Scene 16 · 2 shots`, or `5 shots` across scenes.
    func looseWords(_ placements: [String]) -> String {
        let strips = stripBoard?.unscheduled ?? []
        let held = strips.filter { strip in strip.shots.contains { placements.contains($0.placement) } }
        if placements.count == 1, let shot = held.first?.shots.first(where: { $0.placement == placements[0] }) {
            return shot.number.isEmpty ? "Shot" : shot.number
        }
        if held.count == 1, let strip = held.first {
            return "Scene \(strip.number) · \(placements.count) shots"
        }
        return "\(placements.count) shots"
    }

    /// A click on an opened scene's shot: picks it alone, or with ⌘ or ⇧
    /// adds it to (or takes it from) the picks.
    func pickLoose(_ placement: String, adding: Bool) {
        if adding {
            if loosePicked.contains(placement) { loosePicked.remove(placement) } else { loosePicked.insert(placement) }
        } else {
            loosePicked = loosePicked == [placement] ? [] : [placement]
        }
    }
}
