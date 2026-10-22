import Foundation

/// Where projects live, and how to open one.
///
/// A project is a folder package in `~/Documents/Shotlister/`. **A plain
/// folder, not iCloud Drive** — his ruling, 2026-09-15: *"Relay only."*
/// From 2026-08-17 the films lived in `iCloud Drive/Shotlister/` and iCloud
/// carried them between his Macs; from 2026-08-31 the relay
/// (`Relay.swift`, his own server) carried them too, and two roads moving
/// the same files gave iCloud conflicts to settle — six duplicate logs
/// inside Call Her Back by the day it stopped. Now the engine merges its own
/// document, the relay is the only road between devices, and a film reaches
/// a new Mac by being fetched from the relay (`Relay.clone`), not by a folder
/// appearing. `design/DECISIONS.md`, 2026-09-15.
enum Projects {
    /// **The Labs build keeps its films apart.** `Documents/Shotlister
    /// Labs/`, so nothing built in the fork can open a real film by accident
    /// — a film he wants to try there is copied in on purpose.
    #if SHOTLISTER_LABS
    static let folderName = "Shotlister Labs"
    #else
    static let folderName = "Shotlister"
    #endif
    static let packageExtension = "shotlist"

    /// The folder projects go in. Made if it is missing, so a fresh Mac has
    /// somewhere for the relay to put a film.
    static func home() -> URL {
        // **A checking run can be given a films folder of its own**
        // (`SHOTLISTER_FILMS`), the way `--newfilm` already could — so a check
        // of archiving moves scratch films into a scratch bin and never his.
        // A real launch ignores it: the console never sets it.
        if Launch.checking,
           let said = ProcessInfo.processInfo.environment["SHOTLISTER_FILMS"], !said.isEmpty {
            let folder = URL(fileURLWithPath: said, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
        let folder = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Every project in the home folder, newest first.
    static func all() -> [URL] {
        let home = home()
        // **Not `.skipsHiddenFiles`.** A `.shotlist` folder is a film whether
        // or not Finder's hidden flag is on it, and the extension filter below
        // already keeps out every dotfile and half-built `.shotlister-arriving`
        // folder. With the flag honoured, a hidden film vanished from the list
        // while still being on disk — so the list offered to fetch it from the
        // relay and the fetch refused to write over it. His report,
        // 2026-09-15: a Labs copy of Call Her Back wearing that flag.
        let found = (try? FileManager.default.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return found
            .filter { $0.pathExtension == packageExtension }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return a > b
            }
    }

    // ------------------------------------------------------ iCloud placeholders

    /// A file iCloud has not downloaded yet is *present but empty*, standing in
    /// for the real one under a name like `.manifest.json.icloud`. Treating that
    /// as "the file is missing" is how a synced project looks corrupted on the
    /// second Mac. So: ask for the download and wait briefly for it.
    ///
    /// **Kept after the films left iCloud Drive (2026-09-15)** because a film
    /// can still be opened from anywhere — a backup restored out of iCloud,
    /// a folder he drags in — and in a home folder of plain files this finds
    /// nothing and returns at once.
    ///
    /// Returns the names it was still waiting on, so a caller can say so rather
    /// than opening something half-there.
    @discardableResult
    static func bringDown(_ package: URL, waiting seconds: TimeInterval = 8) -> [String] {
        let manager = FileManager.default
        var pending = placeholders(in: package)
        guard !pending.isEmpty else { return [] }

        for url in pending {
            try? manager.startDownloadingUbiquitousItem(at: realName(of: url))
        }

        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            pending = placeholders(in: package)
            if pending.isEmpty { return [] }
            // A short spin rather than a sleep: this runs before the window
            // exists, and the run loop has nothing else to do yet.
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return pending.map { realName(of: $0).lastPathComponent }
    }

    private static func placeholders(in package: URL) -> [URL] {
        guard let walk = FileManager.default.enumerator(
            at: package, includingPropertiesForKeys: nil
        ) else { return [] }
        return walk.compactMap { $0 as? URL }.filter { $0.pathExtension == "icloud" }
    }

    /// `.manifest.json.icloud` is standing in for `manifest.json`.
    private static func realName(of placeholder: URL) -> URL {
        let stub = placeholder.deletingPathExtension().lastPathComponent
        let real = stub.hasPrefix(".") ? String(stub.dropFirst()) : stub
        return placeholder.deletingLastPathComponent().appendingPathComponent(real)
    }

    // ------------------------------------------------------------------ naming

    /// A title as a filename. `/` and `:` are the two a Mac will not have, and
    /// a name that is nothing but spaces is not a name.
    static func safeName(_ title: String) -> String {
        title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func url(named name: String) -> URL {
        home().appendingPathComponent(name).appendingPathExtension(packageExtension)
    }

    /// A name that is not taken yet. Never overwrites: a project is somebody's
    /// work, and silently opening on top of it is the one unrecoverable mistake
    /// this folder can make.
    static func freeName(startingAt wanted: String) -> String {
        freeName(startingAt: wanted, in: home())
    }

    /// The same, in a folder that is not the projects folder — a project opened
    /// from somewhere else stays where it is when it is renamed.
    static func freeName(startingAt wanted: String, in folder: URL) -> String {
        var name = wanted
        var n = 2
        while FileManager.default.fileExists(atPath: folder
                .appendingPathComponent(name)
                .appendingPathExtension(packageExtension).path) {
            name = "\(wanted) \(n)"
            n += 1
        }
        return name
    }
}
