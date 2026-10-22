import AppKit
import SwiftUI

/// **The export, in a window of its own.**
///
/// His ruling, 2026-09-02, after calling the old box *"clunky and not organized
/// correctly. also design wise, ugly"*: it stops being a sheet. Movable,
/// resizable, and never a takeover — the same bargain `FramesWindow`,
/// `ScriptWindow`, `ScanWindow` and the viewer already strike.
///
/// **The second reason is checking, and it is the bigger one.** No sheet in
/// this app can be photographed (Ref 366): while one is up a checking run has
/// no windows at all, so in the whole app the export box was the screen nobody
/// could ever look at. Every change ever made to it was verified by reading
/// numbers off a log. A real window with an identifier can be photographed —
/// `--window export --snapshot out.png` reaches it through the same door
/// `viewer`, `frames`, `script`, `scan` and `schedule` already use, with no new
/// machinery at all.
final class ExportWindow: NSObject, NSWindowDelegate {
    static let shared = ExportWindow()

    private var window: NSWindow?
    private var hosting: NSHostingView<ExportBox>?
    /// Held so the flags can be cleared when the window closes — see
    /// `windowWillClose`. Weak: the window must never be the reason the app's
    /// state outlives the film it belongs to.
    private weak var state: ShellState?

    /// Open on whatever `state` already says: the whole film, or the scenes
    /// named in `exportingScenes`.
    ///
    /// **One window, never several.** The frames and viewer pop-outs allow
    /// many because each is an eye on a different picture and a pair of them
    /// is the point. This is a machine with settings; two open on one film
    /// would be two answers to the same question, and the second would quietly
    /// win at the save panel.
    func show(state: ShellState) {
        self.state = state
        Printing.warmUp()
        let view = ExportBox(state: state)
        if let hosting {
            hosting.rootView = view
        } else {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1220, height: 760),
                styleMask: [.titled, .closable, .resizable, .miniaturizable,
                            .fullSizeContentView],
                backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 1040, height: 620)
            w.delegate = self
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            // Named, so a checking run can photograph it. This one line is
            // what ends "the export box has never been seen".
            w.identifier = NSUserInterfaceItemIdentifier("export")
            let host = NSHostingView(rootView: view)
            w.contentView = host
            hosting = host
            // His window position is his — remembered between opens, but never
            // written by a checking run. The guard is the whole safety of it:
            // an autosave name writes straight to `UserDefaults`, past
            // `Remembering`, and a run that stamped its own frame there would
            // move his window for him.
            if !Launch.checking { w.setFrameAutosaveName("exportWindow") }
            // A window remembered from before the Order and Days column
            // (2026-10-15) is widened once, so that column is not cut.
            if w.frame.width < 1040 || w.frame.height < 620 {
                w.setContentSize(NSSize(width: max(w.frame.width, 1180), height: max(w.frame.height, 760)))
            }
            if let main = NSApp.windows.first(where: { $0.isVisible && $0 != w }) {
                // A child window rides above the main one and follows it,
                // without floating over every other app on the Mac.
                main.addChildWindow(w, ordered: .above)
                if w.frame.origin == .zero { w.center() }
            }
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
    }

    /// Close from inside the box — Cancel, or an export that finished.
    func close() {
        window?.close()
    }

    /// **The flags are cleared here and nowhere else.** They are what the box
    /// reads to know whether it is showing the whole film or a pick; left set,
    /// the next open would draw the last thing before catching up, and the
    /// share button would hand back a scene's export.
    func windowWillClose(_ notification: Notification) {
        state?.exportingScenes = []
        state?.exportingWholeProject = false
        state?.exportJustDiagram = false
        Printing.coolDown()
        window = nil
        hosting = nil
        state = nil
    }
}
