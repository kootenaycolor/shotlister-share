import SwiftUI

/// **A Look Board on the phone, to look at** (Ref 1551; his decision of
/// 2026-10-06: look only; `design/33-one-app.html` section 6).
///
/// The board as the portal keeps it (`p/<film>/boards/<slug>.json`, drawn
/// there by `hub/public/board.js`): every card at its real place, ties as thin
/// dashed lines with their words, pinch and drag to move about, and the
/// board's own sorts in a bar at the foot. Tap a card for its picture, its
/// threads and its sorts; a shot or scene card opens the app's own.
///
/// **Drawn in one Canvas, not a view per card.** A board holds hundreds of
/// cards; as views, each picture was drawn at full size and scaled, which on
/// Call Her Back's 319 was hundreds of megabytes. One canvas draws only what is
/// on screen, at the size it is on screen.
struct LookBoard {
    enum Value: Hashable {
        case word(String)
        case number(Double)

        init?(_ any: Any?) {
            if let n = any as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { self = .number(n.doubleValue) }
            else if let s = any as? String, !s.isEmpty { self = .word(s) }
            else { return nil }
        }
        var word: String? { if case .word(let s) = self { return s } else { return nil } }
        var number: Double? { if case .number(let n) = self { return n } else { return nil } }
    }

    struct Live: Hashable {
        var type: String
        var id: String
        var key: String
    }

    struct Card: Identifiable {
        var id: String
        var kind: String
        var x: CGFloat
        var y: CGFloat
        var src = ""
        var poster = ""
        var kicker = ""
        var title = ""
        var sub = ""
        var cap = ""
        var text = ""
        var said = ""
        var href = ""
        var live: Live?
        var facts: [String] = []
        var fields: [(String, String)] = []
        var vals: [String: Value] = [:]
        /// Clips the card carries: (clip, still).
        var clips: [(String, String)] = []
        /// Pictures the card carries: (picture, caption).
        var figs: [(String, String)] = []
        var bare = false
        var folded = false
        var size: CGFloat = 1

        /// The picture that stands for the card (`coverOf` in `hub/src/arrange.js`).
        var cover: String {
            switch kind {
            case "still", "doc": return lookFileName(src)
            case "clip": return lookFileName(poster)
            case "ref", "test", "video", "shot", "scene", "location", "link":
                if !src.isEmpty, kind != "ref", kind != "test", !src.hasSuffix(".mp4") { return lookFileName(src) }
                if let fig = figs.first, !fig.0.isEmpty { return lookFileName(fig.0) }
                if let clip = clips.first, !clip.1.isEmpty { return lookFileName(clip.1) }
                return src.isEmpty ? "" : lookFileName(src)
            default: return ""
            }
        }

        /// A clip to play, stored on the film.
        var clip: String {
            if kind == "clip", !src.isEmpty { return lookFileName(src) }
            return clips.first.map { lookFileName($0.0) } ?? ""
        }

        /// What a card is called, in a line.
        var name: String {
            let words = !title.isEmpty ? title : (!text.isEmpty ? text : (!cap.isEmpty ? cap : kicker))
            return words.split(separator: "\n").first.map(String.init) ?? words
        }
    }

    struct Tie: Identifiable {
        var a: String
        var b: String
        var label: String
        var id: String { [a, b].sorted().joined(separator: "~") }
    }

    struct Sort: Identifiable, Hashable {
        struct Column: Hashable {
            var id: String
            var name: String
        }
        var id: String
        var type: String
        var name: String
        var ends: [String] = []
        var cols: [Column] = []
        var none = "Unsorted"
    }

    var cards: [Card] = []
    var ties: [Tie] = []
    var sorts: [Sort] = []

