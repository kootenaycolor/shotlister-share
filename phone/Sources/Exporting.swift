import SwiftUI
import WebKit
import PDFKit
import UIKit
import os

/// **Getting a shot list out of the phone** — every export the Mac's window can
/// do, the phone can do. His instruction, 2026-09-16: *"all the functionality
/// of Mac app's export features to be available on iOS. Right now, that page
/// is old and legacy."*
///
/// That reverses his 2026-08-31 ruling that the phone needed no spreadsheet.
/// The newer word wins: the workbook is here now, laid out for Sheets or for
/// Excel exactly as the Mac offers it.
///
/// **Almost none of this is new work, and that is the point.** The engine
/// writes every page — `print table|storyboard|document <path> key=value…` —
/// and the whole workbook — `xlsx <path> key=value…` — and it takes the same
/// narrowing on both, so a day's pages and a day's workbook are about exactly
/// the same shots. The Mac calls those two doors; the phone calls the same
/// two. `Scope` below is the Mac's `Engine.ExportScope`, word for word, so
/// the two apps cannot ask the engine two different questions.
///
/// What is left for the shell is turning the engine's page into a PDF, and on
/// iOS that is **WebKit's own print formatter**: the page-break rules already
/// live in WebKit, so the renderer is forty lines rather than the Mac's four
/// hundred, and both apps still print the same page.
enum Exporting {
    /// What a PDF can carry. Table, Storyboard and Document are the three
    /// views the engine draws; Script is the real imported pages, sliced
    /// with PDFKit out of the file he gave the app.
    enum Section: String, CaseIterable, Identifiable {
        case table, storyboard, document, script
        var id: String { rawValue }

        var title: String {
            switch self {
            case .table: return "Table"
            case .storyboard: return "Storyboard"
            case .document: return "Document"
            case .script: return "Script"
            }
        }

        /// The shape each one reads best in, left alone — a table wants the
        /// room a landscape page gives its columns, a document reads as a
        /// document.
        var wants: Orientation { self == .document ? .portrait : .landscape }

        /// The Mac's own margins, per view — `Printing.Kind.margin`. The
        /// Document page is one inch because that is what the app's page has.
        var margin: CGFloat {
            switch self {
            case .document: return 72
            case .table: return 32
            case .storyboard, .script: return 36
            }
        }
    }

    /// One file, or a folder's worth — one PDF (and workbook) per shoot day.
    enum Delivery: String, CaseIterable, Identifiable {
        case wholeFilm, perDay
        var id: String { rawValue }
    }

    enum Orientation: String, CaseIterable, Identifiable {
        case portrait, landscape
        var id: String { rawValue }
        var title: String { self == .portrait ? "Portrait" : "Landscape" }

        /// US Letter, in points, either way round — the Mac's own paper.
        var paper: CGSize {
            self == .portrait ? CGSize(width: 612, height: 792)
                              : CGSize(width: 792, height: 612)
        }
    }

    /// How much room a picture gets — the table's picture column, and how
    /// many storyboard cards stand across a row. The engine holds the
    /// numbers; this only carries the word.
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

    /// Which program a workbook is laid out for. **Same `.xlsx` either way**
    /// — the Mac's `FrameStyle`, and the stored values are its: `cells` and
    /// `file` are in his films already.
    enum FrameStyle: String, CaseIterable, Identifiable {
        case forGoogleSheets = "cells"
        case forExcel = "file"
        var id: String { rawValue }

        var label: String {
            switch self {
            case .forGoogleSheets: return "Google Sheets"
            case .forExcel: return "Excel"
            }
        }

        /// The one line that earns its place beside the name — the Mac's
        /// exception under the language law, kept here for the same reason:
        /// nothing in either name warns that one layout draws nothing outside
        /// Sheets. Do not tidy it away.
        var difference: String {
            switch self {
            case .forGoogleSheets:
                return "Frames in cells"
            case .forExcel:
                return "Frames over rows"
            }
        }
    }

    /// **What one view looks like on paper** — its sheet, its text size, how
    /// big its pictures are drawn. One per view, because the three have never
    /// wanted the same page.
    struct Look: Equatable {
        var orientation: Orientation
        var scale: Double = 1.0
        var frames: FrameSize = .medium

        static func standard(for section: Section) -> Look {
            Look(orientation: section.wants)
        }
    }

    /// One shoot day, or everything not on a day yet.
    enum Day: Equatable {
        case on(String)
        case unscheduled

        var argument: String {
            switch self {
            case .on(let id): return id
            case .unscheduled: return "unscheduled"
            }
        }
    }

