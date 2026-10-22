import AppKit
import SwiftUI

/// **Several diagrams on one scene** (his ask, 2026-10-17) and **Hide
/// Empty** on the Diagram's scene list. The engine keeps them
/// (`diagram::scenediagrams`): the scene's own diagram is one of them, the
/// others are records of their own, and every diagram command takes any of
/// their ids where it says scene — so the Diagram only has to know which one
/// is open. Names are his; an unnamed one shows "Diagram N" in grey.

struct SceneDiagramItem: Decodable, Identifiable, Equatable {
    var id: String
    var name: String
    var title: String
    var count: Int
}

extension Engine {
    func sceneDiagrams(_ scene: String) -> [SceneDiagramItem] {
        struct Reply: Decodable { var diagrams: [SceneDiagramItem] }
        return (try? JSONDecoder().decode(Reply.self, from: call("scenediagrams", scene)))?.diagrams ?? []
    }

    func sceneDiagramAdd(_ scene: String, name: String = "", from: String? = nil) -> String? {
        struct Reply: Decodable { var id: String }
        var parts = ["scenediagramadd", scene, name]
        if let from { parts.append(from) }
        return (try? JSONDecoder().decode(Reply.self, from: call(parts)))?.id
    }

    func sceneDiagramRename(_ id: String, to name: String) { call("scenediagramrename", id, name) }
    func sceneDiagramMove(_ id: String, to index: Int) { call("scenediagrammove", id, String(index)) }
    func sceneDiagramDelete(_ id: String) { call("scenediagramdelete", id) }
    /// Hide scenes from the Diagram's list, or show them (`diagramhide`).
    func diagramHide(_ scenes: [String], _ hidden: Bool) { call("diagramhide", hidden ? "on" : "off", scenes.joined(separator: ",")) }
}

extension ShellState {
    /// The picked scene's diagrams, when it has more than one; empty for the
    /// usual one.
    var sceneDiagramsNow: [SceneDiagramItem] { scene?.diagrams ?? [] }

    /// Which of the scene's diagrams is open: the one picked, while it is
    /// still the scene's, else the first in his order. Nil: the scene's own,
    /// the only one.
    var sceneDiagramOwner: String? {
        let all = sceneDiagramsNow
        guard !all.isEmpty else { return nil }
        if let pick = sceneDiagramPick, all.contains(where: { $0.id == pick }) { return pick }
        return all.first?.id
    }

    // ---- Hide Empty, remembered for each project ----------------------------

    private static let hideKey = "diagramHideEmpty"

    var diagramHideEmpty: Bool {
        get {
            guard let id = view?.project.id else { return false }
            if let now = diagramHideEmptyNow[id] { return now }
            return (defaults.dictionary(forKey: Self.hideKey)?[id] as? Bool) ?? false
        }
        set {
            guard let id = view?.project.id else { return }
            diagramHideEmptyNow[id] = newValue
            var all = defaults.dictionary(forKey: Self.hideKey) ?? [:]
            all[id] = newValue
            defaults.set(all, forKey: Self.hideKey)
        }
    }

    /// Whether the Diagram's list would leave this scene out, by hand or by
    /// Hide Empty — except the one he is on, which always stays.
    func diagramLeftOut(_ scene: ViewModel.Scene) -> Bool {
        guard scene.id != sceneId else { return false }
        return scene.diagramHidden == true || (diagramHideEmpty && (scene.diagram ?? 0) == 0)
    }

    /// Whether the list leaves it out now: unless the "N Hidden" line has
    /// been opened.
    func diagramHides(_ scene: ViewModel.Scene) -> Bool {
        !diagramRevealHidden && diagramLeftOut(scene)
    }

    /// What the "N Hidden" line counts: hand-hidden and Hide Empty's together.
    var diagramHiddenCount: Int { scenes.filter { diagramLeftOut($0) }.count }

    func diagramHandHidden(_ id: String) -> Bool {
        view?.scenes.first { $0.id == id }?.diagramHidden == true
    }

    /// **Hide from Diagrams / Show.** The engine keeps it on the scene
    /// (`diagram_hidden`), so the iPhone and the portal read the same.
    func hideFromDiagrams(_ ids: [String], hidden: Bool) {
        guard let engine, !ids.isEmpty else { return }
        engine.diagramHide(ids, hidden)
        replace(engine.view())
        // Nothing left out: the line goes, and the next hide starts closed.
        if hidden || diagramHiddenCount == 0 { diagramRevealHidden = false }
    }
}

