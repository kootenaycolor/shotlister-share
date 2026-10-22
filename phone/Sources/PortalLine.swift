import Foundation
import SwiftUI

/// **The phone's private line to the portal** — Ref 1541 Stage C, 2026-10-06.
///
/// The phone shows what the portal shows: the Library's written pages, decks,
/// look boards and documents. It reads them from the hub's phone door
/// (`phoneDoor` in `hub/src/worker.js`) and **keeps a copy on the phone**, in
/// Application Support, so they open on a set with no signal.
///
/// - **No sign-in, nothing to type.** The door takes the relay's password,
///   which this phone already holds for syncing (`Relay.token`); the hub's
///   `CONSOLE_TOKEN` is the same word (`hub/setup.sh`).
/// - **Its address comes from the relay's.** `sync.<domain>` → `mcp.<domain>`,
///   the hub's host with no browser sign-in in front of it. `PortalURL` in
///   the defaults overrides it (a checking run: `-PortalURL http://…`).
/// - **The film's id is the relay's** (`remote.json`): the portal keys a film
///   by the same 32 hex characters.
/// - **Never on the main thread.** Every fetch and every file read or written
///   happens off it; only the finished answer is handed to the screen
///   (the trap in `STATUS.md`, Ref 1538).
///
/// What is kept, per film, under `Application Support/Portal/<film>/`:
/// `library.json`, `page/<slug>.json`, `deck/<slug>.json`, `board/<slug>.json`,
/// and `pics/<name>`, every picture and file they name. Pictures are named by
/// their contents and never change, so one already kept is never fetched again.
@MainActor
final class PortalLine: ObservableObject {
    /// The Library as last read, from the portal or from the copy kept here.
    @Published private(set) var library: PortalLibrary?
    /// The film's record as last read: front page, spec sheet, People,
    /// Documents, each shoot (`GET /phone/<film>/front`, `PortalFront`).
    @Published private(set) var front: PortalFront?
    @Published private(set) var fetching = false
    /// Why the last refresh did not reach the portal, when it did not.
    @Published private(set) var trouble: String?
    /// Why the last change to the Library's shelves did not land, to say once.
    @Published var failed: String?

    private(set) var project: String?
    private var folder: URL?

    /// Opens a film's line: the copy kept on the phone at once, then the portal.
    func open(film path: URL) async {
        guard let id = Relay.projectId(at: path), id != project else { return }
        project = id
        folder = Self.home(for: id)
        let kept = await Self.read(PortalLibrary.self, at: Self.home(for: id).appending(path: "library.json"))
        let record = await Self.read(PortalFront.self, at: Self.home(for: id).appending(path: "front.json"))
        if project == id { library = kept; front = record }
        await refresh()
    }

    /// Fetches the Library and everything in it that changed, then the
    /// pictures. Safe to call again while one is running; the second waits
    /// for nothing and returns.
    func refresh() async {
        guard let project, let folder, !fetching else { return }
        guard let address = Self.address(), let token = Self.token() else {
            trouble = "Sync not set up"
            return
        }
        fetching = true
        defer { fetching = false }
        let before = library
        do {
            let fresh = try await Self.fetchAll(address: address, token: token, project: project,
                                                folder: folder, before: before)
            if self.project == project {
                library = fresh.library
                if let record = fresh.front { front = record }
                trouble = nil
            }
        } catch {
            if self.project == project { trouble = (error as? Trouble)?.said ?? error.localizedDescription }
        }
    }

    // ---- what the screens ask ----------------------------------------------

    /// An item by its key.
    func item(_ key: String) -> PortalItem? { library?.items.first { $0.key == key } }

    /// The places the record adds to a shelf: Shoots, on a film that shoots
    /// more than once (the portal's rule: one shoot is no shoots).
    func places(on shelf: Shelf) -> [Place] {
        shelf == .logistical && !(front?.shoots.isEmpty ?? true) ? [.shoots] : []
    }

    /// **The film's shelves, in its order** (2026-10-10): the portal's list,
    /// his names; the seven when the portal has not said (no signal and
    /// nothing kept, or a portal from before).
    var shelves: [Shelf] {
        if let said = library?.categories, !said.isEmpty { return said.map { Shelf(id: $0.id, name: $0.name) } }
        return Shelf.defaults
    }

    /// A shelf as the film calls it now.
    func shelf(_ id: String) -> Shelf { shelves.first { $0.id == id } ?? Shelf.named(id) }

