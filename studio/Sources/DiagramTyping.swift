import SwiftUI
import AppKit

// **Typing on the plan, in the words themselves** (his call F, 2026-10-04,
// Back to Paper Batch 2). A lamp's Name or Note, a shared label's, free
// Words, any piece's name: Return, a double-click on the words, or Name or
// Note on the bar puts the cursor right there — the same type, the same
// size, no box, no Cancel or Done. Clicking away keeps what was typed;
// Escape leaves the words as they were.
//
// Nothing is written while he types: the words on the plan are the field,
// and one edit goes to the engine when he is done — one step of undo.

/// What is being typed, and where.
struct DiagramTyping: Equatable {
    /// `sheet`: the sheet's own words — its Notes, a legend head
    /// (`DiagramPage.swift`); `el` is then `sheet:` and what is typed.
    enum What: String { case name, note, text, label, sheet }
    static let sheet = "sheet:"
    /// The piece whose words are typed in: a lamp, a shared label, Words, a
    /// piece with a name.
    var el: String
    var what: What
    /// The lamps a Name or a Note is written to.
    var lamps: [String] = []
    /// The words as they were.
    var start: String
    /// Kept for old callers; every Name is this lamp's alone now.
    var only = false
    /// A frame's Note (2026-10-05): written to the frame itself, its
    /// `label`; `lamps` holds the frame alone.
    var frame = false
    /// Any other piece's Note, its `caption` (2026-10-05: "alll items
    /// should be able to have a note"); `lamps` holds the piece alone.
    var own = false

    /// Words' two sizes, as stored (`render::WORDS_REGULAR`, `WORDS_LARGE`):
    /// 10 and 14 points on the sheet.
    static let wordsRegular = 10.0 * 40 / 60
    static let wordsLarge = 14.0 * 40 / 60
    /// Whether stored words read Large (`render::words_large`).
    static func isLarge(_ size: Double) -> Bool { size * 60 / 40 >= 12 }
}

extension DiagramModel {
    /// The lamps tied to a shared label, by its id.
    func tied(to label: String) -> [DiagramEl] {
        plan.els.filter { $0.tie_to == label && DiagramMarks.canShare($0) }
    }

    /// A piece's Note (`render::note_of`): a lamp's and a frame's `label`,
    /// anything else's `caption`.
    func noteOf(_ e: DiagramEl) -> String {
        DiagramMarks.isLamp(e, self) || DiagramFrames.isFrame(e) ? e.label : (e.caption ?? "")
    }

    /// The shared label a lamp is named on, if it is.
    func sharedLabel(of e: DiagramEl) -> DiagramEl? {
        guard let t = e.tie_to, !t.isEmpty, let l = el(t), l.kind == "text" else { return nil }
        return l
    }

    /// Words with lamps tied to them: a shared label.
    func isSharedLabel(_ e: DiagramEl) -> Bool {
        e.kind == "text" && !tied(to: e.id).isEmpty
    }

    /// **A shared label's lamps light up while it is picked** (the
    /// recommendation's on-canvas list; fix round 2), or while one of its
    /// lamps is: every lamp it holds that is not picked itself.
    var sharedLit: [String] {
        guard !selection.isEmpty, !presenting else { return [] }
        var labels: [String] = []
        for e in picked {
            let l = isSharedLabel(e) ? e.id : sharedLabel(of: e)?.id
            if let l, !labels.contains(l) { labels.append(l) }
        }
        return labels.flatMap { tied(to: $0).map(\.id) }.filter { !selection.contains($0) }
    }

