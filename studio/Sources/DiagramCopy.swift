import AppKit
import SwiftUI

/// **Plans between scenes** (his ask, 2026-10-01: *"lets do copying
/// properly"*). Copy From pulls another scene's plan onto this one; Copy To
/// sends this one to as many scenes as he ticks; Send to Scene does the same
/// with just the picked pieces. A plan that already holds something is never
/// replaced without asking — Add on Top keeps it and lays the copies over it,
/// where they were drawn. The engine does the copying (`diagram::copy`); this
/// only asks.
enum DiagramCopyMode: String { case replace, add }

extension Engine {
    /// Every scene with a plan, by id, and how many pieces it holds.
    func diagramCounts() -> [String: Int] {
        struct Reply: Decodable { var scenes: [String]; var counts: [String: Int]? }
        guard let r = try? JSONDecoder().decode(Reply.self, from: call("diagramscenes", "")) else { return [:] }
        return r.counts ?? Dictionary(r.scenes.map { ($0, 1) }, uniquingKeysWith: { a, _ in a })
    }

    /// `from`'s plan (or its pieces `ids`) onto `scene`'s. How many came.
    func diagramCopy(scene: String, from: String, mode: DiagramCopyMode, ids: [String] = []) -> Int {
        struct Reply: Decodable { var copied: Int }
        var parts = ["diagramcopy", scene, from, "mode=\(mode.rawValue)"]
        if !ids.isEmpty { parts.append("ids=" + ids.joined(separator: ",")) }
        return (try? JSONDecoder().decode(Reply.self, from: call(parts)))?.copied ?? 0
    }

    /// `scene`'s plan (or its pieces `ids`) onto each of `to`. How many
    /// pieces each got.
    func diagramSend(scene: String, to: [String], mode: DiagramCopyMode, ids: [String] = []) -> Int {
        struct Reply: Decodable { var copied: Int }
        var parts = ["diagramsend", scene, "to=" + to.joined(separator: ","), "mode=\(mode.rawValue)"]
        if !ids.isEmpty { parts.append("ids=" + ids.joined(separator: ",")) }
        return (try? JSONDecoder().decode(Reply.self, from: call(parts)))?.copied ?? 0
    }
}

@MainActor
enum DiagramCopy {
    static func pieces(_ n: Int) -> String { n == 1 ? "1 piece" : "\(n) pieces" }

    /// Where a plan can go to or come from: the loose plans, then the live
    /// scenes — never the one open. `count`: how many pieces it holds.
    struct Target: Identifiable {
        var id: String
        /// What a menu or the list calls it — `4A  INT. KITCHEN - DAY`, or a plan's name.
        var label: String
        /// What a title calls it — `4A`, or a plan's name.
        var short: String
        var count: Int
        var plan: Bool
    }

    static func targets(_ model: DiagramModel) -> [Target] {
        guard let state = model.state else { return [] }
        let counts = state.engine?.diagramCounts() ?? [:]
        let plans = state.diagramPlans.filter { $0.id != model.scene }.map {
            Target(id: $0.id, label: $0.name, short: $0.name, count: $0.count, plan: true)
        }
        let scenes = (state.view?.scenes ?? []).filter { !$0.archived && $0.id != model.scene }.map { s in
            Target(id: s.id, label: [s.number, s.heading.isEmpty ? s.title : s.heading].filter { !$0.isEmpty }.joined(separator: "  "),
                   short: s.number, count: counts[s.id] ?? 0, plan: false)
        }
        return plans + scenes
    }