    /// What stands on a shelf, in the portal's order; archived ones are not.
    func items(on shelf: Shelf) -> [PortalItem] {
        (library?.items ?? []).filter { !$0.archived && !$0.isFilms && $0.shelfKey == shelf.id }
    }

    // ---- the one thing the phone changes: the Library's shelves ------------

    /// **Move To** (his ask, 2026-10-10: moving an item to another category
    /// must work from the apps). Shown at once; the portal's answer and a
    /// refresh follow. Answers why not, or nil.
    func move(_ item: PortalItem, to shelf: Shelf) async -> String? {
        let was = library
        if var now = library, let at = now.items.firstIndex(where: { $0.key == item.key }) {
            now.items[at].shelfId = shelf.id
            now.items[at].shelf = shelf.name
            library = now
        }
        let why = await send("library", ["keys": [item.key], "action": "shelf", "to": shelf.id])
        if why != nil { library = was }
        return why
    }

    /// **A pinned file or link, renamed** (the portal's Rename on a document
    /// row). Its category, icon and settings stay with it. Answers why not, or nil.
    func rename(_ item: PortalItem, to name: String) async -> String? {
        await send("library", ["keys": [item.key], "action": "rename", "to": name])
    }

    /// **A category**, added, renamed, moved or removed (`editShelves` on the
    /// portal): `["action": "add", "name": …]`, `["action": "rename", "shelf":
    /// id, "name": …]`, `["action": "move", "shelf": id, "to": "up"]`,
    /// `["action": "order", "ids": […]]`, `["action": "remove", "shelf": id]`.
    func changeShelves(_ ask: [String: Any]) async -> String? {
        await send("shelves", ask)
    }

