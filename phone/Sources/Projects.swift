import WidgetKit
import SwiftUI
import UniformTypeIdentifiers

/// Which projects this phone knows about, and how it is allowed to reach them.
///
/// A project lives in iCloud Drive — the same folder the Mac opens, not a copy.
/// iOS will not hand an app a folder just because it knows the path, so
/// something has to be picked once, and the system gives back a *bookmark* we
/// may keep. The bookmark is the permission.
///
/// **What gets picked is the folder the films live in, not each film.** Picking
/// every project by hand was one step per film forever; picking the folder is
/// one step ever, and a film started on the Mac simply appears here. Both still
/// work — pick a `.shotlist` and it is remembered on its own, pick anything
/// else and it becomes the folder to watch.
@MainActor
final class Projects: ObservableObject {
    struct Known: Identifiable, Codable, Hashable {
        var id: String { bookmarkKey }
        /// What to call it on screen — the folder's name without `.shotlist`.
        var name: String
        /// Where the permission to open it is kept. For a film found inside the
        /// watched folder there is none of its own: the folder's permission
        /// covers everything in it.
        var bookmarkKey: String
        var lastOpened: Date
        /// Whether it was found rather than picked. A found film cannot be
        /// removed from the list — it is in the folder, so it is a project.
        var discovered: Bool = false
        /// **The film's own icon**, off its manifest — so the list draws each
        /// film the way the Mac's switcher does, without opening any of them.
        /// Nothing for a film that has none, and nothing for a film picked one
        /// at a time, whose folder is only reachable behind its own bookmark.
        var mark: FilmMark? = nil
    }

    /// Films picked one at a time. Kept because a project does not have to live
    /// in the watched folder.
    @Published private(set) var known: [Known] = []

    /// Films found in the watched folder. Rebuilt, never stored.
    @Published private(set) var found: [Known] = []

    /// **The films whose pictures are in the cloud only**, by id — offloaded.
    /// Asked of each film's folder on every rescan and never stored: the
    /// folder is the truth (`Offload.inCloud`), and a film opened and synced
    /// takes its pictures back without this list being told.
    @Published private(set) var away: Set<String> = []

    /// A film whose fate arrived while it was open — archived or deleted on
    /// another device. The Projects screen follows it after the cover is
    /// down, never while an engine is open on the folder.
    var followAfterClose: (film: Known, fate: RelayCarrier.Fate)?

    /// **The film to open once this one has closed** — Switch Film on the
    /// film's own menu. Followed by the Projects screen after the cover is
    /// down, so two engines are never open at once.
    var switchTo: Known?

    /// Everything, newest first, with a found film winning over a hand-picked
    /// one of the same name — the found one stays right when he moves things.
    var all: [Known] {
        var seen = Set(found.map(\.name))
        var list = found
        for entry in known where !seen.contains(entry.name) {
            seen.insert(entry.name)
            list.append(entry)
        }
        return list.sorted { $0.lastOpened > $1.lastOpened }
    }

    private let listKey = "shotlister.projects"
    private let folderKey = "shotlister.folder"
    private let visitsKey = "shotlister.visits"
    private let pagesKey = "shotlister.consolePages"

    /// **Which film is which Projects Console project**, learnt each time a
    /// film is opened (its linked page is read out of it then, and not before).
    /// What lets a link from the console find a film whose folder is not named
    /// the way its project is. Notion page id (no dashes) to the film's name.
    private(set) var consolePages: [String: String] = [:]

    func noteConsolePage(_ page: String?, for entry: Known) {
        let key = (page ?? "").replacingOccurrences(of: "-", with: "").lowercased()
        guard !key.isEmpty, consolePages[key] != entry.name else { return }
        consolePages[key] = entry.name
        UserDefaults.standard.set(consolePages, forKey: pagesKey)
    }

    /// The watched folder, held open for as long as the app runs. iOS allows a
    /// limited number of these at once; one is well inside it, and letting it go
    /// would mean every film inside it becoming unreachable.
    private var watched: OpenFolder?
    private var watcher: DispatchSourceFileSystemObject?
    private var watchedHandle: Int32 = -1

