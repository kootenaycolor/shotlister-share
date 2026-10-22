import SwiftUI
import UIKit

/// **A commercial's script, on the phone: text, quoted by shots.**
///
/// His ruling, 2026-09-19 night: *"I just want to be able to highlight text on
/// the right side bar and assign that to a shot."* The Mac's side panel is an
/// `NSTextView` where a drag across the words ties them to the followed shot.
/// A phone has no cursor shot and no mouse-up, so the same gesture is two taps:
/// pick the shot along the top, select the words, and press *Tie* — in the
/// selection's own menu or in the bar. Every quoted stretch is tinted; the
/// followed shot's wears the accent; stretches may overlap, darker where they
/// do.
///
/// One script at a time — the followed shot's, else the scene in view's
/// section's, else the film's — with a picker when the film has several.
struct AVScriptPane: View {
    @EnvironmentObject private var session: Session
    /// The scene in view, which chooses the script and lists the shots.
    let scene: Engine.Scene
    /// The shot to follow when the pane opens, by row id.
    var following: String? = nil

    @State private var followed: String?
    @State private var chosenSection: String?
    @State private var selection: (from: Int, to: Int)?
    /// Bumped when a tie has been made from the bar, so the reader lets go
    /// of the selection — the tint says the rest.
    @State private var collapse = 0
    @State private var editing = false

    private var scripts: [Engine.AVScript] { session.scripts }
    private var rows: [Engine.Row] { session.rows(inScene: scene.id) }
    private var followedRow: Engine.Row? {
        guard let followed else { return nil }
        return rows.first { $0.id == followed } ?? session.groups.flatMap(\.rows).first { $0.id == followed }
    }

    /// The section whose script shows when nobody has picked one: the
    /// followed shot's, else the scene's, else the first the film has.
    private var sectionInView: String? {
        if let row = followedRow, let of = row.scriptOf, row.quotesScript { return of }
        let live = session.scene(scene.id) ?? scene
        if let mine = live.sequence, !mine.isEmpty, scripts.contains(where: { $0.section == mine }) { return mine }
        return scripts.first?.section
    }

    private var shownSection: String { chosenSection ?? sectionInView ?? "" }
    private var shownScript: Engine.AVScript? { scripts.first { $0.section == shownSection } }

    /// Every stretch quoted in the shown script — each of a shot's, when it
    /// holds several — the followed shot's marked.
    private var quotes: [ScriptReader.Quote] {
        session.groups.flatMap(\.rows).flatMap { row -> [ScriptReader.Quote] in
            guard (row.scriptOf ?? "") == shownSection else { return [] }
            return row.spans.map {
                ScriptReader.Quote(shot: row.id, from: $0.from, to: $0.to, followed: row.id == followed)
            }
        }
    }

    /// Does the followed shot already hold every word of the selection? Then
    /// the button lets them go instead of tying them.
    private var selectionHeld: Bool {
        guard let selection, let row = followedRow, (row.scriptOf ?? "") == shownSection,
              let text = shownScript?.text else { return false }
        let units = Array(text.utf16)
        let end = min(selection.to, units.count)
        guard end > selection.from else { return false }
        let words = (selection.from ..< end).filter {
            !Self.blank.contains(units[$0])
        }
        return !words.isEmpty && words.allSatisfy { at in row.spans.contains { $0.from <= at && at < $0.to } }
    }

