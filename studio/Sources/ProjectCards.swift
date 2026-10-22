import AppKit
import Foundation

/// **Studio reads the card** (stage 5 step 4, piece A, 2026-10-14).
///
/// One record per project, kept by the server: the card. What defines a
/// project — its name, director, producer, client, agency, icon and colour,
/// and the Type its kind follows from — is the card's. Studio no longer keeps
/// its own copy in the film: it reads the cards from the server
/// (`GET /console/studio/cards`, `hub/src/studiocards.js`), keeps the last
/// answer on this Mac for offline, and hands the open film's card to the
/// engine (`card`), which lays it over the film without writing anything.
///
/// **Only while the server's switch says so.** Off, or never read, Studio is
/// exactly what it was: facts from the film, the project list from the
/// console's cache file, Change in Console through `open-request.json`.
final class ProjectCards {
    static let shared = ProjectCards()

    struct Credit: Codable, Hashable {
        var role: String
        var people: [String]
    }

    struct Mark: Codable, Hashable {
        var path: String
        var colour: String
    }

    struct Card: Codable, Hashable {
        var id: String
        var notion: String = ""
        var relay: String = ""
        var aliases: [String] = []
        var name: String = ""
        var facts: [String: String] = [:]
        var mark: Mark?
        var type: String = ""
        var kind: String = ""
        var job: Bool = false
        var status: String = ""
        var dates: String = ""
        var drive_url: String = ""
        var notion_url: String = ""
        var logline: String = ""
        var credits: [Credit] = []
        var hidden: [String] = []
        /// The modes this project has on (step 4 piece B), by the server's
        /// names. Optional: an older server sends none, and then every mode
        /// shows.
        var modes: [String]?
        /// **The mods this project has on** (2026-10-17), by the shelf's
        /// keys. Absent from an older server: none.
        var mods: [String]?
        /// The script's draft in use and any newer one waiting in Drive
        /// (step 4 piece C), while the server's `scriptdrive` switch is on.
        var script: ScriptCard?
        /// **The project's shoots** (step 4 piece D), first to last, while
        /// the server's `studioshoots` switch is on: the console's picker's
        /// list. Absent from an older server or with the switch off.
        var shoots: [CardShoot]?
        /// **The project's spec sheet as Studio needs it** (step 4 piece E):
        /// its frames and each camera's sensor, and a shoot's own, while the
        /// server's `studioframes` switch is on. Kept with the rest of the
        /// card, so offline Studio still draws at the project's frames.
        var sheet: CardSheet?

        /// Every id this project is known by, bare and lowercased.
        var ids: Set<String> {
            Set(([id, notion, relay] + aliases).map(ProjectCards.bare).filter { !$0.isEmpty })
        }

        /// What the engine's `card` takes.
        var engineJSON: String? {
            var out: [String: Any] = ["facts": facts, "kind": kind, "type": type]
            if let mark { out["mark"] = ["path": mark.path, "colour": mark.colour] }
            if let shoots {
                out["shoots"] = shoots.map { s -> [String: Any] in
                    var one: [String: Any] = ["id": s.id, "label": s.label, "kind": s.kind ?? "", "start": s.start ?? "",
                                              "end": s.end ?? "", "state": s.state ?? ""]
                    if let n = s.n { one["n"] = n }
                    return one
                }
            }
            if let sheet { out["sheet"] = sheet.engineObject }
            guard let data = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }

        /// The page Projects Console knows the project by.
        var consolePage: String { notion.isEmpty ? id : notion }
    }

    /// **A spec sheet as Studio needs it** (piece E): frames, each camera's
    /// sensor, and under `shoots` a shoot's own when one reads its own.
    struct CardSheet: Codable, Hashable {
        struct Frame: Codable, Hashable {
            var name: String
            var ratio: String
            var main: Bool?
        }
        struct Sensor: Codable, Hashable {
            var label: String
            var name: String?
            var width: Double
            var height: Double?
        }
        struct Part: Codable, Hashable {
            var frames: [Frame]?
            var sensors: [Sensor]?
        }
        var frames: [Frame]?
        var sensors: [Sensor]?
        var shoots: [String: Part]?

