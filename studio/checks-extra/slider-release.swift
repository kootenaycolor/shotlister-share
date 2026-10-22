// **A slider's "let go" must save what it was moved to** (2026-10-15).
//
// A SwiftUI Slider hands `onEditingChanged` the closure it had when the hand
// went down. Everything that closure captured — the arrow the bar was showing —
// is therefore the arrow from *before* the move, however many redraws happen
// while the thumb travels. The Thickness slider saved that one on release, so
// every thickness he picked went straight back to what it had been: "the
// thickness slider on arrows doesn't stay — it always resets to its default".
//
// This puts a real Slider in a real window, presses it and lets go, once the
// old way (saves what the closure captured) and once the way the arrow bar
// does it now (saves what the slider's own setter last wrote, through a class
// that every closure shares — `ArrowSliderDraft`). quick.sh compiles and runs
// it and wants the old way to still fail and the new way to hold.
import SwiftUI
import AppKit

final class Draft { var latest: Double? }

final class Box: ObservableObject {
    @Published var stored = 1.0
    @Published var drafted: Double?
    var saved: [Double] = []
}

struct Bar: View {
    let shown: Double
    let useDraft: Bool
    let preview: (Double?) -> Void
    let save: (Double) -> Void
    @State private var draft = Draft()
    var body: some View {
        Slider(value: Binding(get: { shown }, set: { v in draft.latest = v; preview(v) }),
               in: 0.5...3.0,
               onEditingChanged: { editing in
                   if !editing {
                       save(useDraft ? (draft.latest ?? shown) : shown)
                       draft.latest = nil
                       preview(nil)
                   }
               })
        .frame(width: 200, height: 30)
    }
}

struct Root: View {
    @ObservedObject var box: Box
    let useDraft: Bool
    var body: some View {
        Bar(shown: box.drafted ?? box.stored, useDraft: useDraft,
            preview: { box.drafted = $0 },
            save: { box.stored = $0; box.saved.append($0) })
            .padding(20)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.finishLaunching()
for useDraft in [false, true] {
    for drag in [false, true] {
        let box = Box()
        let win = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 300, height: 100),
                           styleMask: [.titled], backing: .buffered, defer: false)
        win.contentView = NSHostingView(rootView: Root(box: box, useDraft: useDraft))
        win.orderBack(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        func ev(_ type: NSEvent.EventType, _ p: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: p, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: win.windowNumber, context: nil, eventNumber: 0,
                               clickCount: 1, pressure: 1)!
        }
        let p = NSPoint(x: 180, y: win.contentView!.frame.height / 2)
        win.sendEvent(ev(.leftMouseDown, p))
        app.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.01), inMode: .default, dequeue: true)
        if drag {
            for i in 1...8 {
                win.sendEvent(ev(.leftMouseDragged, NSPoint(x: p.x + CGFloat(i) * 2, y: p.y)))
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
        }
        win.sendEvent(ev(.leftMouseUp, p))
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let moved = (box.saved.first ?? 1.0) > 1.5
        print("slider \(useDraft ? "draft" : "captured") \(drag ? "drag " : "click") saved \(moved ? "the new value" : "the old value")")
    }
}
