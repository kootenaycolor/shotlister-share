import SwiftUI

// **Project Settings, sorted** (his approved mockup, 2026-10-16, "Studio
// settings, sorted", claude.ai/artifact/P6ZrWPbz4XZHNWBhDue9MU): Studio
// Settings (⌘,) is only about the app on this Mac; everything about the open
// project lives here, with all of the spec sheet in one group. These are the
// pages that arrived with it: the Spec Sheet group's one status line, Aspect
// Ratio, Columns and Lists.

/// **The Spec Sheet group's one status line**, from real data: whether the
/// lists follow the sheet, and when the sheet last changed.
struct SpecStatus: View {
    @ObservedObject var state: ShellState
    @ObservedObject private var sheets = SpecSheets.shared
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    static func green(_ dark: Bool) -> Color { Brand.data("2F9E5B", dark) }

    var body: some View {
        HStack(spacing: 6) {
            if SpecSheets.linked(state) {
                Circle().fill(Self.green(dark)).frame(width: 6, height: 6)
                let ago = SpecSheets.ago(sheets.updated)
                Text("Shared with Console, portal and iPhone" + (ago.isEmpty ? "" : " · Updated \(ago)"))
                    .sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark)).lineLimit(1)
                Spacer(minLength: 0)
            } else if SpecSheets.hasSheet(state) {
                Circle().strokeBorder(Brand.ink3(dark), lineWidth: 1).frame(width: 6, height: 6)
                Text("Not synced").sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark))
                Spacer(minLength: 0)
                Button("Sync with Spec Sheet") { sheets.setMode("follow", state: state) }
            } else {
                Text("No Spec Sheet").sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark))
                Spacer(minLength: 0)
            }
        }
        .onAppear {
            if SpecSheets.hasSheet(state), !sheets.read { sheets.refresh(state) }
        }
    }
}

/// **Aspect Ratio**: the spec sheet's aspect ratios, and the one Studio draws
/// storyboards at. His rules (2026-10-16): the choices come only from the
/// spec sheet; with only one there is nothing to choose, so the row is not
/// there. A film with no spec sheet keeps its own ratio, picked freely.
struct AspectRatioPage: View {
    @ObservedObject var state: ShellState
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }
    private var project: ViewModel.Project? { state.view?.project }

    /// The rail's figure: the aspect ratio Studio draws at.
    static func face(_ project: ViewModel.Project?) -> String {
        guard let project else { return "" }
        if let frames = project.frames, let picked = frames.first(where: { $0.picked }) ?? frames.first {
            return Self.short(picked.said)
        }
        return Self.short(Ratios.name(project.ratio))
    }

    /// "2.39:1" → "2.39"; "9:16" stays.
    static func short(_ said: String) -> String {
        said.hasSuffix(":1") ? String(said.dropLast(2)).trimmingCharacters(in: .whitespaces) : said
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let frames = project?.frames {
                    Text("Aspect Ratios").fieldLabel(dark)
                    SettingsBox {
                        ForEach(Array(frames.enumerated()), id: \.element.id) { at, f in
                            if at > 0 { Divider().overlay(Brand.ruleFaint(dark)) }
                            HStack(spacing: 10) {
                                RatioGlyph(ratio: f.ratio, dark: dark)
                                Text(f.said).sans(Brand.Size.body, weight: .medium).foregroundStyle(Brand.ink(dark))
                                if f.name != f.said, !f.name.isEmpty {
                                    Text(f.name).sans(Brand.Size.body).foregroundStyle(Brand.ink2(dark))
                                }
                                Spacer(minLength: 0)
                                if f.main { Chip(text: "Main", colour: Brand.ink3(dark), density: 1) }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                        }
                    }
                    if frames.count > 1 {
                        working(frames)
                    }
                } else {
                    // A Studio-only film: its own ratio, any it likes.
                    Text("Working Aspect Ratio").fieldLabel(dark)
                    SettingsBox {
                        HStack {
                            Text("Draw Storyboards At").sans(Brand.Size.body).foregroundStyle(Brand.ink(dark))
                            Spacer(minLength: 0)
                            ProjectFrameMenu(state: state) { face(Ratios.title(project?.ratio ?? 2.39)) }
                                .fixedSize()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                    studioOnly
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18).padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func working(_ frames: [ViewModel.ProjectFrame]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Working Aspect Ratio").fieldLabel(dark).padding(.top, 10)
            SettingsBox {
                HStack {
                    Text("Draw Storyboards At").sans(Brand.Size.body).foregroundStyle(Brand.ink(dark))
                    Spacer(minLength: 0)
                    Menu {
                        ForEach(frames) { f in
                            Button {
                                guard let engine = state.engine, !f.picked else { return }
                                state.replace(engine.pickFrame(f.name))
                            } label: {
                                if f.picked { Label(f.said, systemImage: "checkmark") } else { Text(f.said) }
                            }
                        }
                    } label: {
                        face((frames.first { $0.picked } ?? frames.first)?.said ?? "")
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .accessibilityIdentifier("settings.drawat")
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                Divider().overlay(Brand.ruleFaint(dark))
                HStack {
                    Text("Show Other Aspect Ratios as Guides").sans(Brand.Size.body).foregroundStyle(Brand.ink(dark))
                    Spacer(minLength: 0)
                    Toggle("", isOn: Binding(
                        get: { project?.frameGuides ?? false },
                        set: { on in
                            guard let engine = state.engine else { return }
                            state.replace(engine.setFrameGuides(on))
                        }))
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            studioOnly
        }
    }

    private var studioOnly: some View {
        HStack(spacing: 5) {
            Circle().strokeBorder(Brand.ink3(dark), lineWidth: 1).frame(width: 6, height: 6)
            Text("Studio only").sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark))
        }
    }

    private func face(_ words: String) -> some View {
        HStack(spacing: 4) {
            Text(words).sans(Brand.Size.body).monospacedDigit()
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(Brand.ink(dark))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5).fill(Brand.glass2(dark)))
    }
}

/// A small outline of an aspect ratio's shape.
private struct RatioGlyph: View {
    let ratio: Double
    let dark: Bool
    var body: some View {
        let r = max(min(ratio, 3), 0.3)
        let w: CGFloat = r >= 1 ? 22 : 22 * r
        let h: CGFloat = r >= 1 ? 22 / r : 22
        RoundedRectangle(cornerRadius: 2)
            .strokeBorder(Brand.ink3(dark), lineWidth: 1.2)
            .frame(width: max(w, 6), height: max(h, 6))
            .frame(width: 24, height: 24)
    }
}

/// A rounded group of rows, as the mockup's settings boxes.
struct SettingsBox<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let dark = scheme == .dark
        VStack(alignment: .leading, spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: Brand.radius + 2, style: .continuous).fill(Brand.glass2(dark)))
            .overlay(RoundedRectangle(cornerRadius: Brand.radius + 2, style: .continuous)
                .strokeBorder(Brand.glassEdge(dark), lineWidth: 1))
    }
}

