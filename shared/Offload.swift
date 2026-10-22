import Foundation
import CryptoKit

/// **A film kept in the cloud only.** His ask, 2026-09-29: *"add ability to
/// keep a project saved locally, or keep it in the cloud and offload the local
/// files (mac and iphone)"*. Written once for both apps, the way the carrier
/// is — `studio/build.sh` and `phone/project.yml` both pick `shared/` up.
///
/// ## What goes, and what stays
///
/// **The pictures and clips go** — `media/proxies`, which is what a film
/// weighs. Measured on his own films the day this was built: Call Her Back is
/// 296 MB and 290 MB of it is there; Harbour Light Affair 122 MB and 121 MB.
///
/// **The list stays** — the change logs, the manifest, the link to its relay,
/// and everything that never travels (`media/originals`, `locations/`). About
/// two megabytes. So an offloaded film:
///
/// - is still on the Projects list, with its own icon, on both apps;
/// - is still in the 1pm backup, which copies the logs and never the pictures;
/// - still opens with no signal — only the pictures wait, and the app's own
///   sync fetches them the moment it can, because the film still names them.
///
/// It is exactly the state a film fetched from the relay is in before its
/// first sync (`RelayCarrier.clone`: *"The list only"*), which is a state both
/// apps have handled since 2026-09-15.
///
/// **Taking the whole folder was the other choice, and it would destroy.**
/// `media/originals` and `locations/` never travel ("Only logs and
/// `media/proxies` travel", STATUS), so a film removed whole would lose them
/// with nothing anywhere to bring them back from — Call Her Back holds 4 MB of
/// exactly that. Keeping them costs nothing worth freeing.
///
/// ## Never destroy
///
/// **Nothing leaves this device until the relay has been asked, file by file,
/// and has answered.** Not assumed, not remembered from the last sync:
///
/// - every change log and device mark here is on the relay, at least as long
///   (a log only ever grows, so the same name and length is the same bytes —
///   the relay's own rule, `state` in `relay/src/worker.js`);
/// - every picture and clip here is on the relay under the same name and the
///   same size;
/// - and the same bytes: the relay hands back each file's ETag, which R2 makes
///   the MD5 of what it stores, and that is compared with the MD5 of the file
///   here. A fingerprint the relay does not give (a multipart upload's) leaves
///   the name and size, which for a file named after its own hash is still
///   the file.
///
/// One file short, or one answer that cannot be read, and **nothing moves** —
/// *Not everything has reached the cloud yet.* A picture only ever sent from
/// this device, a log a sync has not carried, a film nobody has synced: all
/// refused, never guessed at.
///
/// **Only the checked files go.** The Drive bridge writes into films every
/// fifteen seconds; a picture that lands between the check and the move is not
/// on the list and stays where it is.
///
/// **And they go somewhere a person can reach.** The Mac puts them in the
/// Trash, one folder per offload; the phone has no Trash of its own to offer,
/// which is why the check comes before and not after.
enum Offload {
    /// The note a film keeps of what it sent to the cloud, beside its manifest.
    ///
    /// **Never travels.** Only `changes/` and `media/proxies` go to the relay;
    /// this is a fact about this device's copy, not about the film.
    static let markerFile = "offloaded.json"

    struct File: Codable, Hashable {
        var name: String
        var size: Int
    }

    /// What was taken off, when, and by which device.
    struct Marker: Codable {
        var when: String
        var by: String
        var files: [File]
    }

    /// What the check found safe to take off: every picture and clip here.
    struct Plan {
        var files: [File]
        var bytes: Int
    }

    /// Why a film stays whole. One line each — see *How the app talks*.
    enum Refusal: LocalizedError {
        /// The relay is missing something this device holds, or holds less of
        /// it. The ordinary reason: a sync has not carried it yet.
        case behind
        /// The relay has a file under the same name that is not the same file.
        /// Never expected; worth a person's look rather than a guess.
        case differs(String)
        /// Nothing here to take off.
        case nothing
        case unreadable

