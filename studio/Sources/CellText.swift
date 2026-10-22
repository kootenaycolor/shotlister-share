import SwiftUI
import AppKit

/// The text editor inside an open cell.
///
/// This is a real `NSTextView`, and the reason is everything a hand expects of
/// one: a caret you can click into place, a drag that selects, ⌘A, ⌘C and ⌘V,
/// double-click to take a word, and Shift-Return for a second line. None of
/// those are things to reimplement — they are the system's, and writing our own
/// half-version of them is how a text box starts feeling wrong.
///
/// **Two things may write into this text, and they do not fight.** When the
/// window is in front the text view has the keyboard and every key is its own.
/// A checking run never brings the window forward — that is a law here, because
/// Nathaniel works on the same Mac — so in a check the view never becomes first
/// responder and no keystroke would ever reach it. The window monitor writes
/// into the same string in that case. Whoever is holding the pen, there is one
/// piece of text, and it is `state.editSeed`.
///
/// The old race is gone by construction: the view is created with the buffer
/// already in it and the caret **after** the last character, so nothing is
/// selected and nothing is about to be replaced by the next keystroke. That
/// selection was the whole of the "Establishing arrived as stablishing" bug.
struct CellText: NSViewRepresentable {
    @Binding var text: String
    /// Whether the view has the keyboard. The window monitor reads this and
    /// keeps its hands off while it is true.
    @Binding var live: Bool
    /// How tall the words came out, so the cell can grow to fit them.
    @Binding var height: CGFloat
    let width: CGFloat
    let size: CGFloat
    let dark: Bool
    /// Replace mode: the edit began by typing over the cell, so every arrow
    /// commits and moves, the way a sheet treats fresh typing. In revise mode
    /// (Return or double-click) the arrows belong to the text and move the
    /// caret — also the way a sheet treats it.
    let freshTyping: Bool
    /// Return, Tab, Escape — and in replace mode the arrows — belong to the
    /// table, not to the text.
    let leave: (Leaving) -> Void

    /// `down`/`up`/`right`/`left` are arrow steps on the grid; `tabNext` and
    /// `tabBack` wrap at the row's edge the way Tab does and arrows do not.
    enum Leaving { case here, down, up, right, left, tabNext, tabBack, cancel }

    func makeNSView(context: Context) -> Editor {
        let view = Editor()
        view.delegate = context.coordinator
        view.isEditable = true
        view.isSelectable = true
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.textContainerInset = NSSize(width: 0, height: 0)
        view.textContainer?.lineFragmentPadding = 0
        view.string = text
        view.onSize = { context.coordinator.report($0) }
        // Said the moment the view takes or loses the keyboard, never on the
        // first edit. `textDidBeginEditing` arrives only once something has
        // been typed, and by then the monitor — which believes nobody else has
        // the keyboard — has already eaten that keystroke. That is the old
        // one-character bug wearing a different coat.
        view.onKeyboard = { context.coordinator.holding($0) }
        // Read at the instant the view takes the keyboard. Between the
        // keystroke that opened the cell and the view claiming first
        // responder, the window monitor is the one typing — into the shared
        // buffer — and any characters it caught have to be in the view the
        // moment the view takes over, or they exist in the committed value and
        // never on screen. The binding's getter reads the live state, so this
        // is always current, not a copy from render time.
        view.latestText = { context.coordinator.parent.text }
        return view
    }