    init(data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let gone = Set(root["gone"] as? [String] ?? [])
        let free = root["free"] as? [String: Any] ?? [:]
        let texts = root["text"] as? [String: String] ?? [:]
        let valsBy = root["vals"] as? [String: [String: Any]] ?? [:]
        let obs = root["obs"] as? [String: Any] ?? [:]
        let cam = root["cam"] as? [String: Any] ?? [:]
        let folded = root["folded"] as? [String: Any] ?? [:]
        let bare = root["bare"] as? [String: Any] ?? [:]
        let sizes = root["size"] as? [String: Any] ?? [:]

        for raw in root["added"] as? [[String: Any]] ?? [] {
            guard let id = raw["id"] as? String, !gone.contains(id) else { continue }
            func s(_ k: String) -> String { raw[k] as? String ?? "" }
            var card = Card(id: id, kind: s("kind"),
                            x: CGFloat((raw["x"] as? NSNumber)?.doubleValue ?? 0),
                            y: CGFloat((raw["y"] as? NSNumber)?.doubleValue ?? 0))
            card.src = s("src"); card.poster = s("poster"); card.kicker = s("kicker")
            card.title = s("title"); card.sub = s("sub"); card.cap = s("cap")
            card.text = s("text"); card.said = s("said"); card.href = s("href")
            if let live = raw["live"] as? [String: Any] {
                card.live = Live(type: live["type"] as? String ?? "",
                                 id: (live["id"] as? String) ?? (live["id"] as? NSNumber)?.stringValue ?? "",
                                 key: live["key"] as? String ?? "")
            }
            card.facts = (raw["facts"] as? [Any] ?? []).compactMap { $0 as? String }
            card.fields = (raw["fields"] as? [[Any]] ?? []).compactMap { pair in
                guard pair.count >= 2, let k = pair[0] as? String else { return nil }
                return (k, (pair[1] as? String) ?? "\(pair[1])")
            }
            for (k, v) in raw["vals"] as? [String: Any] ?? [:] { if let v = Value(v) { card.vals[k] = v } }
            card.clips = (raw["clips"] as? [[String: Any]] ?? []).map { ($0["src"] as? String ?? "", $0["poster"] as? String ?? "") }
            card.figs = (raw["figs"] as? [[String: Any]] ?? []).map { ($0["src"] as? String ?? "", $0["cap"] as? String ?? "") }
            card.bare = raw["bare"] as? Bool ?? false
            card.folded = raw["folded"] as? Bool ?? false
            card.size = CGFloat((raw["size"] as? NSNumber)?.doubleValue ?? 1)
            cards.append(card)
        }
        // **What was changed on a published card** is kept beside it, by id
        // (`stateNow` in `board.js`); laid over the cards that have them.
        for i in cards.indices {
            let id = cards[i].id
            if let at = free[id] as? [NSNumber], at.count == 2 {
                cards[i].x = CGFloat(at[0].doubleValue); cards[i].y = CGFloat(at[1].doubleValue)
            }
            if let t = texts[id] { cards[i].text = t }
            for (sort, by) in valsBy { if let v = Value(by[id]) { cards[i].vals[sort] = v } }
            if let o = obs[id] as? NSNumber { cards[i].vals["obs"] = .number(1 - o.doubleValue) }
            if let c = cam[id] as? String { cards[i].vals["cam"] = .word(c) }
            if folded[id] != nil { cards[i].folded = true }
            if bare[id] != nil { cards[i].bare = true }
            if let k = sizes[id] as? NSNumber { cards[i].size = CGFloat(k.doubleValue) }
            cards[i].size = min(5, max(0.3, cards[i].size))
        }
        let here = Set(cards.map(\.id))
        let cut = Set(root["cut"] as? [String] ?? [])
        let labels = root["labels"] as? [String: String] ?? [:]
        for raw in root["ties"] as? [[String: Any]] ?? [] {
            guard let a = raw["a"] as? String, let b = raw["b"] as? String, here.contains(a), here.contains(b) else { continue }
            var tie = Tie(a: a, b: b, label: raw["label"] as? String ?? "")
            if cut.contains(tie.id) { continue }
            if let label = labels[tie.id] { tie.label = label }
            ties.append(tie)
        }
        for raw in root["lenses"] as? [[String: Any]] ?? [] {
            guard let id = raw["id"] as? String, let type = raw["type"] as? String else { continue }
            var sort = Sort(id: id, type: type, name: raw["name"] as? String ?? id)
            sort.ends = (raw["ends"] as? [Any] ?? []).compactMap { $0 as? String }
            sort.cols = (raw["cols"] as? [[String: Any]] ?? []).compactMap { c in
                guard let cid = c["id"] as? String else { return nil }
                return Sort.Column(id: cid, name: c["name"] as? String ?? cid)
            }
            if let none = raw["none"] as? String, !none.isEmpty { sort.none = none }
            sorts.append(sort)
        }
    }

    func card(_ id: String) -> Card? { cards.first { $0.id == id } }

    /// Where a card sits on a line sort, 0 to 1 (the middle when unsaid).
    static func place(_ card: Card, on sort: Sort) -> Double {
        min(1, max(0, card.vals[sort.id]?.number ?? 0.5))
    }

    /// The column a card is in, or "" for none.
    static func column(_ card: Card, of sort: Sort) -> String {
        card.vals[sort.id]?.word ?? ""
    }
}

// MARK: - drawing a card

/// How each kind is drawn: its width on the board (`KINDS` in `board.js`),
/// the colour of its small heading, and its ground.
enum LookKind {
    static func width(_ kind: String) -> CGFloat {
        switch kind {
        case "ref", "test", "video": return 300
        case "still": return 230
        case "clip": return 270
        case "shot", "location", "link": return 260
        case "scene": return 250
        case "day": return 230
        case "person": return 220
        case "doc": return 240
        case "idea": return 235
        case "gear": return 275
        case "note": return 215
        default: return 240
        }
    }

    static func tint(_ kind: String) -> Color {
        switch kind {
        case "ref": return .orange
        case "test": return .green
        case "video": return .red
        case "shot": return .blue
        case "scene": return .pink
        case "location": return .teal
        case "day": return .indigo
        case "person": return .purple
        case "doc": return .brown
        case "link": return .cyan
        case "gear": return Color(red: 0.32, green: 0.45, blue: 0.6)
        default: return .secondary
        }
    }

    static func ground(_ kind: String) -> Color {
        switch kind {
        case "note": return Color(red: 1.0, green: 0.96, blue: 0.78)
        case "scene": return Color(red: 0.99, green: 0.94, blue: 0.95)
        case "gear": return Color(red: 0.93, green: 0.95, blue: 0.98)
        case "idea", "heading": return .clear
        default: return .white
        }
    }

    static func name(_ kind: String) -> String {
        switch kind {
        case "ref": return "Reference"
        case "test": return "Test"
        case "video": return "Video"
        case "still": return "Still"
        case "clip": return "Clip"
        case "shot": return "Shot"
        case "scene": return "Scene"
        case "location": return "Location"
        case "day": return "Day"
        case "person": return "Person"
        case "doc": return "Document"
        case "link": return "Link"
        case "idea": return "Idea"
        case "gear": return "Gear"
        case "note": return "Note"
        case "heading": return "Heading"
        default: return kind.capitalized
        }
    }