    private func send(_ what: String, _ body: [String: Any]) async -> String? {
        guard let project else { return "No project open" }
        guard let address = Self.address(), let token = Self.token() else { return "Sync not set up" }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return "Not sent" }
        do {
            let answer = try await Self.put("/phone/\(project)/\(what)", body: data, address: address, token: token)
            // The answer is the Library's state: its shelves, and each item's.
            if self.project == project, var now = library,
               let read = try? JSONDecoder().decode(ShelfAnswer.self, from: answer) {
                now.categories = read.shelves
                let moved = Dictionary((read.pages ?? []).map { ($0.at, $0.shelf) } + (read.documents ?? []).map { ("doc:" + $0.name, $0.shelf) },
                                       uniquingKeysWith: { a, _ in a })
                for at in now.items.indices {
                    if let id = moved[now.items[at].key] {
                        now.items[at].shelfId = id
                        now.items[at].shelf = read.shelves.first { $0.id == id }?.name ?? now.items[at].shelf
                    }
                }
                library = now
            }
        } catch {
            return (error as? Trouble)?.said ?? error.localizedDescription
        }
        Task { await refresh() }
        return nil
    }

    private struct ShelfAnswer: Decodable {
        struct Page: Decodable { let at: String; let shelf: String }
        struct Doc: Decodable { let name: String; let shelf: String }
        let shelves: [PortalLibrary.Category]
        let pages: [Page]?
        let documents: [Doc]?
    }

    /// The Archive: everything archived, any shelf.
    var archived: [PortalItem] { (library?.items ?? []).filter { $0.archived && !$0.isFilms } }

    /// Where a kept picture or file is, if it is kept.
    func kept(file name: String) -> URL? {
        guard let folder else { return nil }
        let url = folder.appending(path: "pics").appending(path: name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// A page's, deck's or board's answer as the door gave it, from the copy
    /// kept here. Read off the main thread.
    func kept(_ kind: String, _ slug: String) async -> Data? {
        guard let folder else { return nil }
        let url = folder.appending(path: kind).appending(path: slug + ".json")
        return await Task.detached { try? Data(contentsOf: url) }.value
    }

    /// **What a page, deck or board is made of**, for the native views: the
    /// stored JSON itself (the door wraps it with the name and the pictures it
    /// uses). The copy kept here, else asked of the portal now and kept.
    /// Nil when there is none to draw: no signal and no copy. Read and unwrapped off the
    /// main thread.
    func stored(_ kind: String, _ slug: String) async -> Data? {
        guard let folder, let project else { return nil }
        let key = ["page": "tree", "deck": "deck", "board": "board"][kind] ?? kind
        let url = folder.appending(path: kind).appending(path: slug + ".json")
        let address = Self.address(), token = Self.token()
        return await Task.detached {
            var raw = try? Data(contentsOf: url)
            if raw == nil, let address, let token,
               let got = try? await Self.get("/phone/\(project)/\(kind)/\(slug)", address: address, token: token) {
                try? Self.write(got, to: url)
                raw = got
            }
            guard let raw, let root = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
                  let inner = root[key], !(inner is NSNull),
                  JSONSerialization.isValidJSONObject(inner) else { return nil }
            return try? JSONSerialization.data(withJSONObject: inner)
        }.value
    }

    /// Fetches one picture or file now, if it is not kept: a document opened
    /// before the whole Library had come down.
    func fetch(file name: String) async -> URL? {
        await files?.file(named: name)
    }

    /// The film's kept files as a value any screen can carry off the main
    /// thread: Stage E's look pages ask it for each picture by name.
    var files: PortalFiles? {
        guard let project, let folder else { return nil }
        return PortalFiles(project: project, pics: folder.appending(path: "pics"))
    }

    /// A place's name in the bar: a portal page by the name the portal gives
    /// it, a shelf by the film's name for it.
    func title(of place: Place) -> String {
        if case .page(let key) = place, let item = item(key) { return item.name }
        if case .shelf(let one) = place { return shelf(one.id).short }
        if case .shoot(let slug) = place, let one = front?.shoots.first(where: { $0.slug == slug }) { return one.name }
        return place.title
    }

    /// A place's name in a list, where there is room.
    func libraryTitle(of place: Place) -> String {
        if case .page(let key) = place, let item = item(key) { return item.name }
        if case .shelf(let one) = place { return shelf(one.id).name }
        if case .shoot(let slug) = place, let one = front?.shoots.first(where: { $0.slug == slug }) { return one.name }
        return place.libraryTitle
    }

    func symbol(of place: Place) -> String {
        if case .page(let key) = place, let item = item(key) { return item.symbol }
        return place.symbol
    }

    /// The portal's own page for an item, for what the phone does not draw yet.
    func portalURL(for item: PortalItem) -> URL? {
        guard let base = library?.portal else { return nil }
        if item.kind == "link", let url = item.url { return URL(string: url) }
        if let file = item.file { return URL(string: base + "/pic/" + file) }
        return URL(string: base + "/" + item.key)
    }

    // ---- where, and who ----------------------------------------------------

    nonisolated static func home(for project: String) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "Portal").appending(path: project)
    }

    /// The hub's address: the override if there is one, else the relay's
    /// address with `sync.` changed to `mcp.`.
    nonisolated static func address() -> String? {
        if let set = UserDefaults.standard.string(forKey: "PortalURL"), !set.isEmpty {
            return set.hasSuffix("/") ? String(set.dropLast()) : set
        }
        guard let relay = Relay.address(for: nil) ?? UserDefaults.standard.string(forKey: "RelayURL"),
              var parts = URLComponents(string: relay.hasPrefix("http") ? relay : "https://" + relay),
              let host = parts.host
        else { return nil }
        parts.host = host.hasPrefix("sync.") ? "mcp." + host.dropFirst(5) : host
        parts.path = ""
        parts.scheme = "https"
        return parts.string
    }

    /// The relay's password, which the hub's door takes. A simulator may be
    /// handed one for a checking run (`-PortalToken`); a phone never.
    nonisolated static func token() -> String? {
        #if targetEnvironment(simulator)
        if let set = UserDefaults.standard.string(forKey: "PortalToken"), !set.isEmpty { return set }
        #endif
        return Relay.token
    }

    // ---- the fetching, all of it off the main thread -------------------------

    struct Trouble: Error { let said: String }

    nonisolated private static func get(_ path: String, address: String, token: String) async throws -> Data {
        guard let url = URL(string: address + path) else { throw Trouble(said: "Portal address not readable") }
        var asking = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        asking.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let (data, answer) = try await URLSession.shared.data(for: asking)
        let status = (answer as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw Trouble(said: "Portal refused this iPhone") }
        if status == 503 { throw Trouble(said: "Portal Not Set Up") }
        guard status == 200 else { throw Trouble(said: "Couldn't reach the portal") }
        return data
    }

    /// A change sent through the door: the portal's own reason when it says no.
    nonisolated private static func put(_ path: String, body: Data, address: String, token: String) async throws -> Data {
        guard let url = URL(string: address + path) else { throw Trouble(said: "Portal address not readable") }
        var asking = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        asking.httpMethod = "PUT"
        asking.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        asking.setValue("application/json", forHTTPHeaderField: "Content-Type")
        asking.httpBody = body
        let (data, answer) = try await URLSession.shared.data(for: asking)
        let status = (answer as? HTTPURLResponse)?.statusCode ?? 0
        if status == 200 { return data }
        let said = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["problem"] as? String
        if status == 401 { throw Trouble(said: "Portal refused this iPhone") }
        throw Trouble(said: said ?? (status == 405 ? "Update the portal" : "Couldn't reach the portal"))
    }

    nonisolated private static func read<T: Decodable>(_ type: T.Type, at url: URL) async -> T? {
        await Task.detached {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }.value
    }

    nonisolated private static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    nonisolated private static func fetchPicture(_ name: String, address: String, token: String,
                                                 project: String, into pics: URL) async throws {
        let url = pics.appending(path: name)
        if FileManager.default.fileExists(atPath: url.path) { return }
        let data = try await get("/phone/\(project)/pic/\(name)", address: address, token: token)
        try write(data, to: url)
    }

    /// The Library, then the film's record, then every page, deck and board
    /// whose time has moved, then every picture any of them names that is not
    /// kept yet.
    nonisolated private static func fetchAll(address: String, token: String, project: String,
                                             folder: URL, before: PortalLibrary?) async throws -> (library: PortalLibrary, front: PortalFront?) {
        let raw = try await get("/phone/\(project)/library", address: address, token: token)
        let library = try JSONDecoder().decode(PortalLibrary.self, from: raw)
        // **The record**: small, so asked every time. A hub from before it had
        // this door answers 404; the copy kept here stands.
        var record: PortalFront?
        if let got = try? await get("/phone/\(project)/front", address: address, token: token),
           let read = try? JSONDecoder().decode(PortalFront.self, from: got) {
            try? write(got, to: folder.appending(path: "front.json"))
            record = read
        }
        let stamps = Dictionary((before?.items ?? []).map { ($0.key, $0.stamp ?? 0) }, uniquingKeysWith: { a, _ in a })

        // What to fetch: a page with a tree, a deck, a board — skipping one
        // whose time has not moved and whose copy is here.
        var asks: [(kind: String, slug: String)] = []
        for item in library.items where !item.isFilms {
            let wanted = PortalNative<EmptyView>.kind(of: item)
            guard let kind = wanted else { continue }
            let kept = folder.appending(path: kind).appending(path: item.key + ".json")
            let same = (stamps[item.key] ?? -1) == (item.stamp ?? 0)
            if same, FileManager.default.fileExists(atPath: kept.path) { continue }
            asks.append((kind, item.key))
        }

        var pictures = Set(library.items.compactMap { $0.file })
        pictures.formUnion(library.items.compactMap { $0.pdf?.file })
        pictures.formUnion(record?.pictures ?? [])
        try await withThrowingTaskGroup(of: [String].self) { group in
            var waiting = asks[...]
            func next() {
                guard let ask = waiting.popFirst() else { return }
                group.addTask {
                    let data = try await get("/phone/\(project)/\(ask.kind)/\(ask.slug)", address: address, token: token)
                    try write(data, to: folder.appending(path: ask.kind).appending(path: ask.slug + ".json"))
                    return (try? JSONDecoder().decode(Named.self, from: data))?.pictures ?? []
                }
            }
            for _ in 0..<4 { next() }
            while let named = try await group.next() {
                pictures.formUnion(named)
                next()
            }
        }
        // Pictures the unchanged pages name, read from their kept copies.
        for item in library.items where !item.isFilms {
            for kind in ["page", "deck", "board"] {
                let kept = folder.appending(path: kind).appending(path: item.key + ".json")
                if let data = try? Data(contentsOf: kept), let named = try? JSONDecoder().decode(Named.self, from: data) {
                    pictures.formUnion(named.pictures ?? [])
                }
            }
        }

        // The Library is written once the pages it names are here, so a copy
        // read with no signal never points at a page that did not arrive.
        try write(raw, to: folder.appending(path: "library.json"))

        let pics = folder.appending(path: "pics")
        let missing = pictures.filter { !FileManager.default.fileExists(atPath: pics.appending(path: $0).path) }
        await withTaskGroup(of: Void.self) { group in
            var waiting = missing.sorted()[...]
            func next() {
                guard let name = waiting.popFirst() else { return }
                group.addTask { try? await fetchPicture(name, address: address, token: token, project: project, into: pics) }
            }
            for _ in 0..<4 { next() }
            while await group.next() != nil { next() }
        }
        return (library, record)
    }

    private struct Named: Decodable { let pictures: [String]? }
}

