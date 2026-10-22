import SwiftUI
import PDFKit

/// **The Library opens the portal's pages, decks and boards natively** (Ref
/// 1541, the integration of Stage C's line and Stage E's views).
///
/// `PortalNative` is what a written page, a deck or a look board shows when it
/// is opened from the Library or from a pin: the stored JSON the portal keeps
/// (kept on the phone by `PortalLine`) drawn by `LookPageView`,
/// `LookDeckView` or `LookBoardView`. A page the portal holds only as
/// designed HTML is a written page here: the door reads it back into blocks
/// (`treeFromHtml` on the hub), so the phone never draws HTML. One with no
/// copy and no signal hands back to `PortalItemView`.
struct PortalNative<Fallback: View>: View {
    let item: PortalItem
    @ViewBuilder var fallback: () -> Fallback
    @EnvironmentObject private var portal: PortalLine
    @EnvironmentObject private var session: Session
    @State private var drawn: AnyView?
    @State private var tried = false

    /// Which kind of native view, if the phone has one for this item: the
    /// same rule `PortalLine` uses to decide what it keeps.
    static func kind(of item: PortalItem) -> String? {
        if item.kind == "board" { return "board" }
        // A deck, or a page published as a deck's web page (a Built In
        // Visual Bible): the portal draws the deck, so the phone does too.
        if item.deck == true && (item.kind == "deck" || item.html == true) { return "deck" }
        // A written page, or one published as designed HTML, which the door
        // hands down as blocks.
        return item.tree == true || item.html == true ? "page" : nil
    }

    /// The task restarts when the portal's copy moves or the Library comes down.
    private struct Cause: Equatable {
        var stamp: Double?
        var fetching: Bool
    }

    var body: some View {
        Group {
            if let drawn {
                drawn
            } else if tried {
                fallback()
            } else {
                ProgressView()
            }
        }
        .task(id: Cause(stamp: item.stamp, fetching: portal.fetching)) {
            guard let kind = Self.kind(of: item), let files = portal.files else { tried = true; return }
            if let data = await portal.stored(kind, item.key) {
                drawn = Self.view(kind, item, data, files, session)
            }
            if drawn == nil && !portal.fetching { tried = true }
        }
    }

    private static func view(_ kind: String, _ item: PortalItem, _ data: Data,
                             _ files: PortalFiles, _ session: Session) -> AnyView? {
        switch kind {
        case "page":
            return (try? LookPageView(title: item.name, data: data, files: files)).map { AnyView($0) }
        case "deck":
            return (try? LookDeckView(data: data, files: files, printed: item.pdf?.file)).map { AnyView($0) }
        case "board":
            return (try? LookBoardView(title: item.name, data: data, files: files, session: session)).map { AnyView($0) }
        default:
            return nil
        }
    }
}

// MARK: - the Look shelf

/// **Look, as one tab** (`design/33-one-app.html` section 5): the Visual Bible
/// first, as a card of its own pictures; the boards, each with a montage of
/// its cards; the decks as covers; the reference images the film already
/// holds; and any document filed on the shelf.
struct LookShelfView: View {
    @EnvironmentObject private var portal: PortalLine
    @EnvironmentObject private var session: Session
    @State private var glimpses: [String: Glimpse] = [:]

    /// What a card of the shelf shows of its page, deck or board.
    struct Glimpse: Sendable {
        var pictures: [String] = []
        var said = ""
    }

    private var items: [PortalItem] { portal.items(on: .creative) }
    private func drawn(_ item: PortalItem) -> String? { PortalNative<EmptyView>.kind(of: item) }
    /// **Every page on the shelf, the Visual Bible first** (his note,
    /// 2026-10-10: *"the visual Bible somehow not in the category of look...
    /// it literally is defining the look"*). A page used to need a copy the
    /// phone could draw, which left the Built In Visual Bible out; now
    /// anything that is not a board, deck or document is a page card here.
    private var pages: [PortalItem] {
        items.filter { $0.kind != "board" && $0.kind != "deck" && !$0.isDocument }
            .sorted { ($0.key == "bible" ? 0 : 1) < ($1.key == "bible" ? 0 : 1) }
    }
    private var boards: [PortalItem] { items.filter { $0.kind == "board" } }
    private var decks: [PortalItem] { items.filter { $0.kind == "deck" } }
    private var documents: [PortalItem] { items.filter { $0.isDocument } }

