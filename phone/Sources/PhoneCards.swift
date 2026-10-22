import Foundation

/// **Studio reads the card, on the phone too** (stage 5 step 4, piece A).
///
/// The project's card — title, director, producer, client, agency, icon and
/// colour, and the kind its Type implies — is the server's
/// (`GET /console/studio/cards`). The phone reads it, keeps the last answer
/// for a set with no signal, and hands the open film's card to the engine
/// (`card`), which lays it over the film without writing anything. While the
/// server's switch is off nothing is laid on and the film shows its own words,
/// exactly as an older build does.
@MainActor
final class PhoneCards: ObservableObject {
    static let shared = PhoneCards()

    private struct Saved: Codable, Equatable {
        var on: Bool
        /// The server's modes switch (stage 5 step 4 B); absent from an older server.
        var modes: Bool?
        /// The server's `scriptdrive` switch; absent from an older server.
        var script: Bool?
        var cards: [Card]
    }

    /// Moves whenever a new answer is kept, so the tab bar and the home list
    /// redraw with it.
    @Published private(set) var stamp = 0

    struct Mark: Codable, Hashable { var path: String; var colour: String }

    /// The server's word on a project's script (the Mac's `ScriptCard`).
    struct ScriptCard: Codable, Hashable {
        struct Waiting: Codable, Hashable {
            var file: String
            var name: String
            var label: String
            var same: Bool? = nil
        }
        var label: String = ""
        var new: Waiting?
        var pick: [Waiting]?
    }

    struct Card: Codable, Hashable {
        var id: String
        var notion: String = ""
        var relay: String = ""
        var aliases: [String] = []
        var facts: [String: String] = [:]
        var mark: Mark?
        var type: String = ""
        var kind: String = ""
        /// Absent from an older server.
        var name: String?
        var job: Bool?
        var modes: [String]?
        /// The mods this project has on (2026-10-17); absent from an older server.
        var mods: [String]?
        /// The project's shoots (piece D), while the server's switch is on.
        var shoots: [Shoot]?
        /// **The project's spec sheet's frames and sensors** (piece E), while
        /// the server's `studioframes` switch is on. Kept with the card, so
        /// offline the phone still draws at the project's frames.
        var sheet: Sheet?
        /// The project's script in Drive (step 4 piece C), while `scriptdrive` is on.
        var script: ScriptCard?

        struct Sheet: Codable, Hashable {
            struct Frame: Codable, Hashable { var name: String; var ratio: String; var main: Bool? }
            struct Sensor: Codable, Hashable { var label: String; var name: String?; var width: Double; var height: Double? }
            struct Part: Codable, Hashable { var frames: [Frame]?; var sensors: [Sensor]? }
            var frames: [Frame]?
            var sensors: [Sensor]?
            var shoots: [String: Part]?

            private static func object(_ frames: [Frame]?, _ sensors: [Sensor]?) -> [String: Any] {
                [
                    "frames": (frames ?? []).map { ["name": $0.name, "ratio": $0.ratio, "main": $0.main ?? false] as [String: Any] },
                    "sensors": (sensors ?? []).map { ["label": $0.label, "name": $0.name ?? "", "width": $0.width, "height": $0.height ?? 0] as [String: Any] },
                ]
            }

            var engineObject: [String: Any] {
                var out = Self.object(frames, sensors)
                if let shoots, !shoots.isEmpty { out["shoots"] = shoots.mapValues { Self.object($0.frames, $0.sensors) } }
                return out
            }
        }

        struct Shoot: Codable, Hashable {
            var id: String
            var label: String
            var kind: String?
            var n: Int?
            var start: String?
            var end: String?
            var state: String?
        }

        var ids: Set<String> { Set(([id, notion, relay] + aliases).map(PhoneCards.bare).filter { !$0.isEmpty }) }

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
    }

    private var saved: Saved?
    private var reading = false
    private let file = PortalLine.home(for: "_home").appending(path: "cards.json")

    private init() {
        if let data = try? Data(contentsOf: file), let kept = try? JSONDecoder().decode(Saved.self, from: data) {
            saved = kept
        }
    }