    /// When each found film was last opened. There is nowhere else to keep it:
    /// a found film has no stored record of its own.
    private var visits: [String: Date] = [:]

    init() {
        load()
        openWatchedFolder()
        rescan()
    }

    deinit { watcher?.cancel() }

    private func load() {
        consolePages = UserDefaults.standard.dictionary(forKey: pagesKey) as? [String: String] ?? [:]
        if let data = UserDefaults.standard.data(forKey: visitsKey),
           let stored = try? JSONDecoder().decode([String: Date].self, from: data) {
            visits = stored
        }
        guard let data = UserDefaults.standard.data(forKey: listKey),
              let list = try? JSONDecoder().decode([Known].self, from: data)
        else { return }
        known = list.sorted { $0.lastOpened > $1.lastOpened }
    }

    // ---- the watched folder -------------------------------------------------

    private func openWatchedFolder() {
        guard let data = UserDefaults.standard.data(forKey: folderKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return }
        // The app's own folder needs no permission and may refuse the scope
        // call; a folder anywhere else must grant it.
        if !Projects.isOwnFolder(url), !url.startAccessingSecurityScopedResource() { return }
        if stale, let fresh = try? url.bookmarkData() {
            UserDefaults.standard.set(fresh, forKey: folderKey)
        }
        watched = OpenFolder(url: url)
        watchForNewProjects(url)
    }

