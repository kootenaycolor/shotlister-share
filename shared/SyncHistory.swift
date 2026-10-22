import Foundation

/// **What sync has actually done, and when it last ran.**
///
/// His ask, 2026-08-31: *"when i hold the mouse over i want to display the last
/// time they synced and then somewhere have a sync history"*.
///
/// Compiled into the Mac app and the phone alike — `studio/build.sh` and
/// `phone/project.yml` both pick `shared/` up — because a record of syncing
/// that meant something slightly different on each device would be worse than
/// none.
///
/// ## Two questions, deliberately answered separately
///
/// **"When did it last sync?"** and **"what has it done?"** are not the same
/// question, and answering both from one list gets both wrong.
///
/// The list keeps itself level every five minutes, so a history that recorded
/// every run would be **288 entries a day**, 287 of them saying nothing
/// happened — a log nobody can read, which is the same as no log. So:
///
/// - **`lastRan`** is the last time a sync *finished without trouble*, whether
///   or not anything moved. That is the honest answer to "am I up to date", and
///   it is what the tooltip shows.
/// - **`entries`** holds only what would interest a person: a sync that moved
///   something, and any sync that failed. Those are the things worth scrolling.
enum SyncHistory {
    /// One thing worth remembering about a sync.
    struct Entry: Codable, Identifiable, Hashable {
        var id: Date { when }
        var when: Date
        /// What moved, in the app's own words — `3 in, 1 out`.
        var said: String
        /// Why it did not work, when it did not.
        var trouble: String?
        /// Whether he pressed the button or it happened on its own. Worth
        /// keeping: "it has not synced since Tuesday" means something very
        /// different if he has not pressed anything since Tuesday.
        var byHand: Bool

        var worked: Bool { trouble == nil }
    }

    /// **Deliberately not inside the film.** A sync log is *this device's*
    /// account of its own comings and goings — it is not part of the work, it
    /// must not travel to other devices, and it must not become a change that
    /// syncs. Putting it in the package would make the act of recording a sync
    /// into something that needs syncing.
    private static var file: URL {
        let folder = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Shotlister")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "sync-history.json")
    }

    private struct Stored: Codable {
        var lastRan: Date?
        var entries: [Entry]
    }

    /// **Kept in memory and written through**, because the tooltip reads this
    /// on every redraw and a file read per frame is a file read per frame.
    private static var held: Stored?

    private static func load() -> Stored {
        if let held { return held }
        let read = (try? Data(contentsOf: file))
            .flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
            ?? Stored(lastRan: nil, entries: [])
        held = read
        return read
    }

    private static func save(_ stored: Stored) {
        held = stored
        // Written whole and swapped into place — the rule everything else in
        // this app that writes a file follows.
        if let data = try? JSONEncoder().encode(stored) {
            try? data.write(to: file, options: .atomic)
        }
    }

    /// How many are kept. Enough to cover a shoot, few enough to read.
    private static let keep = 60

    // ---- what the screens ask ------------------------------------------

    /// When a sync last finished without trouble — whether or not it moved
    /// anything. Nil until one has.
    static var lastRan: Date? { load().lastRan }

    /// What has happened, newest first.
    static var entries: [Entry] { load().entries }

    /// The last sync in the words a person uses: *Synced 4 minutes ago*.
    /// **Never "Never synced"** where it might simply not be set up — the
    /// caller decides that; this only reports what it knows.
    static var said: String {
        guard let when = lastRan else { return "Not synced yet" }
        if Date().timeIntervalSince(when) < 45 { return "Synced just now" }
        let shape = RelativeDateTimeFormatter()
        shape.unitsStyle = .full
        return "Synced " + shape.localizedString(for: when, relativeTo: Date())
    }

    // ---- what sync tells it --------------------------------------------

    /// A sync finished. `said` is the app's own summary; `moved` is whether
    /// anything actually did.
    ///
    /// **A quiet automatic run updates the time and writes no entry.** That is
    /// the whole reason the two are separate — see the note at the top.
    static func finished(said: String, moved: Bool, byHand: Bool) {
        var stored = load()
        stored.lastRan = Date()
        if moved || byHand {
            stored.entries.insert(
                Entry(when: Date(), said: said, trouble: nil, byHand: byHand), at: 0)
            stored.entries = Array(stored.entries.prefix(keep))
        }
        save(stored)
    }

    /// A sync could not be done. **Always recorded, automatic or not** — a
    /// relay that has been unreachable all afternoon is exactly the thing he
    /// would want to find in here, and it is invisible everywhere else because
    /// an automatic sync is deliberately silent.
    ///
    /// The same trouble repeating is folded into the one entry rather than
    /// written 288 times: what matters is that it started, not each attempt.
    static func failed(_ why: String, byHand: Bool) {
        var stored = load()
        if let first = stored.entries.first, first.trouble == why, !byHand {
            return
        }
        stored.entries.insert(
            Entry(when: Date(), said: "", trouble: why, byHand: byHand), at: 0)
        stored.entries = Array(stored.entries.prefix(keep))
        save(stored)
    }
}
