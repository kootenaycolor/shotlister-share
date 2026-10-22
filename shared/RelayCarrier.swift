import Foundation

/// **Carrying a film to his own relay and back — written once, for both apps.**
///
/// Until 2026-09-16 this lived twice, as `studio/Sources/Relay.swift` and
/// `phone/Sources/Relay.swift`, kept in step by discipline. They had drifted by
/// eight hundred lines: the Mac had grown a tidy of superseded files, an audit,
/// a second question after a 409, and the phone had none of them. Compiled into
/// both apps — `studio/build.sh` and `phone/project.yml` both pick `shared/`
/// up — the way `Watch.swift` already is, and for the same reason: two
/// implementations of one road drift, and the drifted one is the one nobody
/// tested.
///
/// **This does not decide anything.** What should move is worked out by the
/// engine — `syncplan` — and this only fetches and puts what it was told to,
/// then hands the result to the `pull` that has always existed. Two answers to
/// "what should move" would drift apart the same way.
///
/// **What differs per device is handed in**, as a `RelayDevice`, rather than
/// copied around: where the address comes from (a file the Mac's *Set Up Sync*
/// wrote; the film's own `remote.json` on the phone), whose Keychain item the
/// password is, and which device the sentences name. Each app's `Relay` is
/// that, plus a forwarder per function, and nothing else.
///
/// The transfers are `URLSession`'s rather than the engine's, and that is the
/// whole reason this is in Swift: it is the only way to get a transfer that
/// survives the app going to the background or a signal dropping halfway up a
/// logging road.
///
/// ## The order matters
///
/// **Logs, then merge, then pictures.** A film is about a megabyte of list and
/// a hundred megabytes of photographs. Merging in between is the difference
/// between seeing today's shots straight away and waiting for a whole film's
/// worth of pictures on a bad connection.

/// The three things that are genuinely one device's and not the other's.
struct RelayDevice {
    /// How a sentence names it: `this Mac`, `this iPhone`.
    var name: String
    /// The whole sentence for a device that has not been set up, because the
    /// way to set it up differs — a double-click on the Mac, a menu on the phone.
    var notSetUp: String
    /// The relay's address, for a film in hand or for none — tidied, and with
    /// no trailing slash. The Mac reads a file *Set Up Sync* left; the phone
    /// reads the film's own `remote.json` and falls back to what was typed.
    var address: (URL?) -> String?
    /// The word that gets this device in. Each app's own Keychain item.
    var token: () -> String?

    /// Before an app has said which it is. Every sentence still reads, and
    /// nothing else changes; the apps set the real one at launch.
    static let unknown = RelayDevice(
        name: "this device",
        notSetUp: "Sync is not set up on this device.",
        address: { _ in nil },
        token: { nil })
}

enum RelayCarrier {
    /// Which device this is. Set once by each app's `Relay` before anything
    /// here is asked — see `Relay.device` in `studio/` and `phone/`.
    static var device = RelayDevice.unknown

    /// Where things sit inside a project.
    ///
    /// **The engine owns these names** — `engine/src/package.rs` — and they are
    /// a file-format contract, so they cannot change without breaking every
    /// film ever written. Repeated here because Swift cannot ask Rust for a
    /// constant, and kept in one place so there is one thing to fix if that
    /// ever stops being true. The relay's side of the same names is
    /// `relay/layout.json`, and `relay/checks.sh` measures this file against it.
    static let changesDir = "changes"
    static let proxiesDir = "media/proxies"
    static let manifestFile = "manifest.json"

    /// The file inside a project that remembers which relay it belongs to.
    ///
    /// **Written once and never rewritten**, which is what makes it safe to
    /// keep inside a package that syncs: it travels to every device over
    /// whatever is already carrying the folder, so a film started on the Mac is
    /// already pointed at the right relay by the time the phone opens it — and
    /// there is nothing for two devices to disagree about, the way there would
    /// be if each rewrote it. The same reasoning as the identity mark beside
    /// the logs (Ref 186).
    static let linkFile = "remote.json"

    // ---- which film this is ------------------------------------------------

    /// Which film this is, as far as the relay is concerned.
    ///
    /// Made on the first sync and then never again. Random rather than derived
    /// from the title, because a film gets renamed and its identity should not
    /// move when it does — his *Untitled 2* became *Call Her Back* and the
    /// manifest inside it lagged for weeks.
    ///
    /// A phone that makes one has almost always got there first — the ordinary
    /// case is that the Mac already pushed this film and the id came down with
    /// the package.
    static func projectId(at path: URL, making: Bool = false) -> String? {
        if let held = link(at: path), !held.project.isEmpty { return held.project }
        guard making else { return nil }
        let made = String((0..<32).map { _ in "0123456789abcdef".randomElement()! })
        let held = Link(relay: device.address(path) ?? "", project: made)
        if let data = try? JSONEncoder().encode(held) {
            try? data.write(to: path.appending(path: linkFile), options: .atomic)
        }
        return made
    }

    static func link(at path: URL) -> Link? {
        guard let data = try? Data(contentsOf: path.appending(path: linkFile)) else { return nil }
        return try? JSONDecoder().decode(Link.self, from: data)
    }

    struct Link: Codable {
        var relay: String
        var project: String
        /// **Whether this film has ever been on the relay from here.** Set the
        /// first time a sync finds the relay holding it, or sends it up; a
        /// link written before this existed has no value and reads as false.
        ///
        /// This is what tells *taken off the relay* from *never sent*. Both
        /// look the same from a device — the relay holds nothing under the
        /// name — and without it a film he archived on the Mac was quietly
        /// put back by the iPhone's next sync (Ref 1033, 2026-09-16).
        var synced: Bool?
    }

    /// The film has been on the relay from this device before.
    static func wasOnTheRelay(at path: URL) -> Bool {
        link(at: path)?.synced == true
    }