    /// **Start typing on the plan.** `what` nil: a lamp's Note, Words' text,
    /// anything else's name. Nothing when it has no words of its own to type
    /// (a camera named by its shot, a person by their character).
    func startTyping(_ id: String, _ what: DiagramTyping.What? = nil, only: Bool = false) {
        guard !readOnly, !presenting, let e = el(id) else { return }
        if typing != nil { endTyping(keep: true) }
        var t: DiagramTyping
        if DiagramMarks.isLamp(e, self) {
            let lamps: [DiagramEl]
            let on: String
            // Several lamps picked: a Name typed is each one's (the bar's
            // Name on a pick of lamps); one lamp, that one alone.
            let pickedLamps = picked.filter { DiagramMarks.isLamp($0, self) }
            if let shared = sharedLabel(of: e) { on = shared.id; lamps = tied(to: shared.id) }
            else if what == .name, pickedLamps.count > 1, pickedLamps.contains(where: { $0.id == e.id }) { on = e.id; lamps = pickedLamps }
            else { on = e.id; lamps = [e] }
            let w = what == .name ? DiagramTyping.What.name : .note
            t = DiagramTyping(el: on, what: w, lamps: lamps.map(\.id),
                              start: w == .name ? (lamps.first?.lamp_name ?? "") : (lamps.first?.label ?? ""),
                              only: only && w == .name && on == e.id)
        } else if DiagramFrames.isFrame(e) {
            // **A frame's Name is what he types** (2026-10-17: *"I still
            // can't manually just label a silk"*), its Note under it.
            if let shared = sharedLabel(of: e) {
                let w = what == .name ? DiagramTyping.What.name : .note
                let held = tied(to: shared.id)
                t = DiagramTyping(el: shared.id, what: w, lamps: held.map(\.id),
                                  start: w == .name ? (held.first?.lamp_name ?? "") : (held.first.map(noteOf) ?? ""))
            } else if what == .name {
                t = DiagramTyping(el: e.id, what: .name, lamps: [e.id], start: e.lamp_name ?? "", frame: true)
            } else {
                t = DiagramTyping(el: e.id, what: .note, lamps: [e.id], start: e.label, frame: true)
            }
        } else if isSharedLabel(e) {
            let lamps = tied(to: e.id)
            // Its Name is its lamps' and frames' Name; a label shared only
            // by other pieces takes its own words (2026-10-17).
            let named = lamps.contains { DiagramMarks.isLamp($0, self) || DiagramFrames.isFrame($0) }
            let w = what == .name ? DiagramTyping.What.name : .note
            t = DiagramTyping(el: e.id, what: w, lamps: lamps.map(\.id),
                              start: w == .name ? (named ? (lamps.first?.lamp_name ?? "") : e.text) : (lamps.first.map(noteOf) ?? ""))
        } else if ["text", "note"].contains(e.kind) {
            t = DiagramTyping(el: e.id, what: .text, start: e.text)
        } else if what == .note {
            guard DiagramNames.notable(e) else { return }
            t = DiagramTyping(el: e.id, what: .note, lamps: [e.id], start: e.caption ?? "", own: true)
        } else {
            guard DiagramNames.renamable(e) else { return }
            t = DiagramTyping(el: e.id, what: .label, start: e.label)
        }
        if !selection.contains(id) { selection = [id] }
        typing = t
    }

    /// Done typing: `keep` writes what was typed (clicking away, Return),
    /// else the words stay as they were (Escape).
    func endTyping(keep: Bool) {
        guard let t = typing else { return }
        let view = canvas as? DiagramCanvasView
        let text = (view?.typist?.string ?? t.start).trimmingCharacters(in: .whitespacesAndNewlines)
        typing = nil
        if !glow.isEmpty { glow = [] }
        if let view { view.window?.makeFirstResponder(view) }
        guard keep, text != t.start.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        // **Hide Label stays as he set it** (fix round 2): a name typed on a
        // lamp whose label he hid is drawn while it is typed, then hidden
        // again — it is in the legend and on the bar. Show Label shows it.
        var ops: [[String: Any]]
        switch t.what {
        case .note where t.frame:
            ops = [DiagramOps.update([t.el], ["label": text])]
        case .note where t.own:
            ops = [DiagramOps.update([t.el], ["caption": text])]
        case .name:
            // One lamp or frame, or every one on the shared label being
            // typed on; a label shared only by other pieces, its own words.
            let named = t.lamps.filter { el($0).map { DiagramMarks.isLamp($0, self) || DiagramFrames.isFrame($0) } ?? false }
            if named.isEmpty {
                guard let l = el(t.el), l.kind == "text" else { return }
                ops = [DiagramOps.update([t.el], ["text": text])]
            } else {
                ops = named.map { ["op": "name_piece", "id": $0, "name": text] }
            }
        case .note:
            // A lamp's and a frame's Note is its `label`; any other piece's
            // its `caption` (a shared label can hold all of them).
            let pieces = t.lamps.compactMap { el($0) }
            let byLabel = pieces.filter { DiagramMarks.isLamp($0, self) || DiagramFrames.isFrame($0) }.map(\.id)
            let byCaption = pieces.map(\.id).filter { !byLabel.contains($0) }
            ops = []
            if !byLabel.isEmpty { ops.append(DiagramOps.update(byLabel, ["label": text])) }
            if !byCaption.isEmpty { ops.append(DiagramOps.update(byCaption, ["caption": text])) }
            if ops.isEmpty { return }
        case .text: ops = [DiagramOps.update([t.el], ["text": text])]
        case .label: ops = [DiagramOps.update([t.el], ["label": text])]
        case .sheet:
            guard let op = sheetEdit(t.el, text) else { return }
            ops = [op]
        }
        edit(ops.count == 1 ? ops[0] : DiagramOps.batch(ops))
    }
}