        private static func object(_ frames: [Frame]?, _ sensors: [Sensor]?) -> [String: Any] {
            [
                "frames": (frames ?? []).map { ["name": $0.name, "ratio": $0.ratio, "main": $0.main ?? false] as [String: Any] },
                "sensors": (sensors ?? []).map { ["label": $0.label, "name": $0.name ?? "", "width": $0.width, "height": $0.height ?? 0] as [String: Any] },
            ]
        }

        /// What the engine's `card` takes under `sheet`.
        var engineObject: [String: Any] {
            var out = Self.object(frames, sensors)
            if let shoots, !shoots.isEmpty {
                out["shoots"] = shoots.mapValues { Self.object($0.frames, $0.sensors) }
            }
            return out
        }
    }

    /// One of the project's shoots, as the card says it (piece D).
    struct CardShoot: Codable, Hashable {
        var id: String
        var label: String
        var kind: String?
        var name: String?
        var n: Int?
        var start: String?
        var end: String?
        var when: String?
        var state: String?
    }

    /// **The script, from Drive** (step 4 piece C, `hub/src/scriptdrive.js`):
    /// the draft in use, as every app labels it, and a newer PDF in the
    /// project's `1-creative/script/current-draft/` when there is one — or,
    /// when that folder holds more than one draft, the ones he picks from.
    struct ScriptCard: Codable, Hashable {
        struct Waiting: Codable, Hashable {
            var file: String
            var name: String
            var label: String
            var modified: String = ""
            /// In a pick: whether this file is the draft in use already.
            var same: Bool? = nil
        }
        var label: String = ""
        var name: String = ""
        var dated: String = ""
        var new: Waiting?
        /// More than one draft in `current-draft/`: he picks. Never guessed.
        var pick: [Waiting]?
        var folder: String = ""
        var checked: String = ""
    }

    /// What the server answered, as kept on this Mac.
    struct Saved: Codable {
        var on: Bool
        /// The server's modes switch (`studiomodes`): whether Studio shows
        /// only the modes a project has on. Absent from an older server.
        var modes: Bool?
        /// The server's `scriptdrive` switch: whether the script draws from
        /// Drive. Absent from an older server.
        var script: Bool?
        /// The server's `studioshoots` switch (piece D). Absent from an older server.
        var shoots: Bool?
        /// The server's `studioframes` switch (piece E). Absent from an older server.
        var frames: Bool?
        var at: String
        var cards: [Card]
    }

    private(set) var saved: Saved?
    private var reading = false

    private init() {
        if let data = try? Data(contentsOf: Self.file),
           let kept = try? JSONDecoder().decode(Saved.self, from: data) {
            saved = kept
        }
    }

    /// Whether Studio reads the card: the server's switch, as last read.
    var on: Bool { saved?.on == true }

    /// The cards, while the switch is on; empty otherwise.
    var cards: [Card] { on ? (saved?.cards ?? []) : [] }

    /// This Mac's name as Projects Console says it (Python's
    /// `socket.gethostname()`), so its console takes only its own requests.
    nonisolated static var macName: String {
        var buffer = [CChar](repeating: 0, count: 256)
        gethostname(&buffer, 255)
        return String(cString: buffer)
    }