    /// **Put it back.** His answer to *taken off the relay* when the phone's
    /// copy is the one he wants to keep: forget that the relay ever held it,
    /// and the next sync sends the whole film up as if it were new.
    static func allowResend(at path: URL) {
        guard var held = link(at: path), held.synced == true else { return }
        held.synced = false
        if let data = try? JSONEncoder().encode(held) {
            try? data.write(to: path.appending(path: linkFile), options: .atomic)
        }
    }

    /// **Out of a bin, and the relay told first.** The relay's note that the
    /// film was taken off is cleared before this device syncs, because a
    /// sync reads the note first and would put the film straight back in
    /// the bin it just left. A film that was never on the relay, or a relay
    /// that cannot be reached, is not an error here: the film is back on
    /// this device either way, and the next sync sends it up.
    static func putBack(at path: URL) async {
        allowResend(at: path)
        guard let (root, word) = try? onTheRelay(path) else { return }
        _ = try? await send("PUT", to: "\(root)/back", word)
    }

    /// Remember that the relay has held this film. Written once; rewriting
    /// the same fact would only touch the file's date.
    private static func markSynced(at path: URL) {
        guard var held = link(at: path), held.synced != true else { return }
        held.synced = true
        if let data = try? JSONEncoder().encode(held) {
            try? data.write(to: path.appending(path: linkFile), options: .atomic)
        }
    }

    /// **Why a film left the relay** — his ruling 2026-09-16: one Projects
    /// list on every device, so the fate travels and every copy follows it.
    enum Fate: String, Codable {
        case archived
        case deleted
    }

    // ---- what a run of it did ---------------------------------------------

    struct Report {
        var sentLogs = 0
        var receivedLogs = 0
        var sentMedia = 0
        var receivedMedia = 0
        var merged = 0
        var clashes = 0
        /// Files the relay held that the film no longer names, taken away.
        var tidied = 0

        var isEmpty: Bool {
            sentLogs == 0 && receivedLogs == 0 && sentMedia == 0 && receivedMedia == 0
        }

        /// What the toolbar says afterwards. **A count is a count** — see the
        /// copy law in `CLAUDE.md`.
        var said: String {
            if isEmpty { return "Up to date" }
            var parts: [String] = []
            // **`merged`, not `receivedLogs`, decides whether to say anything.**
            //
            // A log can arrive and change nothing — it is the ordinary case
            // when a device fetches back a log it had already taken in. Keying
            // the sentence off *arrival* and then printing the merge count says
            // **"0 in"**, which is not a count of anything and reads as a
            // failure. Nothing new is "Up to date", which is what it is.
            if merged > 0 { parts.append("\(merged) in") }
            if sentLogs > 0 { parts.append("\(sentLogs) out") }
            if receivedMedia > 0 { parts.append("\(receivedMedia) pictures") }
            return parts.isEmpty ? "Up to date" : parts.joined(separator: ", ")
        }
    }

    enum Trouble: LocalizedError {
        case notSetUp
        case refused(Int)
        case unreachable(String)
        /// **A transfer that stalled, saying so in its own words.**
        ///
        /// Not `unreachable`: that one prefixes "Could not reach the relay",
        /// which is a lie when the relay answered perfectly well and refused
        /// one file, and a contradiction when the sentence after it names a
        /// status code. 2026-09-08.
        case stuck(String)
        case alreadyHere(String)
        /// **The relay no longer holds a film this device once synced.** It was
        /// archived or deleted somewhere else, and sending it up again would
        /// undo that — so nothing is sent, and the app does the same to its
        /// own copy. The fate is the relay's note when it left one; nil is a
        /// relay that forgot (taken off before 2026-09-16), which the apps
        /// treat as archived, the fate that loses nothing.
        case gone(Fate?)

        var errorDescription: String? {
            switch self {
            case .notSetUp:
                return RelayCarrier.device.notSetUp
            case .refused(let code):
                return code == 401
                    ? "The relay would not accept \(RelayCarrier.device.name)'s password."
                    : "The relay said \(code)."
            case .unreachable(let why):
                return "Could not reach the relay. \(why)"
            case .stuck(let why):
                return why
            case .alreadyHere(let name):
                return "\(name) is already here. Open it and sync instead."
            case .gone(let fate):
                switch fate {
                case .deleted: return "This film was deleted on another device."
                case .archived: return "This film was archived on another device."
                case nil: return "This film was taken off the relay."
                }
            }
        }
    }

    // ---- doing it ----------------------------------------------------------