/// The words being typed: a text view laid exactly over where the plan
/// draws them, in their own type, on a patch of the plan's paper — **in
/// capitals as he types**, the way the plan draws every word (Ref 1452), so
/// nothing jumps when he is done. What he typed is kept as he typed it.
final class DiagramTypist: NSTextView, NSLayoutManagerDelegate {
    /// Told once, when typing ends: true keeps it.
    var finish: ((Bool) -> Void)?
    /// Told as the words change.
    var changed: ((String) -> Void)?
    /// Words may run to several lines (⌥Return) — a name and a label too
    /// (his ask, 2026-10-17); a sheet's head is one line.
    var multiline = false
    /// Drawn in capitals as he types, only with Plan Settings › All Caps
    /// (2026-10-17); else as typed.
    var caps = false
    /// Which side of the words stays put as they grow: `start`, `middle`, `end`.
    var anchor = "middle"
    /// The point it grows from, on the canvas: x the anchor, y the top.
    var spot: CGPoint = .zero
    /// **The light library under a lamp's Name** (`DiagramMarks.names`):
    /// as he types, the lights that match are listed under the words — no
    /// box of their own; Return or a click takes one, typing on ignores them.
    var suggestions: [String] = []
    private var ending = false
    /// The text the typist lays out, held here: a text view made on its own
    /// stack does not keep it.
    private var storage: NSTextStorage?

