import SwiftUI
import PDFKit

/// **The whole script, on its own tab** — Ref 1541 Stage D,
/// `design/33-one-app.html` section 4. Not one scene's pages behind a button:
/// every page, top to bottom, laid out the way the engine lays out a printed
/// screenplay. Tap a shot's mark and its page opens.
///
/// **A shot that holds lines is marked beside them** (Ref 1553,
/// `engine/src/playties.rs`): a bar in its colour down the left of every line
/// it covers, and its number over the first. A shot that holds no lines in
/// this draft keeps its mark under the scene's heading, so every shot is
/// still a tap away. The engine says which lines; nothing here searches.
///
/// **A commercial's script is its AV scripts** (Ref 1586): every section's,
/// one after another in one scroll, each as Video beside Audio, its shots
/// marked the same way the screenplay's are.
struct WholeScriptView: View {
    @EnvironmentObject private var session: Session

    var body: some View {
        Group {
            if session.isCommercial {
                CommercialScript()
                    .leadingTitle("Script")
            } else {
                FilmScript()
                    .leadingTitle("Script")
            }
        }
        .navigationDestination(for: SceneShotsView.Opening.self) { opening in
            ShotDetailView(sceneId: opening.sceneId, heading: opening.heading,
                           showing: opening.rowId)
        }
    }
}

/// A film's screenplay, every page of it.
private struct FilmScript: View {
    @EnvironmentObject private var session: Session
    @AppStorage("script.shotLines") private var shotLines = true

    struct Revision: Decodable, Identifiable, Hashable {
        var id: String
        var name: String
        var latest: Bool
        var filename: String = ""
        var importedAt: String = ""

        /// `Halcyon Pink · Oct 12, 2026`, the same as every app (step 4 C).
        var label: String { DraftLabel.label(name: name, cameFrom: filename, dated: importedAt) }