    /// White space and an AV script's two marks — nothing a person reads.
    private static let blank: Set<UInt16> = [0x20, 0x09, 0x0a, 0x0d, 0xa0, 0x1d, 0x1e]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let script = shownScript, AVLayout.isAV(script.text) {
                AVTableReader(text: script.text, quotes: quotes,
                              scrollTo: followedRow?.scriptFrom,
                              tieLabel: tieLabel,
                              selection: selection,
                              collapse: collapse,
                              onSelection: { selection = $0 },
                              onTie: { from, to in tie(from: from, to: to) })
            } else if let script = shownScript, !script.text.isEmpty {
                ScriptReader(text: script.text, quotes: quotes,
                             scrollTo: followedRow?.scriptFrom,
                             tieLabel: tieLabel,
                             collapse: collapse,
                             onSelection: { selection = $0 },
                             onTie: { from, to in tie(from: from, to: to) })
            } else {
                ContentUnavailableView {
                    Label("No script", systemImage: "doc.plaintext")
                } actions: {
                    if !session.isReadOnly {
                        Button("Edit Script…") { editing = true }
                    }
                }
            }
        }
        .onAppear { followed = following ?? followed }
        .task { await checkTie() }
        .onChange(of: sectionInView) { _, _ in chosenSection = nil }
        .sheet(isPresented: $editing) {
            NavigationStack { ScriptEditView(section: shownSection, presented: true) }
                .environmentObject(session)
        }
    }

    // ---- the bar: which script, which shot, and the tie -------------------

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if scripts.count > 1 {
                    Menu {
                        ForEach(scripts) { script in
                            Button(sectionTitle(script.section)) { chosenSection = script.section }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(sectionTitle(shownSection))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(sectionInk(shownSection) ?? .primary)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text(sectionTitle(shownSection))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(sectionInk(shownSection) ?? .primary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let selection, let row = followedRow {
                    Button(selectionHeld ? "Untie from \(row.number)" : "Tie to \(row.number)") {
                        tie(from: selection.from, to: selection.to)
                    }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                } else if let row = followedRow, row.quotesScript {
                    Button("Untie") { session.untie(row) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                if !session.isReadOnly {
                    Button { editing = true } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("Edit Script")
                }
            }
            shotStrip
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    /// The scene's shots as a row to pick from — the phone's cursor. The
    /// followed one is filled; a shot that already quotes wears a dot.
    private var shotStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if rows.isEmpty {
                    Text("No shots").font(.kitLabel).foregroundStyle(.tertiary)
                }
                ForEach(rows) { row in
                    Button {
                        followed = (followed == row.id) ? nil : row.id
                        selection = nil
                    } label: {
                        HStack(spacing: 4) {
                            Text(row.number).font(.kitLabel.weight(.semibold).monospacedDigit())
                            if row.quotesScript {
                                Circle().fill(.tint).frame(width: 5, height: 5)
                            }
                        }
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        // `.tint`, never `Color.accentColor`: the film's own
                        // colour arrives through `.tint()` on the project
                        // view, and only the tint style follows it.
                        .background {
                            if followed == row.id {
                                Capsule().fill(.tint.opacity(0.22))
                            } else {
                                Capsule().fill(Color(.tertiarySystemFill))
                            }
                        }
                        .overlay {
                            if followed == row.id { Capsule().strokeBorder(.tint.opacity(0.6)) }
                        }
                        .foregroundStyle(followed == row.id ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var tieLabel: String? {
        guard let row = followedRow, !session.isReadOnly else { return nil }
        return selectionHeld ? "Untie from \(row.number)" : "Tie to \(row.number)"
    }

    private func sectionTitle(_ id: String) -> String {
        guard !id.isEmpty else { return scripts.count > 1 ? "Film" : "Script" }
        return session.sequences.first { $0.id == id }?.title ?? "Script"
    }

    private func sectionInk(_ id: String) -> Color? {
        session.tint(of: session.sequences.first { $0.id == id })
    }

    /// A checking door: `-AVTie <from>-<to>` selects those words of the
    /// script after two seconds, so the bar offers the tie, and makes it four
    /// seconds later — a simulator has no finger to drag with.
    private func checkTie() async {
        guard let asked = UserDefaults.standard.string(forKey: "AVTie") else { return }
        let ends = asked.split(separator: "-").compactMap { Int($0) }
        guard ends.count == 2 else { return }
        try? await Task.sleep(for: .seconds(2))
        selection = (ends[0], ends[1])
        try? await Task.sleep(for: .seconds(4))
        tie(from: ends[0], to: ends[1])
    }

    private func tie(from: Int, to: Int) {
        guard let row = followedRow, to > from else { return }
        session.tie(row, section: shownSection.isEmpty ? nil : shownSection, from: from, to: to)
        selection = nil
        collapse += 1
    }
}

// ------------------------------------------------------------- the reader

/// **A script as selectable text, with every quoted stretch tinted.** A real
/// `UITextView`, read-only and selectable, because selecting words is the
/// system's gesture and it does it better than anything drawn by hand. The
/// selection's own menu offers the tie, so the words are never covered by a
/// bar the thumb has to reach past.
struct ScriptReader: UIViewRepresentable {
    struct Quote: Equatable {
        let shot: String
        let from: Int
        let to: Int
        let followed: Bool
    }

    let text: String
    let quotes: [Quote]
    /// The UTF-16 offset to bring into view, when the followed shot has one.
    let scrollTo: Int?
    /// What the selection's menu says — nil when there is no shot to tie to.
    let tieLabel: String?
    /// Bumped by the pane when the selection has done its work.
    let collapse: Int
    /// The selection as it changes, as UTF-16 offsets; nil when it collapses.
    let onSelection: ((from: Int, to: Int)?) -> Void
    /// The tie, chosen from the selection's menu.
    let onTie: (Int, Int) -> Void

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ScriptReader
        var lastText = ""
        var lastQuotes: [Quote] = []
        var lastScroll: Int?
        var lastCollapse = 0
        var lastStyle: UIUserInterfaceStyle = .unspecified
        init(_ parent: ScriptReader) { self.parent = parent }

        func textViewDidChangeSelection(_ view: UITextView) {
            let range = view.selectedRange
            parent.onSelection(range.length > 0 ? (range.location, range.location + range.length) : nil)
        }

        func textView(_ view: UITextView, editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0, let label = parent.tieLabel else { return nil }
            let tie = UIAction(title: label, image: UIImage(systemName: "link")) { [weak view] _ in
                self.parent.onTie(range.location, range.location + range.length)
                view?.selectedRange = NSRange(location: range.location + range.length, length: 0)
            }
            let copy = suggestedActions.filter { ($0 as? UICommand)?.action == #selector(UIResponderStandardEditActions.copy(_:)) }
            return UIMenu(children: [tie] + copy)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = true
        view.alwaysBounceVertical = true
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 14, left: 10, bottom: 90, right: 10)
        view.delegate = context.coordinator
        view.attributedText = attributed(style: view.traitCollection.userInterfaceStyle)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        let c = context.coordinator
        let style = view.traitCollection.userInterfaceStyle
        if c.lastText != text || c.lastQuotes != quotes || c.lastStyle != style {
            let kept = view.selectedRange
            view.attributedText = attributed(style: style)
            if kept.location + kept.length <= (text as NSString).length { view.selectedRange = kept }
            c.lastText = text
            c.lastQuotes = quotes
            c.lastStyle = style
        }
        if let at = scrollTo, c.lastScroll != at, at <= (text as NSString).length {
            view.scrollRangeToVisible(NSRange(location: at, length: 0))
            c.lastScroll = at
        }
        if c.lastCollapse != collapse {
            c.lastCollapse = collapse
            let end = view.selectedRange.location + view.selectedRange.length
            view.selectedRange = NSRange(location: min(end, (text as NSString).length), length: 0)
        }
    }

    private func attributed(style: UIUserInterfaceStyle) -> NSAttributedString {
        let dark = style == .dark
        let out = NSMutableAttributedString(string: text)
        let whole = NSRange(location: 0, length: out.length)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 8
        out.addAttributes([
            .font: CellReader.font,
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph,
        ], range: whole)
        // Others first, the followed one on top.
        for quote in quotes.sorted(by: { !$0.followed && $1.followed }) {
            let from = max(0, min(quote.from, out.length))
            let to = max(from, min(quote.to, out.length))
            guard to > from else { continue }
            let range = NSRange(location: from, length: to - from)
            let tint = quote.followed
                ? UIColor.tintColor.withAlphaComponent(dark ? 0.34 : 0.24)
                : UIColor.label.withAlphaComponent(dark ? 0.14 : 0.09)
            out.addAttribute(.backgroundColor, value: tint, range: range)
        }
        return out
    }
}

// ------------------------------------------------------- an AV script's rows

/// **An AV script, cut into its rows** (`engine/src/quoting.rs`): one text, a
/// mark between a row's Video and its Audio (U+001D), another between rows
/// (U+001E). Drawn as it is, the marks are invisible and the two columns run
/// together into one paragraph, which is what TestFlight build 4 showed him
/// (Ref 1586). Every cell keeps where it sits in the whole text, in UTF-16
/// units, so a tie made in a cell is a tie in the script.
///
/// A plain script (no marks) is its paragraphs, one wide cell each.
enum AVLayout {
    static let cellUnit: UInt16 = 0x1d
    static let rowUnit: UInt16 = 0x1e

    struct Cell: Hashable {
        /// Where the cell sits in the whole text, in UTF-16 units.
        let from: Int
        let to: Int
        /// Its words: the marks inside it as line breaks, one unit for one,
        /// so an offset into this is an offset from `from`. Trailing blanks
        /// are dropped, which moves nothing before them.
        let text: String
    }

    struct Row: Identifiable, Hashable {
        let id: Int
        let video: Cell
        /// Nil for a plain script's paragraph, which is one wide cell.
        let audio: Cell?
        var from: Int { video.from }
        var to: Int { audio?.to ?? video.to }
        var isEmpty: Bool { video.text.isEmpty && (audio?.text.isEmpty ?? true) }
    }

    static func isAV(_ text: String) -> Bool { text.utf16.contains(cellUnit) }

    static func rows(_ text: String) -> [Row] {
        let whole = text as NSString
        let units = Array(text.utf16)
        func cell(_ a: Int, _ b: Int) -> Cell {
            let raw = whole.substring(with: NSRange(location: a, length: max(0, b - a))) as NSString
            let shown = raw.replacingOccurrences(of: "\u{1d}", with: "\n")
            var end = shown.endIndex
            while end > shown.startIndex, shown[shown.index(before: end)].isWhitespace { end = shown.index(before: end) }
            return Cell(from: a, to: b, text: String(shown[..<end]))
        }
        var out: [Row] = []
        var start = 0
        if isAV(text) {
            for at in 0 ... units.count where at == units.count || units[at] == rowUnit {
                if let mid = (start ..< at).first(where: { units[$0] == cellUnit }) {
                    out.append(Row(id: out.count, video: cell(start, mid), audio: cell(mid + 1, at)))
                } else {
                    out.append(Row(id: out.count, video: cell(start, at), audio: cell(at, at)))
                }
                start = at + 1
            }
            return out.filter { !$0.isEmpty }
        }
        for at in 0 ... units.count where at == units.count || units[at] == 0x0a {
            let made = cell(start, at)
            if !made.text.trimmingCharacters(in: .whitespaces).isEmpty {
                out.append(Row(id: out.count, video: made, audio: nil))
            }
            start = at + 1
        }
        return out
    }
}

/// **An AV script on the scene's screen**: Video beside Audio, a row at a
/// time, every cell a reader of its own so words can be selected and tied
/// the way the whole-text reader always allowed. A selection lives in one
/// cell; starting one in another lets the first go.
struct AVTableReader: View {
    let text: String
    let quotes: [ScriptReader.Quote]
    let scrollTo: Int?
    let tieLabel: String?
    let selection: (from: Int, to: Int)?
    let collapse: Int
    let onSelection: ((from: Int, to: Int)?) -> Void
    let onTie: (Int, Int) -> Void

    private var rows: [AVLayout.Row] { AVLayout.rows(text) }

    var body: some View {
        let rows = rows
        ScrollViewReader { reader in
            ScrollView {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 14) {
                        Kicker("Video")
                        Kicker("Audio")
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    ForEach(rows) { row in
                        Divider().padding(.leading, 14)
                        HStack(alignment: .top, spacing: 14) {
                            cellView(row.video)
                            if let audio = row.audio { cellView(audio) }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .id(row.id)
                    }
                }
                .card()
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 90)
            }
            .background(Style.page)
            .onAppear { go(reader, rows) }
            .onChange(of: scrollTo) { _, _ in go(reader, rows) }
        }
    }

    private func cellView(_ cell: AVLayout.Cell) -> some View {
        CellReader(cell: cell, quotes: quotes, tieLabel: tieLabel,
                   holds: selection.map { cell.from <= $0.from && $0.to <= cell.to } ?? false,
                   collapse: collapse,
                   onSelection: { picked in
                       if let picked {
                           onSelection(picked)
                       } else if let selection, cell.from <= selection.from, selection.to <= cell.to {
                           // Only the cell that holds the selection may let it go.
                           onSelection(nil)
                       }
                   },
                   onTie: onTie)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func go(_ reader: ScrollViewProxy, _ rows: [AVLayout.Row]) {
        guard let at = scrollTo, let row = rows.first(where: { $0.from <= at && at <= $0.to }) else { return }
        DispatchQueue.main.async { reader.scrollTo(row.id, anchor: .top) }
    }
}

/// One cell of an AV script: selectable words, sized to them, its quoted
/// stretches tinted the way the whole-text reader tints them.
struct CellReader: UIViewRepresentable {
    let cell: AVLayout.Cell
    let quotes: [ScriptReader.Quote]
    let tieLabel: String?
    /// Whether the pane's selection is in this cell; when it is not, any
    /// selection left here is let go.
    let holds: Bool
    let collapse: Int
    /// The selection in the whole script's offsets; nil when it collapses.
    let onSelection: ((from: Int, to: Int)?) -> Void
    let onTie: (Int, Int) -> Void

    static let font = UIFont.systemFont(ofSize: 15)

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CellReader
        var lastCell: AVLayout.Cell?
        var lastQuotes: [ScriptReader.Quote] = []
        var lastCollapse = 0
        var quiet = false
        init(_ parent: CellReader) { self.parent = parent }

        func textViewDidChangeSelection(_ view: UITextView) {
            guard !quiet else { return }
            let range = view.selectedRange
            let at = parent.cell.from
            parent.onSelection(range.length > 0 ? (at + range.location, at + range.location + range.length) : nil)
        }

        func textView(_ view: UITextView, editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0, let label = parent.tieLabel else { return nil }
            let at = parent.cell.from
            let tie = UIAction(title: label, image: UIImage(systemName: "link")) { [weak view] _ in
                self.parent.onTie(at + range.location, at + range.location + range.length)
                view?.selectedRange = NSRange(location: range.location + range.length, length: 0)
            }
            let copy = suggestedActions.filter { ($0 as? UICommand)?.action == #selector(UIResponderStandardEditActions.copy(_:)) }
            return UIMenu(children: [tie] + copy)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        view.textContainer.lineFragmentPadding = 4
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let c = context.coordinator
        c.parent = self
        if c.lastCell != cell || c.lastQuotes != quotes {
            c.quiet = true
            let kept = view.selectedRange
            view.attributedText = attributed()
            if kept.location + kept.length <= (cell.text as NSString).length { view.selectedRange = kept }
            c.quiet = false
            c.lastCell = cell
            c.lastQuotes = quotes
        }
        if (!holds || c.lastCollapse != collapse), view.selectedRange.length > 0 {
            c.quiet = true
            view.selectedRange = NSRange(location: view.selectedRange.location + view.selectedRange.length, length: 0)
            c.quiet = false
        }
        c.lastCollapse = collapse
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 160
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fit.height))
    }

    private func attributed() -> NSAttributedString {
        let out = NSMutableAttributedString(string: cell.text)
        let length = out.length
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        out.addAttributes([.font: Self.font, .foregroundColor: UIColor.label, .paragraphStyle: paragraph],
                          range: NSRange(location: 0, length: length))
        // Others first, the followed one on top — as `ScriptReader` does.
        for quote in quotes.sorted(by: { !$0.followed && $1.followed }) {
            let from = max(0, min(quote.from - cell.from, length))
            let to = max(from, min(quote.to - cell.from, length))
            guard to > from else { continue }
            let tint = quote.followed
                ? UIColor.tintColor.withAlphaComponent(0.26)
                : UIColor.label.withAlphaComponent(0.09)
            out.addAttribute(.backgroundColor, value: tint, range: NSRange(location: from, length: to - from))
        }
        return out
    }
}

// ------------------------------------------------------------- editing it

/// **The script as text, to paste and edit by hand** — the Mac's Project
/// Settings → Script, on the phone. One script per section, plain text,
/// nothing parsed. Save keeps every shot's tie whose words are still there
/// and says how many were lost.
struct ScriptEditView: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss

    @State var section: String = ""
    /// Whether this is its own sheet (from the script pane), which needs a
    /// Done of its own — pushed from Project Settings it has the back button.
    var presented: Bool = false
    @State private var text = ""
    @State private var said = ""
    @State private var naming = false
    @State private var newName = ""
    @State private var loaded = false

    private var held: String { session.scripts.first { $0.section == section }?.text ?? "" }
    private var dirty: Bool { text != held }
    private var quoting: Int {
        session.groups.flatMap(\.rows).filter { ($0.scriptOf ?? "") == section && $0.quotesScript }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Menu {
                    Button("Film") { section = "" }
                    ForEach(session.sequences) { run in
                        Button(run.title) { section = run.id }
                    }
                    Divider()
                    Button { newName = ""; naming = true } label: {
                        Label("New \(session.sequenceWord)…", systemImage: "plus")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(sectionTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(session.tint(of: session.sequences.first { $0.id == section }) ?? .primary)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Text(said.isEmpty ? "\(quoting) shot\(quoting == 1 ? "" : "s") quote this" : said)
                    .font(.kitLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
            Divider()
            TextEditor(text: $text)
                .font(.custom("Courier", size: 13))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Paste the script here")
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 14).padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
        }
        .navigationTitle("Script")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if dirty {
                    Button("Revert") { load() }
                } else if presented {
                    Button("Done") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(!dirty || session.isReadOnly)
            }
            // **Paste After** (the Mac's Paste Script): the clipboard's words
            // added after what the section already has.
            ToolbarItem(placement: .primaryAction) {
                Button("Paste After") {
                    guard let words = UIPasteboard.general.string,
                          !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { said = "Nothing to paste"; return }
                    if let edit = session.setScript(words, section: section.isEmpty ? nil : section, append: true) {
                        said = "Added" + (edit.lost > 0 ? " · \(edit.lost) lost" : "")
                    }
                    text = held
                }
                .disabled(dirty || session.isReadOnly)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if section.isEmpty, let first = session.scripts.first?.section { section = first }
            load()
        }
        .onChange(of: section) { _, _ in load() }
        .alert("New \(session.sequenceWord)", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                if let made = session.addSequence(named: newName) { section = made.id }
            }
        }
    }

    private var sectionTitle: String {
        guard !section.isEmpty else { return "Film" }
        return session.sequences.first { $0.id == section }?.title ?? "Film"
    }

    private func load() {
        text = held
        said = ""
    }

    private func save() {
        let edit = session.setScript(text, section: section.isEmpty ? nil : section)
        if let edit {
            said = edit.kept + edit.lost == 0 ? "Saved"
                : "Saved"
                  + (edit.lost > 0 ? " · \(edit.lost) lost" : "")
        }
        text = held
    }
}
