import SwiftUI

/// **Studio ▸ Settings… (⌘,)** — the Mac's own settings window, with tabs
/// (2026-10-15, mockup "Two Settings screens",
/// claude.ai/artifact/35coMv5bAQBVQPZDf3rbXT; his: "LIKES a real Studio
/// Preferences window").
///
/// What moved in, and from where (the full before/after is
/// `settings-inventory.md` in the coordinator's notes):
///
/// - **General** — Text Size (the bar's zoom slider; ⌘+ ⌘− ⌘0 still walk
///   it), On Launch (new), Play Clips and Clip Thumbnails (the View menu).
/// - **Aspect Ratio and Columns moved to Project Settings** (2026-10-16,
///   his approved mockup "Studio settings, sorted"): this window is only
///   about the app on this Mac.
/// - **Sync** — the relay, its state, Sync Now, Set Up Sync…, Sync History…,
///   and the two copy buttons (the sync button's right-click menu keeps them).
///
/// Project Settings (the film's facts, lists, script, spec sheet, sequences,
/// spreadsheet) stays its own sheet: the gear and ⇧⌘,.
struct StudioSettings: View {
    @ObservedObject var state: ShellState
    @AppStorage("settings.tab") private var tab = SettingsTab.general.rawValue

    var body: some View {
        TabView(selection: Binding(
            // **App only** (2026-10-16): General and Sync. Aspect Ratio and
            // Columns moved into Project Settings; a remembered old tab
            // lands on General.
            get: {
                let want = Launch.checking ? (StudioSettings.checkTab ?? tab) : tab
                return want == SettingsTab.sync.rawValue ? want : SettingsTab.general.rawValue
            },
            set: { tab = $0; StudioSettings.checkTab = $0 })) {
            GeneralTab(state: state)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general.rawValue)
            SyncTab(state: state)
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                .tag(SettingsTab.sync.rawValue)
        }
        .frame(width: 480)
        .background(SettingsWindowTag())
    }

    /// The tab a checking run asked for (`--prefs <tab>`); a check never
    /// writes his remembered tab.
    static var checkTab: String?
}

enum SettingsTab: String, CaseIterable {
    case general, aspectRatio = "aspect", columns, sync
}

/// **Text size has one value and two controls** (the shot list bar's slider and
/// Settings ▸ General ▸ Text Size). Both set it here, and both redraw on
/// `columnBump`, so moving one moves the other.
enum TextSize {
    static func set(_ density: CGFloat, _ state: ShellState, remember: Bool = true) {
        Brand.density = density
        if remember { Remembering().set(Double(density), forKey: "tableDensity") }
        state.columnBump &+= 1
    }
}

/// **The way in from code.** SwiftUI hands `openSettings` only to views, so
/// the main window lends it here once it is drawn.
enum SettingsDoor {
    static var open: () -> Void = {}

    /// A checking run's press of a settings button (`--prefsdo`), the same
    /// action the button runs: `columns` (Shot List Columns' Edit…), `tags`
    /// (Tag Colors' Edit…), `spec` (Open Spec Sheet), `setup` (Set Up
    /// Sync…), `history` (Sync History…).
    static func press(_ name: String, _ state: ShellState) {
        switch name {
        case "size0", "size1", "size2", "size3":
            // The text size, set the way both controls set it, without
            // writing his remembered value.
            TextSize.set(Brand.comfortable[Int(name.dropFirst(4)) ?? 1], state, remember: false)
        case "columns": toMain(); state.editingColumns = true
        case "tags": project(state, list: "tags")
        case "spec": project(state, list: "aspect")
        case "gear": toMain(); state.gearOpen = true
        case "setup": toMain(); state.settingUpSync = true
        case "history": toMain(); state.showingSyncHistory = true
        default: FileHandle.standardError.write(Data("prefsdo: no \(name)\n".utf8))
        }
        FileHandle.standardError.write(Data("prefsdo: \(name)\n".utf8))
    }

    /// Main window to the front, for a sheet a settings tab asked for.
    static func toMain() {
        NSApp.windows.first { $0.identifier?.rawValue == "main" }?.makeKeyAndOrderFront(nil)
    }

    /// Project Settings, on one page.
    static func project(_ state: ShellState, list: String? = nil) {
        toMain()
        state.settingsList = list
        state.editingProject = true
    }
}