    /// The id the day picker uses for "everything not on a day yet" — the
    /// same word the engine reads.
    static let unscheduledDayId = "unscheduled"

    /// What one view is asked for: the narrowing, and that view's own dials.
    /// The Mac's `Engine.ExportScope`, so the options go over the wire the
    /// same way from both apps.
    struct Scope {
        /// Exactly these scenes, whatever is searched or filtered on screen.
        var scenes: [String] = []
        /// Mutually exclusive with `scenes` — the engine refuses both.
        var day: Day? = nil
        /// Overrides the columns on screen. Nil keeps them.
        var columns: [String]? = nil
        var scale: Double? = nil
        var frames: String? = nil
        /// His own say over how wide each column of the table prints — a
        /// multiplier on the weight the page already gives it.
        var widths: [String: Double] = [:]
        /// What the Document page writes in its corner — the real order
        /// (`ExportChoice.caption`), the Mac's `order=`.
        var order: String? = nil
        /// The export's Order, Filter and Days (`ExportChoice.narrowing`).
        var narrowing: [String] = []
        /// **Auto's column shares, exactly** (the Mac's `shares=`), and
        /// whether its sheet cut no word (`fitted=1`).
        var shares: [String: Double] = [:]
        var fitted = false
        /// More words, in the Mac's `extra` place — Auto's Size and paper
        /// (`AutoAsk.words`).
        var extra: [String] = []

        var options: [String] {
            var out: [String] = []
            if !scenes.isEmpty { out.append("scenes=" + scenes.joined(separator: ",")) }
            if let day { out.append("day=" + day.argument) }
            if let columns { out.append("columns=" + columns.joined(separator: ",")) }
            if let scale { out.append(String(format: "scale=%.2f", scale)) }
            if let frames { out.append("frames=" + frames) }
            if let order, !order.isEmpty { out.append("order=" + order) }
            out.append(contentsOf: extra)
            out.append(contentsOf: narrowing)
            if !shares.isEmpty {
                if fitted { out.append("fitted=1") }
                out.append("shares=" + shares.sorted { $0.key < $1.key }
                    .map { String(format: "%@:%.4f", $0.key, $0.value) }
                    .joined(separator: ","))
            }
            // Only the ones he has actually moved.
            let moved = widths.filter { abs($0.value - 1) > 0.01 }
            if !moved.isEmpty {
                out.append("widths=" + moved.sorted { $0.key < $1.key }
                    .map { String(format: "%@:%.3f", $0.key, $0.value) }
                    .joined(separator: ","))
            }
            return out
        }
    }

    /// One page of a combined export: which view, narrowed and dialled how,
    /// on which paper.
    struct Job {
        let section: Section
        let scope: Scope
        let orientation: Orientation
    }

    enum Trouble: LocalizedError {
        case engine(String)
        case page
        case nothingDrawn
        case couldNotWrite

        var errorDescription: String? {
            switch self {
            case .engine(let said): return said
            case .page: return "That page couldn't be made into a PDF."
            case .nothingDrawn: return "Nothing is ticked to include."
            case .couldNotWrite: return "The file could not be written."
            }
        }
    }

    // ------------------------------------------------------- the engine's doors

    /// What each column of the printed table is worth, before he adjusts
    /// anything — asked of the engine so the weights live in one place.
    struct ColumnWeight: Decodable {
        let field: String
        let weight: Double
    }

    /// Write the page a PDF is made from. Nil, with the engine's own words,
    /// when it refuses.
    @MainActor
    static func printPage(_ section: Section, to path: URL, scope: Scope,
                          engine: Engine) -> String? {
        let reply = engine.raw(["print", section.rawValue, path.path] + scope.options)
        if let refusal = Session.refusal(in: reply) { return refusal }
        guard String(data: reply, encoding: .utf8)?.contains("\"path\"") == true else {
            return "The engine could not draw the \(section.title.lowercased()) page."
        }
        return nil
    }

    /// The workbook. **The narrowing and the columns, and nothing else** —
    /// `xlsx` has never read a text size, a frame size or a width.
    ///
    /// Laid out for Sheets, the frame goes in as an address the sheet fetches
    /// from the relay. No relay behind this film means no address, and then
    /// the frames are carried in the file whatever was asked for.
    @MainActor
    static func exportExcel(to path: URL, scope: Scope, frames: FrameStyle,
                            engine: Engine, folder: URL) -> String? {
        var options = scope.options
        _ = Relay.device
        if frames == .forGoogleSheets, let pictures = RelayCarrier.picturesAt(folder) {
            options.append("pictures=\(pictures)")
        }
        let reply = engine.raw(["xlsx", path.path] + options)
        if let refusal = Session.refusal(in: reply) { return refusal }
        guard String(data: reply, encoding: .utf8)?.contains("\"path\"") == true else {
            return "The engine could not write the spreadsheet."
        }
        return nil
    }

