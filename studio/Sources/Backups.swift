import Foundation

/// **Reading the backups from inside the app.**
///
/// The snapshots themselves are made by `backup/backup.sh`, on a schedule, and
/// that stays where it is: a backup that only runs while the app is open is a
/// backup that is not there on the morning the app will not open.
///
/// What belongs *here* is going back to one. His question, 2026-08-31, on being
/// shown the Projects screen: *"Restore from backup should be an option."* It
/// was in a separate program in his Developer folder, which meant leaving the
/// app and coming back through a side door to reach yesterday's version of his
/// own film. That is not where it goes.
///
/// **This only ever reads and copies.** Nothing here writes into the backup
/// folder, prunes it, or touches the film he is working in.
enum Backups {
    /// Where `backup.sh` puts them. Named once, here, and repeated nowhere.
    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs/Shotlister Backups")
    }

    /// One point in time for one film.
    struct Snapshot: Identifiable, Hashable {
        var id: URL { zip }
        var zip: URL
        var film: String
        var taken: Date
        var bytes: Int

        /// The date in the words a person uses. Not "2026-08-31-1926".
        var said: String {
            let shape = DateFormatter()
            shape.dateFormat = Calendar.current.isDateInToday(taken)
                ? "'Today at' HH:mm"
                : (Calendar.current.isDateInYesterday(taken)
                   ? "'Yesterday at' HH:mm"
                   : "EEEE d MMMM 'at' HH:mm")
            return shape.string(from: taken)
        }
    }

    /// Every snapshot of one film, newest first.
    ///
    /// The film is found by folder name, which is what `backup.sh` files them
    /// under and what he sees in Finder.
    static func snapshots(of film: String) -> [Snapshot] {
        let mine = folder.appending(path: film)
        let found = (try? FileManager.default.contentsOfDirectory(
            at: mine, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]
        )) ?? []
        return found
            .filter { $0.pathExtension == "zip" }
            .compactMap { zip -> Snapshot? in
                guard let taken = when(zip) else { return nil }
                let bytes = (try? zip.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return Snapshot(zip: zip, film: film, taken: taken, bytes: bytes)
            }
            .sorted { $0.taken > $1.taken }
    }

    /// `2026-08-31-1926.zip` → the moment it was taken.
    private static func when(_ zip: URL) -> Date? {
        let shape = DateFormatter()
        shape.dateFormat = "yyyy-MM-dd-HHmm"
        return shape.date(from: zip.deletingPathExtension().lastPathComponent)
    }

    enum Trouble: LocalizedError {
        case couldNotOpen
        case notAFilm

        var errorDescription: String? {
            switch self {
            case .couldNotOpen: return "That backup could not be opened."
            case .notAFilm: return "That backup does not look like a film."
            }
        }
    }

    /// **Puts a snapshot back as a film of its own, and never over the original.**
    ///
    /// It lands beside the films with the date in its name — *Call Her Back
    /// (31 Aug).shotlist* — so the two can be opened one after the other and
    /// compared before anything is decided. **Overwriting the live film is not
    /// something this can do, on purpose:** the point of a backup is to be sure,
    /// and a restore that clobbers is a second way to lose work.
    ///
    /// The photographs are not in the snapshot — they are already on this Mac,
    /// in iCloud and on the relay, and they are three hundred times the size of
    /// the list (see `backup/backup.sh`). They are copied across from the live
    /// film if it is still here; anything genuinely missing comes down on the
    /// Sync button, because a picture is named after its own contents and the
    /// relay never deletes one.
    static func restore(_ snapshot: Snapshot, beside films: URL) throws -> URL {
        let manager = FileManager.default
        let shape = DateFormatter()
        shape.dateFormat = "d MMM"
        let label = shape.string(from: snapshot.taken)

        var target = films.appending(path: "\(snapshot.film) (\(label)).shotlist")
        var n = 2
        while manager.fileExists(atPath: target.path) {
            target = films.appending(path: "\(snapshot.film) (\(label)) \(n).shotlist")
            n += 1
        }

        let scratch = manager.temporaryDirectory
            .appending(path: "shotlister-restore-\(UUID().uuidString)")
        try manager.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: scratch) }

        // `ditto` rather than a zip library: it is what wrote the archive, it
        // is on every Mac, and it keeps the package's shape.
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", snapshot.zip.path, scratch.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else { throw Trouble.couldNotOpen }

        let inside = (try? manager.contentsOfDirectory(at: scratch, includingPropertiesForKeys: nil))?
            .first { $0.pathExtension == "shotlist" }
        guard let inside else { throw Trouble.notAFilm }

        try manager.moveItem(at: inside, to: target)

        // The pictures, from the film he is working in. Same bytes under the
        // same names, so this can only ever add.
        let live = films.appending(path: "\(snapshot.film).shotlist/media")
        if manager.fileExists(atPath: live.path) {
            try? manager.copyItem(at: live, to: target.appending(path: "media"))
        }
        return target
    }
}
