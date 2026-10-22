import SwiftUI
import AppKit

struct RichText: NSViewRepresentable {
    @Binding var attributed: NSAttributedString
    var font: NSFont
    var colour: NSColor
    var onCommit: (NSAttributedString) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let text = scroll.documentView as? NSTextView else { return scroll }

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.autohidesScrollers = true

        text.delegate = context.coordinator
        text.isRichText = true
        text.allowsUndo = true
        text.drawsBackground = false
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.textContainerInset = NSSize(width: 0, height: 2)
        text.textContainer?.widthTracksTextView = true
        text.font = font
        text.textColor = colour
        text.textStorage?.setAttributedString(attributed)
        context.coordinator.text = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        // never fight the person typing
        if text.window?.firstResponder !== text,
           text.textStorage?.string != attributed.string {
            text.textStorage?.setAttributedString(attributed)
        }
        text.typingAttributes[.font] = font
        text.typingAttributes[.foregroundColor] = colour
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichText
        weak var text: NSTextView?

        init(_ parent: RichText) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let text = notification.object as? NSTextView,
                  let storage = text.textStorage else { return }
            parent.attributed = NSAttributedString(attributedString: storage)
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let text = notification.object as? NSTextView,
                  let storage = text.textStorage else { return }
            parent.onCommit(NSAttributedString(attributedString: storage))
        }

        func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                commit(view)
                view.window?.selectNextKeyView(nil)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                commit(view)
                view.window?.selectPreviousKeyView(nil)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                // Return is a new line here, not a commit: a note is prose,
                // and the table's rule (Return closes the cell) belongs to
                // cells. The words are written when the field is left, and
                // on every keystroke through the binding.
                return false
            default:
                return false
            }
        }

        private func commit(_ view: NSTextView) {
            guard let storage = view.textStorage else { return }
            parent.onCommit(NSAttributedString(attributedString: storage))
        }
    }
}

// ------------------------------------------------------------------ storage

/// Formatting travels as RTF, base64'd, because the change log carries text and
/// RTF is the one rich format every Mac can already read and write.
enum Rich {
    /// **A run he deliberately sized or refaced.**
    ///
    /// Lives only in the text storage — RTF cannot carry an attribute it has
    /// never heard of — and is written out beside the RTF by `encode`, which
    /// is why the storage format grew a second half.
    ///
    /// It exists because the page's Body size became something he can set,
    /// and the moment it did, "10.5 point" stopped meaning "the page said so".
    /// Without a mark, a class change either leaves every word he has already
    /// written at the old size (his report: *"the body didn't seem to change
    /// size with my adjustments"*) or stamps over the two words he made
    /// bigger on purpose. The mark is what tells the two apart.
    static let chosen = NSAttributedString.Key("shotlisterChosenType")

    /// Re-ink a whole storage, leaving every font alone.
    ///
    /// The words are stored with a colour, so black type written in daylight
    /// would stay black at night. This is the only thing that may be applied
    /// to a whole paragraph without being asked: the ink is a fact about the
    /// screen, not about the writing.
    static func recolour(_ storage: NSTextStorage, to colour: NSColor) {
        let whole = NSRange(location: 0, length: storage.length)
        guard whole.length > 0 else { return }
        storage.addAttribute(.foregroundColor, value: colour, range: whole)
    }

    /// Put **a range** into a new face, run by run, keeping each run's own
    /// bold and italic.
    ///
    /// His correction of 2026-08-20: *"font and font type should only affect
    /// the text I've selected — not globally."* It used to take the whole
    /// paragraph, which is not what a font control does in any editor.
    static func reface(_ storage: NSTextStorage, in range: NSRange,
                       design: NSFontDescriptor.SystemDesign, size: CGFloat?) {
        guard range.length > 0 else { return }
        let manager = NSFontManager.shared
        storage.beginEditing()
        // His, from here on: the page's own face no longer reaches these words.
        storage.addAttribute(chosen, value: true, range: range)
        storage.enumerateAttribute(.font, in: range) { value, part, _ in
            let current = value as? NSFont ?? NSFont.systemFont(ofSize: 13.5)
            let traits = manager.traits(of: current)
            let points = size ?? current.pointSize
            var next = NSFont.systemFont(ofSize: points)
            if let descriptor = next.fontDescriptor.withDesign(design),
               let designed = NSFont(descriptor: descriptor, size: points) {
                next = designed
            }
            if traits.contains(.boldFontMask) {
                next = manager.convert(next, toHaveTrait: .boldFontMask)
            }
            if traits.contains(.italicFontMask) {
                next = manager.convert(next, toHaveTrait: .italicFontMask)
            }
            storage.addAttribute(.font, value: next, range: part)
        }
        storage.endEditing()
    }

