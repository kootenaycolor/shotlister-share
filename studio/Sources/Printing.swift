import AppKit
import PDFKit
import WebKit

/// Turning a page the engine drew into a PDF.
///
/// The engine decides what is on the page — that is a rule, and belongs where
/// every platform reads the same one. Setting type and deciding where a page
/// breaks is something the system already does better than anything worth
/// hand-writing, so this hands the page to WebKit and asks it to print.
///
/// Ported from the old app's `Printing.swift`, 2026-08-24, for the scene PDF
/// export dialog. Two changes since: rendering hands back a `PDFDocument` in
/// memory rather than writing straight to a destination, so several sections
/// — shot list, storyboard, document — can be rendered separately and joined
/// into one file before anything touches disk; and slicing now asks the page
/// itself where its rows are, so a page break never lands inside one. His
/// report, 2026-08-24: a shot's description ran onto a second page and the
/// second half was simply gone — the old slicer cut at a fixed height with no
/// idea what was there.
enum Printing {
    enum Orientation: String, CaseIterable, Identifiable {
        case portrait, landscape
        var id: String { rawValue }
        var title: String { self == .portrait ? "Portrait" : "Landscape" }
    }

    /// **How much room a picture gets on the page.** His ask, 2026-09-01:
    /// the table's picture column is about a tenth of a landscape page, so a
    /// single frame is small there and a clip's four moments are very small.
    ///
    /// One dial, two effects — the table's picture column, and how many
    /// storyboard cards stand across a row. The engine holds the numbers;
    /// this only carries the word.
    enum FrameSize: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var title: String {
            switch self {
            case .small: return "Small"
            case .medium: return "Medium"
            case .large: return "Large"
            }
        }
    }

    enum Kind: String {
        case document, table, storyboard
        /// **The script down the left, the shots that cover it beside** —
        /// the engine's Script page (`html::script`), his ask from set,
        /// 2026-09-22. Named `avscript` on the wire because `script` in the
        /// export box already means the imported screenplay's own pages.
        case avscript
        /// A scene's overhead, one sheet each.
        case diagram

        var title: String {
            switch self {
            case .document: return "Document"
            case .table: return "Shot List"
            case .storyboard: return "Storyboard"
            case .avscript: return "Script"
            case .diagram: return "Diagram"
            }
        }

        /// The shape each kind reads best in, left alone — a table wants the
        /// room a landscape page gives its columns, a document page reads as
        /// a document. The dialog can still ask for the other one.
        var defaultOrientation: Orientation {
            self == .document || self == .avscript ? .portrait : .landscape
        }

        /// US Letter, in points, either way round.
        func paper(_ orientation: Orientation) -> NSSize {
            orientation == .portrait ? NSSize(width: 612, height: 792) : NSSize(width: 792, height: 612)
        }

        var margin: CGFloat {
            switch self {
            // **One inch, because that is what the app's page has** — his
            // instruction, 2026-09-01: what he sees in the Document view is
            // what the export is. It was 0.75in, and the page it printed was
            // therefore half an inch wider than the one he had been editing,
            // so every line broke somewhere else and every page ended
            // somewhere else. `Page.margin` in `Document.swift` and
            // `doc::MARGIN` in the engine are this same number.
            case .document: return 72
            case .table: return 32
            case .storyboard: return 36
            // Three quarters of an inch — the director's own sheet, near
            // enough, and the engine's `@page` for it says the same.
            case .avscript: return 54
            case .diagram: return 36
            }
        }
    }

    /// Render a page the engine wrote into a PDF, in memory.
    ///
    /// Asynchronous because the web view has to lay the page out before it can
    /// be asked how long it is, and a PDF made before the pictures have loaded
    /// is a PDF with holes in it.
    static func render(
        fromPageAt source: URL,
        kind: Kind,
        orientation: Orientation? = nil,
        stale: (() -> Bool)? = nil,
        done: @escaping (Result<PDFDocument, Error>) -> Void
    ) {
        let orientation = orientation ?? kind.defaultOrientation
        let configuration = WKWebViewConfiguration()
        let paper = kind.paper(orientation)
        let printable = NSRect(
            x: 0, y: 0,
            width: paper.width - kind.margin * 2,
            height: paper.height - kind.margin * 2
        )
        let web = WKWebView(frame: printable, configuration: configuration)

        // The view has to be in a window, off screen, before it can be printed.
        // A WKWebView with no window prints forever: the operation never
        // decides it has reached the end, and what comes out is a file that
        // grows for as long as you let it.
        let host = NSWindow(
            contentRect: printable,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        host.contentView = web
        host.orderOut(nil)

        let delegate = Renderer(kind: kind, orientation: orientation, done: done)
        delegate.stale = stale
        delegate.host = host
        web.navigationDelegate = delegate
        // Held for the life of the render: a navigation delegate is a weak
        // reference, and the whole thing would be collected mid-page without
        // this.
        renders.append(delegate)
        delegate.web = web
        web.loadFileURL(source, allowingReadAccessTo: source.deletingLastPathComponent())
    }

    private static var renders: [Renderer] = []

    /// **A web view kept alive while the export window is open**, so the
    /// first preview does not pay for starting WebKit's page process (about
    /// 400ms of the first draw, measured 2026-10-15). Nothing is loaded into
    /// it; it only keeps the process up.
    private static var warm: WKWebView?
    static func warmUp() {
        guard warm == nil else { return }
        warm = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        warm?.loadHTMLString("", baseURL: nil)
    }
    static func coolDown() { warm = nil }

    /// Fonts in, every picture loaded, layout forced; answers how many
    /// pictures the page holds. Pictures are not force-decoded: that made
    /// WebKit embed every frame at full size, three times the file. (No
    /// animation frame either: a hidden web view never gets one.)
    fileprivate static let readyScript = """
    await (document.fonts ? document.fonts.ready : 0);
    await Promise.all(Array.from(document.images).map(i => i.complete ? 0
        : new Promise(r => { i.onload = r; i.onerror = r; })));
    void document.body.offsetHeight;
    return document.images.length;
    """

    /// Every row-shaped thing a page can carry, whatever it's called on that
    /// page — a table row, a shot's whole paragraph, a storyboard card.
    /// Cards share a grid row with their neighbours, so this groups anything
    /// sitting at the same top edge into one block: a page break can land
    /// between rows, never through the middle of one.
    /// Where every block on the page begins and ends — and whether it is one
    /// that must not be the last thing on a sheet.
    ///
    /// **A heading is the second kind.** Left at the foot of a page it
    /// announces a scene that then does not begin, which is worse than a
    /// short page; the app's own Document view carries the heading over with
    /// the shot under it, and this is how the printed page does the same.
    /// The third number is 1 for "keep me with the next block".
    ///
    /// Every heading the pages draw is one: a scene's (`.scene-head`, and
    /// `.group-head` on all three pages, not only the Document's), a
    /// section's tinted band (`.section-head`) and a scene's line inside a
    /// day (`.run-head`). The last two were unknown here until 2026-09-20,
    /// so a cut could land right under a section's head — and no CSS could
    /// stop it, because the cutting is done here, not by WebKit.
    ///
    /// **The fourth number is 1 for "start a fresh sheet here".** A page
    /// carrying `.fresh-page` — a shoot day on the Document, a script's
    /// chapter on the Script page — asks for one in CSS, and CSS has never
    /// been read here. So the first block inside every such element opens
    /// a sheet. The element itself is not a block (a chapter is a page
    /// tall; as a block it would be stepped through a sheet at a time).
    private static let blockBoundsScript = """
    (() => {
      const els = Array.from(document.querySelectorAll(
        'tbody tr, .shot, .card, .scene-head, .group-head, .section-head, .run-head, .sc-cols'));
      const heads = ['scene-head', 'group-head', 'section-head', 'run-head', 'sc-cols'];
      const opened = new Set();
      const rows = new Map();
      for (const el of els) {
        const r = el.getBoundingClientRect();
        const key = Math.round(r.top);
        const holds = heads.some((c) => el.classList.contains(c)) ? 1 : 0;
        // The first block inside a fresh-page element opens the sheet —
        // the element's own top edge is above its first block by its
        // head's margin, so the block is what is looked for, not the edge.
        const fresh = el.closest('.fresh-page');
        const starts = fresh && !opened.has(fresh) ? 1 : 0;
        if (fresh) opened.add(fresh);
        // **A Script page's stretch may be cut inside** (2026-10-05): a
        // stretch with its shots beside it is one row, often most of a
        // sheet, and moving it whole left a chapter's title alone on its
        // first page. It is cut the way any document is — between two
        // lines, never through one, and never through a picture — in both
        // columns at once.
        const cuts = [];
        if (el.matches('.sc tbody tr') && !el.classList.contains('sc-cols')) {
          const boxes = [];
          const walk = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
          while (walk.nextNode()) {
            if (!walk.currentNode.textContent.trim()) continue;
            const range = document.createRange();
            range.selectNodeContents(walk.currentNode);
            for (const b of range.getClientRects()) boxes.push([b.top, b.bottom]);
          }
          for (const pic of el.querySelectorAll('.card-pic, img')) {
            const b = pic.getBoundingClientRect();
            boxes.push([b.top, b.bottom]);
          }
          const seen = new Set();
          for (const [top] of boxes) {
            const y = Math.round(top) - 1;
            if (seen.has(y) || y <= r.top + 1) continue;
            seen.add(y);
            if (!boxes.some(([a, b]) => a < y && b > y)) cuts.push(y);
          }
        }
        const existing = rows.get(key);
        if (existing) {
          existing[1] = Math.max(existing[1], r.bottom);
          existing[2] = Math.max(existing[2], holds);
          existing[3] = Math.max(existing[3], starts);
          existing.push(...cuts);
        } else { rows.set(key, [r.top, r.bottom, holds, starts, ...cuts]); }
      }
      return Array.from(rows.values()).sort((a, b) => a[0] - b[0]);
    })()
    """

    struct Block {
        var top: CGFloat
        var bottom: CGFloat
        /// A heading: it goes over to the next sheet rather than sit alone at
        /// the foot of this one.
        var holdsTheNext: Bool
        /// The first thing on a fresh sheet, whatever room is left on this
        /// one — a shoot day, a script's chapter.
        var startsASheet: Bool = false
        /// Where it may be cut without crossing a line of anything — only a
        /// Script page's stretch has any.
        var cuts: [CGFloat] = []
    }

    private static func parseBlocks(_ value: Any?) -> [Block] {
        guard let pairs = value as? [[NSNumber]] else { return [] }
        return pairs.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return Block(
                top: CGFloat(pair[0].doubleValue),
                bottom: CGFloat(pair[1].doubleValue),
                holdsTheNext: pair.count > 2 && pair[2].intValue == 1,
                startsASheet: pair.count > 3 && pair[3].intValue == 1,
                cuts: pair.count > 4 ? pair[4...].map { CGFloat($0.doubleValue) }.sorted() : [])
        }
    }

    /// Where each page should start, so a row never gets cut in two just
    /// because a fixed height happened to end there. A block taller than one
    /// whole page cannot be saved this way — that one still splits, in
    /// page-sized steps, but nothing else does.
    static func pageBreaks(
        blocks: [Block],
        pageHeight: CGFloat
    ) -> [CGFloat] {
        guard pageHeight > 0 else { return [0] }
        var breaks: [CGFloat] = [0]
        var pageStart: CGFloat = 0

        let ordered = blocks.sorted(by: { $0.top < $1.top })
        for (at, block) in ordered.enumerated() {
            // Already covered by an earlier page — nothing to decide here.
            guard block.top >= pageStart else { continue }

            // Asked for a sheet of its own: it opens one, unless it is
            // already the first thing on this one — the very first block
            // of the page is, whatever stands over it.
            if block.startsASheet, block.top > pageStart, at > 0 {
                pageStart = block.top
                breaks.append(pageStart)
            }

            // A heading reaches as far as the block it is holding on to, so
            // "does this fit" is asked about the pair rather than the heading
            // alone. Same rule the app's own sheets are cut by. **Headings
            // chain**: a section's band over a scene's line over its first
            // row is one thing, so the band reaches to the row — or the
            // band would stay behind while the line and the row moved on.
            var reaches = block.bottom
            var held = at
            while ordered[held].holdsTheNext, held + 1 < ordered.count {
                held += 1
                // A block that can be cut is held only as far as its first
                // piece: the heading needs something under it, not all of it.
                let next = ordered[held]
                reaches = max(reaches, next.cuts.first { $0 > next.top } ?? next.bottom)
            }
            // A chain taller than a sheet cannot be kept whole on any sheet
            // — a shot quoting a whole script is one row taller than the
            // page — so the heading asks only not to be the last thing: it
            // and a good slice of what it heads, together.
            if reaches - block.top > pageHeight {
                reaches = min(reaches, block.bottom + pageHeight * 0.3)
            }
            if reaches - pageStart > pageHeight, block.top > pageStart,
               block.bottom - pageStart <= pageHeight {
                pageStart = block.top
                breaks.append(pageStart)
                continue
            }

            // A block that can be cut fills the sheet and goes on over,
            // cut at the lowest place that fits — never moved whole.
            if block.bottom - pageStart > pageHeight, !block.cuts.isEmpty {
                while block.bottom - pageStart > pageHeight {
                    if let cut = block.cuts.last(where: { $0 > pageStart + 1 && $0 - pageStart <= pageHeight }) {
                        pageStart = cut
                    } else if block.top > pageStart, block.bottom - block.top <= pageHeight {
                        pageStart = block.top
                    } else {
                        pageStart += pageHeight
                    }
                    breaks.append(pageStart)
                }
                continue
            }

            if block.bottom - pageStart > pageHeight {
                // Room to spare on this page, and a fresh sheet would hold
                // the whole block — so it moves whole. A block taller than
                // a sheet is not moved: a fresh sheet would not hold it
                // either, and moving it would strand the heading that was
                // just placed over it.
                if block.top > pageStart, block.bottom - block.top <= pageHeight {
                    pageStart = block.top
                    breaks.append(pageStart)
                }
                // Taller than a page on its own: no whole-block move helps,
                // so step through it a page at a time, same as before.
                while block.bottom - pageStart > pageHeight {
                    pageStart += pageHeight
                    breaks.append(pageStart)
                }
            }
        }
        return breaks
    }

    private final class Renderer: NSObject, WKNavigationDelegate {
        let kind: Kind
        let orientation: Orientation
        let done: (Result<PDFDocument, Error>) -> Void
        var web: WKWebView?
        var host: NSWindow?
        /// **The diagram's own paper** (Back to Paper, Batch 2): a plan can
        /// be set on Tabloid or A4 (View › Sheet), and the engine says which
        /// on the page (`data-paper="792x1224"`, points). Letter otherwise.
        var said: NSSize?
        /// The paper this job is cut onto.
        var paper: NSSize { said ?? kind.paper(orientation) }

        init(kind: Kind, orientation: Orientation, done: @escaping (Result<PDFDocument, Error>) -> Void) {
            self.kind = kind
            self.orientation = orientation
            self.done = done
        }

        /// Set by the preview so a draw that has been overtaken stops at the
        /// next step instead of cutting pages nobody will see.
        var stale: (() -> Bool)?
        private var started = Date()
        private var settled = false

        /// Once the page is ready. **A page with no pictures goes on at once;
        /// one with pictures keeps the old 0.4-second settle**, because WebKit
        /// decodes a picture a beat after it has loaded and a sheet cut too
        /// soon comes out with a hole where the frame should be (measured
        /// 2026-10-15 on ZED: a Document page lost a whole frame). The ceiling
        /// also covers a page that never answers. `then` runs exactly once.
        private func whenReady(_ web: WKWebView, ceiling: Double = 0.4, then: @escaping () -> Void) {
            var fired = false
            let go = {
                guard !fired else { return }
                fired = true
                then()
            }
            let began = Date()
            web.callAsyncJavaScript(Printing.readyScript, arguments: [:], in: nil,
                                    in: .page) { result in
                let pictures = (try? result.get() as? Int) ?? 1
                guard pictures > 0 else { return go() }
                let left = ceiling - Date().timeIntervalSince(began)
                DispatchQueue.main.asyncAfter(deadline: .now() + max(0, left)) { go() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + ceiling + 0.2) { go() }
        }

        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
            if Launch.checking {
                FileHandle.standardError.write(Data(String(
                    format: "stage load: %.0fms\n", Date().timeIntervalSince(started) * 1000).utf8))
            }
            whenReady(web) { [self] in
                if stale?() == true { return finish(.failure(CancelledDraw())) }
                guard kind == .diagram else { return go(web) }
                web.evaluateJavaScript("document.body.dataset.paper || ''") { value, _ in
                    let parts = ((value as? String) ?? "").split(separator: "x").compactMap { Double($0) }
                    let want = parts.count == 2 && parts[0] > 100 && parts[1] > 100 ? NSSize(width: parts[0], height: parts[1]) : nil
                    guard let want, want != self.kind.paper(self.orientation) else { return self.go(web) }
                    // Laid out again at that paper's width before it is cut.
                    self.said = want
                    let m = self.kind.margin
                    let printable = NSRect(x: 0, y: 0, width: want.width - 2 * m, height: want.height - 2 * m)
                    self.host?.setContentSize(printable.size)
                    web.frame = printable
                    self.whenReady(web, ceiling: 0.3) { self.go(web) }
                }
            }
        }

        /// How tall the page is, then where its rows are, then the cut.
        private func go(_ web: WKWebView) {
            web.evaluateJavaScript("document.body.scrollHeight") { value, _ in
                let tall = (value as? CGFloat) ?? 0
                self.measure(web, contentHeight: max(tall, 1))
            }
        }

        /// Ask the page where its rows are before cutting it into sheets.
        private func measure(_ web: WKWebView, contentHeight: CGFloat) {
            web.evaluateJavaScript(Printing.blockBoundsScript) { [self] result, _ in
                let blocks = Printing.parseBlocks(result)
                self.slice(web, contentHeight: contentHeight, blocks: blocks)
            }
        }

        /// Cut the page into sheets and ask WebKit for each one.
        ///
        /// Deliberately not `NSPrintOperation`. Printing a web view that way
        /// never decides it has reached the end of the document — it produced
        /// four hundred thousand pages of a four-page list, and kept going for
        /// as long as it was allowed to. Asking for one rectangle at a time is
        /// slower to write and cannot run away: the number of pages is worked
        /// out here, from a height that has already been measured — and now
        /// from where the rows actually are, so a break never lands mid-row.
        private func slice(_ web: WKWebView, contentHeight: CGFloat, blocks: [Printing.Block]) {
            let width = paper.width - kind.margin * 2
            let height = paper.height - kind.margin * 2
            let breaks = Printing.pageBreaks(blocks: blocks, pageHeight: height)
            if Launch.checking {
                FileHandle.standardError.write(Data(String(
                    format: "stage ready+measure done at %.0fms\n", Date().timeIntervalSince(started) * 1000).utf8))
            }
            // Under a checking run, say where the cuts fell and what they
            // were cut between — the only way to see why a sheet came out
            // short without printing it and looking.
            if Launch.checking {
                let told = blocks.map { b in
                    String(format: "%.0f-%.0f%@", b.top, b.bottom, b.holdsTheNext ? "h" : "")
                }.joined(separator: " ")
                let cuts = breaks.map { String(format: "%.0f", $0) }.joined(separator: " ")
                FileHandle.standardError.write(Data(
                    "cuts \(kind.rawValue): page \(Int(height))  blocks \(told)  breaks \(cuts)\n".utf8))
            }

            // One sheet at a time: asking for them all at once measured
            // *slower* on a long, picture-heavy film (ZED, 2026-10-15).
            var spans: [CGRect] = []
            for index in 0..<breaks.count {
                let start = breaks[index]
                let end = index + 1 < breaks.count ? breaks[index + 1] : contentHeight
                guard end > start else { continue }
                spans.append(CGRect(x: 0, y: start, width: width, height: min(height, end - start)))
            }
            var pages: [Data] = []
            let cutting = Date()
            func next(_ index: Int) {
                guard index < spans.count else {
                    if Launch.checking {
                        FileHandle.standardError.write(Data(String(
                            format: "stage cut: %.0fms for %d sheets\n",
                            Date().timeIntervalSince(cutting) * 1000, spans.count).utf8))
                    }
                    write(pages)
                    return
                }
                let configuration = WKPDFConfiguration()
                configuration.rect = spans[index]
                web.createPDF(configuration: configuration) { result in
                    if case .success(let data) = result { pages.append(data) }
                    next(index + 1)
                }
            }
            next(0)
        }

        /// One document out of the sheets, on the paper the kind asks for.
        private func write(_ sheets: [Data]) {
            let paper = self.paper
            let out = PDFDocument()
            for data in sheets {
                guard let piece = PDFDocument(data: data), let page = piece.page(at: 0) else { continue }
                // Each sheet comes back the size of the slice; it is placed on
                // a full page with the margins around it, so what comes out is
                // real US Letter rather than a picture of part of one.
                let stamped = Stamped(source: page, from: piece, paper: paper, margin: kind.margin)
                out.insert(stamped, at: out.pageCount)
            }
            if out.pageCount == 0 {
                finish(.failure(Failure.nothingToPrint))
                return
            }
            finish(.success(out))
        }

        struct CancelledDraw: LocalizedError {
            var errorDescription: String? { "draw cancelled" }
        }

        enum Failure: LocalizedError {
            case nothingToPrint

            var errorDescription: String? {
                switch self {
                case .nothingToPrint: return "there was nothing on the page"
                }
            }
        }

        func webView(_ web: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(.failure(error))
        }

        func webView(
            _ web: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            finish(.failure(error))
        }

        private func finish(_ result: Result<PDFDocument, Error>) {
            done(result)
            host?.contentView = nil
            host = nil
            web = nil
            Printing.renders.removeAll { $0 === self }
        }
    }
}