    /// A typist on its own text stack, so its words can be drawn in
    /// capitals while what he types is kept as typed.
    static func make() -> DiagramTypist {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 4000, height: 4000))
        layout.addTextContainer(container)
        let v = DiagramTypist(frame: CGRect(x: 0, y: 0, width: 40, height: 14), textContainer: container)
        v.storage = storage
        layout.delegate = v
        return v
    }

    func end(_ keep: Bool) {
        guard !ending else { return }
        ending = true
        finish?(keep)
    }

    /// Every letter drawn as its capital: the glyphs change, the words do not.
    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes charIndexes: UnsafePointer<Int>, font aFont: NSFont,
                       forGlyphRange glyphRange: NSRange) -> Int {
        guard caps, let text = layoutManager.textStorage?.string as NSString?, glyphRange.length > 0 else { return 0 }
        let n = glyphRange.length
        var out = Array(UnsafeBufferPointer(start: glyphs, count: n))
        var changed = false
        for i in 0..<n {
            let index = charIndexes[i]
            guard index < text.length else { continue }
            let c = text.character(at: index)
            if (0xD800...0xDFFF).contains(c) { continue }
            let up = Array(String(utf16CodeUnits: [c], count: 1).uppercased().utf16)
            guard up.count == 1, up[0] != c else { continue }
            var u = up[0]
            var g: CGGlyph = 0
            if CTFontGetGlyphsForCharacters(aFont, &u, &g, 1) { out[i] = g; changed = true }
        }
        guard changed else { return 0 }
        layoutManager.setGlyphs(out, properties: props, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
        return n
    }

    // MARK: the light library, under a lamp's Name

    /// The list under the words: on the plan beside them, not a window.
    private(set) var list: DiagramSuggestions?

    /// The lights that match what is typed, the typed words themselves left out.
    func matches() -> [String] {
        let typed = string.trimmingCharacters(in: .whitespaces)
        guard !suggestions.isEmpty, !typed.isEmpty else { return [] }
        return Array(suggestions.filter {
            $0.localizedCaseInsensitiveContains(typed) && $0.caseInsensitiveCompare(typed) != .orderedSame
        }.prefix(8))
    }

    /// The list brought up to date with what is typed, under the words.
    private func offer() {
        guard !suggestions.isEmpty, let host = superview else { return }
        let found = ending ? [] : matches()
        if found.isEmpty {
            list?.removeFromSuperview()
            list = nil
            return
        }
        let l = list ?? {
            let l = DiagramSuggestions(frame: .zero)
            l.pick = { [weak self] name in self?.take(name); self?.end(true) }
            host.addSubview(l)
            list = l
            return l
        }()
        l.dark = host.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if l.items != found { l.items = found; l.chosen = nil }
        l.place(under: frame)
    }

    private func take(_ word: String) {
        guard !word.isEmpty, word != string else { return }
        string = word
        setSelectedRange(NSRange(location: (word as NSString).length, length: 0))
        fit()
        changed?(string)
    }

    override func removeFromSuperview() {
        list?.removeFromSuperview()
        list = nil
        super.removeFromSuperview()
    }

    override func doCommand(by selector: Selector) {
        switch selector {
        // Down and up go through the lights listed under the words.
        case #selector(moveDown(_:)) where list != nil:
            list?.step(1)
        case #selector(moveUp(_:)) where list != nil:
            list?.step(-1)
        case #selector(insertNewline(_:)), #selector(insertTab(_:)), #selector(insertBacktab(_:)):
            if let l = list, let i = l.chosen, l.items.indices.contains(i) { take(l.items[i]) }
            end(true)
        case #selector(insertNewlineIgnoringFieldEditor(_:)):
            if multiline { insertText("\n", replacementRange: selectedRange()) } else { end(true) }
        case #selector(cancelOperation(_:)):
            end(false)
        default:
            super.doCommand(by: selector)
        }
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        // Clicking away keeps it.
        if ok, !ending { DispatchQueue.main.async { [weak self] in self?.end(true) } }
        return ok
    }

    override func didChangeText() {
        super.didChangeText()
        fit()
        changed?(string)
    }

    /// As wide as the words, grown from its anchor.
    func fit() {
        defer { offer() }
        guard let lm = layoutManager, let tc = textContainer else { return }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)
        let lineH = (font.map { $0.ascender - $0.descender + $0.leading }) ?? 12
        let w = max(ceil(used.width) + 3, 12)
        let h = max(ceil(used.height), lineH)
        let x = anchor == "start" ? spot.x : anchor == "end" ? spot.x - w : spot.x - w / 2
        let f = CGRect(x: x, y: spot.y, width: w, height: h)
        if f != frame { frame = f }
    }
}

/// **The lights that match a lamp's Name as it is typed**, listed just
/// under the words on the plan. A click, or Down then Return, takes one.
final class DiagramSuggestions: NSView {
    var items: [String] = [] { didSet { needsDisplay = true } }
    var chosen: Int? { didSet { needsDisplay = true } }
    var dark = false
    var pick: ((String) -> Void)?
    static let row: CGFloat = 20
    static let font = NSFont.systemFont(ofSize: 12)

    override var isFlipped: Bool { true }

    func step(_ by: Int) {
        guard !items.isEmpty else { return }
        let next = (chosen ?? (by > 0 ? -1 : items.count)) + by
        chosen = next < 0 || next >= items.count ? nil : next
    }

    /// Under the words, as wide as its longest light.
    func place(under words: CGRect) {
        let w = items.map { ($0 as NSString).size(withAttributes: [.font: Self.font]).width }.max() ?? 80
        let size = CGSize(width: max(ceil(w) + 20, 120), height: CGFloat(items.count) * Self.row + 8)
        let f = CGRect(x: words.minX, y: words.maxY + 4, width: size.width, height: size.height)
        if frame != f { frame = f }
    }

