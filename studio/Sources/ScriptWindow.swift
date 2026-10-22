import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// **The whole script, in a window of its own.**
///
/// His ask, 2026-08-22: *"on the script subtab, there should be an option to
/// just read the whole script if I desire, like a button, rather than going
/// scene by scene. It shouldn't be extremely prominent, more like a circle icon
/// in the top right."*
///
/// A window rather than the panel, for the panel's own reason turned around: the
/// panel is narrow because it sits beside the shot list, and a screenplay read
/// at 60 characters across a 320pt column is a screenplay read through a
/// letterbox. This is the same pages, given room — and it can live on the second
/// monitor while the list is worked on the first.
final class ScriptWindow: NSObject, NSWindowDelegate {
    static let shared = ScriptWindow()

    /// **Preview first, this second.** His call, 2026-08-22: the button should
    /// open the actual script file rather than our drawing of it — Preview is
    /// better at reading a PDF than we will ever be, and it is the app his hands
    /// already know.
    ///
    /// A revision taken in before revisions kept their pages has no file to
    /// open, and for those this window is still the only way to read the
    /// script. So the button is never dead: the real thing when there is one,
    /// ours when there is not.
    static func read(state: ShellState, scene: String?) {
        guard let engine = state.engine,
              let latest = engine.revisions().first(where: \.latest),
              let bytes = engine.scriptPDF(of: latest.id) else {
            shared.show(state: state, scene: scene)
            return
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shotlister-scripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Named after the revision, so two drafts open as two documents rather
        // than replacing each other in Preview's window.
        let safe = latest.name.replacingOccurrences(of: "/", with: "-")
        let file = dir.appendingPathComponent("\(safe).pdf")
        do {
            try bytes.write(to: file)
        } catch {
            shared.show(state: state, scene: scene)
            return
        }
        if Launch.checking {
            FileHandle.standardError.write(Data((
                "script file: \"\(file.lastPathComponent)\"  bytes \(bytes.count)\n").utf8))
            return
        }
        NSWorkspace.shared.open(file)
    }
    private var window: NSWindow?
    private var hosting: NSHostingView<WholeScript>?

    func show(state: ShellState, scene: String?) {
        let view = WholeScript(state: state, startAt: scene)
        if let hosting {
            hosting.rootView = view
        } else {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 860),
                styleMask: [.titled, .closable, .resizable, .miniaturizable,
                            .fullSizeContentView],
                backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 420, height: 400)
            w.delegate = self
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.identifier = NSUserInterfaceItemIdentifier("script")
            let host = NSHostingView(rootView: view)
            w.contentView = host
            hosting = host
            if !Launch.checking { w.setFrameAutosaveName("scriptWindow") }
            if let main = NSApp.windows.first(where: { $0.isVisible && $0 != w }) {
                main.addChildWindow(w, ordered: .above)
                if w.frame.origin == .zero { w.center() }
            }
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        hosting = nil
    }
}

/// Every page, one after another, with the scene you came from in view.
struct WholeScript: View {
    @ObservedObject var state: ShellState
    /// The scene to open on — where the panel was standing when the button was
    /// pressed. A reader that always starts at page one is a reader you have to
    /// scroll every time.
    var startAt: String?

    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    @State private var pages: ScriptPages?
    @State private var read = false
    /// Whether the latest draft kept the file it came from. False means this
    /// window is a fallback rather than a choice.
    @State private var noFileKept = false

    /// Re-read when a draft is taken in, and when any shot's screenplay lines
    /// change (a tie made in the panel, by Claude or on another device), the
    /// panel's own rule.
    private var reading: String {
        var hasher = Hasher()
        for row in state.view?.allRows ?? [] where !(row.playLines ?? []).isEmpty {
            hasher.combine(row.shot)
            hasher.combine(row.playLines ?? [])
        }
        return "\(state.scriptStamp)/\(hasher.finalize())"
    }

