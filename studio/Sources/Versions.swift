import AppKit
import SwiftUI

/// **Versions** — the film as it stood at a moment, kept so it can be looked
/// at and brought back.
///
/// His ask, 2026-09-29, on the eve of restructuring *Call Her Back*: *"I might
/// want to refer back to or pivot back to stuff that I delete and change
/// around… a snapshot in time I can go back to."* His picks, the same night:
/// look first, then bring back pieces, then the whole film; one saved on its
/// own each day he works and before a new draft; the Mac first.
///
/// Everything that decides anything is in the engine (`engine/src/versions.rs`)
/// and at its door (`ffi/src/versions.rs`). This file is the window, the
/// banner, and the few lines that carry a click across.
///
/// **Looking is safe by construction, not by care.** While an old version is
/// on screen the engine answers every *showing* command from it, runs saving
/// and syncing against today's film, and refuses every edit — including ones
/// added after this was written. Nothing here has to remember to switch
/// anything off.

// MARK: - the model

// `VersionItem` is in shared/VersionItem.swift; the iPhone reads it too.

// MARK: - the engine's door

extension Engine {
    func versions() -> (looking: String, list: [VersionItem]) {
        struct Reply: Decodable { var looking: String; var versions: [VersionItem] }
        guard let r = try? JSONDecoder().decode(Reply.self, from: call("versions")) else {
            return ("", [])
        }
        return (r.looking, r.versions)
    }

    /// The id of the version saved, or nil if the engine refused.
    func saveVersion(_ name: String, day: String) -> String? {
        struct Reply: Decodable { var saved: String }
        let r = try? JSONDecoder().decode(Reply.self, from: call("saveversion", name, day))
        return (r?.saved.isEmpty ?? true) ? nil : r?.saved
    }

    func renameVersion(_ id: String, to name: String) {
        call("renameversion", id, name)
    }

    func deleteVersion(_ id: String) {
        call("deleteversion", id)
    }

    /// The start-of-day version, if one is due.
    @discardableResult
    func dailyVersion(day: String) -> String? {
        struct Reply: Decodable { var saved: String }
        let r = try? JSONDecoder().decode(Reply.self, from: call("dailyversion", day))
        return (r?.saved.isEmpty ?? true) ? nil : r?.saved
    }

    func lookAt(_ id: String) -> ViewModel? { decode(call("lookat", id)) }

    func lookNow() -> ViewModel? { decode(call("looknow")) }

    struct Brought: Decodable { var records: Int; var fields: Int; var saved: String }

    func bringBack(from version: String, _ ids: [String]) -> (brought: Brought?, view: ViewModel?) {
        struct Reply: Decodable { var brought: Brought; var view: ViewModel }
        let data = call("bringback", version, ids.joined(separator: ","))
        guard let r = try? JSONDecoder().decode(Reply.self, from: data) else {
            FileHandle.standardError.write(Data("engine: \(String(decoding: data, as: UTF8.self))\n".utf8))
            return (nil, nil)
        }
        return (r.brought, r.view)
    }

    /// Write the version out as a new film into `folder`. Nil when it worked;
    /// otherwise what went wrong, in the engine's words.
    func copyVersion(_ version: String, into folder: URL, title: String) -> String? {
        struct Reply: Decodable { var copied: String?; var error: String? }
        let r = try? JSONDecoder().decode(Reply.self, from: call("copyversion", version, folder.path, title))
        if r?.copied != nil { return nil }
        return r?.error ?? "The copy could not be made"
    }

    func goBack(to version: String, day: String) -> (brought: Brought?, view: ViewModel?) {
        struct Reply: Decodable { var brought: Brought; var view: ViewModel }
        let data = call("goback", version, day)
        guard let r = try? JSONDecoder().decode(Reply.self, from: data) else {
            FileHandle.standardError.write(Data("engine: \(String(decoding: data, as: UTF8.self))\n".utf8))
            return (nil, nil)
        }
        return (r.brought, r.view)
    }
}

// MARK: - what a click does

extension ShellState {
    /// Today, where he is — `2026-09-29`. The engine keys the day's version
    /// on this rather than on UTC's day.
    static var dayHere: String {
        let shape = DateFormatter()
        shape.dateFormat = "yyyy-MM-dd"
        return shape.string(from: Date())
    }

    /// The start-of-day version, when a film opens. Never in a checking run
    /// unless it asks, so a battery's scratch film is not written on open.
    func saveDailyVersionIfDue() {
        guard let engine else { return }
        guard !Launch.checking || CommandLine.arguments.contains("--dailyversion") else { return }
        if let made = engine.dailyVersion(day: Self.dayHere) {
            FileHandle.standardError.write(Data("daily version: \(made)\n".utf8))
        }
    }

