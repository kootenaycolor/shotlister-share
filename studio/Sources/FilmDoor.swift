import AppKit
import Foundation

/// **The Projects Console's door for putting a film away, and getting it back.**
///
/// The one-record plan, item 7 (2026-10-05): *Archive done once.* Archiving a
/// project in the console moves its Drive folders, flips Notion, restricts the
/// portal — and until now only *reminded* him to archive the Shotlister film.
/// This is the door that lets the console ask Shotlister to do it, the same
/// way `--recordfacts` and `--newfilm` are doors: the console never moves a
/// film itself, it asks the program that owns it.
///
///     --archivefilm   <Notion page id>
///     --unarchivefilm <Notion page id>
///
/// **By the linked project page, never by title.** A title is a guess that
/// breaks the day either end is renamed; the page id is written into the film
/// by Link (`console_page`). Two films linked to one page is refused — the
/// door does not pick.
///
/// **Archived exactly as the Projects screen's Archive does it** — the same
/// order, the same relay calls, the same bin (`Archive`): fetch everything the
/// relay holds that this Mac does not, take the film off the relay (which sets
/// the portal's files aside in `kept/` first), then move the folder. On top of
/// that, two things only a program asking from outside needs:
///
/// * **Close it if it is open.** A Shotlister window holding the film is asked
///   to let go (a distributed notification, `letGo`), and the door waits until
///   the film's `.in-use` lock is free. One that will not let go is a refusal.
/// * **Never lose work.** Everything this Mac has that the relay does not is
///   sent first — a film the console wrote facts into is often closed, and a
///   closed film does not sync. Anything that still will not go up is a
///   refusal that names it, and nothing has moved.
///
/// Says one line back on stderr, starting `archivefilm:` or `unarchivefilm:`,
/// and ends the run.
@MainActor
enum FilmDoor {
    /// What a Shotlister window listens for. The object is the film's path.
    nonisolated static let letGo = Notification.Name("com.example.shotlister.letgo")

    struct Found {
        var url: URL
        var title: String
        var inTheBin: Bool
    }

    /// One spelling of a Notion page id: no dashes, lower case.
    static func bare(_ page: String) -> String {
        page.replacingOccurrences(of: "-", with: "").lowercased()
            .trimmingCharacters(in: .whitespaces)
    }

    /// Every film on this Mac — the films folder, then the bin — that says it
    /// belongs to this page. Read through the engine, the film's own word.
    static func films(linkedTo page: String) -> [Found] {
        let wanted = bare(page)
        guard !wanted.isEmpty else { return [] }
        let live = Projects.all().map { ($0, false) }
        let binned = Archive.all().map { ($0, true) }
        var found: [Found] = []
        for (url, inTheBin) in live + binned {
            guard let engine = Engine(path: url, device: ShellState.deviceId),
                  let project = engine.view()?.project else { continue }
            if bare(project.consolePage) == wanted {
                found.append(Found(url: url, title: project.title, inTheBin: inTheBin))
            }
        }
        return found
    }

    // ---- in ---------------------------------------------------------------

