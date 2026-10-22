// Turn a PDF into the `page` / `run` lines the engine reads a screenplay out of.
//
// This is the shell's whole half of the PDF boundary, and it is deliberately
// stupid: it decodes, it measures, and it makes no judgement whatsoever about
// what any of the text *means*. Every decision about what a line is — a slug, a
// cue, a room — belongs to `engine/src/printed.rs`, where it is tested without a
// PDF in sight. See decision 1 in design/phases/phase-2-script.md.
//
//   swift tools/pdftext.swift <file.pdf> [> pages.txt]
//
// **Lines, not characters.** The obvious way to do this is to walk
// `characterBounds(at:)` and gather letters into words, and it does not work:
// the index it wants and the index into `page.string` come apart on any PDF
// with ligatures or an unusual encoding, and the words arrive shredded — `OVE`,
// `BLAC`, `Writte`. `selectionsByLine()` asks PDFKit for what it already knows
// — where each line is and what it says — and is both simpler and right.
//
// **y counts down from the top.** PDF measures up from the bottom, so it is
// flipped here, once, and everything downstream reads down the page the way a
// person does.

import Foundation
import PDFKit

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write("usage: pdftext <file.pdf>\n".data(using: .utf8)!)
    exit(2)
}

let url = URL(fileURLWithPath: arguments[1])
guard let document = PDFDocument(url: url) else {
    FileHandle.standardError.write("that file will not open as a PDF\n".data(using: .utf8)!)
    exit(1)
}

var out = ""
out.reserveCapacity(1 << 20)

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
        // Tabs would be read as field separators on the other side.
        let clean = text.replacingOccurrences(of: "\t", with: " ")
        out += "run\t\(box.minX)\t\(top)\t\(clean)\n"
    }
}

FileHandle.standardOutput.write(out.data(using: .utf8)!)
