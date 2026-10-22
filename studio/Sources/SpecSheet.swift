import SwiftUI

/// **The Camera Spec Sheet, from Shotlister** (Ref 1627, his words
/// 2026-10-08: *"the camera spec sheet especially should be available in
/// either … The spec sheet could also feed the lenses in Shotlister and
/// diagrams and vice versa."*)
///
/// **Where the sheet lives.** One Notion row per shoot; Projects Console on
/// the Studio Mac writes it, and the portal holds what it said at its last
/// refresh. This Mac keeps no copy. It asks the portal's kit door
/// (`hub/src/kit.js`, with the relay's password, the way the iPhone asks for
/// its record) and:
///
/// - **takes the kit into the film** — each shoot's lenses onto the Lens
///   list, its cameras' bodies onto the cameras — through the engine
///   (`recordkit`), as the film's **Spec Sheet switch** says (2026-10-13:
///   he does not want it syncing on every project). Off, nothing flows and
///   nothing is even asked for until he opens the page; Ask, a bar over the
///   tab says what changed and Take takes it; Follow, on opening a film and
///   every five minutes, as before the switch. Off is every film's default;
/// - **shows and edits the sheet** on Project Settings' Spec Sheet page. A
///   change goes back as an edit the Studio writes into Notion, with the
///   words this screen showed so one that crossed another is refused;
/// - **offers Add to Spec Sheet** on a shot whose lens or camera the sheet
///   does not have (the engine says which: `offKit`). Offered, never done.
final class SpecSheets: ObservableObject {
    static let shared = SpecSheets()

    /// One shoot's sheet as the kit door gives it.
    struct Sheet: Decodable, Equatable, Identifiable {
        var shoot: String
        var name: String
        var start: String
        var end: String
        var sheet: String
        var lead: Bool
        /// The boxes by their short names: body, lenses, format, capture,
        /// colour, codec, fps, desqueeze.
        var camera: [String: String]
        /// Boxes asked for and not yet in Notion.
        var waiting: [String]
        /// Why the Studio could not write the last change, when it could not.
        var failed: String
        var cameras: [ViewModel.KitCamera]
        var lenses: [String]
        var modifiers: [String]?
        var filters: [String]?
        /// Each lens's close focus off the lens library, by its line
        /// ("CF 0.35 m"); a lens with none is not named (2026-10-15).
        var lens_cf: [String: String]?
        /// The sheet's Aspect Ratio list (Main first) and Finishing Resolutions
        /// list, read only here; edited in Projects Console and the Studio's
        /// aspect ratio menu (2026-10-15: a camera has no guides or finishing of its own).
        var ratios: [Ratio]?
        var finishing: [Finishing]?
        var id: String { sheet.isEmpty ? "shoot:" + shoot + name : sheet }
        var title: String { name.isEmpty ? "The Film" : name }
    }

    private struct Answer: Decodable {
        var ok: Bool?
        var why: String?
        var editable: Bool?
        var shoots: [Sheet]?
        var pills: [String: [Pill]]?
        /// When the sheet last changed, ISO 8601.
        var updated: String?
        /// Kept on the project record (true) or still in Notion.
        var on_record: Bool?
    }

    struct Ratio: Decodable, Equatable, Hashable {
        var name: String
        var ratio: String
        var main: Bool
    }
    struct Finishing: Decodable, Equatable, Hashable {
        var title: String
        var resolution: String
        var note: String
    }

    /// One pill Notion offers for a box, in the colour Notion gave it.
    struct Pill: Decodable, Equatable, Hashable {
        var name: String
        var color: String
    }

    /// The boxes in order of operation (his ask, 2026-10-15), with the words
    /// on screen: Camera, then Color, then Deliverables (`group`).
    /// Every box is Notion pills since 2026-10-13, one per line here.
    static let boxes: [(key: String, label: String, lines: Bool)] = [
        ("body", "Camera", true), ("format", "Shooting Format", true), ("capture", "Capture Resolution", true),
        ("lenses", "Lenses", true), ("desqueeze", "Desqueeze", true),
        ("fps", "Frame Rate", true), ("codec", "Codec", true),
        ("colour", "Color Space", true),
    ]

    /// The group a box is shown under.
    static func group(_ key: String) -> String {
        key == "colour" ? "Color" : "Camera"
    }