    /// **Copy From** — `source`'s plan onto this one. Over a drawn plan it
    /// asks: Add on Top, Replace, or Cancel.
    static func from(_ source: Target, into model: DiagramModel, mode asked: DiagramCopyMode? = nil) {
        guard let engine = model.engine, let scene = model.scene else { return }
        let here = model.plan.els.count
        var mode = asked ?? .replace
        if asked == nil, here > 0 {
            let alert = NSAlert()
            alert.messageText = "Copy From \(source.short)"
            alert.informativeText = "Replaces this plan"
            alert.addButton(withTitle: "Add on Top")
            let replace = alert.addButton(withTitle: "Replace")
            replace.hasDestructiveAction = true
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn: mode = .add
            case .alertSecondButtonReturn: mode = .replace
            default: return
            }
        }
        let n = engine.diagramCopy(scene: scene, from: source.id, mode: mode)
        guard n > 0 else { return }
        model.state?.replace(engine.view())
        model.reload()
        if mode == .replace || here == 0 { model.fitted = false }
        model.flash("Copied \(pieces(n))")
    }

    /// **Copy To** (`ids` empty: the whole plan) and **Send to Scene** (the
    /// picked pieces): tick the scenes, and for a whole plan choose whether
    /// it replaces theirs or goes on top.
    static func to(model: DiagramModel, ids: [String]) {
        guard let engine = model.engine, let scene = model.scene else { return }
        let places = targets(model)
        guard !places.isEmpty, !model.plan.els.isEmpty else { return }
        let counts = Dictionary(places.map { ($0.id, $0.count) }, uniquingKeysWith: { a, _ in a })
        let whole = ids.isEmpty

        let alert = NSAlert()
        alert.messageText = whole ? "Copy To" : "Send To"
        alert.informativeText = whole ? pieces(model.plan.els.count) : pieces(ids.count)
        let picker = ScenePicker(targets: places, choosesMode: whole)
        alert.accessoryView = picker.view
        alert.addButton(withTitle: whole ? "Copy" : "Send")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let ticked = picker.ticked
        guard !ticked.isEmpty else { return }
        let mode: DiagramCopyMode = picker.replaces ? .replace : .add

        if mode == .replace {
            let drawn = ticked.filter { (counts[$0] ?? 0) > 0 }
            if !drawn.isEmpty {
                let confirm = NSAlert()
                confirm.messageText = "Replace \(drawn.count == 1 ? "1 Plan" : "\(drawn.count) Plans")"
                let held = drawn.reduce(0) { $0 + (counts[$1] ?? 0) }
                confirm.informativeText = "\(pieces(held)) on \(drawn.count == 1 ? "that plan" : "those plans") will be replaced."
                let replace = confirm.addButton(withTitle: "Replace")
                replace.hasDestructiveAction = true
                confirm.addButton(withTitle: "Cancel")
                guard confirm.runModal() == .alertFirstButtonReturn else { return }
            }
        }
        send(model: model, engine: engine, scene: scene, to: ticked, mode: mode, ids: ids)
    }

    /// The list Copy To shows, drawn to a PNG — so a check can look at it
    /// without a modal sheet stopping the run.
    static func pickerPicture(model: DiagramModel) -> Data? {
        guard let engine = model.engine else { return nil }
        _ = engine
        let picker = ScenePicker(targets: targets(model), choosesMode: true)
        let v = picker.view
        v.appearance = NSApp.effectiveAppearance
        v.layoutSubtreeIfNeeded()
        let bg = NSView(frame: v.bounds.insetBy(dx: -12, dy: -12))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        v.frame.origin = NSPoint(x: 12, y: 12)
        bg.addSubview(v)
        bg.appearance = NSApp.effectiveAppearance
        guard let rep = bg.bitmapImageRepForCachingDisplay(in: bg.bounds) else { return nil }
        bg.cacheDisplay(in: bg.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// The sending itself, without asking — what the checks call.
    static func send(model: DiagramModel, engine: Engine, scene: String, to: [String], mode: DiagramCopyMode, ids: [String]) {
        let n = engine.diagramSend(scene: scene, to: to, mode: mode, ids: ids)
        guard n > 0 else { return }
        model.state?.replace(engine.view())
        model.reload()
        model.flash(to.count == 1 ? "Copied to 1 plan" : "Copied to \(to.count) plans")
    }
}

/// The list Copy To and Send To show: every loose plan and every other scene,
/// a box to tick and how many pieces each holds, and — for a whole plan — Add on
/// Top or Replace.
@MainActor
private final class ScenePicker: NSObject {
    let view: NSView
    private var boxes: [(String, NSButton)] = []
    private var modeControl: NSSegmentedControl?

    init(targets: [DiagramCopy.Target], choosesMode: Bool) {
        let width: CGFloat = 380
        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 4
        list.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        var boxes: [(String, NSButton)] = []
        for s in targets {
            let box = NSButton(checkboxWithTitle: s.label, target: nil, action: nil)
            box.lineBreakMode = .byTruncatingTail
            let n = s.count
            let count = NSTextField(labelWithString: n > 0 ? DiagramCopy.pieces(n) : "")
            count.textColor = .secondaryLabelColor
            count.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            let row = NSStackView(views: [box, count])
            row.orientation = .horizontal
            row.distribution = .fill
            box.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            count.setContentHuggingPriority(.required, for: .horizontal)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalToConstant: width - 30).isActive = true
            list.addArrangedSubview(row)
            boxes.append((s.id, box))
        }
        self.boxes = boxes

        let rows = CGFloat(min(targets.count, 12))
        let listHeight = rows * 22 + 12
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: listHeight))
        scroll.hasVerticalScroller = targets.count > 12
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = false
        let flipped = FlippedView(frame: NSRect(x: 0, y: 0, width: width - 4, height: list.fittingSize.height))
        list.frame = flipped.bounds
        list.autoresizingMask = [.width, .height]
        flipped.addSubview(list)
        scroll.documentView = flipped

        let modeHeight: CGFloat = choosesMode ? 34 : 0
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: listHeight + modeHeight))
        scroll.frame.origin = NSPoint(x: 0, y: modeHeight)
        container.addSubview(scroll)
        if choosesMode {
            let seg = NSSegmentedControl(labels: ["Add on Top", "Replace"], trackingMode: .selectOne, target: nil, action: nil)
            seg.selectedSegment = 0
            seg.sizeToFit()
            seg.frame.origin = NSPoint(x: 0, y: 2)
            container.addSubview(seg)
            modeControl = seg
        }
        view = container
        super.init()
    }

    var ticked: [String] { boxes.filter { $0.1.state == .on }.map(\.0) }
    var replaces: Bool { modeControl?.selectedSegment == 1 }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
