import SwiftUI
import AppKit

// **The Diagram's two sidebars** (design/24, approved 2026-09-28). His
// complaint was eleven floating pieces — "two bottom bars, nothing's
// centered — it's all kind of a mess". One job, one place: the scene list,
// Layers and Shots are three tabs of the app's own left sidebar, and Details
// and Gear two tabs of one rounded panel down the right. Both are inset,
// rounded panels like the rest of the program's, not flush columns (his one
// change to the mock).

/// A row of tabs at the head of a sidebar: the one showing on a soft fill.
struct DiagramTabs: View {
    let items: [(key: String, title: String)]
    let selected: String?
    var fill = true
    let pick: (String) -> Void
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.key) { item in
                let on = item.key == selected
                Button { pick(item.key) } label: {
                    Text(item.title).sans(Brand.Size.body, weight: on ? .semibold : .medium)
                        .foregroundStyle(on ? Brand.ink(dark) : Brand.ink2(dark))
                        .padding(.horizontal, fill ? 0 : 12)
                        .frame(maxWidth: fill ? .infinity : nil).frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(on ? Brand.glassOn(dark) : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The left sidebar in the Diagram: Scenes · Layers · Shots. The Legend is
/// on the sheet now, where it prints (Back to Paper, design/32 item 9).
struct DiagramSidebar<Scenes: View>: View {
    @ObservedObject var state: ShellState
    @ObservedObject var model: DiagramModel
    @ViewBuilder var scenes: () -> Scenes

    var body: some View {
        let tab = model.sideTab == "legend" ? "scenes" : model.sideTab
        VStack(spacing: 0) {
            DiagramTabs(items: [("scenes", "Scenes"), ("layers", "Layers"), ("shots", "Shots")],
                        selected: tab) { tab in model.sideTab = tab }
                .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 8)
            switch tab {
            case "layers": DiagramLayers(model: model)
            case "shots": DiagramShots(model: model)
            default: scenes()
            }
        }
    }
}

/// The right sidebar: Details, a rounded panel inset from the edge, there
/// only when asked for. The gear is Copy › Gear List now.
struct DiagramRightPanel: View {
    @ObservedObject var state: ShellState
    @ObservedObject var model: DiagramModel
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DiagramInspector(state: state, model: model)
                .disabled(model.readOnly)
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DiagramFloat(dark: dark, radius: 16))
    }
}