    static func archive(page: String) async -> String {
        let all = films(linkedTo: page)
        let live = all.filter { !$0.inTheBin }
        if live.isEmpty {
            if let put = all.first {
                return "archivefilm: already archived \"\(put.title)\" at \"\(put.url.path)\""
            }
            return "archivefilm: refused — no film is linked to this project"
        }
        if live.count > 1 {
            return "archivefilm: refused — \(live.count) films are linked to this project: "
                + live.map { "\"\($0.url.lastPathComponent)\"" }.joined(separator: ", ")
        }
        let film = live[0]
        let url = film.url

        // **Closed first.** Nothing below may run under a window that has it.
        if InUse.elsewhere(url) {
            guard await askToLetGo(url) else {
                return "archivefilm: refused — \"\(film.title)\" is open in Shotlister and was not closed"
            }
        }

        var sent = (logs: 0, media: 0)
        var brought = (logs: 0, media: 0)
        var removed = (gone: 0, keptAt: "", keptFiles: 0)
        var offAlready = false
        if Relay.projectId(at: url) != nil {
            guard await Relay.lendTheDoorHisWord() else {
                return "archivefilm: refused — sync is not set up on this Mac, or its password could not be read"
            }
            // **Everything this Mac has, up first** — and then asked again.
            // Only for a film the relay has held: one that never went up has
            // nothing anywhere else to fall behind, and sending it now would
            // sign it up to the relay just to take it off again.
            if Relay.wasOnTheRelay(at: url) {
                guard let engine = Engine(path: url, device: ShellState.deviceId) else {
                    return "archivefilm: refused — \"\(film.title)\" could not be opened"
                }
                var trouble = ""
                do {
                    let logs = try await Relay.syncLogs(engine: engine, path: url)
                    sent.logs = logs.sentLogs
                } catch RelayCarrier.Trouble.gone(let fate) {
                    if fate == .deleted {
                        return "archivefilm: refused — \"\(film.title)\" was deleted on another device"
                    }
                    offAlready = true
                } catch {
                    trouble = error.localizedDescription
                }
                if !offAlready {
                    do {
                        let media = try await Relay.syncMedia(engine: engine, path: url)
                        sent.media = media.sentMedia
                    } catch {
                        if trouble.isEmpty { trouble = error.localizedDescription }
                    }
                    do {
                        let left = try await Relay.unsent(engine: engine, path: url)
                        let waiting = left.logs.count + left.media.count
                        if waiting > 0 {
                            var why = "archivefilm: refused — not synced: "
                            why += Self.count(left.logs.count, "change log", "change logs")
                            why += ", " + Self.count(left.media.count, "picture", "pictures")
                            why += " (" + (left.logs + left.media).prefix(6).joined(separator: ", ")
                            why += left.logs.count + left.media.count > 6 ? ", …)" : ")"
                            if !trouble.isEmpty { why += " — \(trouble)" }
                            return why
                        }
                    } catch RelayCarrier.Trouble.gone(let fate) {
                        if fate == .deleted {
                            return "archivefilm: refused — \"\(film.title)\" was deleted on another device"
                        }
                        offAlready = true
                    } catch {
                        return "archivefilm: refused — could not check what is synced: \(error.localizedDescription)"
                    }
                }
            }
            // The Projects screen's own order from here: fetch, take off, move.
            if !offAlready {
                do {
                    let got = try await Relay.pullEverything(at: url)
                    brought = (got.logs, got.media)
                    removed = try await Relay.removeFilmSaying(at: url, fate: .archived)
                } catch {
                    return "archivefilm: refused — \(error.localizedDescription)"
                }
            }
        }

        // Opened again while the relay was being asked? Then the window that
        // has it moves it itself at its next sync, which reads the relay's
        // note — and this door does not pull the floor out from under it.
        if InUse.elsewhere(url) {
            return "archivefilm: off the sync service; \"\(film.title)\" is open in Shotlister, which moves it to the archive itself"
        }
        do {
            let put = try Archive.put(url)
            var line = "archivefilm: archived \"\(film.title)\" at \"\(put.path)\""
            line += "  sent \(sent.logs) logs \(sent.media) pictures"
            line += "  fetched \(brought.logs) logs \(brought.media) pictures"
            if offAlready {
                line += "  relay: already off"
            } else {
                line += "  relay: \(removed.gone) files off"
            }
            if removed.keptFiles > 0 {
                line += "  portal kept: \(removed.keptFiles) files at \"\(removed.keptAt)\""
            }
            return line
        } catch {
            return "archivefilm: off the sync service, but the folder did not move — \(error.localizedDescription)"
        }
    }

    // ---- deleting an empty one ----------------------------------------------