    /// The lanes a line sort lays its cards in (`LANES` in `board.js`).
    static let lanes: [(String, [String])] = [
        ("Pictures", ["ref", "test", "video", "still", "clip"]),
        ("From the Film", ["shot", "scene", "location", "day", "person", "doc"]),
        ("Ideas", ["idea"]),
        ("Links", ["link"]),
        ("Gear", ["gear"]),
        ("Notes", ["note"]),
    ]
}

/// A card's parts, measured once: what lines it draws and how tall it is,
/// before its picture. Fonts match what the canvas draws them in.
struct LookCardFace {
    struct Line {
        var text: String
        var font: UIFont
        var color: Color
        var height: CGFloat
        var upper = false
    }
    var width: CGFloat
    var lines: [Line] = []
    var inset: CGFloat
    var pictured: Bool
    var bare: Bool
    var heading = false

    static let pad: CGFloat = 12

    init(_ card: LookBoard.Card) {
        let k = card.size
        if card.kind == "heading" {
            let font = UIFont.systemFont(ofSize: 30 * k, weight: .bold)
            let said = card.text.isEmpty ? card.title : card.text
            let w = (said as NSString).size(withAttributes: [.font: font]).width + 8
            width = max(60, w)
            inset = 0
            pictured = false
            bare = false
            heading = true
            lines = [Line(text: said, font: font, color: .primary, height: font.lineHeight * 1.15)]
            return
        }
        width = LookKind.width(card.kind) * k
        pictured = !card.cover.isEmpty || card.kind == "clip"
        bare = card.bare && pictured
        inset = (card.kind == "still" || card.kind == "clip") ? 7 * k : 0
        if bare { return }
        let room = width - 2 * Self.pad * k
        func add(_ text: String, _ size: CGFloat, _ weight: UIFont.Weight, _ color: Color, upper: Bool = false, most: Int = 0) {
            let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !said.isEmpty else { return }
            let font = UIFont.systemFont(ofSize: size * k, weight: weight)
            let shown = upper ? said.uppercased() : said
            var h = (shown as NSString).boundingRect(with: CGSize(width: room, height: .greatestFiniteMagnitude),
                                                     options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                     attributes: [.font: font], context: nil).height.rounded(.up)
            if most > 0 { h = min(h, font.lineHeight * CGFloat(most)) }
            lines.append(Line(text: shown, font: font, color: color, height: h + 1, upper: upper))
        }
        let tint = LookKind.tint(card.kind)
        switch card.kind {
        case "note":
            add(card.text.isEmpty ? card.title : card.text, 14, .regular, .primary)
        case "still", "clip":
            add(card.kicker, 10, .semibold, .secondary, upper: true)
            if card.cap != card.kicker { add(card.cap, 12, .regular, .secondary, most: 3) }
            add(card.text, 13, .regular, .primary)
        default:
            add(card.kicker, 10, .semibold, tint, upper: true)
            let big = card.kind == "idea" || card.kind == "gear"
            if card.kind != "note" { add(card.title, big ? 20 : 16, .semibold, .primary, most: card.folded ? 2 : 0) }
            if !card.folded {
                add(card.sub.isEmpty ? card.cap : card.sub, 12, .regular, .secondary, most: 5)
                let shown = card.fields.filter { ["Size", "Angle", "Lens", "Movement", "Support", "Scene", "Day"].contains($0.0) }
                if !shown.isEmpty {
                    add(shown.prefix(5).map(\.1).joined(separator: " · "), 11, .medium, .secondary, most: 3)
                } else if !card.facts.isEmpty {
                    add(card.facts.prefix(6).joined(separator: " · "), 11, .medium, .secondary, most: 3)
                }
                add(card.text, 13, .regular, .primary)
            }
        }
    }

    /// The card's whole height with its picture at the given shape.
    func height(shape: CGFloat?, size k: CGFloat) -> CGFloat {
        if heading { return lines.first?.height ?? 40 }
        let pic = pictured ? (width - 2 * inset) / max(0.25, shape ?? 1.6) : 0
        if bare { return pic + 2 * inset }
        let words = lines.reduce(0) { $0 + $1.height } + CGFloat(max(0, lines.count - 1)) * 5 * k
        let pad = lines.isEmpty ? 0 : 2 * Self.pad * k
        return inset + pic + (pictured && inset > 0 ? inset : 0) + words + pad
    }
}

// MARK: - the board

struct LookBoardView: View {
    let title: String
    let board: LookBoard
    let files: any LookFiles
    /// The film the board belongs to, so a shot or scene card can open the
    /// app's own. Without it the cards are only looked at.
    let session: Session?

    init(title: String, board: LookBoard, files: any LookFiles, session: Session? = nil) {
        self.title = title
        self.board = board
        self.files = files
        self.session = session
    }

    init(title: String, data: Data, files: any LookFiles, session: Session? = nil) throws {
        self.init(title: title, board: try LookBoard(data: data), files: files, session: session)
    }

    @State private var mode = "free"
    @State private var picked: LookBoard.Card?
    @State private var detent: PresentationDetent = .medium
    @StateObject private var pictures = LookBoardPictures()
    @State private var fitAsked = 0
    @State private var zoom: CGFloat = 1

    private var sort: LookBoard.Sort? { board.sorts.first { $0.id == mode } }