/// One slice of the page, sitting on a full sheet of paper with its margins.
///
/// WebKit hands back a PDF the size of the rectangle asked for. This puts that
/// rectangle where it belongs on US Letter, so the result is a page somebody can
/// print rather than a crop of one.
private final class Stamped: PDFPage {
    private let source: PDFPage
    /// Held on purpose: a `PDFPage` cannot be drawn once the document it came
    /// from has been released, and the slice's document would otherwise go the
    /// moment this initialiser returns.
    private let sourceDocument: PDFDocument
    private let paper: NSSize
    private let margin: CGFloat

    init(source: PDFPage, from document: PDFDocument, paper: NSSize, margin: CGFloat) {
        self.source = source
        self.sourceDocument = document
        self.paper = paper
        self.margin = margin
        super.init()
        setBounds(CGRect(origin: .zero, size: paper), for: .mediaBox)
    }

    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        context.saveGState()
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: paper))
        // The slice is drawn from the top down, which is the way a page is
        // read; PDF counts from the bottom, hence the offset.
        let size = source.bounds(for: .mediaBox).size
        context.translateBy(x: margin, y: paper.height - margin - size.height)
        source.draw(with: .mediaBox, to: context)
        context.restoreGState()
    }
}

/// **A page baked into a picture.** His ask, 2026-09-16: a *flat* PDF — one
/// nobody can select, copy or move a word of — beside the editable one.
///
/// The page is drawn once into a bitmap at 200 dpi (crisp on paper, a fifth
/// of the bytes of 300), the bitmap becomes a JPEG, and the JPEG is drawn
/// back onto a fresh page of the same size. **A JPEG-sourced `CGImage` is
/// passed through by the PDF writer as it is**, so the file holds one
/// compressed picture per page rather than a re-encoded one — that is why it
/// goes through `CGImageSource` instead of straight from the bitmap.
///
/// A rendering step, not a document one: the engine draws the same page
/// either way, and this only decides what kind of file it ends up in.
final class Rasterised: PDFPage {
    private let picture: CGImage
    private let size: CGSize

