import SwiftUI
import AppKit

/// **A script as selectable text, with every quoted stretch tinted.**
///
/// A real `NSTextView`, read-only and selectable, because the whole gesture
/// is the system's: drag across the words, let go, and the selection is the
/// shot's. Quoted stretches wear a tint; the followed shot's wears the
/// accent, so a fast scroll says where you are. Stretches may overlap — a
/// darker tint where they do, which is honest.
///
/// **An AV script draws as a table** — Video on the left, Audio on the
/// right, one row per row (his ask, 2026-09-30). It is still one text and
/// one view: each of the engine's two marks (`AVScript`) is shown as a line
/// break, one character for one, so every offset into the script is an
/// offset into what is drawn, and a drag in either column ties exactly as it
/// does in a plain script.
struct ScriptText: NSViewRepresentable {
    struct Quote: Equatable {
        let shot: String
        let number: String
        let from: Int
        let to: Int
        let followed: Bool
    }

    let text: String
    /// Draw as Video beside Audio.
    var av: Bool = false
    let quotes: [Quote]
    let dark: Bool
    /// The UTF-16 offset to bring into view, when the followed shot has one.
    let scrollTo: Int?
    /// The selection, on mouse-up, as UTF-16 offsets into `text` — one
    /// piece, or one per row when a drag kept to one column of an AV script.
    let onSelect: ([(Int, Int)]) -> Void
    /// A click with no drag, on a character: its UTF-16 offset.
    var onClick: (Int) -> Void = { _ in }
    /// **A screenplay page** (Ref 1553): Courier at this size, one line to a
    /// row with no space between paragraphs, so the page keeps the shape the
    /// engine laid out. Nil draws a commercial's script as it always has.
    var page: CGFloat? = nil
    /// Ranges drawn faint — the paginator's own `(MORE)` and `(CONT'D)`.
    var faded: [NSRange] = []

