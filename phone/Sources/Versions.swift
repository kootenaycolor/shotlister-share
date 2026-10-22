import SwiftUI

/// **Versions on the iPhone** — the Mac's (`studio/Sources/Versions.swift`),
/// his list of 2026-10-09: the film as it stood at a moment, to save, name,
/// look at, bring pieces back from, or go back to whole. Everything that
/// decides anything is in the engine; this is the list and the banner.
///
/// **Duplicate as New Project** (the Mac's): the version as a project of
/// its own beside this one, opened.
struct VersionsView: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    /// Looking at a version, or going back to one, leaves the film's menu
    /// altogether, so the shot list and its banner are what is seen.
    var leave: () -> Void = {}
    /// The copy made, to open once this project has closed.
    var open: (Projects.Known) -> Void = { _ in }
    @EnvironmentObject private var projects: Projects
    @State private var copying: VersionItem?
    @State private var copyName = ""
    @State private var trouble: String?

    @State private var list: [VersionItem] = []
    @State private var saving = false
    @State private var name = ""
    @State private var renaming: VersionItem?
    @State private var renamed = ""
    @State private var deleting: VersionItem?
    @State private var goingBack: VersionItem?

    var body: some View {
        NavigationStack {
            List {
                if list.isEmpty {
                    Text("No versions yet").foregroundStyle(.secondary)
                }
                ForEach(list) { version in
                    Button {
                        session.look(at: version)
                        leave()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(version.title).font(.kitRow.weight(.semibold)).foregroundStyle(Color(.label))
                                if session.looking?.id == version.id {
                                    Text("Viewing").font(.kitLabel.weight(.semibold)).foregroundStyle(.tint)
                                }
                            }
                            Text(version.subtitle).font(.footnote).foregroundStyle(.secondary)
                            Text(version.sinceSaid).font(.footnote).foregroundStyle(Style.ink3)
                        }
                        .padding(.vertical, 2)
                    }
                    .accessibilityIdentifier("version.\(version.title)")
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { deleting = version } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button { renamed = version.name; renaming = version } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.indigo)
                    }
                    .contextMenu {
                        Button { session.look(at: version); leave() } label: {
                            Label("Look", systemImage: "eye")
                        }
                        Button { goingBack = version } label: {
                            Label("Go Back to This Version…", systemImage: "clock.arrow.circlepath")
                        }
                        Button { renamed = version.name; renaming = version } label: {
                            Label("Rename…", systemImage: "pencil")
                        }
                        Button {
                            copyName = "\(session.folder.url.deletingPathExtension().lastPathComponent) (\(version.title))"
                            copying = version
                        } label: {
                            Label("Duplicate as New Project…", systemImage: "plus.square.on.square")
                        }
                        Button(role: .destructive) { deleting = version } label: {
                            Label("Delete…", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Versions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save Version") { name = ""; saving = true }
                        .disabled(session.looking != nil || session.isReadOnly)
                }
            }
            .alert("Duplicate as New Project", isPresented: Binding(get: { copying != nil }, set: { if !$0 { copying = nil } })) {
                TextField("Name", text: $copyName)
                Button("Cancel", role: .cancel) { copying = nil }
                Button("Make Copy") { if let v = copying { copy(v) }; copying = nil }
            }
            .alert(trouble ?? "", isPresented: Binding(get: { trouble != nil }, set: { if !$0 { trouble = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .alert("Save Version", isPresented: $saving) {
                TextField("Name", text: $name)
                Button("Cancel", role: .cancel) {}
                Button("Save") { session.saveVersion(named: name); reload() }
            }
            .alert("Rename Version", isPresented: Binding(get: { renaming != nil },
                                                          set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $renamed)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Rename") {
                    if let version = renaming { session.renameVersion(version, to: renamed) }
                    renaming = nil
                    reload()
                }
            }
            .confirmationDialog("Delete “\(deleting?.title ?? "")”?",
                                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let version = deleting { session.deleteVersion(version) }
                    deleting = nil
                    reload()
                }
                Button("Cancel", role: .cancel) { deleting = nil }
            }
            .confirmationDialog("Go Back to “\(goingBack?.title ?? "")”?",
                                isPresented: Binding(get: { goingBack != nil }, set: { if !$0 { goingBack = nil } }),
                                titleVisibility: .visible) {
                Button("Go Back") {
                    if let version = goingBack { session.goBack(to: version) }
                    goingBack = nil
                    leave()
                }
                Button("Cancel", role: .cancel) { goingBack = nil }
            } message: {
                // The one sentence this earns: what it costs, and why it is safe.
                Text("Current state is saved first")
            }
            .onAppear(perform: reload)
        }
    }

    /// The version as a new project beside this one: its pictures and scans
    /// copied, then the engine writes the version into it; then it opens.
    private func copy(_ version: VersionItem) {
        guard let engine = session.engine else { return }
        let name = copyName.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !name.isEmpty else { return }
        let here = session.folder.url
        let manager = FileManager.default
        let films = here.deletingLastPathComponent()
        var target = films.appending(path: "\(name).shotlist")
        var n = 2
        while manager.fileExists(atPath: target.path) {
            target = films.appending(path: "\(name) \(n).shotlist")
            n += 1
        }
        do {
            try manager.createDirectory(at: target, withIntermediateDirectories: true)
            for part in ["media", "locations"] {
                let from = here.appending(path: part)
                if manager.fileExists(atPath: from.path) { try manager.copyItem(at: from, to: target.appending(path: part)) }
            }
        } catch {
            try? manager.removeItem(at: target)
            trouble = "The copy could not be made."
            return
        }
        let title = target.deletingPathExtension().lastPathComponent
        let reply = engine.raw("copyversion", version.id, target.path, title)
        if let problem = Session.refusal(in: reply) {
            try? manager.removeItem(at: target)
            trouble = problem
            return
        }
        projects.rescan()
        if let made = projects.all.first(where: { $0.name == title }) { open(made) } else { trouble = "Made “\(title)”" }
    }

    private func reload() { list = session.versions() }
}

