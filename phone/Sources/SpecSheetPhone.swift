import SwiftUI
import UIKit

/// **The Camera Spec Sheet on the phone** — the Mac's `SpecSheets`
/// (studio/Sources/SpecSheet.swift), so Project Settings' Spec Sheet group
/// says the same things on both (Studio Settings, sorted, 2026-10-16).
///
/// It asks the portal's kit door (`/kit/<project>`, the relay's password, the
/// way the Mac asks) and takes the kit into the film through the engine
/// (`recordkit`) as the film's switch says: Off nothing flows; Ask offers
/// Take; Sync takes it whenever the sheet is read. Adding a term from a list
/// goes back as the same `add` the Mac sends.
@MainActor
final class PhoneSpecSheet: ObservableObject {
    struct Sheet: Decodable, Equatable, Identifiable {
        var shoot: String = ""
        var name: String = ""
        var start: String = ""
        var end: String = ""
        var sheet: String = ""
        var lead: Bool = false
        var camera: [String: String] = [:]
        var cameras: [Engine.KitCamera] = []
        var lenses: [String] = []
        var modifiers: [String]?
        var filters: [String]?
        var lens_cf: [String: String]?
        var ratios: [Ratio]?
        var finishing: [Finishing]?
        /// Boxes asked for and not yet written; why the last change was not.
        var waiting: [String]?
        var failed: String?
        var id: String { sheet.isEmpty ? "shoot:" + shoot + name : sheet }
        var title: String { name.isEmpty ? "Project" : name }
    }
    struct Ratio: Decodable, Equatable, Hashable { var name: String; var ratio: String; var main: Bool }
    struct Finishing: Decodable, Equatable, Hashable { var title: String; var resolution: String; var note: String }

    private struct Answer: Decodable {
        var ok: Bool?
        var why: String?
        var shoots: [Sheet]?
        var updated: String?
        var editable: Bool?
        var pills: [String: [Pill]]?
    }

    /// One pill a box offers, in the colour Notion gave it.
    struct Pill: Decodable, Equatable, Hashable { var name: String; var color: String }

    @Published private(set) var sheets: [Sheet] = []
    @Published private(set) var read = false
    @Published private(set) var updated = ""
    @Published private(set) var busy = false
    @Published var said = ""
    /// Whether the boxes can be changed from here, and each box's pills.
    @Published private(set) var editable = false
    @Published private(set) var pills: [String: [Pill]] = [:]
    /// Ask: the kit read and not yet taken, and what it would change.
    @Published private(set) var offered: [Engine.KitShoot]?
    @Published private(set) var offer: String?

    private weak var session: Session?

    init(session: Session) { self.session = session }

    // ---- the door ----------------------------------------------------------

    private var project: String? {
        guard let session else { return nil }
        return Relay.projectId(at: session.folder.url)
    }

    /// Whether this project has a sheet to sync with: on the shared record,
    /// or linked to a Notion project before the record.
    var hasSheet: Bool {
        guard let p = session?.view?.project else { return false }
        return p.card || !p.consolePage.isEmpty
    }

    var mode: String { session?.view?.project.kitMode ?? "off" }
    var linked: Bool { mode != "off" }

    private nonisolated static func ask(_ project: String, body: [String: Any]?) async throws -> Answer {
        guard let address = PortalLine.address(), let token = PortalLine.token(),
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
        if status == 401 { throw Trouble(said: "Portal refused this iPhone") }
        if status == 404 { throw Trouble(said: "Not on the portal") }
        if let got = try? JSONDecoder().decode(Answer.self, from: data) {
            if status != 200, let why = got.why { throw Trouble(said: why) }
            if status == 200 { return got }
        }
        throw Trouble(said: "Couldn't reach the portal")
    }

    struct Trouble: Error { let said: String }

    // ---- reading -------------------------------------------------------------

