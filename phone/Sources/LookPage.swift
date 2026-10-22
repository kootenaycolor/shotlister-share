import SwiftUI
import QuickLook

/// **A written page, drawn natively** — any Visual Bible, any page written on
/// the portal or fed to it from Notion (Ref 1551; `design/33-one-app.html`
/// section 5 and 8).
///
/// The portal keeps every such page as one small tree of blocks
/// (`p/<film>/pages/<slug>.json`, drawn there by `drawBlocks` in
/// `hub/src/pages.js`). The phone learns the dozen kinds of block once and so
/// reads every page: a bible from Notion and a shoot's notes written by an
/// agent come out of the same code.
///
/// What it does that the portal's page does not: a row of the page's headings
/// to jump between, pictures that open full screen, and a toggle drawn open
/// (on a set, a section hidden behind a triangle is a section nobody reads).
struct LookBlock: Decodable, Identifiable {
    struct Run: Decodable, Hashable {
        var s: String = ""
        var u: String?
    }

    var id = UUID()
    /// What kind: h1 h2 h3 p quote callout hr li toggle img file table trow
    /// columns column video.
    var t: String = ""
    var r: [Run] = []
    var k: [LookBlock] = []
    /// A numbered list item.
    var n: Bool = false
    /// A picture's, a file's or a clip's stored name (`<hash>.<ext>`).
    var src: String = ""
    var cap: String = ""
    /// A file's own name, and an address for a file kept elsewhere, or a
    /// clip on Livid or YouTube.
    var name: String = ""
    var url: String = ""
    var bytes: Int = 0
    /// A table whose first row is its heading.
    var head: Bool = false
    /// A table row's cells.
    var c: [[Run]] = []
    /// A clip's still, when it has one.
    var poster: String = ""

    enum Key: String, CodingKey { case t, r, k, n, src, cap, name, url, bytes, head, c, poster }

    init(from decoder: Decoder) throws {
        let d = try decoder.container(keyedBy: Key.self)
        t = (try? d.decode(String.self, forKey: .t)) ?? ""
        r = (try? d.decode([Run].self, forKey: .r)) ?? []
        k = (try? d.decode([LookBlock].self, forKey: .k)) ?? []
        n = (try? d.decode(Bool.self, forKey: .n)) ?? false
        src = (try? d.decode(String.self, forKey: .src)) ?? ""
        cap = (try? d.decode(String.self, forKey: .cap)) ?? ""
        name = (try? d.decode(String.self, forKey: .name)) ?? ""
        url = (try? d.decode(String.self, forKey: .url)) ?? ""
        bytes = (try? d.decode(Int.self, forKey: .bytes)) ?? 0
        head = (try? d.decode(Bool.self, forKey: .head)) ?? false
        c = (try? d.decode([[Run]].self, forKey: .c)) ?? []
        poster = (try? d.decode(String.self, forKey: .poster)) ?? ""
    }

    /// A page's stored blocks. An empty or unreadable page is no blocks.
    static func page(_ data: Data) throws -> [LookBlock] {
        try JSONDecoder().decode([LookBlock].self, from: data)
    }

    var plain: String { r.map(\.s).joined() }
    var isHeading: Bool { t == "h1" || t == "h2" }

    /// Every picture under this block, in reading order.
    var pictures: [String] {
        (t == "img" && !src.isEmpty ? [src] : []) + k.flatMap(\.pictures)
    }

    /// A columns block that is only pictures: drawn as a grid, row by row.
    var pictureColumns: [[String]]? {
        guard t == "columns", !k.isEmpty else { return nil }
        let cols = k.map { $0.k }
        guard cols.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.t == "img" && !$0.src.isEmpty } }) else { return nil }
        let names = cols.map { $0.map(\.src) }
        let tallest = names.map(\.count).max() ?? 0
        // Side by side on the portal, so a row here is the n-th of each column.
        return (0..<tallest).map { row in names.compactMap { row < $0.count ? $0[row] : nil } }
    }
}

