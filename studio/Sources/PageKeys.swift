import AppKit
import SwiftUI

/// **The document page, driven by keys alone** — the check for his ask of
/// 2026-09-30: *"the goal is to not need to touch the mouse while adding shots
/// and details to shots."*
///
/// `--pagekeys "⇥; type Wide on the door; ⌘↩; rows"` plays one step at a time
/// into the page and, after every step, prints where the page's caret is,
/// which shots are picked, what holds the keyboard and what the shot says.
/// Steps are separated by `;`:
///
///     ⇥ ⇧⇥ ↩ ⇧↩ ⌘↩ ⎋ ↑ ↓ ⇧↑ ⇧↓ ⌘↑ ⌘↓ ⌘⌫ ⌘a     one key
///     type <words>                               letters, one key each
///     swipe <x> <y> <dy> <count>                 a trackpad swipe, routed by the window
///     wheel <x> <y> <dy> <count>                 scroll handed to the view under the point
///     rows                                       every shot of the caret's scene, as stored
///     wait <seconds>                             nothing, for a while
///
/// **A checking window is never the key window**, and the page's lines only
/// take the keyboard in the key window — the catch that stops a check from
/// yanking his Mac out from under him. So while this drives, the page lets its
/// lines take the keyboard in a window that is not key (`driving`), and each
/// key is handed to the page's own watcher and then the window, the same two
/// stops a real key makes. Nothing is activated and nothing comes to the front.
///
/// **Clicks cannot be checked here.** A click on a window that is not in front
/// is spent bringing it forward, and SwiftUI's taps never hear it — tried both
/// posted and handed to the window, 2026-09-30. Only a loud run, on his
/// say-so, can check the mouse.
enum PageKeys {
    /// True only while a check is driving the page. Read by the page's claim.
    static var driving = false

