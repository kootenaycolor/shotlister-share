import SwiftUI
import PDFKit

/// **A deck on the phone** (Ref 1551; `design/33-one-app.html` section 7).
///
/// Two ways to read one, as his decision of 2026-10-06 has it: **Native**, the
/// deck's own words and pictures in its own order, drawn in the app's style
/// (so every deck reads on a phone without anyone designing one for it), and
/// **Designed**, the printed PDF in the phone's own viewer.
///
/// The deck is the record the portal keeps at `p/<film>/decks/<slug>.json`:
/// sections of picture groups, words keyed `section.slot`, pictures by key.
struct LookDeck {
    struct Picture {
        var name: String
        var shape: CGFloat?
    }

    struct Group {
        var emphasis: String
        var pictures: [String]
        /// A shape every picture in the group is cut to (`"16/9"`).
        var ratio: CGFloat?
        /// His own number across, when he set one for the web.
        var across: Int?
    }

    struct Section {
        var id: String
        var on: Bool
        var groups: [Group]
    }

    var name: String = ""
    var slug: String = ""
    var sections: [Section] = []
    var words: [String: String] = [:]
    var pictures: [String: Picture] = [:]
    /// Group keys that are not keys of `pictures`, matched to them by order.
    private var byOrder: [String: Picture] = [:]