    override func draw(_ dirtyRect: NSRect) {
        let back = NSColor(Brand.surface(dark))
        let edge = NSColor(Brand.rule2(dark))
        let ink = NSColor(Brand.ink(dark))
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        back.setFill(); box.fill()
        edge.setStroke(); box.lineWidth = 1; box.stroke()
        for (i, name) in items.enumerated() {
            let r = CGRect(x: 4, y: 4 + CGFloat(i) * Self.row, width: bounds.width - 8, height: Self.row)
            if i == chosen {
                NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
                NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5).fill()
            }
            let colour = i == chosen ? NSColor.white : ink
            (name as NSString).draw(at: CGPoint(x: r.minX + 6, y: r.minY + 3), withAttributes: [.font: Self.font, .foregroundColor: colour])
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = Int((p.y - 4) / Self.row)
        guard items.indices.contains(i) else { return }
        chosen = i
        pick?(items[i])
    }

    /// Clicks on the list are the list's, not the plan's under it.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension DiagramCanvasView {
    /// Where the words being typed are drawn: the shape that draws them, and
    /// which of its lines is being typed — `nil` all of them.
    private func typedShape(_ m: DiagramModel, _ t: DiagramTyping) -> DiagramShape? {
        let shapes = m.shown.shapes
        if t.what == .text || m.el(t.el).map(m.isSharedLabel) == true {
            return shapes.first { $0.e == t.el && $0.p == "body" && $0.k == "text" }
        }
        return shapes.first { $0.e == t.el && $0.p == "label" && $0.k == "text" }
    }

    /// The lines of the drawn words that are being typed: their run among
    /// the lines drawn — a Name may take several (2026-10-17) — or an empty
    /// run one past either end when they are not drawn yet; nil for all.
    private func typedLines(_ m: DiagramModel, _ t: DiagramTyping, lines: [String]) -> Range<Int>? {
        let count = { (s: String) -> Int in s.isEmpty ? 0 : s.components(separatedBy: "\n").count }
        switch t.what {
        case .text, .label, .sheet: return nil
        case .name, .note:
            let lamp = t.lamps.first.flatMap(m.el)
            if let label = m.el(t.el), m.isSharedLabel(label) {
                // Its words first, then the line under them.
                let named = max(lines.count - ((lamp.map(m.noteOf) ?? "").isEmpty ? 0 : 1), t.what == .name ? 1 : 0)
                return t.what == .name ? 0..<min(max(named, 1), lines.count) : min(named, lines.count)..<lines.count
            }
            // Any piece's own Note: the lines under its name, or a new one.
            if t.own {
                let note = count(lamp?.caption ?? "")
                return note == 0 ? lines.count..<lines.count : max(lines.count - note, 0)..<lines.count
            }
            let first = lamp?.label_lines?.first ?? lamp?.lamp_name ?? ""
            let n = min(count(first), lines.count)
            if t.what == .name { return 0..<n }
            return n..<lines.count
        }
    }

    /// What the plan draws while words are typed: the typed line left out,
    /// the rest where it was.
    func typingShape(_ s: DiagramShape) -> DiagramShape? {
        guard let m = model, let t = m.typing, s.e == t.el, s.k == "text", let typed = typedShape(m, t),
              typed.p == s.p, typed.x == s.x, typed.y == s.y else { return s }
        let lines = (s.tx ?? "").components(separatedBy: "\n")
        guard let run = typedLines(m, t, lines: lines) else { return nil }
        guard !run.isEmpty else { return s }
        var out = s
        var kept = lines
        for i in run where i < kept.count { kept[i] = "" }
        out.tx = kept.joined(separator: "\n")
        return out
    }