    init(picture: CGImage, size: CGSize) {
        self.picture = picture
        self.size = size
        super.init()
        setBounds(CGRect(origin: .zero, size: size), for: .mediaBox)
    }

    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        context.draw(picture, in: CGRect(origin: .zero, size: size))
    }

    /// One page, as a JPEG-backed image at `dpi`. Nil when the page will not
    /// draw — the caller keeps the original page rather than losing it.
    static func picture(of page: PDFPage, dpi: CGFloat) -> (CGImage, CGSize)? {
        let bounds = page.bounds(for: .mediaBox)
        // A page turned on its side is drawn turned; the picture takes the
        // shape the reader sees.
        let turned = page.rotation % 180 != 0
        let shown = turned ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
        let scale = dpi / 72
        let width = Int((shown.width * scale).rounded())
        let height = Int((shown.height * scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        // Drawn by PDFKit itself, rotation and all, so a page that is a
        // footered or sliced one comes out exactly as it prints.
        context.concatenate(page.transform(for: .mediaBox))
        page.draw(with: .mediaBox, to: context)
        guard let bitmap = context.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: bitmap)
        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]),
              let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let picture = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return (picture, shown)
    }
}

extension Printing {
    /// How many characters of text a written PDF still carries — nought for a
    /// flat one, which is the whole claim a flat file makes. For the checks.
    static func wordCount(inFileAt url: URL) -> Int {
        PDFDocument(url: url)?.string?
            .trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0
    }