    final class Coordinator: NSObject {
        var onSelect: ([(Int, Int)]) -> Void
        var onClick: (Int) -> Void = { _ in }
        var lastText = ""
        var lastQuotes: [Quote] = []
        var lastDark: Bool?
        var lastAV: Bool?
        var lastScroll: Int?
        var lastPage: CGFloat?
        var lastLength = 0
        init(onSelect: @escaping ([(Int, Int)]) -> Void) { self.onSelect = onSelect }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let view = Reader()
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 10, height: 12)
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        if page != nil {
            // A screenplay line is already laid out; wrapping it again
            // would break the page's shape.
            view.textContainer?.widthTracksTextView = false
            view.textContainer?.containerSize = NSSize(width: 100_000, height: CGFloat.greatestFiniteMagnitude)
            view.isHorizontallyResizable = true
        }
        view.onClick = { at in
            guard at < context.coordinator.lastLength else { return }
            context.coordinator.onClick(at)
        }
        view.onMouseUp = { [weak view] in
            guard let view else { return }
            // An empty last cell is drawn with a space the script does not
            // have; a drag into it stops at the script's end.
            let pieces = view.selectedRanges.map(\.rangeValue).compactMap { range -> (Int, Int)? in
                let end = min(range.location + range.length, context.coordinator.lastLength)
                return end > range.location ? (range.location, end) : nil
            }
            guard let last = pieces.last else { return }
            context.coordinator.onSelect(pieces)
            // The selection has done its work; the tint says the rest.
            view.setSelectedRange(NSRange(location: last.1, length: 0))
        }
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? Reader else { return }
        context.coordinator.onSelect = onSelect
        context.coordinator.onClick = onClick
        let c = context.coordinator
        if c.lastText != text || c.lastQuotes != quotes || c.lastDark != dark || c.lastAV != av || c.lastPage != page {
            view.textStorage?.setAttributedString(attributed())
            c.lastText = text
            c.lastQuotes = quotes
            c.lastDark = dark
            c.lastAV = av
            c.lastPage = page
            c.lastLength = (text as NSString).length
            view.cells = av ? Self.cells(text) : []
        }
        if let at = scrollTo, c.lastScroll != at, at <= (text as NSString).length {
            view.scrollRangeToVisible(NSRange(location: at, length: 0))
            c.lastScroll = at
        }
    }

    private func attributed() -> NSAttributedString {
        let shown = av ? AVScript.readable(text) : text
        let out = NSMutableAttributedString(string: shown)
        let whole = NSRange(location: 0, length: out.length)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = page == nil ? 3 : 0
        paragraph.paragraphSpacing = page == nil ? 8 : 0
        if let page {
            paragraph.minimumLineHeight = page * 1.35
            paragraph.maximumLineHeight = page * 1.35
        }
        let size = page ?? 12
        out.addAttributes([
            .font: NSFont(name: "Courier", size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular),
            .foregroundColor: NSColor(Brand.ink(dark)),
            .paragraphStyle: paragraph,
        ], range: whole)
        for range in faded where NSMaxRange(range) <= out.length {
            out.addAttribute(.foregroundColor, value: NSColor(Brand.ink4(dark)), range: range)
        }
        if av { layAsTable(out) }
        // Others first, the followed one on top.
        for quote in quotes.sorted(by: { !$0.followed && $1.followed }) {
            let from = max(0, min(quote.from, out.length))
            let to = max(from, min(quote.to, out.length))
            guard to > from else { continue }
            let range = NSRange(location: from, length: to - from)
            let tint = quote.followed
                ? NSColor(Brand.accent(dark)).withAlphaComponent(dark ? 0.32 : 0.22)
                : NSColor(Brand.ink(dark)).withAlphaComponent(dark ? 0.12 : 0.08)
            out.addAttribute(.backgroundColor, value: tint, range: range)
            if quote.followed {
                out.addAttribute(.foregroundColor, value: NSColor(Brand.ink(dark)), range: range)
            }
        }
        return out
    }

    /// **Video beside Audio**: each cell's paragraphs put in a cell of one
    /// two-column table. The cells are found by walking the script's own
    /// marks, so the table and the text can never disagree.
    private func layAsTable(_ out: NSMutableAttributedString) {
        let table = NSTextTable()
        table.numberOfColumns = 2
        table.layoutAlgorithm = .fixedLayoutAlgorithm
        table.collapsesBorders = true
        table.hidesEmptyCells = false
        let rule = NSColor(Brand.rule(dark))
        let units = Array(text.utf16)
        let font = NSFont(name: "Courier", size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        var row = 0, column = 0, start = 0
        func cell(_ from: Int, _ to: Int) {
            let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
            block.setValue(50, type: .percentageValueType, for: .width)
            block.setWidth(8, type: .absoluteValueType, for: .padding)
            block.setWidth(1, type: .absoluteValueType, for: .border, edge: .maxY)
            if column == 0 { block.setWidth(1, type: .absoluteValueType, for: .border, edge: .maxX) }
            block.setBorderColor(rule)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 3
            paragraph.paragraphSpacing = 6
            paragraph.textBlocks = [block]
            if to == from, to >= out.length {
                // The last cell, empty: a table cell needs a character.
                out.append(NSAttributedString(string: " ", attributes: [.font: font]))
            }
            out.addAttribute(.paragraphStyle, value: paragraph,
                             range: NSRange(location: from, length: max(1, to - from)))
        }
        for (at, unit) in units.enumerated() where unit == AVScript.cellUnit || unit == AVScript.rowUnit {
            cell(start, at + 1)
            if unit == AVScript.cellUnit { column = 1 } else { row += 1; column = 0 }
            start = at + 1
        }
        cell(start, units.count)
    }

    /// An AV script's cells, `(range, column)`, each range its words
    /// without the mark that closes it.
    static func cells(_ text: String) -> [(NSRange, Int)] {
        var out: [(NSRange, Int)] = []
        var column = 0, start = 0
        for (at, unit) in text.utf16.enumerated() where unit == AVScript.cellUnit || unit == AVScript.rowUnit {
            out.append((NSRange(location: start, length: at - start), column))
            column = unit == AVScript.cellUnit ? 1 : 0
            start = at + 1
        }
        out.append((NSRange(location: start, length: text.utf16.count - start), column))
        return out
    }

    /// The text view that reports a finished drag.
    final class Reader: NSTextView {
        var onMouseUp: (() -> Void)?
        /// A press that selected nothing, with the character under it.
        var onClick: ((Int) -> Void)?
        /// An AV script's cells; empty for a plain one.
        var cells: [(NSRange, Int)] = []
        /// The column a drag began in, while it lasts.
        private var downColumn: Int?

        /// Video (0) or Audio (1), by which half of the page the pointer is on.
        private func column(of event: NSEvent) -> Int? {
            guard !cells.isEmpty, let container = textContainer else { return nil }
            let x = convert(event.locationInWindow, from: nil).x - textContainerOrigin.x
            return x < container.size.width / 2 ? 0 : 1
        }

        /// **A drag that keeps to one column takes only that column** — his
        /// ask, 2026-10-05: *"select audio only or video only lines."* Down
        /// the Video, the selection is each row's Video and none of its
        /// Audio, drawn that way while the drag is still going. A drag that
        /// crosses into the other column takes both, as it always did.
        override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
            guard let down = downColumn, ranges.count == 1, let range = ranges.first?.rangeValue, range.length > 0,
                  let event = NSApp.currentEvent, column(of: event) == down
            else {
                super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
                return
            }
            let pieces = cells.filter { $0.1 == down }.compactMap { cell -> NSValue? in
                let both = NSIntersectionRange(cell.0, range)
                return both.length > 0 ? NSValue(range: both) : nil
            }
            super.setSelectedRanges(pieces.isEmpty ? ranges : pieces, affinity: affinity, stillSelecting: stillSelecting)
        }
        /// A press lands on the words even when the window is not key — the
        /// side panel is glanced at and dragged across, not clicked into
        /// first. (And a checking run's window is never key at all.)
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)
            onMouseUp?()
        }
        override func mouseDown(with event: NSEvent) {
            downColumn = column(of: event)
            super.mouseDown(with: event)
            downColumn = nil
            if (selectedRanges.first?.rangeValue.length ?? 0) == 0, let at = character(under: event) {
                onClick?(at)
            }
            // `super.mouseDown` runs the whole drag loop and returns on
            // mouse-up without calling `mouseUp` — so the report is here.
            if Launch.checking {
                let r = selectedRanges.first?.rangeValue ?? NSRange(location: 0, length: 0)
                FileHandle.standardError.write(Data(("reader: mouse down at \(event.locationInWindow), selection \(r.location)+\(r.length)\n").utf8))
            }
            onMouseUp?()
        }

        /// The character drawn under the pointer — on it, not merely nearest.
        private func character(under event: NSEvent) -> Int? {
            guard let layout = layoutManager, let container = textContainer else { return nil }
            let p = convert(event.locationInWindow, from: nil)
            let point = NSPoint(x: p.x - textContainerOrigin.x, y: p.y - textContainerOrigin.y)
            var fraction: CGFloat = 0
            let glyph = layout.glyphIndex(for: point, in: container, fractionOfDistanceThroughGlyph: &fraction)
            guard glyph < layout.numberOfGlyphs else { return nil }
            let box = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            guard box.insetBy(dx: -1, dy: -2).contains(point) else { return nil }
            return layout.characterIndexForGlyph(at: glyph)
        }
    }
}


