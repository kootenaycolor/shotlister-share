import AppKit
import Foundation

/// **His Projects Console, read from the outside.**
///
/// `~/Developer/projects-console` is the window over every project he has —
/// status, shoot dates, the drives holding the media, and a door to each one's
/// Notion page and Google Drive folder. A Shotlister project that knows which
/// console project it *is* can stop asking: a mood board, a location's
/// photographs, a wrap ritual all already have a folder to go to.
///
/// **Read from its cache file, not from its server.** The console keeps
/// `projects-cache.json` beside its state so it can still draw a project list
/// during a Notion outage, and that file is exactly what is wanted here: no
/// second app has to be running, nothing is asked of the network, and the
/// answer is the same one the console itself would give. If it is missing —
/// the console has never run on this Mac — the list is simply empty and the
/// link is not offered. Nothing here writes to it.
enum Console {
    /// **The film's own icon and colour**, and the only two things about a
    /// Notion icon anybody here needs: the outline to draw, and the colour to
    /// draw it in.
    ///
    /// The same two the website wears. `hub/refresh.py` fetches the icon from
    /// Notion and keeps exactly this pair; the console's cache already holds
    /// the whole drawing, so the Mac takes the pair out of that instead and
    /// asks nothing of the network.
    struct Mark: Hashable {
        var path: String
        var colour: String
    }

    /// One credit and its people, in the record's order.
    struct Credit: Hashable {
        var role: String
        var people: [String]
        /// "A", "A & B", "A, B & C" — the console's `credits.line`.
        var line: String {
            let names = people.filter { !$0.isEmpty }
            guard names.count > 2, let last = names.last else { return names.joined(separator: " & ") }
            return names.dropLast().joined(separator: ", ") + " & " + last
        }
    }

    /// The credits a project shows beyond its director and producer (which
    /// the film itself carries), less any it hides. Empty when the console's
    /// cache does not say.
    static func otherCredits(page: String) -> [Credit] {
        guard let project = project(page: page) else { return [] }
        let lines = ["Executive Producer": "executive_producer", "Line Producer": "line_producer"]
        return project.credits.filter { credit in
            credit.role != "Director" && credit.role != "Producer" && !credit.people.isEmpty
                && !project.hidden.contains("credit:\(credit.role)")
                && !project.hidden.contains(lines[credit.role] ?? "")
        }
    }

    static func project(page: String) -> Project? {
        guard !page.isEmpty else { return nil }
        let bare = page.replacingOccurrences(of: "-", with: "").lowercased()
        return projects().first {
            $0.pageId.replacingOccurrences(of: "-", with: "").lowercased() == bare || $0.cardIds.contains(bare)
        }
    }

    struct Project: Identifiable, Hashable {
        var pageId: String
        var name: String
        var status: String
        var kind: String
        var dates: String
        var driveUrl: String
        var notionUrl: String
        /// The whole drawing, as the console cached it off Notion. Empty for a
        /// project whose row carries no icon.
        var iconSvg: String
        /// The Notion palette colour on the row — the fallback, not the first
        /// choice. See `mark`.
        var iconColour: String
        /// The logline, when the console's cache carries one — the project
        /// record's, laid over the Notion row on the Mac that runs the
        /// console. Empty otherwise.
        var logline: String = ""
        /// **Every credit the record holds** (2026-10-05, more than one per
        /// title), and what the project hides — both laid onto the cache by
        /// the console (record.py `_overlay_owned`). Empty from an older one.
        var credits: [Credit] = []
        var hidden: [String] = []
        /// **The card's mark**, when this row came from the server's cards
        /// (`ProjectCards`): drawn as it is, no SVG to read.
        var cardMark: Mark? = nil
        /// The ids the card knows this project by (its own, its Notion page,
        /// its film's relay id). Empty for a row off the console's file.
        var cardIds: Set<String> = []
        var id: String { pageId }

        /// "Development · 2 Nov 2026", or as much of it as there is.
        var line: String {
            [status, dates].filter { !$0.isEmpty }.joined(separator: " · ")
        }

        /// **Read out of the drawing, exactly the way the website reads it.**
        ///
        /// `refresh.py` takes the first `d` and the first `fill` out of the SVG
        /// itself — so the colour is Notion's *rendered* one (`#D44C47`) rather
        /// than the paler palette name on the row (`#e03e3e`). Taking the row's
        /// instead would put the Mac a shade off the browser on every film,
        /// which is the one thing this is for. The row's colour is kept only
        /// for an icon that somehow arrives without a fill of its own.
        var mark: Mark? {
            if let cardMark { return cardMark }
            guard let outline = attribute(" d", in: iconSvg), !outline.isEmpty else { return nil }
            let colour = attribute("fill", in: iconSvg) ?? iconColour
            guard colour.count == 7, colour.hasPrefix("#"),
                  colour.dropFirst().allSatisfy(\.isHexDigit) else { return nil }
            return Mark(path: outline, colour: colour.uppercased())
        }
    }