    /// Read the sheets, and take the kit as the switch says.
    func refresh() {
        guard let project, hasSheet else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                take(try await Self.ask(project, body: nil))
            } catch let trouble as Trouble {
                said = trouble.said
            } catch {
                said = "Portal not reached"
            }
        }
    }

    private func take(_ got: Answer) {
        sheets = got.shoots ?? []
        if let when = got.updated { updated = when }
        if let e = got.editable { editable = e }
        if let p = got.pills { pills = p }
        read = true
        let kit = sheets.map {
            Engine.KitShoot(name: $0.name, start: $0.start, end: $0.end, sheet: $0.sheet, lead: $0.lead,
                            cameras: $0.cameras, lenses: $0.lenses, modifiers: $0.modifiers, filters: $0.filters)
        }
        let had = session?.view?.project.kit ?? []
        if had == kit { offered = nil; offer = nil; return }
        switch mode {
        case "follow": takeKit(kit)
        case "ask": offered = kit; offer = Self.change(from: had, to: kit)
        default: offered = nil; offer = nil
        }
    }

    private func takeKit(_ kit: [Engine.KitShoot]) {
        guard let json = Self.kitJSON(kit) else { return }
        session?.takeKit(json)
        offered = nil
        offer = nil
    }

    func takeOffered() {
        guard let kit = offered else { return }
        takeKit(kit)
        said = "Spec Sheet taken"
    }

    func setMode(_ now: String) {
        guard now != mode else { return }
        session?.setKitMode(now)
        if now == "off" { offered = nil; offer = nil } else { refresh() }
    }

    // ---- changing the boxes ----------------------------------------------------

    /// **Change boxes of one sheet**, the Mac's Save: `seen` is what this
    /// screen showed, so a box changed elsewhere since is refused rather
    /// than written over.
    func save(_ one: Sheet, changes: [String: String], done: @escaping (Bool) -> Void) {
        guard let project, !changes.isEmpty else { done(false); return }
        let seen = changes.keys.reduce(into: [String: String]()) { $0[$1] = one.camera[$1] ?? "" }
        let body: [String: Any] = ["sheet": one.sheet, "changes": changes, "seen": seen, "by": UIDevice.current.name]
        busy = true
        Task {
            defer { busy = false }
            do {
                take(try await Self.ask(project, body: body))
                // His own change: Ask has nothing to ask him.
                if mode == "ask", let kit = offered { takeKit(kit) }
                said = "Saved"
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

    // ---- adding --------------------------------------------------------------

    /// **Add to Sheet** from a Lenses, Filters or Modifiers list: onto the
    /// lead shoot's sheet, the same as the Mac's.
    func addToLead(field: String, name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let kit = session?.view?.project.kit, !kit.isEmpty, let project else {
            said = "No Spec Sheet yet"
            return
        }
        let shoot = kit.first { $0.lead } ?? kit[0]
        let key = field == "lens" ? "lens" : field == "modifiers" ? "modifier" : "filter"
        let body: [String: Any] = ["sheet": shoot.sheet.isEmpty ? shoot.name : shoot.sheet,
                                   "add": [key: name], "by": UIDevice.current.name]
        busy = true
        Task {
            defer { busy = false }
            do {
                take(try await Self.ask(project, body: body))
                said = "\(name) added to Spec Sheet"
            } catch let trouble as Trouble {
                said = trouble.said
            } catch {
                said = "Portal not reached"
            }
        }
    }

    /// **Add to Spec Sheet** from a shot (the Mac's shot menu): what the
    /// shot uses and the sheet lacks, onto the shoot's sheet the engine named.
    func add(_ off: Engine.Row.OffKit, lens: String? = nil, body: String? = nil, label: String = "",
             modifier: String? = nil, filter: String? = nil) {
        guard let kit = session?.view?.project.kit, off.shoot < kit.count, let project else {
            said = "No Spec Sheet yet"
            return
        }
        let shoot = kit[off.shoot]
        var add: [String: Any] = [:]
        if let lens { add["lens"] = lens }
        if let body { add["camera"] = body; add["label"] = label }
        if let modifier { add["modifier"] = modifier }
        if let filter { add["filter"] = filter }
        let name = lens ?? body ?? modifier ?? filter ?? ""
        let ask: [String: Any] = ["sheet": shoot.sheet.isEmpty ? shoot.name : shoot.sheet, "add": add,
                                  "by": UIDevice.current.name]
        busy = true
        Task {
            defer { busy = false }
            do {
                take(try await Self.ask(project, body: ask))
                said = "\(name) added to Spec Sheet"
            } catch let trouble as Trouble {
                said = trouble.said
            } catch {
                said = "Portal not reached"
            }
        }
    }

    // ---- words -----------------------------------------------------------------

    static let kitLists = ["lens", "modifiers", "lens_filters"]

    /// Each spec-sheet list its own colour, drawn like the shot list's tags.
    static func ink(_ box: String) -> String {
        switch box {
        case "lens", "lenses": return "2C7A7B"
        case "lens_filters", "filters": return "7B4BC4"
        case "modifiers": return "2F7A44"
        case "body", "format", "capture", "desqueeze": return "2B6CB0"
        case "colour": return "A33574"
        default: return "9A6B10"
        }
    }

    static func modeName(_ mode: String) -> String {
        mode == "follow" ? "Sync" : mode == "ask" ? "Ask" : "Off"
    }

    static let boxes: [(key: String, label: String)] = [
        ("body", "Camera"), ("format", "Shooting Format"), ("capture", "Capture Resolution"),
        ("lenses", "Lenses"), ("desqueeze", "Desqueeze"), ("fps", "Frame Rate"), ("codec", "Codec"),
        ("colour", "Color Space"),
    ]

    static func change(from had: [Engine.KitShoot], to kit: [Engine.KitShoot]) -> String {
        let key = { (s: String) in s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        let lenses = Set(kit.flatMap(\.lenses).map(key)).subtracting(had.flatMap(\.lenses).map(key)).count
        let cams = Set(kit.flatMap(\.cameras).map { key($0.label) + "|" + key($0.body) })
            .subtracting(had.flatMap(\.cameras).map { key($0.label) + "|" + key($0.body) }).count
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

    static func kitJSON(_ kit: [Engine.KitShoot]) -> String? {
        let list: [[String: Any]] = kit.map {
            ["name": $0.name, "start": $0.start, "end": $0.end, "sheet": $0.sheet, "lead": $0.lead,
             "cameras": $0.cameras.map { ["label": $0.label, "body": $0.body] }, "lenses": $0.lenses,
             "modifiers": $0.modifiers ?? [], "filters": $0.filters ?? []]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: list, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func lensKey(_ s: String) -> String {
        var k = nameKey(s)
        if k.hasSuffix(" mm") { k = String(k.dropLast(3)) + "mm" }
        if !k.isEmpty, k.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == "-") }) { k += "mm" }
        return k
    }

    static func nameKey(_ s: String) -> String {
        s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .replacingOccurrences(of: "\u{2013}", with: "-")
    }

    /// Is this term on the film's sheets? With no kit, everything is.
    static func onSheet(_ field: String, _ term: String, kit: [Engine.KitShoot]) -> Bool {
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

    /// "2 min ago" when the sheet's change time is known.
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
}

// ---- the screens ---------------------------------------------------------------

/// **The Spec Sheet group's one line**, the Mac's `SpecStatus`.
struct SpecStatusLine: View {
    @EnvironmentObject private var session: Session
    @ObservedObject var sheet: PhoneSpecSheet

    var body: some View {
        HStack(spacing: 6) {
            if sheet.linked {
                Circle().fill(Color(markHex: "2F9E5B")).frame(width: 6, height: 6)
                let ago = PhoneSpecSheet.ago(sheet.updated)
                Text("Shared with Console, portal and iPhone" + (ago.isEmpty ? "" : " · Updated \(ago)"))
            } else if sheet.hasSheet {
                Text("Not synced")
                Spacer(minLength: 0)
                Button("Sync with Spec Sheet") { sheet.setMode("follow") }
                    .font(.footnote)
            } else {
                Text("No Spec Sheet")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .textCase(nil)
    }
}

/// **Spec Sheet ▸ Camera**: the switch, Ask's offer, and each shoot's sheet
/// as the portal holds it. The boxes are changed in Projects Console or
/// Studio on the Mac.
struct SpecSheetView: View {
    @EnvironmentObject private var session: Session
    @ObservedObject var sheet: PhoneSpecSheet
    @State private var editing: PhoneSpecSheet.Sheet?

    var body: some View {
        List {
            Section {
                Picker("Lists", selection: Binding(get: { sheet.mode }, set: { sheet.setMode($0) })) {
                    Text("Off").tag("off")
                    Text("Ask").tag("ask")
                    Text("Sync").tag("follow")
                }
                .disabled(!sheet.hasSheet)
                if let offer = sheet.offer {
                    HStack {
                        Text(offer).font(.footnote)
                        Spacer()
                        Button("Take") { sheet.takeOffered() }
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    SpecStatusLine(sheet: sheet)
                    if !sheet.said.isEmpty { Text(sheet.said) }
                }
            }

            ForEach(sheet.sheets) { one in
                Section {
                    ForEach(PhoneSpecSheet.boxes, id: \.key) { box in
                        let items = lines(one, box.key)
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(box.label).font(.footnote).foregroundStyle(.secondary)
                                Chips(tags: items.map {
                                    .init(text: $0, ink: .chosen(PhoneSpecSheet.ink(box.key)))
                                }, roomy: true)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    if let ratios = one.ratios, !ratios.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Aspect Ratio").font(.footnote).foregroundStyle(.secondary)
                            ForEach(ratios, id: \.self) { r in
                                HStack {
                                    Text(r.ratio).fontWeight(.medium)
                                    if !r.name.isEmpty, r.name != r.ratio { Text(r.name).foregroundStyle(.secondary) }
                                    Spacer()
                                    if r.main { Text("Main").font(.caption2).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                    if let finishing = one.finishing, !finishing.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Finishing Resolutions").font(.footnote).foregroundStyle(.secondary)
                            ForEach(finishing, id: \.self) { f in
                                Text([f.title, f.resolution, f.note].filter { !$0.isEmpty }.joined(separator: " · "))
                            }
                        }
                    }
                    if let failed = one.failed, !failed.isEmpty {
                        Text("Not written: \(failed)").font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    HStack {
                        Text(sheet.sheets.count > 1 ? one.title : "Camera")
                        Spacer()
                        if sheet.editable, !one.sheet.isEmpty {
                            Button("Edit") { editing = one }
                                .font(.footnote.weight(.semibold))
                                .textCase(nil)
                                .accessibilityIdentifier("spec.edit")
                        }
                    }
                }
            }

            if sheet.hasSheet {
                Section {
                    Button("Open in Projects Console") { ConsoleLink.open(session) }
                }
            }
        }
        .navigationTitle("Camera")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { sheet.refresh() }
        .overlay {
            if !sheet.hasSheet {
                ContentUnavailableView("No Spec Sheet", systemImage: "camera")
            } else if sheet.busy && !sheet.read {
                ProgressView()
            }
        }
        .onAppear { if !sheet.read { sheet.refresh() } }
        .sheet(item: $editing) { one in
            SpecSheetEditor(sheet: sheet, one: one)
        }
    }

    private func lines(_ one: PhoneSpecSheet.Sheet, _ key: String) -> [String] {
        var out = (one.camera[key] ?? "").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if key == "lenses", let cf = one.lens_cf {
            out = out.map { line in cf[line].map { line + "  " + $0 } ?? line }
        }
        return out
    }
}

/// **This project in Projects Console**, by the page it is linked to, and by
/// its title when nothing is. `projectsconsole://project`.
enum ConsoleLink {
    @MainActor
    static func open(_ session: Session, missing: @escaping () -> Void = {}) {
        var parts = URLComponents()
        parts.scheme = "projectsconsole"
        parts.host = "project"
        let page = session.view?.project.consolePage ?? ""
        let name = session.view?.project.shownTitle ?? session.entry.name
        parts.queryItems = (page.isEmpty ? [] : [URLQueryItem(name: "page", value: page)])
            + [URLQueryItem(name: "name", value: name)]
        guard let link = parts.url else { return }
        UIApplication.shared.open(link) { opened in
            if !opened { missing() }
        }
    }
}

/// **Editing one shoot's sheet** (the Mac's Spec Sheet page): cameras a row
/// each with their label, then every box as pills — tap one to take it off,
/// Add for the sheet's other pills or a new one. Save writes the boxes that
/// changed to the project record, as the Mac does.
struct SpecSheetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var sheet: PhoneSpecSheet
    let one: PhoneSpecSheet.Sheet

    @State private var typed: [String: String] = [:]
    @State private var newFor: String?
    @State private var newText = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Cameras") {
                    ForEach(Array(lines("body").enumerated()), id: \.offset) { at, line in
                        let row = Self.split(line)
                        HStack {
                            TextField("\(Self.letter(at)) Cam", text: Binding(get: { row.label },
                                                                             set: { setCamera(at, label: $0, body: nil) }))
                                .frame(width: 90)
                            Menu {
                                ForEach(sheet.pills["body"] ?? [], id: \.self) { pill in
                                    Button(pill.name) { setCamera(at, label: nil, body: pill.name) }
                                }
                                Divider()
                                Button("New Camera…") { newFor = "body#\(at)"; newText = "" }
                            } label: {
                                Text(row.body).foregroundStyle(Color(.label))
                            }
                            Spacer()
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) {
                                setLines("body", lines("body").enumerated().filter { $0.offset != at }.map(\.element))
                            }
                        }
                    }
                    Menu("Add Camera") {
                        ForEach(sheet.pills["body"] ?? [], id: \.self) { pill in Button(pill.name) { addCamera(pill.name) } }
                        Divider()
                        Button("New Camera…") { newFor = "body"; newText = "" }
                    }
                }
                ForEach(PhoneSpecSheet.boxes.filter { $0.key != "body" }, id: \.key) { box in
                    Section {
                        ForEach(lines(box.key), id: \.self) { name in
                            HStack {
                                Text(name)
                                if box.key == "lenses", let cf = one.lens_cf?[name], !cf.isEmpty {
                                    Text(cf).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .swipeActions {
                                Button("Remove", role: .destructive) { setLines(box.key, lines(box.key).filter { $0 != name }) }
                            }
                        }
                        .onMove { from, to in
                            var list = lines(box.key)
                            list.move(fromOffsets: from, toOffset: to)
                            setLines(box.key, list)
                        }
                        let have = Set(lines(box.key).map { $0.lowercased() })
                        let rest = (sheet.pills[box.key] ?? []).filter { !have.contains($0.name.lowercased()) }
                        Menu("Add") {
                            ForEach(rest, id: \.self) { pill in Button(pill.name) { setLines(box.key, lines(box.key) + [pill.name]) } }
                            if !rest.isEmpty { Divider() }
                            Button("New \(box.label)…") { newFor = box.key; newText = "" }
                        }
                    } header: {
                        HStack {
                            Text(box.key == "colour" ? "Color Space" : box.label)
                            if one.waiting?.contains(box.key) == true { Text("Waiting").textCase(nil) }
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.inactive))
            .navigationTitle(sheet.sheets.count > 1 ? one.title : "Camera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        sheet.save(one, changes: changes()) { ok in
                            saving = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(changes().isEmpty || saving)
                    .accessibilityIdentifier("spec.save")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !sheet.said.isEmpty, !saving {
                    Text(sheet.said).font(.footnote).foregroundStyle(.secondary).padding(.bottom, 6)
                }
            }
            .alert(newFor?.hasPrefix("body") == true ? "Camera" : "New", isPresented: Binding(get: { newFor != nil }, set: { if !$0 { newFor = nil } })) {
                TextField("Name", text: $newText)
                Button("Cancel", role: .cancel) {}
                Button("Add") { addNew() }
            }
        }
        .onAppear {
            typed = Dictionary(uniqueKeysWithValues: PhoneSpecSheet.boxes.map { ($0.key, one.camera[$0.key] ?? "") })
        }
    }

    private static func letter(_ at: Int) -> String { String(Character(UnicodeScalar(65 + min(at, 25))!)) }

    private func lines(_ key: String) -> [String] {
        (typed[key] ?? "").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    private func setLines(_ key: String, _ list: [String]) { typed[key] = list.joined(separator: "\n") }

    private func changes() -> [String: String] {
        var out: [String: String] = [:]
        for box in PhoneSpecSheet.boxes {
            let now = typed[box.key] ?? ""
            if now != (one.camera[box.key] ?? "") { out[box.key] = now }
        }
        return out
    }

    /// "A Cam: Alexa 35" → ("A Cam", "Alexa 35"); no label → ("", line).
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
        setLines("body", lines("body") + ["\(Self.letter(lines("body").count)) Cam: \(b)"])
    }

    private func addNew() {
        guard let key = newFor else { return }
        let name = newText.replacingOccurrences(of: ",", with: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        newFor = nil
        guard !name.isEmpty else { return }
        if key == "body" { addCamera(name); return }
        if key.hasPrefix("body#"), let at = Int(key.dropFirst(5)) { setCamera(at, label: nil, body: name); return }
        if !lines(key).contains(where: { $0.lowercased() == name.lowercased() }) { setLines(key, lines(key) + [name]) }
    }
}
