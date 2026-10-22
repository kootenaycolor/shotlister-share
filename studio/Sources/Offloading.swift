import Foundation

/// The Mac's half of keeping a film in the cloud only — see `shared/Offload.swift`
/// for what goes, what stays, and the check that comes first. What is the Mac's
/// own: where the files go (the Trash), and knowing that a film is open in
/// another window of this app.
enum Offloading {
    /// **Into the Trash, as one folder** — `Call Her Back — Offloaded` — so the
    /// Finder can give it back, and the Trash is not three hundred files named
    /// by their hashes.
    ///
    /// **A checking run never touches his Trash.** Its folder goes to the
    /// run's own temporary folder instead, and the run says where.
    static func putAway(_ folder: URL) throws {
        if Launch.checking {
            let bin = FileManager.default.temporaryDirectory
                .appending(path: "shotlister-offload-trash-\(ProcessInfo.processInfo.processIdentifier)")
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            let landing = bin.appending(path: folder.lastPathComponent)
            try? FileManager.default.removeItem(at: landing)
            try FileManager.default.moveItem(at: folder, to: landing)
            FileHandle.standardError.write(Data("offload trash: \(landing.path)\n".utf8))
            return
        }
        try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
    }

    static func said(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// **Which films are open in a window of this app, across every copy of it.**
///
/// *Open in another window* starts a second copy of the app on another film
/// (`Launch.another`), and each copy knows only its own. Offloading a film one
/// of them has open would pull its pictures out from under that window — and
/// that window's next sync would fetch them straight back, undoing the offload
/// with nothing said.
///
/// So each copy holds a shared lock on a small file inside the film it has
/// open (`.in-use`), and an offload asks for the exclusive one first. **The
/// system lets go of a lock when the program ends, crash or not**, so a copy of
/// the app that died never leaves a film looking open.
enum InUse {
    static let fileName = ".in-use"
    private static var held: Int32 = -1
    private static var heldFor: String?

    /// One spelling of a film's place — a folder URL can carry a trailing
    /// slash or not depending on who made it.
    static func same(_ a: URL?, _ b: URL?) -> Bool {
        guard let a, let b else { return false }
        return a.standardizedFileURL.path == b.standardizedFileURL.path
    }

    /// Called by `ShellState.open` for the film it has just opened.
    static func hold(_ film: URL) {
        guard heldFor != film.standardizedFileURL.path else { return }
        release()
        let lock = film.appending(path: fileName)
        let existed = FileManager.default.fileExists(atPath: lock.path)
        // Keeps the film folder's date the first time the file is made: the
        // Projects list sorts by that date and says *Edited* from it.
        let date = (try? film.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        let fd = open(lock.path, O_RDONLY | O_CREAT, 0o644)
        if !existed, let date {
            try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: film.path)
        }
        guard fd >= 0 else { return }
        if flock(fd, LOCK_SH | LOCK_NB) != 0 {
            close(fd)
            return
        }
        held = fd
        heldFor = film.standardizedFileURL.path
    }

    static func release() {
        if held >= 0 {
            flock(held, LOCK_UN)
            close(held)
        }
        held = -1
        heldFor = nil
    }

    /// **Whether another copy of the app has this film open.** A film that has
    /// never been opened by a build with this has no file to lock, and nobody
    /// can be holding it.
    static func elsewhere(_ film: URL) -> Bool {
        if heldFor == film.standardizedFileURL.path { return true }
        let lock = film.appending(path: fileName)
        let fd = open(lock.path, O_RDONLY)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            flock(fd, LOCK_UN)
            return false
        }
        return true
    }
}

extension Offloading {
    /// Why a film stays whole that only the Mac can know.
    enum Refusal: LocalizedError {
        case open(String)
        var errorDescription: String? {
            switch self {
            case .open(let name): return "“\(name)” is open."
            }
        }
    }

    /// **The whole offload, after the question** — the Projects screen's menu
    /// and the checking door both come through here, so what a check proves is
    /// what the menu does.
    ///
    /// **Open is asked twice**: before the check, and again after it, because
    /// the check asks the relay about every picture and takes long enough for
    /// him to open the film in another window meanwhile.
    @MainActor
    static func run(_ url: URL, state: ShellState,
                    progress: @escaping @MainActor (Int, Int) -> Void) async throws
        -> (files: Int, bytes: Int) {
        let name = url.deletingPathExtension().lastPathComponent
        guard !InUse.same(url, state.projectPath), !InUse.elsewhere(url) else { throw Refusal.open(name) }
        let plan = try await Relay.offloadCheck(at: url, progress: progress)
        guard !InUse.same(url, state.projectPath), !InUse.elsewhere(url) else { throw Refusal.open(name) }
        let bytes = try Offload.takeOff(plan, at: url, putAway: putAway)
        return (plan.files.count, bytes)
    }
}