/// Runs of words, a link where one is.
func lookRuns(_ runs: [LookBlock.Run]) -> AttributedString {
    var out = AttributedString()
    for run in runs {
        var piece = AttributedString(run.s)
        if let u = run.u, let url = URL(string: u) {
            piece.link = url
            piece.underlineStyle = .single
        }
        out += piece
    }
    return out
}

struct LookPageView: View {
    let title: String
    var subtitle: String = ""
    let blocks: [LookBlock]
    let files: any LookFiles

    @State private var viewing: LookViewer.Opening?
    @State private var chosen: UUID?

    init(title: String, subtitle: String = "", blocks: [LookBlock], files: any LookFiles) {
        self.title = title
        self.subtitle = subtitle
        self.blocks = blocks
        self.files = files
    }

    /// From the page's stored JSON as the portal keeps it.
    init(title: String, subtitle: String = "", data: Data, files: any LookFiles) throws {
        self.init(title: title, subtitle: subtitle, blocks: try LookBlock.page(data), files: files)
    }

    private var headings: [LookBlock] { blocks.filter { $0.isHeading && !$0.plain.isEmpty } }
    private var everyPicture: [String] { blocks.flatMap(\.pictures) }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 28, weight: .heavy))
                            .kerning(-0.6)
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 13))
                                .foregroundStyle(Style.ink3)
                        }
                    }
                    .padding(.bottom, 2)
                    // **The page's headings as chips under its name** (the
                    // mockup's `.chips`): a tap goes there. The bar's list
                    // button does the same once they have scrolled away.
                    if headings.count > 1 {
                        ScrollViewReader { chips in
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(headings) { heading in
                                        Button {
                                            jump(to: heading.id, reader)
                                        } label: {
                                            InkChip(text: heading.plain, on: (chosen ?? headings.first?.id) == heading.id)
                                        }
                                        .buttonStyle(.plain)
                                        .id("chip-\(heading.id)")
                                    }
                                }
                                .padding(.horizontal, 18)
                            }
                            .padding(.horizontal, -18)
                            .onChange(of: chosen) { _, now in
                                if let now { withAnimation(.snappy) { chips.scrollTo("chip-\(now)", anchor: .center) } }
                            }
                        }
                        .padding(.bottom, 4)
                    }
                    if blocks.isEmpty {
                        Text("Nothing written yet")
                            .foregroundStyle(.secondary)
                    }
                    LookBlocks(blocks: blocks, depth: 0, open: open)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 40)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Style.page)
            .onAppear {
                // Checking doors (`LookCheck`): a heading, a picture.
                if let n = LookCheck.value("--lookjump").flatMap(Int.init), n < headings.count {
                    let target = headings[n].id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        chosen = target
                        reader.scrollTo(target, anchor: .top)
                    }
                }
                if let n = LookCheck.value("--lookpicture").flatMap(Int.init), n < everyPicture.count {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { open(everyPicture[n]) }
                }
            }
            .toolbar {
                if headings.count > 1 {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            ForEach(headings) { heading in
                                Button(heading.plain) { jump(to: heading.id, reader) }
                            }
                        } label: {
                            Label("Sections", systemImage: "list.bullet")
                        }
                    }
                }
            }
        }
        .environment(\.lookFiles, files)
        .fullScreenCover(item: $viewing) { opening in
            LookViewer(opening: opening).environment(\.lookFiles, files)
        }
    }

    private func jump(to id: UUID, _ reader: ScrollViewProxy) {
        chosen = id
        withAnimation(.snappy) { reader.scrollTo(id, anchor: .top) }
    }

    private func open(_ name: String) {
        let all = everyPicture
        viewing = .init(names: all.isEmpty ? [name] : all, at: all.firstIndex(of: name) ?? 0)
    }
}

