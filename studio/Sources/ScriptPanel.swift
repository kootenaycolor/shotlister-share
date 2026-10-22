import SwiftUI
import AppKit

/// **The script beside the shot list, locked to the scene you are on.**
///
/// Ref 18, and the reason the side panel was built with three sections from the
/// start rather than one. What it draws is `scriptpages` — the screenplay laid
/// out as real pages, 55 lines of 12pt Courier, worked out by the engine.
/// **Nothing here measures anything**: every line arrives knowing which row of
/// the page it is on and how many characters in it starts, and this positions
/// and paints.
///
/// One scene at a time, not the whole draft scrolled to a place. Locked is the
/// point — the question a shot list asks of a script is always "what happens in
/// *this* scene", and a panel that can drift off it answers a different one.
struct ScriptPane: View {
    @ObservedObject var state: ShellState
    let scene: ViewModel.Scene
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    @State private var pages: ScriptPages?
    @State private var read = false
    private var commercial: Bool { state.view?.project.isCommercial ?? false }

    var body: some View {
        Group {
            if commercial {
                // **A commercial's script is an AV script**, or nothing. No
                // screenplay pages to lay out: the scene's own Video and Audio
                // are the script, and a pasted table is the way a whole one
                // arrives. `design/22-commercial.html`.
                avPane
            } else if let pages {
                VStack(spacing: 0) {
                    header(extent(in: pages))
                    if let extent = extent(in: pages) {
                        script(pages, extent)
                    } else {
                        // The project has a script; this scene is not in it. A
                        // scene added by hand, or one the last draft dropped.
                        missing("Not in the script")
                    }
                }
            } else if read {
                empty
            } else {
                Color.clear
            }
        }
        .background(Brand.paper(dark))
        // **Tell the table not to read clicks that land in here** — Ref 271.
        // The table watches the mouse through its own monitor, which sees the
        // whole window; without this, the button in the header below sorted
        // whichever column happened to be behind it.
        .background {
            GeometryReader { geo in
                let frame = geo.frame(in: .global)
                Color.clear
                    .onAppear { state.panelFrames["script"] = frame }
                    .onChange(of: frame) { _, now in state.panelFrames["script"] = now }
                    .onDisappear { state.panelFrames.removeValue(forKey: "script") }
            }
        }
        .task(id: key) { load() }
    }

    /// Re-read when the project takes a draft in, and not otherwise: laying out
    /// a whole screenplay is real work and the answer does not change while
    /// somebody is typing in the table.
    private var key: String { "\(state.scriptStamp)/\(state.projectPath?.path ?? "")/\(heldLines)" }

    /// Every shot's screenplay lines, as one fingerprint: a tie made here, by
    /// Claude or on another device lays the pages out again; typing in the
    /// table does not.
    private var heldLines: Int {
        var hasher = Hasher()
        for row in state.view?.allRows ?? [] where !(row.playLines ?? []).isEmpty {
            hasher.combine(row.shot)
            hasher.combine(row.playLines ?? [])
        }
        return hasher.finalize()
    }

    private func load() {
        pages = state.engine?.scriptPages()
        read = true
        guard Launch.checking else { return }
        FileHandle.standardError.write(Data((
            "script panel: scene \(scene.number)"
            + "  script \(pages != nil)"
            + "  lines \(pages.map { extract($0).count } ?? 0)\n").utf8))
    }

    private func extent(in pages: ScriptPages) -> ScriptPages.Extent? {
        pages.scenes.first { $0.label == scene.number }
    }

    // ---- the page -------------------------------------------------------