    /// Ask for a name, then keep the film as it stands.
    func askToSaveVersion() {
        guard engine != nil, looking == nil else { return }
        let ask = NSAlert()
        ask.messageText = "Save Version"
        ask.addButton(withTitle: "Save")
        ask.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Name"
        ask.accessoryView = field
        ask.window.initialFirstResponder = field
        guard ask.runModal() == .alertFirstButtonReturn else { return }
        saveVersion(named: field.stringValue)
    }

    func saveVersion(named name: String) {
        guard let engine, looking == nil else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard engine.saveVersion(trimmed, day: Self.dayHere) != nil else { return }
        say(trimmed.isEmpty ? "Version saved" : "Saved “\(trimmed)”")
        FileHandle.standardError.write(Data("version saved: \(trimmed)\n".utf8))
        VersionsWindow.shared.refresh()
    }

    /// Put an old version on screen instead of now.
    func look(at version: VersionItem) {
        guard let engine else { return }
        guard let seen = engine.lookAt(version.id) else { return }
        looking = version
        replace(seen)
        if sceneId == nil || view?.scenes.contains(where: { $0.id == sceneId }) != true {
            sceneId = view?.scenes.first?.id
        }
        marked = []
        wholeShots = []
        FileHandle.standardError.write(Data("looking at: \(version.title)\n".utf8))
        VersionsWindow.shared.refresh()
    }

    /// Back to the film as it stands.
    func lookNow() {
        guard let engine, looking != nil else { return }
        looking = nil
        replace(engine.lookNow())
        if sceneId == nil || view?.scenes.contains(where: { $0.id == sceneId }) != true {
            sceneId = view?.scenes.first?.id
        }
        marked = []
        wholeShots = []
        FileHandle.standardError.write(Data("looking at: now\n".utf8))
        VersionsWindow.shared.refresh()
    }

    /// **What "Bring Back" would bring**, from what is picked in the old
    /// version: ticked shots, else ticked scenes, else the scene he is on —
    /// or the board or location open in those modes. The words name it.
    var bringing: (label: String, ids: [String])? {
        guard looking != nil, let view else { return nil }
        switch sideTab {
        case .scenes:
            let picked = marked.union(wholeShots)
            if !picked.isEmpty {
                let shots = view.scenes.flatMap { rows(of: $0.id) }
                    .filter { picked.contains($0.id) }
                    .map(\.shot)
                let unique = Array(Set(shots))
                if !unique.isEmpty {
                    return (unique.count == 1 ? "Bring Back Shot" : "Bring Back \(unique.count) Shots", unique)
                }
            }
            if pickedScenes.count > 1 {
                return ("Bring Back \(pickedScenes.count) Scenes", Array(pickedScenes))
            }
            if let scene {
                let number = scene.number.isEmpty ? scene.heading : "Scene \(scene.number)"
                return ("Bring Back \(number)", [scene.id])
            }
            return nil
        case .boards:
            guard let board else { return nil }
            return ("Bring Back Board", [board.id])
        case .locations:
            guard let location else { return nil }
            return ("Bring Back Location", [location.id])
        default:
            return nil
        }
    }

    /// Bring what is picked back into now, as it was. One undo step.
    func bringBackPicked() {
        guard let engine, let version = looking, let what = bringing else { return }
        let (brought, fresh) = engine.bringBack(from: version.id, what.ids)
        guard let brought, let fresh else { return }
        looking = nil
        replace(fresh)
        marked = []
        wholeShots = []
        let thing = what.label.replacingOccurrences(of: "Bring Back ", with: "")
        say(brought.records == 0 ? "\(thing) is already as it was" : "\(thing) brought back")
        FileHandle.standardError.write(Data(
            "brought back: \(what.ids.count) picked, \(brought.records) records, \(brought.fields) fields\n".utf8))
        VersionsWindow.shared.refresh()
    }

    /// The whole film back as it was. Asks first; now is saved as a version
    /// before anything changes.
    func askToGoBack(to version: VersionItem) {
        let ask = NSAlert()
        ask.messageText = "Go Back to “\(version.title)”?"
        // The one sentence this earns: what it costs, and why it is safe.
        ask.informativeText = "Current state is saved as a version first."
        ask.addButton(withTitle: "Go Back")
        ask.addButton(withTitle: "Cancel")
        guard ask.runModal() == .alertFirstButtonReturn else { return }
        goBack(to: version)
    }

    func goBack(to version: VersionItem) {
        guard let engine else { return }
        let (brought, fresh) = engine.goBack(to: version.id, day: Self.dayHere)
        guard let brought, let fresh else { return }
        looking = nil
        replace(fresh)
        if sceneId == nil || view?.scenes.contains(where: { $0.id == sceneId }) != true {
            sceneId = view?.scenes.first?.id
        }
        marked = []
        wholeShots = []
        say("Back to “\(version.title)”")
        FileHandle.standardError.write(Data(
            "went back: \(brought.records) records, \(brought.fields) fields, now saved as \(brought.saved)\n".utf8))
        VersionsWindow.shared.refresh()
    }