    /// **Delete a project that holds nothing**, the way the Projects screen's
    /// Delete does it: the relay first (which sets any portal files aside in
    /// `kept/` and leaves the note every other device follows), then the folder
    /// to the Trash. Found by its relay id, the id the Studio side shows.
    ///
    /// **Refuses anything that holds a scene, location, board, day, shot or
    /// picture.** This door exists for the empty "Untitled" projects a stray
    /// New Project leaves behind, which the console's Delete cannot reach
    /// because they have no record. It is not a way to delete a real project.
    static func deleteEmpty(relay id: String) async -> String {
        let wanted = bare(id)
        guard !wanted.isEmpty else { return "deletefilm: refused — no id given" }
        let here = Projects.all().filter { Relay.projectId(at: $0).map(bare) == wanted }
        guard here.count == 1, let url = here.first else {
            return here.isEmpty
                ? "deletefilm: refused — no project on this Mac has that relay id"
                : "deletefilm: refused — \(here.count) projects on this Mac have that relay id"
        }
        guard let engine = Engine(path: url, device: ShellState.deviceId),
              let view = engine.view() else {
            return "deletefilm: refused — \"\(url.lastPathComponent)\" could not be opened"
        }
        var held: [String] = []
        if !view.scenes.isEmpty { held.append("\(view.scenes.count) scenes") }
        if !view.units.isEmpty { held.append("\(view.units.count) shots") }
        if !view.locations.isEmpty { held.append("\(view.locations.count) locations") }
        if !view.boards.isEmpty { held.append("\(view.boards.count) boards") }
        if !view.days.isEmpty { held.append("\(view.days.count) days") }
        var pictures = 0
        if let walk = FileManager.default.enumerator(
            at: url.appending(path: "media"), includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let file as URL in walk
            where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                pictures += 1
            }
        }
        if pictures > 0 { held.append("\(pictures) pictures") }
        if !held.isEmpty {
            return "deletefilm: refused — \"\(view.project.title)\" is not empty (\(held.joined(separator: ", ")))"
        }
        if InUse.elsewhere(url) {
            guard await askToLetGo(url) else {
                return "deletefilm: refused — \"\(view.project.title)\" is open in Studio and was not closed"
            }
        }
        guard await Relay.lendTheDoorHisWord() else {
            return "deletefilm: refused — sync is not set up on this Mac, or its password could not be read"
        }
        var removed = (gone: 0, keptAt: "", keptFiles: 0)
        do {
            removed = try await Relay.removeFilmSaying(at: url, fate: .deleted)
        } catch {
            return "deletefilm: refused — \(error.localizedDescription)"
        }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            return "deletefilm: off the relay, but the folder did not move to the Trash — \(error.localizedDescription)"
        }
        var line = "deletefilm: deleted \"\(view.project.title)\" (\(url.lastPathComponent))  relay: \(removed.gone) files off"
        if removed.keptFiles > 0 { line += "  portal kept: \(removed.keptFiles) files at \"\(removed.keptAt)\"" }
        return line
    }

    // ---- out --------------------------------------------------------------

    /// **Out of the bin**, as the Projects screen's Unarchive does it: the
    /// folder back, the relay's note cleared first, and — because a door does
    /// not open the film the way a click does — one sync to send it back up,
    /// so his phone and the portal's film have it again. The portal's own
    /// files (invites, links, What Viewers See) stay where the relay set them
    /// aside; `backup/restore-portal.sh` brings those back.
    static func unarchive(page: String) async -> String {
        let all = films(linkedTo: page)
        let binned = all.filter(\.inTheBin)
        if binned.isEmpty {
            if let here = all.first {
                return "unarchivefilm: not archived \"\(here.title)\" at \"\(here.url.path)\""
            }
            return "unarchivefilm: refused — no film is linked to this project"
        }
        if binned.count > 1 || all.count > 1 {
            return "unarchivefilm: refused — \(all.count) films are linked to this project"
        }
        let film = binned[0]
        let back: URL
        do {
            back = try Archive.back(film.url)
        } catch {
            return "unarchivefilm: refused — \(error.localizedDescription)"
        }
        var line = "unarchivefilm: back \"\(film.title)\" at \"\(back.path)\""
        guard Relay.projectId(at: back) != nil else { return line + "  relay: never on it" }
        guard await Relay.lendTheDoorHisWord() else {
            return line + "  relay: not set up — sends when opened"
        }
        await Relay.putBack(at: back)
        guard let engine = Engine(path: back, device: ShellState.deviceId) else {
            return line + "  relay: sends when opened"
        }
        do {
            let logs = try await Relay.syncLogs(engine: engine, path: back)
            let media = try await Relay.syncMedia(engine: engine, path: back)
            line += "  sent \(logs.sentLogs) logs \(media.sentMedia) pictures"
        } catch {
            line += "  relay: \(error.localizedDescription) — sends when opened"
        }
        return line
    }

    // ---- closing a film somebody else has open ------------------------------

    /// Asks every Shotlister window to let go of this film, then waits for its
    /// lock to come free. True when nobody holds it any more.
    static func askToLetGo(_ url: URL, patience: Double = 30) async -> Bool {
        DistributedNotificationCenter.default().postNotificationName(
            letGo, object: url.standardizedFileURL.path, userInfo: nil, deliverImmediately: true)
        let until = Date().addingTimeInterval(patience)
        while Date() < until {
            if !InUse.elsewhere(url) { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return !InUse.elsewhere(url)
    }

    /// **A window's half: let go when the door asks.** Installed by every real
    /// launch, and by a checking run that holds a film for a check
    /// (`--holdfilm`). Waits for a sync of that film to finish, puts the pen
    /// down so a half-typed cell is written, then opens something else — the
    /// same `letGoOf` the Projects screen's own Archive uses.
    nonisolated static func listen(state: ShellState) {
        DistributedNotificationCenter.default().addObserver(
            forName: letGo, object: nil, queue: .main
        ) { note in
            guard let path = note.object as? String else { return }
            MainActor.assumeIsolated {
                letGoWhenQuiet(URL(fileURLWithPath: path), state: state, tries: 150)
            }
        }
    }

    private static func letGoWhenQuiet(_ url: URL, state: ShellState, tries: Int) {
        guard InUse.same(url, state.projectPath) else { return }
        if state.syncing, tries > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                letGoWhenQuiet(url, state: state, tries: tries - 1)
            }
            return
        }
        for window in NSApp.windows where window.firstResponder is NSTextView {
            window.makeFirstResponder(nil)
        }
        state.engine?.save()
        let gone = state.letGoOf(url)
        if Launch.checking {
            FileHandle.standardError.write(Data((
                "letgo: \(gone ? "let go" : "could not let go") of \"\(url.lastPathComponent)\""
                + "  now open: \"\(state.projectPath?.lastPathComponent ?? "-")\"\n").utf8))
        }
    }

    private static func count(_ n: Int, _ one: String, _ many: String) -> String {
        "\(n) \(n == 1 ? one : many)"
    }
}