/// A run of blocks: pictures next to each other become one grid, numbered
/// items count up, everything else is drawn as it comes.
struct LookBlocks: View {
    let blocks: [LookBlock]
    let depth: Int
    let open: (String) -> Void

    private enum Piece: Identifiable {
        case one(LookBlock, number: Int)
        case pictures([LookBlock])

        var id: UUID {
            switch self {
            case .one(let b, _): return b.id
            case .pictures(let list): return list[0].id
            }
        }
    }

    private var pieces: [Piece] {
        var out: [Piece] = []
        var run: [LookBlock] = []
        var counting = 0
        for block in blocks {
            if block.t == "img", !block.src.isEmpty {
                run.append(block)
                continue
            }
            if !run.isEmpty { out.append(.pictures(run)); run = [] }
            counting = block.t == "li" && block.n ? counting + 1 : 0
            out.append(.one(block, number: counting))
        }
        if !run.isEmpty { out.append(.pictures(run)) }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(pieces) { piece in
                switch piece {
                case .pictures(let list):
                    LookPictureGrid(rows: lookLines(list.map(\.src), most: 3),
                                    captions: list.map(\.cap), open: open)
                        .padding(.vertical, 4)
                case .one(let block, let number):
                    LookBlockView(block: block, number: number, depth: depth, open: open)
                        .id(block.id)
                }
            }
        }
    }
}

/// Lines of pictures, each line at one height; captions under, if any.
struct LookPictureGrid: View {
    let rows: [[String]]
    var captions: [String] = []
    let open: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                LookPictureRow(names: row) { open(row[$0]) }
            }
            let said = captions.filter { !$0.isEmpty }
            if !said.isEmpty {
                Text(said.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct LookBlockView: View {
    @Environment(\.lookFiles) private var files
    @Environment(\.openURL) private var openURL
    let block: LookBlock
    let number: Int
    let depth: Int
    let open: (String) -> Void
    @State private var looking: URL?
    @State private var playing: LookClipOpening?

    var body: some View {
        switch block.t {
        // The mockup's written page (`.nb-*`): headings heavy and tight,
        // the words at 15 with air between the lines.
        case "h1":
            heading(.system(size: 26, weight: .heavy), top: 18)
        case "h2":
            heading(.system(size: 21, weight: .bold), top: 12)
        case "h3", "toggle":
            heading(.system(size: 17, weight: .bold), top: 6)
        case "p":
            VStack(alignment: .leading, spacing: 6) {
                if !block.r.isEmpty { Text(lookRuns(block.r)).font(Self.words).lineSpacing(2.5) }
                kids
            }
        case "quote":
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color(.label)).frame(width: 3)
                VStack(alignment: .leading, spacing: 6) {
                    Text(lookRuns(block.r)).font(.system(size: 15)).lineSpacing(2.5)
                    kids
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        case "callout":
            VStack(alignment: .leading, spacing: 6) {
                Text(lookRuns(block.r)).font(Self.words).lineSpacing(2.5)
                kids
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(Style.Radius.tile)
        case "hr":
            Divider().padding(.vertical, 6)
        case "li":
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(block.n ? "\(max(1, number))." : (depth % 2 == 0 ? "•" : "◦"))
                    .font(Self.words.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 12, alignment: .trailing)
                VStack(alignment: .leading, spacing: 6) {
                    Text(lookRuns(block.r)).font(Self.words).lineSpacing(2)
                        .foregroundStyle(depth > 0 ? Style.ink2 : Color(.label))
                    kids
                }
            }
        case "img":
            LookPictureGrid(rows: [[block.src]], captions: [block.cap], open: open)
        case "columns":
            if let grid = block.pictureColumns {
                // Each picture's caption, under the row, as one picture's is.
                LookPictureGrid(rows: grid, captions: block.k.flatMap { $0.k.map(\.cap) }, open: open)
            } else {
                // Side by side on a desk is one under the other on a phone.
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(block.k) { column in
                        LookBlocks(blocks: column.k, depth: depth, open: open)
                    }
                }
            }
        case "column":
            kids
        case "table":
            LookTable(block: block)
        case "file":
            fileRow
        case "video":
            clip
        default:
            // A kind this phone does not know yet: its words, if it has any.
            if !block.r.isEmpty { Text(lookRuns(block.r)) }
        }
    }

    /// The words of a written page: 15, the mockup's `.nb-p`.
    static let words = Font.system(size: 15)

    @ViewBuilder private var kids: some View {
        if !block.k.isEmpty {
            LookBlocks(blocks: block.k, depth: depth + 1, open: open)
        }
    }

    private func heading(_ font: Font, top: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lookRuns(block.r))
                .font(font)
                .padding(.top, top)
            kids
        }
    }

    private var fileRow: some View {
        Button {
            Task { await openFile() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: block.src.isEmpty && !block.url.isEmpty ? "link" : "doc")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.name.isEmpty ? (block.src.isEmpty ? block.url : block.src) : block.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if block.bytes > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(block.bytes), countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .card(12)
        }
        .buttonStyle(.plain)
        .quickLookPreview($looking)
    }

    private func openFile() async {
        if !block.src.isEmpty, let files, let url = await files.file(named: block.src) {
            if url.isFileURL { looking = url } else { openURL(url) }
        } else if let url = URL(string: block.url), !block.url.isEmpty {
            openURL(url)
        }
    }

    /// **A clip** (his decision, 2026-10-06: the hand-made pages are rebuilt
    /// from blocks, with Video as a new one). Its still with a play mark; a
    /// stored clip plays here, a Livid or YouTube one opens in Safari.
    private var clip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                Task { await play() }
            } label: {
                Color.black
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        if !block.poster.isEmpty { LookPicture(name: block.poster, longest: 1400) }
                    }
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                .clipShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !block.cap.isEmpty || !block.r.isEmpty {
                Text(block.cap.isEmpty ? block.plain : block.cap)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fullScreenCover(item: $playing) { LookPlayer(url: $0.url) }
        .onAppear {
            // Checking door (`LookCheck`): `--lookplay <stored name>`.
            if !block.src.isEmpty, LookCheck.value("--lookplay") == block.src {
                Task { try? await Task.sleep(for: .seconds(1)); await play() }
            }
        }
    }

    private func play() async {
        if !block.src.isEmpty, let files, let url = await files.file(named: block.src) {
            playing = .init(url: url)
        } else if let url = URL(string: block.url), !block.url.isEmpty {
            openURL(url)
        }
    }
}