    func updateNSView(_ view: Editor, context: Context) {
        context.coordinator.parent = self
        view.font = .systemFont(ofSize: size)
        view.textColor = NSColor(Brand.ink(dark))
        view.insertionPointColor = NSColor(Brand.accent(dark))
        // Only when it differs, and never while the view has the keyboard:
        // writing the string back into a view that is being typed into moves
        // the caret to the end of it mid-word.
        // In front of a person the view is the one being typed into, and
        // writing the string back would drag the caret to the end mid-word.
        // In a check the monitor is typing instead, and the view has to be
        // told, or a photograph of the open cell shows an empty one.
        if view.string != text && (!view.isFirstResponder || !NSApp.isActive) {
            view.string = text
            view.measure()
        }
        view.textContainer?.containerSize = NSSize(
            width: width, height: .greatestFiniteMagnitude
        )
        view.measure()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CellText

        init(_ parent: CellText) { self.parent = parent }

        func report(_ measured: CGFloat) {
            // Straight assignment here re-enters SwiftUI's own layout pass.
            DispatchQueue.main.async {
                if abs(self.parent.height - measured) > 0.5 {
                    self.parent.height = measured
                }
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }

        func holding(_ has: Bool) {
            // Straight through, not deferred. A hop here is a window in which
            // the monitor still believes it owns the keyboard, and a keystroke
            // arriving inside that window is eaten by it and never reaches the
            // view — one lost character, at the start of every edit, which is
            // precisely the bug this whole arrangement exists to prevent.
            parent.live = has
        }

        /// The keys that are the table's rather than the text's.
        ///
        /// Shift-Return is deliberately *not* here: AppKit routes it to
        /// `insertNewlineIgnoringFieldEditor`, which falls through to the
        /// default and puts a line break in, which is what a sheet does.
        func textView(_ view: NSTextView, doCommandBy command: Selector) -> Bool {
            // Replace mode: arrows commit and move on the grid. The recording
            // shows exactly this — he types into a cell and presses an arrow
            // or Return and is already on the next cell. Revise mode falls
            // through, so the arrows walk the caret like any text box.
            if parent.freshTyping {
                switch command {
                case #selector(NSResponder.moveDown(_:)): parent.leave(.down); return true
                case #selector(NSResponder.moveUp(_:)): parent.leave(.up); return true
                case #selector(NSResponder.moveRight(_:)): parent.leave(.right); return true
                case #selector(NSResponder.moveLeft(_:)): parent.leave(.left); return true
                default: break
                }
            }
            switch command {
            case #selector(NSResponder.insertNewline(_:)):
                // Shift-Return is a second line inside the cell. AppKit usually
                // routes that to `insertNewlineIgnoringFieldEditor`, but only
                // when the key bindings say so; reading the modifier here means
                // it behaves the same whichever way the event arrived.
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    view.insertText("\n", replacementRange: view.selectedRange())
                    return true
                }
                // Return puts the words away and **stays on the cell** — his
                // call, and the deliberate departure from a sheet's
                // commit-and-drop-down. The arrows are how you leave.
                parent.leave(.here)
                return true
            case #selector(NSResponder.insertTab(_:)):
                parent.leave(.tabNext)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                parent.leave(.tabBack)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.leave(.cancel)
                return true
            default:
                return false
            }
        }
    }

    /// A text view that takes the keyboard the moment it is in a window, puts
    /// the caret after the last character, and measures itself.
    final class Editor: NSTextView {
        var onSize: ((CGFloat) -> Void)?
        var onKeyboard: ((Bool) -> Void)?
        var latestText: (() -> String)?
        private var claimed = false
        private var loaded = false

        override func becomeFirstResponder() -> Bool {
            let took = super.becomeFirstResponder()
            if took {
                // The hand-off, closed airtight. Until this exact moment the
                // monitor owns the keyboard and types into the shared buffer;
                // from this moment the view owns it. Loading the buffer here —
                // synchronously, inside the claim — means a character that
                // arrived during the gap is on screen before the next one can
                // arrive, because events queue behind this call on the main
                // thread. Loading it anywhere later recreates the dropped-
                // letter bug with a smaller window, which is not fixed, just
                // rarer.
                if !loaded {
                    loaded = true
                    if let latest = latestText?(), latest != string {
                        string = latest
                    }
                    setSelectedRange(NSRange(location: string.count, length: 0))
                    measure()
                }
                onKeyboard?(true)
            }
            return took
        }

        override func resignFirstResponder() -> Bool {
            let gave = super.resignFirstResponder()
            if gave { onKeyboard?(false) }
            return gave
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, !claimed else { return }
            claimed = true
            // The claim retries. A single attempt lands wherever the
            // activation dice happen to sit at that instant — and when
            // another app is fighting for the front (a busy machine, a loud
            // run racing a dying sibling), one losing moment used to mean the
            // editor never took the keyboard at all and the whole edit ran on
            // the fallback path. Polling for a key window keeps the promise:
            // in front of a person it claims within a tick; in a quiet check
            // the window never becomes key and the poll expires having asked
            // for nothing.
            var tries = 0
            let poll = Timer(timeInterval: 0.1, repeats: true) { [weak self] timer in
                guard let self, let window = self.window, !self.isFirstResponder else {
                    timer.invalidate(); return
                }
                tries += 1
                if tries > 30 { timer.invalidate(); return }
                guard window.isKeyWindow else { return }
                window.makeFirstResponder(self)
                if self.isFirstResponder { timer.invalidate() }
            }
            RunLoop.main.add(poll, forMode: .common)
            poll.fire()
        }

        func measure() {
            guard let container = textContainer, let manager = layoutManager else { return }
            manager.ensureLayout(for: container)
            let used = manager.usedRect(for: container).height
            onSize?(max(used, 17))
        }

        override func didChangeText() {
            super.didChangeText()
            measure()
        }
    }
}

extension NSView {
    var isFirstResponder: Bool { window?.firstResponder === self }
}