    static func drive(_ script: String, in window: NSWindow, done: @escaping () -> Void) {
        driving = true
        let steps = script.split(separator: ";").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
        say("start", window)
        var at = 0
        func next() {
            guard at < steps.count else {
                driving = false
                done()
                return
            }
            let step = steps[at]
            at += 1
            let wait = play(step, in: window)
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                say(step, window)
                next()
            }
        }
        next()
    }

    /// Plays one step; answers how long to let it settle.
    private static func play(_ step: String, in window: NSWindow) -> TimeInterval {
        let words = step.split(separator: " ", maxSplits: 1).map(String.init)
        switch words.first ?? "" {
        case "type":
            for ch in (words.count > 1 ? words[1] : "") { key(String(ch), 0, [], window) }
            return 0.4
        case "wheel":
            let n = step.split(separator: " ").dropFirst().compactMap { Double($0) }
            guard n.count == 4 else { return 0.1 }
            wheel(CGPoint(x: n[0], y: n[1]), dy: n[2], count: Int(n[3]), window)
            return 0.7
        case "swipe":
            let n = step.split(separator: " ").dropFirst().compactMap { Double($0) }
            guard n.count == 4 else { return 0.1 }
            swipe(CGPoint(x: n[0], y: n[1]), dy: n[2], count: Int(n[3]), window)
            return 1.0
        case "wait":
            return Double(words.count > 1 ? words[1] : "") ?? 0.5
        case "rows":
            // Every shot of the scene the caret is in, as the engine holds it.
            let state = ShellState.shared
            let rows = Shortcuts.everyRow(state)
            let scene = rows.first { $0.id == state.cursorShot }?.sceneId
            for row in rows where row.sceneId == scene {
                FileHandle.standardError.write(Data(
                    "  \(row.number): \"\(row.description)\" · \(row.size) · \(row.lens) · note \"\(row.notes)\"\n".utf8))
            }
            return 0.1
        default:
            let keys: [String: (String, UInt16, NSEvent.ModifierFlags)] = [
                "⇥": ("\t", 48, []), "⇧⇥": ("\u{19}", 48, [.shift]),
                "↩": ("\r", 36, []), "⇧↩": ("\r", 36, [.shift]),
                "⌘↩": ("\r", 36, [.command]), "⎋": ("\u{1b}", 53, []),
                "↑": ("\u{F700}", 126, []), "↓": ("\u{F701}", 125, []),
                "⇧↑": ("\u{F700}", 126, [.shift]), "⇧↓": ("\u{F701}", 125, [.shift]),
                "⌘↑": ("\u{F700}", 126, [.command]), "⌘↓": ("\u{F701}", 125, [.command]),
                "⌘⌫": ("\u{7f}", 51, [.command]), "⌘a": ("a", 0, [.command]),
                "⇧⌘a": ("a", 0, [.command, .shift]), "⌫": ("\u{7f}", 51, []),
            ]
            guard let (chars, code, flags) = keys[step] else {
                FileHandle.standardError.write(Data("pagekeys: no such step \(step)\n".utf8))
                return 0.1
            }
            key(chars, code, flags, window)
            return 0.45
        }
    }

    /// The page's own key watcher, set while a document page is showing.
    static var page: ((NSEvent) -> NSEvent?)?

    /// One key, the way the app would meet it: the page's watcher first —
    /// which carries the shortcuts too — and, if it lets the key by, the
    /// window's menu chords and then its first responder. Handed over by
    /// hand, not posted: NSApp sends keys only to the key window, and a
    /// checking window never is one.
    private static func key(_ chars: String, _ code: UInt16,
                            _ flags: NSEvent.ModifierFlags, _ window: NSWindow) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            characters: chars, charactersIgnoringModifiers: chars,
            isARepeat: false, keyCode: code
        ) else { return }
        guard let passed = page.map({ $0(event) }) ?? event else { return }
        if passed.modifierFlags.contains(.command),
           NSApp.mainMenu?.performKeyEquivalent(with: passed) == true { return }
        if window.performKeyEquivalent(with: passed) { return }
        (window.firstResponder ?? window).keyDown(with: passed)
    }

    private static func wheel(_ p: CGPoint, dy: Double, count: Int, _ window: NSWindow) {
        let at = CGPoint(x: p.x, y: window.frame.height - p.y)
        var held = 0
        for _ in 0..<count {
            guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                   wheelCount: 1, wheel1: Int32(dy), wheel2: 0, wheel3: 0),
                  let ev = NSEvent(cgEvent: cg) else { continue }
            if let gate = ListScroll.Anchor.open, gate.swallows(ev, at: at) { held += 1; continue }
            window.contentView?.hitTest(at)?.scrollWheel(with: ev)
        }
        FileHandle.standardError.write(Data("  wheel: \(held) of \(count) held by a list\n".utf8))
    }

    /// **A trackpad swipe, the way the trackpad sends one** — continuous,
    /// with its began / changed / ended phases, through the app's own queue.
    /// `wheel` hands each event to the view under the point, so it passed
    /// while his trackpad, over the page's lists, scrolled the page instead
    /// (2026-09-30). A real swipe is routed by the window, which a background
    /// window never does for a made-up one — so the only honest check here is
    /// that the app's own watchers catch the swipe before any routing.
    private static func swipe(_ p: CGPoint, dy: Double, count: Int, _ window: NSWindow) {
        // A made-up scroll belongs to no window, so its location reads as the
        // window's own: placed so that it lands on the window point asked for.
        let inWindow = CGPoint(x: p.x, y: window.frame.height - p.y)
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let global = CGPoint(x: inWindow.x, y: top - inWindow.y)
        for at in 0..<max(count, 2) {
            let phase: Int64 = at == 0 ? 1 : (at == count - 1 ? 4 : 2)
            guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                   wheelCount: 1, wheel1: phase == 4 ? 0 : Int32(dy),
                                   wheel2: 0, wheel3: 0) else { continue }
            cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            cg.location = global
            guard let event = NSEvent(cgEvent: cg) else { continue }
            // Through the app's queue, so its watchers see it the way they
            // see a real swipe. A window not in front never receives one
            // itself — so this checks the watchers, not the routing, and a
            // swipe nothing steers moves nothing at all.
            NSApp.postEvent(event, atStart: false)
        }
    }

    /// Where everything stands, one line.
    static func say(_ step: String, _ window: NSWindow) {
        let state = ShellState.shared
        let rows = Shortcuts.everyRow(state)
        func number(_ id: String?) -> String {
            rows.first { $0.id == id }?.number ?? "-"
        }
        let cursor = rows.first { $0.id == state.cursorShot }
        let marked = rows.filter { state.marked.contains($0.id) }.map(\.number)
        let responder: String = {
            guard let r = window.firstResponder else { return "none" }
            if let grow = r as? GrowText {
                return "line[\(grow.placeholder.isEmpty ? "words" : grow.placeholder)]"
            }
            if let editor = r as? NSTextView, editor.isFieldEditor {
                return "field-editor"
            }
            return String(describing: type(of: r))
        }()
        let inScene = rows.filter { $0.sceneId == cursor?.sceneId }.map(\.number)
        var scrolls: [String] = []
        func walk(_ v: NSView) {
            if let s = v as? NSScrollView, s.frame.height > 20 {
                scrolls.append("\(Int(s.frame.height))h@\(Int(s.contentView.bounds.origin.y))")
            }
            v.subviews.forEach(walk)
        }
        if let root = window.contentView { walk(root) }
        let line = "pagekeys [\(step)] cursor=\(number(state.cursorShot)) part=\(PageProbe.part)"
            + " list=\(PageProbe.list ?? "shut")"
            + " marked=[\(marked.joined(separator: ","))] responder=\(responder)"
            + " scene=[\(inScene.joined(separator: ","))]"
            + " title=\"\(cursor?.title ?? "")\" words=\"\(cursor?.description ?? "")\""
            + " size=\"\(cursor?.size ?? "")\" lens=\"\(cursor?.lens ?? "")\""
            + " notes=\"\(cursor?.notes ?? "")\" scrolls=\(scrolls.joined(separator: " "))\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}

/// What the page's caret and the open list are, for the check to read. The
/// page's own state is private to its view; this is written beside it.
enum PageProbe {
    static var part = "-"
    /// The field whose list is showing.
    static var list: String?
}