    /// The typist put there, or taken away, as the model says.
    func syncTypist() {
        guard let m = model else { return }
        guard let t = m.typing else {
            if let typist {
                self.typist = nil
                typist.finish = nil
                if window?.firstResponder === typist { window?.makeFirstResponder(self) }
                typist.removeFromSuperview()
            }
            needsDisplay = true
            return
        }
        if let typist, typist.identifier?.rawValue == "\(t.el)|\(t.what.rawValue)" { return }
        typist?.removeFromSuperview()
        let v = DiagramTypist.make()
        v.identifier = NSUserInterfaceItemIdentifier("\(t.el)|\(t.what.rawValue)")
        v.isRichText = false
        v.importsGraphics = false
        v.allowsUndo = true
        v.isAutomaticQuoteSubstitutionEnabled = false
        v.isAutomaticDashSubstitutionEnabled = false
        v.isAutomaticTextReplacementEnabled = false
        v.isAutomaticSpellingCorrectionEnabled = false
        v.isContinuousSpellCheckingEnabled = false
        v.textContainerInset = .zero
        v.textContainer?.lineFragmentPadding = 0
        v.textContainer?.widthTracksTextView = false
        v.textContainer?.containerSize = CGSize(width: 4000, height: 4000)
        v.isHorizontallyResizable = true
        v.isVerticallyResizable = true
        v.focusRingType = .none
        v.multiline = t.what != .sheet
        v.caps = m.settings.caps
        // A lamp's Name: the light library under it as he types.
        if t.what == .name, !t.lamps.isEmpty, !t.frame { v.suggestions = DiagramMarks.names(m) }
        v.string = t.start
        v.finish = { [weak m] keep in m?.endTyping(keep: keep) }
        // The bar shows the words as they are typed.
        v.changed = { [weak m] words in if m?.typing != nil { m?.typed = words } }
        typist = v
        addSubview(v)
        placeTypist()
        window?.makeFirstResponder(v)
        v.selectAll(nil)
        needsDisplay = true
    }

    /// Laid over the words, in their type: called as the plan is drawn, so
    /// it follows a zoom or a pan.
    func placeTypist() {
        guard let m = model, let t = m.typing, let v = typist else { return }
        if t.what == .sheet { placeSheetTypist(m, t, v); return }
        let size = bounds.size
        let T = m.transform(size: size)
        let shrink = CGFloat(m.namesShrink)
        let shape = typedShape(m, t)
        let lines = (shape?.tx ?? "").components(separatedBy: "\n").filter { _ in shape != nil }
        let index = typedLines(m, t, lines: lines)?.lowerBound
        var pt: CGFloat = 10 * shrink
        var anchor = "middle"
        var at: CGPoint
        var ink = DiagramInk.color("ink", dark: dark) ?? .labelColor
        if let s = shape, let x = s.x, let y = s.y {
            let fixed = s.fx ?? true
            pt = fixed ? CGFloat(s.sz ?? 10) * shrink : CGFloat(s.sz ?? 0.3) * m.scale
            anchor = s.an ?? "middle"
            at = CGPoint(x: x, y: y).applying(T)
            let font = NSFont.systemFont(ofSize: max(pt, 6))
            let lineH = font.ascender - font.descender + font.leading
            let total = lineH * CGFloat(max(lines.count, 1))
            let top = at.y - total / 2
            if let i = index {
                at.y = top + CGFloat(i) * lineH
                if i >= 1 { ink = DiagramInk.color(s.f2, dark: dark) ?? DiagramInk.color("ink2", dark: dark) ?? ink }
                else { ink = DiagramInk.color(s.f, dark: dark) ?? ink }
            } else {
                at.y = top
                ink = DiagramInk.color(s.f, dark: dark) ?? ink
            }
        } else if let e = m.el(t.el) {
            // Nothing drawn yet: where its name goes, just under it.
            let now = e.at(beat: m.beat)
            let p = m.toView(CGPoint(x: now.x, y: now.y), size: size)
            if ["text", "note"].contains(e.kind) {
                // As the plan draws Words (`render::words_drawn_pt`).
                pt = CGFloat((DiagramTyping.isLarge(e.size) ? 12.5 : 10) * (m.page?.words ?? 1)) * shrink
                at = CGPoint(x: p.x, y: p.y - pt * 0.6)
            } else {
                let reach = DiagramMarks.isLamp(e, m) ? 10 : CGFloat(max(e.w, e.h) / 2) * m.scale
                at = CGPoint(x: p.x, y: p.y + reach + 8)
                if t.what == .note, !(e.lamp_name ?? "").isEmpty { at.y += pt * 1.2 }
            }
        } else {
            return
        }
        let font = NSFont.systemFont(ofSize: max(pt, 6), weight: .regular)
        if v.font != font { v.font = font }
        v.textColor = ink
        v.insertionPointColor = ink
        v.drawsBackground = true
        v.backgroundColor = m.lit(DiagramInk.color("paper", dark: dark)!)
        v.typingAttributes = [.font: font, .foregroundColor: ink, .ligature: 0]
        v.alignment = anchor == "start" ? .left : anchor == "end" ? .right : .center
        v.anchor = anchor
        v.spot = at
        v.fit()
    }
}