/// Names the settings window `prefs`, so `--window prefs --snapshot` can
/// photograph it like the app's other windows.
private struct SettingsWindowTag: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.identifier = NSUserInterfaceItemIdentifier("prefs") }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// The project a tab is about: its icon in its color, and its name.
private struct ProjectHead: View {
    @ObservedObject var state: ShellState

    var body: some View {
        if let project = state.view?.project {
            HStack(spacing: 6) {
                if let mark = project.mark { FilmIcon(mark: mark, size: 14) }
                Text(project.shownTitle).font(.headline).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// ------------------------------------------------------------------ General

/// What the launch does: reopen the last project (as always), or open on it
/// with the Projects browser up.
enum LaunchChoice: String, CaseIterable, Identifiable {
    case lastProject = "last", projects
    static let key = "launch.open"
    var id: String { rawValue }
    var title: String { self == .lastProject ? "Open Last Project" : "Show Projects" }
    static var current: LaunchChoice {
        LaunchChoice(rawValue: Remembering().string(forKey: key) ?? "") ?? .lastProject
    }
}

private struct GeneralTab: View {
    @ObservedObject var state: ShellState
    @ObservedObject private var clips = ClipPlay.shared
    @State private var size = Brand.density
    @State private var launch = LaunchChoice.current

    private static let sizes: [(CGFloat, String)] = zip(Brand.comfortable, ["Small", "Medium", "Large", "Extra Large"]).map { ($0, $1) }

    var body: some View {
        Form {
            Section {
            Picker("Text Size", selection: Binding(
                get: { Brand.comfortable.min { abs($0 - size) < abs($1 - size) } ?? 1 },
                set: { now in
                    size = now
                    TextSize.set(now, state)
                })) {
                ForEach(Self.sizes, id: \.0) { Text($0.1).tag($0.0) }
            }
            Picker("On Launch", selection: Binding(
                get: { launch },
                set: { launch = $0; Remembering().set($0.rawValue, forKey: LaunchChoice.key) })) {
                ForEach(LaunchChoice.allCases) { Text($0.title).tag($0) }
            }
            Divider()
            Picker("Play Clips", selection: $clips.onTheirOwn) {
                Text("Automatically").tag(true)
                Text("On Click").tag(false)
            }
            Picker("Clip Thumbnails", selection: $clips.thumbs) {
                ForEach(ClipThumbs.allCases) { Text($0.title).tag($0) }
            }
            .disabled(clips.onTheirOwn)
            } header: {
                Label("This Mac only", systemImage: "desktopcomputer")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.columns)
        .padding(20)
        // ⌘+ / ⌘− change it from the table too; follow them.
        .onChange(of: state.columnBump) { _, _ in size = Brand.density }
        .onAppear { size = Brand.density }
    }
}

// ------------------------------------------------------------------ Sync

private struct SyncTab: View {
    @ObservedObject var state: ShellState

    private var server: String {
        guard let address = Relay.address, let url = URL(string: address) else { return "Not Set Up" }
        return url.host ?? address
    }

    private var status: String {
        if !state.canSync { return "Not Set Up" }
        if state.syncing { return "Syncing…" }
        if let problem = state.syncProblem { return problem }
        if state.picturesWaiting > 0 {
            return "\(state.picturesWaiting) picture\(state.picturesWaiting == 1 ? "" : "s") not sent"
        }
        return SyncHistory.said
    }

    var body: some View {
        Form {
            Section {
            LabeledContent("Server") { Text(server).textSelection(.enabled) }
            LabeledContent("Status") {
                Text(status).foregroundStyle(state.syncProblem == nil ? Color.primary : Color.red)
                    .lineLimit(2).frame(maxWidth: 260, alignment: .leading)
                    .id(state.syncedAt ?? .distantPast)
            }
            LabeledContent("") {
                HStack(spacing: 8) {
                    Button("Sync Now") { state.syncNow() }
                        .disabled(!state.canSync || state.syncing || state.engine == nil)
                    Button("Set Up Sync…") { SettingsDoor.toMain(); state.settingUpSync = true }
                }
            }
            }
            Section {
            LabeledContent("") {
                VStack(alignment: .leading, spacing: 6) {
                    Button("Sync History…") { SettingsDoor.toMain(); state.showingSyncHistory = true }
                    Button("Copy Password for iPhone") { state.copyRelayToken() }
                        .disabled(!state.canSync)
                    Button("Copy Relay Address") { state.copyRelayAddress() }
                        .disabled(!state.canSync)
                }
            }
            }
            .padding(.top, 8)
        }
        .formStyle(.columns)
        .padding(20)
    }
}
