import SwiftUI
import PDFKit
import UniformTypeIdentifiers

// **Taking a script in, on the phone** (the Mac's Import Script, parity 3,
// 2026-10-16). A PDF becomes `page`/`run` lines, the engine reads the scenes
// and the cast, he reads what is about to happen and says yes. Every sentence
// on the confirm screen is the engine's. A draft from the project's Drive
// script folder comes the same way, through "New draft in Drive".

enum ScriptPDFPhone {
    /// The PDF as the engine reads it: a `page` line per page, a `run` line
    /// per line of text with where it sits (the Mac's `ScriptPDF.runs`).
    static func runs(from document: PDFDocument) -> String {
        var out = ""
        for index in 0 ..< document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            out += "page\t\(bounds.width)\t\(bounds.height)\n"
            guard let whole = page.selection(for: bounds) else { continue }
            for line in whole.selectionsByLine() {
                guard let said = line.string else { continue }
                let text = said.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty { continue }
                let box = line.bounds(for: page)
                if box.isNull || box.isInfinite { continue }
                let top = bounds.height - box.maxY
                out += "run\t\(box.minX)\t\(top)\t\(text.replacingOccurrences(of: "\t", with: " "))\n"
            }
        }
        return out
    }
}

/// What the engine read in a draft (the Mac's `ScriptReading`).
struct ScriptReadingPhone: Decodable {
    var pages: Int
    var script: String
    var scenes: Scenes
    var characters: Characters

    struct Scenes: Decodable {
        var detected: Int
        var matched: Int
        var new: Int
        var omitted: Int
        var rows: [Row]
        var goneFromTheDraft: [Gone]
        var movedNumber: [Moved]?
    }
    struct Moved: Decodable { var index: Int; var from: String; var to: String; var heading: String; var shots: Int }
    struct Row: Decodable {
        var label: String
        var heading: String
        var status: String
        var accepted: Bool
        var matched: Bool
        var length: String?
    }
    struct Gone: Decodable { var number: String; var heading: String; var shots: Int }
    struct Characters: Decodable { var detected: Int; var rows: [Person] }
    struct Person: Decodable { var name: String; var display: String; var speeches: Int }
}

struct ScriptPlanPhone: Decodable {
    var sentences: [String]
}

/// A draft waiting in Drive, as the review needs it.
struct DriveDraftPhone: Hashable {
    var project: String
    var file: String
    var label: String
}

struct ScriptFilePhone: Identifiable {
    let url: URL
    var drive: DriveDraftPhone?
    var id: String { url.path }
}