    nonisolated static func bare(_ id: String) -> String {
        id.replacingOccurrences(of: "-", with: "").trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// **Where the saved copy lives.** A checking run never touches his:
    /// `SHOTLISTER_CARDS` names a file, or it keeps none.
    nonisolated static var file: URL {
        if let set = ProcessInfo.processInfo.environment["SHOTLISTER_CARDS"], !set.isEmpty {
            return URL(fileURLWithPath: set)
        }
        if Launch.checking {
            return FileManager.default.temporaryDirectory.appending(path: "shotlister-check-cards-\(getpid()).json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Shotlister/cards.json")
    }

    /// The card for a film: by its relay id, else by the console page it was
    /// linked to. Nil while the switch is off.
    func card(film relay: String?, page: String = "") -> Card? {
        let wanted = [relay ?? "", page].map(Self.bare).filter { !$0.isEmpty }
        guard !wanted.isEmpty else { return nil }
        return cards.first { card in wanted.contains { card.ids.contains($0) } }
    }

    /// The card for a console page or project id.
    func card(page: String) -> Card? { card(film: nil, page: page) }

    /// **A closed project** (Close Project, 2026-10-16): its record says
    /// Closed, so Studio's project list leaves its shot list out. Nothing is
    /// moved or deleted; Reopen Project brings it back on the next read.
    /// From the saved cards whether or not the cards switch is on.
    func closed(film relay: String?) -> Bool {
        let id = Self.bare(relay ?? "")
        guard !id.isEmpty, let card = saved?.cards.first(where: { $0.ids.contains(id) }) else { return false }
        return card.status.trimmingCharacters(in: .whitespaces).lowercased() == "closed"
    }

    /// Whether the film at this path is a closed project's.
    func closed(at url: URL) -> Bool { closed(film: Relay.projectId(at: url)) }

    // ---- reading -------------------------------------------------------------

    /// **Read the cards from the server** and keep them; then lay the open
    /// film's card on again if it changed. Quiet: offline, the saved copy
    /// stands and nothing is said.
    func refresh(_ state: ShellState? = nil) {
        guard !reading, let address = SpecSheets.address(), let token = SpecSheets.token(),
              let url = URL(string: "\(address)/console/studio/cards") else { return }
        reading = true
        Task { @MainActor in
            defer { reading = false }
            var ask = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            ask.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            guard let (data, answer) = try? await URLSession.shared.data(for: ask),
                  (answer as? HTTPURLResponse)?.statusCode == 200,
                  let got = try? JSONDecoder().decode(Saved.self, from: data) else { return }
            let before = saved
            saved = got
            try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let bytes = try? JSONEncoder().encode(got) { try? bytes.write(to: Self.file, options: .atomic) }
            if let state, before?.on != got.on || before?.modes != got.modes || before?.cards != got.cards {
                lay(on: state, fromElsewhere: true)
            }
            if let state, got.script == true { checkScript(state) }
        }
    }

    /// **Lay the open film's card over it**, from what is kept — or take it
    /// off when the switch is off or the film is no project's.
    func lay(on state: ShellState, fromElsewhere: Bool = false) {
        guard let engine = state.engine, let path = state.projectPath else { return }
        let relay = Relay.projectId(at: path)
        state.applyModes(modes(film: relay, page: state.view?.project.consolePage ?? ""), fromElsewhere: fromElsewhere)
        let mods = self.mods(film: relay, page: state.view?.project.consolePage ?? "")
        if state.modsOn != mods, !(Launch.checking && CommandLine.arguments.contains("--modson")) { state.modsOn = mods }
        // At open, a fresh look at the script folder (step 4 piece C).
        if !fromElsewhere && scriptOn { checkScript(state) }
        let card = self.card(film: relay, page: state.view?.project.consolePage ?? "")
        let had = state.view?.project.card == true
        if card == nil && !had { return }
        state.replace(engine.setCard(card?.engineJSON))
        // The project's shoots came with it (piece D): the picker's pick.
        state.applyShootPick()
        if Launch.checking {
            FileHandle.standardError.write(Data("card: \(card.map { "\($0.id) \($0.facts["title"] ?? $0.name)" } ?? "none")\n".utf8))
        }
    }

    // ---- modes (stage 5 step 4, piece B) ---------------------------------------

    /// Whether Studio shows only the modes a project has on: the server's
    /// switch, as last read. Off, every mode shows, as it always has.
    var modesOn: Bool { saved?.modes == true }

    /// The card for a film among everything kept, whether or not the cards
    /// switch is on: the modes have their own.
    private func anyCard(film relay: String?, page: String) -> Card? {
        let wanted = [relay ?? "", page].map(Self.bare).filter { !$0.isEmpty }
        guard !wanted.isEmpty else { return nil }
        return saved?.cards.first { card in wanted.contains { card.ids.contains($0) } }
    }

    /// The modes a film's project has on, in the switcher's order; nil when
    /// every mode shows (the switch off, no card, or an older server).
    func modes(film relay: String?, page: String) -> [SideTab]? {
        guard modesOn, let card = anyCard(film: relay, page: page), let said = card.modes else { return nil }
        let on = Set(said.compactMap(Self.tab))
        // Script goes with Shot List, and Schedule arranges its scenes.
        return SideTab.allCases.filter { on.contains($0) }
    }

    /// **The mods a film's project has on** (Mods.swift's shelf keys); none
    /// without a card. Off by default, whatever any switch says.
    func mods(film relay: String?, page: String) -> [String] {
        anyCard(film: relay, page: page)?.mods ?? []
    }

    /// **Switch one mod for the open film's project** (`POST
    /// /console/studio/mods/<id>`), the console card's switch. The kept card
    /// follows at once.
    func setMod(_ key: String, on: Bool, film relay: String?, page: String) async -> (mods: [String]?, why: String?) {
        guard let card = anyCard(film: relay, page: page) else { return (nil, "This film has no project.") }
        guard let address = SpecSheets.address(), let token = SpecSheets.token(),
              let url = URL(string: "\(address)/console/studio/mods/\(card.id)") else { return (nil, "Can't reach the server.") }
        var ask = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        ask.httpMethod = "POST"
        ask.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        ask.setValue("application/json", forHTTPHeaderField: "Content-Type")
        ask.httpBody = try? JSONSerialization.data(withJSONObject: ["mod": key, "on": on, "by": "studio"])
        guard let (data, _) = try? await URLSession.shared.data(for: ask),
              let said = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (nil, "Can't reach the server.") }
        guard said["ok"] as? Bool == true, let list = said["mods"] as? [String] else {
            return (nil, (said["why"] as? String) ?? "Not changed.")
        }
        if var kept = saved, let at = kept.cards.firstIndex(where: { $0.id == card.id }) {
            kept.cards[at].mods = list
            saved = kept
            if let bytes = try? JSONEncoder().encode(kept) { try? bytes.write(to: Self.file, options: .atomic) }
        }
        return (list, nil)
    }

    /// The server's name for a mode, and back.
    nonisolated static func key(_ tab: SideTab) -> String {
        switch tab {
        case .scenes: return "shot_list"
        case .locations: return "locations"
        case .boards: return "references"
        case .schedule: return "schedule"
        case .diagram: return "diagram"
        }
    }

    nonisolated static func tab(_ key: String) -> SideTab? {
        SideTab.allCases.first { Self.key($0) == key }
    }

    /// What the server answered a mode change: the project's modes now, or
    /// why not. `needsBoth`: Shot List off while Schedule is on.
    struct ModeAnswer {
        var modes: [SideTab]?
        var why: String?
        var needsBoth = false
    }

    /// **Turn one mode on or off for the open film's project**
    /// (`POST /console/studio/modes/<id>`), the same switch as the console's.
    /// On success the kept card follows at once, so the bar does not wait
    /// for the next read.
    func setMode(_ tab: SideTab, on: Bool, both: Bool, film relay: String?, page: String) async -> ModeAnswer {
        guard let card = anyCard(film: relay, page: page) else { return ModeAnswer(why: "This film has no project.") }
        guard let address = SpecSheets.address(), let token = SpecSheets.token(),
              let url = URL(string: "\(address)/console/studio/modes/\(card.id)") else {
            return ModeAnswer(why: "Can't reach the server.")
        }
        var ask = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        ask.httpMethod = "POST"
        ask.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        ask.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["mode": Self.key(tab), "on": on, "by": "studio"]
        if both { body["both"] = true }
        ask.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await URLSession.shared.data(for: ask),
              let said = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ModeAnswer(why: "Can't reach the server.")
        }
        let list = (said["modes"] as? [String]) ?? []
        guard said["ok"] as? Bool == true else {
            return ModeAnswer(modes: nil, why: (said["why"] as? String) ?? "Not changed.",
                              needsBoth: (said["needs"] as? String) == "both")
        }
        if var kept = saved, let at = kept.cards.firstIndex(where: { $0.id == card.id }) {
            kept.cards[at].modes = list
            saved = kept
            if let bytes = try? JSONEncoder().encode(kept) { try? bytes.write(to: Self.file, options: .atomic) }
        }
        let on = Set(list.compactMap(Self.tab))
        return ModeAnswer(modes: SideTab.allCases.filter { on.contains($0) })
    }