@MainActor
enum DiagramSceneActions {
    /// A new diagram on the scene, opened, its name asked for at once — left
    /// blank, it keeps the grey placeholder. `from`: start as its copy.
    static func add(_ state: ShellState, from: String? = nil) {
        guard let engine = state.engine, let scene = state.sceneId,
              let id = engine.sceneDiagramAdd(scene, from: from) else { return }
        state.replace(engine.view())
        state.sceneDiagramPick = id
        if let made = state.sceneDiagramsNow.first(where: { $0.id == id }) {
            rename(state, made, title: from == nil ? "New Diagram" : "Duplicate")
        }
    }

    static func rename(_ state: ShellState, _ item: SceneDiagramItem, title: String = "Rename Diagram") {
        guard let engine = state.engine else { return }
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = item.name
        field.placeholderString = item.title
        alert.accessoryView = field
        alert.addButton(withTitle: title == "Rename Diagram" ? "Rename" : "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard name != item.name else { return }
        engine.sceneDiagramRename(item.id, to: name)
        state.replace(engine.view())
    }

    static func move(_ state: ShellState, _ item: SceneDiagramItem, by step: Int) {
        guard let engine = state.engine,
              let at = state.sceneDiagramsNow.firstIndex(where: { $0.id == item.id }) else { return }
        engine.sceneDiagramMove(item.id, to: max(0, at + step))
        state.replace(engine.view())
    }

    /// Deleting is his decision, asked every time, with what it costs.
    static func delete(_ state: ShellState, _ item: SceneDiagramItem, asking: Bool = true) {
        guard let engine = state.engine else { return }
        if asking {
            let alert = NSAlert()
            alert.messageText = "Delete \(item.title)?"
            if item.count > 0 { alert.informativeText = "\(DiagramCopy.pieces(item.count)) on it go with it." }
            let delete = alert.addButton(withTitle: "Delete")
            delete.hasDestructiveAction = true
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        engine.sceneDiagramDelete(item.id)
        if state.sceneDiagramPick == item.id { state.sceneDiagramPick = nil }
        state.replace(engine.view())
    }
}

/// **The switcher**: a row of tabs along the foot of the Diagram's header,
/// one a diagram, and + at the end. A scene with one diagram shows only a
/// quiet "+ New Diagram".
struct DiagramTabStrip: View {
    @ObservedObject var state: ShellState
    let readOnly: Bool
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        let all = state.sceneDiagramsNow
        let open = state.sceneDiagramOwner
        HStack(alignment: .bottom, spacing: 2) {
            Group {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(Array(all.enumerated()), id: \.element.id) { i, item in
                            tab(item, on: item.id == open, index: i, of: all.count)
                        }
                        if !readOnly {
                            Button { DiagramSceneActions.add(state) } label: {
                                Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Brand.ink3(dark))
                                    .frame(width: 28, height: 28).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("New Diagram")
                            .accessibilityIdentifier("diagram.newDiagram")
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 30, alignment: .bottom)
    }

    private func tab(_ item: SceneDiagramItem, on: Bool, index: Int, of count: Int) -> some View {
        Button { state.sceneDiagramPick = item.id } label: {
            Text(item.title)
                .sans(Brand.Size.small, weight: on ? .semibold : .medium)
                .italic(item.name.isEmpty)
                .foregroundStyle(on ? Brand.ink(dark) : (item.name.isEmpty ? Brand.ink3(dark) : Brand.ink2(dark)))
                .lineLimit(1)
                .padding(.horizontal, 12).frame(height: 28)
                .background(UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8, style: .continuous)
                    .fill(on ? Brand.glassOn(dark) : .clear))
                .overlay(alignment: .top) {
                    if on { Rectangle().fill(Brand.ink(dark)).frame(height: 2).padding(.horizontal, 6) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("diagram.tab.\(index)")
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if !readOnly { DiagramSceneActions.rename(state, item) }
        })
        .contextMenu {
            if !readOnly {
                Button("Rename…") { DiagramSceneActions.rename(state, item) }
                Button("Duplicate") { DiagramSceneActions.add(state, from: item.id) }
                Divider()
                Button("Move Left") { DiagramSceneActions.move(state, item, by: -1) }.disabled(index == 0)
                Button("Move Right") { DiagramSceneActions.move(state, item, by: 1) }.disabled(index == count - 1)
                Divider()
                Button("Delete…") { DiagramSceneActions.delete(state, item) }
            }
        }
    }
}