struct ImportScriptPhone: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    let file: ScriptFilePhone
    var done: () -> Void = {}

    enum Page: String, CaseIterable { case summary = "Summary", scenes = "Scenes", characters = "Characters" }

    @State private var page: Page = .summary
    @State private var runs = ""
    @State private var reading: ScriptReadingPhone?
    @State private var trouble: String?
    @State private var busy = true
    @State private var name = ""
    @State private var ticked: Set<Int> = []
    @State private var cast: Set<String> = []
    @State private var moving: Set<Int> = []
    @State private var number = true
    @State private var duplicates = true
    @State private var rooms = true
    @State private var merging = "regular"
    @State private var least = 0
    @State private var archiveOmitted = true
    @State private var plan: ScriptPlanPhone?

    @State private var contains: [String] = []
    @State private var forbid: [String] = ["CONTINUED:"]

    private var settings: String {
        "number=\(number ? 1 : 0),duplicates=\(duplicates ? 1 : 0),rooms=\(rooms ? 1 : 0)"
            + ",contains=\(contains.joined(separator: "|")),forbid=\(forbid.joined(separator: "|"))"
    }

    var body: some View {
        NavigationStack {
            Group {
                if let trouble {
                    ContentUnavailableView(trouble, systemImage: "doc.text")
                } else if busy || reading == nil {
                    ProgressView()
                } else if let plan {
                    confirm(plan)
                } else if let reading {
                    review(reading)
                }
            }
            .navigationTitle(file.drive?.label ?? "Import Script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(plan == nil ? "Cancel" : "Back") { if plan == nil { dismiss() } else { plan = nil } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if plan == nil {
                        Button("Review") { weigh() }.disabled(reading == nil || ticked.isEmpty)
                            .accessibilityIdentifier("import.review")
                    } else {
                        Button("Import") { take() }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("import.take")
                    }
                }
            }
        }
        .task { await open() }
    }

    // ---- reading -----------------------------------------------------------------

    private func open() async {
        name = Self.stem(file.url.lastPathComponent)
        let url = file.url
        let read: String? = await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let document = PDFDocument(url: url) else { return nil }
            return ScriptPDFPhone.runs(from: document)
        }.value
        guard let read else { trouble = "Can't open that PDF"; busy = false; return }
        guard read.contains("run\t") else { trouble = "No text in that PDF"; busy = false; return }
        runs = read
        // The project's own dials, when it has set them.
        if let engine = session.engine,
           let d = try? JSONDecoder().decode(Dials.self, from: engine.raw("detection")) {
            number = d.mustHaveANumber; duplicates = d.ignoreDuplicateNumbers; rooms = d.findSubSlugs
            contains = d.mustContain; forbid = d.neverContains
        }
        reread()
        busy = false
    }

    private struct Dials: Decodable {
        var mustHaveANumber: Bool; var ignoreDuplicateNumbers: Bool; var findSubSlugs: Bool
        var mustContain: [String]; var neverContains: [String]
    }

    /// Every turn of a dial is a whole fresh reading.
    private func reread() {
        guard let engine = session.engine, !runs.isEmpty else { return }
        let data = engine.raw(["readscript\t\(settings)\t\(merging)\t\(least)\n" + runs])
        guard let fresh = try? JSONDecoder().decode(ScriptReadingPhone.self, from: data) else {
            trouble = Session.refusal(in: data) ?? "Can't read that script"
            return
        }
        reading = fresh
        ticked = Set(fresh.scenes.rows.indices.filter { fresh.scenes.rows[$0].accepted })
        cast = Set(fresh.characters.rows.map(\.name))
        moving = []
    }

    private func line(named: String) -> String {
        let f = ISO8601DateFormatter()
        return ["takescript", named, file.url.lastPathComponent, f.string(from: Date()),
                ticked.sorted().map(String.init).joined(separator: ","),
                cast.sorted().joined(separator: "|"),
                archiveOmitted ? "1" : "0", merging, String(least), settings,
                moving.filter { ticked.contains($0) }.sorted().map(String.init).joined(separator: ",")].joined(separator: "\t")
    }

    private func weigh() {
        guard let engine = session.engine, let reading else { return }
        let data = engine.raw([line(named: "weigh") + "\n" + reading.script])
        guard let p = try? JSONDecoder().decode(ScriptPlanPhone.self, from: data) else {
            trouble = Session.refusal(in: data) ?? "Can't work that out"
            return
        }
        plan = p
    }

    private func take() {
        guard let engine = session.engine, let reading else { return }
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = engine.raw("detection", settings)
        let data = engine.raw([line(named: wanted) + "\n" + reading.script])
        if let problem = Session.refusal(in: data) { trouble = problem; return }
        // The draft keeps the pages it came from.
        struct List: Decodable { var revisions: [R] }
        struct R: Decodable { var id: String; var hash: String; var latest: Bool }
        let latest = (try? JSONDecoder().decode(List.self, from: engine.raw("revisions")))?.revisions.first { $0.latest }
        let scoped = file.url.startAccessingSecurityScopedResource()
        let bytes = try? Data(contentsOf: file.url)
        if scoped { file.url.stopAccessingSecurityScopedResource() }
        if let latest, let bytes { _ = engine.raw("scriptpdf", latest.id, bytes.base64EncodedString()) }
        session.refresh()
        if let latest { fileInDrive(stem: String(latest.hash.prefix(32)), bytes: bytes) }
        done()
        dismiss()
    }

    /// **Drive keeps up**, the Mac's way: a draft from Drive settles on that
    /// file; a PDF picked here is sent to `current-draft/`. Offline, nothing
    /// is lost — the Mac's next check files it.
    private func fileInDrive(stem: String, bytes: Data?) {
        guard let card = PhoneCards.shared.scriptCard(film: Relay.projectId(at: session.folder.url),
                                                      page: session.view?.project.consolePage ?? "") else { return }
        let drive = file.drive
        let name = file.url.lastPathComponent
        Task {
            if let drive {
                var body: [String: Any] = ["stem": stem, "by": "studio"]
                body["file"] = drive.file
                _ = await PhoneCards.scriptCall("\(card.id)/settle", method: "POST", json: body)
            } else if let bytes {
                _ = await PhoneCards.scriptCall("\(card.id)/upload", method: "PUT", body: bytes, query: [
                    URLQueryItem(name: "name", value: name), URLQueryItem(name: "stem", value: stem),
                    URLQueryItem(name: "by", value: "studio")])
            }
            await PhoneCards.shared.refresh()
        }
    }

    static func stem(_ file: String) -> String {
        file.lowercased().hasSuffix(".pdf") ? String(file.dropLast(4)) : file
    }

    // ---- the screens ---------------------------------------------------------------

    @ViewBuilder private func review(_ r: ScriptReadingPhone) -> some View {
        VStack(spacing: 0) {
            Picker("", selection: $page) { ForEach(Page.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.vertical, 8)
            Form {
                switch page {
                case .summary: summary(r)
                case .scenes: scenes(r)
                case .characters: characters(r)
                }
            }
        }
    }

    @ViewBuilder private func summary(_ r: ScriptReadingPhone) -> some View {
        Section {
            TextField("Draft Name", text: $name)
            LabeledContent("Pages", value: "\(r.pages)")
            LabeledContent("Scenes", value: "\(ticked.count) of \(r.scenes.rows.count)")
            LabeledContent("Already in Project", value: "\(r.scenes.matched)")
            LabeledContent("New", value: "\(r.scenes.new)")
            LabeledContent("Cast", value: "\(cast.count) of \(r.characters.rows.count)")
        }
        if !r.scenes.goneFromTheDraft.isEmpty {
            Section("Not in This Draft") {
                Toggle("Archive Them", isOn: $archiveOmitted)
                ForEach(r.scenes.goneFromTheDraft, id: \.number) { g in
                    HStack {
                        Text(g.number).monospacedDigit().frame(width: 40, alignment: .leading)
                        Text(g.heading).lineLimit(1)
                        Spacer()
                        if g.shots > 0 { Text("\(g.shots) shot\(g.shots == 1 ? "" : "s")").foregroundStyle(.secondary) }
                    }
                }
            }
        }
        Section("Reading") {
            Toggle("Scenes Have Numbers", isOn: Binding(get: { number }, set: { number = $0; reread() }))
            Toggle("Ignore Repeated Numbers", isOn: Binding(get: { duplicates }, set: { duplicates = $0; reread() }))
            Toggle("Find Rooms Under a Scene", isOn: Binding(get: { rooms }, set: { rooms = $0; reread() }))
            Picker("Cast Names", selection: Binding(get: { merging }, set: { merging = $0; reread() })) {
                Text("As Written").tag("none"); Text("Merged").tag("regular"); Text("Merged Hard").tag("hard")
            }
            Stepper("At Least \(least) Line\(least == 1 ? "" : "s")", value: Binding(get: { least }, set: { least = $0; reread() }), in: 0...20)
        }
    }

    @ViewBuilder private func scenes(_ r: ScriptReadingPhone) -> some View {
        let moved = Dictionary((r.scenes.movedNumber ?? []).map { ($0.index, $0) }, uniquingKeysWith: { a, _ in a })
        Section {
            ForEach(Array(r.scenes.rows.enumerated()), id: \.offset) { at, row in
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(get: { ticked.contains(at) }, set: { on in
                        if on { ticked.insert(at) } else { ticked.remove(at) }
                    })) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.label).monospacedDigit().frame(width: 40, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.heading).lineLimit(2)
                                Text(row.matched ? "In project" : (row.status == "room" ? "Room" : "New"))
                                    .font(.system(size: Kit.Size.label)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let m = moved[at], ticked.contains(at) {
                        Toggle(isOn: Binding(get: { moving.contains(at) }, set: { on in
                            if on { moving.insert(at) } else { moving.remove(at) }
                        })) {
                            Text("Renumber \(m.from) → \(m.to)").font(.system(size: Kit.Size.body)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func characters(_ r: ScriptReadingPhone) -> some View {
        Section {
            ForEach(r.characters.rows, id: \.name) { p in
                Toggle(isOn: Binding(get: { cast.contains(p.name) }, set: { on in
                    if on { cast.insert(p.name) } else { cast.remove(p.name) }
                })) {
                    HStack {
                        Text(p.display.isEmpty ? p.name : p.display)
                        Spacer()
                        Text("\(p.speeches)").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func confirm(_ p: ScriptPlanPhone) -> some View {
        Form {
            Section { TextField("Draft Name", text: $name) }
            Section { ForEach(p.sentences, id: \.self) { Text($0) } }
        }
    }
}