    @Published private(set) var sheets: [Sheet] = []
    @Published private(set) var editable = false
    /// Every pill each box offers, by box (body, lenses, format…), Notion's
    /// order and colours (2026-10-13: "pills, same as notion").
    @Published private(set) var pills: [String: [Pill]] = [:]
    @Published private(set) var read = false
    /// When the sheet last changed, as the portal said it (ISO 8601).
    @Published private(set) var updated = ""
    /// The sheet is the project record's (true) or Notion's.
    @Published private(set) var onRecord = true
    /// The one line under the page: what happened last, or why not.
    @Published var said = ""
    @Published private(set) var busy = false
    /// **Ask**: the kit read off the sheets and not yet taken, and what it
    /// would change, in words ("3 Lenses · 1 Camera"). Nil when nothing waits.
    @Published private(set) var offered: [ViewModel.KitShoot]?
    @Published private(set) var offer: String?
    /// The offer he closed with ✕, so the same one is not said again.
    private var setAside: String?
    private var film: String?

    // ---- the door ----------------------------------------------------------

    /// The hub's address: the override a checking run gives
    /// (`-PortalURL`), else the relay's with `sync.` turned to `mcp.` — the
    /// iPhone's rule (`PortalLine.address`).
    nonisolated static func address() -> String? {
        if let set = UserDefaults.standard.string(forKey: "PortalURL"), !set.isEmpty {
            return set.hasSuffix("/") ? String(set.dropLast()) : set
        }
        guard !Launch.checking, let relay = Relay.address,
              var parts = URLComponents(string: relay.hasPrefix("http") ? relay : "https://" + relay),
              let host = parts.host
        else { return nil }
        parts.host = host.hasPrefix("sync.") ? "mcp." + host.dropFirst(5) : host
        parts.path = ""
        parts.scheme = "https"
        return parts.string
    }

    /// The relay's password, which the door takes. A checking run is handed
    /// one (`-PortalToken`) and never reads the Keychain.
    nonisolated static func token() -> String? {
        if Launch.checking { return UserDefaults.standard.string(forKey: "PortalToken") }
        return Relay.token
    }

    private nonisolated static func ask(_ project: String, body: [String: Any]?) async throws -> Answer {
        guard let address = address(), let token = token(),
              let url = URL(string: "\(address)/kit/\(project)")
        else { throw Trouble(said: "Sync isn't set up") }
        var asking = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        asking.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if let body {
            asking.httpMethod = "POST"
            asking.setValue("application/json", forHTTPHeaderField: "Content-Type")
            asking.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, answer) = try await URLSession.shared.data(for: asking)
        let status = (answer as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw Trouble(said: "The portal refused this Mac") }
        if status == 404 { throw Trouble(said: "Not on the portal") }
        if let got = try? JSONDecoder().decode(Answer.self, from: data) {
            if status != 200, let why = got.why { throw Trouble(said: why) }
            if status == 200 { return got }
        }
        throw Trouble(said: "The portal answered \(status)")
    }

    struct Trouble: Error { let said: String }

    // ---- reading, and the film taking it -------------------------------------