/// A table drawn as a table (the portal's rule: a table read as prose is not
/// a table). Its heading row small and grey; wide ones scroll sideways.
private struct LookTable: View {
    let block: LookBlock

    private var rows: [LookBlock] { block.k.filter { $0.t == "trow" } }

    var body: some View {
        let head = block.head && !rows.isEmpty ? rows[0] : nil
        let rest = head == nil ? rows : Array(rows.dropFirst())
        let across = rows.map(\.c.count).max() ?? 0
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                if let head {
                    GridRow {
                        ForEach(0..<across, id: \.self) { i in
                            cell(i < head.c.count ? head.c[i] : [])
                                .font(.system(size: 11, weight: .bold))
                                .kerning(0.6)
                                .textCase(.uppercase)
                                .foregroundStyle(Style.ink3)
                        }
                    }
                    Divider()
                }
                ForEach(Array(rest.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        ForEach(0..<across, id: \.self) { i in
                            cell(i < row.c.count ? row.c[i] : []).font(.system(size: 13))
                        }
                    }
                    if index < rest.count - 1 { Divider() }
                }
            }
            .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in
                across > 3 ? max(width, CGFloat(across) * 140) : width
            }
        }
        .card(Style.Radius.tile)
        .padding(.vertical, 4)
    }

    private func cell(_ runs: [LookBlock.Run]) -> some View {
        Text(lookRuns(runs))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