    /// The task restarts when the Library's items move.
    private var cause: [String] { items.map { "\($0.key)@\($0.stamp ?? 0)" } + [portal.fetching ? "…" : ""] }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(pages) { item in
                    // A page with no pictures to show (the Built In Visual
                    // Bible, a page not yet kept here) is a plain row rather
                    // than an empty grey grid.
                    NavigationLink(value: Place.page(item.key)) {
                        if glimpses[item.key]?.pictures.isEmpty == false {
                            PageCard(item: item, glimpse: glimpses[item.key])
                        } else {
                            Row(title: item.name, symbol: item.symbol)
                        }
                    }
                        .buttonStyle(.plain)
                        .contextMenu { MoveToMenu(item: item) }
                        .padding(.bottom, 10)
                }
                if !boards.isEmpty {
                    Heading("Boards")
                    ForEach(boards) { item in
                        NavigationLink(value: Place.page(item.key)) { BoardCard(item: item, glimpse: glimpses[item.key]) }
                            .buttonStyle(.plain)
                            .contextMenu { MoveToMenu(item: item) }
                            .padding(.bottom, 10)
                    }
                }
                if !decks.isEmpty {
                    Heading("Decks")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(decks) { item in
                                NavigationLink(value: Place.page(item.key)) {
                                    DeckCard(item: item, glimpse: glimpses[item.key], printed: printed[item.key])
                                }
                                .buttonStyle(.plain)
                                .contextMenu { MoveToMenu(item: item) }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.horizontal, -16)
                }
                Heading("Reference Images")
                if session.boards.isEmpty {
                    NavigationLink(value: Place.references) {
                        Row(title: "Reference Images", symbol: Place.references.symbol)
                    }
                    .buttonStyle(.plain)
                } else {
                    // **The film's own reference boards, as their covers**
                    // (the mockup's `.refgrid`), each opening its board.
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                              spacing: 14) {
                        ForEach(session.boards) { board in
                            NavigationLink(value: board) { BoardCover(board: board) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if !documents.isEmpty {
                    Heading("Documents")
                    LibraryCard {
                        ForEach(documents) { item in
                            NavigationLink(value: Place.page(item.key)) {
                                LibraryRow(item: item, pinned: false)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { MoveToMenu(item: item) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .background(Style.page)
        .environment(\.lookFiles, portal.files)
        .leadingTitle(portal.shelf(Shelf.creative.id).name)
        .navigationDestination(for: Place.self) { place in PlaceView(place: place) }
        .navigationDestination(for: Engine.Board.self) { board in
            BoardDetailView(id: board.id).environmentObject(session)
        }
        .refreshable { await portal.refresh() }
        .task(id: cause) { await look() }
    }

    /// Each deck's printed first page, where it has a printed copy: the
    /// cover the portal's own deck opens on.
    @State private var printed: [String: UIImage] = [:]

    /// A glimpse of each page, deck and board, read from the copy kept here,
    /// off the main thread.
    private func look() async {
        for item in items {
            guard let kind = PortalNative<EmptyView>.kind(of: item), glimpses[item.key] == nil,
                  let data = await portal.stored(kind, item.key) else { continue }
            let seen = await Task.detached(priority: .utility) { Self.glimpse(kind, data) }.value
            if let seen { glimpses[item.key] = seen }
        }
        for item in decks where printed[item.key] == nil {
            guard let name = item.pdf?.file, let url = await portal.fetch(file: name) else { continue }
            let page = await Task.detached(priority: .utility) { () -> UIImage? in
                PDFDocument(url: url)?.page(at: 0)?.thumbnail(of: CGSize(width: 324, height: 420), for: .mediaBox)
            }.value
            if let page { printed[item.key] = page }
        }
    }

    nonisolated static func glimpse(_ kind: String, _ data: Data) -> Glimpse? {
        switch kind {
        case "page":
            guard let blocks = try? LookBlock.page(data) else { return nil }
            let sections = blocks.filter { $0.isHeading && !$0.plain.isEmpty }.count
            return Glimpse(pictures: Array(blocks.flatMap(\.pictures).prefix(8)),
                           said: sections == 1 ? "1 section" : "\(sections) sections")
        case "board":
            guard let board = try? LookBoard(data: data) else { return nil }
            let covers = board.cards.map(\.cover).filter { !$0.isEmpty }
            let count = board.cards.count
            let sorts = board.sorts.count
            var said = count == 1 ? "1 card" : "\(count) cards"
            if sorts > 0 { said += sorts == 1 ? " · 1 sort" : " · \(sorts) sorts" }
            return Glimpse(pictures: Array(covers.prefix(12)), said: said)
        case "deck":
            guard let deck = try? LookDeck(data: data) else { return nil }
            var cover: String?
            for section in deck.sections where section.on && cover == nil {
                for group in section.groups where cover == nil {
                    cover = group.pictures.lazy.compactMap { deck.picture($0)?.name }.first
                }
            }
            if cover == nil { cover = deck.pictures.values.first?.name }
            // The deck's own name, so the line under a cover says what the
            // deck is rather than the word Deck three times in a row.
            return Glimpse(pictures: cover.map { [$0] } ?? [], said: deck.name)
        default:
            return nil
        }
    }

    // ---- the pieces ----------------------------------------------------------

    private struct Heading: View {
        let text: String
        init(_ text: String) { self.text = text }
        var body: some View {
            SectionTitle(text)
                .padding(.top, 14)
                .padding(.bottom, 10)
                .padding(.leading, 4)
        }
    }

    private struct Row: View {
        let title: String
        let symbol: String
        var body: some View {
            HStack(spacing: 10) {
                LibraryRow.Tile(symbol: symbol)
                Text(title).font(.system(size: 15))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .card(Style.Radius.list)
            .contentShape(Rectangle())
        }
    }

    /// A grid of a page's, a board's or a deck's own pictures, `across` to a row.
    private struct Montage: View {
        let names: [String]
        let across: Int
        let rows: Int

        var body: some View {
            let shown = Array(names.prefix(across * rows))
            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: across)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<(across * rows), id: \.self) { index in
                    // A square the width of its column, the picture laid over
                    // it and cut to it: a picture never sets its own size.
                    Color(.tertiarySystemFill)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            if index < shown.count { LookPicture(name: shown[index], longest: 360) }
                        }
                        .clipped()
                }
            }
        }
    }

    /// **The Visual Bible's card** (the mockup's `.bcard`): its pictures four
    /// across, its name large under them.
    private struct PageCard: View {
        let item: PortalItem
        let glimpse: Glimpse?
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Montage(names: glimpse?.pictures ?? [], across: 4, rows: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.system(size: 20, weight: .bold))
                    if let said = glimpse?.said {
                        Text(said).font(.system(size: 13)).foregroundStyle(Style.ink3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }
            .card(Style.Radius.card)
            .contentShape(Rectangle())
        }
    }

    /// **A board's card** (the mockup's `.boardcard`): a small montage of its
    /// cards beside its name and count.
    private struct BoardCard: View {
        let item: PortalItem
        let glimpse: Glimpse?
        var body: some View {
            HStack(spacing: 12) {
                Montage(names: glimpse?.pictures ?? [], across: 4, rows: 3)
                    .frame(width: 120)
                    .clipShape(Rectangle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.system(size: 20, weight: .bold)).lineLimit(2)
                    if let said = glimpse?.said {
                        Text(said).font(.system(size: 13)).foregroundStyle(Style.ink3)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(10)
            .card(20)
            .contentShape(Rectangle())
        }
    }

    /// **A deck as its cover** (the mockup's `.deckcard`): upright, its
    /// printed first page where it has one, else its first picture.
    private struct DeckCard: View {
        let item: PortalItem
        let glimpse: Glimpse?
        let printed: UIImage?
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if let printed {
                        Image(uiImage: printed).resizable().aspectRatio(contentMode: .fill)
                    } else if let cover = glimpse?.pictures.first {
                        LookPicture(name: cover, longest: 480)
                    } else {
                        Rectangle().fill(Color(light: 0x141010, dark: 0x2C2C2E))
                            .overlay {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                    }
                }
                .frame(width: 108, height: 140, alignment: .top)
                .clipShape(Rectangle())
                // **Two lines reserved, so the captions share a baseline.**
                // A two-line title used to shove its caption down and the row
                // went ragged (2026-10-07).
                Text(item.name)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 108, height: 34, alignment: .topLeading)
                if let said = glimpse?.said, !said.isEmpty, said != item.name {
                    Text(said)
                        .font(.system(size: 13))
                        .foregroundStyle(Style.ink3)
                        .lineLimit(2)
                        .frame(width: 108, alignment: .leading)
                }
            }
            .contentShape(Rectangle())
        }
    }
}
