import SwiftUI
import AppKit

// **Present**, and the Diagram's own keys.
//
// Present hides every control — the toolbar, the bars, the panels, the window's
// own top bar and scene list — and fits the plan to the window, to show a
// director or a crew. Esc comes back to where he was.
//
// The keys: ⌃⌘1 Layers, ⌃⌘2 Details, ⌘F Present. (⌃⌘3 was Gear, which
// is Copy › Gear List now.) Not ⌘1–⌘3,
// which the menu bar gives to the five modes (⌘5 is this one).

extension DiagramModel {
    var presenting: Bool { state?.diagramPresenting == true }

    func present(_ on: Bool) {
        guard let state, on != presenting else { return }
        if on {
            beforePresent = (centre, scale)
            typing = nil
            selection = []
            pending = []
            calibrating = nil
            tool = .select
            showingSun = false
            state.diagramPresenting = true
            // Fitted once the chrome has gone and the canvas has its new size.
            fitted = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, self.presenting else { return }
                self.fitted = false
                self.canvas?.needsDisplay = true
                self.objectWillChange.send()
            }
        } else {
            state.diagramPresenting = false
            if let was = beforePresent {
                centre = was.centre
                scale = was.scale
                fitted = true
            }
            beforePresent = nil
            canvas?.needsDisplay = true
        }
    }

    /// Open or close one of the sidebars.
    func toggle(panel: String) {
        withAnimation(.easeOut(duration: 0.18)) {
            switch panel {
            // Layers is a tab of the left sidebar: on it, back to the scenes.
            case "layers": sideTab = sideTab == "layers" ? "scenes" : "layers"
            case "details": showingDetails.toggle(); if showingDetails { gearFront = false }
            case "show": showingShow.toggle()
            default: break
            }
        }
    }
}

enum DiagramKeys {
    /// Watches the window's keys while the Diagram is showing, whatever has
    /// the focus — a sidebar's field included.
    static func install(_ model: DiagramModel) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak model] e in
            guard let model else { return e }
            return handle(e, model) ? nil : e
        }
    }

    static func remove(_ monitor: Any?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    /// Whether the key was one of ours, and done.
    static func handle(_ e: NSEvent, _ model: DiagramModel) -> Bool {
        guard let window = model.canvas?.window, e.window === window else { return false }
        // Drawing on a picture: its own keys first (`PhotoEditor.swift`).
        if model.photoEditing != nil, model.photoKey(e) { return true }
        let mods = e.modifierFlags.intersection([.command, .control, .option, .shift])
        let ch = e.charactersIgnoringModifiers?.lowercased() ?? ""
        if model.presenting, e.keyCode == 53 {
            model.present(false)
            return true
        }
        // **⌥⌘I, Details** (Show Inspector, as in Apple's own apps).
        if mods == [.command, .option], ch == "i" || e.keyCode == 34, !model.presenting {
            model.toggleDetails()
            return true
        }
        // **Esc in a Details field: back to the plan** (2026-10-17); the
        // plan's own Esc then lets go of the pick. Not a name being typed on
        // the plan, which has its own Esc.
        if e.keyCode == 53, mods.isEmpty, model.typing == nil, model.detailsOpen,
           window.firstResponder is NSText || window.firstResponder is NSTextField,
           let canvas = model.canvas, window.firstResponder !== canvas {
            window.makeFirstResponder(canvas)
            return true
        }
        if mods == [.command, .control] {
            switch (ch, e.keyCode) {
            case ("1", _), (_, 18): model.toggle(panel: "layers")
            case ("2", _), (_, 19): model.toggle(panel: "details")
            default: return false
            }
            return true
        }
        if mods == [.command], ch == "f" || e.keyCode == 3 {
            model.present(!model.presenting)
            return true
        }
        // Return on a picked piece: its name, typed over on the plan.
        if DiagramNames.renameKey(e, model) { return true }
        // **Delete takes what is picked, wherever the keyboard is** (his
        // note, 2026-09-29: "backspace should delete things in diagram
        // mode"). The plan's own key handling only hears it while the plan
        // has the keyboard; a click in Layers, a panel's button or the
        // toolbar took it elsewhere and Delete went nowhere. Only typing
        // keeps it — a name being written, a search, a field in Details.
        if [51, 117].contains(e.keyCode), mods.isDisjoint(with: [.command, .control, .option]),
           !model.presenting, !model.readOnly, !model.selection.isEmpty,
           !(window.firstResponder is NSText), !(window.firstResponder is NSTextField) {
            if model.stepPick != nil { model.removePickedStep() }
            else if model.pickedCorner != nil { model.removeCorner() }
            else { model.remove(model.selection) }
            model.canvas?.needsDisplay = true
            return true
        }
        return false
    }
}