    /// **A version as a new film of its own**, beside this one — an old
    /// direction to take up without giving up the current one. Asks for its
    /// name, then opens it.
    func askToCopy(_ version: VersionItem) {
        let film = projectPath?.deletingPathExtension().lastPathComponent ?? "Film"
        let ask = NSAlert()
        ask.messageText = "Duplicate as New Project"
        ask.addButton(withTitle: "Make Copy")
        ask.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = "\(film) (\(version.title))"
        field.placeholderString = "Name"
        ask.accessoryView = field
        ask.window.initialFirstResponder = field
        guard ask.runModal() == .alertFirstButtonReturn else { return }
        copy(version, named: field.stringValue)
    }

    func copy(_ version: VersionItem, named asked: String) {
        guard let engine, let here = projectPath else { return }
        let name = asked.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        guard !name.isEmpty else { return }
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
            // The pictures and the phone's scans, cloned — on this Mac's disk a
            // copy of a file costs nothing until one of the two changes. Only
            // what the version names survives the copy's first open; the rest
            // is swept as strays of the copy, never of this film.
            for part in ["media", "locations"] {
                let from = here.appending(path: part)
                if manager.fileExists(atPath: from.path) {
                    try manager.copyItem(at: from, to: target.appending(path: part))
                }
            }
        } catch {
            try? manager.removeItem(at: target)
            problem = "The copy could not be made: \(error.localizedDescription)"
            return
        }
        if let trouble = engine.copyVersion(version.id, into: target, title: target.deletingPathExtension().lastPathComponent) {
            try? manager.removeItem(at: target)
            problem = trouble
            return
        }
        FileHandle.standardError.write(Data("copied as: \(target.lastPathComponent)\n".utf8))
        VersionsWindow.shared.close()
        if open(target) {
            say("Opened “\(target.deletingPathExtension().lastPathComponent)”")
        }
    }

    func askToDelete(_ version: VersionItem) {
        let ask = NSAlert()
        ask.messageText = "Delete “\(version.title)”?"
        ask.addButton(withTitle: "Delete")
        ask.addButton(withTitle: "Cancel")
        guard ask.runModal() == .alertFirstButtonReturn else { return }
        if looking?.id == version.id { lookNow() }
        engine?.deleteVersion(version.id)
        VersionsWindow.shared.refresh()
    }

    func askToRename(_ version: VersionItem) {
        let ask = NSAlert()
        ask.messageText = "Rename Version"
        ask.addButton(withTitle: "Rename")
        ask.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = version.name
        field.placeholderString = "Name"
        ask.accessoryView = field
        ask.window.initialFirstResponder = field
        guard ask.runModal() == .alertFirstButtonReturn else { return }
        engine?.renameVersion(version.id, to: field.stringValue)
        VersionsWindow.shared.refresh()
    }
}

// MARK: - the banner

/// **Across the top while an old version is on screen.** Says which one,
/// and holds the three things to do about it.
struct LookingBanner: View {
    @ObservedObject var state: ShellState
    let version: VersionItem

    var body: some View {
        HStack(spacing: 10) {
            Text("Viewing").sans(13).opacity(0.8)
            Text(version.title).sans(13, weight: .semibold).lineLimit(1)
            Text(version.when).sans(13).opacity(0.8).lineLimit(1)
            Text("Read Only").mono(8, weight: .semibold, tracking: 1)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: Brand.radiusSmall, style: .continuous)
                    .fill(Color.white.opacity(0.18)))
            Spacer(minLength: 12)
            if let what = state.bringing {
                Button(what.label) { state.bringBackPicked() }
                    .buttonStyle(BannerButton())
            }
            Button("Go Back to This Version…") { state.askToGoBack(to: version) }
                .buttonStyle(BannerButton())
            Button("Make a Copy…") { state.askToCopy(version) }
                .buttonStyle(BannerButton())
            Button("Back to Now") { state.lookNow() }
                .buttonStyle(BannerButton(filled: true))
                .keyboardShortcut(.cancelAction)
        }
        .foregroundStyle(Brand.onImage)
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(Brand.hex("9A6B10"))
    }
}

/// A button on the banner's own colour: a hairline capsule, or filled white.
private struct BannerButton: ButtonStyle {
    var filled = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .sans(13, weight: .semibold)
            .foregroundStyle(filled ? Brand.hex("9A6B10") : Brand.onImage)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Capsule(style: .continuous).fill(filled ? Color.white : Color.clear))
            .overlay {
                if !filled {
                    Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule(style: .continuous))
    }
}

// MARK: - the window