    var body: some View {
        Group {
            if let sort, sort.type == "columns" {
                LookBoardColumns(board: board, sort: sort, pictures: pictures) { picked = $0 }
            } else {
                LookBoardCanvas(board: board, sort: sort, pictures: pictures,
                                fitAsked: fitAsked, zoom: $zoom) { picked = $0 }
            }
        }
        .environment(\.lookFiles, files)
        .background(Style.page)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) { bar }
        .sheet(item: $picked) { card in
            LookCardSheet(board: board, card: card, session: session)
                .environment(\.lookFiles, files)
                .presentationDetents([.medium, .large], selection: $detent)
        }
        .task { await pictures.load(board.cards, from: files) }
        .onAppear {
            // Checking doors (`LookCheck`): a sort, an opened card.
            if let m = LookCheck.value("--lookmode"), board.sorts.contains(where: { $0.id == m }) { mode = m }
            if LookCheck.value("--lookcard", 1) == "large" { detent = .large }
            if let c = LookCheck.value("--lookcard") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { picked = board.card(c) }
            }
        }
    }

    private var bar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    choice("free", "Free")
                    ForEach(board.sorts) { choice($0.id, $0.name) }
                }
                .padding(4)
            }
            .glassCapsule()
            if sort?.type != "columns" {
                Button {
                    fitAsked += 1
                } label: {
                    VStack(spacing: 0) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.footnote.weight(.semibold))
                        Text("\(Int((zoom * 100).rounded()))%")
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    }
                    .frame(width: 50, height: 50)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassCapsule()
                .accessibilityLabel("Fit")
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func choice(_ id: String, _ name: String) -> some View {
        Button {
            withAnimation(.snappy) { mode = id }
            fitAsked += 1
        } label: {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .foregroundStyle(mode == id ? Color(.systemBackground) : Color(.label))
                .background(mode == id ? Color(.label) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Every card's picture, small, and a few large for what is close.
@MainActor
final class LookBoardPictures: ObservableObject {
    @Published private(set) var small: [String: UIImage] = [:]
    @Published private(set) var large: [String: UIImage] = [:]
    private var files: (any LookFiles)?
    private var wanting: Set<String> = []

    func shape(_ name: String) -> CGFloat? {
        guard let image = small[name] ?? large[name], image.size.height > 0 else { return nil }
        return image.size.width / image.size.height
    }

    func load(_ cards: [LookBoard.Card], from files: any LookFiles) async {
        self.files = files
        let names = Array(Set(cards.map(\.cover).filter { !$0.isEmpty }))
        await withTaskGroup(of: (String, UIImage?).self) { group in
            var next = names.makeIterator()
            func more() {
                guard let name = next.next() else { return }
                group.addTask { (name, await LookPictures.shared.image(name, longest: 360, from: files)) }
            }
            for _ in 0..<6 { more() }
            var batch: [String: UIImage] = [:]
            for await (name, image) in group {
                if let image { batch[name] = image }
                if batch.count >= 24 { small.merge(batch) { $1 }; batch = [:] }
                more()
            }
            small.merge(batch) { $1 }
        }
    }

    /// Close up, the pictures on screen are read again, larger. Only the
    /// last few dozen are kept.
    func sharpen(_ names: [String]) {
        guard let files else { return }
        let wanted = names.filter { large[$0] == nil && !wanting.contains($0) }.prefix(16)
        guard !wanted.isEmpty else { return }
        wanting.formUnion(wanted)
        Task {
            for name in wanted {
                if let image = await LookPictures.shared.image(name, longest: 1100, from: files) {
                    if large.count > 40, let drop = large.keys.first(where: { !names.contains($0) }) {
                        large[drop] = nil
                    }
                    large[name] = image
                }
                wanting.remove(name)
            }
        }
    }
}

/// Where each card is, for the way the board is being looked at.
private struct LookPlaced {
    var card: LookBoard.Card
    var face: LookCardFace
    var rect: CGRect
}

private struct LookBoardCanvas: View {
    let board: LookBoard
    let sort: LookBoard.Sort?
    @ObservedObject var pictures: LookBoardPictures
    let fitAsked: Int
    @Binding var zoom: CGFloat
    let tap: (LookBoard.Card) -> Void

    @State private var faces: [String: LookCardFace] = [:]
    @State private var scale: CGFloat = 0.1
    @State private var offset: CGSize = .zero
    @State private var pinchFrom: (scale: CGFloat, offset: CGSize)?
    @State private var dragFrom: CGSize?
    @State private var size: CGSize = .zero
    @State private var fitted = false

    /// Half the width of a line sort, as the portal has it (`SPAN`).
    private let span: CGFloat = 1900

    var body: some View {
        let placed = layout()
        GeometryReader { space in
            Canvas { context, canvasSize in
                draw(placed, in: &context, size: canvasSize)
            }
            .contentShape(Rectangle())
            .gesture(pan.simultaneously(with: pinch))
            .onTapGesture(count: 2) { at in zoomBy(2, at: at) }
            .onTapGesture { at in
                let world = toWorld(at)
                if let hit = placed.last(where: { $0.rect.contains(world) && $0.card.kind != "heading" }) {
                    tap(hit.card)
                }
            }
            .onAppear {
                size = space.size
                if faces.isEmpty { faces = Dictionary(uniqueKeysWithValues: board.cards.map { ($0.id, LookCardFace($0)) }) }
            }
            .onChange(of: space.size) { _, new in size = new }
        }
        .onChange(of: fitAsked) { _, _ in withAnimation(.snappy) { fit(layout()) } }
        .onChange(of: placed.count) { _, _ in if !fitted { fit(placed); checkZoom() } }
        .onChange(of: size) { _, _ in if !fitted { fit(layout()); checkZoom() } }
        .onChange(of: scale) { _, new in zoom = new }
    }

    // ---- placing

    private func layout() -> [LookPlaced] {
        guard !faces.isEmpty else { return [] }
        let list = board.cards.filter { sort == nil || $0.kind != "heading" }
        var out: [LookPlaced] = []
        func rect(_ card: LookBoard.Card, _ face: LookCardFace, x: CGFloat, y: CGFloat) -> CGRect {
            let h = face.height(shape: pictures.shape(card.cover), size: card.size)
            return CGRect(x: x - face.width / 2, y: y - h / 2, width: face.width, height: h)
        }
        guard let sort, sort.type == "line" else {
            for card in list {
                guard let face = faces[card.id] else { continue }
                out.append(LookPlaced(card: card, face: face, rect: rect(card, face, x: card.x, y: card.y)))
            }
            return out
        }
        // **A line sort, as the portal lays it** (`layout` in `board.js`):
        // lane by lane, each card as near its place on the line as the others
        // let it, a crowd spreading sideways around where it belongs.
        var top: CGFloat = 0
        let gap: CGFloat = 26
        for (_, kinds) in LookKind.lanes {
            let members = list.filter { kinds.contains($0.kind) }
                .sorted { LookBoard.place($0, on: sort) < LookBoard.place($1, on: sort) }
            guard !members.isEmpty else { continue }
            let rows = Int((Double(members.count) / 10).rounded(.up))
            for r in 0..<rows {
                let row = members.enumerated().filter { $0.offset % rows == r }.map(\.element)
                var items: [(card: LookBoard.Card, face: LookCardFace, w: CGFloat, h: CGFloat, want: CGFloat)] = row.compactMap { card in
                    guard let face = faces[card.id] else { return nil }
                    let h = face.height(shape: pictures.shape(card.cover), size: card.size)
                    return (card, face, face.width, h, -span + CGFloat(LookBoard.place(card, on: sort)) * 2 * span)
                }
                // Clusters that push apart until nothing overlaps.
                var clusters: [(its: [Int], left: CGFloat, w: CGFloat)] = []
                func settle(_ its: [Int]) -> (its: [Int], left: CGFloat, w: CGFloat) {
                    var off: CGFloat = 0
                    var offs: [CGFloat] = []
                    for i in its { offs.append(off); off += items[i].w + gap }
                    let w = off - gap
                    let left = zip(its, offs).reduce(CGFloat(0)) { $0 + (items[$1.0].want - items[$1.0].w / 2 - $1.1) } / CGFloat(its.count)
                    return (its, left, w)
                }
                for i in items.indices.sorted(by: { items[$0].want < items[$1].want }) {
                    clusters.append(settle([i]))
                    while clusters.count > 1 {
                        let c2 = clusters[clusters.count - 1], c1 = clusters[clusters.count - 2]
                        if c1.left + c1.w + gap <= c2.left { break }
                        clusters.removeLast(2)
                        clusters.append(settle(c1.its + c2.its))
                    }
                }
                let tallest = items.map(\.h).max() ?? 0
                for c in clusters {
                    var x = c.left
                    for i in c.its {
                        items[i].want = x + items[i].w / 2
                        x += items[i].w + gap
                    }
                }
                for item in items {
                    out.append(LookPlaced(card: item.card, face: item.face,
                                          rect: CGRect(x: item.want - item.w / 2, y: top, width: item.w, height: item.h)))
                }
                top += tallest + 40
            }
            top += 110
        }
        return out
    }

    // ---- looking about

    private func toWorld(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - offset.width) / scale, y: (p.y - offset.height) / scale)
    }

    private var pan: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { g in
                let from = dragFrom ?? offset
                if dragFrom == nil { dragFrom = offset }
                offset = CGSize(width: from.width + g.translation.width, height: from.height + g.translation.height)
                fitted = true
            }
            .onEnded { _ in dragFrom = nil; sharpen() }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { g in
                if pinchFrom == nil { pinchFrom = (scale, offset); dragFrom = nil }
                guard let from = pinchFrom else { return }
                let next = min(4, max(0.02, from.scale * g.magnification))
                // Hold still the point under the fingers.
                let anchor = g.startLocation
                let world = CGPoint(x: (anchor.x - from.offset.width) / from.scale,
                                    y: (anchor.y - from.offset.height) / from.scale)
                scale = next
                offset = CGSize(width: anchor.x - world.x * next, height: anchor.y - world.y * next)
                fitted = true
            }
            .onEnded { _ in pinchFrom = nil; dragFrom = nil; sharpen() }
    }

    private func zoomBy(_ k: CGFloat, at p: CGPoint) {
        let world = toWorld(p)
        let next = min(4, max(0.02, scale * k))
        withAnimation(.snappy) {
            scale = next
            offset = CGSize(width: p.x - world.x * next, height: p.y - world.y * next)
        }
        fitted = true
        sharpen()
    }

    private func fit(_ placed: [LookPlaced]) {
        guard size.width > 120, size.height > 120, let first = placed.first?.rect else { return }
        let all = placed.reduce(first) { $0.union($1.rect) }.insetBy(dx: -40, dy: -40)
        let s = min(size.width / all.width, size.height / all.height)
        scale = max(0.02, min(2, s))
        offset = CGSize(width: (size.width - all.width * scale) / 2 - all.minX * scale,
                        height: (size.height - all.height * scale) / 2 - all.minY * scale)
    }

    /// `--lookzoom <scale> <x> <y>`: a checking run looking close at a place.
    private func checkZoom() {
        guard let s = LookCheck.value("--lookzoom").flatMap(Double.init),
              let x = LookCheck.value("--lookzoom", 1).flatMap(Double.init),
              let y = LookCheck.value("--lookzoom", 2).flatMap(Double.init), size.width > 120, size.height > 120 else { return }
        scale = CGFloat(s)
        offset = CGSize(width: size.width / 2 - CGFloat(x) * scale, height: size.height / 2 - CGFloat(y) * scale)
        fitted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { sharpen() }
    }

    /// Close enough to read: what is on screen comes in sharper.
    private func sharpen() {
        guard scale >= 0.55 else { return }
        let seen = CGRect(origin: toWorld(.zero), size: CGSize(width: size.width / scale, height: size.height / scale))
        pictures.sharpen(layout().filter { $0.rect.intersects(seen) }.map(\.card.cover).filter { !$0.isEmpty })
    }

    // ---- drawing

    private func draw(_ placed: [LookPlaced], in context: inout GraphicsContext, size: CGSize) {
        let seen = CGRect(origin: toWorld(.zero), size: CGSize(width: size.width / scale, height: size.height / scale))
            .insetBy(dx: -60, dy: -60)
        var at: [String: CGRect] = [:]
        for p in placed { at[p.card.id] = p.rect }

        var world = context
        world.translateBy(x: offset.width, y: offset.height)
        world.scaleBy(x: scale, y: scale)
        let far = scale < 0.28

        if let sort, sort.type == "line" {
            // The line itself, its two words at its ends.
            var track = Path()
            track.move(to: CGPoint(x: -span, y: -190))
            track.addLine(to: CGPoint(x: span, y: -190))
            world.stroke(track, with: .color(.secondary.opacity(0.5)), lineWidth: 2 / max(scale, 0.2))
            if sort.ends.count == 2 {
                let font = Font.system(size: 34, weight: .bold)
                world.draw(Text(sort.ends[0]).font(font).foregroundStyle(.secondary), at: CGPoint(x: -span, y: -250), anchor: .leading)
                world.draw(Text(sort.ends[1]).font(font).foregroundStyle(.secondary), at: CGPoint(x: span, y: -250), anchor: .trailing)
            }
        }

        // Ties first, under the cards: thin, dashed, their words on them.
        for tie in board.ties {
            guard let a = at[tie.a], let b = at[tie.b] else { continue }
            let line = CGRect(x: min(a.midX, b.midX), y: min(a.midY, b.midY),
                              width: abs(a.midX - b.midX) + 1, height: abs(a.midY - b.midY) + 1)
            guard line.intersects(seen) else { continue }
            var path = Path()
            path.move(to: CGPoint(x: a.midX, y: a.midY))
            path.addLine(to: CGPoint(x: b.midX, y: b.midY))
            let w = 1.2 / scale
            world.stroke(path, with: .color(Color(.systemGray2).opacity(0.7)),
                         style: StrokeStyle(lineWidth: w, dash: [5 / scale, 4 / scale]))
            if !far, !tie.label.isEmpty {
                let mid = CGPoint(x: (a.midX + b.midX) / 2, y: (a.midY + b.midY) / 2)
                let text = world.resolve(Text(tie.label).font(.system(size: 11 / max(scale, 0.5)))
                    .foregroundStyle(Color(.secondaryLabel)))
                let measured = text.measure(in: CGSize(width: 400, height: 100))
                let back = CGRect(x: mid.x - measured.width / 2 - 4, y: mid.y - measured.height / 2 - 2,
                                  width: measured.width + 8, height: measured.height + 4)
                world.fill(Path(roundedRect: back, cornerRadius: 4), with: .color(Style.page.opacity(0.9)))
                world.draw(text, at: mid, anchor: .center)
            }
        }

        for p in placed where p.rect.intersects(seen) {
            card(p, in: &world, far: far)
        }
    }

    private func card(_ p: LookPlaced, in world: inout GraphicsContext, far: Bool) {
        let card = p.card, face = p.face, r = p.rect, k = card.size
        if card.kind == "heading" {
            if let line = face.lines.first {
                world.draw(Text(line.text).font(.system(size: line.font.pointSize, weight: .bold)).foregroundStyle(.primary),
                           in: r.insetBy(dx: -40, dy: -10))
            }
            return
        }
        // A picture is never rounded (his rule, 2026-10-07): a card that
        // carries one is square, so its picture can be.
        let corner: CGFloat = face.pictured ? 0 : 8 * k
        let shape = Path(roundedRect: r, cornerRadius: corner, style: .continuous)
        let ground = LookKind.ground(card.kind)
        if !face.bare {
            if card.kind == "idea" {
                world.stroke(shape, with: .color(Color(.separator)), lineWidth: 1 / max(scale, 0.3))
            } else {
                if !far {
                    var shadow = world
                    shadow.addFilter(.shadow(color: .black.opacity(0.10), radius: 6 * k, y: 2 * k))
                    shadow.fill(shape, with: .color(ground))
                } else {
                    world.fill(shape, with: .color(ground))
                }
                world.stroke(shape, with: .color(Color.black.opacity(0.08)), lineWidth: 0.6 / max(scale, 0.3))
            }
        }
        var y = r.minY
        if face.pictured {
            let pic = CGRect(x: r.minX + face.inset, y: r.minY + face.inset, width: r.width - 2 * face.inset,
                             height: face.bare ? r.height - 2 * face.inset
                                : (r.width - 2 * face.inset) / max(0.25, pictures.shape(card.cover) ?? 1.6))
            let clip = Path(pic)
            if let image = pictures.large[card.cover] ?? pictures.small[card.cover] {
                world.drawLayer { layer in
                    layer.clip(to: clip)
                    layer.draw(Image(uiImage: image).resizable(), in: pic)
                }
            } else {
                world.fill(clip, with: .color(Color(.systemGray5)))
            }
            if !card.clip.isEmpty || card.kind == "video" {
                let d = min(44 * k, pic.width / 3)
                let disc = CGRect(x: pic.midX - d / 2, y: pic.midY - d / 2, width: d, height: d)
                world.fill(Path(ellipseIn: disc), with: .color(.black.opacity(0.45)))
                var play = Path()
                play.move(to: CGPoint(x: disc.minX + d * 0.4, y: disc.minY + d * 0.3))
                play.addLine(to: CGPoint(x: disc.minX + d * 0.72, y: disc.midY))
                play.addLine(to: CGPoint(x: disc.minX + d * 0.4, y: disc.maxY - d * 0.3))
                play.closeSubpath()
                world.fill(play, with: .color(.white))
            }
            y = pic.maxY + (face.inset > 0 ? face.inset : 0)
        }
        guard !face.bare, !face.lines.isEmpty else { return }
        let pad = LookCardFace.pad * k
        y += pad
        let x = r.minX + pad, w = r.width - 2 * pad
        for line in face.lines {
            let box = CGRect(x: x, y: y, width: w, height: line.height)
            if far {
                // Too far out to read: a grey bar where the words are.
                let bar = CGRect(x: x, y: y + line.height * 0.25, width: w * 0.8, height: max(2, line.height * 0.5))
                world.fill(Path(roundedRect: bar, cornerRadius: 2), with: .color(Color(.systemGray4)))
            } else {
                let weight: Font.Weight = line.font.fontDescriptor.symbolicTraits.contains(.traitBold) ? .semibold : .regular
                world.draw(Text(line.text)
                    .font(.system(size: line.font.pointSize, weight: line.upper ? .semibold : weight))
                    .kerning(line.upper ? 1.2 * k : 0)
                    .foregroundStyle(line.color), in: box)
            }
            y += line.height + 5 * k
        }
    }
}

