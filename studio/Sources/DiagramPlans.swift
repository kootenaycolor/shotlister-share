import AppKit
import SwiftUI

/// **Loose plans** — a diagram that belongs to no scene (his ruling,
/// 2026-10-01: *"loose plans (which you can import any 3d scan into)"*). They
/// sit above the scenes in the Diagram's sidebar; picking one shows it in the
/// scene's place. The engine keeps a plan exactly as it keeps a scene's
/// (`diagram::plans`), so every diagram command takes a plan's id where it
/// says scene — which is why most of the Diagram never had to learn a plan
/// was there.

struct DiagramPlanItem: Decodable, Identifiable, Equatable {
    var id: String
    var name: String
    var count: Int
}

extension Engine {
    func diagramPlans() -> [DiagramPlanItem] {
        struct Reply: Decodable { var plans: [DiagramPlanItem] }
        return (try? JSONDecoder().decode(Reply.self, from: call("diagramplans")))?.plans ?? []
    }

    /// A new plan, blank or a copy of `from`'s diagram. Its id.
    func diagramPlanAdd(name: String = "", from: String? = nil) -> String? {
        struct Reply: Decodable { var id: String }
        var parts = ["diagramplanadd", name]
        if let from { parts.append(from) }
        return (try? JSONDecoder().decode(Reply.self, from: call(parts)))?.id
    }

    func diagramPlanRename(_ id: String, to name: String) { call("diagramplanrename", id, name) }
    func diagramPlanDelete(_ id: String) { call("diagramplandelete", id) }
}

extension ShellState {
    var diagramPlans: [DiagramPlanItem] { engine?.diagramPlans() ?? [] }

    /// The plan picked, while it is still there — a plan deleted, or taken
    /// back by Undo, hands the Diagram back to the scene.
    var diagramPlanLive: DiagramPlanItem? {
        guard let id = diagramPlan else { return nil }
        return diagramPlans.first { $0.id == id }
    }

    /// Whose diagram the Diagram shows: the plan picked, else the scene.
    var diagramOwner: String? { diagramPlanLive?.id ?? sceneDiagramOwner ?? sceneId }

    /// The scene whose shots the Diagram offers — none on a loose plan.
    var diagramScene: String? { diagramPlanLive == nil ? sceneId : nil }

    /// What the Diagram's header and Export name.
    var diagramSheet: DiagramSheet? {
        if let plan = diagramPlanLive { return DiagramSheet(plan: plan.id, name: plan.name) }
        guard let scene else { return nil }
        var sheet = DiagramSheet(scene)
        // One of several: the header says which (`DiagramScenes`); Export
        // still takes the scene, every diagram of it a sheet.
        if let open = sceneDiagramsNow.first(where: { $0.id == sceneDiagramOwner }) {
            sheet.heading += " — \(open.title)"
        }
        return sheet
    }
}

@MainActor
enum DiagramPlanActions {
    /// + in the sidebar: a blank plan, picked. `from`: start it as a copy.
    static func add(_ state: ShellState, from: String? = nil, name: String = "") {
        guard let engine = state.engine, let id = engine.diagramPlanAdd(name: name, from: from) else { return }
        state.replace(engine.view())
        state.diagramPlan = id
    }

    static func rename(_ state: ShellState, _ plan: DiagramPlanItem) {
        guard let engine = state.engine else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Plan"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = plan.name
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != plan.name else { return }
        engine.diagramPlanRename(plan.id, to: name)
        state.replace(engine.view())
        state.objectWillChange.send()
    }

    /// Deleting is his decision, asked every time, with what it costs.
    static func delete(_ state: ShellState, _ plan: DiagramPlanItem, asking: Bool = true) {
        guard let engine = state.engine else { return }
        if asking {
            let alert = NSAlert()
            alert.messageText = "Delete \(plan.name)"
            if plan.count > 0 {
                alert.informativeText = "\(DiagramCopy.pieces(plan.count)) on it go with it."
            }
            let delete = alert.addButton(withTitle: "Delete")
            delete.hasDestructiveAction = true
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        engine.diagramPlanDelete(plan.id)
        if state.diagramPlan == plan.id { state.diagramPlan = nil }
        state.replace(engine.view())
    }
}

/// The Plans run at the top of the Diagram's scene list — rows of the same
/// list, tagged `plan:<id>` so picking one is a pick like any scene's
/// (`Sidebar.sceneList`, which draws the Scenes head under them).
///
/// **Each head carries its own buttons**, his report 2026-10-02 (*"this looks
/// messy"*): the scene list's filter and + stood in a row of their own with
/// nothing on its left, over a Plans head with a second, larger + drawn from
/// a text glyph. Now Plans has its + and Scenes its filter and +, the same
/// `ToolButton`, and both heads start at the panels' edge.
struct DiagramPlanRows: View {
    @ObservedObject var state: ShellState
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    static let tagPrefix = "plan:"

    var body: some View {
        let plans = state.diagramPlans
        let picked = state.diagramPlanLive?.id
        Self.head("Plans", dark: dark) {
            ToolButton(icon: "plus", help: "New Plan") { DiagramPlanActions.add(state) }
                .disabled(state.view?.project.readOnly == true)
        }
        .padding(.top, 2)
        ForEach(plans) { plan in
            HStack(spacing: 8) {
                Text(plan.name)
                    .sans(11, weight: .semibold)
                    .foregroundStyle(Brand.ink(dark))
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                if plan.count > 0 {
                    Text(DiagramCopy.pieces(plan.count))
                        .sans(Brand.Size.tiny).monospacedDigit()
                        .foregroundStyle(Brand.ink3(dark))
                        .fixedSize()
                }
            }
            .padding(.vertical, 6).padding(.horizontal, 8)
            .tag(Self.tagPrefix + plan.id)
            .sidebarRow(picked: picked == plan.id, dark: dark)
            .contextMenu {
                Button("Rename…") { DiagramPlanActions.rename(state, plan) }
                Button("Duplicate") {
                    DiagramPlanActions.add(state, from: plan.id, name: "\(plan.name) Copy")
                }
                Divider()
                Button("Delete…") { DiagramPlanActions.delete(state, plan) }
            }
        }
    }

    /// A head of the list — Plans, Scenes — with its buttons opposite. Not
    /// pickable; the words sit on the panels' left edge and the buttons end
    /// on their right, so the list reads as one column.
    static func head<Buttons: View>(_ title: String, dark: Bool,
                                    @ViewBuilder buttons: () -> Buttons) -> some View {
        HStack(spacing: 4) {
            Text(title).sans(Brand.Size.small, weight: .semibold).foregroundStyle(Brand.ink3(dark))
            Spacer(minLength: 0)
            buttons()
        }
        .padding(.bottom, 2)
        .selectionDisabled()
        // **4 in, not `sidebarRow`'s 12.** The list sets every row's words 8
        // further in than its fill, so 12 put the head 8 inside the panels'
        // edge, between their edge and their words. 4 lands the words on the
        // edge, and the buttons end on the right one.
        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}