    /// **Read the sheets, and take the kit as the switch says.** Quiet:
    /// nothing is said unless the Spec Sheet page is showing it. `auto` is
    /// the film opening and the five-minute beat; Off, those ask for nothing.
    func refresh(_ state: ShellState, auto: Bool = false) {
        guard let path = state.projectPath, Self.address() != nil,
              let project = Relay.projectId(at: path)
        else {
            if film != nil { sheets = []; read = false; film = nil; clearOffer() }
            return
        }
        if film != project { sheets = []; read = false; film = project; clearOffer(); setAside = nil }
        if auto && mode(state) == "off" { clearOffer(); return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let got = try await Self.ask(project, body: nil)
                guard film == project else { return }
                take(got, into: state)
            } catch let trouble as Trouble {
                said = trouble.said
            } catch {
                said = "Portal not reached"
            }
        }
    }

    private func take(_ got: Answer, into state: ShellState) {
        sheets = got.shoots ?? []
        if let offered = got.pills { pills = offered }
        if let when = got.updated { updated = when }
        if let kept = got.on_record { onRecord = kept }
        editable = got.editable ?? false
        read = true
        let kit = sheets.map { ViewModel.KitShoot(name: $0.name, start: $0.start, end: $0.end, sheet: $0.sheet,
                                                  lead: $0.lead, cameras: $0.cameras, lenses: $0.lenses,
                                                  modifiers: $0.modifiers, filters: $0.filters) }
        // The engine writes nothing when the film already has this kit; the
        // comparison only spares the view a rebuild.
        let had = state.view?.project.kit ?? []
        if had == kit { clearOffer(); return }
        switch mode(state) {
        case "follow":
            takeKit(kit, into: state)
        case "ask":
            let words = Self.change(from: had, to: kit)
            offered = kit
            offer = words == setAside ? nil : words
        default:
            clearOffer()
        }
    }

    private func takeKit(_ kit: [ViewModel.KitShoot], into state: ShellState) {
        guard let engine = state.engine, let json = Self.kitJSON(kit) else { return }
        state.replace(engine.takeKit(json))
        clearOffer()
    }

    private func clearOffer() { offered = nil; offer = nil }

    func mode(_ state: ShellState) -> String { state.view?.project.kitMode ?? "off" }

    /// A pill's Notion colour name, by box and name; "default" when unknown.
    func colour(_ box: String, _ name: String) -> String {
        let key = name.lowercased()
        return pills[box]?.first { $0.name.lowercased() == key }?.color ?? "default"
    }

    /// **Take** what Ask offered.
    func takeOffered(_ state: ShellState) {
        guard let kit = offered else { return }
        takeKit(kit, into: state)
        state.say("Spec Sheet taken")
    }

    /// ✕ on the bar: not now. A different change is offered again.
    func setOfferAside() { setAside = offer; offer = nil }

    /// **The switch**, from the Spec Sheet page. Turning it to Follow or Ask
    /// reads the sheets at once.
    func setMode(_ now: String, state: ShellState) {
        guard now != mode(state), let engine = state.engine else { return }
        state.replace(engine.setKitMode(now))
        setAside = nil
        if now == "off" { clearOffer() } else { refresh(state) }
    }

    /// What taking the kit would change, in his words: "3 Lenses · 1 Camera".
    static func change(from had: [ViewModel.KitShoot], to kit: [ViewModel.KitShoot]) -> String {
        let key = { (s: String) in s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        let lensesHad = Set(had.flatMap(\.lenses).map(key))
        let lenses = Set(kit.flatMap(\.lenses).map(key)).subtracting(lensesHad).count
        let camsHad = Set(had.flatMap(\.cameras).map { key($0.label) + "|" + key($0.body) })
        let cams = Set(kit.flatMap(\.cameras).map { key($0.label) + "|" + key($0.body) }).subtracting(camsHad).count
        let modifiers = Set(kit.flatMap { $0.modifiers ?? [] }.map(key))
            .subtracting(had.flatMap { $0.modifiers ?? [] }.map(key)).count
        let filters = Set(kit.flatMap { $0.filters ?? [] }.map(key))
            .subtracting(had.flatMap { $0.filters ?? [] }.map(key)).count
        var parts: [String] = []
        if lenses > 0 { parts.append("\(lenses) \(lenses == 1 ? "Lens" : "Lenses")") }
        if modifiers > 0 { parts.append("\(modifiers) \(modifiers == 1 ? "Modifier" : "Modifiers")") }
        if filters > 0 { parts.append("\(filters) \(filters == 1 ? "Filter" : "Filters")") }
        if cams > 0 { parts.append("\(cams) \(cams == 1 ? "Camera" : "Cameras")") }
        return parts.isEmpty ? "Spec Sheet Changed" : "Spec Sheet Changed · " + parts.joined(separator: " · ")
    }

    /// The kit as `recordkit` takes it.
    static func kitJSON(_ kit: [ViewModel.KitShoot]) -> String? {
        let list: [[String: Any]] = kit.map {
            ["name": $0.name, "start": $0.start, "end": $0.end, "sheet": $0.sheet, "lead": $0.lead,
             "cameras": $0.cameras.map { ["label": $0.label, "body": $0.body] }, "lenses": $0.lenses,
             "modifiers": $0.modifiers ?? [], "filters": $0.filters ?? []]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: list, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // ---- changing it ---------------------------------------------------------

    /// **Change boxes of one sheet.** `seen` is what this screen showed, so a
    /// box changed in Notion since is refused rather than written over.
    func save(_ sheet: Sheet, changes: [String: String], seen: [String: String], state: ShellState,
              done: @escaping (Bool) -> Void = { _ in }) {
        send(["sheet": sheet.sheet, "changes": changes, "seen": seen, "by": Host.current().localizedName ?? "Mac"],
             state: state, ok: "Saved · waiting for Notion", done: done)
    }

    /// **Add to Spec Sheet** — a shot's lens, camera body, modifier or filter
    /// onto the sheet of the shoot the engine named.
    func add(lens: String? = nil, body: String? = nil, label: String = "", modifier: String? = nil,
             filter: String? = nil, for off: ViewModel.OffKit, state: ShellState) {
        guard let kit = state.view?.project.kit, off.shoot < kit.count else { return }
        let shoot = kit[off.shoot]
        var add: [String: Any] = [:]
        if let lens { add["lens"] = lens }
        if let body { add["camera"] = body; add["label"] = label }
        if let modifier { add["modifier"] = modifier }
        if let filter { add["filter"] = filter }
        let name = lens ?? body ?? modifier ?? filter ?? ""
        send(["sheet": shoot.sheet.isEmpty ? shoot.name : shoot.sheet, "add": add,
              "by": Host.current().localizedName ?? "Mac"],
             state: state, ok: "\(name) added to \(shoot.name.isEmpty ? "the" : shoot.name + "'s") Spec Sheet") { [weak state] good in
            if !good, let state { state.say(self.said) }
        }
    }

    /// **Add to the sheet from a Kit list** (Kit Links): a lens, modifier or
    /// filter onto the lead shoot's sheet, by the list it was typed in.
    func addToLead(field: String, name: String, state: ShellState) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let kit = state.view?.project.kit, !kit.isEmpty else {
            said = "No Spec Sheet yet"
            return
        }
        let off = ViewModel.OffKit(shoot: kit.firstIndex { $0.lead } ?? 0)
        switch field {
        case "lens": add(lens: name, for: off, state: state)
        case "modifiers": add(modifier: name, for: off, state: state)
        case "lens_filters": add(filter: name, for: off, state: state)
        default: break
        }
    }

    // ---- what is linked (Kit Links, 2026-10-14) ---------------------------------

    /// The lists the spec sheet feeds. Camera is fed too, by body, and has
    /// its own page.
    static let kitLists = ["lens", "modifiers", "lens_filters"]

    /// Whether the film's lists follow its sheet: Ask or Sync.
    static func linked(_ state: ShellState) -> Bool { (state.view?.project.kitMode ?? "off") != "off" }

    /// **Each spec-sheet list its own color, drawn like the shot list's tags**
    /// (his mockup, 2026-10-16: "should feel a part of a system"). Lenses
    /// wear the shot list's lens color.
    static func ink(_ box: String) -> String {
        switch box {
        case "lens", "lenses": return Brand.columnInks["lens"] ?? "2C7A7B"
        case "lens_filters", "filters": return "7B4BC4"
        case "modifiers": return "2F7A44"
        case "body", "format", "capture", "desqueeze": return "2B6CB0"
        case "colour": return "A33574"
        default: return "9A6B10"
        }
    }

    /// The switch as the rail's chip says it: Synced, Ask, Off.
    static func chipName(_ mode: String) -> String {
        mode == "follow" ? "Synced" : mode == "ask" ? "Ask" : "Off"
    }

    /// **Whether this film has a sheet to sync with**: it is on the shared
    /// project record (its card is laid on), or it was linked to a Notion
    /// project before the record. The server finds the sheet either way.
    static func hasSheet(_ state: ShellState) -> Bool {
        guard let project = state.view?.project else { return false }
        return project.card || !project.consolePage.isEmpty
    }

    /// The switch, as he says it: Off, Ask, Sync.
    static func modeName(_ mode: String) -> String {
        mode == "follow" ? "Sync" : mode == "ask" ? "Ask" : "Off"
    }

    /// The engine's `lens_key`: "35 MM" = "35mm" = "35".
    static func lensKey(_ s: String) -> String {
        var k = s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .replacingOccurrences(of: "\u{2013}", with: "-")
        if k.hasSuffix(" mm") { k = String(k.dropLast(3)) + "mm" }
        if !k.isEmpty, k.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == "-") }) { k += "mm" }
        return k
    }

    static func nameKey(_ s: String) -> String {
        s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .replacingOccurrences(of: "\u{2013}", with: "-")
    }

    /// **Is this term on the film's sheets?** Matched as the engine matches:
    /// the same name, or one naming the other with its maker. With no kit
    /// taken there is nothing to be off, so everything is on.
    static func onSheet(_ field: String, _ term: String, kit: [ViewModel.KitShoot]) -> Bool {
        guard !kit.isEmpty else { return true }
        let picks: [String]
        let key: (String) -> String
        switch field {
        case "lens": picks = kit.flatMap(\.lenses); key = lensKey
        case "modifiers": picks = kit.flatMap { $0.modifiers ?? [] }; key = nameKey
        case "lens_filters": picks = kit.flatMap { $0.filters ?? [] }; key = nameKey
        default: return true
        }
        let want = key(term)
        guard !want.isEmpty else { return true }
        return picks.map(key).contains { have in
            have == want || have.hasSuffix(" " + want) || want.hasSuffix(" " + have)
        }
    }

    /// "Edited 2 min ago" when the sheet's change time is known.
    static func ago(_ iso: String) -> String {
        let read = ISO8601DateFormatter()
        read.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let when = read.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        let minutes = Int(Date().timeIntervalSince(when) / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        if minutes < 60 * 24 { return "\(minutes / 60) h ago" }
        let day = DateFormatter()
        day.dateFormat = "d MMM"
        return day.string(from: when)
    }

    private func send(_ body: [String: Any], state: ShellState, ok: String, done: @escaping (Bool) -> Void) {
        guard let path = state.projectPath, let project = Relay.projectId(at: path) else {
            said = "This film is not on the portal yet"
            done(false)
            return
        }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let got = try await Self.ask(project, body: body)
                take(got, into: state)
                // His own change, from this Mac: Ask has nothing to ask him
                if mode(state) == "ask", let kit = offered { takeKit(kit, into: state) }
                said = ok
                state.say(ok)
                done(true)
            } catch let trouble as Trouble {
                said = trouble.said
                done(false)
            } catch {
                said = "Portal not reached"
                done(false)
            }
        }
    }
}