    /// **The list, both ways.** Send our logs, fetch theirs into `changes/`.
    ///
    /// It deliberately stops there and does **not** merge. Merging is the
    /// app's (`ShellState.pullNow`, `Session.pullNow`), which already knows to
    /// refresh the screen, let go of thumbnails for pictures the project no
    /// longer has, and say something when a disagreement arrives. Doing it
    /// here would be a second copy of all that, and the second copy is the one
    /// that goes stale.
    static func syncLogs(engine: Engine, path: URL) async throws -> Report {
        let (root, word) = try where_(path)
        guard let (plan, _, held) = try await plan(engine: engine, at: path, root: root, word: word) else {
            throw Trouble.unreachable("The relay's answer could not be read.")
        }

        var report = Report()
        let changes = path.appending(path: changesDir)

        // **One file that will not move must not stop the rest.** This used to
        // throw at the first refusal, so a single log the relay would not take
        // held back every log behind it — and the newest, which is the day's
        // work, is always behind. 2026-09-04, when a folded log the relay
        // refused kept an afternoon of changes on this Mac while the web showed
        // the film as it stood that afternoon. The trouble is still raised; it
        // is raised after everything that could travel has.
        // **Which way it was going, and what was said.** Ref filed 2026-09-08.
        //
        // This was a bare `[String]` and every entry read *"one file would not
        // move"* — the same sentence for an upload the relay rejected and for a
        // download that never arrived, which are opposite faults with opposite
        // fixes. It cost a whole investigation: the name in the message did not
        // even exist on this Mac, so it could only ever have been a fetch, and
        // the message had been read as a rejected send.
        //
        // A refusal now carries its direction and the relay's own words.
        var refused: [(name: String, why: String)] = []

        for name in plan.uploadLogs {
            guard let body = try? Data(contentsOf: changes.appending(path: name)) else { continue }
            // **A log a fold wrote over says so.** The relay's rule is that a
            // log may only ever grow, and this is its own documented exception
            // — asked for by name, never assumed. Ref 192.
            let address = plan.rewriteLogs.contains(name)
                ? "\(root)/log/\(name)?rewrite=1"
                : "\(root)/log/\(name)"
            do {
                try await put(body, to: address, word)
                report.sentLogs += 1
            } catch {
                // **A 409 is worth one more question.** It is the relay saying
                // this body does not begin with what it already holds, and
                // that has two completely different causes: our copy is behind
                // the relay's (nothing wrong — the writer will push the rest),
                // or the two have genuinely parted company under one name,
                // which is somebody's work at risk and needs a person.
                //
                // The message could not tell them apart, so it read as a
                // catastrophe every time. One extra request, only on a 409,
                // and only for the log that was actually refused.
                var why = "could not send it — \(error.localizedDescription)"
                if case Trouble.refused(409) = error {
                    why += " " + (await compare(name, ours: body, root: root, word: word))
                }
                refused.append((name, why))
            }
        }
        for name in plan.downloadLogs {
            let body: Data
            do {
                body = try await data(at: "\(root)/log/\(name)", word)
            } catch {
                refused.append((name, "could not fetch it — \(error.localizedDescription)"))
                continue
            }
            try? FileManager.default.createDirectory(at: changes, withIntermediateDirectories: true)
            // Written whole and swapped into place, so nothing on this machine
            // can read half a log — the rule saving already follows.
            try? body.write(to: changes.appending(path: name), options: .atomic)
            report.receivedLogs += 1
        }

        // **The manifest last of the small things.** It is the one file here
        // rewritten rather than appended to, so sending it after the logs means
        // the relay's copy is never newer than the changes that explain it.
        if let body = try? Data(contentsOf: path.appending(path: manifestFile)) {
            try? await put(body, to: "\(root)/manifest", word)
        }

        // The relay holds the film now, whether it did before or we just sent
        // it — from here on, finding it empty means somebody took it off.
        if held > 0 || report.sentLogs > 0 { markSynced(at: path) }

        if let first = refused.first {
            throw Trouble.stuck(
                refused.count == 1
                    ? "\(first.name): \(first.why)"
                    : "\(refused.count) files would not move. \(first.name): \(first.why)")
        }
        return report
    }

    /// **The pictures, after the merge.**
    ///
    /// Asked second and on purpose: which pictures this device wants depends on
    /// what the list now says, and the list only says it once the logs have
    /// been taken in. Asked before the merge, a photograph attached on the
    /// phone this morning would not be fetched until the sync after next. This
    /// matters more on a phone than anywhere — he is usually on the worse
    /// connection of the two.
    static func syncMedia(engine: Engine, path: URL) async throws -> Report {
        let (root, word) = try where_(path)
        guard let (plan, listing, _) = try await plan(engine: engine, at: path, root: root, word: word) else {
            throw Trouble.unreachable("The relay's answer could not be read.")
        }

        var report = Report()
        let proxies = path.appending(path: proxiesDir)

        for name in plan.uploadMedia {
            guard let body = try? Data(contentsOf: proxies.appending(path: name)) else { continue }
            try await put(body, to: "\(root)/media/\(name)", word)
            report.sentMedia += 1
        }
        if !plan.downloadMedia.isEmpty {
            try? FileManager.default.createDirectory(at: proxies, withIntermediateDirectories: true)
        }
        for name in plan.downloadMedia {
            let body = try await data(at: "\(root)/media/\(name)", word)
            try? body.write(to: proxies.appending(path: name), options: .atomic)
            report.receivedMedia += 1
        }
        report.tidied = await tidy(engine: engine, root: root, word: word, listing: listing)
        return report
    }

    /// **Files the relay holds that the film no longer names, taken away.**
    /// 2026-09-15.
    ///
    /// The relay was the one place a superseded file lived for ever: a picture
    /// removed from every shot gives its room back on each device (Ref 192),
    /// and a clip re-encoded smaller leaves its old self behind under the old
    /// name — and neither ever reached the relay, because nothing there asked.
    /// The engine judges (`strays`), from the same listing the plan was made
    /// from; this is only the hand.
    ///
    /// **A week old, or not at all.** A file can land a moment before the log
    /// that names it, and a listing read in that moment would call it a
    /// stray. A week is longer than any device goes between syncs and shorter
    /// than anything worth keeping.
    ///
    /// Quiet on failure: a delete that does not go through is a file that
    /// waits for the next sync, which is nothing.
    private static func tidy(engine: Engine, root: String, word: String, listing: String) async -> Int {
        let strays = engine.strays(media: listing)
        guard !strays.isEmpty else { return 0 }
        struct Listing: Decodable {
            struct Entry: Decodable { var name: String; var uploaded: String? }
            var media: [Entry]
        }
        let when = Dictionary(
            ((try? JSONDecoder().decode(Listing.self, from: Data(listing.utf8)))?.media ?? [])
                .map { ($0.name, $0.uploaded ?? "") },
            uniquingKeysWith: { first, _ in first })
        let settled = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        let old = strays.filter { name in
            guard let stamp = when[name],
                  let landed = iso.date(from: stamp) ?? plain.date(from: stamp) else { return false }
            return landed < settled
        }
        return await clear(
            old,
            held: { await boardsHold(root: root, word: word) },
            delete: { name in (try? await send("DELETE", to: "\(root)/media/\(name)", word)) != nil })
    }

    // ---- what the portal's boards lean on ----------------------------------