    // ---- the script, from Drive (stage 5 step 4, piece C) ---------------------

    /// Whether the script draws from Drive: the server's switch, as last read.
    var scriptOn: Bool { saved?.script == true }

    /// The open film's project card, whatever the cards switch says.
    func scriptCard(film relay: String?, page: String) -> Card? {
        guard scriptOn else { return nil }
        return anyCard(film: relay, page: page)
    }

    /// **A newer draft in the project's Drive script folder**, not yet taken
    /// in. Nil while the switch is off, the project has none, or Shot List is
    /// off (the script goes with it).
    func draftInDrive(film relay: String?, page: String) -> (card: Card, waiting: ScriptCard.Waiting)? {
        guard let card = scriptCard(film: relay, page: page), let waiting = card.script?.new else { return nil }
        if modesOn, let modes = card.modes, !modes.contains("shot_list") { return nil }
        return (card, waiting)
    }

    /// **More than one draft in `current-draft/`** (his rule, 2026-10-15):
    /// the drafts to pick the current one from. Nil as for `draftInDrive`.
    func draftChoices(film relay: String?, page: String) -> (card: Card, choices: [ScriptCard.Waiting])? {
        guard let card = scriptCard(film: relay, page: page), let pick = card.script?.pick, pick.count > 1 else { return nil }
        if modesOn, let modes = card.modes, !modes.contains("shot_list") { return nil }
        return (card, pick)
    }