    /// Look again at what is in the folder.
    ///
    /// Cheap enough to do on every appearance: one directory listing, no
    /// opening, no reading. A film that has not come down from iCloud yet still
    /// appears in the listing, so it is on the list before it is on the phone.
    func rescan() {
        guard let watched else { found = []; return }
        let kids = (try? FileManager.default.contentsOfDirectory(
            at: watched.url, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
        found = kids
            .filter { $0.pathExtension == "shotlist" }
            .map { url in
                let name = url.deletingPathExtension().lastPathComponent
                return Known(name: name, bookmarkKey: "found." + name,
                             lastOpened: visits[name] ?? .distantPast, discovered: true,
                             mark: Projects.markInPackage(at: url))
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        // What a Shortcuts action can offer, without opening the folder.
        UserDefaults.standard.set(all.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending },
                                  forKey: FilmEntity.filmsKey)
        refreshShortcutMarks()
        lookForAway()
    }

    /// A lock screen shortcut wears its film's icon; a film that got one, or
    /// a new one, since the shortcut was set is put right here.
    private func refreshShortcutMarks() {
        var changed = false
        for var shortcut in LockShortcuts.all() {
            guard let film = shortcut.film, let entry = all.first(where: { $0.name == film }) else { continue }
            guard shortcut.markPath != entry.mark?.path || shortcut.markColour != entry.mark?.colour else { continue }
            shortcut.markPath = entry.mark?.path
            shortcut.markColour = entry.mark?.colour
            LockShortcuts.save(shortcut)
            changed = true
        }
        if changed {
            WidgetCenter.shared.reloadAllTimelines()
            if #available(iOS 18, *) { ControlCenter.shared.reloadAllControls() }
        }
    }

    /// Which films are in the cloud only, from their folders. See `away`.
    func lookForAway() {
        var now: Set<String> = []
        for entry in all {
            guard let folder = resolve(entry) else { continue }
            if Offload.inCloud(folder.url) { now.insert(entry.id) }
            folder.release()
        }
        if now != away { away = now }
    }

    /// **A film's icon, out of its manifest.** One small file per film, read
    /// where the folder is already being walked — the same copy the Mac's
    /// switcher reads, and for the same reason: a row should not have to open a
    /// document to draw itself.
    ///
    /// Nothing for a film written before a film carried one, which reads exactly
    /// as a film with no icon and is what every row looked like before.
    static func markInPackage(at url: URL) -> FilmMark? {
        struct Manifest: Decodable {
            var markPath: String?
            var markColour: String?
        }
        guard let bytes = try? Data(contentsOf: url.appending(path: "manifest.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: bytes),
              let path = manifest.markPath, !path.isEmpty,
              let colour = manifest.markColour, !colour.isEmpty else { return nil }
        return FilmMark(path: path, colour: colour)
    }

    /// A film started on the Mac should appear here without being asked for.
    private func watchForNewProjects(_ folder: URL) {
        let fd = Darwin.open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchedHandle = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .attrib, .link], queue: .main)
        source.setEventHandler { [weak self] in self?.rescan() }
        source.setCancelHandler { [weak self] in
            guard let self, self.watchedHandle >= 0 else { return }
            close(self.watchedHandle)
            self.watchedHandle = -1
        }
        source.resume()
        watcher = source
    }

    private func save() {
        if let data = try? JSONEncoder().encode(known) {
            UserDefaults.standard.set(data, forKey: listKey)
        }
        if let data = try? JSONEncoder().encode(visits) {
            UserDefaults.standard.set(data, forKey: visitsKey)
        }
    }

    /// Remembers a folder he has just picked. Returns the entry so the caller can
    /// open it straight away — picking a project and then having to tap it again
    /// would be a step that exists only because the code was written that way.
    func remember(url: URL) -> Known? {
        // **What he picked decides what happens.** A film is remembered on its
        // own; anything else is the folder his films live in, and everything in
        // it — now and later — is a project.
        guard url.pathExtension == "shotlist" else {
            watchFolder(url)
            return nil
        }
        guard let bookmark = try? url.bookmarkData() else { return nil }
        let key = "bookmark." + UUID().uuidString
        UserDefaults.standard.set(bookmark, forKey: key)

        let name = url.deletingPathExtension().lastPathComponent
        // Re-picking a project already on the list should not put it there twice.
        if let existing = known.firstIndex(where: { $0.name == name }) {
            UserDefaults.standard.removeObject(forKey: known[existing].bookmarkKey)
            known.remove(at: existing)
        }
        let entry = Known(name: name, bookmarkKey: key, lastOpened: Date())
        known.insert(entry, at: 0)
        save()
        return entry
    }

    /// Start watching a folder, in place of whatever was being watched.
    func watchFolder(_ url: URL) {
        guard let bookmark = try? url.bookmarkData() else { return }
        watcher?.cancel()
        watcher = nil
        watched?.release()
        watched = nil
        UserDefaults.standard.set(bookmark, forKey: folderKey)
        openWatchedFolder()
        rescan()
    }

    /// Whether a folder is being watched at all — the one thing the screen has
    /// to say differently when it is not.
    var watchingAFolder: Bool { watched != nil }

    /// **Where a film fetched from the relay should land.**
    ///
    /// The URL only, never the `OpenFolder`: this object holds that permission
    /// for its whole life, and handing it out invites somebody to `release()`
    /// it and shut every film in the folder out at once.
    var filmsFolder: URL? { watched?.url }

    /// *On My iPhone ▸ Shotlister* — the app's own Documents folder, which is
    /// where a film belongs on a phone since films left iCloud (2026-09-15).
    static var ownFolder: URL { URL.documentsDirectory }

    static func isOwnFolder(_ url: URL) -> Bool {
        url.standardizedFileURL.path == ownFolder.standardizedFileURL.path
    }

    var watchingOwnFolder: Bool { watched.map { Projects.isOwnFolder($0.url) } ?? false }

    /// Point the list at the phone's own folder. The films come from the
    /// relay from here on, one tap each.
    func useOwnFolder() {
        try? FileManager.default.createDirectory(at: Projects.ownFolder, withIntermediateDirectories: true)
        watchFolder(Projects.ownFolder)
    }

    /// The folder as a person would name it: `On My iPhone ▸ Shotlister`, or
    /// `iCloud Drive ▸ Films`. The app's own Documents folder is what the
    /// Files app calls *On My iPhone ▸ Shotlister*.
    static func said(_ folder: URL) -> String {
        if isOwnFolder(folder) { return "On My iPhone ▸ Studio" }
        let parts = folder.pathComponents
        if let cloud = parts.firstIndex(where: { $0.hasPrefix("com~apple~CloudDocs") }) {
            let rest = parts[(cloud + 1)...]
            return (["iCloud Drive"] + rest).joined(separator: " ▸ ")
        }
        return parts.suffix(2).joined(separator: " ▸ ")
    }

    func forget(_ entry: Known) {
        // A found film is in the folder. Taking it off the list would only mean
        // putting it back on the next time anything looked.
        guard !entry.discovered else { return }
        UserDefaults.standard.removeObject(forKey: entry.bookmarkKey)
        known.removeAll { $0.bookmarkKey == entry.bookmarkKey }
        save()
    }

    func touch(_ entry: Known) {
        if entry.discovered {
            visits[entry.name] = Date()
            if let i = found.firstIndex(where: { $0.name == entry.name }) {
                found[i].lastOpened = Date()
            }
            save()
            return
        }
        guard let i = known.firstIndex(where: { $0.bookmarkKey == entry.bookmarkKey }) else { return }
        known[i].lastOpened = Date()
        known.sort { $0.lastOpened > $1.lastOpened }
        save()
    }

    // ---- keeping a film in the cloud only ------------------------------------
    //
    // His ask, 2026-09-29. What goes, what stays, and the check that comes
    // first are all in `shared/Offload.swift`, written once for both apps.

    /// How much offloading this film would free, for the question before it.
    func weight(_ entry: Known) -> Int {
        guard let folder = resolve(entry) else { return 0 }
        defer { folder.release() }
        return Offload.bytes(at: folder.url)
    }

    /// **Its pictures off this iPhone, once the relay has them all.** Returns
    /// how many bytes went.
    ///
    /// **There is no Trash to hand them to here**, which is exactly why the
    /// check is the whole of the safety: every log and every picture asked
    /// about, by name, size and fingerprint, and one short means nothing moves.
    /// The Projects list is only on screen while no film is open, so the film
    /// being offloaded is never the one a session is drawing.
    func offload(_ entry: Known, progress: @escaping @MainActor (Int, Int) -> Void) async throws -> Int {
        guard let folder = resolve(entry) else { throw Trouble.notHere(entry.name) }
        defer { folder.release() }
        let plan = try await Relay.offloadCheck(at: folder.url, progress: progress)
        let gone = try Offload.takeOff(plan, at: folder.url) { holding in
            try FileManager.default.removeItem(at: holding)
        }
        lookForAway()
        return gone
    }

    /// **The pictures, back from the relay** — the first half of opening an
    /// offloaded film, and *Download* on its own.
    func bringBack(_ entry: Known, progress: @escaping @MainActor (Int, Int) -> Void) async throws {
        guard let folder = resolve(entry) else { throw Trouble.notHere(entry.name) }
        defer { folder.release() }
        do {
            try await Relay.bringBack(at: folder.url, progress: progress)
        } catch {
            lookForAway()
            throw error
        }
        lookForAway()
    }

    // ---- putting a film away, and taking one off this phone -----------------
    //
    // **The Mac's order, exactly** (`studio/Sources/ProjectBrowser.swift`,
    // his ruling of 2026-09-04): fetch anything the relay has that this phone
    // does not, *then* take the film off the relay, *then* move the folder.
    // Any step failing leaves the film where it was, still on the list. Ref
    // 1033, 2026-09-16: until this existed the phone could not put a film
    // away at all, and its copy of one the Mac had archived quietly re-created
    // it on the relay at the next sync.

    /// The bin, beside the films — `z-archive`, his one archive name
    /// everywhere. A film in it is a level deeper than `rescan` looks, so it
    /// leaves the list without anything being told.
    static let binName = "z-archive"

    private func bin(beside film: URL) -> URL {
        film.deletingLastPathComponent().appending(path: Projects.binName)
    }

    /// Everything in the bin, newest first.
    var archived: [URL] {
        guard let watched else { return [] }
        let found = (try? FileManager.default.contentsOfDirectory(
            at: watched.url.appending(path: Projects.binName),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        return found
            .filter { $0.pathExtension == "shotlist" }
            .sorted { edited($0) > edited($1) }
    }

    private func edited(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
    }

    /// **Into the bin, off the relay.** Returns how many pictures were fetched
    /// first, so the screen can say so.
    func archive(_ entry: Known) async throws -> Int {
        guard let folder = resolve(entry) else { throw Trouble.notHere(entry.name) }
        defer { folder.release() }
        let brought = try await Relay.pullEverything(at: folder.url)
        _ = try await Relay.removeFilm(at: folder.url, fate: .archived)
        let manager = FileManager.default
        let bin = bin(beside: folder.url)
        try manager.createDirectory(at: bin, withIntermediateDirectories: true)
        try manager.moveItem(at: folder.url, to: Projects.free(folder.url.lastPathComponent, in: bin))
        forget(entry)
        rescan()
        return brought.media
    }

    /// **Out of the bin, the relay told first.** Its note that the film was
    /// taken off goes before the film's next sync, or that sync would read
    /// the note and bin the film again; then the sync sends the lot up.
    func restore(_ film: URL) async throws {
        guard let watched else { throw Trouble.notHere(film.lastPathComponent) }
        let target = Projects.free(film.lastPathComponent, in: watched.url)
        try FileManager.default.moveItem(at: film, to: target)
        await Relay.putBack(at: target)
        rescan()
    }

    /// Out of the bin because the relay holds the film again — put back on
    /// another device. Nothing to tell the relay.
    private func restoreQuietly(_ film: URL) throws {
        guard let watched else { throw Trouble.notHere(film.lastPathComponent) }
        let target = Projects.free(film.lastPathComponent, in: watched.url)
        try FileManager.default.moveItem(at: film, to: target)
        Relay.allowResend(at: target)
        rescan()
    }

    /// **Gone from this phone and from the relay.** The relay first, and its
    /// failure stops the whole thing — a film deleted here but still on the
    /// relay comes straight back at the next sync.
    func delete(_ entry: Known) async throws {
        guard let folder = resolve(entry) else { throw Trouble.notHere(entry.name) }
        defer { folder.release() }
        _ = try await Relay.removeFilm(at: folder.url, fate: .deleted)
        try FileManager.default.removeItem(at: folder.url)
        forget(entry)
        rescan()
    }

    /// The film's copy on this phone, gone, with the relay left alone — what
    /// a delete decided on another device means here.
    func removeCopy(_ entry: Known) throws {
        guard let folder = resolve(entry) else { throw Trouble.notHere(entry.name) }
        defer { folder.release() }
        try FileManager.default.removeItem(at: folder.url)
        forget(entry)
        rescan()
    }

    /// Into the bin with the relay left alone — what an archive decided on
    /// another device means here. The copy is kept whole; nothing is fetched
    /// first because the device that archived it already did that.
    func binCopy(_ entry: Known) throws {
        guard let folder = resolve(entry) else { throw Trouble.notHere(entry.name) }
        defer { folder.release() }
        let manager = FileManager.default
        let bin = bin(beside: folder.url)
        try manager.createDirectory(at: bin, withIntermediateDirectories: true)
        try manager.moveItem(at: folder.url, to: Projects.free(folder.url.lastPathComponent, in: bin))
        forget(entry)
        rescan()
    }

    /// **Do here what was done elsewhere.** His ruling 2026-09-16: one
    /// Projects list on every device, nothing done twice. Given the relay's
    /// listing, a film here that the relay says was archived goes to the
    /// bin, one it says was deleted goes, and a film in the bin that the
    /// relay holds again comes back out. Says what it did, one line each.
    ///
    @discardableResult
    func follow(listing: [Relay.Film]) async -> [String] {
        var said: [String] = []
        let held = Set(listing.filter { $0.gone == nil && $0.logs > 0 }.map(\.project))
        let fates = Dictionary(uniqueKeysWithValues: listing.compactMap { film in
            film.gone.map { (film.project, $0) }
        })

        for entry in all {
            guard let folder = resolve(entry) else { continue }
            let url = folder.url
            let onIt = Relay.wasOnTheRelay(at: url)
            let id = Relay.projectId(at: url)
            guard onIt, let id else { folder.release(); continue }
            // The relay's note first. A film the listing does not mention
            // at all — taken off before the relay kept notes — is asked
            // about one film at a time, against *its own* relay, never the
            // listing's silence: silence from a wiped or wrong relay would
            // bin every film on the device. His project, 2026-09-16.
            var fate = fates[id]
            if fate == nil, !held.contains(id) { fate = await Relay.fate(at: url) }
            folder.release()
            guard let fate else { continue }
            do {
                switch fate {
                case .archived:
                    try binCopy(entry)
                    said.append("Archived \(entry.name)")
                case .deleted:
                    try removeCopy(entry)
                    said.append("Deleted \(entry.name)")
                }
            } catch {
                said.append(error.localizedDescription)
            }
        }

        for film in archived {
            guard let id = Relay.projectId(at: film), held.contains(id) else { continue }
            do {
                try restoreQuietly(film)
                said.append("Put back \(film.deletingPathExtension().lastPathComponent)")
            } catch {
                said.append(error.localizedDescription)
            }
        }
        return said
    }

    /// The fate a sync found while the film was open, followed once it is
    /// closed. Same rules as `follow(listing:)`, for one film.
    func follow(_ entry: Known, fate: RelayCarrier.Fate) -> String {
        do {
            switch fate {
            case .archived:
                try binCopy(entry)
                return "Archived \(entry.name)"
            case .deleted:
                try removeCopy(entry)
                return "Deleted \(entry.name)"
            }
        } catch {
            return error.localizedDescription
        }
    }

    enum Trouble: LocalizedError {
        case notHere(String)
        var errorDescription: String? {
            switch self {
            case .notHere(let name): return "\(name) is not on this iPhone any more."
            }
        }
    }

    /// A name not already taken in that folder — the bin must never write
    /// over a film.
    private static func free(_ name: String, in folder: URL) -> URL {
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appending(path: name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appending(path: "\(stem) \(n).\(ext)")
            n += 1
        }
        return candidate
    }

    /// Resolves a remembered project back to a folder we may read and write.
    ///
    /// The returned handle **must** be released — the system allows only a
    /// limited number of open security-scoped folders at once, and leaking them
    /// eventually fails in a way that looks like the project vanishing.
    func resolve(_ entry: Known) -> OpenFolder? {
        if entry.discovered {
            // No permission of its own, and none needed: it sits inside a folder
            // this app is already inside. Nothing to release either, which is
            // why it is handed back unscoped — releasing it would close the
            // folder out from under every other film in it.
            guard let watched else { return nil }
            let url = watched.url.appending(path: entry.name + ".shotlist")
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return OpenFolder(url: url, scoped: false)
        }
        guard let data = UserDefaults.standard.data(forKey: entry.bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        if stale, let fresh = try? url.bookmarkData() {
            UserDefaults.standard.set(fresh, forKey: entry.bookmarkKey)
        }
        return OpenFolder(url: url)
    }
}

/// A folder we are currently allowed into. Releases the permission when it goes.
final class OpenFolder {
    let url: URL
    private var released = false
    /// Whether this handle owns the permission. A film inside the watched
    /// folder does not: the folder's permission covers it, and releasing it
    /// here would shut every other film in the folder out too.
    private let scoped: Bool

    init(url: URL, scoped: Bool = true) {
        self.url = url
        self.scoped = scoped
    }

    func release() {
        guard !released, scoped else { return }
        released = true
        url.stopAccessingSecurityScopedResource()
    }

    deinit { release() }
}

/// The system folder picker, as something SwiftUI can present.
struct FolderPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