    /// The value of one attribute in the drawing, or nothing.
    ///
    /// **Plain scanning rather than a pattern**, because this is one attribute
    /// out of a string we already hold and a regular expression here would be a
    /// second way of reading a file that has one. The leading space in `" d"`
    /// is what keeps it off the `d` inside `id`.
    private static func attribute(_ name: String, in svg: String) -> String? {
        guard let opens = svg.range(of: "\(name)=\"") else { return nil }
        let rest = svg[opens.upperBound...]
        guard let shuts = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<shuts])
    }

    /// **The mark for one film**, by the console project it is linked to.
    ///
    /// **And by name when it is linked to nothing**, which is deliberate and is
    /// how his own films behave: a `Daybreak.shotlist` beside a Notion project
    /// called *Daybreak* is the same film, and making him press a button in
    /// Project Settings before the app will wear its colour would be a chore
    /// with an obvious right answer. The written link always wins where there
    /// is one.
    static func mark(page: String, named: String) -> Mark? {
        let all = projects()
        let bare = ProjectCards.bare(page)
        if !page.isEmpty, let one = all.first(where: { ProjectCards.bare($0.pageId) == bare || $0.cardIds.contains(bare) }) {
            return one.mark
        }
        guard !named.isEmpty else { return nil }
        return all.first { $0.name.caseInsensitiveCompare(named) == .orderedSame }?.mark
    }

    /// **Change in Console** — his Projects Console, opened on this film's
    /// project. **Through the server** while Studio reads the card (stage 5
    /// step 4): the request waits there for this Mac's console, which takes it
    /// when it comes to the front. Off, or with the server out of reach, the
    /// console's own deep-link door on this Mac: `open-request.json` beside
    /// its state, picked up and cleared. `action` `archive` or `delete` opens
    /// the project's own Archive or Delete, behind the console's previews and
    /// confirmations. A checking run says what it would have asked and opens
    /// nothing.
    static func openProject(page: String, action: String = "") {
        if Launch.checking {
            let route = ProjectCards.shared.on ? "server" : "file"
            FileHandle.standardError.write(Data("console: open project \"\(page)\"\(action.isEmpty ? "" : " " + action) via \(route)\n".utf8))
            return
        }
        // A film made under a minted ID has no console page of its own: the
        // open film's card says which project it is.
        let card = ProjectCards.shared.card(page: page)
            ?? ProjectCards.shared.card(film: ShellState.shared.projectPath.flatMap { Relay.projectId(at: $0) })
        let wanted = card?.consolePage ?? page
        let app = URL(fileURLWithPath: "/Applications/Projects Console.app")
        Task { @MainActor in
            var sent = false
            if ProjectCards.shared.on {
                sent = await ProjectCards.askConsole(page: wanted, id: card?.id ?? page, action: action)
            }
            if !sent {
                var request: [String: String] = ["type": "project", "page": wanted]
                if !action.isEmpty { request["action"] = action }
                let flag = cacheFile.deletingLastPathComponent().appendingPathComponent("open-request.json")
                if let bytes = try? JSONSerialization.data(withJSONObject: request) {
                    try? bytes.write(to: flag, options: .atomic)
                }
            }
            _ = try? await NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// The project's logline, by its page, or empty.
    static func logline(page: String) -> String {
        guard !page.isEmpty else { return "" }
        if let card = ProjectCards.shared.card(page: page) { return card.logline }
        let bare = page.replacingOccurrences(of: "-", with: "").lowercased()
        return projects().first {
            $0.pageId.replacingOccurrences(of: "-", with: "").lowercased() == bare
        }?.logline.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static var cacheFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Developer/.projects-console-state/projects-cache.json")
    }

    /// Every project the console knows about. **Decoded by hand**, forgivingly:
    /// this is another program's file and a field appearing or vanishing there
    /// must not stop a shot list opening.
    static func projects() -> [Project] {
        // **From the server's cards** while Studio reads the card (stage 5
        // step 4), with the copy kept on this Mac offline. A project the
        // server has no card for (The Turning, in an older Notion database) is
        // laid in from the console's file, so none the Mac knows is dropped.
        let cards = ProjectCards.shared.cards
        let file = fromFile()
        guard !cards.isEmpty else { return file }
        let rows = cards.filter { !$0.job }.map(project(from:))
        let known = Set(rows.flatMap { $0.cardIds })
        let missing = file.filter { !known.contains(ProjectCards.bare($0.pageId)) }
        return rows + missing
    }

    /// One card as a row of the project list.
    static func project(from card: ProjectCards.Card) -> Project {
        Project(
            pageId: card.consolePage,
            name: card.name.isEmpty ? (card.facts["title"] ?? "") : card.name,
            status: card.status,
            kind: card.type,
            dates: card.dates,
            driveUrl: card.drive_url,
            notionUrl: card.notion_url,
            iconSvg: "",
            iconColour: card.mark?.colour ?? "",
            logline: card.logline,
            credits: card.credits.map { Credit(role: $0.role, people: $0.people) },
            hidden: card.hidden,
            cardMark: card.mark.map { Mark(path: $0.path, colour: $0.colour.uppercased()) },
            cardIds: card.ids)
    }

    /// Every project in the console's own cache file — the list before the
    /// cards, and the fallback beside them.
    static func fromFile() -> [Project] {
        guard let bytes = try? Data(contentsOf: cacheFile),
              let top = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let rows = top["projects"] as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let id = row["page_id"] as? String, !id.isEmpty,
                  let name = row["name"] as? String, !name.isEmpty else { return nil }
            return Project(
                pageId: id,
                name: name,
                status: row["status"] as? String ?? "",
                kind: row["type"] as? String ?? "",
                dates: row["dates"] as? String ?? "",
                driveUrl: row["drive_url"] as? String ?? "",
                notionUrl: row["notion_url"] as? String ?? "",
                iconSvg: row["icon_svg"] as? String ?? "",
                iconColour: row["icon_color"] as? String ?? "",
                logline: row["logline"] as? String ?? "",
                credits: (row["credits"] as? [[String: Any]] ?? []).compactMap { one in
                    guard let role = one["role"] as? String, !role.isEmpty else { return nil }
                    return Credit(role: role, people: one["people"] as? [String] ?? [])
                },
                hidden: row["hidden"] as? [String] ?? [])
        }
    }

    // ---- the web address and the path are two different facts --------------

    /// The folder id inside `https://drive.google.com/drive/folders/<id>`.
    static func folderId(in url: String) -> String? {
        guard let at = url.range(of: "/folders/") else { return nil }
        let id = url[at.upperBound...].prefix {
            $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_"
        }
        return id.isEmpty ? nil : String(id)
    }

    /// **Google Drive stamps every synced folder with its own id**, in an
    /// extended attribute, which is how a web address and a path on this Mac
    /// can be matched without asking Google anything. His own note in
    /// `CLAUDE.md` — this is that, read rather than written.
    static func driveId(of url: URL) -> String? {
        let name = "com.google.drivefs.item-id#S"
        return url.withUnsafeFileSystemRepresentation { path -> String? in
            guard let path else { return nil }
            let size = getxattr(path, name, nil, 0, 0, 0)
            guard size > 0 else { return nil }
            var buffer = [UInt8](repeating: 0, count: size)
            guard getxattr(path, name, &buffer, size, 0, 0) == size else { return nil }
            return String(decoding: buffer, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// The same folder, on this Mac. **Slow enough to belong off the main
    /// thread** — it walks the mounted Drives breadth-first, reading one
    /// attribute per folder, and stops at the first match. Four levels reaches
    /// `My Drive/cinematography/projects/call-her-back`, which is where his
    /// actually are; the count is a backstop rather than a limit anybody should
    /// hit.
    static func localFolder(driveId wanted: String, depth: Int = 4) -> URL? {
        let manager = FileManager.default
        let cloud = manager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/CloudStorage", isDirectory: true)
        let mounts = ((try? manager.contentsOfDirectory(
            at: cloud, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("GoogleDrive-") }

        var queue: [(URL, Int)] = mounts.map { ($0, 0) }
        var looked = 0
        while !queue.isEmpty, looked < 6000 {
            let (here, level) = queue.removeFirst()
            looked += 1
            if driveId(of: here) == wanted { return here }
            guard level < depth else { continue }
            let inside = (try? manager.contentsOfDirectory(
                at: here, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants])) ?? []
            for one in inside
            where (try? one.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                queue.append((one, level + 1))
            }
        }
        return nil
    }

    /// A path short enough to read in a row: the last three parts of it.
    static func shortPath(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        let parts = path.split(separator: "/")
        return parts.suffix(3).joined(separator: "/")
    }
}

/// **Writing the link down**, in one place.
///
/// The setup screen, the settings page and a checking run all say the same
/// four things to the project record, so they say them through here rather than
/// each spelling out the field names. Everything goes through the engine's
/// ordinary `set`, so a link undoes, saves and syncs like any other edit.
enum Linking {
    /// Point this film at a console project, or at none.
    static func link(_ one: Console.Project?, state: ShellState) {
        write("console_page", one?.pageId ?? "", state: state)
        write("console_name", one?.name ?? "", state: state)
        write("drive_url", one?.driveUrl ?? "", state: state)
    }

    static func setFolder(_ path: String, state: ShellState) {
        write("drive_folder", path, state: state)
    }

    /// The local folder for whatever this project is linked to. **Blocking** —
    /// callers on the main thread hand it to a background queue.
    static func findFolder(state: ShellState) -> URL? {
        guard let id = Console.folderId(in: state.view?.project.driveUrl ?? "") else {
            return nil
        }
        return Console.localFolder(driveId: id)
    }

    private static func write(_ field: String, _ value: String, state: ShellState) {
        guard let engine = state.engine, let id = state.view?.project.id else { return }
        state.replace(engine.set(shot: id, field: field, value: value))
        guard Launch.checking else { return }
        FileHandle.standardError.write(Data(("link: \(field) \"\(value)\"\n").utf8))
    }
}