        enum CodingKeys: String, CodingKey { case id, name, latest, filename, importedAt }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            latest = try c.decode(Bool.self, forKey: .latest)
            filename = try c.decodeIfPresent(String.self, forKey: .filename) ?? ""
            importedAt = try c.decodeIfPresent(String.self, forKey: .importedAt) ?? ""
        }
    }

    enum Reading {
        case waiting
        case missing(String)
        case read(Script)
    }

    @State private var reading: Reading = .waiting
    @State private var revisions: [Revision] = []
    @State private var renaming = false
    @State private var renamingDraft = ""
    @State private var chosen: String?
    @State private var jumping = false

    /// **Pages | PDF** (Ref 1587): the engine's own drawing of the script, or
    /// the file the draft came from, as the portal's Script page shows it.
    /// `-ScriptPDF 1` opens on the PDF, for checking.
    enum Mode: Hashable { case pages, pdf }
    enum Kept {
        case waiting
        case missing
        case ready(PDFDocument)
    }
    @State private var mode: Mode = UserDefaults.standard.bool(forKey: "ScriptPDF") ? .pdf : .pages
    /// Import Script (a PDF picked here, or the draft waiting in Drive).
    @State private var pickingPDF = false
    @State private var attachingPDF = false
    @State private var importing: ScriptFilePhone?
    @State private var fetching = false
    @State private var trouble: String?
    /// **Tie Lines**: the shot that tapped lines go to, while it is on.
    @State private var tying: Engine.Row?
    @ObservedObject private var cards = PhoneCards.shared
    @State private var kept: Kept = .waiting
    @State private var pageJump: Int?

    var body: some View {
        ScrollViewReader { reader in
            Group {
                if mode == .pdf {
                    pdfPane
                } else {
                    switch reading {
                    case .waiting:
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .missing(let why):
                        noScript(why)
                    case .read(let script):
                        pages(script)
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    GlassSegments(options: [(Mode.pages, "Pages"), (Mode.pdf, "PDF")],
                                  selection: $mode, compact: true)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                    driveBanner
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let tying {
                    HStack(spacing: 10) {
                        Text("Tie Lines · \(tying.number)")
                            .font(.system(size: Kit.Size.body, weight: .semibold))
                        Text("Tap a line").font(.system(size: Kit.Size.body)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Done") { self.tying = nil }
                            .font(.system(size: Kit.Size.body, weight: .semibold))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(.bar)
                    .padding(.bottom, 70)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { jumping = true } label: { Label("Scenes", systemImage: "list.number") }
                        .disabled(script == nil)
                }
                // **Display: how this screen looks** (`design/42-one-home`).
                // It was a ••• that held only this, and ••• elsewhere meant
                // the whole film.
                ToolbarItem(placement: .primaryAction) {
                    // **Which draft is open rides here too** (2026-10-09): with
                    // the film's name leading, a third button folded two of
                    // them into •••. Which draft is a choice about what you
                    // are looking at, which is what Display is.
                    Menu {
                        if revisions.count > 1 {
                            Picker("Draft", selection: Binding(
                                get: { chosen ?? revisions.first(where: \.latest)?.id ?? "" },
                                set: { chosen = $0 }
                            )) {
                                ForEach(revisions) { Text($0.label).tag($0.id) }
                            }
                            .pickerStyle(.menu)
                        }
                        Toggle(isOn: $shotLines) { Label("Shot Lines", systemImage: "text.line.first.and.arrowtriangle.forward") }
                        // **Tie a shot to the lines it covers** (the Mac's highlighter).
                        if script != nil, !session.isReadOnly {
                            Menu {
                                ForEach(session.shownScenes) { scene in
                                    let rows = session.rows(inScene: scene.id)
                                    if !rows.isEmpty {
                                        Section(scene.number + "  " + scene.heading) {
                                            ForEach(rows) { r in Button("\(r.number)  \(r.title)") { tying = r; shotLines = true } }
                                        }
                                    }
                                }
                            } label: { Label("Tie Lines…", systemImage: "highlighter") }
                        }
                        if !session.isReadOnly {
                            Button { pickingPDF = true } label: { Label("Import Script…", systemImage: "square.and.arrow.down") }
                        }
                        // **Rename a draft** (the Mac's Script settings).
                        if draftId != nil {
                            Button { renamingDraft = draftName; renaming = true } label: {
                                Label("Rename Draft…", systemImage: "pencil")
                            }
                        }
                    } label: {
                        Label("Display", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $jumping) {
                if let script {
                    ScriptSceneJump(script: script) { label in
                        jumping = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            if mode == .pdf {
                                pageJump = script.scenes?.first { $0.label == label }?.startsOnPage
                            } else {
                                withAnimation(.snappy) { reader.scrollTo("scene-\(label)", anchor: .top) }
                            }
                        }
                    }
                    .presentationDetents([.medium, .large])
                }
            }
        }
        .alert("Rename Draft", isPresented: $renaming) {
            TextField("Name", text: $renamingDraft)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let name = renamingDraft.trimmingCharacters(in: .whitespaces)
                guard let id = draftId, !name.isEmpty, let engine = session.engine else { return }
                _ = engine.raw("renamerevision", id, name)
                session.refresh()
                Task { await load() }
            }
        }
        .task(id: chosen) { await load() }
        .fileImporter(isPresented: $pickingPDF, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result { importing = ScriptFilePhone(url: url) }
        }
        .sheet(item: $importing) { file in
            ImportScriptPhone(file: file) { Task { await load() } }
                .environmentObject(session)
        }
        .alert(trouble ?? "", isPresented: Binding(get: { trouble != nil }, set: { if !$0 { trouble = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .task {
            // A checking door: `-ImportScript <path>` opens a PDF's import review.
            #if targetEnvironment(simulator)
            if let path = UserDefaults.standard.string(forKey: "ImportScript"), importing == nil {
                importing = ScriptFilePhone(url: URL(fileURLWithPath: path))
            }
            #endif
            await PhoneCards.shared.checkScript(film: Relay.projectId(at: session.folder.url),
                                                page: session.view?.project.consolePage ?? "")
        }
        .task(id: PDFWish(draft: mode == .pdf ? draftId : nil, settled: settled)) { await loadPDF() }
    }

    private func noScript(_ why: String) -> some View {
        ContentUnavailableView {
            Label("No Script", systemImage: "doc.plaintext")
        } description: {
            Text(why)
        } actions: {
            if !session.isReadOnly { Button("Import Script…") { pickingPDF = true } }
        }
    }

    // ---- a draft waiting in Drive (step 4 piece C) ----------------------------------

    @ViewBuilder private var driveBanner: some View {
        let relay = Relay.projectId(at: session.folder.url)
        let page = session.view?.project.consolePage ?? ""
        let _ = cards.stamp
        if let found = cards.draftChoices(film: relay, page: page) {
            banner(title: "Pick the current draft", detail: "\(found.choices.count) in Drive") {
                Menu(fetching ? "Getting It…" : "Pick…") {
                    ForEach(found.choices, id: \.file) { c in
                        Button(c.same == true ? "\(c.label) (in use)" : c.label) { pick(c, card: found.card) }
                    }
                }
                .disabled(fetching)
            }
        } else if let found = cards.draftInDrive(film: relay, page: page) {
            banner(title: "New draft in Drive", detail: found.waiting.label) {
                Button(fetching ? "Getting It…" : "Review…") { review(found.waiting, card: found.card) }
                    .disabled(fetching)
                    .accessibilityIdentifier("script.review.drive")
            }
        }
    }

    private func banner<A: View>(title: String, detail: String, @ViewBuilder action: () -> A) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text").foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: Kit.Size.body, weight: .semibold))
                Text(detail).font(.system(size: Kit.Size.label)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            action().font(.system(size: Kit.Size.body, weight: .semibold))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Style.card, in: RoundedRectangle(cornerRadius: Kit.Radius.card, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private func review(_ waiting: PhoneCards.ScriptCard.Waiting, card: PhoneCards.Card) {
        fetching = true
        Task {
            defer { fetching = false }
            guard let url = await PhoneCards.fetchDraft(project: card.id, waiting: waiting) else {
                trouble = "Couldn't get the draft from Drive."
                return
            }
            importing = ScriptFilePhone(url: url, drive: DriveDraftPhone(project: card.id, file: waiting.file, label: waiting.label))
        }
    }

    /// The draft in use already: the others go to `z-archive/`. Another: its review.
    private func pick(_ choice: PhoneCards.ScriptCard.Waiting, card: PhoneCards.Card) {
        guard choice.same == true else { return review(choice, card: card) }
        struct List: Decodable { var revisions: [R] }
        struct R: Decodable { var hash: String; var latest: Bool }
        let stem = session.engine.flatMap { try? JSONDecoder().decode(List.self, from: $0.raw("revisions")) }?
            .revisions.first { $0.latest }.map { String($0.hash.prefix(32)) } ?? ""
        Task {
            if await PhoneCards.scriptCall("\(card.id)/settle", method: "POST",
                                           json: ["stem": stem, "by": "studio", "file": choice.file]) == nil {
                trouble = "Couldn't update Drive."
            }
            await PhoneCards.shared.checkScript(film: Relay.projectId(at: session.folder.url),
                                                page: session.view?.project.consolePage ?? "")
        }
    }

    /// A tapped line: the shot being tied takes it, or lets it go if it holds it.
    private func tapped(_ line: Script.Line, in script: Script) {
        guard let row = tying, let from = line.from, let to = line.to, to > from, let engine = session.engine else { return }
        if (line.shots ?? []).contains(row.shot) {
            _ = engine.raw("playuntieat", row.shot, script.revision, String(from))
        } else {
            _ = engine.raw("playtie", row.shot, script.revision, String(from), String(to))
        }
        session.refresh()
        Task { await load() }
    }

    // ------------------------------------------------------------ the PDF

    struct PDFWish: Equatable {
        var draft: String?
        var settled: Bool
    }

    /// The draft being read: the one picked, else the latest.
    private var draftId: String? { chosen ?? revisions.first(where: \.latest)?.id }

    /// The pages have been asked for and answered, whichever way.
    private var settled: Bool {
        if case .waiting = reading { return false }
        return true
    }

    @ViewBuilder private var pdfPane: some View {
        switch kept {
        case .waiting:
            if case .missing(let why) = reading {
                noScript(why)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .missing:
            // **Attach the PDF** to a draft that came without one (the Mac's).
            ContentUnavailableView {
                Label("No PDF", systemImage: "doc.richtext")
            } actions: {
                if !session.isReadOnly, draftId != nil { Button("Attach PDF…") { attachingPDF = true } }
            }
            .fileImporter(isPresented: $attachingPDF, allowedContentTypes: [.pdf]) { result in
                guard case .success(let url) = result, let id = draftId, let engine = session.engine else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let bytes = try? Data(contentsOf: url), PDFDocument(data: bytes) != nil else { trouble = "That isn't a PDF."; return }
                _ = engine.raw("scriptpdf", id, bytes.base64EncodedString())
                Task { await loadPDF() }
            }

        case .ready(let document):
            ScriptPDFPane(document: document, jump: $pageJump)
        }
    }

    /// The draft's PDF, read and decoded off the main thread (Ref 1538): it
    /// is a whole file in base64 through the engine's one lock.
    private func loadPDF() async {
        guard mode == .pdf else { return }
        guard let engine = session.engine, let id = draftId else {
            kept = settled ? .missing : .waiting
            return
        }
        kept = .waiting
        let data: Data? = await Task.detached(priority: .userInitiated) {
            struct Bytes: Decodable { var data: String }
            guard let bytes = try? JSONDecoder().decode(Bytes.self, from: engine.raw("scriptpdf", id)),
                  !bytes.data.isEmpty else { return nil }
            return Data(base64Encoded: bytes.data)
        }.value
        if let data, let document = PDFDocument(data: data) {
            kept = .ready(document)
        } else {
            kept = .missing
        }
    }

    private var script: Script? {
        if case .read(let script) = reading { return script }
        return nil
    }

    private var draftName: String {
        let id = chosen ?? revisions.first(where: \.latest)?.id
        return revisions.first { $0.id == id }?.label ?? "Draft"
    }

    /// The pages, read off the main thread: the whole screenplay is the
    /// biggest thing the engine hands over, and the engine's one lock is how
    /// the phone froze before (Ref 1538).
    private func load() async {
        guard let engine = session.engine else {
            reading = .missing("This project isn't open.")
            return
        }
        let wanted = chosen
        let (pagesData, listData) = await Task.detached(priority: .userInitiated) {
            let pages = wanted.map { engine.raw("scriptpages", $0) } ?? engine.raw("scriptpages")
            return (pages, engine.raw("revisions"))
        }.value
        struct List: Decodable { var revisions: [Revision] }
        if let list = try? JSONDecoder().decode(List.self, from: listData) {
            revisions = list.revisions
            // A checking door: `-ScriptDraft <n>` opens on the nth draft in
            // the picker's order, counting from 0.
            if chosen == nil, UserDefaults.standard.object(forKey: "ScriptDraft") != nil {
                let at = UserDefaults.standard.integer(forKey: "ScriptDraft")
                if at > 0, at < list.revisions.count { chosen = list.revisions[at].id }
            }
        }
        struct Problem: Decodable { var error: String }
        if let problem = try? JSONDecoder().decode(Problem.self, from: pagesData) {
            reading = .missing(problem.error)
        } else if let read = try? JSONDecoder().decode(Script.self, from: pagesData) {
            reading = .read(read)
        } else {
            reading = .missing("Can't read the script")
        }
    }

    private func pages(_ script: Script) -> some View {
        GeometryReader { space in
            // Sized so the engine's measure fits the width, exactly as one
            // scene's pages are (`ScenePages`): the engine has already wrapped
            // every line, and wrapping again would lose the shape.
            let marks = ShotMarks(script: script, session: session, on: shotLines)
            let em = (space.size.width - 48 - marks.gutter) / CGFloat(max(script.measure, 40))
            let size = min(14, max(7, em / 0.6))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(script.pageList, id: \.number) { page in
                        ScriptSheet(page: page, size: size, shotLines: shotLines, marks: marks,
                                    tying: tying?.shot, tap: { tapped($0, in: script) })
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .background(Style.page)
        }
    }
}

/// A draft's own PDF: native, pinch to zoom, with where you are.
private struct ScriptPDFPane: View {
    let document: PDFDocument
    @Binding var jump: Int?
    @State private var page = 1

    var body: some View {
        ZStack(alignment: .bottom) {
            ScriptPDFKit(document: document, jump: $jump, page: $page)
            Text("\(page) of \(document.pageCount)")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassCapsule()
                .padding(.bottom, 12)
                .allowsHitTesting(false)
        }
        .task {
            // A checking door: `-ScriptPDFPage <n>` opens on page n.
            let n = UserDefaults.standard.integer(forKey: "ScriptPDFPage")
            guard n > 0 else { return }
            try? await Task.sleep(for: .seconds(1))
            jump = n
        }
    }
}

private struct ScriptPDFKit: UIViewRepresentable {
    let document: PDFDocument
    @Binding var jump: Int?
    @Binding var page: Int

    func makeCoordinator() -> Coordinator { Coordinator(page: $page) }

    func makeUIView(context: Context) -> PDFView {
        let view = FitPDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.maxScaleFactor = 5
        view.backgroundColor = UIColor(Style.page)
        view.document = document
        for name in [Notification.Name.PDFViewPageChanged, .PDFViewVisiblePagesChanged] {
            NotificationCenter.default.addObserver(
                context.coordinator, selector: #selector(Coordinator.changed(_:)),
                name: name, object: view)
        }
        DispatchQueue.main.async { context.coordinator.report(view) }
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
        if let n = jump {
            if let target = document.page(at: n - 1) { view.go(to: target) }
            DispatchQueue.main.async { jump = nil }
        }
    }

    /// A PDF view laid out before it has a width keeps its first scale, so
    /// the page came up a third too wide. Fit it to the width whenever the
    /// width changes; a pinch in between is left alone.
    final class FitPDFView: PDFView {
        private var fittedWidth: CGFloat = 0
        override func layoutSubviews() {
            super.layoutSubviews()
            guard document != nil, bounds.width > 0, abs(bounds.width - fittedWidth) > 1 else { return }
            fittedWidth = bounds.width
            let fit = scaleFactorForSizeToFit
            if fit > 0 { minScaleFactor = fit; scaleFactor = fit }
        }
    }

    final class Coordinator: NSObject {
        let page: Binding<Int>
        init(page: Binding<Int>) { self.page = page }
        @objc func changed(_ note: Notification) {
            if let view = note.object as? PDFView { report(view) }
        }
        func report(_ view: PDFView) {
            guard let current = view.currentPage, let document = view.document else { return }
            page.wrappedValue = document.index(for: current) + 1
        }
    }
}

/// One printed page: its number, then its lines on the monospaced grid, the
/// blank rows between them kept.
private struct ScriptSheet: View {
    @EnvironmentObject private var session: Session
    let page: Script.Page
    let size: CGFloat
    let shotLines: Bool
    let marks: ShotMarks
    var tying: String? = nil
    var tap: (Script.Line) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Page \(page.number)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(drawn.enumerated()), id: \.offset) { at, item in
                    switch item {
                    case .gap:
                        HStack(spacing: 0) {
                            marks.bars(columns, covering: gapCover(at))
                            Color.clear
                        }
                        .frame(height: size * 1.35)
                    case .line(let line):
                        // The marks of the shots whose lines start here, over
                        // the line they start on.
                        let starting = starts(at)
                        if !starting.isEmpty {
                            HStack(spacing: 0) {
                                marks.bars(columns, covering: Set(cover(previous(at))).intersection(cover(at)))
                                LineMarks(shots: starting, marks: marks)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(spacing: 0) {
                            marks.bars(columns, covering: Set(cover(at)))
                            // A heading wears its scene's number, the way a
                            // shooting script prints it.
                            Text(line.kind == "heading" && line.scene != nil
                                 ? "\(line.scene ?? "")  " + line.text
                                 : String(repeating: " ", count: max(0, line.indent)) + line.text)
                                .font(.system(size: size, weight: line.kind == "heading" ? .bold : .regular,
                                              design: .monospaced))
                                .foregroundStyle(line.added ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .frame(height: size * 1.35, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(tying != nil && (line.shots ?? []).contains(tying!) ? Color.accentColor.opacity(0.14) : .clear)
                        .contentShape(Rectangle())
                        .onTapGesture { if tying != nil { tap(line) } }
                        .id(line.kind == "heading" ? "scene-\(line.scene ?? "")" : "p\(page.number)r\(line.row)")
                        if shotLines, line.kind == "heading", let label = line.scene {
                            SceneShotMarks(label: label, tied: marks.tied)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Style.card,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    enum Item { case gap, line(Script.Line) }

    /// The shots marked on this page, one bar column each, in the order
    /// their lines first appear.
    private var columns: [String] {
        guard shotLines else { return [] }
        var out: [String] = []
        for line in page.lines {
            for shot in line.shots ?? [] where !out.contains(shot) && marks.knows(shot) { out.append(shot) }
        }
        return out
    }

    /// The shots covering the drawn item at `at`: a line's own; none for a gap.
    private func cover(_ at: Int) -> [String] {
        guard shotLines, at >= 0, at < drawn.count, case .line(let line) = drawn[at] else { return [] }
        return (line.shots ?? []).filter { marks.knows($0) }
    }

    /// A gap carries a bar when the lines either side of it both do.
    private func gapCover(_ at: Int) -> Set<String> {
        var before = at - 1, after = at + 1
        while before >= 0, case .gap = drawn[before] { before -= 1 }
        while after < drawn.count, case .gap = drawn[after] { after += 1 }
        return Set(cover(before)).intersection(cover(after))
    }

    /// The line drawn before `at`, gaps skipped; -1 when none on this page.
    private func previous(_ at: Int) -> Int {
        var before = at - 1
        while before >= 0, case .gap = drawn[before] { before -= 1 }
        return before
    }

    /// The shots whose stretch begins on the line at `at`: covering it, and
    /// not the line before it (gaps skipped; a page's first line counts as
    /// a start only when the last page's last line did not carry it).
    private func starts(_ at: Int) -> [String] {
        let before = previous(at)
        let earlier: Set<String> = before >= 0 ? Set(cover(before)) : marks.carried(into: page.number)
        return cover(at).filter { !earlier.contains($0) }
    }

    /// The page's lines with the empty rows between them rebuilt from the row
    /// numbers, the same way `Script.drawn(ofScene:)` does for one scene.
    private var drawn: [Item] {
        var out: [Item] = []
        var last = -1
        for line in page.lines {
            if last >= 0, line.row > last + 1 {
                out.append(contentsOf: Array(repeating: Item.gap, count: line.row - last - 1))
            }
            out.append(.line(line))
            last = line.row
        }
        return out
    }
}

/// **Which shot wears which mark, and where.** Built once per reading of the
/// script from the engine's `ties` and the shot list: a shot's tint is its
/// place among its scene's shots, the same tint its heading mark has always
/// worn.
struct ShotMarks {
    struct Mark {
        let shot: String
        let row: Engine.Row
        let sceneId: String
        let heading: String
        let tint: Color
    }

    static let tints: [Color] = [.orange, .blue, .green, .purple, .pink, .teal, .brown]

    /// Every shot with lines in this draft, by shot id.
    let byShot: [String: Mark]
    /// The same shots, by id, for the heading marks to leave out.
    var tied: Set<String> { Set(byShot.keys) }
    /// Room for the bars at the left of every line.
    let gutter: CGFloat
    /// For each page number, the shots covering the last line before it.
    private let carriedInto: [Int: Set<String>]

    @MainActor init(script: Script, session: Session, on: Bool) {
        var byShot: [String: Mark] = [:]
        if on {
            let wanted = Set((script.ties ?? []).map(\.shot))
            for scene in session.scenes {
                for (index, row) in session.rows(inScene: scene.id).enumerated()
                where wanted.contains(row.shot) && byShot[row.shot] == nil {
                    byShot[row.shot] = Mark(shot: row.shot, row: row, sceneId: scene.id, heading: scene.heading,
                                            tint: Self.tints[index % Self.tints.count])
                }
            }
        }
        self.byShot = byShot
        var most = 0
        var carried: [Int: Set<String>] = [:]
        var last: Set<String> = []
        for page in script.pageList {
            carried[page.number] = last
            var here: [String] = []
            for line in page.lines {
                for shot in line.shots ?? [] where byShot[shot] != nil && !here.contains(shot) { here.append(shot) }
            }
            most = max(most, here.count)
            if let final = page.lines.last(where: { $0.from != nil }) {
                last = Set((final.shots ?? []).filter { byShot[$0] != nil })
            }
        }
        carriedInto = carried
        gutter = most == 0 ? 0 : CGFloat(most) * 5 + 5
    }

    func knows(_ shot: String) -> Bool { byShot[shot] != nil }

    func carried(into page: Int) -> Set<String> { carriedInto[page] ?? [] }

    /// One bar per column, lit where the column's shot covers the line.
    func bars(_ columns: [String], covering: Set<String>) -> some View {
        HStack(spacing: 2) {
            ForEach(columns, id: \.self) { shot in
                Rectangle()
                    .fill(covering.contains(shot) ? (byShot[shot]?.tint ?? .clear) : .clear)
                    .frame(width: 3)
            }
        }
        .frame(width: gutter, alignment: .leading)
        .frame(maxHeight: .infinity)
    }
}

/// The marks of shots whose lines start on the next line: number and title
/// in the shot's tint, a tap away from its page.
private struct LineMarks: View {
    let shots: [String]
    let marks: ShotMarks

    var body: some View {
        Wrap(spacing: 5) {
            ForEach(shots, id: \.self) { shot in
                if let mark = marks.byShot[shot] {
                    NavigationLink(value: SceneShotsView.Opening(rowId: mark.row.id, sceneId: mark.sceneId,
                                                                 heading: mark.heading)) {
                        ShotChip(row: mark.row, tint: mark.tint)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

/// A shot's number, and its title when it has one, in its tint.
private struct ShotChip: View {
    let row: Engine.Row
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Text(row.number).font(.kitLabel.weight(.heavy))
            if !row.title.isEmpty {
                Text(row.title).font(.kitLabel).lineLimit(1)
                    .frame(maxWidth: 230, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .strikethrough(row.struck)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(tint)
        .background(tint.opacity(0.13), in: Capsule())
    }
}

/// A scene's shots that hold no lines in this draft, as marks under its
/// heading: each one's number in a tint, a tap away from its page.
private struct SceneShotMarks: View {
    @EnvironmentObject private var session: Session
    let label: String
    var tied: Set<String> = []

    var body: some View {
        if let scene = session.scenes.first(where: { $0.number == label }) {
            let rows = Array(session.rows(inScene: scene.id).enumerated()).filter { !tied.contains($0.element.shot) }
            if !rows.isEmpty {
                Wrap(spacing: 5) {
                    ForEach(rows, id: \.element.id) { index, row in
                        let tint = ShotMarks.tints[index % ShotMarks.tints.count]
                        NavigationLink(value: SceneShotsView.Opening(rowId: row.id, sceneId: scene.id,
                                                                     heading: scene.heading)) {
                            ShotChip(row: row, tint: tint)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }
}

/// Every scene the script has, with the page it starts on.
private struct ScriptSceneJump: View {
    @Environment(\.dismiss) private var dismiss
    let script: Script
    let go: (String) -> Void

    var body: some View {
        NavigationStack {
            List(script.scenes ?? [], id: \.label) { scene in
                Button { go(scene.label) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(scene.label)
                            .font(.kitRow.weight(.bold).monospacedDigit())
                            .frame(minWidth: 30, alignment: .leading)
                        Text(scene.heading).lineLimit(2)
                        Spacer()
                        Text("p. \(scene.startsOnPage)")
                            .font(.kitLabel)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                }
            }
            .listStyle(.insetGrouped)
            .leadingTitle("Scenes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

// ------------------------------------------------------ a commercial's script

/// **Every script on a commercial, in one scroll** (Ref 1586). Until build 4
/// this tab showed one section's script, chosen by the film's first scene,
/// as one run-on paragraph with Video and Audio pressed together. Now each
/// section that has a script is a head in its own colour, as the shot list
/// heads it, and under it a table: Video beside Audio, a row a beat. A shot
/// that quotes the script wears a bar in its colour down the rows it holds
/// and its number over the row its words start in; the words themselves are
/// tinted. Tying is on the scene's screen, where the shots are.
private struct CommercialScript: View {
    @EnvironmentObject private var session: Session
    @AppStorage("script.shotLines") private var shotLines = true
    @State private var editing = false

    /// The film's own script first, then the sections' in the film's order.
    private var scripts: [Engine.AVScript] {
        let order = Dictionary(session.sequences.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        return session.scripts
            .filter { !AVLayout.rows($0.text).isEmpty }
            .sorted { (order[$0.section] ?? -1) < (order[$1.section] ?? -1) }
    }

    var body: some View {
        let scripts = scripts
        Group {
            if scripts.isEmpty {
                ContentUnavailableView {
                    Label("No Script", systemImage: "doc.plaintext")
                } actions: {
                    if !session.isReadOnly { Button("Edit Script…") { editing = true } }
                }
            } else {
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(scripts) { script in
                                AVScriptSection(script: script, headed: scripts.count > 1 || !script.section.isEmpty,
                                                marks: AVMarks(section: script.section, text: script.text,
                                                               session: session, on: shotLines))
                                    .id(script.id)
                            }
                        }
                        .padding(.bottom, 24)
                    }
                    .background(Style.page)
                    .task {
                        // A checking door: `-ScriptJump <n>` opens on the nth
                        // script, counting from 0.
                        let jump = UserDefaults.standard.integer(forKey: "ScriptJump")
                        guard jump > 0, jump < scripts.count else { return }
                        try? await Task.sleep(for: .seconds(1))
                        reader.scrollTo(scripts[jump].id, anchor: .top)
                    }
                }
            }
        }
        .toolbar {
            if !session.isReadOnly {
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = true } label: { Label("Edit Script", systemImage: "square.and.pencil") }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Toggle(isOn: $shotLines) { Label("Shot Lines", systemImage: "text.line.first.and.arrowtriangle.forward") }
                } label: {
                    Label("Display", systemImage: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack { ScriptEditView(section: scripts.first?.section ?? "", presented: true) }
                .environmentObject(session)
        }
    }
}

/// **Which shot wears which mark in one section's script.** A shot's tint is
/// its place among its scene's shots, as on the screenplay (`ShotMarks`).
/// Bars share a lane when their rows never meet, so a phone's margin holds
/// them.
struct AVMarks {
    struct Mark {
        let row: Engine.Row
        let sceneId: String
        let heading: String
        let tint: Color
        let spans: [(from: Int, to: Int)]
        let lane: Int
    }

    let rows: [AVLayout.Row]
    /// In the order their words first appear.
    let marks: [Mark]
    let lanes: Int
    var gutter: CGFloat { lanes == 0 ? 0 : CGFloat(lanes) * 5 + 6 }
    /// The whole script's reach: a stretch over all of it marks no words.
    private let whole: (from: Int, to: Int)

    @MainActor init(section: String, text: String, session: Session, on: Bool) {
        let rows = AVLayout.rows(text)
        self.rows = rows
        // To the last word, not the last mark: a tie over "everything" made
        // by dragging to the end usually stops short of trailing blanks.
        let last = rows.last.map { row in
            max(row.video.from + row.video.text.utf16.count,
                row.audio.map { $0.text.isEmpty ? 0 : $0.from + $0.text.utf16.count } ?? 0)
        }
        whole = (rows.first?.from ?? 0, last ?? 0)
        guard on else { marks = []; lanes = 0; return }
        var found: [(row: Engine.Row, sceneId: String, heading: String, tint: Color)] = []
        for scene in session.scenes {
            for (index, row) in session.rows(inScene: scene.id).enumerated()
            where (row.scriptOf ?? "") == section && row.quotesScript && !found.contains(where: { $0.row.id == row.id }) {
                found.append((row, scene.id, scene.heading, ShotMarks.tints[index % ShotMarks.tints.count]))
            }
        }
        func reach(_ spans: [(from: Int, to: Int)]) -> ClosedRange<Int>? {
            let hit = rows.indices.filter { at in spans.contains { $0.from < rows[at].to && rows[at].from < $0.to } }
            guard let first = hit.first, let last = hit.last else { return nil }
            return first ... last
        }
        let ordered = found.compactMap { item -> (item: (row: Engine.Row, sceneId: String, heading: String, tint: Color), reach: ClosedRange<Int>)? in
            reach(item.row.spans).map { (item, $0) }
        }
        .sorted { ($0.reach.lowerBound, $0.item.row.spans.map(\.from).min() ?? 0) < ($1.reach.lowerBound, $1.item.row.spans.map(\.from).min() ?? 0) }
        var laneEnds: [Int] = []
        var made: [Mark] = []
        for (item, reach) in ordered {
            let lane = laneEnds.firstIndex { $0 < reach.lowerBound } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(reach.upperBound) } else { laneEnds[lane] = reach.upperBound }
            made.append(Mark(row: item.row, sceneId: item.sceneId, heading: item.heading, tint: item.tint,
                             spans: item.row.spans, lane: lane))
        }
        marks = made
        lanes = laneEnds.count
    }

    /// The marks whose stretches touch this row.
    func covering(_ row: AVLayout.Row) -> [Mark] {
        marks.filter { $0.spans.contains { $0.from < row.to && row.from < $0.to } }
    }

    /// The marks with a stretch starting in this row (or carried into the
    /// first row it touches), for their numbers over it.
    func starting(_ row: AVLayout.Row) -> [Mark] {
        marks.filter { mark in
            mark.spans.contains { span in
                let start = rows.first { span.from < $0.to && $0.from < span.to }
                return start?.id == row.id
            }
        }
    }

    /// The tint behind each stretch of a cell's words: the shot holding the
    /// fewest words wins, so a small quote inside a long one still shows.
    func tinted(_ cell: AVLayout.Cell) -> AttributedString {
        var out = AttributedString(cell.text)
        let length = (cell.text as NSString).length
        let pieces = marks.flatMap { mark in mark.spans.map { (span: $0, tint: mark.tint) } }
            .filter { !($0.span.from <= whole.from && $0.span.to >= whole.to) }
            .sorted { ($0.span.to - $0.span.from) > ($1.span.to - $1.span.from) }
        for piece in pieces {
            let from = max(0, min(piece.span.from - cell.from, length))
            let to = max(from, min(piece.span.to - cell.from, length))
            guard to > from else { continue }
            let units = cell.text.utf16
            let a = String.Index(units.index(units.startIndex, offsetBy: from), within: cell.text)
            let b = String.Index(units.index(units.startIndex, offsetBy: to), within: cell.text)
            guard let a, let b, let lo = AttributedString.Index(a, within: out),
                  let hi = AttributedString.Index(b, within: out) else { continue }
            out[lo ..< hi].backgroundColor = piece.tint.opacity(0.2)
        }
        return out
    }

    func bars(_ covering: [Mark]) -> some View {
        let lit = Dictionary(covering.map { ($0.lane, $0.tint) }, uniquingKeysWith: { a, _ in a })
        return HStack(spacing: 2) {
            ForEach(0 ..< lanes, id: \.self) { lane in
                Rectangle().fill(lit[lane] ?? .clear).frame(width: 3)
            }
        }
        .frame(width: gutter, alignment: .leading)
        .frame(maxHeight: .infinity)
    }
}

/// One section's script: its name in its colour, then the table.
private struct AVScriptSection: View {
    @EnvironmentObject private var session: Session
    let script: Engine.AVScript
    let headed: Bool
    let marks: AVMarks

    private var section: Engine.Sequence? { session.sequences.first { $0.id == script.section } }
    private var isAV: Bool { AVLayout.isAV(script.text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if headed {
                Text(section?.title ?? "Film")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(session.tint(of: section) ?? .primary)
                    .lineLimit(2)
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 8)
            }
            VStack(alignment: .leading, spacing: 0) {
                if isAV {
                    HStack(alignment: .top, spacing: 12) {
                        Kicker("Video")
                        Kicker("Audio")
                    }
                    .padding(.leading, 12 + marks.gutter)
                    .padding(.trailing, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
                }
                ForEach(marks.rows) { row in
                    AVScriptRow(row: row, marks: marks, ruled: isAV)
                }
            }
            .padding(.bottom, 6)
            .card()
            .padding(.horizontal, 12)
            .padding(.top, headed ? 0 : 12)
        }
    }
}

/// One beat: the bars of the shots holding it, the numbers of the shots
/// starting in it, then Video beside Audio (or a plain script's paragraph).
private struct AVScriptRow: View {
    let row: AVLayout.Row
    let marks: AVMarks
    let ruled: Bool

    var body: some View {
        let covering = marks.covering(row)
        let starting = marks.starting(row)
        HStack(alignment: .top, spacing: 0) {
            marks.bars(covering)
                .padding(.leading, 6)
            VStack(alignment: .leading, spacing: 4) {
                if ruled { Divider() }
                if !starting.isEmpty {
                    Wrap(spacing: 5) {
                        ForEach(starting, id: \.row.id) { mark in
                            NavigationLink(value: SceneShotsView.Opening(rowId: mark.row.id, sceneId: mark.sceneId,
                                                                         heading: mark.heading)) {
                                ShotChip(row: mark.row, tint: mark.tint)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                }
                HStack(alignment: .top, spacing: 12) {
                    Text(marks.tinted(row.video))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    if let audio = row.audio {
                        Text(marks.tinted(audio))
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .font(.system(size: 15))
                .foregroundStyle(Color(.label))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