    /// The scene's own line, and the one way out of it.
    private func header(_ extent: ScriptPages.Extent?) -> some View {
        HStack(spacing: 8) {
            if let extent {
                Text(extent.label).sans(Brand.Size.small, weight: .semibold).monospacedDigit()
                    .foregroundStyle(Brand.ink(dark))
                Text(extent.length).sans(Brand.Size.tiny).foregroundStyle(Brand.ink3(dark))
            }
            // The shot a selection ties to.
            if let shot = followedShot {
                Text(shot.number).mono(11, weight: .medium)
                    .foregroundStyle(Brand.ink3(dark))
            }
            Spacer(minLength: 6)
            if let extent {
                Text("p. \(extent.startsOnPage)").sans(Brand.Size.tiny).monospacedDigit()
                    .foregroundStyle(Brand.ink3(dark))
            }
            // **Quiet, in the corner** — his ask: not prominent, a circle icon
            // in the top right. The panel is for the scene you are on; this is
            // for the once in a while you want the whole thing.
            ToolButton(icon: "book", size: 11, help: "Whole script") {
                ScriptWindow.read(state: state, scene: scene.number)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Brand.surface2(dark))
        .hairline(.bottom, Brand.rule(dark))
    }

    private func script(_ pages: ScriptPages, _ extent: ScriptPages.Extent) -> some View {
        GeometryReader { space in
            let page = FilmPage(lines: extract(pages))
            // **The type is sized to the page, not chosen.** A screenplay's
            // shape *is* its indents — a cue is a cue because it sits 22
            // characters in — so the whole measure has to fit the panel or
            // the shape is gone. A monospaced glyph advances about 0.6 of
            // its point size, which is where the arithmetic comes from.
            let widest = max(page.lines.map(\.width).max() ?? 60, 40)
            let size = min(13, max(6.5, (space.size.width - 56) / (CGFloat(widest) * 0.6)))
            // **Select words and they are the followed shot's** (Ref 1553),
            // the commercial's gesture on a film: every shot's lines tinted,
            // the followed shot's in the accent; a click on its lines lets
            // that stretch go.
            ScriptText(text: page.text, quotes: page.quotes(pages.ties ?? [], followed: followedShot?.shot),
                       dark: dark,
                       scrollTo: page.firstDrawn(of: followedShot?.shot, in: pages.ties ?? []),
                       onSelect: { pieces in tieLines(page, pieces, revision: pages.revision) },
                       onClick: { at in untieLines(page, at: at, revision: pages.revision, ties: pages.ties ?? []) },
                       page: size, faded: page.faded)
        }
    }

    /// The pane's text: this scene's lines as drawn, one to a row, and where
    /// each sits both in what is drawn and in the draft's text.
    struct FilmPage {
        let lines: [Drawn]
        let text: String
        /// `(drawn start, length, draft offset)` for every line of the writer's.
        let spans: [(Int, Int, Int)]
        let faded: [NSRange]

        init(lines: [Drawn]) {
            self.lines = lines
            var text = ""
            var spans: [(Int, Int, Int)] = []
            var faded: [NSRange] = []
            var at = 0
            for (index, line) in lines.enumerated() {
                if index > 0 { text += "\n"; at += 1 }
                let indent = line.text.utf16.count - line.words.utf16.count
                if let from = line.from {
                    spans.append((at + indent, line.words.utf16.count, from))
                }
                if line.faded { faded.append(NSRange(location: at, length: line.text.utf16.count)) }
                text += line.text
                at += line.text.utf16.count
            }
            self.text = text
            self.spans = spans
            self.faded = faded
        }

        /// A stretch of the draft, as ranges of what is drawn.
        func drawn(_ from: Int, _ to: Int) -> [(Int, Int)] {
            spans.compactMap { start, length, draft in
                let a = max(from, draft), b = min(to, draft + length)
                return b > a ? (start + a - draft, start + b - draft) : nil
            }
        }

        /// A selection of what is drawn, as one stretch of the draft.
        func draft(_ from: Int, _ to: Int) -> (Int, Int)? {
            let hit = spans.compactMap { start, length, draft -> (Int, Int)? in
                let a = max(from, start), b = min(to, start + length)
                return b > a ? (draft + a - start, draft + b - start) : nil
            }
            guard let first = hit.first, let last = hit.last else { return nil }
            return (first.0, last.1)
        }

        /// The draft offset under a drawn character, on a line's words.
        func draft(at: Int) -> Int? {
            spans.first { at >= $0.0 && at < $0.0 + $0.1 }.map { $0.2 + at - $0.0 }
        }

        func quotes(_ ties: [ScriptPages.Tie], followed: String?) -> [ScriptText.Quote] {
            ties.flatMap { tie in
                tie.spans.flatMap { span -> [ScriptText.Quote] in
                    guard span.count == 2 else { return [] }
                    return drawn(span[0], span[1]).map {
                        ScriptText.Quote(shot: tie.shot, number: tie.number, from: $0.0, to: $0.1,
                                         followed: tie.shot == followed)
                    }
                }
            }
        }

        func firstDrawn(of shot: String?, in ties: [ScriptPages.Tie]) -> Int? {
            guard let shot, let tie = ties.first(where: { $0.shot == shot }) else { return nil }
            return tie.spans.lazy.compactMap { $0.count == 2 ? drawn($0[0], $0[1]).first?.0 : nil }.first
        }
    }

    /// A selection on the page, tied to the followed shot (every picked
    /// shot's, when several are). Words it already holds are let go.
    private func tieLines(_ page: FilmPage, _ pieces: [(Int, Int)], revision: String) {
        guard let engine = state.engine, let first = pieces.first, let last = pieces.last,
              let stretch = page.draft(first.0, last.1) else { return }
        for row in targets {
            state.replace(engine.playTie(shot: row.shot, revision: revision, pieces: [stretch]))
            if Launch.checking {
                FileHandle.standardError.write(Data(("lines \(stretch.0)-\(stretch.1) for \(row.number): \(row.number) holds \(state.view?.allRows.first { $0.id == row.id }?.playLines ?? [])\n").utf8))
            }
        }
    }

    /// A click on one of the followed shot's lines lets that stretch go.
    private func untieLines(_ page: FilmPage, at: Int, revision: String, ties: [ScriptPages.Tie]) {
        guard let engine = state.engine, let spot = page.draft(at: at) else { return }
        for row in targets {
            let holds = ties.first { $0.shot == row.shot }?.spans.contains { $0.count == 2 && $0[0] <= spot && spot < $0[1] } ?? false
            guard holds else { continue }
            state.replace(engine.playUntie(shot: row.shot, revision: revision, at: spot))
            if Launch.checking {
                FileHandle.standardError.write(Data(("untied lines of \(row.number) at \(spot)\n").utf8))
            }
        }
    }

    struct Drawn {
        let text: String
        let width: Int
        /// The paginator's own words — `(MORE)`, `(CONT'D)` — greyed, because
        /// they are not the writer's and nobody should read them as dialogue.
        let faded: Bool
        /// The line's own words, without its indent, and where they start in
        /// the draft's text (none for a blank row or the paginator's words).
        var words: String = ""
        var from: Int? = nil
    }

    /// Every line of this scene, in order, with the blank lines the layout
    /// actually has between them.
    ///
    /// The gaps matter: a screenplay is mostly whitespace and it is what makes
    /// an action block read as separate from the cue under it. They are rebuilt
    /// from the row numbers rather than guessed at, so what is drawn here is
    /// the same page the engine paginated.
    private func extract(_ pages: ScriptPages) -> [Drawn] {
        var out: [Drawn] = []
        var lastPage = -1
        var lastRow = -1
        for page in pages.pageList {
            for line in page.lines where line.scene == scene.number {
                if lastPage == page.number, line.row > lastRow + 1 {
                    for _ in 0 ..< (line.row - lastRow - 1) {
                        out.append(Drawn(text: "", width: 0, faded: false))
                    }
                } else if lastPage != -1, lastPage != page.number {
                    out.append(Drawn(text: "", width: 0, faded: false))
                }
                let padded = String(repeating: " ", count: max(0, line.indent)) + line.text
                out.append(Drawn(text: padded, width: padded.count, faded: line.added,
                                 words: line.text, from: line.added ? nil : line.from))
                lastPage = page.number
                lastRow = line.row
            }
        }
        return out
    }

    // ---- a commercial's script: text, quoted by shots -----------------------

    /// **The script as text, and the current shot's stretch of it lit.** His
    /// ruling, 2026-09-19 night: *"I just want to be able to highlight text
    /// on the right side bar and assign that to a shot. Some things can
    /// overlap or have multiple shots per beat. So I just click and drag
    /// and that assigns that text to a shot."* One script at a time — the
    /// followed shot's, else the scene in view's section's. Every quoted
    /// stretch is tinted; the followed shot's in the accent; selecting text
    /// ties it to the followed shot (every picked shot, when several are).
    private var allScripts: [ViewModel.Script] { state.view?.scripts ?? [] }

    /// The shot the panel follows: the cursor's, else the first picked.
    private var followedShot: ViewModel.Row? {
        let rows = state.view?.allRows ?? []
        if let id = state.cursorShot, let row = rows.first(where: { $0.id == id }) { return row }
        if let id = state.wholeShots.first, let row = rows.first(where: { $0.id == id }) { return row }
        return nil
    }

    @State private var chosenSection: String?
    @State private var followedSection: String?

    private var sectionInView: String? {
        if let shot = followedShot, let of = shot.scriptOf, shot.scriptFrom != nil { return of }
        let inView = state.view?.scenes.first { $0.id == scene.id } ?? scene
        if let mine = inView.sequence, !mine.isEmpty, allScripts.contains(where: { $0.section == mine }) { return mine }
        return allScripts.first?.section
    }

    private var shownSection: String? { chosenSection ?? sectionInView }
    private var shownScript: ViewModel.Script? { allScripts.first { $0.section == (shownSection ?? "") } }

    /// Every stretch quoted in the shown script: `(shot number, from, to,
    /// followed)` — one for each of a shot's stretches.
    private var quotes: [ScriptText.Quote] {
        let section = shownSection ?? ""
        let followed = followedShot?.id
        return (state.view?.allRows ?? []).flatMap { row -> [ScriptText.Quote] in
            guard (row.scriptOf ?? "") == section else { return [] }
            return Self.spans(row).map {
                ScriptText.Quote(shot: row.id, number: row.number, from: $0.0, to: $0.1, followed: row.id == followed)
            }
        }
    }

    /// A shot's stretches: the engine's list, else the one it always had.
    static func spans(_ row: ViewModel.Row) -> [(Int, Int)] {
        if let all = row.scriptSpans, !all.isEmpty {
            return all.compactMap { $0.count == 2 && $0[1] > $0[0] ? ($0[0], $0[1]) : nil }
        }
        if let from = row.scriptFrom, let to = row.scriptTo, to > from { return [(from, to)] }
        return []
    }

    private var avPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if allScripts.count > 1 {
                    Dropdown(selection: Binding(
                        get: { shownSection ?? "" },
                        set: { chosenSection = $0 }
                    ), items: allScripts.map { script in
                        Dropdown.Item(script.section, sectionTitle(script.section) ?? "Film")
                    }, size: 11)
                } else {
                    Text(sectionTitle(shownSection) ?? "Script").sans(11, weight: .semibold)
                        .foregroundStyle(Brand.ink(dark))
                }
                if let shot = followedShot {
                    Text(shot.number).mono(11, weight: .medium)
                        .foregroundStyle(Brand.ink3(dark))
                    if shot.scriptFrom != nil {
                        Button("Untie") { untie(shot) }
                            .buttonStyle(.rowAction)
                            .focusEffectDisabled()
                    }
                }
                Spacer(minLength: 6)
                Button("Edit…") { state.settingsPage = .script; state.editingProject = true }
                    .buttonStyle(.capsule)
                    .disabled(state.engine == nil || state.view?.project.readOnly == true)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Brand.surface2(dark))
            .hairline(.bottom, Brand.rule(dark))
            .onChange(of: sectionInView) { _, now in
                if now != followedSection { followedSection = now; chosenSection = nil }
            }
            .onAppear { followedSection = sectionInView }