    private var checking = false

    /// **Ask the server to look at the open film's script folder now**
    /// (`POST /console/studio/script/<id>/check`), so a draft saved into Drive
    /// a minute ago shows without waiting for the server's ten-minute look.
    /// Quiet offline. Also finishes a confirm that could not reach Drive.
    func checkScript(_ state: ShellState) {
        guard scriptOn, !checking, let path = state.projectPath else { return }
        let relay = Relay.projectId(at: path)
        guard let card = anyCard(film: relay, page: state.view?.project.consolePage ?? "") else { return }
        checking = true
        Task { @MainActor in
            defer { checking = false }
            if let waiting = ScriptPending.take(card.id) {
                _ = await ScriptPending.retry(waiting, card: card, state: state)
            }
            guard let said = await Self.scriptCall("\(card.id)/check", method: "POST", json: [:]) else { return }
            keepScript(said["script"], for: card.id)
            if Launch.checking {
                let script = said["script"] as? [String: Any]
                let new = script?["new"] as? [String: Any]
                let pick = (script?["pick"] as? [[String: Any]])?.compactMap { $0["label"] as? String } ?? []
                FileHandle.standardError.write(Data("script check: \(new?["label"] as? String ?? (pick.isEmpty ? "no new draft" : "pick: " + pick.joined(separator: " | ")))\n".utf8))
            }
        }
    }

    /// The server's word on one project's script, kept in the saved cards.
    @MainActor
    func keepScript(_ raw: Any?, for id: String) {
        guard var kept = saved, let at = kept.cards.firstIndex(where: { $0.id == id }) else { return }
        if let raw, !(raw is NSNull), let data = try? JSONSerialization.data(withJSONObject: raw),
           let got = try? JSONDecoder().decode(ScriptCard.self, from: data) {
            kept.cards[at].script = got
        } else {
            kept.cards[at].script = nil
        }
        guard kept.cards != saved?.cards else { return }
        saved = kept
        if let bytes = try? JSONEncoder().encode(kept) { try? bytes.write(to: Self.file, options: .atomic) }
        ShellState.shared.scriptStamp += 1
    }