    /// Every page of `document` baked into a picture, in the same order and
    /// the same size — see `Rasterised`. A page that will not draw is kept
    /// as it was rather than dropped.
    static func flattened(_ document: PDFDocument, dpi: CGFloat = 200) -> PDFDocument {
        let out = PDFDocument()
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            if let (picture, size) = Rasterised.picture(of: page, dpi: dpi) {
                out.insert(Rasterised(picture: picture, size: size), at: out.pageCount)
            } else {
                out.insert(page, at: out.pageCount)
            }
        }
        return out
    }
}

/// A finished page with a running footer stamped on — when it was made, and
/// where it sits in the whole file. Drawn once, over the *combined* document,
/// because only then is the real page count known: Table might be two pages,
/// Storyboard three, Script five, and "Page 4 of 10" only means something
/// once they are all one file.
final class Footered: PDFPage {
    private let source: PDFPage
    private let sourceDocument: PDFDocument
    private let pageNumber: Int
    private let totalPages: Int
    private let stampedAt: String

    init(source: PDFPage, from document: PDFDocument, pageNumber: Int, totalPages: Int, stampedAt: String) {
        self.source = source
        self.sourceDocument = document
        self.pageNumber = pageNumber
        self.totalPages = totalPages
        self.stampedAt = stampedAt
        super.init()
        setBounds(source.bounds(for: .mediaBox), for: .mediaBox)
    }

    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        source.draw(with: box, to: context)

