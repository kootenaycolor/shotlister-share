import Foundation

/// The files that sit beside a location.
///
/// **A location itself is no longer here.** Its name, address, notes, where it
/// is and its photographs are engine records — they moved there on 2026-08-21,
/// the day the engine learned what a location is. This file used to hold a
/// second copy of all of that in `location.json`, which meant two sources of
/// truth for one thing, and that is exactly the shape of bug the engine law
/// exists to prevent.
///
/// What is left is the part that was always meant to be files, by his ruling:
///
/// ```text
/// <Project>.shotlist/locations/<folder>/
///   scans/        RoomScan_….usdz  the shape
///                 RoomScan_….json  the measurements
///   attachments/  permits, plans, parking notes
/// ```
///
/// A room scan is a document, not a field, and the engine holds the change log
/// rather than the models — putting a forty-megabyte room inside it would be
/// putting a filing cabinet inside a notebook.
struct LocationStore {
    /// The project folder — the same one the Mac opens.
    let project: URL

    /// The location's own folder, named once when it is made so that renaming
    /// the place cannot strand its files.
    func folder(_ named: String) -> URL {
        project.appendingPathComponent("locations", isDirectory: true)
            .appendingPathComponent(named, isDirectory: true)
    }

    func scansFolder(_ named: String) -> URL {
        folder(named).appendingPathComponent("scans", isDirectory: true)
    }

    func attachmentsFolder(_ named: String) -> URL {
        folder(named).appendingPathComponent("attachments", isDirectory: true)
    }

    /// A scan is a pair of files under one name — the shape and the
    /// measurements. Keeping them named alike is what lets either be found from
    /// the other without anything having to record the relationship.
    struct Scan: Identifiable, Hashable {
        var name: String
        var usdz: URL
        var json: URL
        var made: Date
        var id: String { name }
        /// Whether the measurements survived. The shape alone still opens; it
        /// just cannot become a floor plan.
        var isMeasured: Bool { FileManager.default.fileExists(atPath: json.path) }
    }

    func scans(in named: String) -> [Scan] {
        guard !named.isEmpty else { return [] }
        rescueOldScan(in: named)
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: scansFolder(named), includingPropertiesForKeys: [.creationDateKey]
        ) else { return [] }
        return files
            .filter { $0.pathExtension.lowercased() == "usdz" }
            .map { usdz in
                let name = usdz.deletingPathExtension().lastPathComponent
                return Scan(
                    name: name,
                    usdz: usdz,
                    json: scansFolder(named).appendingPathComponent(name + ".json"),
                    made: (try? usdz.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                )
            }
            .sorted { $0.made > $1.made }
    }

    /// Where the next scan goes. Named for when it was taken, because that is
    /// the only thing anybody knows about it at the moment it is made.
    func nextScan(in named: String) -> Scan {
        let stamp = ISO8601DateFormatter.filenameSafe.string(from: Date())
        let name = "RoomScan_" + stamp
        return Scan(
            name: name,
            usdz: scansFolder(named).appendingPathComponent(name + ".usdz"),
            json: scansFolder(named).appendingPathComponent(name + ".json"),
            made: Date()
        )
    }

    func rename(scan: Scan, to fresh: String, in named: String) throws {
        let safe = fresh.replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safe.isEmpty, safe != scan.name else { return }
        let fm = FileManager.default
        try fm.moveItem(at: scan.usdz, to: scansFolder(named).appendingPathComponent(safe + ".usdz"))
        if scan.isMeasured {
            try fm.moveItem(at: scan.json, to: scansFolder(named).appendingPathComponent(safe + ".json"))
        }
    }