    /// Nudge only the **size** of a range, keeping each run's face and traits.
    static func resize(_ storage: NSTextStorage, in range: NSRange, by step: CGFloat) {
        guard range.length > 0 else { return }
        storage.beginEditing()
        storage.addAttribute(chosen, value: true, range: range)
        storage.enumerateAttribute(.font, in: range) { value, part, _ in
            let current = value as? NSFont ?? NSFont.systemFont(ofSize: 13.5)
            let points = min(28, max(8, current.pointSize + step))
            if let sized = NSFont(descriptor: current.fontDescriptor, size: points) {
                storage.addAttribute(.font, value: sized, range: part)
            }
        }
        storage.endEditing()
    }

    /// Put a whole storage into a new base face, **run by run**, keeping each
    /// run's own bold and italic.
    ///
    /// The page's Serif/Sans switch and its type size are a fact about the
    /// *page*, not about the words — so changing them has to reach words that
    /// are already written. Setting `font` on a rich text view does not do
    /// that (it styles what you type next), which is why the toolbar moved a
    /// number and nothing on the page moved with it.
    static func restyle(_ storage: NSTextStorage, to font: NSFont, colour: NSColor) {
        let whole = NSRange(location: 0, length: storage.length)
        guard whole.length > 0 else { return }
        let manager = NSFontManager.shared
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: whole) { value, part, _ in
            let traits = manager.traits(of: value as? NSFont ?? font)
            var next = font
            if traits.contains(.boldFontMask) {
                next = manager.convert(next, toHaveTrait: .boldFontMask)
            }
            if traits.contains(.italicFontMask) {
                next = manager.convert(next, toHaveTrait: .italicFontMask)
            }
            storage.addAttribute(.font, value: next, range: part)
        }
        // The ink follows the appearance, not the words: black type stored in
        // daylight must not stay black at night.
        storage.addAttribute(.foregroundColor, value: colour, range: whole)
        storage.endEditing()
    }

    /// **The RTF, and then the runs that are his.**
    ///
    /// `<base64 rtf>|12,5;30,7` — the second half is the ranges he sized or
    /// refaced himself, which RTF has no way to carry. No second half means
    /// no such runs, which is nearly every shot ever written.
    ///
    /// Base64 has no `|` in its alphabet, so the split is unambiguous and an
    /// older app reading a newer string simply fails to decode the whole thing
    /// and falls back to the plain words — never to a scrambled page.
    /// **Give the page's face and size to the words that are the page's.**
    ///
    /// The live half of `fitted`. A class the page owns changed, so every run
    /// that has not been deliberately sized or refaced follows it — and the
    /// ones marked `chosen` do not, which is what lets both be true at once.
    ///
    /// This is not the old whole-paragraph restyle his correction of
    /// 2026-08-20 threw out. That one had no way to tell a run he had chosen
    /// from a run the page had handed out, so it took both; this takes only
    /// the page's own.
    static func repage(_ storage: NSTextStorage, to font: NSFont) {
        let whole = NSRange(location: 0, length: storage.length)
        guard whole.length > 0 else { return }
        let manager = NSFontManager.shared
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: whole) { value, range, _ in
            let traits = manager.traits(of: value as? NSFont ?? font)
            var next = font
            for trait in [NSFontTraitMask.boldFontMask, .italicFontMask]
            where traits.contains(trait) {
                next = manager.convert(next, toHaveTrait: trait)
            }
            // Run by run inside this one: a sentence can be half his.
            storage.enumerateAttribute(chosen, in: range) { mark, part, _ in
                guard mark == nil else { return }
                storage.addAttribute(.font, value: next, range: part)
            }
        }
        storage.endEditing()
    }

    static func encode(_ text: NSAttributedString) -> String {
        let range = NSRange(location: 0, length: text.length)
        guard let data = text.rtf(from: range, documentAttributes: [:]) else { return "" }
        var marks: [String] = []
        text.enumerateAttribute(chosen, in: range) { value, part, _ in
            guard value != nil, part.length > 0 else { return }
            marks.append("\(part.location),\(part.length)")
        }
        let body = data.base64EncodedString()
        return marks.isEmpty ? body : body + "|" + marks.joined(separator: ";")
    }

    /// `12,5;30,7` back into ranges. Anything malformed is simply not a range.
    private static func ranges(_ said: String) -> [NSRange] {
        said.split(separator: ";").compactMap { pair in
            let halves = pair.split(separator: ",")
            guard halves.count == 2,
                  let at = Int(halves[0]), let long = Int(halves[1]),
                  at >= 0, long > 0 else { return nil }
            return NSRange(location: at, length: long)
        }
    }

    static func decode(_ encoded: String, plain: String, font: NSFont, colour: NSColor) -> NSAttributedString {
        let halves = encoded.split(separator: "|", maxSplits: 1,
                                   omittingEmptySubsequences: false)
        let body = halves.first.map(String.init) ?? ""
        // **No second half means nobody has said which runs are his** — an
        // older string, so the sizes have to be read instead. See `fitted`.
        let his = halves.count > 1 ? ranges(String(halves[1])) : nil
        if !body.isEmpty,
           let data = Data(base64Encoded: body),
           let text = NSAttributedString(rtf: data, documentAttributes: nil),
           text.string == plain {
            // only trust the formatted copy while it still says the same words
            return recoloured(fitted(text, to: font, keeping: his), colour: colour)
        }
        return NSAttributedString(
            string: plain,
            attributes: [.font: font, .foregroundColor: colour]
        )
    }

    /// **The sizes the page has handed out by default over its life.**
    ///
    /// A run carries a size for one of two reasons: he chose it, or the page
    /// gave it one and he never thought about it. The first is his and must
    /// survive; the second is the page's own and should follow the page when
    /// the page changes — the same argument the colour below already makes.
    ///
    /// Nothing distinguishes them in stored RTF, so this is the list of sizes
    /// the page itself has used. **Add to it, never edit it**, whenever
    /// `Page.body` changes: a size on this list was the page talking.
    ///
    /// It matters because everything written before 2026-08-23 carries 13.5,
    /// which was the page's body when it was, in his words, *"way too big"*.
    /// Without this, shrinking the page would have left every sentence he has
    /// already written at the old size, and the change would have appeared to
    /// do nothing at all on his two real films.
    ///
    /// **Only strings written before the mark existed are read this way.** A
    /// string with a second half says outright which runs are his, and this
    /// list is not consulted at all. 10.5 joined it on 2026-09-03: it was the
    /// page's body from August until the day the size became his to set, so
    /// every sentence in both his real films carries it — and until it was on
    /// this list, moving Body moved nothing, which is exactly what he
    /// reported.
    static let pageDefaults: [CGFloat] = [13.5, 10.5]

    /// Give the page's face and size back to the runs that never chose their
    /// own. Bold and italic survive — those are always deliberate.
    ///
    /// The face goes with the size for the same reason: the words written
    /// before the serif fix carry HelveticaNeue, which was the editor's
    /// fallback rather than anybody's decision.
    private static func fitted(_ text: NSAttributedString, to font: NSFont,
                               keeping his: [NSRange]?) -> NSAttributedString {
        let out = NSMutableAttributedString(attributedString: text)
        let whole = NSRange(location: 0, length: out.length)
        guard whole.length > 0 else { return out }

        // Which characters are his. Said outright when the string carries the
        // marks; read off the sizes when it was written before they existed.
        var mine = IndexSet()
        if let his {
            for range in his {
                let inside = NSIntersectionRange(range, whole)
                guard inside.length > 0 else { continue }
                mine.insert(integersIn: inside.location..<(inside.location + inside.length))
            }
        } else {
            out.enumerateAttribute(.font, in: whole) { value, range, _ in
                guard let current = value as? NSFont else { return }
                guard !pageDefaults.contains(where: { abs($0 - current.pointSize) < 0.01 })
                else { return }
                mine.insert(integersIn: range.location..<(range.location + range.length))
            }
        }

        let manager = NSFontManager.shared
        out.beginEditing()
        // Carried forward, so the next `encode` still knows which runs are his.
        for run in mine.rangeView {
            out.addAttribute(chosen, value: true,
                             range: NSRange(location: run.lowerBound, length: run.count))
        }
        let pageOwns = IndexSet(integersIn: 0..<out.length).subtracting(mine)
        out.enumerateAttribute(.font, in: whole) { value, range, _ in
            let traits = manager.traits(of: value as? NSFont ?? font)
            var next = font
            for trait in [NSFontTraitMask.boldFontMask, .italicFontMask]
            where traits.contains(trait) {
                next = manager.convert(next, toHaveTrait: trait)
            }
            let run = IndexSet(integersIn: range.location..<(range.location + range.length))
            for piece in pageOwns.intersection(run).rangeView {
                out.addAttribute(.font, value: next,
                                 range: NSRange(location: piece.lowerBound, length: piece.count))
            }
        }
        out.endEditing()
        return out
    }

    /// RTF remembers the colour it was written in, which is wrong the moment the
    /// window changes appearance. Emphasis is kept; colour is the page's to say.
    private static func recoloured(_ text: NSAttributedString, colour: NSColor) -> NSAttributedString {
        let out = NSMutableAttributedString(attributedString: text)
        out.addAttribute(.foregroundColor, value: colour,
                         range: NSRange(location: 0, length: out.length))
        return out
    }
}