            if let script = shownScript, !script.text.isEmpty {
                if script.isAV {
                    // The two columns' heads, over the table's two halves.
                    HStack(spacing: 0) {
                        Text("Video").fieldLabel(dark).frame(maxWidth: .infinity, alignment: .leading)
                        Text("Audio").fieldLabel(dark).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, 23).padding(.trailing, 15).padding(.top, 8)
                }
                ScriptText(text: script.text, av: script.isAV, quotes: quotes, dark: dark,
                           scrollTo: followedShot.flatMap { $0.scriptFrom },
                           onSelect: { pieces in tieFollowed(pieces) },
                           onClick: { at in untieFollowed(at: at) })
            } else {
                EmptyState(title: "No script") {
                    Button("+ Paste Script…") { state.pastingScript = true }
                        .disabled(state.engine == nil)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func sectionTitle(_ id: String?) -> String? {
        guard let id, !id.isEmpty else { return allScripts.isEmpty ? nil : (allScripts.count > 1 ? "Film" : "Script") }
        return state.view?.sequences.first { $0.id == id }?.title
    }

    /// The shots a gesture in the script acts on: every picked one, else
    /// the cursor's.
    private var targets: [ViewModel.Row] {
        var ids = Array(state.wholeShots)
        if ids.isEmpty, let one = state.cursorShot { ids = [one] }
        let rows = state.view?.allRows ?? []
        return ids.compactMap { id in rows.first { $0.id == id } }
    }

    /// **The highlighter** (2026-10-05): a selection is added to the
    /// followed shot's stretches — every picked shot's, when several are
    /// picked — and selecting words it already holds lets them go. Lines
    /// far apart are one shot's by dragging each in turn. A checking run
    /// says what it did.
    ///
    /// A drag down one column of an AV script arrives in pieces, one per
    /// row, and is one gesture: all of it added, or all of it let go.
    private func tieFollowed(_ pieces: [(Int, Int)]) {
        guard let engine = state.engine, !pieces.isEmpty else { return }
        let section = shownSection.flatMap { $0.isEmpty ? nil : $0 }
        for row in targets {
            state.replace(engine.toggleTie(shot: row.shot, section: section, pieces: pieces))
            if Launch.checking {
                let said = pieces.map { "\($0.0)-\($0.1)" }.joined(separator: ",")
                FileHandle.standardError.write(Data(("selected \(said) for \(row.number)\n").utf8))
            }
        }
    }

    /// A click on one of the followed shot's stretches lets that one go.
    private func untieFollowed(at: Int) {
        guard let engine = state.engine else { return }
        let section = shownSection ?? ""
        for row in targets where (row.scriptOf ?? "") == section
            && Self.spans(row).contains(where: { $0.0 <= at && at < $0.1 }) {
            state.replace(engine.untie(shot: row.shot, at: at))
            if Launch.checking {
                FileHandle.standardError.write(Data(("untied \(row.number) at \(at)\n").utf8))
            }
        }
    }

    private func untie(_ row: ViewModel.Row) {
        guard let engine = state.engine else { return }
        state.replace(engine.tie(shot: row.shot, section: nil, from: 0, to: 0))
    }

    // ---- nothing to draw ------------------------------------------------

    /// One line and a "+ Verb" capsule, no icon — the empty state's one shape.
    private var empty: some View {
        EmptyState(title: "No script yet") {
            Button("+ Import script…") { ScriptImport.pick(state: state) }
                .disabled(state.engine == nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func missing(_ said: String) -> some View {
        EmptyState(title: said)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