    nonisolated static func bare(_ id: String) -> String {
        id.replacingOccurrences(of: "-", with: "").trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// The card for a film, by its relay id or the console page it names; nil while off.
    func card(film relay: String?, page: String) -> Card? {
        guard saved?.on == true else { return nil }
        let wanted = [relay ?? "", page].map(Self.bare).filter { !$0.isEmpty }
        guard !wanted.isEmpty else { return nil }
        return saved?.cards.first { c in wanted.contains { c.ids.contains($0) } }
    }

    // ---- the script, from Drive (step 4 piece C) -------------------------------

    /// The open film's card while the script draws from Drive.
    func scriptCard(film relay: String?, page: String) -> Card? {
        guard saved?.script == true else { return nil }
        return anyCard([relay ?? "", page])
    }

    /// A newer draft in the project's Drive script folder, not yet taken in.
    func draftInDrive(film relay: String?, page: String) -> (card: Card, waiting: ScriptCard.Waiting)? {
        guard let card = scriptCard(film: relay, page: page), let w = card.script?.new else { return nil }
        if modesOn, let modes = card.modes, !modes.contains("shot_list") { return nil }
        return (card, w)
    }

    /// More than one draft in `current-draft/`: he picks, never guessed.
    func draftChoices(film relay: String?, page: String) -> (card: Card, choices: [ScriptCard.Waiting])? {
        guard let card = scriptCard(film: relay, page: page), let pick = card.script?.pick, pick.count > 1 else { return nil }
        if modesOn, let modes = card.modes, !modes.contains("shot_list") { return nil }
        return (card, pick)
    }

    /// One call to the server's script door; its answer, nil when not reached.
    nonisolated static func scriptCall(_ rest: String, method: String, json: [String: Any]? = nil,
                                       body: Data? = nil, query: [URLQueryItem] = []) async -> [String: Any]? {
        guard let address = PortalLine.address(), let token = PortalLine.token(),
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

    /// The draft's PDF, from Drive through the server, under its own name.
    nonisolated static func fetchDraft(project id: String, waiting: ScriptCard.Waiting) async -> URL? {
        guard let address = PortalLine.address(), let token = PortalLine.token(),
              let url = URL(string: "\(address)/console/studio/script/\(id)/file/\(waiting.file)") else { return nil }
        var ask = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
        ask.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        guard let (data, answer) = try? await URLSession.shared.data(for: ask),
              (answer as? HTTPURLResponse)?.statusCode == 200, data.starts(with: Array("%PDF".utf8)) else { return nil }
        let folder = FileManager.default.temporaryDirectory.appending(path: "draft-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var name = waiting.name.replacingOccurrences(of: "/", with: "-")
        if !name.lowercased().hasSuffix(".pdf") { name += ".pdf" }
        let file = folder.appending(path: name)
        guard (try? data.write(to: file)) != nil else { return nil }
        return file
    }

    /// Ask the server to look at the script folder now (`check`), keeping its word.
    func checkScript(film relay: String?, page: String) async {
        guard let card = scriptCard(film: relay, page: page),
              let said = await Self.scriptCall("\(card.id)/check", method: "POST", json: [:]) else { return }
        guard var kept = saved, let at = kept.cards.firstIndex(where: { $0.id == card.id }) else { return }
        if let raw = said["script"], !(raw is NSNull), let data = try? JSONSerialization.data(withJSONObject: raw) {
            kept.cards[at].script = try? JSONDecoder().decode(ScriptCard.self, from: data)
        } else {
            kept.cards[at].script = nil
        }
        guard kept != saved else { return }
        saved = kept
        stamp += 1
        if let bytes = try? JSONEncoder().encode(kept) { try? bytes.write(to: file, options: .atomic) }
    }

    /// Lay the open film's card on from the kept copy, then read the server
    /// again and lay it on afresh if it changed.
    func lay(on session: Session) {
        openRelay = Relay.projectId(at: session.folder.url)
        openPage = session.view?.project.consolePage ?? ""
        apply(to: session)
        guard !reading, let address = PortalLine.address(), let token = PortalLine.token(),
              let url = URL(string: address + "/console/studio/cards") else { return }
        reading = true
        Task { @MainActor in
            defer { reading = false }
            var ask = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            ask.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            guard let (data, answer) = try? await URLSession.shared.data(for: ask),
                  (answer as? HTTPURLResponse)?.statusCode == 200,
                  let got = try? JSONDecoder().decode(Saved.self, from: data) else { return }
            let changed = got != saved
            saved = got
            if changed { stamp += 1 }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let bytes = try? JSONEncoder().encode(got) { try? bytes.write(to: file, options: .atomic) }
            if changed { apply(to: session) }
        }
    }

    // ---- modes (stage 5 step 4, piece B) ---------------------------------------

    /// Read the cards again, for the home list (no film open). Quiet offline.
    func refresh() async {
        guard !reading, let address = PortalLine.address(), let token = PortalLine.token(),
              let url = URL(string: address + "/console/studio/cards") else { return }
        reading = true
        defer { reading = false }
        var ask = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        ask.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        guard let (data, answer) = try? await URLSession.shared.data(for: ask),
              (answer as? HTTPURLResponse)?.statusCode == 200,
              let got = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        guard got != saved else { return }
        saved = got
        stamp += 1
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let bytes = try? JSONEncoder().encode(got) { try? bytes.write(to: file, options: .atomic) }
    }

    /// The film standing open, for the lists that draw places without it.
    private var openRelay: String?
    private var openPage = ""

    /// Whether a place shows for the open film's project.
    func showsHere(_ place: Place) -> Bool { shows(place, film: openRelay, page: openPage) }

    /// Whether the phone follows the projects' modes: the server's switch, as last read.
    var modesOn: Bool { saved?.modes == true }

    private func anyCard(_ wanted: [String]) -> Card? {
        let ids = wanted.map(Self.bare).filter { !$0.isEmpty }
        guard !ids.isEmpty else { return nil }
        return saved?.cards.first { c in ids.contains { c.ids.contains($0) } }
    }

    /// The modes a film's project has on (the server's names); nil while
    /// every mode shows.
    func modes(film relay: String?, page: String) -> Set<String>? {
        guard modesOn, let card = anyCard([relay ?? "", page]), let on = card.modes else { return nil }
        return Set(on)
    }

    /// **The mods a film's project has on** (PhoneMods.swift); none without a card.
    func mods(film relay: String?, page: String) -> Set<String> {
        Set(anyCard([relay ?? "", page])?.mods ?? [])
    }

    /// **Switch a mod** for a film's project (`POST /console/studio/mods/<id>`),
    /// the console card's switch. The kept card follows at once.
    func setMod(_ key: String, on: Bool, film relay: String?, page: String) async -> String? {
        guard let card = anyCard([relay ?? "", page]) else { return "This project has no record." }
        guard let address = PortalLine.address(), let token = PortalLine.token(),
              let url = URL(string: address + "/console/studio/mods/" + card.id) else { return "Can't reach the server." }
        var ask = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        ask.httpMethod = "POST"
        ask.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        ask.setValue("application/json", forHTTPHeaderField: "Content-Type")
        ask.httpBody = try? JSONSerialization.data(withJSONObject: ["mod": key, "on": on, "by": "studio iphone"])
        guard let (data, _) = try? await URLSession.shared.data(for: ask),
              let said = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "Can't reach the server." }
        guard said["ok"] as? Bool == true, let list = said["mods"] as? [String] else {
            return (said["why"] as? String) ?? "Not changed."
        }
        if var kept = saved, let at = kept.cards.firstIndex(where: { $0.id == card.id }) {
            kept.cards[at].mods = list
            saved = kept
            stamp += 1
            if let bytes = try? JSONEncoder().encode(kept) { try? bytes.write(to: file, options: .atomic) }
        }
        return nil
    }

    /// The mode a place belongs to. **Script goes with Shot List.** Places
    /// that are no mode's (Overview, shoots, the portal's pages) always show.
    nonisolated static func mode(of place: Place) -> String? {
        switch place {
        case .shotList, .script: return "shot_list"
        case .schedule: return "schedule"
        case .locations: return "locations"
        case .references: return "references"
        case .diagrams: return "diagram"
        default: return nil
        }
    }

    /// Whether a place shows for this film's project.
    func shows(_ place: Place, film relay: String?, page: String) -> Bool {
        guard let mode = Self.mode(of: place), let on = modes(film: relay, page: page) else { return true }
        return on.contains(mode)
    }

    /// **The home list leaves out Jobs and projects with no modes on**,
    /// while the modes switch is on. Found by any id the project is known by,
    /// or by its name.
    func leavesOut(ids: [String], name: String) -> Bool {
        guard modesOn else { return false }
        let card = anyCard(ids) ?? saved?.cards.first { c in
            let n = name.trimmingCharacters(in: .whitespaces).lowercased()
            return !n.isEmpty && [c.name ?? "", c.facts["title"] ?? ""].contains { $0.lowercased() == n }
        }
        guard let card else { return false }
        if card.job == true { return true }
        if let on = card.modes, on.isEmpty { return true }
        return false
    }

    private func apply(to session: Session) {
        guard let engine = session.engine else { return }
        let card = self.card(film: Relay.projectId(at: session.folder.url), page: session.view?.project.consolePage ?? "")
        let had = session.view?.project.card == true
        if card == nil && !had { return }
        _ = try? engine.call("card", card?.engineJSON ?? "none")
        session.refresh()
        // The project's shoots came with it (piece D): the picker's pick.
        session.applyShootPick()
    }
}