/// **Project Settings › Spec Sheet.** Each shoot's sheet, its boxes editable,
/// the picks it gives the shot list under Lenses.
struct SpecSheetPage: View {
    @ObservedObject var state: ShellState
    @ObservedObject private var sheets = SpecSheets.shared
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    @State private var chosen: String?
    @State private var typed: [String: String] = [:]
    @State private var shownFor: String?
    /// Which box's New… is open ("lenses", "body", "body#1"), and its words.
    @State private var newFor: String?
    @State private var newText = ""

    private var current: SpecSheets.Sheet? {
        sheets.sheets.first { $0.id == chosen } ?? sheets.sheets.first { $0.lead } ?? sheets.sheets.first
    }

    private var readOnly: Bool { !sheets.editable || (current?.sheet.isEmpty ?? true) }

    private var mode: String { state.view?.project.kitMode ?? "off" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // **Where this sheet lives** (Kit Links, 2026-10-14): the page is the
            // sheet itself, not a copy, and says so.
            // Where it lives and when it changed is the group's one status
            // line, above (2026-10-16); here only the way to the console.
            // **The switch** (2026-10-13), Off on every film until he says.
            // Follow is called Sync on screen (his word, 2026-10-14); the
            // record still says `follow`.
            Field("Lists") {
                HStack {
                    Segmented(selection: Binding(get: { mode }, set: { sheets.setMode($0, state: state) }), items: [
                        .init(value: "off", title: "Off"),
                        .init(value: "ask", title: "Ask"),
                        .init(value: "follow", title: "Sync"),
                    ], quiet: true)
                    .fixedSize()
                    Spacer(minLength: 0)
                    if SpecSheets.hasSheet(state) {
                        Button("Open in Console") { Console.openProject(page: state.view?.project.consolePage ?? "") }
                    }
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 10)
            if let offer = sheets.offer {
                HStack(spacing: 10) {
                    Text(offer).sans(13, weight: .semibold)
                    Spacer(minLength: 0)
                    Button("Take") { sheets.takeOffered(state) }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: Brand.radius).fill(Brand.ground(dark)))
                .padding(.horizontal, 18).padding(.bottom, 10)
            }
            if sheets.sheets.isEmpty {
                EmptyState(title: sheets.read ? "No Spec Sheet yet" : (sheets.busy ? "Loading" : "Not on the portal"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let sheet = current {
                if sheets.sheets.count > 1 {
                    Picker("Shoot", selection: Binding(get: { sheet.id }, set: { pick($0) })) {
                        ForEach(sheets.sheets) { one in Text(one.title).tag(one.id) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, 18).padding(.bottom, 8)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        camerasBox(sheet)
                        let shown = SpecSheets.boxes.filter { $0.key != "body" }
                        ForEach(Array(shown.enumerated()), id: \.element.key) { i, box in
                            let group = SpecSheets.group(box.key)
                            if i > 0 && SpecSheets.group(shown[i - 1].key) != group {
                                Text(group).sans(11, weight: .semibold).foregroundStyle(Brand.ink3(dark))
                                    .padding(.top, 6)
                            }
                            if box.key == "fps", let ratios = sheet.ratios, !ratios.isEmpty {
                                readOnlyList("Aspect Ratio", ratios.map { "\($0.name)  \($0.ratio)" + ($0.main ? "  Main" : "") })
                            }
                            field(box.key, box.label, sheet: sheet)
                        }
                        if let fin = sheet.finishing, !fin.isEmpty {
                            Text("Deliverables").sans(11, weight: .semibold).foregroundStyle(Brand.ink3(dark))
                                .padding(.top, 6)
                            readOnlyList("Finishing Resolutions", fin.map { [$0.title, $0.resolution, $0.note].filter { !$0.isEmpty }.joined(separator: " · ") })
                        }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 6)
                }
            }
            Divider().overlay(Brand.rule(dark))
            HStack(spacing: 8) {
                if let sheet = current, !sheet.failed.isEmpty {
                    Text("Not written: \(sheet.failed)").sans(11).foregroundStyle(Brand.ink2(dark)).lineLimit(2)
                } else if current != nil && readOnly {
                    Text(sheets.editable ? "No Sheet" : "Read Only")
                        .sans(11).foregroundStyle(Brand.ink3(dark)).lineLimit(1)
                } else {
                    Text(sheets.said).sans(11).foregroundStyle(Brand.ink3(dark)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button("Refresh") { sheets.refresh(state) }
                    .disabled(sheets.busy)
                Button("Save") { save() }
                    .disabled(readOnly || sheets.busy || changes().isEmpty)
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
        }
        .onAppear {
            sheets.refresh(state)
            fill()
        }
        .onChange(of: sheets.sheets) { _, _ in fill() }
    }

    // ---- pills (2026-10-13: "pills, same as notion … then we stick to it") ----

    private func lines(_ key: String) -> [String] {
        (typed[key] ?? "").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    private func setLines(_ key: String, _ list: [String]) { typed[key] = list.joined(separator: "\n") }

    /// One box: its name, then its pills wrapping, then Add. A pill's menu
    /// takes it off; Add offers Notion's other pills, or a new one.
    private func field(_ key: String, _ label: String, sheet: SpecSheets.Sheet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label).fieldLabel(dark)
                if sheet.waiting.contains(key) {
                    Text("Waiting").sans(10).foregroundStyle(Brand.ink3(dark))
                }
                Spacer(minLength: 0)
                if key == "lenses", !lines(key).isEmpty {
                    // every lens as plain text, one per line (his ask)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(lines(key).joined(separator: "\n"), forType: .string)
                        state.say("Lenses copied")
                    }
                    .buttonStyle(.plain).sans(11).foregroundStyle(Brand.ink2(dark))
                }
            }
            WrappingRow(spacing: 6, runSpacing: 6) {
                ForEach(lines(key), id: \.self) { name in
                    Menu {
                        Button("Remove") { setLines(key, lines(key).filter { $0 != name }) }
                    } label: {
                        HStack(spacing: 5) {
                            Chip(text: name, colour: Brand.data(SpecSheets.ink(key), dark), density: 1)
                            if key == "lenses", let cf = sheet.lens_cf?[name], !cf.isEmpty {
                                Text(cf).sans(11).foregroundStyle(Brand.ink3(dark))
                            }
                        }
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .disabled(readOnly)
                }
                if !readOnly { addPill(key, label: label) }
                if lines(key).isEmpty && readOnly {
                    Text("None").sans(13).foregroundStyle(Brand.ink3(dark))
                }
            }
        }
    }

    /// Add: Notion's other pills for this box, then New….
    private func addPill(_ key: String, label: String) -> some View {
        let have = Set(lines(key).map { $0.lowercased() })
        let rest = (sheets.pills[key] ?? []).filter { !have.contains($0.name.lowercased()) }
        return Menu {
            ForEach(rest, id: \.self) { pill in
                Button(pill.name) { setLines(key, lines(key) + [pill.name]) }
            }
            if !rest.isEmpty { Divider() }
            Button("New \(label)…") { newFor = key; newText = "" }
        } label: {
            Text("Add").sans(11, weight: .medium).foregroundStyle(Brand.ink2(dark))
                .padding(.horizontal, 8).frame(height: 22)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Brand.ink3(dark).opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .popover(isPresented: Binding(get: { newFor == key }, set: { if !$0 { newFor = nil } })) {
            HStack(spacing: 8) {
                FieldText(placeholder: label, text: $newText)
                    .frame(width: 200)
                    .onSubmit { addNew(key) }
                Button("Add") { addNew(key) }.disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
        }
    }

    private func addNew(_ key: String) {
        let name = newText.replacingOccurrences(of: ",", with: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if !name.isEmpty, !lines(key).contains(where: { $0.lowercased() == name.lowercased() }) {
            setLines(key, lines(key) + [name])
        }
        newFor = nil
    }

    /// **The cameras, the old way** (his ask, 2026-10-13): a row each, its
    /// label beside it, the camera itself a pill picked from Notion's. The
    /// label goes on the project record; Notion keeps only the camera.
    private func camerasBox(_ sheet: SpecSheets.Sheet) -> some View {
        let rows = lines("body").map(Self.split)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(rows.count > 1 ? "Cameras" : "Camera").fieldLabel(dark)
                if sheet.waiting.contains("body") {
                    Text("Waiting").sans(10).foregroundStyle(Brand.ink3(dark))
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { at, row in
                HStack(spacing: 10) {
                    FieldText(placeholder: "\(Character(UnicodeScalar(65 + min(at, 25))!)) Cam",
                              text: Binding(get: { row.label }, set: { setCamera(at, label: $0, body: nil) }))
                        .frame(width: 96)
                        .disabled(readOnly)
                    Menu {
                        ForEach(sheets.pills["body"] ?? [], id: \.self) { pill in
                            Button(pill.name) { setCamera(at, label: nil, body: pill.name) }
                        }
                        Divider()
                        Button("New Camera…") { newFor = "body#\(at)"; newText = "" }
                        Button("Remove") { setLines("body", lines("body").enumerated().filter { $0.offset != at }.map(\.element)) }
                    } label: {
                        Chip(text: row.body, colour: Brand.data(SpecSheets.ink("body"), dark), density: 1)
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .disabled(readOnly)
                    .popover(isPresented: Binding(get: { newFor == "body#\(at)" }, set: { if !$0 { newFor = nil } })) {
                        HStack(spacing: 8) {
                            FieldText(placeholder: "Camera", text: $newText).frame(width: 200)
                                .onSubmit { setCamera(at, label: nil, body: newText); newFor = nil }
                            Button("Use") { setCamera(at, label: nil, body: newText); newFor = nil }
                        }
                        .padding(12)
                    }
                    Spacer(minLength: 0)
                }
            }
            if !readOnly {
                Menu {
                    ForEach(sheets.pills["body"] ?? [], id: \.self) { pill in
                        Button(pill.name) { addCamera(pill.name) }
                    }
                    Divider()
                    Button("New Camera…") { newFor = "body"; newText = "" }
                } label: {
                    Text("Add Camera").sans(11, weight: .medium).foregroundStyle(Brand.ink2(dark))
                        .padding(.horizontal, 8).frame(height: 22)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Brand.ink3(dark).opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .popover(isPresented: Binding(get: { newFor == "body" }, set: { if !$0 { newFor = nil } })) {
                    HStack(spacing: 8) {
                        FieldText(placeholder: "Camera", text: $newText).frame(width: 200)
                            .onSubmit { addCamera(newText); newFor = nil }
                        Button("Add") { addCamera(newText); newFor = nil }
                    }
                    .padding(12)
                }
            }
        }
    }

    /// "A Cam: Alexa 35" → ("A Cam", "Alexa 35"); a line with no label → ("", line).
    static func split(_ line: String) -> (label: String, body: String) {
        guard let colon = line.range(of: ": ") else { return ("", line) }
        let label = String(line[..<colon.lowerBound]).trimmingCharacters(in: .whitespaces)
        guard label.count <= 24, label.split(separator: " ").count <= 4, label.contains(where: \.isLetter) else { return ("", line) }
        return (label, String(line[colon.upperBound...]).trimmingCharacters(in: .whitespaces))
    }

    private func setCamera(_ at: Int, label: String?, body: String?) {
        var list = lines("body")
        guard at < list.count else { return }
        let was = Self.split(list[at])
        let l = (label ?? was.label).replacingOccurrences(of: ":", with: " ").trimmingCharacters(in: .whitespaces)
        let b = (body ?? was.body).replacingOccurrences(of: ",", with: " ").trimmingCharacters(in: .whitespaces)
        guard !b.isEmpty else { return }
        list[at] = l.isEmpty ? b : "\(l): \(b)"
        setLines("body", list)
    }

    private func addCamera(_ body: String) {
        let b = body.replacingOccurrences(of: ",", with: " ").trimmingCharacters(in: .whitespaces)
        guard !b.isEmpty else { return }
        let n = lines("body").count
        setLines("body", lines("body") + ["\(Character(UnicodeScalar(65 + min(n, 25))!)) Cam: \(b)"])
    }

    /// A list this page only shows: its label, then a line each.
    private func readOnlyList(_ label: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).fieldLabel(dark)
            ForEach(items, id: \.self) { Text($0).sans(13).foregroundStyle(Brand.ink2(dark)) }
        }
    }

    private func pick(_ id: String) {
        chosen = id
        fill(force: true)
    }

    /// What the boxes say, from the sheet — kept while he is typing in them.
    private func fill(force: Bool = false) {
        guard let sheet = current else { return }
        if !force, shownFor == sheet.id, !changes().isEmpty { return }
        shownFor = sheet.id
        typed = Dictionary(uniqueKeysWithValues: SpecSheets.boxes.map { ($0.key, sheet.camera[$0.key] ?? "") })
    }

    private func changes() -> [String: String] {
        guard let sheet = current, shownFor == sheet.id else { return [:] }
        var out: [String: String] = [:]
        for box in SpecSheets.boxes {
            let now = typed[box.key] ?? ""
            if now != (sheet.camera[box.key] ?? "") { out[box.key] = now }
        }
        return out
    }

    private func save() {
        guard let sheet = current else { return }
        let asked = changes()
        let seen = asked.keys.reduce(into: [String: String]()) { $0[$1] = sheet.camera[$1] ?? "" }
        sheets.save(sheet, changes: asked, seen: seen, state: state) { _ in fill(force: true) }
    }
}

/// **Ask: the Spec Sheet changed.** Over whichever tab is open, the way the
/// app's other held sentences are: what changed, Take, and ✕ for not now.
struct SpecSheetAsk: View {
    @ObservedObject var state: ShellState
    @ObservedObject private var sheets = SpecSheets.shared

    var body: some View {
        if let offer = sheets.offer, sheets.mode(state) == "ask" {
            HStack(spacing: 10) {
                Image(systemName: "doc.text").font(.system(size: 11))
                Text(offer).sans(13)
                Button("Take") { sheets.takeOffered(state) }
                    .buttonStyle(.plain)
                    .sans(13, weight: .semibold)
                Button { sheets.setOfferAside() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.plain)
                    .help("Not Now")
            }
            .foregroundStyle(Brand.onImage)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Capsule().fill(Brand.hex("2C5AA0")))
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// **A spec sheet pill**, in the colour Notion gave it — Notion's own tag
/// colours, light and dark (the web screens use the same table,
/// `hub/src/specpills.js`).
struct SpecPill: View {
    let name: String
    let colour: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let (ground, ink) = SpecPill.colours(colour, dark: scheme == .dark)
        Text(name)
            .sans(13, weight: .medium)
            .lineLimit(1)
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 5).fill(ground))
    }

    static func colours(_ name: String, dark: Bool) -> (Color, Color) {
        let table: [String: (String, String, String, String)] = [
            "default": ("E9E9E7", "37352F", "3A3A3A", "E6E6E4"), "gray": ("E3E2E0", "32302C", "5A5A5A", "F0F0EE"),
            "brown": ("EEE0DA", "442A1E", "603B2C", "F3E8E2"), "orange": ("FADEC9", "49290E", "854C1D", "FBEBDD"),
            "yellow": ("FDECC8", "402C1B", "89632A", "FCF1DA"), "green": ("DBEDDB", "1C3829", "2B593F", "E3F1E5"),
            "blue": ("D3E5EF", "183347", "28456C", "E1EDF6"), "purple": ("E8DEEE", "412454", "492F64", "EFE7F5"),
            "pink": ("F5E0E9", "4C2337", "69314C", "F7E6EE"), "red": ("FFE2DD", "5D1715", "6E3630", "FBE6E3"),
        ]
        let c = table[name] ?? table["default"]!
        return dark ? (Brand.hex(c.2), Brand.hex(c.3)) : (Brand.hex(c.0), Brand.hex(c.1))
    }
}

/// **Kit Links** (2026-10-14): the two colours that say how a thing is tied
/// to the spec sheet. Blue: it comes from the sheet. Amber: a shot uses it
/// and the sheet does not have it.
enum KitLinks {
    static let blue = "0A6CE8"
    static let amber = "D97706"
}