/// **An AV script's text**, as the engine keeps it (`engine/src/quoting.rs`):
/// one text, a mark between a row's Video and its Audio, another between
/// rows. A person never sees the marks.
enum AVScript {
    static let cell: Character = "\u{1d}"
    static let row: Character = "\u{1e}"
    static let cellUnit: UInt16 = 0x1d
    static let rowUnit: UInt16 = 0x1e

    struct Row: Identifiable, Equatable {
        let id = UUID()
        var video: String
        var audio: String
        static func == (a: Row, b: Row) -> Bool { a.video == b.video && a.audio == b.audio }
    }

    static func isAV(_ text: String) -> Bool { text.contains(cell) }

    /// The marks as line breaks, one unit for one.
    static func readable(_ text: String) -> String {
        String(text.map { $0 == cell || $0 == row ? "\n" : $0 })
    }

    static func rows(_ text: String) -> [Row] {
        guard isAV(text) else { return text.isEmpty ? [] : [Row(video: "", audio: text)] }
        return text.split(separator: row, omittingEmptySubsequences: false).map { part in
            let halves = part.split(separator: cell, maxSplits: 1, omittingEmptySubsequences: false)
            return Row(video: String(halves.first ?? ""),
                       audio: halves.count > 1 ? readable(String(halves[1])) : "")
        }
    }

    static func text(_ rows: [Row]) -> String {
        func clean(_ s: String) -> String { readable(s) }
        guard !rows.isEmpty else { return String(cell) }
        return rows.map { clean($0.video) + String(cell) + clean($0.audio) }.joined(separator: String(row))
    }
}