    init(data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        name = root["name"] as? String ?? ""
        slug = root["slug"] as? String ?? ""
        words = (root["words"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
        for (key, value) in root["pictures"] as? [String: Any] ?? [:] {
            guard let one = value as? [String: Any], let file = one["name"] as? String else { continue }
            let ar = (one["ar"] as? NSNumber).map { CGFloat(truncating: $0) }
            pictures[key] = Picture(name: file, shape: ar)
        }
        for raw in root["sections"] as? [[String: Any]] ?? [] {
            let groups: [Group] = (raw["groups"] as? [[String: Any]] ?? []).map { g in
                Group(emphasis: g["emphasis"] as? String ?? "normal",
                      pictures: (g["pictures"] as? [Any] ?? []).compactMap { $0 as? String },
                      ratio: Self.ratio(g["ratio"] as? String),
                      across: (g["across"] as? [String: Any])?["web"] as? Int)
            }
            sections.append(Section(id: raw["id"] as? String ?? "",
                                    on: raw["on"] as? Bool ?? true,
                                    groups: groups))
        }
        // **A deck whose groups name files rather than keys** (Lens Character,
        // published 2026-09-10, keeps `pair-01/a-….jpg` in its groups and
        // hashed keys in its pictures). The pictures were stored in the order
        // the deck uses them, so they are matched by order. Read off the
        // stored text, since a decoded dictionary has no order.
        let used = sections.filter(\.on).flatMap { $0.groups.flatMap(\.pictures) }
        if !used.isEmpty, !used.contains(where: { pictures[$0] != nil }),
           let text = String(data: data, encoding: .utf8) {
            let ordered = pictures.keys.compactMap { key -> (String, String.Index)? in
                guard let at = text.range(of: "\"\(key)\"")?.lowerBound else { return nil }
                return (key, at)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
            if ordered.count == used.count {
                for (file, key) in zip(used, ordered) { byOrder[file] = pictures[key] }
            }
        }
    }

    private static func ratio(_ said: String?) -> CGFloat? {
        guard let said else { return nil }
        let parts = said.split(separator: "/").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, parts[1] > 0 else { return nil }
        return CGFloat(parts[0] / parts[1])
    }

    func picture(_ key: String) -> Picture? { pictures[key] ?? byOrder[key] }

    /// The words a section draws from: its own id, or the id its run of
    /// sheets shares (`overall_approach_a`, `_b`, `_c` all draw from
    /// `overall_approach.`).
    func base(of id: String) -> String {
        if words.keys.contains(where: { $0.hasPrefix(id + ".") }) { return id }
        if let range = id.range(of: "_[a-z]$", options: .regularExpression) {
            return String(id[..<range.lowerBound])
        }
        return id
    }

    /// One word slot: what kind, and which number.
    struct Slot: Comparable {
        var kind: String
        var number: Int
        var said: String
        static func < (a: Slot, b: Slot) -> Bool { a.number < b.number }
    }

    func slots(_ base: String) -> [Slot] {
        words.compactMap { key, value -> Slot? in
            guard key.hasPrefix(base + "."), !value.isEmpty else { return nil }
            let slot = key.dropFirst(base.count + 1)
            let kind = String(slot.prefix { $0.isLetter })
            let number = Int(slot.drop { $0.isLetter }) ?? 0
            return Slot(kind: kind, number: number, said: value)
        }
        .sorted()
    }

    /// **A section's words, in the order they are read.** The record keeps
    /// them by slot, not by place, so they are put back together: titles and
    /// subtitles lead; a paragraph that opens in bold starts a new part (or,
    /// with as many heads as paragraphs, each paragraph is one); the heads go
    /// to the parts in order, and any head more than there are parts leads.
    /// Column heads (`col1`, `col2`) close it, side by side.
    struct Reading {
        var lead: [Slot] = []
        var parts: [[Slot]] = []
        var cols: [Slot] = []
        var isEmpty: Bool { lead.isEmpty && parts.isEmpty && cols.isEmpty }
    }

    func reading(_ base: String) -> Reading {
        let all = slots(base)
        let isBody: (Slot) -> Bool = { ["b", "p", "body"].contains($0.kind) }
        let opensBold: (Slot) -> Bool = { $0.said.hasPrefix("<b>") || $0.said.hasPrefix("<strong>") }
        let heads = all.filter { $0.kind == "head" }
        let bodies = all.filter(isBody)
        var out = Reading()
        let rank = ["kicker": 0, "title": 1, "sub": 2]
        out.lead = all.filter { !isBody($0) && $0.kind != "head" && $0.kind != "col" }
            .sorted { (rank[$0.kind] ?? 3, $0.number) < (rank[$1.kind] ?? 3, $1.number) }
        out.cols = all.filter { $0.kind == "col" }
        var parts: [[Slot]] = []
        if bodies.filter(opensBold).count > 1, let first = bodies.first, opensBold(first) {
            for body in bodies {
                if opensBold(body) || parts.isEmpty { parts.append([body]) } else { parts[parts.count - 1].append(body) }
            }
        } else if heads.count > 1, heads.count == bodies.count {
            parts = bodies.map { [$0] }
        } else if !bodies.isEmpty {
            parts = [bodies]
        }
        if !parts.isEmpty, heads.count >= parts.count {
            let extra = heads.count - parts.count
            out.lead += heads.prefix(extra)
            out.parts = parts.enumerated().map { [heads[extra + $0.offset]] + $0.element }
        } else {
            out.lead += heads
            out.parts = parts
        }
        return out
    }
}

struct LookDeckView: View {
    enum Way: String, CaseIterable, Identifiable {
        case native = "Native"
        case designed = "Designed"
        var id: String { rawValue }
    }

    let deck: LookDeck
    let files: any LookFiles
    /// The printed deck's stored file name (a `lookbook` document in the
    /// film's `front.json`), if it has been printed.
    let printed: String?

    @State private var way: Way = .native
    @State private var viewing: LookViewer.Opening?

    init(deck: LookDeck, files: any LookFiles, printed: String? = nil) {
        self.deck = deck
        self.files = files
        self.printed = printed
    }

    init(data: Data, files: any LookFiles, printed: String? = nil) throws {
        self.init(deck: try LookDeck(data: data), files: files, printed: printed)
    }

    var body: some View {
        Group {
            switch way {
            case .native: native
            case .designed: LookPrinted(name: printed ?? "", files: files)
            }
        }
        .environment(\.lookFiles, files)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if printed != nil {
                ToolbarItem(placement: .principal) {
                    GlassSegments(options: Way.allCases.map { ($0, $0.rawValue) }, selection: $way)
                        .fixedSize()
                }
            }
        }
        .navigationTitle(printed == nil ? deck.name : "")
        .fullScreenCover(item: $viewing) { opening in
            LookViewer(opening: opening).environment(\.lookFiles, files)
        }
        .onAppear { if printed != nil, LookCheck.value("--lookway") == "designed" { way = .designed } }
    }

    private var everyPicture: [String] {
        deck.sections.filter(\.on).flatMap { $0.groups.flatMap { $0.pictures.compactMap { deck.picture($0)?.name } } }
    }

    private var native: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Deck · \(deck.name)")
                    .font(.system(size: 13, weight: .bold))
                    .kerning(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(Style.ink3)
                ForEach(Array(deck.sections.filter(\.on).enumerated()), id: \.offset) { _, section in
                    sectionView(section)
                }
                ForEach(leftover, id: \.self) { base in
                    words(deck.reading(base))
                        .padding(.top, 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Style.page)
    }

    /// The section that draws each run's words: the first of the run.
    private var drawnBases: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for section in deck.sections where section.on {
            let base = deck.base(of: section.id)
            if seen.insert(base).inserted { out.append(section.id) }
        }
        return out
    }

    /// Words that belong to no section on (a closing sheet the arrangement
    /// does not list): drawn at the end rather than lost.
    private var leftover: [String] {
        let bases = Set(deck.sections.filter(\.on).map { deck.base(of: $0.id) })
        var out: [String] = []
        for key in deck.words.keys.sorted() {
            let base = String(key.prefix { $0 != "." })
            if !bases.contains(base), !out.contains(base) { out.append(base) }
        }
        // A closing sheet is called `end` by the press; it goes last.
        return out.sorted { a, b in a == "end" ? false : (b == "end" ? true : a < b) }
    }

    @ViewBuilder
    private func sectionView(_ section: LookDeck.Section) -> some View {
        let first = drawnBases.contains(section.id)
        let read = first ? deck.reading(deck.base(of: section.id)) : LookDeck.Reading()
        VStack(alignment: .leading, spacing: 10) {
            if !read.lead.isEmpty { slots(read.lead) }
            // A run's parts go with its groups one to one when they match, the
            // way the deck sets them; otherwise words, then pictures.
            if !read.parts.isEmpty, section.groups.count == read.parts.count {
                ForEach(Array(section.groups.enumerated()), id: \.offset) { i, group in
                    slots(read.parts[i])
                    groupView(group)
                }
                cols(read.cols)
            } else {
                ForEach(Array(read.parts.enumerated()), id: \.offset) { _, part in slots(part) }
                cols(read.cols)
                ForEach(Array(section.groups.enumerated()), id: \.offset) { _, group in
                    groupView(group)
                }
            }
        }
        .padding(.top, first ? 10 : 0)
    }

    private func words(_ read: LookDeck.Reading) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            slots(read.lead)
            ForEach(Array(read.parts.enumerated()), id: \.offset) { _, part in slots(part) }
            cols(read.cols)
        }
    }