    /// **Auto, for the printed table** — the Mac's `Engine.TableLayout`:
    /// which way round, the text and picture size, every column's share.
    struct TableLayout: Decodable, Equatable {
        let orientation: String
        let scale: Double
        let frames: String
        let picture: Double
        let pages: Int
        let cut: Int
        let shares: [String: Double]
        let factors: [String: Double]

        var look: Look {
            Look(orientation: Orientation(rawValue: orientation) ?? .landscape, scale: scale,
                 frames: FrameSize(rawValue: frames) ?? .medium)
        }
    }

    /// Measure here (a pass over the rows), then decide **off the main
    /// thread** — the Mac's two halves, so the screen never waits on it.
    @MainActor
    static func tableLayout(scope: Scope, engine: Engine) async -> TableLayout? {
        struct Ticket: Decodable { let ticket: UInt64 }
        guard let ticket = try? JSONDecoder().decode(
            Ticket.self, from: engine.raw(["tablelayout"] + scope.options + ["defer=1"])).ticket
        else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> TableLayout? in
            guard let reply = sl_solve_layout(ticket) else { return nil }
            defer { sl_free(reply) }
            return try? JSONDecoder().decode(TableLayout.self, from: Data(String(cString: reply).utf8))
        }.value
    }

    /// The Table's filter and sort, and every shoot day (`exportinfo`).
    @MainActor
    static func info(engine: Engine) -> ExportInfo {
        (try? JSONDecoder().decode(ExportInfo.self, from: engine.raw("exportinfo"))) ?? .empty
    }

    @MainActor
    static func columnWeights(scope: Scope, engine: Engine) -> [ColumnWeight] {
        let reply = engine.raw(["colwidths"] + scope.options)
        return (try? JSONDecoder().decode([ColumnWeight].self, from: reply)) ?? []
    }

    /// The kept script: the real PDF of the latest draft, and where each
    /// scene starts in it. Nil when the film keeps no pages.
    struct KeptScript {
        let document: PDFDocument
        let pages: Int
        let starts: [(scene: String, page: Int)]

        /// Every page of one scene, in the file's own numbering.
        func pageRange(for sceneNumber: String) -> ClosedRange<Int>? {
            let ordered = starts.sorted { $0.page < $1.page }
            guard let index = ordered.firstIndex(where: { $0.scene == sceneNumber }) else { return nil }
            let start = ordered[index].page
            let end = index + 1 < ordered.count ? ordered[index + 1].page - 1 : pages
            return start...max(start, end)
        }

        /// The whole draft for the whole film; a scene's own pages for a
        /// scene — in script order, so a scattered pick reads front to back.
        func sliced(for sceneNumbers: [String]) -> PDFDocument? {
            if sceneNumbers.isEmpty { return document }
            let ordered = sceneNumbers.sorted {
                (pageRange(for: $0)?.lowerBound ?? 0) < (pageRange(for: $1)?.lowerBound ?? 0)
            }
            let out = PDFDocument()
            for scene in ordered {
                guard let range = pageRange(for: scene) else { continue }
                for pageNumber in range {
                    let index = pageNumber - 1
                    guard index >= 0, index < document.pageCount,
                          let page = document.page(at: index) else { continue }
                    out.insert(page, at: out.pageCount)
                }
            }
            return out.pageCount > 0 ? out : nil
        }
    }

    @MainActor
    static func keptScript(engine: Engine) -> KeptScript? {
        struct Revisions: Decodable { var revisions: [Revision] }
        struct Revision: Decodable { var id: String; var latest: Bool }
        struct Bytes: Decodable { var data: String }
        struct Pages: Decodable { var pages: Int; var scenes: [Extent] }
        struct Extent: Decodable { var label: String; var startsOnPage: Int }

        guard let list = try? JSONDecoder().decode(Revisions.self, from: engine.raw("revisions")),
              let latest = list.revisions.first(where: \.latest),
              let bytes = try? JSONDecoder().decode(Bytes.self, from: engine.raw("scriptpdf", latest.id)),
              !bytes.data.isEmpty,
              let data = Data(base64Encoded: bytes.data),
              let document = PDFDocument(data: data),
              let laid = try? JSONDecoder().decode(Pages.self, from: engine.raw("scriptpages", latest.id))
        else { return nil }
        return KeptScript(document: document, pages: laid.pages,
                          starts: laid.scenes.map { ($0.label, $0.startsOnPage) })
    }

    // ------------------------------------------------------------ the pages

    /// One view's pages, drawn by the engine and printed by WebKit.
    /// **Where the time goes**, said out loud — `log stream --predicate
    /// 'subsystem == "shotlister"'` on the simulator. A guess about which
    /// half is slow is worth nothing; Ref 1046 was forty seconds of guessing.
    static let log = Logger(subsystem: "shotlister", category: "export")

    @MainActor
    static func render(_ job: Job, engine: Engine, folder: URL, ratio: Double) async throws -> PDFDocument {
        let html = FileManager.default.temporaryDirectory
            .appending(path: "shotlister-page-\(UUID().uuidString).html")
        defer { try? FileManager.default.removeItem(at: html) }
        // Every printed page comes through here, which is why a clip's
        // four-moment strip is made here and nowhere else — Ref 530. Since
        // Ref 1046 the film has usually made them already, on opening; this
        // is the safety net, and it waits rather than freezes.
        let began = Date()
        await Filmstrip.ensure(engine: engine, folder: folder, ratio: ratio)
        let stripped = Date()
        if let refusal = printPage(job.section, to: html, scope: job.scope, engine: engine) {
            throw Trouble.engine(refusal)
        }
        let wrote = Date()
        let bytes = (try? FileManager.default.attributesOfItem(atPath: html.path)[.size] as? Int) ?? 0
        guard let data = await Pages.pdf(of: html, orientation: job.orientation,
                                         margin: job.section.margin),
              let doc = PDFDocument(data: data), doc.pageCount > 0 else {
            throw Trouble.page
        }
        log.notice("\(job.section.rawValue): strips \(Int(stripped.timeIntervalSince(began) * 1000)) ms, engine \(Int(wrote.timeIntervalSince(stripped) * 1000)) ms, page \(bytes / 1024) KB, print \(Int(Date().timeIntervalSince(wrote) * 1000)) ms, \(doc.pageCount) pages")
        return doc
    }

    /// Every job's pages in turn, then the script's, footer-stamped as one
    /// document. **The same document the preview shows and the export
    /// writes** — one path, so what he looks at cannot differ from what he
    /// gets.
    @MainActor
    static func combined(_ jobs: [Job], script: PDFDocument?,
                         engine: Engine, folder: URL, ratio: Double) async throws -> PDFDocument {
        let out = PDFDocument()
        for job in jobs {
            let doc = try await render(job, engine: engine, folder: folder, ratio: ratio)
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i) { out.insert(page, at: out.pageCount) }
            }
        }
        if let script {
            for i in 0..<script.pageCount {
                if let page = script.page(at: i) { out.insert(page, at: out.pageCount) }
            }
        }
        guard out.pageCount > 0 else { throw Trouble.nothingDrawn }
        // Stamped once, over the combined document — only now is the real
        // page count known. "Page 4 of 10" means nothing until they are all
        // one file.
        let stampedAt = exportedAt.string(from: Date())
        let final = PDFDocument()
        for i in 0..<out.pageCount {
            guard let page = out.page(at: i) else { continue }
            final.insert(Footered(source: page, pageNumber: i + 1, totalPages: out.pageCount,
                                  stampedAt: stampedAt), at: final.pageCount)
        }
        return final
    }

    /// "Aug 24, 2026 at 8:40 AM" — when the file was made, on every page.
    private static let exportedAt: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter
    }()

    /// A fresh folder under the film's name, so what the share sheet shows is
    /// the film's, not a UUID's. **Slashes and colons are folders and drive
    /// letters in a filename**; they become dashes.
    static func scratch(named name: String) -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "shotlister-export-\(UUID().uuidString)")
            .appending(path: safe(name))
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func safe(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    /// `Day 3 – Fri 12 Sep` — the label the board shows, plus its date.
    static func dayFileName(_ day: Engine.Day) -> String {
        var name = day.label
        if !day.date.isEmpty { name += " – \(day.date)" }
        return safe(name)
    }
}