/// **Over the shot list while an old version is on screen**: which one, Read
/// Only, and what to do about it — bring a scene back, go back whole, or
/// return to now. A shot is brought back from its own menu (hold it).
struct LookingBanner: View {
    @EnvironmentObject private var session: Session
    let version: VersionItem
    @State private var goingBack = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Viewing · Read Only").font(.system(size: 11, weight: .semibold)).opacity(0.85)
                Text(version.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            }
            Spacer(minLength: 6)
            Menu {
                Menu {
                    ForEach(session.shownScenes) { scene in
                        Button(sceneName(scene)) { session.bringBack([scene.id]) }
                    }
                } label: {
                    Label("Bring Back Scene", systemImage: "arrow.uturn.backward")
                }
                // **Boards and places too** (the Mac brings back whatever
                // its screen shows).
                if !session.boards.isEmpty {
                    Menu {
                        ForEach(session.boards) { board in
                            Button(board.shown) { session.bringBack([board.id]) }
                        }
                    } label: { Label("Bring Back Board", systemImage: "square.grid.2x2") }
                }
                if !session.locations.isEmpty {
                    Menu {
                        ForEach(session.locations) { place in
                            Button(place.name) { session.bringBack([place.id]) }
                        }
                    } label: { Label("Bring Back Location", systemImage: "mappin.and.ellipse") }
                }
                Button { goingBack = true } label: {
                    Label("Go Back to This Version…", systemImage: "clock.arrow.circlepath")
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 20))
            }
            .accessibilityLabel("Version")
            Button("Back to Now") { session.lookNow() }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(.white, in: Capsule())
                .foregroundStyle(Color.accentColor)
                .accessibilityIdentifier("version.now")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.accentColor)
        .confirmationDialog("Go Back to “\(version.title)”?", isPresented: $goingBack, titleVisibility: .visible) {
            Button("Go Back") { session.goBack(to: version) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Current state is saved first")
        }
    }

    private func sceneName(_ scene: Engine.Scene) -> String {
        let name = session.isCommercial && !scene.title.isEmpty ? scene.title : scene.heading
        return name.isEmpty ? scene.number : "\(scene.number) · \(name)"
    }
}
