import UIKit

/// **The Mac's bold and italic, on the Document page.**
///
/// A shot's words carry their emphasis beside the plain text as RTF (base64,
/// optionally `|` and the runs he sized himself), which the Mac trusts only
/// while it still says the same words. This reads that for the phone's page
/// and writes it back the same way, so editing a sentence there keeps what was
/// bold or italic in it.
enum DocumentRich {
    struct Run: Equatable {
        var text: String
        var bold = false
        var italic = false
    }

    /// The words as runs, when the stored emphasis still says these words.
    static func runs(rich: String, plain: String) -> [Run]? {
        let body = rich.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        guard !body.isEmpty, let data = Data(base64Encoded: body),
              let text = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                  documentAttributes: nil),
              text.string == plain else { return nil }
        var out: [Run] = []
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            let font = value as? UIFont
            let name = (font?.fontName ?? "").lowercased()
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            let bold = traits.contains(.traitBold) || ["bold", "heavy", "black"].contains { name.contains($0) }
            let italic = traits.contains(.traitItalic) || ["italic", "oblique"].contains { name.contains($0) }
            out.append(Run(text: (text.string as NSString).substring(with: range), bold: bold, italic: italic))
        }
        return merged(out)
    }

    static func merged(_ runs: [Run]) -> [Run] {
        var out: [Run] = []
        for r in runs where !r.text.isEmpty {
            if let last = out.last, last.bold == r.bold, last.italic == r.italic { out[out.count - 1].text += r.text }
            else { out.append(r) }
        }
        return out
    }

    static func plain(_ runs: [Run]) -> String { runs.map(\.text).joined() }

    /// One flag byte per UTF-16 unit — bold 1, italic 2 — for comparing two
    /// sets of runs over the same words without caring where runs split.
    static func marks(_ runs: [Run]) -> [UInt8] {
        runs.flatMap { r in Array(repeating: (r.bold ? 1 : 0) | (r.italic ? 2 : 0), count: r.text.utf16.count) }
    }

    static func hasEmphasis(_ runs: [Run]) -> Bool { runs.contains { $0.bold || $0.italic } }

    static func html(_ runs: [Run]) -> String {
        runs.map { r in
            var s = r.text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\n", with: "<br>")
            if r.italic { s = "<i>\(s)</i>" }
            if r.bold { s = "<b>\(s)</b>" }
            return s
        }.joined()
    }

    /// The words and their emphasis as the Mac stores them; empty when nothing
    /// is emphasised. Sized at the page's own 10.5 so the Mac still lets the
    /// page's size and face reach these words.
    static func encode(_ runs: [Run]) -> String {
        guard hasEmphasis(runs) else { return "" }
        let out = NSMutableAttributedString()
        for r in runs {
            let name = r.bold && r.italic ? "Helvetica-BoldOblique" : r.bold ? "Helvetica-Bold" : r.italic ? "Helvetica-Oblique" : "Helvetica"
            out.append(NSAttributedString(string: r.text, attributes: [.font: UIFont(name: name, size: 10.5) ?? UIFont.systemFont(ofSize: 10.5)]))
        }
        guard let data = try? out.data(from: NSRange(location: 0, length: out.length),
                                       documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) else { return "" }
        return data.base64EncodedString()
    }
}