    /// The shot the panel follows (the cursor's, else the first picked), so
    /// its lines wear the accent here too.
    private var followed: String? {
        let rows = state.view?.allRows ?? []
        if let id = state.cursorShot, let row = rows.first(where: { $0.id == id }) { return row.shot }
        if let id = state.wholeShots.first, let row = rows.first(where: { $0.id == id }) { return row.shot }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            bar
            Group {
                if let pages, !pages.pageList.isEmpty {
                    paper(pages)
                } else if read {
                    nothing
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Brand.desk(dark))
        .task(id: reading) {
            pages = state.engine?.scriptPages()
            read = true
            noFileKept = state.engine
                .flatMap { engine in
                    engine.revisions().first(where: \.latest)
                        .map { engine.scriptPDF(of: $0.id) == nil }
                } ?? false
            guard Launch.checking else { return }
            let marks: String = pages.map { ScriptMarks(pages: $0, followed: followed).said } ?? ""
            var said = "script window: pages \(pages?.pages ?? 0)"
            said += "  scenes \(pages?.scenes.count ?? 0)"
            said += "  opening \(startAt ?? "none")"
            said += "  noFileKept \(noFileKept)"
            said += "  marks \(marks)\n"
            FileHandle.standardError.write(Data(said.utf8))
        }
    }

    /// **The draft as every app labels it** (stage 5 step 4, piece C):
    /// `Halcyon Pink · Oct 12, 2026`.
    private var barTitle: String {
        guard let pages else { return "Script" }
        if let one = state.engine?.revisions().first(where: { $0.id == pages.revision }) {
            return DraftLabel.label(name: one.name, cameFrom: one.filename, dated: one.importedAt)
        }
        return pages.name
    }

    private var bar: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: 68)
            Text(barTitle).sans(Brand.Size.title, weight: .semibold)
                .foregroundStyle(Brand.ink(dark))
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            // **Why this is our reader and not Preview** — Ref 271. He pressed
            // the button, got this window, and reasonably read that as the
            // Preview change not working. It is working; his drafts were taken
            // in before a revision kept the file it came from. Falling back
            // silently made a true thing look broken, so it says so — once, in
            // the bar, and only when there is genuinely no file.
            if noFileKept {
                Text("Imported before the file was kept")
                    .sans(11).foregroundStyle(Brand.ink3(dark))
                    .lineLimit(1).truncationMode(.tail)
                // **And a way out of it that is not re-importing.** Ref 271
                // said what was wrong and left him with the whole import sheet
                // as the only cure — his answer, plainly: it still doesn't
                // open in Preview. The file is on his disk; this hands it to
                // the draft and opens it, and every press after this one goes
                // straight to Preview.
                Button("Choose File…") { choose() }
                    .buttonStyle(.capsule)
            }
            if let pages {
                Text(pages.pages == 1 ? "1 page" : "\(pages.pages) pages")
                    .sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Brand.surface2(dark))
        .hairline(.bottom, Brand.rule(dark))
    }

    /// The PDF this draft was read from, handed over by him. Nothing else can
    /// supply it: a draft taken in before revisions kept their pages threw the
    /// file away, and we do not invent one.
    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.message = "The PDF this draft was read from"
        panel.prompt = "Keep"
        guard panel.runModal() == .OK, let url = panel.url,
              let bytes = try? Data(contentsOf: url),
              let engine = state.engine,
              let latest = engine.revisions().first(where: \.latest) else { return }
        engine.keepScriptPDF(of: latest.id, bytes: bytes)
        state.scriptStamp += 1
        ScriptWindow.read(state: state, scene: startAt)
    }

    /// **Real pages on a desk.** The engine has already decided what row and
    /// what indent every line sits at, so this places and paints and measures
    /// nothing — the same rule the panel follows, at a size somebody can read.
    private func paper(_ pages: ScriptPages) -> some View {
        let marks = ScriptMarks(pages: pages, followed: followed)
        return ScrollViewReader { hand in
            ScrollView {
                VStack(spacing: 18) {
                    ForEach(pages.pageList) { page in
                        sheet(page, measure: pages.measure, marks: marks)
                            .id(anchor(of: page, in: pages))
                    }
                }
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
            }
            .onAppear {
                guard let startAt,
                      let extent = pages.scenes.first(where: { $0.label == startAt })
                else { return }
                hand.scrollTo("page-\(extent.startsOnPage)", anchor: .top)
            }
        }
    }

    /// A page is anchored by its number so the opening scroll can find it.
    private func anchor(of page: ScriptPages.Page, in pages: ScriptPages) -> String {
        "page-\(page.number)"
    }

    private func sheet(_ page: ScriptPages.Page, measure: Int, marks: ScriptMarks) -> some View {
        // 12pt Courier at 7.2pt a character is the standard; the page is as
        // wide as the measure plus its margins and no wider, so it reads the
        // way it prints however big the window is.
        let glyph: CGFloat = 7.2
        let width = CGFloat(measure) * glyph + 108 * 2
        let columns = marks.columns(page)
        let gutter = CGFloat(columns.count) * 5
        return ZStack(alignment: .topLeading) {
            ForEach(Array(page.lines.enumerated()), id: \.offset) { _, line in
                Text(marks.drawn(line, dark: dark, accent: Brand.accent(dark)))
                    .font(Brand.monoFont(12))
                    .foregroundStyle(line.added ? Brand.ink4(dark) : Brand.ink(dark))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(height: 16, alignment: .leading)
                    .offset(y: CGFloat(line.row) * 16)
            }
            // **Shot marks beside the lines** (Ref 1568): one bar per shot in
            // the margin, lit down every line it holds, and its number over
            // the line it starts on, the way the phone draws them. The
            // followed shot's wear the accent, as in the panel.
            ForEach(Array(columns.enumerated()), id: \.element) { index, shot in
                ForEach(marks.bars(shot, on: page), id: \.row) { bar in
                    Rectangle()
                        .fill(marks.tint(shot, dark: dark, accent: Brand.accent(dark)))
                        .frame(width: 3, height: CGFloat(bar.rows) * 16)
                        .offset(x: -(gutter + 8) + CGFloat(index) * 5, y: CGFloat(bar.row) * 16)
                }
            }
            ForEach(marks.starts(page), id: \.row) { start in
                HStack(spacing: 5) {
                    ForEach(start.shots, id: \.self) { shot in
                        Text(marks.number(shot)).mono(10, weight: .medium)
                            .foregroundStyle(marks.tint(shot, dark: dark, accent: Brand.accent(dark), label: true))
                    }
                }
                .lineLimit(1)
                .frame(width: 96, height: 16, alignment: .trailing)
                .offset(x: -(gutter + 8 + 96 + 6), y: CGFloat(start.row) * 16)
            }
        }
        .frame(width: width - 216, height: CGFloat(56) * 16, alignment: .topLeading)
        .padding(.horizontal, 108)
        .padding(.vertical, 40)
        .background(Brand.paper(dark))
        .overlay(alignment: .topTrailing) {
            Text("\(page.number).").mono(11)
                .foregroundStyle(Brand.ink4(dark))
                .padding(.top, 22).padding(.trailing, 40)
        }
        .shadow(color: .black.opacity(dark ? 0.5 : 0.18), radius: 8, y: 3)
    }

    private var nothing: some View {
        EmptyState(title: "No script yet")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// **Which shots hold which lines, drawn beside the page** (Ref 1568). Built
/// from the engine's `ties` and each line's `shots`; nothing here reads the
/// draft itself, and a draft with no ties draws exactly as it did before.
struct ScriptMarks {
    let ties: [ScriptPages.Tie]
    let lost: [ScriptPages.Lost]
    let followed: String?
    /// For each page number, the shots covering the last line before it.
    private let carried: [Int: Set<String>]

    init(pages: ScriptPages, followed: String?) {
        ties = pages.ties ?? []
        lost = pages.lost ?? []
        self.followed = followed
        let known = Set(ties.map(\.shot))
        var carried: [Int: Set<String>] = [:]
        var last: Set<String> = []
        for page in pages.pageList {
            carried[page.number] = last
            if let final = page.lines.last(where: { $0.from != nil }) {
                last = Set((final.shots ?? []).filter { known.contains($0) })
            }
        }
        self.carried = carried
    }

    func number(_ shot: String) -> String { ties.first { $0.shot == shot }?.number ?? "" }

    private func cover(_ line: ScriptPages.Line) -> [String] {
        let known = Set(ties.map(\.shot))
        return (line.shots ?? []).filter { known.contains($0) }
    }

    /// The shots marked on this page, one bar column each, in the order
    /// their lines first appear.
    func columns(_ page: ScriptPages.Page) -> [String] {
        var out: [String] = []
        for line in page.lines { for shot in cover(line) where !out.contains(shot) { out.append(shot) } }
        return out
    }

    struct Bar { let row: Int; let rows: Int }

    /// A shot's bar down the page: every line it holds, and the blank rows
    /// between two of its lines.
    func bars(_ shot: String, on page: ScriptPages.Page) -> [Bar] {
        var out: [Bar] = []
        var previous: ScriptPages.Line?
        for line in page.lines {
            guard cover(line).contains(shot) else { continue }
            if let previous, cover(previous).contains(shot), line.row > previous.row + 1 {
                out.append(Bar(row: previous.row + 1, rows: line.row - previous.row - 1))
            }
            out.append(Bar(row: line.row, rows: 1))
            previous = line
        }
        return out
    }

    struct Start { let row: Int; let shots: [String] }

    /// The shots whose stretch begins on a line: covering it, and not the
    /// line before it (a page's first line counts only when the last page's
    /// last line did not carry it).
    func starts(_ page: ScriptPages.Page) -> [Start] {
        var out: [Start] = []
        for (index, line) in page.lines.enumerated() {
            let earlier: Set<String> = index > 0 ? Set(cover(page.lines[index - 1])) : (carried[page.number] ?? [])
            let begin = cover(line).filter { !earlier.contains($0) }
            if !begin.isEmpty { out.append(Start(row: line.row, shots: begin)) }
        }
        return out
    }

    /// The panel's look: the followed shot in the accent, every other in ink.
    func tint(_ shot: String, dark: Bool, accent: Color, label: Bool = false) -> Color {
        if shot == followed { return accent }
        return label ? Brand.ink3(dark) : Brand.ink(dark).opacity(dark ? 0.35 : 0.3)
    }

    /// A line's words, the stretches held by a shot tinted as the panel
    /// tints them. Offsets are the draft's, as the engine reports them.
    func drawn(_ line: ScriptPages.Line, dark: Bool, accent: Color) -> AttributedString {
        let indent = String(repeating: " ", count: max(0, line.indent))
        var out = AttributedString(indent + line.text)
        guard let from = line.from, !ties.isEmpty else { return out }
        let text = line.text
        let count = text.utf16.count
        /// A draft offset (UTF-16, as the panel reads it) as a character count.
        func chars(_ units: Int) -> Int {
            text.distance(from: text.startIndex, to: text.utf16.index(text.utf16.startIndex, offsetBy: units))
        }
        func place(_ a: Int, _ b: Int, _ color: Color) {
            guard b > a, a >= 0, b <= count else { return }
            let skip = indent.count
            let start = out.index(out.startIndex, offsetByCharacters: skip + chars(a))
            let end = out.index(out.startIndex, offsetByCharacters: skip + chars(b))
            out[start..<end].backgroundColor = color
        }
        // Others first, the followed one on top.
        for tie in ties.sorted(by: { $0.shot != followed && $1.shot == followed }) {
            let color = tie.shot == followed
                ? Brand.accent(dark).opacity(dark ? 0.32 : 0.22)
                : Brand.ink(dark).opacity(dark ? 0.12 : 0.08)
            for span in tie.spans where span.count == 2 {
                place(max(span[0], from) - from, min(span[1], from + count) - from, color)
            }
        }
        return out
    }

    /// For a checking run: what is marked, in a line.
    var said: String {
        ties.map { tie in
            "\(tie.number)=" + tie.spans.compactMap { $0.count == 2 ? "\($0[0])-\($0[1])" : nil }.joined(separator: ",")
        }.joined(separator: " ")
        + (lost.isEmpty ? "" : "  lost " + lost.map { "\($0.number)(\($0.words.count))" }.joined(separator: " "))
    }
}