    func delete(scan: Scan) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: scan.usdz)
        if fm.fileExists(atPath: scan.json.path) { try fm.removeItem(at: scan.json) }
    }

    // ---- scans that landed outside any location ----------------------------

    /// Where a scan went when the place it was taken in had no folder.
    ///
    /// **A location made on the Mac has no folder** — nobody ever gave it one —
    /// and every path here is built from that name. With it empty the path
    /// collapsed to one shared bucket just under `locations/`, and `scans(in:)`
    /// answers nothing for a nameless folder, so the scan was written perfectly
    /// and then never seen again. That is the bug he reported on 2026-08-22:
    /// *"after clicking Done Scanning the scan isn't recorded and disappears"*.
    ///
    /// A place's folder falls back to its own id now, so nothing new can land
    /// here. What already did is still on the disk and still good.
    private var strandedFolder: URL {
        project.appendingPathComponent("locations", isDirectory: true)
            .appendingPathComponent("scans", isDirectory: true)
    }

    /// The scans in that bucket. **Which room each belongs to is not written
    /// down anywhere** — the path was the only record of it, and the path is
    /// what went missing — so they are offered rather than filed by guesswork.
    func stranded() -> [Scan] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: strandedFolder, includingPropertiesForKeys: [.creationDateKey]
        ) else { return [] }
        return files
            .filter { $0.pathExtension.lowercased() == "usdz" }
            .map { usdz in
                let name = usdz.deletingPathExtension().lastPathComponent
                return Scan(
                    name: name,
                    usdz: usdz,
                    json: strandedFolder.appendingPathComponent(name + ".json"),
                    made: (try? usdz.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                )
            }
            .sorted { $0.made > $1.made }
    }

    /// Puts one of them where he says it belongs.
    func adopt(_ scan: Scan, into named: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: scansFolder(named), withIntermediateDirectories: true)
        try fm.moveItem(at: scan.usdz, to: scansFolder(named).appendingPathComponent(scan.name + ".usdz"))
        if scan.isMeasured {
            try fm.moveItem(at: scan.json, to: scansFolder(named).appendingPathComponent(scan.name + ".json"))
        }
    }

    func attachments(in named: String) -> [URL] {
        guard !named.isEmpty else { return [] }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: attachmentsFolder(named),
                                                      includingPropertiesForKeys: nil)
        else { return [] }
        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    @discardableResult
    func addAttachment(from source: URL, in named: String) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: attachmentsFolder(named), withIntermediateDirectories: true)
        var destination = attachmentsFolder(named).appendingPathComponent(source.lastPathComponent)
        var n = 2
        while fm.fileExists(atPath: destination.path) {
            let stem = source.deletingPathExtension().lastPathComponent
            destination = attachmentsFolder(named)
                .appendingPathComponent("\(stem)-\(n).\(source.pathExtension)")
            n += 1
        }
        try fm.copyItem(at: source, to: destination)
        return destination
    }

    func prepare(_ named: String) {
        guard !named.isEmpty else { return }
        try? FileManager.default.createDirectory(at: scansFolder(named), withIntermediateDirectories: true)
    }

    /// Rescues a scan written before a location could hold more than one.
    ///
    /// The layout changed on 2026-08-21, from a single `scan.usdz` at the top of
    /// the location to a `scans/` folder. Anything written by the earlier build
    /// is still on disk and perfectly good — just somewhere nothing looks any
    /// more. Rather than tell him a scan he took has vanished, move it.
    private func rescueOldScan(in named: String) {
        let fm = FileManager.default
        let old = folder(named).appendingPathComponent("scan.usdz")
        guard fm.fileExists(atPath: old.path) else { return }
        let name = "RoomScan_" + ISO8601DateFormatter.filenameSafe.string(
            from: (try? old.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        )
        do {
            try fm.createDirectory(at: scansFolder(named), withIntermediateDirectories: true)
            try fm.moveItem(at: old, to: scansFolder(named).appendingPathComponent(name + ".usdz"))
            let oldJson = folder(named).appendingPathComponent("scan.json")
            if fm.fileExists(atPath: oldJson.path) {
                try fm.moveItem(at: oldJson, to: scansFolder(named).appendingPathComponent(name + ".json"))
            }
        } catch {
            // A scan that cannot be moved is still a scan; leaving it where it
            // is loses nothing that was not already invisible.
        }
    }
}

extension ISO8601DateFormatter {
    /// A timestamp that is legal in a filename on every system this project
    /// touches — colons are not.
    static let filenameSafe: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withDashSeparatorInDate]
        f.timeZone = .current
        return f
    }()
}
