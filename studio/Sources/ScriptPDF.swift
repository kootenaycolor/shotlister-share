import Foundation
import PDFKit
import AppKit

/// Turning a PDF into something the engine can read a screenplay out of.
///
/// **This is the shell's whole half of the PDF boundary**, and it is
/// deliberately stupid: it decodes, it measures, and it makes no judgement at
/// all about what any of the text *means*. Every decision about what a line is —
/// a slug, a cue, a room, a page number, a `(CONTINUED)` — belongs to
/// `engine/src/printed.rs`, where it is tested without a PDF in sight. That is
/// decision 1 of the script phase, and it is why this file is sixty lines.
///
/// It lived as `tools/pdftext.swift`, a thing run by hand, from the day the
/// engine could read a script until the day the app could import one. This is
/// the same code with a home (Ref 17).
enum ScriptPDF {
    /// What the engine's `readscript` expects: a `page` line for each page and a
    /// `run` line for each line of text on it.
    ///
    /// ```text
    /// page\t<width>\t<height>
    /// run\t<x>\t<y>\t<text>
    /// ```
    ///
    /// **`y` counts down from the top.** PDF measures up from the bottom, so it
    /// is flipped here, once, and everything downstream reads down the page the
    /// way a person does.
    ///
    /// **Points, not pixels.** US Letter is 612 × 792.
    static func runs(from document: PDFDocument) -> String {
        var out = ""
        out.reserveCapacity(1 << 20)

        for index in 0 ..< document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            out += "page\t\(bounds.width)\t\(bounds.height)\n"

            guard let whole = page.selection(for: bounds) else { continue }
            // **Lines, not characters.** The obvious way is to walk
            // `characterBounds(at:)` and gather letters into words, and it does
            // not work: that index and the index into `page.string` come apart
            // on any PDF with ligatures or an unusual encoding, and the words
            // arrive shredded — `OVE`, `BLAC`, `Writte`. `selectionsByLine()`
            // asks PDFKit for what it already knows.
            for line in whole.selectionsByLine() {
                guard let said = line.string else { continue }
                let text = said.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty { continue }

                let box = line.bounds(for: page)
                if box.isNull || box.isInfinite { continue }
                let top = bounds.height - box.maxY
                // Tabs would be read as field separators on the other side.
                let clean = text.replacingOccurrences(of: "\t", with: " ")
                out += "run\t\(box.minX)\t\(top)\t\(clean)\n"
            }
        }
        return out
    }

    /// The first page, small, for the import sheet to show. Seeing the script
    /// you are about to take in is most of knowing you picked the right file.
    static func firstPage(of document: PDFDocument, wide: CGFloat = 220) -> NSImage? {
        guard let page = document.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0 else { return nil }
        let scale = wide / bounds.width
        let size = NSSize(width: bounds.width * scale, height: bounds.height * scale)
        return NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            guard let context = NSGraphicsContext.current?.cgContext else { return true }
            context.saveGState()
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()
            return true
        }
    }
}