    /// **The new draft's PDF, from Drive through the server**, saved under its
    /// own name in a fresh folder so the draft remembers the file it came from.
    nonisolated static func fetchDraft(project id: String, waiting: ScriptCard.Waiting) async -> URL? {
        guard let address = SpecSheets.address(), let token = SpecSheets.token(),
              let url = URL(string: "\(address)/console/studio/script/\(id)/file/\(waiting.file)") else { return nil }
        var ask = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
        ask.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        guard let (data, answer) = try? await URLSession.shared.data(for: ask),
              (answer as? HTTPURLResponse)?.statusCode == 200, data.starts(with: Array("%PDF".utf8)) else { return nil }
        let folder = FileManager.default.temporaryDirectory.appending(path: "shotlister-draft-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var name = waiting.name.replacingOccurrences(of: "/", with: "-")
        if !name.lowercased().hasSuffix(".pdf") { name += ".pdf" }
        let file = folder.appending(path: name)
        guard (try? data.write(to: file)) != nil else { return nil }
        return file
    }

    /// One call to the script's door; the answer as JSON, nil when the server
    /// could not be reached or would not.
    nonisolated static func scriptCall(_ rest: String, method: String, json: [String: Any]? = nil,
                                       body: Data? = nil, query: [URLQueryItem] = []) async -> [String: Any]? {
        guard let address = SpecSheets.address(), let token = SpecSheets.token(),
              var parts = URLComponents(string: "\(address)/console/studio/script/\(rest)") else { return nil }
        if !query.isEmpty { parts.queryItems = query }
        guard let url = parts.url else { return nil }
        var ask = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
        ask.httpMethod = method
        ask.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if let json {
            ask.setValue("application/json", forHTTPHeaderField: "Content-Type")
            ask.httpBody = try? JSONSerialization.data(withJSONObject: json)
        } else if let body {
            ask.setValue("application/pdf", forHTTPHeaderField: "Content-Type")
            ask.httpBody = body
        }
        guard let (data, _) = try? await URLSession.shared.data(for: ask),
              let said = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              said["ok"] as? Bool == true else { return nil }
        return said
    }

    // ---- opening the console ---------------------------------------------------

    /// **Projects Console, opened on a project — through the server.** The
    /// request is left on the server for this Mac's console
    /// (`/console/studio/open`), which picks it up the moment it comes to the
    /// front. `action` is `archive` or `delete` for the project's own Archive
    /// and Delete, behind the console's previews and confirmations. Answers
    /// false when the server could not be reached, so the caller falls back to
    /// the file beside the console.
    nonisolated static func askConsole(page: String, id: String, action: String) async -> Bool {
        guard let address = SpecSheets.address(), let token = SpecSheets.token(),
              let url = URL(string: "\(address)/console/studio/open") else { return false }
        var ask = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
        ask.httpMethod = "POST"
        ask.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        ask.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: String] = ["mac": macName, "page": page, "id": id, "by": "studio"]
        if !action.isEmpty { body["action"] = action }
        ask.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (_, answer) = try? await URLSession.shared.data(for: ask) else { return false }
        return (answer as? HTTPURLResponse)?.statusCode == 200
    }
}


/// **A confirm that has not reached Drive yet** (step 4 piece C). The draft is
/// taken into the film at once; filing it in Drive (and moving the old one to
/// `z-archive/`) needs the server. Offline, it waits here, one per project, and
/// goes the next time the script is checked.
enum ScriptPending {
    struct Waiting: Codable {
        /// `settle` (a draft from Drive) or `upload` (Studio's own Import).
        var kind: String
        var file: String = ""
        var stem: String
        var name: String = ""
        var path: String = ""
    }

    private static var key: String { Launch.checking ? "scriptPendingCheck" : "scriptPending" }

    private static func all() -> [String: Waiting] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let got = try? JSONDecoder().decode([String: Waiting].self, from: data) else { return [:] }
        return got
    }

    private static func save(_ list: [String: Waiting]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: key)
    }

    static func keep(_ waiting: Waiting, for id: String) {
        var list = all()
        list[id] = waiting
        save(list)
    }

    static func take(_ id: String) -> Waiting? {
        var list = all()
        let got = list.removeValue(forKey: id)
        save(list)
        return got
    }

    /// **File the draft just taken in.** From Drive: settle on that file.
    /// From Studio's own Import: send the PDF. Answers the server's words, or
    /// nil (kept to try again).
    @MainActor
    static func retry(_ waiting: Waiting, card: ProjectCards.Card, state: ShellState) async -> [String: Any]? {
        var said: [String: Any]?
        if waiting.kind == "settle" {
            var body: [String: Any] = ["stem": waiting.stem, "by": "studio"]
            if !waiting.file.isEmpty { body["file"] = waiting.file }
            said = await ProjectCards.scriptCall("\(card.id)/settle", method: "POST", json: body)
        } else {
            let bytes = state.engine?.revisions().first(where: { $0.hash.hasPrefix(waiting.stem) })
                .flatMap { state.engine?.scriptPDF(of: $0.id) }
            guard let bytes else { return [:] }      // no PDF kept: nothing to file
            said = await ProjectCards.scriptCall("\(card.id)/upload", method: "PUT", body: bytes, query: [
                URLQueryItem(name: "name", value: waiting.name), URLQueryItem(name: "stem", value: waiting.stem),
                URLQueryItem(name: "by", value: "studio")])
        }
        guard let said else {
            keep(waiting, for: card.id)
            return nil
        }
        ProjectCards.shared.keepScript(said["script"], for: card.id)
        if Launch.checking {
            let moved = (said["archived"] as? [String]) ?? []
            FileHandle.standardError.write(Data("script filed: \(waiting.kind) kept \(said["kept"] as? String ?? "") archived \(moved.joined(separator: ","))\n".utf8))
        }
        return said
    }
}