/// **The list of versions, in a window of its own** — beside the film, so
/// clicking down the list shows each one in turn. A real window with an
/// identifier, so a checking run can photograph it (Ref 366).
final class VersionsWindow: NSObject, NSWindowDelegate {
    static let shared = VersionsWindow()

    private var window: NSWindow?
    private var hosting: NSHostingView<VersionsList>?
    private weak var state: ShellState?
    /// Bumped to make the list read the engine again.
    private let reading = VersionsReading()

    func show(state: ShellState) {
        self.state = state
        reading.read(state)
        if hosting == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 560),
                styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 340, height: 320)
            w.delegate = self
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.identifier = NSUserInterfaceItemIdentifier("versions")
            let host = NSHostingView(rootView: VersionsList(state: state, reading: reading))
            w.contentView = host
            hosting = host
            // Where he last left it; the first time, over the film's right
            // edge, below the top bar and the banner — where the side panel
            // sits, and out of the way of the list he is reading.
            let remembered = !Launch.checking && w.setFrameUsingName("versionsWindow")
            if !Launch.checking { w.setFrameAutosaveName("versionsWindow") }
            window = w
            place(w, remembered: remembered)
        }
        window?.makeKeyAndOrderFront(nil)
    }

    /// Ride above the film's window and follow it; the first time, sit over
    /// its right edge. A checking run opens this before the film's window is
    /// on screen, so it waits a beat for it rather than landing in a corner.
    private func place(_ w: NSWindow, remembered: Bool, tries: Int = 10) {
        let main = NSApp.windows.first {
            $0 != w && $0.isVisible && $0.identifier?.rawValue.hasPrefix("main") == true
        } ?? NSApp.windows.first {
            $0 != w && $0.isVisible && $0.frame.width > 800 && $0.parent == nil
        }
        guard let main else {
            if tries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak w] in
                    guard let w else { return }
                    self?.place(w, remembered: remembered, tries: tries - 1)
                }
            }
            return
        }
        main.addChildWindow(w, ordered: .above)
        if !remembered {
            let m = main.frame
            w.setFrameTopLeftPoint(NSPoint(x: m.maxX - w.frame.width - 16, y: m.maxY - 104))
        }
        if Launch.checking {
            FileHandle.standardError.write(Data((
                "versions window: \(w.frame) main \(main.frame)\n").utf8))
        }
    }

    func close() {
        window?.close()
    }

    /// Read the list again — after a save, a rename, a look.
    func refresh() {
        guard let state, window != nil else { return }
        reading.read(state)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        hosting = nil
    }
}

/// What the list shows, read from the engine when asked rather than kept.
final class VersionsReading: ObservableObject {
    @Published var list: [VersionItem] = []

    func read(_ state: ShellState) {
        list = state.engine?.versions().list ?? []
    }
}

struct VersionsList: View {
    @ObservedObject var state: ShellState
    @ObservedObject var reading: VersionsReading
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Versions").sans(Brand.Size.large, weight: .semibold)
                    .foregroundStyle(Brand.ink(dark))
                Spacer(minLength: 0)
                Button("Save Version…") { state.askToSaveVersion() }
                    .buttonStyle(.capsule)
                    .disabled(state.looking != nil)
            }
            .padding(.horizontal, 18)
            .padding(.top, 34)
            .padding(.bottom, 12)

            Divider().overlay(Brand.rule(dark))

            if reading.list.isEmpty {
                EmptyState(title: "No versions yet")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        nowRow
                        ForEach(reading.list) { v in row(v) }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .background(Brand.surface(dark))
        .frame(minWidth: 340, minHeight: 320)
    }

    /// Now, at the top — the way back, and what is being compared against.
    private var nowRow: some View {
        let on = state.looking == nil
        return Button { state.lookNow() } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Now").sans(13, weight: .semibold).foregroundStyle(Brand.ink(dark))
                Text(state.view?.project.shownTitle ?? "").sans(11).foregroundStyle(Brand.ink3(dark))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
                .fill(on ? Brand.accentTint(dark) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private func row(_ v: VersionItem) -> some View {
        let on = state.looking?.id == v.id
        return Button { state.look(at: v) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(v.title).sans(13, weight: .semibold).foregroundStyle(Brand.ink(dark))
                    .lineLimit(1)
                Text(v.subtitle).sans(11).foregroundStyle(Brand.ink3(dark))
                Text(v.sinceSaid).sans(11).foregroundStyle(Brand.ink2(dark))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
                .fill(on ? Brand.accentTint(dark) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .contextMenu {
            Button("Look") { state.look(at: v) }
            Button("Go Back to This Version…") { state.askToGoBack(to: v) }
            Button("Duplicate as New Project…") { state.askToCopy(v) }
            Divider()
            Button("Rename…") { state.askToRename(v) }
            Button("Delete…") { state.askToDelete(v) }
        }
    }
}