        var errorDescription: String? {
            switch self {
            case .behind: return "Not everything has reached the cloud yet."
            case .differs: return "A picture in the cloud does not match this one."
            case .nothing: return "No pictures here to offload."
            case .unreadable: return "The relay's answer could not be read."
            }
        }
    }

    // ---- what this device holds ---------------------------------------------

    /// Every picture and clip in the film, as the sync names them: the hash's
    /// first 32 characters and an extension (`relay/layout.json`, `medium`).
    /// Anything else in the folder never travels and is never touched here.
    static func pictures(at path: URL) -> [File] {
        let proxies = path.appending(path: RelayCarrier.proxiesDir)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: proxies.path)) ?? []
        return names.filter(isMedium).sorted().compactMap { name in
            guard let size = size(of: proxies.appending(path: name)) else { return nil }
            return File(name: name, size: size)
        }
    }

    /// How much offloading would free, for the question asked before it.
    static func bytes(at path: URL) -> Int {
        pictures(at: path).reduce(0) { $0 + $1.size }
    }

    /// Every change log and device mark — what the sync carries out of
    /// `changes/`. A fold record stays on the device that wrote it.
    static func logs(at path: URL) -> [File] {
        let changes = path.appending(path: RelayCarrier.changesDir)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: changes.path)) ?? []
        return names.filter(isLog).sorted().compactMap { name in
            guard let size = size(of: changes.appending(path: name)) else { return nil }
            return File(name: name, size: size)
        }
    }

    // ---- whether a film is in the cloud -------------------------------------

    static func marker(at path: URL) -> Marker? {
        guard let data = try? Data(contentsOf: path.appending(path: markerFile)) else { return nil }
        return try? JSONDecoder().decode(Marker.self, from: data)
    }

    /// The files the note names that are not back yet.
    static func missing(at path: URL) -> [File] {
        guard let marker = marker(at: path) else { return [] }
        let proxies = path.appending(path: RelayCarrier.proxiesDir)
        return marker.files.filter {
            !FileManager.default.fileExists(atPath: proxies.appending(path: $0.name).path)
        }
    }

    /// **Whether this film's pictures are in the cloud and not here.**
    ///
    /// Asked of the disk every time, never remembered: a film opened by any
    /// door — Open Recent, a double-click in Finder, the phone's sync — takes
    /// its pictures back through the app's own sync, and a note that outlived
    /// them would draw a film as *In the Cloud* that is not. So a note whose
    /// files are all back is let go on the spot.
    static func inCloud(_ path: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: path.appending(path: markerFile).path) else {
            return false
        }
        if missing(at: path).isEmpty {
            forget(at: path)
            return false
        }
        return true
    }

    /// The note, gone. Keeps the folder's date: letting go of a note is not
    /// an edit, and the Projects list sorts and says *Edited* by that date.
    static func forget(at path: URL) {
        keepingTheDate(of: path) {
            try? FileManager.default.removeItem(at: path.appending(path: markerFile))
        }
    }

    // ---- asking the relay ---------------------------------------------------

    /// **Everything here, checked against the relay.** Returns what may go;
    /// throws, with one line, when anything may not.
    ///
    /// Reads and writes nothing on the relay and nothing here. `progress` is
    /// told how many pictures have been compared, out of how many.
    static func check(at path: URL,
                      progress: @escaping @MainActor (Int, Int) -> Void = { _, _ in }) async throws -> Plan {
        let here = pictures(at: path)
        guard !here.isEmpty else { throw Refusal.nothing }
        // A film with no identity has never been on any relay.
        guard let (root, word) = try whereOnTheRelay(path) else { throw Refusal.behind }

        // **The film is still the relay's** — archived or deleted elsewhere,
        // it is the app's `follow` that decides what happens here, not this.
        let state = try await RelayCarrier.text(at: "\(root)/state", word)
        if let fate = RelayCarrier.fateSaid(in: state) { throw RelayCarrier.Trouble.gone(fate) }
        if RelayCarrier.letGo(state: state, at: path) { throw RelayCarrier.Trouble.gone(nil) }
        let listing = try await RelayCarrier.text(at: "\(root)/media", word)
        // An answer that cannot be read is a refusal, never an empty relay.
        guard let logsThere = sizes(in: state, key: "logs"),
              let mediaThere = sizes(in: listing, key: "media") else { throw Refusal.unreadable }

        // **Every change.** A log only grows, so the relay's copy holding at
        // least this many bytes under the name is the relay holding these.
        for log in logs(at: path) {
            guard let there = logsThere[log.name], there >= log.size else { throw Refusal.behind }
        }
        // **Every picture, by name and size** — the relay's own listing.
        for file in here {
            guard let there = mediaThere[file.name] else { throw Refusal.behind }
            guard there == file.size else { throw Refusal.differs(file.name) }
        }

        // **And by content.** Six at a time, like a clone: a film is a few
        // hundred pictures and each is its own small request.
        let proxies = path.appending(path: RelayCarrier.proxiesDir)
        var done = 0
        await progress(0, here.count)
        var queue = here[...]
        while !queue.isEmpty {
            let batch = queue.prefix(6)
            queue = queue.dropFirst(6)
            try await withThrowingTaskGroup(of: Void.self) { group in
                for file in batch {
                    group.addTask {
                        guard let theirs = try await fingerprint(of: "\(root)/media/\(file.name)", word) else {
                            return
                        }
                        guard let ours = md5(of: proxies.appending(path: file.name)) else {
                            throw Refusal.differs(file.name)
                        }
                        if ours != theirs { throw Refusal.differs(file.name) }
                    }
                }
                try await group.waitForAll()
            }
            done += batch.count
            await progress(done, here.count)
        }
        return Plan(files: here, bytes: here.reduce(0) { $0 + $1.size })
    }

    // ---- taking them off ----------------------------------------------------

    /// **The checked files, off this device.** Returns how many bytes went.
    ///
    /// The order is the safety:
    ///
    /// 1. **The note first**, so whatever happens next the film knows what it
    ///    is missing and where to fetch it from.
    /// 2. The files into one folder beside them — a rename on one volume, so
    ///    nothing is half-copied. **Only a file still the size it was checked
    ///    at**; a name is a hash, so anything else is not the file that was
    ///    checked, and it stays.
    /// 3. That folder handed to `putAway` — the Trash on the Mac.
    ///
    /// **Any step failing puts everything back** and the note with it, so a
    /// failed offload leaves the film exactly as it was.
    @discardableResult
    static func takeOff(_ plan: Plan, at path: URL, putAway: (URL) throws -> Void) throws -> Int {
        let manager = FileManager.default
        let proxies = path.appending(path: RelayCarrier.proxiesDir)
        let before = marker(at: path)

        var note = before ?? Marker(when: "", by: RelayCarrier.device.name, files: [])
        let known = Set(note.files.map(\.name))
        note.files += plan.files.filter { !known.contains($0.name) }
        note.when = ISO8601DateFormatter().string(from: Date())
        note.by = RelayCarrier.device.name
        try write(note, at: path)

        let holding = holdingFolder(for: path)
        var moved: [File] = []
        do {
            try manager.createDirectory(at: holding, withIntermediateDirectories: true)
            for file in plan.files {
                let from = proxies.appending(path: file.name)
                guard size(of: from) == file.size else { continue }
                try manager.moveItem(at: from, to: holding.appending(path: file.name))
                moved.append(file)
            }
            try putAway(holding)
        } catch {
            // Everything back where it was, then the note as it was.
            for file in moved {
                try? manager.moveItem(at: holding.appending(path: file.name),
                                      to: proxies.appending(path: file.name))
            }
            if ((try? manager.contentsOfDirectory(atPath: holding.path)) ?? []).isEmpty {
                try? manager.removeItem(at: holding)
            }
            if let before { try? write(before, at: path) } else { forget(at: path) }
            throw error
        }
        return moved.reduce(0) { $0 + $1.size }
    }

    /// Where the files wait on their way out: inside the film's own `media`,
    /// named so the folder in the Trash says where it came from.
    static func holdingFolder(for path: URL) -> URL {
        path.appending(path: "media")
            .appending(path: "\(path.deletingPathExtension().lastPathComponent) — Offloaded")
    }

    // ---- bringing them back -------------------------------------------------

    /// **The pictures, back from the relay.** What opening an offloaded film
    /// does first, and what *Download* does on its own.
    ///
    /// Fetches exactly what the note names and is missing — never the rest of
    /// what the relay holds, which may include files the film let go of.
    /// A name the relay no longer holds was tidied off it by the engine's own
    /// judgement (`RelayCarrier.tidy`, a week after the film stopped naming
    /// it), so it is not fetched and not waited for. The note goes when
    /// everything is back; an interruption leaves it naming what is still
    /// missing, and the next try picks up there.
    ///
    /// Returns how many came down and how many the relay had let go of.
    @discardableResult
    static func bringBack(at path: URL,
                          progress: @escaping @MainActor (Int, Int) -> Void = { _, _ in })
        async throws -> (brought: Int, letGo: Int) {
        let proxies = path.appending(path: RelayCarrier.proxiesDir)
        let manager = FileManager.default
        try? manager.createDirectory(at: proxies, withIntermediateDirectories: true)

        // **An offload interrupted before the Trash** left its files in the
        // holding folder. They come back from there, not over the network.
        let holding = holdingFolder(for: path)
        for file in missing(at: path) {
            let left = holding.appending(path: file.name)
            if manager.fileExists(atPath: left.path) {
                try? manager.moveItem(at: left, to: proxies.appending(path: file.name))
            }
        }
        if ((try? manager.contentsOfDirectory(atPath: holding.path)) ?? ["?"]).isEmpty {
            try? manager.removeItem(at: holding)
        }

        let wanted = missing(at: path)
        guard !wanted.isEmpty else {
            forget(at: path)
            return (0, 0)
        }
        guard let (root, word) = try whereOnTheRelay(path) else { throw Refusal.behind }

        // **Taken off elsewhere is not "tidied".** An archived film holds
        // nothing on the relay, and reading that as every picture having been
        // let go would drop the note on a film whose pictures are on another
        // device. The app's `follow` is what handles a fate.
        let state = try await RelayCarrier.text(at: "\(root)/state", word)
        if let fate = RelayCarrier.fateSaid(in: state) { throw RelayCarrier.Trouble.gone(fate) }
        if RelayCarrier.letGo(state: state, at: path) { throw RelayCarrier.Trouble.gone(nil) }
        let listing = try await RelayCarrier.text(at: "\(root)/media", word)
        guard let there = sizes(in: listing, key: "media") else { throw Refusal.unreadable }

        let fetching = wanted.filter { there[$0.name] != nil }
        var done = 0
        await progress(0, fetching.count)
        var queue = fetching[...]
        while !queue.isEmpty {
            let batch = queue.prefix(6)
            queue = queue.dropFirst(6)
            try await withThrowingTaskGroup(of: Void.self) { group in
                for file in batch {
                    group.addTask {
                        let body = try await RelayCarrier.data(at: "\(root)/media/\(file.name)", word)
                        // Written whole and swapped into place, the rule every
                        // other fetch follows.
                        try body.write(to: proxies.appending(path: file.name), options: .atomic)
                    }
                }
                try await group.waitForAll()
            }
            done += batch.count
            await progress(done, fetching.count)
        }
        forget(at: path)
        return (fetching.count, wanted.count - fetching.count)
    }

    // ---- the plumbing -------------------------------------------------------

    /// Where the film lives on the relay — or nil when it has no identity,
    /// which means it has never been there. Never makes one: checking a film
    /// must not be the thing that signs it up.
    private static func whereOnTheRelay(_ path: URL) throws -> (root: String, word: String)? {
        guard let id = RelayCarrier.projectId(at: path) else { return nil }
        let device = RelayCarrier.device
        guard let base = device.address(path), let word = device.token() else {
            throw RelayCarrier.Trouble.notSetUp
        }
        return ("\(base)/v1/p/\(id)", word)
    }

    /// **The relay's fingerprint of one file** — its ETag, which R2 makes the
    /// MD5 of the bytes it holds. Asked with a one-byte range, and the answer
    /// let go as soon as its headers arrive: only the header is wanted, and a
    /// relay that ignores the range must not cost a second download.
    ///
    /// Nil when the tag is not an MD5 (a multipart upload's is not); the name
    /// and size have already been checked by then.
    private static func fingerprint(of url: String, _ word: String) async throws -> String? {
        guard var ask = RelayCarrier.request(url, word) else {
            throw RelayCarrier.Trouble.unreachable("Bad address.")
        }
        ask.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        ask.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let reply: URLResponse
        do {
            let (stream, answer) = try await URLSession.shared.bytes(for: ask)
            stream.task.cancel()
            reply = answer
        } catch {
            throw RelayCarrier.Trouble.unreachable(error.localizedDescription)
        }
        let http = reply as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        // Listed a moment ago and not there now: not the relay holding it.
        if code == 404 { throw Refusal.behind }
        guard (200..<300).contains(code) else { throw RelayCarrier.Trouble.refused(code) }
        var tag = (http?.value(forHTTPHeaderField: "ETag") ?? "").lowercased()
        if tag.hasPrefix("w/") { tag.removeFirst(2) }
        tag = tag.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return tag.count == 32 && tag.allSatisfy(\.isHexDigit) ? tag : nil
    }

    /// The MD5 of a file, read a megabyte at a time — a clip can be a hundred.
    static func md5(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = Insecure.MD5()
        while true {
            // **The end of a file is `nil`, not an empty chunk** — so a failed
            // read and the end have to be told apart here, not flattened by
            // `try?` into one. Flattened, every file read as unreadable and
            // every offload was refused as *does not match*. 2026-09-29.
            let chunk: Data?
            do { chunk = try handle.read(upToCount: 1 << 20) } catch { return nil }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Name to size, from one of the relay's listings — `nil` when the answer
    /// is not the shape it should be, never an empty relay.
    private static func sizes(in text: String, key: String) -> [String: Int]? {
        guard let root = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let rows = root[key] as? [[String: Any]] else { return nil }
        var out: [String: Int] = [:]
        for row in rows {
            guard let name = row["name"] as? String,
                  let size = (row["size"] as? NSNumber)?.intValue else { return nil }
            out[name] = size
        }
        return out
    }

    private static func size(of url: URL) -> Int? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true else { return nil }
        return values.fileSize
    }

    /// `^[0-9a-f]{32}\.[A-Za-z0-9]{1,8}$` — `relay/layout.json`, `medium`.
    private static func isMedium(_ name: String) -> Bool {
        let halves = name.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard halves.count == 2 else { return false }
        let stem = halves[0], ext = halves[1]
        return stem.count == 32 && stem.allSatisfy { $0.isHexDigit && !$0.isUppercase }
            && (1...8).contains(ext.count) && ext.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// `^[0-9a-f]{16}-[0-9a-f]{16}\.(log|device)$` — `log` and `mark`.
    private static func isLog(_ name: String) -> Bool {
        let halves = name.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard halves.count == 2, halves[1] == "log" || halves[1] == "device" else { return false }
        let parts = halves[0].split(separator: "-", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy {
            $0.count == 16 && $0.allSatisfy { $0.isHexDigit && !$0.isUppercase }
        }
    }

    private static func write(_ marker: Marker, at path: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(marker)
        try keepingTheDate(of: path) {
            try data.write(to: path.appending(path: markerFile), options: .atomic)
        }
    }

    /// Does `work` and puts the film folder's date back as it was.
    private static func keepingTheDate(of path: URL, _ work: () throws -> Void) rethrows {
        let key = URLResourceKey.contentModificationDateKey
        let was = (try? path.resourceValues(forKeys: [key]))?.contentModificationDate
        try work()
        if let was {
            try? FileManager.default.setAttributes([.modificationDate: was], ofItemAtPath: path.path)
        }
    }
}