/// **Columns**: what the shot list shows, and the editor for it. The editor
/// is the main window's sheet, so this one steps aside for it.
struct ColumnsPage: View {
    @ObservedObject var state: ShellState
    let close: () -> Void
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        let shown = (state.view?.columns ?? []).filter(\.visible)
        VStack(alignment: .leading, spacing: 10) {
            SettingsBox {
                HStack(spacing: 8) {
                    Text("Shot List Columns").sans(Brand.Size.body).foregroundStyle(Brand.ink(dark))
                    Spacer(minLength: 0)
                    Text("\(shown.count) Shown").sans(Brand.Size.body).foregroundStyle(Brand.ink3(dark))
                    Button("Edit…") { Self.edit(state, close: close) }
                        .accessibilityIdentifier("settings.columns")
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            WrappingRow(spacing: 6, runSpacing: 6) {
                ForEach(shown, id: \.name) { column in
                    Text(Columns.label(column.name)).sans(Brand.Size.small).foregroundStyle(Brand.ink2(dark))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Brand.glass2(dark)))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).padding(.bottom, 18)
    }

    /// Close Project Settings, then open the column editor on the main window.
    static func edit(_ state: ShellState, close: () -> Void) {
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { state.editingColumns = true }
    }
}

/// **Lists**: every list that is not the spec sheet's or Tags, one at a time.
struct ListsPage: View {
    @ObservedObject var state: ShellState
    let fields: [String]
    @State private var field = ""
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    private var all: [String] { fields.contains("camera") ? fields : fields + ["camera"] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Dropdown(selection: Binding(get: { field.isEmpty ? (all.first ?? "") : field },
                                            set: { field = $0 }),
                         items: all.map { .init($0, Columns.label($0)) }, width: 220)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18).padding(.bottom, 4)
            let shown = field.isEmpty ? (all.first ?? "") : field
            if shown == "camera" {
                CameraPage(state: state)
            } else if !shown.isEmpty {
                ListPage(state: state, field: shown)
            }
        }
    }
}

/// **The gear** (mockup part 1): quick jumps in one click, and the working
/// aspect ratio when the spec sheet gives more than one.
struct GearPopover: View {
    @ObservedObject var state: ShellState
    let done: () -> Void
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        let project = state.view?.project
        VStack(alignment: .leading, spacing: 2) {
            if let frames = project?.frames, frames.count > 1 {
                Text("Working Aspect Ratio").sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark))
                    .padding(.horizontal, 10).padding(.top, 4)
                Picker("", selection: Binding(
                    get: { (frames.first { $0.picked } ?? frames.first)?.name ?? "" },
                    set: { name in
                        guard let engine = state.engine,
                              frames.first(where: { $0.name == name })?.picked == false else { return }
                        state.replace(engine.pickFrame(name))
                    })) {
                    ForEach(frames) { Text(AspectRatioPage.short($0.said)).tag($0.name) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .padding(.horizontal, 10).padding(.bottom, 6)
                Divider().padding(.vertical, 2)
            }
            row("tablecells", "Columns…", trailing: "\((state.view?.columns ?? []).filter(\.visible).count) shown") {
                done()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { state.editingColumns = true }
            }
            row("doc.text", "Spec Sheet…") { open(.aspect) }
            row("tag", "Tags…") { open(.list("tags")) }
            Divider().padding(.vertical, 2)
            row("gearshape", "Project Settings…", trailing: "⇧⌘,") { open(nil) }
            row("macwindow", "Studio Settings…", trailing: "⌘,") {
                done()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { SettingsDoor.open() }
            }
        }
        .padding(6)
        .frame(width: 250)
    }

    private func open(_ page: SettingsPage?) {
        done()
        state.settingsPage = page
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { state.editingProject = true }
    }

    private func row(_ icon: String, _ title: String, trailing: String = "",
                     action: @escaping () -> Void) -> some View {
        GearRow(icon: icon, title: title, trailing: trailing, action: action)
    }
}

private struct GearRow: View {
    let icon: String
    let title: String
    let trailing: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 11)).frame(width: 16)
                    .foregroundStyle(hovering ? Color.white : Brand.ink2(dark))
                Text(title).sans(Brand.Size.body)
                    .foregroundStyle(hovering ? Color.white : Brand.ink(dark))
                Spacer(minLength: 0)
                Text(trailing).sans(Brand.Size.small)
                    .foregroundStyle(hovering ? Color.white.opacity(0.8) : Brand.ink3(dark))
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? Color.accentColor : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
    }
}
