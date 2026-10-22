import Foundation

/// **Putting a finished film away, and taking a copy of one.**
///
/// His ask, 2026-09-04: *"there should be an archiving ability for projects
/// that are finished, and the ability to export a project file with everything
/// you'd ever need to restore it. and then beyond that, if you actually want to
/// delete something you can delete with a warning."*
///
/// **They are three separate things and he said so.** Asked whether archiving
/// should write the copy for him: *"archiivng and exportin ga project file are
/// two different things. Archiivng takes it off my projects list and puts it in
/// a separate bin where i can always 'unarchive'. I can chose to export a
/// project at any time, separate from archive status."* So nothing here does
/// two of them at once, and a film's archive state has no bearing on whether a
/// copy of it can be taken.
enum Archive {
    /// The bin, inside the films folder.
    ///
    /// **Named `z-archive` by his own standing convention** — one archive name
    /// across everything he owns, never `zz-archive` or `z-archived` — and it
    /// earns its awkward spelling twice over here: it sorts to the bottom in
    /// Finder, and `Projects.all()` only ever counts things ending in
    /// `.shotlist`, so a folder is invisible to the Projects screen for free.
    ///
    /// **That is also what takes it off his iPhone.** The phone lists the films
    /// in the folder he pointed it at, one level down. A film inside the bin is
    /// a level deeper than it looks, so it leaves the phone's list without the
    /// phone being told anything. Taking it off the relay does the rest.
    static let folderName = "z-archive"

    static var bin: URL { Projects.home().appending(path: folderName) }

    /// Every archived film, newest first. Reads nothing if the bin was never made.
    static func all() -> [URL] {
        let found = (try? FileManager.default.contentsOfDirectory(
            at: bin,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return found
            .filter { $0.pathExtension == Projects.packageExtension }
            .sorted { edited($0) > edited($1) }
    }

    private static func edited(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
    }

    /// **In.** The film moves; nothing is copied and nothing is thrown away.
    ///
    /// Taking it off the relay is the caller's, and it is deliberately not done
    /// here: it can fail on a bad connection, and a film half-archived is worse
    /// than one still on the list. The order is *make sure this Mac has
    /// everything, take it off the relay, then move the folder* — so a failure
    /// at any point leaves the film exactly where it was.
    static func put(_ film: URL) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: bin, withIntermediateDirectories: true)
        let target = free(film.lastPathComponent, in: bin)
        try manager.moveItem(at: film, to: target)
        return target
    }

    /// **Out**, to the films folder it came from.
    ///
    /// The film goes back on the relay by itself: the relay has nothing under
    /// its name any more, so the next sync finds every log and every picture
    /// missing there and sends them all up. Nothing here has to know that.
    static func back(_ film: URL) throws -> URL {
        let home = Projects.home()
        let target = free(film.lastPathComponent, in: home)
        try FileManager.default.moveItem(at: film, to: target)
        return target
    }

    /// A name not already taken in that folder. Archiving must never write over
    /// a film — the whole point of the bin is that nothing in it is lost.
    private static func free(_ name: String, in folder: URL) -> URL {
        let stem = (name as NSString).deletingPathExtension
        var target = folder.appending(path: name)
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = folder.appending(path: "\(stem) \(n).\(Projects.packageExtension)")
            n += 1
        }
        return target
    }
}

/// **One file holding a whole film.**
///
/// His words: *"the ability to export a project file with everything you'd ever
/// need to restore it."* The emphasis is his and it is the whole specification
/// — this is the one thing in the app that carries the photographs.
///
/// **That is what makes it different from a backup.** `backup/backup.sh` writes
/// a zip of every film every day and deliberately leaves the pictures out, on
/// the grounds that they are three hundred times the size of the list and are
/// on the relay anyway. True for a backup, which is insurance against this Mac.
/// Not true for this, which is the copy you put on a drive, hand to somebody,
/// or open in five years when the relay is a fond memory.
///
/// **A plain zip, not a format of our own.** A film is already a folder; a zip
/// of that folder opens on any Mac ever made by double-clicking it, with no
/// Shotlister at all. Inventing an extension would buy an icon and cost him the
/// ability to get his own work back without this app.
enum Copies {
    enum Trouble: LocalizedError {
        case couldNotWrite
        case couldNotOpen
        case notAFilm

        var errorDescription: String? {
            switch self {
            case .couldNotWrite: return "That copy could not be written."
            case .couldNotOpen: return "That file could not be opened."
            case .notAFilm: return "That file does not hold a film."
            }
        }
    }

    /// What the save panel should offer — named like every other export
    /// (`FileNames.export`), and still ending `.shotlist.zip` so a folder of
    /// these says what they are: `Call-Her-Back_Film-Copy_2026-10-06.shotlist.zip`.
    static func suggestedName(for film: URL) -> String {
        let name = film.deletingPathExtension().lastPathComponent
        return FileNames.export(film: name, document: "Film-Copy",
                                ext: "\(film.pathExtension).zip")
    }

    /// **The film, whole, as one file.**
    ///
    /// `ditto` rather than a zip library: it is what `backup.sh` writes with and
    /// what `Backups.restore` reads with, it is on every Mac, and it is the only
    /// one of them that keeps a package's shape.
    static func write(_ film: URL, to destination: URL) throws {
        let manager = FileManager.default
        // The save panel has already asked him about overwriting. `ditto`
        // refuses a target that exists, so this is the answer to a question he
        // has been asked once already.
        try? manager.removeItem(at: destination)

        // Built beside and moved into place, so a copy interrupted halfway
        // leaves nothing behind that looks like a whole film.
        let building = destination.deletingLastPathComponent()
            .appending(path: ".shotlister-copying-\(UUID().uuidString).zip")
        defer { try? manager.removeItem(at: building) }

        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zip.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent",
                         film.path, building.path]
        try zip.run()
        zip.waitUntilExit()
        guard zip.terminationStatus == 0 else { throw Trouble.couldNotWrite }
        try manager.moveItem(at: building, to: destination)
    }

    /// **Back the other way**, so *Open Other…* can be handed one of these.
    ///
    /// It lands beside the films under a name that is not taken, and never over
    /// anything — the same rule as restoring a backup, and for the same reason:
    /// a copy is opened to compare it with what is here, and one that clobbers
    /// is a second way to lose the work.
    static func open(_ file: URL, into folder: URL) throws -> URL {
        let manager = FileManager.default
        let scratch = manager.temporaryDirectory
            .appending(path: "shotlister-copy-\(UUID().uuidString)")
        try manager.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: scratch) }

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", file.path, scratch.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else { throw Trouble.couldNotOpen }

        let inside = (try? manager.contentsOfDirectory(at: scratch,
                                                      includingPropertiesForKeys: nil))?
            .first { $0.pathExtension == Projects.packageExtension }
        guard let inside else { throw Trouble.notAFilm }

        let stem = inside.deletingPathExtension().lastPathComponent
        let target = folder
            .appending(path: Projects.freeName(startingAt: stem, in: folder))
            .appendingPathExtension(Projects.packageExtension)
        try manager.moveItem(at: inside, to: target)
        return target
    }
}
