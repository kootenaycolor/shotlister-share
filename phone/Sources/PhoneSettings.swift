import SwiftUI

/// **One Settings screen** (2026-10-15, mockup "Two Settings screens",
/// claude.ai/artifact/35coMv5bAQBVQPZDf3rbXT). Before it there were two: this
/// iPhone's own (the gear on Projects, and App Settings in a project's sheet)
/// and Film Settings (the project sheet). Now one screen, one set of controls:
///
/// - the open project, at the top, pushing to its own page (`ProjectSettingsForm`);
/// - Sync and the Projects Folder;
/// - Lock Screen and Appearance.
///
/// A project's sheet keeps one **Project Settings** row, which opens this
/// screen already standing on that project's page (`start: .project`); Back
/// goes up to the rest of Settings.
///
/// Every control that was here before is still here, one level down:
/// Appearance, Play Clips and Clip Thumbnails under Appearance; Relay and
/// Sync History under Sync; the shortcuts and information widgets under Lock
/// Screen; the folder and its buttons under Projects Folder.
struct PhoneSettings: View {
    @EnvironmentObject private var projects: Projects
    @Environment(\.dismiss) private var dismiss
    /// Handed back to the Projects screen, which owns the folder picker.
    /// Nil inside a project: the folder is changed from the Projects list,
    /// with no project open on it.
    var chooseFolder: (() -> Void)? = nil
    var syncChanged: () -> Void = {}
    /// The open project, when Settings is opened from inside one. Nil from
    /// the Projects list, where there is no project to show.
    var session: Session? = nil
    /// Where the screen opens: the root, or straight onto the project's page.
    var start: SettingsRoute? = nil

    @State private var path = NavigationPath()
    @State private var settingUpSync = false
    @State private var history = false
    /// Redrawn after Set Up Sync closes, so the Sync row's value follows.
    @State private var relayBump = 0

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                if let session {
                    Section {
                        NavigationLink(value: SettingsRoute.project) {
                            ProjectSettingsRowLabel().environmentObject(session)
                        }
                        .accessibilityIdentifier("settings.project")
                    }
                    .listRowBackground(Style.card)
                }

                Section {
                    NavigationLink(value: SettingsRoute.sync) {
                        LabeledContent("Sync", value: relayOn ? "On" : "Not Set Up")
                    }
                    .accessibilityIdentifier("settings.sync")
                    NavigationLink(value: SettingsRoute.folder) {
                        LabeledContent("Projects Folder", value: folderSaid)
                    }
                    .accessibilityIdentifier("settings.folder")
                }
                .listRowBackground(Style.card)

                Section {
                    NavigationLink(value: SettingsRoute.lockScreen) { Text("Lock Screen") }
                        .accessibilityIdentifier("settings.lockscreen")
                    NavigationLink(value: SettingsRoute.appearance) { Text("Appearance") }
                        .accessibilityIdentifier("settings.appearance")
                }
                .listRowBackground(Style.card)
            }
            .id(relayBump)
            .scrollContentBackground(.hidden)
            .background(Style.page)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .project:
                    if let session {
                        ProjectSettingsForm(close: { dismiss() }).environmentObject(session)
                    }
                case .sync: syncPage
                case .folder: folderPage
                case .lockScreen: lockPage
                case .appearance: AppearancePage()
                }
            }
            .sheet(isPresented: $settingUpSync, onDismiss: { relayBump &+= 1 }) {
                SyncSetupView { syncChanged() }
            }
            .sheet(isPresented: $history) {
                SyncHistoryScreen()
            }
        }
        .onAppear {
            if let start, path.isEmpty, start != .project || session != nil { path.append(start) }
        }
    }

    private var relayOn: Bool { Relay.token != nil && Relay.address(for: nil) != nil }

    /// The folder in a word or two: the app's own, or the folder's name.
    private var folderSaid: String {
        guard let folder = projects.filmsFolder else { return "None" }
        if projects.watchingOwnFolder { return "Studio" }
        return folder.lastPathComponent
    }

    // ---- the pages ----------------------------------------------------------

    private var syncPage: some View {
        Form {
            Section {
                Button { settingUpSync = true } label: {
                    LabeledContent("Relay", value: relayOn ? "On" : "Not Set Up")
                }
                .foregroundStyle(Color(.label))
                Button("Sync History") { history = true }
                    .foregroundStyle(Color(.label))
            }
            .listRowBackground(Style.card)
        }
        .id(relayBump)
        .scrollContentBackground(.hidden)
        .background(Style.page)
        .navigationTitle("Sync")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var folderPage: some View {
        Form {
            Section {
                if let folder = projects.filmsFolder {
                    Text(Projects.said(folder)).foregroundStyle(Style.ink2)
                }
                if let chooseFolder {
                    Button(projects.watchingAFolder ? "Choose Another Folder" : "Choose Folder") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { chooseFolder() }
                    }
                }
                // Projects left iCloud on 2026-09-15; a phone still watching
                // that folder sees stale copies. One tap puts it right.
                if projects.filmsFolder != nil && !projects.watchingOwnFolder {
                    Button("Use Studio Folder") { projects.useOwnFolder() }
                }
            }
            .listRowBackground(Style.card)
        }
        .scrollContentBackground(.hidden)
        .background(Style.page)
        .navigationTitle("Projects Folder")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var lockPage: some View {
        Form {
            LockScreenSection()
                .listRowBackground(Style.card)
        }
        .scrollContentBackground(.hidden)
        .background(Style.page)
        .navigationTitle("Lock Screen")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The pages of Settings, as values a path can hold.
enum SettingsRoute: Hashable {
    case project, sync, folder, lockScreen, appearance
}

/// **Appearance**: how the app looks and how clips behave. All three were the
/// first group of Settings before 2026-10-15.
private struct AppearancePage: View {
    /// Which light the app draws in. His, not the phone's (2026-10-07).
    @AppStorage(Appearance.key) private var appearance = Appearance.dark.rawValue
    /// Whether a clip in a list moves by itself or waits for its play mark.
    @AppStorage(ClipPlay.key) private var automatic = ClipPlay.startingAutomatic
    @AppStorage(ClipPlay.thumbsKey) private var thumbs = ClipPlay.startingThumbs

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.name).tag($0.rawValue) }
                }
                Picker("Play Clips", selection: $automatic) {
                    Text("Automatically").tag(true)
                    Text("On Tap").tag(false)
                }
                .accessibilityIdentifier("settings.playclips")
                Picker("Clip Thumbnails", selection: $thumbs) {
                    ForEach(ClipThumbs.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .disabled(automatic)
                .accessibilityIdentifier("settings.clipthumbnails")
            }
            .listRowBackground(Style.card)
        }
        .scrollContentBackground(.hidden)
        .background(Style.page)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The project's row at the top of Settings: its icon in its color, its
/// name, and what its page holds.
private struct ProjectSettingsRowLabel: View {
    @EnvironmentObject private var session: Session

    var body: some View {
        let project = session.view?.project
        HStack(spacing: 10) {
            Group {
                if let mark = project?.mark {
                    FilmIcon(mark: mark, size: 18)
                } else {
                    Image(systemName: "film").font(.system(size: 15)).foregroundStyle(Style.ink3)
                }
            }
            .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(project?.shownTitle ?? session.entry.name)
                    .lineLimit(1)
                Text("Details, Spec Sheet, Columns, Lists")
                    .font(.system(size: 13))
                    .foregroundStyle(Style.ink3)
                    .lineLimit(1)
            }
        }
    }
}