/// **A film's kept pictures and files, by stored name** (`<hash>.<ext>`):
/// the copy on the phone, else fetched through the door and kept. Sendable,
/// so a screen drawing a page can ask from any thread. Shaped as Stage E's
/// `LookFiles` asks (`file(named:)`).
struct PortalFiles: Sendable {
    let project: String
    let pics: URL

    func file(named name: String) async -> URL? {
        let url = pics.appending(path: name)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        guard name.range(of: #"^[0-9a-f]{32}\.[A-Za-z0-9]{1,8}$"#, options: .regularExpression) != nil,
              let address = PortalLine.address(), let token = PortalLine.token(),
              let asked = URL(string: "\(address)/phone/\(project)/pic/\(name)")
        else { return nil }
        var asking = URLRequest(url: asked, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        asking.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        guard let (data, answer) = try? await URLSession.shared.data(for: asking),
              (answer as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        try? FileManager.default.createDirectory(at: pics, withIntermediateDirectories: true)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }
}

/// The Library as the portal's phone door says it (`phoneLibraryOf` in
/// `hub/src/pages.js`).
struct PortalLibrary: Codable {
    var project: String
    var title: String?
    var portal: String
    var updated: String?
    var shelves: [String]
    /// The film's shelves with their ids (2026-10-10); a portal from before
    /// sends only `shelves`, the seven's names.
    var categories: [Category]?
    var items: [PortalItem]

    struct Category: Codable, Hashable {
        var id: String
        var name: String
        var builtIn: Bool?
    }
}

/// One page or document in the portal's Library.
struct PortalItem: Codable, Hashable, Identifiable {
    var key: String
    var name: String
    /// `built`, `page`, `deck`, `board`, `file` or `link`.
    var kind: String
    /// The shelf's name, and (2026-10-10) its id, which is what files it.
    var shelf: String
    var shelfId: String?
    var pinned: Bool
    var isPrivate: Bool
    var archived: Bool
    var icon: String?
    /// A page the phone draws from the film itself (Shot List, Script…).
    var film: Bool?
    var tree: Bool?
    var html: Bool?
    var deck: Bool?
    var stamp: Double?
    var share: String?
    var pdf: PortalFile?
    var file: String?
    var bytes: Int?
    var ext: String?
    var named: String?
    var url: String?

    var id: String { key }
    /// The shelf it stands on, by id: a Library read before ids says only the name.
    var shelfKey: String { Shelf.named(shelfId ?? shelf).id }
    var isFilms: Bool { film == true }
    var isDocument: Bool { kind == "file" || kind == "link" }

    enum CodingKeys: String, CodingKey {
        case key, name, kind, shelf, shelfId, pinned, archived, icon, film, tree, html, deck, stamp, share, pdf, file, bytes, ext, named, url
        case isPrivate = "private"
    }

    /// What it says under its name: the kind, where the kind is news.
    var kindSaid: String {
        switch kind {
        case "deck": return "Deck"
        case "board": return "Board"
        case "file": return (ext ?? "File").uppercased()
        case "link": return "Link"
        default: return "Page"
        }
    }

    /// An SF Symbol for the portal's icon names (`hub/src/icons.js`), by kind
    /// where it has none of its own.
    var symbol: String {
        let mapped: [String: String] = [
            "script": "doc.plaintext", "page": "doc.text", "file": "doc", "link": "link",
            "documents": "folder", "list": "list.bullet", "shotlist": "list.bullet.rectangle",
            "film": "film", "camera": "camera", "lens": "camera.aperture", "image": "photo",
            "boards": "square.grid.2x2", "palette": "paintpalette", "eye": "eye", "bulb": "lightbulb",
            "diagrams": "pencil.and.ruler", "locations": "mappin.and.ellipse", "schedule": "calendar",
            "clock": "clock", "people": "person.2", "user": "person", "bible": "book.closed",
            "deck": "rectangle.on.rectangle", "star": "star", "heart": "heart", "flag": "flag",
            "bookmark": "bookmark", "tag": "tag", "pencil": "pencil", "mail": "envelope", "mic": "mic",
            "music": "music.note", "car": "car", "home": "house", "sun": "sun.max", "moon": "moon",
            "bolt": "bolt", "check": "checkmark.circle",
        ]
        if let icon, let symbol = mapped[icon] { return symbol }
        switch kind {
        case "deck": return "rectangle.on.rectangle"
        case "board": return "square.grid.3x3"
        case "file": return ext == "pdf" ? "doc.richtext" : "doc"
        case "link": return "link"
        default: return "doc.text"
        }
    }
}

struct PortalFile: Codable, Hashable {
    var file: String
    var name: String?
    var bytes: Int?
}

extension PortalFiles: LookFiles {}