    /// **A picture a portal board or page shows is in use** (2026-10-15).
    ///
    /// The film names the pictures its shots and Studio boards show; a picture
    /// put on a portal board (the Dump Board, a look board) is named only by
    /// that board, which lives on the portal's server and not in the film. So
    /// the engine calls it a stray, and a week later the tidy deleted it —
    /// six Call Her Back pictures were due to go on 22 October.
    ///
    /// **The portal is asked before anything goes**, and it answers with the
    /// names it holds on to (`hub/src/boardheld.js`). **If it cannot answer —
    /// offline, an error, an answer that does not read — nothing is deleted
    /// this time.** A tidy that waits a day costs nothing; one that guesses
    /// breaks a board.
    ///
    /// The names are stems (a picture's name without its extension), so a
    /// clip's poster is kept with its clip.
    static func clear(
        _ names: [String],
        held: () async -> Set<String>?,
        delete: (String) async -> Bool
    ) async -> Int {
        guard !names.isEmpty else { return 0 }
        guard let keep = await held() else { return 0 }
        var gone = 0
        for name in names where !keep.contains(stem(of: name)) {
            if await delete(name) { gone += 1 }
        }
        return gone
    }

    /// A file's name without its extension: `<32 hex>.jpg` -> `<32 hex>`.
    static func stem(of name: String) -> String {
        name.split(separator: ".", maxSplits: 1).first.map(String.init) ?? name
    }

    /// The portal's address for a relay's: `sync.` turned to `mcp.`, the way
    /// every other call from the apps to it is made. A checking run may hand
    /// one in (`PortalURL`).
    static func hubAddress(forRelay relay: String) -> String? {
        if let set = UserDefaults.standard.string(forKey: "PortalURL"), !set.isEmpty {
            return set.hasSuffix("/") ? String(set.dropLast()) : set
        }
        guard var parts = URLComponents(string: relay.hasPrefix("http") ? relay : "https://" + relay),
              let host = parts.host else { return nil }
        parts.host = host.hasPrefix("sync.") ? "mcp." + host.dropFirst(5) : host
        parts.path = ""
        parts.scheme = "https"
        return parts.string
    }

    /// Read the portal's answer: the stems it holds on to, or nil for
    /// anything that is not a whole, successful answer.
    static func heldStems(in answer: Data) -> Set<String>? {
        struct Held: Decodable { var ok: Bool?; var scanned: Int?; var stems: [String]? }
        guard let got = try? JSONDecoder().decode(Held.self, from: answer),
              got.ok == true, got.scanned != nil, let stems = got.stems else { return nil }
        return Set(stems)
    }