    private func slots(_ list: [LookDeck.Slot]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(list.enumerated()), id: \.offset) { _, slot in line(slot) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func cols(_ list: [LookDeck.Slot]) -> some View {
        if !list.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.offset) { _, col in
                    Text(lookMarked(col.said))
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func line(_ slot: LookDeck.Slot) -> some View {
        switch slot.kind {
        case "title":
            Text(lookMarked(slot.said)).font(.system(size: 28, weight: .heavy)).kerning(-0.6)
        case "sub":
            Text(lookMarked(slot.said)).font(.system(size: 13)).foregroundStyle(Style.ink3)
        case "head":
            Text(lookMarked(slot.said)).font(.system(size: 20, weight: .bold)).padding(.top, 8)
        case "kicker":
            Text(lookMarked(slot.said)).font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
        default:
            Text(lookMarked(slot.said)).font(.system(size: 15)).lineSpacing(2.5)
        }
    }

    /// How many a group of each loudness puts on a line: the table the deck
    /// itself uses (`CAPS` in `hub/public/deck.js`).
    private func most(_ group: LookDeck.Group) -> Int {
        if let across = group.across, across > 0 { return across }
        switch group.emphasis {
        case "hero": return 1
        case "large": return 2
        case "quiet": return 4
        default: return 3
        }
    }

    private func groupView(_ group: LookDeck.Group) -> some View {
        let held = group.pictures.compactMap { deck.picture($0) }
        let lines = lookLines(held, most: most(group))
        return VStack(spacing: group.emphasis == "quiet" ? 3 : 5) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                LookPictureRow(names: line.map(\.name),
                               known: line.map(\.shape),
                               forced: group.ratio,
                               spacing: group.emphasis == "quiet" ? 3 : 5) { index in
                    let all = everyPicture
                    viewing = .init(names: all, at: all.firstIndex(of: line[index].name) ?? 0)
                }
            }
        }
        .padding(.vertical, group.emphasis == "quiet" ? 0 : 2)
    }
}

/// **The printed deck**, in PDFKit: its real look, a page at a time down the
/// screen, pinch to zoom, which page in a small capsule at the foot.
private struct LookPrinted: View {
    let name: String
    let files: any LookFiles
    @State private var document: PDFDocument?
    @State private var url: URL?
    @State private var page = 1
    @State private var missing = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Style.page.ignoresSafeArea()
            if let document {
                LookPDF(document: document, page: $page)
                    .ignoresSafeArea(edges: .bottom)
                Text("\(page) of \(document.pageCount)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassCapsule(interactive: false)
                    .padding(.bottom, 24)
            } else if missing {
                ContentUnavailableView("Not on This Phone", systemImage: "doc.richtext")
            } else {
                ProgressView()
            }
        }
        .toolbar {
            if let url, url.isFileURL {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: url)
                }
            }
        }
        .task(id: name) {
            guard !name.isEmpty, let found = await files.file(named: name) else { missing = true; return }
            url = found
            let made = await Task.detached { PDFDocument(url: found) }.value
            document = made
            missing = made == nil
        }
    }
}

private struct LookPDF: UIViewRepresentable {
    let document: PDFDocument
    @Binding var page: Int

    func makeCoordinator() -> Coordinator { Coordinator(page: $page) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(Style.page)
        view.pageShadowsEnabled = true
        context.coordinator.observe(view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
    }

    final class Coordinator: NSObject {
        let page: Binding<Int>
        private var token: NSObjectProtocol?
        init(page: Binding<Int>) { self.page = page }

        func observe(_ view: PDFView) {
            token = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak view, page] _ in
                guard let view, let current = view.currentPage, let doc = view.document else { return }
                page.wrappedValue = doc.index(for: current) + 1
            }
        }

        deinit { if let token { NotificationCenter.default.removeObserver(token) } }
    }
}