/// **A columns sort**: a column per value, each a small grid of the cards in
/// it, anything without one in a last column. Read on a phone the way the
/// portal lays them out on a desk.
private struct LookBoardColumns: View {
    let board: LookBoard
    let sort: LookBoard.Sort
    @ObservedObject var pictures: LookBoardPictures
    let tap: (LookBoard.Card) -> Void

    private var columns: [(id: String, name: String, cards: [LookBoard.Card])] {
        let list = board.cards.filter { $0.kind != "heading" }
        var out = sort.cols.map { col in (col.id, col.name, list.filter { LookBoard.column($0, of: sort) == col.id }) }
        let known = Set(sort.cols.map(\.id))
        let rest = list.filter { !known.contains(LookBoard.column($0, of: sort)) }
        if !rest.isEmpty { out.append(("", sort.none, rest)) }
        return out
    }

    var body: some View {
        GeometryReader { space in
            let width = max(124, (space.size.width - 24) / CGFloat(min(3, max(1, columns.count))) - 6)
            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(columns, id: \.id) { column in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(column.name)
                                    .font(.footnote.weight(.bold))
                                    .lineLimit(2)
                                Spacer(minLength: 2)
                                Text("\(column.cards.count)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 4) {
                                ForEach(column.cards) { card in
                                    tile(card).onTapGesture { tap(card) }
                                }
                            }
                        }
                        .padding(8)
                        .frame(width: width, alignment: .topLeading)
                        .background(Style.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    @ViewBuilder
    private func tile(_ card: LookBoard.Card) -> some View {
        let cover = card.cover
        if !cover.isEmpty {
            Color(.systemGray5)
                .aspectRatio(1.3, contentMode: .fit)
                .overlay {
                    if let image = pictures.large[cover] ?? pictures.small[cover] {
                        Image(uiImage: image).resizable().scaledToFill()
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if let mark = mark(card) {
                        Text(mark)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 3))
                            .padding(3)
                    }
                }
                .clipped()
                .contentShape(Rectangle())
        } else {
            Text(card.name)
                .font(.system(size: 10))
                .lineLimit(5)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
                .padding(5)
                .background(LookKind.ground(card.kind) == .clear ? Color(.systemBackground) : LookKind.ground(card.kind),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
    }

    /// A shot's number or a scene's, on its picture.
    private func mark(_ card: LookBoard.Card) -> String? {
        if let live = card.live, !live.key.isEmpty { return live.key }
        return nil
    }
}

// MARK: - a card, opened

private struct LookCardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.lookFiles) private var files
    let board: LookBoard
    @State var card: LookBoard.Card
    let session: Session?
    @State private var viewing: LookViewer.Opening?
    @State private var playing: LookClipOpening?
    @State private var path = NavigationPath()

    private var threads: [(card: LookBoard.Card, label: String)] {
        board.ties.compactMap { tie in
            let other = tie.a == card.id ? tie.b : (tie.b == card.id ? tie.a : nil)
            guard let other, let found = board.card(other) else { return nil }
            return (found, tie.label)
        }
    }

    private var sorted: [String] {
        board.sorts.compactMap { sort in
            if sort.type == "columns" {
                let at = LookBoard.column(card, of: sort)
                guard let col = sort.cols.first(where: { $0.id == at }) else { return nil }
                return "\(sort.name) · \(col.name)"
            }
            guard let v = card.vals[sort.id]?.number, sort.ends.count == 2 else { return nil }
            let pct = Int((v * 100).rounded())
            return "\(sort.name) · \(pct)%"
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.kicker.isEmpty ? LookKind.name(card.kind) : card.kicker)
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(LookKind.tint(card.kind))
                        if !card.title.isEmpty, card.title != card.kicker {
                            Text(card.title).font(.title2.weight(.bold))
                        }
                    }
                    if !card.cover.isEmpty {
                        Button {
                            if !card.clip.isEmpty {
                                Task { await play() }
                            } else {
                                let names = [card.cover] + card.figs.map { lookFileName($0.0) }.filter { $0 != card.cover }
                                viewing = .init(names: names, at: 0)
                            }
                        } label: {
                            ZStack {
                                LookPicture(name: card.cover, longest: 1400, mode: .fit)
                                if !card.clip.isEmpty {
                                    Image(systemName: "play.fill")
                                        .font(.title2)
                                        .foregroundStyle(.white)
                                        .frame(width: 58, height: 58)
                                        .background(.black.opacity(0.45), in: Circle())
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 240)
                            .clipped()
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach([card.sub, card.cap == card.kicker ? "" : card.cap, card.said, card.text].filter { !$0.isEmpty }, id: \.self) { words in
                        Text(words).font(.body)
                    }
                    if !card.fields.isEmpty {
                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                            ForEach(Array(card.fields.enumerated()), id: \.offset) { _, field in
                                GridRow {
                                    Text(field.0).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    Text(field.1).font(.subheadline)
                                }
                            }
                        }
                    } else if !card.facts.isEmpty {
                        Chips(tags: card.facts.map { .init(text: $0, tint: .gray) })
                    }
                    if !threads.isEmpty {
                        group("Threads") {
                            Wrap(spacing: 6) {
                                ForEach(Array(threads.enumerated()), id: \.offset) { _, thread in
                                    Button {
                                        withAnimation(.snappy) { card = thread.card }
                                    } label: {
                                        Text(thread.label.isEmpty ? thread.card.name : "\(thread.card.kicker.isEmpty ? thread.card.name : thread.card.kicker) · \(thread.label)")
                                            .font(.footnote)
                                            .lineLimit(1)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color(.tertiarySystemFill), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    if !sorted.isEmpty {
                        group("Sorts") {
                            Wrap(spacing: 6) {
                                ForEach(sorted, id: \.self) { said in
                                    Text(said)
                                        .font(.footnote)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color(.tertiarySystemFill), in: Capsule())
                                }
                            }
                        }
                    }
                    links
                }
                .padding(18)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .navigationDestination(for: SceneShotsView.Opening.self) { opening in
                if let session {
                    ShotDetailView(sceneId: opening.sceneId, heading: opening.heading, showing: opening.rowId)
                        .environmentObject(session)
                }
            }
            .navigationDestination(for: Engine.Scene.self) { scene in
                if let session {
                    SceneShotsView(scene: scene).environmentObject(session)
                }
            }
        }
        .fullScreenCover(item: $viewing) { LookViewer(opening: $0).environment(\.lookFiles, files) }
        .fullScreenCover(item: $playing) { LookPlayer(url: $0.url) }
        .onAppear {
            // Checking door (`LookCheck`): follow the card into the film.
            guard LookCheck.value("--lookcard", 2) == "open" else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if let shot = filmShot { path.append(shot) } else if let scene = filmScene { path.append(scene) }
            }
        }
    }

    private func group<Content: View>(_ name: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    /// Into the app's own shot or scene, when this film has it.
    @ViewBuilder private var links: some View {
        let shot = filmShot
        let scene = filmScene
        if shot != nil || scene != nil || !card.href.isEmpty {
            VStack(spacing: 0) {
                if let shot {
                    NavigationLink(value: shot) { row("Open in Shot List", "list.bullet.rectangle") }
                }
                if let scene {
                    if shot != nil { Divider().padding(.leading, 44) }
                    NavigationLink(value: scene) { row("Open Scene", "film") }
                }
                if let url = URL(string: card.href), !card.href.isEmpty {
                    if shot != nil || scene != nil { Divider().padding(.leading, 44) }
                    Button { openURL(url) } label: { row("Open Link", "link") }
                }
            }
            .buttonStyle(.plain)
            .background(Style.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func row(_ name: String, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 22)
            Text(name)
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var filmShot: SceneShotsView.Opening? {
        guard let session, let live = card.live, live.type == "shot" else { return nil }
        let rows = session.groups.flatMap(\.rows)
        guard let row = rows.first(where: { !live.id.isEmpty && $0.shot == live.id })
                ?? rows.first(where: { !live.key.isEmpty && $0.number == live.key }),
              let sceneId = row.sceneId else { return nil }
        return SceneShotsView.Opening(rowId: row.id, sceneId: sceneId,
                                      heading: session.scene(sceneId)?.heading ?? "")
    }

    private var filmScene: Engine.Scene? {
        guard let session, let live = card.live else { return nil }
        if live.type == "scene" {
            return session.scenes.first { $0.id == live.id } ?? session.scenes.first { $0.number == live.key }
        }
        if live.type == "shot", let opening = filmShot { return session.scene(opening.sceneId) }
        return nil
    }

    private func play() async {
        guard let files, let url = await files.file(named: card.clip) else { return }
        playing = .init(url: url)
    }
}