        let size = bounds(for: .mediaBox).size
        let margin: CGFloat = 24
        let font = NSFont.systemFont(ofSize: 8)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.darkGray]

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

        let dateString = NSAttributedString(string: stampedAt, attributes: attrs)
        dateString.draw(at: CGPoint(x: margin, y: margin - font.descender + 2))

        let pageString = NSAttributedString(string: "Page \(pageNumber) of \(totalPages)", attributes: attrs)
        let pageSize = pageString.size()
        pageString.draw(at: CGPoint(x: size.width - margin - pageSize.width, y: margin - font.descender + 2))
    }
}

extension Printing {
    enum CombineError: LocalizedError {
        case nothingDrawn
        var errorDescription: String? {
            "nothing was checked to include"
        }
    }

    private static let exportedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter
    }()

    /// **What one view looks like on paper** — its sheet, its text size, how
    /// big its pictures are drawn.
    ///
    /// One of these per view, not one for the export, because the three views
    /// have never wanted the same page: Document is a portrait document and
    /// the other two are landscape tables. His reorganisation, 2026-09-02.
    struct Look: Equatable {
        var orientation: Orientation
        var scale: Double = 1.0
        var frames: FrameSize = .medium

        /// What a view asks for when nobody has said otherwise — the paper
        /// `Kind` has always named, and the sizes the box has always started
        /// at.
        static func standard(for section: String, frames: FrameSize = .medium) -> Look {
            Look(orientation: (Kind(rawValue: section) ?? .table).defaultOrientation,
                 scale: 1.0, frames: frames)
        }
    }

    /// One page of a combined export: which view, narrowed and dialled how,
    /// and **on which paper**.
    ///
    /// The paper is per job because the app has always known the three views
    /// want different sheets — `Kind.defaultOrientation` says so — while this
    /// function took a single orientation for all of them. So a film exported
    /// as Table + Document could only ever be right about one: whichever way
    /// the dial was set, the other page came out sideways. His reorganisation
    /// of 2026-09-02 made the split visible in the box; this is where it
    /// becomes true in the file.
    struct Job {
        let section: String
        let scope: Engine.ExportScope
        let orientation: Orientation

        init(section: String, scope: Engine.ExportScope, orientation: Orientation) {
            self.section = section
            // **The document page is never scaled from the exporter.** Its
            // type is set on the page itself now — nine classes, each with its
            // own size — and a second dial over the top of that is a second
            // owner of the same number.
            //
            // The dial was taken out of the box on 2026-09-02 and the *stored*
            // value went on being applied, which is a worse thing than leaving
            // it in: his own film had 50% remembered from before, so the
            // export came out at half what the document view drew and nothing
            // on screen said why. His report, 2026-09-03: *"a discrepancy
            // between the layout in the editor and the preview of what the
            // first page will look like."* Pinned here rather than at the
            // three places a job is built, so no path can leak.
            var narrowed = scope
            if section == Kind.document.rawValue || section == Kind.avscript.rawValue {
                narrowed.scale = 1.0
            }
            self.scope = narrowed
            self.orientation = orientation
        }
    }

    /// Every job's pages, one after another, footer-stamped as one file — the
    /// same combining the export box does for a scene or the whole film,
    /// pulled out here so a folder of per-day PDFs (Ref 377's follow-up,
    /// 2026-08-27) can be built the same way instead of the plain, unstamped
    /// single page it used to write.
    static func combinedDocument(
        _ jobs: [Job],
        engine: Engine,
        done: @escaping (Result<PDFDocument, Error>) -> Void
    ) {
        let out = PDFDocument()
        var remaining = jobs

        func finish() {
            guard out.pageCount > 0 else {
                done(.failure(CombineError.nothingDrawn))
                return
            }
            let stampedAt = exportedAtFormatter.string(from: Date())
            let final = PDFDocument()
            for i in 0..<out.pageCount {
                guard let page = out.page(at: i) else { continue }
                let footered = Footered(
                    source: page, from: out,
                    pageNumber: i + 1, totalPages: out.pageCount,
                    stampedAt: stampedAt
                )
                final.insert(footered, at: final.pageCount)
            }
            done(.success(final))
        }

        func next() {
            guard let job = remaining.first else {
                finish()
                return
            }
            remaining.removeFirst()
            Filmstrip.prepare(engine: engine) { draw(job) }
        }

        func draw(_ job: Job) {
            let kind = Kind(rawValue: job.section) ?? .table
            let page = FileManager.default.temporaryDirectory
                .appendingPathComponent("shotlister-export-\(UUID().uuidString).html")
            let wrote = Date()
            guard engine.printPage(job.section, to: page.path, scope: job.scope, stripsReady: true) != nil else {
                next()
                return
            }
            let drew = Date()
            render(fromPageAt: page, kind: kind, orientation: job.orientation) { result in
                // Where the time goes, under a checking run — the engine's
                // half runs on the main thread and is what a click waits on.
                if Launch.checking {
                    let bytes = (try? FileManager.default.attributesOfItem(atPath: page.path)[.size] as? Int) ?? 0
                    FileHandle.standardError.write(Data((String(
                        format: "timing %@: engine %.0fms  render %.0fms  page %.1f MB\n", job.section,
                        drew.timeIntervalSince(wrote) * 1000,
                        Date().timeIntervalSince(drew) * 1000,
                        Double(bytes) / 1e6)).utf8))
                }
                try? FileManager.default.removeItem(at: page)
                switch result {
                case .success(let doc):
                    for i in 0..<doc.pageCount {
                        if let sourcePage = doc.page(at: i) {
                            out.insert(sourcePage, at: out.pageCount)
                        }
                    }
                    next()
                case .failure(let error):
                    done(.failure(error))
                }
            }
        }
        next()
    }
}