// ------------------------------------------------------------------ the paper

/// A page the engine wrote, printed.
@MainActor
enum Pages {
    /// **Held for the length of the render.** A `WKWebView` with nothing
    /// holding it is collected mid-page, and what comes back is an empty PDF.
    private static var printing: [WKWebView] = []

    static func pdf(of html: URL, orientation: Exporting.Orientation, margin: CGFloat) async -> Data? {
        let paper = CGRect(origin: .zero, size: orientation.paper)
        let web = WKWebView(frame: paper)
        printing.append(web)
        defer { printing.removeAll { $0 === web } }

        // **On screen, behind everything.** An off-screen web view on iOS is
        // allowed to skip work — including decoding the pictures the page
        // carries as data URIs — and a page printed before they decode is a
        // page with holes in it. So it goes in the window and is covered by
        // the app: **at the back**, not on top, where it showed through the
        // sheet's blur as a ghost of the page.
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first {
            web.alpha = 0.01
            web.isUserInteractionEnabled = false
            window.insertSubview(web, at: 0)
        }
        defer { web.removeFromSuperview() }

        let watcher = Loaded()
        web.navigationDelegate = watcher
        web.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
        let began = Date()
        guard await watcher.wait() else { return nil }
        Exporting.log.notice("load: \(Int(Date().timeIntervalSince(began) * 1000)) ms")
        // The load finishing is not the pictures being drawn. A page of
        // storyboard frames is a megabyte of data URIs, and printing the
        // instant the navigation ends gives grey rectangles.
        try? await Task.sleep(for: .milliseconds(600))

        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(web.viewPrintFormatter(), startingAtPageAt: 0)
        renderer.setValue(paper, forKey: "paperRect")
        renderer.setValue(paper.insetBy(dx: margin, dy: margin), forKey: "printableRect")

        let out = NSMutableData()
        UIGraphicsBeginPDFContextToData(out, paper, nil)
        let counted = Date()
        let pages = renderer.numberOfPages
        Exporting.log.notice("paginate: \(Int(Date().timeIntervalSince(counted) * 1000)) ms")
        guard pages > 0 else {
            UIGraphicsEndPDFContext()
            return nil
        }
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: pages))
        for page in 0..<pages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return out as Data
    }

    /// Waiting for the page to be laid out, as a value rather than a callback.
    private final class Loaded: NSObject, WKNavigationDelegate {
        private var waiting: CheckedContinuation<Bool, Never>?
        private var answered = false

        func wait() async -> Bool {
            await withCheckedContinuation { continuation in
                waiting = continuation
                // A page that never finishes must not hang the app for ever.
                DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                    self?.answer(false)
                }
            }
        }

        private func answer(_ how: Bool) {
            guard !answered else { return }
            answered = true
            waiting?.resume(returning: how)
            waiting = nil
        }

        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) { answer(true) }
        func webView(_ web: WKWebView, didFail navigation: WKNavigation!,
                     withError error: Error) { answer(false) }
        func webView(_ web: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) { answer(false) }
    }
}