    /// Ask the portal. Nil on any trouble at all.
    private static func boardsHold(root: String, word: String) async -> Set<String>? {
        guard let cut = root.range(of: "/v1/p/") else { return nil }
        let relay = String(root[..<cut.lowerBound])
        let film = String(root[cut.upperBound...])
        guard !film.isEmpty, let hub = hubAddress(forRelay: relay),
              var ask = request("\(hub)/console/studio/held/\(film)", word) else { return nil }
        ask.timeoutInterval = 30
        guard let (body, reply) = try? await URLSession.shared.data(for: ask),
              (reply as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return heldStems(in: body)
    }

    /// **These files, off the relay now.** For the pass that has just replaced
    /// a clip and holds the names of what it superseded — no week's wait, the
    /// engine has already renamed the record and every device takes logs
    /// before it takes pictures.
    static func forget(_ names: [String], path: URL) async -> Int {
        guard let (root, word) = try? where_(path) else { return 0 }
        return await clear(
            names,
            held: { await boardsHold(root: root, word: word) },
            delete: { name in (try? await send("DELETE", to: "\(root)/media/\(name)", word)) != nil })
    }

    /// **How many photographs are waiting to go up — asked, not sent.**
    ///
    /// The same plan `syncMedia` works from, read for its length and thrown
    /// away. Two small requests; nothing large moves. This is what lets the app
    /// say *20 pictures not sent* on a beat without shipping twenty pictures on
    /// that beat — the decision of 2026-08-31 stands, and stops being silent.
    static func picturesWaiting(engine: Engine, path: URL) async throws -> Int {
        let (root, word) = try where_(path)
        guard let (plan, _, _) = try await plan(engine: engine, at: path, root: root, word: word) else { return 0 }
        return plan.uploadMedia.count
    }

    // ---- taking a film off the relay ---------------------------------------

    /// **Everything the relay is holding for this film that this device is not.**
    ///
    /// The one thing that has to happen before a film comes off the relay, and
    /// the reason archiving is not simply a delete. Two of his own films are
    /// already known to differ in this direction — a picture that reached the
    /// relay from the phone and never reached the Mac — so taking a film off
    /// without asking for those first would destroy the only copy of them.
    ///
    /// **It does not ask the engine.** `syncplan` decides what this device
    /// *wants*, which is the right question for a sync and the wrong one here:
    /// a picture nothing points at any more is still a picture, and this is the
    /// last moment anybody could keep it. So it compares the relay's own two
    /// listings against the two folders on disk and takes the difference,
    /// whatever it turns out to be.
    ///
    /// Returns what it actually brought down, so a screen can say so.
    @discardableResult
    static func pullEverything(at path: URL) async throws -> (logs: Int, media: Int) {
        guard let (root, word) = try onTheRelay(path) else { return (0, 0) }
        let manager = FileManager.default

        struct Listing: Decodable {
            struct Log: Decodable { var name: String }
            var logs: [Log]
        }
        struct Pictures: Decodable {
            struct Picture: Decodable { var name: String }
            var media: [Picture]
        }

        var brought = (logs: 0, media: 0)

        let changes = path.appending(path: changesDir)
        let here = Set((try? manager.contentsOfDirectory(atPath: changes.path)) ?? [])
        let there = try JSONDecoder().decode(
            Listing.self, from: try await data(at: "\(root)/state", word))
        for log in there.logs where !here.contains(log.name) {
            let body = try await data(at: "\(root)/log/\(log.name)", word)
            try? manager.createDirectory(at: changes, withIntermediateDirectories: true)
            try? body.write(to: changes.appending(path: log.name), options: .atomic)
            brought.logs += 1
        }

        let proxies = path.appending(path: proxiesDir)
        let hereToo = Set((try? manager.contentsOfDirectory(atPath: proxies.path)) ?? [])
        let pictures = try JSONDecoder().decode(
            Pictures.self, from: try await data(at: "\(root)/media", word))
        for picture in pictures.media where !hereToo.contains(picture.name) {
            let body = try await data(at: "\(root)/media/\(picture.name)", word)
            try? manager.createDirectory(at: proxies, withIntermediateDirectories: true)
            try? body.write(to: proxies.appending(path: picture.name), options: .atomic)
            brought.media += 1
        }

        return brought
    }

    /// **The film, off the relay, whole.**
    ///
    /// One request, by prefix, so nothing is left behind — the relay grew the
    /// route for exactly this. Taking a film off by its pieces left the
    /// portal's own `front.json` sitting beside them, and 268 bytes was enough
    /// to keep the film in the list and draw it on the Projects screen as if it
    /// had never gone. 2026-09-04.
    ///
    /// **A film that was never on the relay is not an error.** Archiving one
    /// should not fail because it happens to have been made this morning.
    ///
    /// **With why**, since 2026-09-16: the relay keeps the fate beside the
    /// films, and every other device's next sync does the same to its copy.
    @discardableResult
    static func removeFilm(at path: URL, fate: Fate) async throws -> Int {
        guard let (root, word) = try onTheRelay(path) else { return 0 }
        struct Gone: Decodable { var gone: Int }
        let said = try await send("DELETE", to: "\(root)?fate=\(fate.rawValue)", word)
        return (try? JSONDecoder().decode(Gone.self, from: said))?.gone ?? 0
    }

    /// **The same, saying what the relay set aside.** Since 2026-10-04 the
    /// relay copies the portal's own files (invites, links, What Viewers See,
    /// pages) to `kept/<film>/<time>/` before it takes a film off, and says
    /// where and how many. The Projects Console's archive door reports that,
    /// so the one place the portal went is written down where he can see it.
    static func removeFilmSaying(at path: URL, fate: Fate) async throws
        -> (gone: Int, keptAt: String, keptFiles: Int) {
        guard let (root, word) = try onTheRelay(path) else { return (0, "", 0) }
        struct Kept: Decodable { var at: String?; var files: Int? }
        struct Gone: Decodable { var gone: Int?; var kept: Kept? }
        let said = try await send("DELETE", to: "\(root)?fate=\(fate.rawValue)", word)
        let read = try? JSONDecoder().decode(Gone.self, from: said)
        return (read?.gone ?? 0, read?.kept?.at ?? "", read?.kept?.files ?? 0)
    }

    /// **What this device holds that the relay does not — asked, not sent.**
    ///
    /// The engine's own plan, read for its two outgoing lists and thrown away:
    /// a log or a picture named here would be lost to every other device if
    /// the film came off the relay now. The archive door asks this after
    /// sending everything it can, and refuses while either list is not empty.
    /// Throws `gone` like a sync does when the relay no longer holds the film.
    static func unsent(engine: Engine, path: URL) async throws -> (logs: [String], media: [String]) {
        let (root, word) = try where_(path)
        guard let (plan, _, _) = try await plan(engine: engine, at: path, root: root, word: word) else {
            throw Trouble.unreachable("The relay's answer could not be read.")
        }
        return (plan.uploadLogs, plan.uploadMedia)
    }

    /// Where this film lives on the relay — or nil, if it has never been there.
    ///
    /// The difference from `where_` is the one that matters to archiving:
    /// `where_` *makes* an identity when there is none, which is right for a
    /// sync and wrong for taking something off. A film with no `remote.json`
    /// has nothing on the relay, and inventing a name for it so it can be
    /// deleted is a way of writing to the relay while removing from it.
    private static func onTheRelay(_ path: URL) throws -> (root: String, word: String)? {
        // A film that has never been on the relay is asked nothing, whether
        // or not this device could ask — archiving one on a phone without
        // sync used to stop at "sync is not set up" (2026-09-16).
        guard let id = projectId(at: path) else { return nil }
        guard let base = device.address(path), let word = device.token() else { throw Trouble.notSetUp }
        return ("\(base)/v1/p/\(id)", word)
    }

    /// Where this film's pictures can be fetched from without a password.
    ///
    /// **The one address Shotlister ever hands to somebody else's computer.**
    /// A frame in the exported spreadsheet is written as an `IMAGE()` formula
    /// so that it belongs to its cell and travels when he sorts — and it is
    /// Google's own servers that go and fetch it. They cannot be given his
    /// token, and Sheets refuses a picture carried inside the formula ("is not
    /// a valid url", measured 2026-09-04). So the address itself is the
    /// permission: the relay's `/i/` route answers for one exact picture name
    /// and nothing else, and that name is the picture's own hash — unguessable
    /// rather than merely unlisted.
    ///
    /// **`making: false`, deliberately.** Exporting a spreadsheet must never be
    /// the thing that quietly signs a film up to the relay. No identity yet
    /// means no address, which means the frames are carried inside the file the
    /// way they always were.
    static func picturesAt(_ path: URL) -> String? {
        guard let base = device.address(path), let id = projectId(at: path) else { return nil }
        return "\(base)/i/\(id)"
    }

    /// **Why the relay would not take this log, in one sentence.**
    ///
    /// Asked only after a 409, because it costs a fetch. A log may only ever
    /// grow and has exactly one writer, so there are only three answers and
    /// they want three different reactions:
    ///
    /// - **ours is behind** — the writer has pushed more than this device has
    ///   seen. Nothing is wrong and nothing needs doing; this device should
    ///   simply stop offering it.
    /// - **they part company at a byte** — two different streams under one
    ///   name. That is the serious one: somebody's work exists in two versions
    ///   and only a person can say which.
    /// - **the relay would not say** — the question itself failed.
    private static func compare(_ name: String, ours: Data, root: String, word: String) async -> String {
        guard let theirs = try? await data(at: "\(root)/log/\(name)", word) else {
            return "The relay would not say what it is holding."
        }
        let at = firstDifference(ours, theirs)
        let shorter = min(ours.count, theirs.count)
        let mine = device.name.prefix(1).uppercased() + device.name.dropFirst()
        if at == shorter {
            return ours.count < theirs.count
                ? "\(mine)'s copy is \(ours.count) bytes and the relay's is \(theirs.count) — ours is behind, not different. Nothing is lost."
                : "\(mine)'s copy is \(ours.count) bytes and the relay's is \(theirs.count), and one is the start of the other."
        }
        return "They part company at byte \(at) — \(device.name) has \(ours.count) bytes, the relay \(theirs.count). Two versions of one log; keep both until somebody decides."
    }

    /// Where two copies of a log stop agreeing — the length of the shorter when
    /// one is the start of the other.
    private static func firstDifference(_ ours: Data, _ theirs: Data) -> Int {
        let shorter = min(ours.count, theirs.count)
        var at = 0
        while at < shorter, ours[ours.startIndex + at] == theirs[theirs.startIndex + at] {
            at += 1
        }
        return at
    }

    // ---- telling the two copies apart --------------------------------------

    /// **Every log this device holds beside every log the relay holds, and
    /// where they stop agreeing.** Read-only; it writes nothing, anywhere.
    ///
    /// Built 2026-09-08 because the app's own report of a stuck sync — *"one
    /// file would not move"* — cannot say which way it was going. `syncLogs`
    /// files a refusal into the same list whether an upload was rejected or a
    /// download failed, so the message is the same for two opposite faults, and
    /// guessing between them is how somebody ends up overwriting a log.
    ///
    /// **Neither the relay's password nor a log's contents leave this method.**
    /// It reports names, lengths and the offset where two copies first differ.
    /// A change log is his work; an offset is a fact about it.
    static func auditLogs(at path: URL) async -> String {
        var out: [String] = []
        let root: String, word: String
        do { (root, word) = try where_(path) } catch {
            return "audit: sync is not set up on \(device.name)."
        }

        struct Listing: Decodable {
            struct One: Decodable { var name: String; var size: Int }
            var logs: [One]
        }
        let state: String
        do { state = try await text(at: "\(root)/state", word) } catch {
            return "audit: the relay would not answer — \(error.localizedDescription)"
        }
        guard let listing = try? JSONDecoder().decode(Listing.self, from: Data(state.utf8)) else {
            return "audit: the relay's answer could not be read."
        }

        var there: [String: Int] = [:]
        for one in listing.logs where one.name.hasSuffix(".log") { there[one.name] = one.size }

        let changes = path.appending(path: changesDir)
        var here: [String: Int] = [:]
        for name in (try? FileManager.default.contentsOfDirectory(atPath: changes.path)) ?? [] {
            guard name.hasSuffix(".log") else { continue }
            let size = (try? FileManager.default
                .attributesOfItem(atPath: changes.appending(path: name).path)[.size]) as? Int
            here[name] = size ?? 0
        }

        out.append("audit: \(here.count) logs here, \(there.count) on the relay")

        for name in Set(here.keys).union(there.keys).sorted() {
            switch (here[name], there[name]) {
            case let (mine?, nil):
                out.append("only here    \(mine)\t\(name)")
            case let (nil, theirs?):
                out.append("only relay   \(theirs)\t\(name)")
            case let (mine?, theirs?) where mine == theirs:
                out.append("same size    \(mine)\t\(name)")
            case let (mine?, theirs?):
                // **The only case worth bytes.** A log may only ever grow, so
                // the honest question is whether the shorter one is the start
                // of the longer. If it is, this is nothing but a transfer that
                // has not happened yet. If it is not, the two have genuinely
                // parted company and *that* is the thing worth a person's
                // attention.
                let word_ = mine > theirs ? "here longer " : "relay longer"
                guard let ours = try? Data(contentsOf: changes.appending(path: name)),
                      let theirsBody = try? await data(at: "\(root)/log/\(name)", word) else {
                    out.append("\(word_) \(mine) vs \(theirs)\t\(name)\t(could not read both)")
                    continue
                }
                let at = firstDifference(ours, theirsBody)
                out.append(at == min(ours.count, theirsBody.count)
                    ? "\(word_) \(mine) vs \(theirs)\t\(name)\tone is the start of the other — a transfer, not a split"
                    : "\(word_) \(mine) vs \(theirs)\t\(name)\tDIVERGE at byte \(at)")
            case (nil, nil):
                continue
            }
        }
        return out.joined(separator: "\n")
    }

    /// Where this film lives on the relay, and the word that gets in.
    private static func where_(_ path: URL) throws -> (root: String, word: String) {
        guard let base = device.address(path), let word = device.token() else { throw Trouble.notSetUp }
        guard let id = projectId(at: path, making: true) else { throw Trouble.notSetUp }
        return ("\(base)/v1/p/\(id)", word)
    }

    /// The engine's plan, and the media listing it was made from — kept beside
    /// it so the tidy that follows judges the same moment rather than asking
    /// again.
    ///
    /// **And the one refusal that belongs here, before anything moves.** The
    /// relay keeps no memory of a film it has let go; its answer for one is
    /// an empty listing, the same answer a film made this morning gets. The
    /// difference is on this device — `Link.synced` — and a film that was on
    /// the relay and is not now was archived or deleted elsewhere. Sending it
    /// up would put it back, which is exactly the fault (Ref 1033). So the
    /// plan is refused, both for the logs and for the pictures, and the app
    /// decides what to offer him.
    private static func plan(engine: Engine, at path: URL, root: String, word: String) async throws
        -> (Engine.SyncPlan, String, Int)? {
        let state = try await text(at: "\(root)/state", word)
        let media = try await text(at: "\(root)/media", word)
        let held = logsHeld(in: state)
        if let fate = fateSaid(in: state) { throw Trouble.gone(fate) }
        if letGo(state: state, at: path) { throw Trouble.gone(nil) }
        guard let plan = engine.syncPlan(state: state, media: media) else { return nil }
        return (plan, media, held)
    }

    /// How many logs the relay's `state` answer lists.
    static func logsHeld(in state: String) -> Int {
        struct Held: Decodable {
            struct Log: Decodable { var name: String }
            var logs: [Log]
        }
        return (try? JSONDecoder().decode(Held.self, from: Data(state.utf8)))?.logs.count ?? 0
    }

    /// **Ask this one film's own relay whether it still holds it.** Read
    /// from the film's own link, so a film is never judged against a relay
    /// that is not its own. `nil` when the relay cannot be reached or the
    /// film was never there — neither is a fate. Otherwise the fate: the
    /// relay's note when it left one, `archived` when it holds nothing and
    /// this device once synced the film (taken off before notes existed).
    static func fate(at path: URL) async -> Fate? {
        guard wasOnTheRelay(at: path), let (root, word) = try? onTheRelay(path) else { return nil }
        guard let state = try? await text(at: "\(root)/state", word) else { return nil }
        if let said = fateSaid(in: state) { return said }
        return logsHeld(in: state) == 0 ? .archived : nil
    }

    /// The relay's own note, when its `state` answer carries one.
    static func fateSaid(in state: String) -> Fate? {
        struct Said: Decodable { var gone: String? }
        return (try? JSONDecoder().decode(Said.self, from: Data(state.utf8)))?.gone.flatMap(Fate.init)
    }

    /// **The decision on its own**, so a check can make it without a relay:
    /// the relay holds nothing under the film's name, and this device knows
    /// it once did.
    static func letGo(state: String, at path: URL) -> Bool {
        logsHeld(in: state) == 0 && wasOnTheRelay(at: path)
    }

    // ---- films the relay holds that this device may not ---------------------

    /// A film on the relay, as the *Open from relay* list draws it.
    struct Film: Identifiable, Hashable {
        var id: String { project }
        var project: String
        var title: String
        var logs: Int
        var bytes: Int
        /// **The film's own icon and colour**, as its manifest says — so a film
        /// this device has never downloaded still draws itself correctly in the
        /// switcher. Empty for a film with no mark, or one whose manifest was
        /// written before a film carried one. The Mac turns the pair into a
        /// `Console.Mark`; the phone does not draw one yet.
        var markPath: String = ""
        var markColour: String = ""
        /// The relay's note that this film was taken off, and why. A row with
        /// one holds nothing to fetch; it is here so a device that still has
        /// a copy can follow the fate.
        var gone: Fate? = nil

        init(project: String, title: String, logs: Int, bytes: Int,
             markPath: String = "", markColour: String = "", gone: Fate? = nil) {
            self.project = project
            self.title = title
            self.logs = logs
            self.bytes = bytes
            self.markPath = markPath
            self.markColour = markColour
            self.gone = gone
        }
    }

    /// **Everything the relay is holding.**
    ///
    /// `/v1/projects` knows a film's identity and its size but not what it is
    /// called — the name lives in the film's own manifest, which is the same
    /// file the app reads locally. So this asks for both: the list, then one
    /// manifest per film for its title.
    static func films() async throws -> [Film] {
        let (base, word) = try whereRelay()
        struct Listing: Decodable {
            struct Row: Decodable {
                var project: String
                var logs: Int?
                var bytes: Int?
                var gone: String?
            }
            var projects: [Row]
        }
        struct Manifest: Decodable {
            var title: String?
            /// Written beside the title since 2026-09-11, so the pair can be
            /// read without downloading a film. Absent in every manifest older
            /// than that, which reads as no mark.
            var markPath: String?
            var markColour: String?
        }

        let listing = try JSONDecoder().decode(
            Listing.self, from: try await data(at: "\(base)/v1/projects", word))
        var films: [Film] = []
        for row in listing.projects {
            // A film the relay only remembers: nothing to fetch, one fact.
            if let fate = row.gone.flatMap(Fate.init) {
                films.append(Film(project: row.project, title: String(row.project.prefix(8)),
                                  logs: 0, bytes: 0, gone: fate))
                continue
            }
            // A film whose manifest will not come back is still a film. It is
            // named after its identity rather than left out, because a list
            // that silently drops one is worse than a list with an ugly name
            // in it — he would have no way to know it was there.
            let manifest = (try? await data(at: "\(base)/v1/p/\(row.project)/manifest", word))
                .flatMap { try? JSONDecoder().decode(Manifest.self, from: $0) }
            // **Leftovers are not a film** (2026-10-17). A project deleted from
            // the console can leave a few portal files behind under its old id
            // (a front page, cover pictures) and nothing else: no manifest, no
            // change logs. Listed, it drew a nameless project on every Mac and
            // iPhone that could not be opened or deleted. No manifest and no
            // logs is nothing to fetch, so it is left out. The relay says the
            // same since the same day; this is for a relay not yet updated.
            if manifest == nil && (row.logs ?? 0) == 0 { continue }
            let title = manifest?.title
            films.append(Film(project: row.project,
                              title: (title?.isEmpty == false ? title! : String(row.project.prefix(8))),
                              logs: row.logs ?? 0,
                              bytes: row.bytes ?? 0,
                              markPath: manifest?.markPath ?? "",
                              markColour: manifest?.markColour ?? ""))
        }
        return films.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// **Build a film's folder from nothing.** The Swift twin of
    /// `remote::courier::clone_project`, and the thing that lets iCloud go:
    /// until now a film reached a second device because iCloud put the folder
    /// there, and the relay only ever topped it up. This puts one somewhere new.
    ///
    /// **The list only.** Everything needed to *open* a film is here — the
    /// manifest that says what it is, and every change log. Photographs are the
    /// hundred megabytes and they come afterwards, on the same button as
    /// always, so a film opens on a bad connection in seconds rather than never.
    ///
    /// **Built beside and moved into place**, so a clone interrupted halfway
    /// leaves no half a film behind for somebody to open next week. And it
    /// refuses to write over a folder that already exists: cloning on top of a
    /// film somebody has been working in is not a thing anybody means to do,
    /// and the local copy may hold changes the relay has never seen.
    static func clone(_ film: Film, into folder: URL) async throws -> URL {
        let (base, word) = try whereRelay()
        let manager = FileManager.default
        let destination = folder.appending(path: "\(safeName(film.title)).shotlist")
        guard !manager.fileExists(atPath: destination.path) else {
            throw Trouble.alreadyHere(destination.lastPathComponent)
        }

        // Beside the destination rather than in a temporary folder, so the move
        // into place is a rename on one volume and cannot half-copy.
        let building = folder.appending(path: ".shotlister-arriving-\(film.project)")
        try? manager.removeItem(at: building)
        try manager.createDirectory(at: building.appending(path: changesDir),
                                    withIntermediateDirectories: true)

        do {
            let root = "\(base)/v1/p/\(film.project)"
            let manifest = try await data(at: "\(root)/manifest", word)
            try manifest.write(to: building.appending(path: manifestFile), options: .atomic)

            struct State: Decodable {
                struct Log: Decodable { var name: String }
                var logs: [Log]
            }
            let state = try JSONDecoder().decode(
                State.self, from: try await data(at: "\(root)/state", word))
            // **Six at a time, not one after another.** A film is a hundred-odd
            // change logs and each is its own request; fetched in single file
            // that is the better part of a minute before anything appears,
            // which is precisely the wait he moved off iCloud to escape. Six is
            // a polite number for one small server and turns it into seconds.
            let changes = building.appending(path: changesDir)
            var queue = state.logs.map(\.name)[...]
            while !queue.isEmpty {
                let batch = queue.prefix(6)
                queue = queue.dropFirst(6)
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for name in batch {
                        group.addTask {
                            let body = try await data(at: "\(root)/log/\(name)", word)
                            try body.write(to: changes.appending(path: name), options: .atomic)
                        }
                    }
                    try await group.waitForAll()
                }
            }

            // **Written here rather than on the first sync.** The film has to
            // arrive already knowing which relay it came from, or the device
            // that just fetched it would have to be told all over again.
            let link = Link(relay: base, project: film.project, synced: true)
            try JSONEncoder().encode(link)
                .write(to: building.appending(path: linkFile), options: .atomic)

            try manager.moveItem(at: building, to: destination)
            return destination
        } catch {
            // Nothing half-built is left where a person could find it.
            try? manager.removeItem(at: building)
            throw error
        }
    }

    /// A title as a folder name. The same two characters a Mac will not have.
    private static func safeName(_ title: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    /// The relay itself, with no film in hand — which is the whole point here:
    /// this is used before the film exists on this device.
    private static func whereRelay() throws -> (base: String, word: String) {
        guard let base = device.address(nil), let word = device.token() else { throw Trouble.notSetUp }
        return (base, word)
    }

    // ---- the plumbing ------------------------------------------------------

    /// Internal rather than private since 2026-09-29: `Offload` asks the relay
    /// for one picture's fingerprint with a header of its own, and building
    /// the request anywhere but here is how two ideas of a request start.
    static func request(_ url: String, _ word: String) -> URLRequest? {
        guard let real = URL(string: url) else { return nil }
        var ask = URLRequest(url: real)
        ask.setValue("Bearer \(word)", forHTTPHeaderField: "Authorization")
        ask.timeoutInterval = 30
        return ask
    }

    /// Internal rather than private: each app's `check` asks the relay one
    /// question with an address and a word that are not saved yet.
    static func data(at url: String, _ word: String) async throws -> Data {
        guard let ask = request(url, word) else { throw Trouble.unreachable("Bad address.") }
        do {
            let (body, reply) = try await URLSession.shared.data(for: ask)
            let code = (reply as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else { throw Trouble.refused(code) }
            return body
        } catch let trouble as Trouble {
            throw trouble
        } catch {
            throw Trouble.unreachable(error.localizedDescription)
        }
    }

    static func text(at url: String, _ word: String) async throws -> String {
        String(data: try await data(at: url, word), encoding: .utf8) ?? ""
    }

    /// A request with no body that hands back the answer. `DELETE` is the only
    /// caller today; it is spelled generally because writing a second one of
    /// these for the next verb is how two ideas of a request start.
    static func send(_ method: String, to url: String, _ word: String) async throws -> Data {
        guard var ask = request(url, word) else { throw Trouble.unreachable("Bad address.") }
        ask.httpMethod = method
        do {
            let (body, reply) = try await URLSession.shared.data(for: ask)
            let code = (reply as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else { throw Trouble.refused(code) }
            return body
        } catch let trouble as Trouble {
            throw trouble
        } catch {
            throw Trouble.unreachable(error.localizedDescription)
        }
    }

    private static func put(_ body: Data, to url: String, _ word: String) async throws {
        guard var ask = request(url, word) else { throw Trouble.unreachable("Bad address.") }
        ask.httpMethod = "PUT"
        ask.httpBody = body
        do {
            let (_, reply) = try await URLSession.shared.data(for: ask)
            let code = (reply as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else { throw Trouble.refused(code) }
        } catch let trouble as Trouble {
            throw trouble
        } catch {
            throw Trouble.unreachable(error.localizedDescription)
        }
    }
}