/// **A page baked into a picture** — the Mac's `Rasterised`, in UIKit. His
/// ask, 2026-09-16: a *flat* PDF nobody can select, copy or move a word of,
/// beside the editable one. Drawn once at 200 dpi, made a JPEG, and the JPEG
/// drawn back onto a page of the same size; a JPEG-sourced `CGImage` is
/// passed through by the PDF writer as it is, so the file holds one
/// compressed picture per page.
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

    static func picture(of page: PDFPage, dpi: CGFloat) -> (CGImage, CGSize)? {
        let bounds = page.bounds(for: .mediaBox)
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
        context.concatenate(page.transform(for: .mediaBox))
        page.draw(with: .mediaBox, to: context)
        guard let bitmap = context.makeImage(),
              let jpeg = UIImage(cgImage: bitmap).jpegData(compressionQuality: 0.85),
              let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let picture = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return (picture, shown)
    }
}

extension Exporting {
    /// Every page of `document` baked into a picture, same order, same size.
    /// A page that will not draw is kept as it was rather than dropped.
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

/// A page with the line along its foot: when the file was made, and which
/// page of how many. The Mac's `Footered`, in UIKit.
final class Footered: PDFPage {
    private let source: PDFPage
    private let pageNumber: Int
    private let totalPages: Int
    private let stampedAt: String

    init(source: PDFPage, pageNumber: Int, totalPages: Int, stampedAt: String) {
        self.source = source
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
        let font = UIFont.systemFont(ofSize: 8)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.darkGray]

        // PDF space is upright; UIKit draws flipped. Flip once so the text
        // comes out the right way up, at the foot of the page.
        UIGraphicsPushContext(context)
        context.saveGState()
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        let baseline = size.height - margin - font.lineHeight
        NSAttributedString(string: stampedAt, attributes: attrs)
            .draw(at: CGPoint(x: margin, y: baseline))
        let pageString = NSAttributedString(string: "Page \(pageNumber) of \(totalPages)", attributes: attrs)
        pageString.draw(at: CGPoint(x: size.width - margin - pageString.size().width, y: baseline))
        context.restoreGState()
        UIGraphicsPopContext()
    }
}
