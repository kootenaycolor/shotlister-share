import SwiftUI
import AppKit
import PDFKit

/// What a scene's own PDF can carry. Table, Storyboard and Document are the
/// three views this app already has; Script is the real imported pages —
/// sliced with PDFKit out of the file he actually gave the app, not redrawn
/// from the engine's own re-flowed text.
private enum ExportSection: String, CaseIterable, Identifiable {
    case table, storyboard, document, script
    /// **The Script page** — a commercial's script down the left, the shots
    /// that cover each stretch beside it, drawn by the engine like the other
    /// three. Offered only on a film that holds a script; the imported
    /// screenplay's pages (`script`) are the other kind of film's.
    case avscript
    /// **The overhead**, one sheet a scene — its plan and its shot key, drawn
    /// by the engine (`diagram::print`). Offered when a scene picked has one.
    case diagram

    var id: String { rawValue }

    var title: String {
        switch self {
        case .table: return "Table"
        case .storyboard: return "Storyboard"
        case .document: return "Document"
        case .script: return "Script"
        case .avscript: return "Script"
        case .diagram: return "Diagram"
        }
    }
}

/// What the whole-film dialog hands back: one file, or a folder with one per
/// shoot day. Not offered for a scene pick — that already says what it
/// covers.
private enum Delivery: String, CaseIterable, Identifiable {
    case wholeFilm, perDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wholeFilm: return "Whole film"
        case .perDay: return "Each day"
        }
    }
}

/// The export box: one scene's own PDF, or several picked at once, or the
/// whole film. A tab strip previews one section at a time; checkboxes say
/// which land in the one file that gets written.
///
/// **Lives in a window of its own, not a sheet** — his ruling, 2026-09-02. See
/// `ExportWindow`, which owns the frame and clears the flags on close.
struct ExportBox: View {
    @ObservedObject var state: ShellState
    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }

    /// Read from `state` rather than taken in, so the sheet's own `.sheet`
    /// binding in `Shell.swift` stays a plain `isPresented` — one fewer
    /// inline binding closure in a modifier chain that has already once
    /// pushed the type-checker past its budget.
    private var scenes: [ViewModel.Scene] {
        (state.view?.scenes ?? []).filter { state.exportingScenes.contains($0.id) }
    }

    /// **Loose plans picked**, by id, alongside scenes. A plan is only ever a
    /// Diagram page: it has no shots, no script and no table of its own.
    private var plans: [DiagramPlanItem] {
        let picked = Set(state.exportingScenes)
        guard !wholeProject, !picked.isEmpty else { return [] }
        return state.diagramPlans.filter { picked.contains($0.id) }
    }

    /// Only loose plans picked, so the Diagram page is the only page there is.
    private var plansOnly: Bool { scenes.isEmpty && !plans.isEmpty }

    /// **The whole film, rather than a pick.** Opened from the share button
    /// instead of a scene's own menu, and the difference reaches everything
    /// below: no scene narrowing on the engine call, a different title, a
    /// different filename, and a Script tab that covers the whole draft
    /// rather than a few scenes' pages.
    private var wholeProject: Bool { state.exportingWholeProject }

    /// What one view is asked for: the narrowing, and that view's own dials.
    ///
    /// The scene list is empty for the whole film — which is what "no scenes
    /// named" means to `print` and `xlsx` alike.
    ///
    /// **The widths only ride along with the table.** The engine drops them
    /// everywhere else, so sending them with a storyboard would be this box
    /// making a claim the page does not honour.
    private func scope(for section: ExportSection) -> Engine.ExportScope {
        let look = look(section)
        return Engine.ExportScope(
            scenes: wholeProject ? [] : scenes.map(\.id) + (section == .diagram ? plans.map(\.id) : []),
            columns: orderedColumns,
            scale: look.scale,
            frames: look.frames.rawValue,
            widths: section == .table && !tableAuto ? columnWidths : [:],
            // Auto's shares, exactly, while the table is on Auto.
            shares: section == .table && tableAuto ? (autoPlan?.shares ?? [:]) : [:],
            fitted: section == .table && tableAuto && autoPlan?.cut == 0,
            // **The order the file is really in** — the Document page's
            // corner used to say SCRIPT ORDER whatever the export did.
            order: orderCaption,
            extra: section == .diagram
                ? ["bar=\(diagramBar ? 1 : 0)", "dims=1", "cones=\(diagramCones ? 1 : 0)", "dark=\(diagramDark ? 1 : 0)",
                   "key=\(diagramKey ? 1 : 0)",
                   "orientation=\(look.orientation == .portrait ? "portrait" : "landscape")"]
                : [],
            narrowing: narrowing
        )
    }

    // ------------------------------------------------------ order and days

    /// **The Order, Filter and Days, as the engine and the name hear them**
    /// (`shared/ExportPresets.swift`, the same for the iPhone).
    private var choice: ExportChoice {
        ExportChoice(arrange: arrange, useFilter: useFilter, picked: selectedDays,
                     whole: wholeProject, info: info, label: Columns.label)
    }

    private var narrowing: [String] { choice.narrowing }
    private var allDayIds: Set<String> { choice.allDays }
    private var daysAreAll: Bool { choice.daysAreAll }
    private var tableSortName: String { choice.tableSortName }
    private var orderCaption: String { choice.caption }

    /// This view's look, or the standard one for it.
    private func look(_ section: ExportSection) -> Printing.Look {
        if section == .table, tableAuto, let plan = autoPlan { return plan.look }
        return looks[section] ?? Printing.Look.standard(for: section.rawValue)
    }

    /// One dial of one view's look, as something a control can drive.
    private func lookBinding<V>(
        _ section: ExportSection,
        _ path: WritableKeyPath<Printing.Look, V>
    ) -> Binding<V> {
        Binding(
            get: { look(section)[keyPath: path] },
            set: { now in
                if section == .table { takeOverFromAuto() }
                var current = look(section)
                current[keyPath: path] = now
                looks[section] = current
            }
        )
    }

    // ------------------------------------------------------------ remembering

    /// **Everything under one key**, so there is one thing to read, one thing
    /// to write and one thing for a battery to delete.
    ///
    /// **A checking run gets its own store.** The fixture a battery copies
    /// carries his real Daybreak's project id, so a shared key would mean
    /// every run read — and wrote — his actual export settings. The same
    /// split, for the same reason, as `Table.swift`'s column widths.
    private var storeKey: String { Launch.checking ? "export.checking" : "export" }

    /// Per-project entries live inside that one dictionary, under the film's
    /// own id: what belongs on a page is a fact about a film, not about him.
    private var filmKey: String { state.view?.project.id ?? "default" }

    /// **Writes go through `Remembering` unless this is a checking run**,
    /// which owns a disposable store of its own and may write to it — that is
    /// what lets a check prove a setting survives a relaunch without touching
    /// anything of his.
    private func keep(_ store: [String: Any]) {
        if Launch.checking {
            UserDefaults.standard.set(store, forKey: storeKey)
        } else {
            Remembering().set(store, forKey: storeKey)
        }
    }

    private var stored: [String: Any] {
        UserDefaults.standard.dictionary(forKey: storeKey) ?? [:]
    }

    /// How he left it. Called once, as the box opens.
    private func recall() {
        let store = stored
        if let names = store["included"] as? [String] {
            include = Set(names.compactMap(ExportSection.init(rawValue:)))
        }
        // The split is not restored: the box opens As in Table, one file.
        // **Once, the remembered tick is dropped.** The box remembered
        // `alsoWorkbook` as true from the day it opened on true, so changing
        // the default alone would have changed nothing he could see.
        if store["workbookOffByDefault"] as? Bool != true {
            var fresh = store
            fresh["alsoWorkbook"] = false
            fresh["workbookOffByDefault"] = true
            keep(fresh)
            alsoWorkbook = false
        } else if let also = store["alsoWorkbook"] as? Bool { alsoWorkbook = also }
        if let baked = store["flat"] as? Bool { flat = baked }
        if let auto = store["tableAuto"] as? Bool { tableAuto = auto }
        autoAsk = AutoAsk(size: store["autoSize"] as? Double ?? 1, paper: store["autoPaper"] as? String ?? "auto")
        if let page = store["diagram"] as? [String: Bool] {
            diagramBar = page["bar"] ?? diagramBar
            diagramCones = page["cones"] ?? diagramCones
            diagramDark = page["dark"] ?? diagramDark
            diagramKey = page["key"] ?? diagramKey
        }
        if let all = store["looks"] as? [String: [String: Any]] {
            for (name, one) in all {
                guard let section = ExportSection(rawValue: name) else { continue }
                var look = Printing.Look.standard(for: name)
                if let paper = one["orientation"] as? String,
                   let sheet = Printing.Orientation(rawValue: paper) { look.orientation = sheet }
                if let size = one["scale"] as? Double { look.scale = size }
                if let frames = one["frames"] as? String,
                   let picture = Printing.FrameSize(rawValue: frames) { look.frames = picture }
                looks[section] = look
            }
        }
        if let picked = (store["columns"] as? [String: [String]])?[filmKey] {
            includedColumns = Set(picked)
            // **A column the film has grown since this set was remembered
            // starts ticked.** The Script column arrived on 2026-09-19 and
            // every film's remembered set predated it, so it never printed
            // — his report: "script isn't properly rendering in the PDF".
            // What was *seen* when the set was kept says what is new.
            let seen = Set((store["seenColumns"] as? [String: [String]])?[filmKey] ?? picked)
            for column in availableColumns where column.visible && !seen.contains(column.name) {
                includedColumns.insert(column.name)
            }
        }
        if let dials = (store["widths"] as? [String: [String: Double]])?[filmKey] {
            columnWidths = dials
        }
    }

    /// **What he left is only kept if this film can use it.** The ticked pages
    /// and the split are remembered for every film at once, so a commercial's
    /// *Script* tick, or *Each day* from a film with a schedule, arrived in a
    /// film with neither — and Export… then made a save panel and no file, or
    /// a folder of nothing (his report, 2026-10-15: "it didn't go"). Pages the
    /// film cannot print are dropped, and if none are left it starts on the
    /// usual three; *Each day* needs a day to split by.
    private func sanitize() {
        let possible = Set(availableSections)
        include = include.filter { possible.contains($0) || $0 == .script }
        if !include.contains(where: { $0 != .script }) {
            include.formUnion([.table, .storyboard, .document])
        }
        // **A file per day is a Schedule's**, and needs a day to split by.
        if delivery == .perDay, !(wholeProject && arrange == .schedule) || info.days.isEmpty {
            delivery = .wholeFilm
        }
        if wholeProject, delivery == .perDay, selectedDays.isEmpty { selectedDays = allDayIds }
    }

    /// Nothing ticked that this film can actually draw.
    private var nothingToExport: Bool {
        includedSections.isEmpty && !(include.contains(.script) && scriptAvailable)
    }

    /// Called whenever anything changes. Cheap: one dictionary, one write.
    private func remember() {
        var store = stored
        // Opened from the Diagram, the box is narrowed to its one page; that
        // narrowing is not what the Share export should open on next time.
        if !state.exportJustDiagram {
            store["included"] = include.map(\.rawValue).sorted()
        }
        store["diagram"] = ["bar": diagramBar, "cones": diagramCones,
                            "dark": diagramDark, "key": diagramKey]
        store["delivery"] = delivery.rawValue
        store["alsoWorkbook"] = alsoWorkbook
        store["flat"] = flat
        store["tableAuto"] = tableAuto
        store["autoSize"] = autoAsk.size
        store["autoPaper"] = autoAsk.paper
        store["looks"] = looks.reduce(into: [String: [String: Any]]()) { out, pair in
            out[pair.key.rawValue] = [
                "orientation": pair.value.orientation.rawValue,
                "scale": pair.value.scale,
                "frames": pair.value.frames.rawValue,
            ]
        }
        var byFilm = store["columns"] as? [String: [String]] ?? [:]
        byFilm[filmKey] = includedColumns.sorted()
        store["columns"] = byFilm
        var seen = store["seenColumns"] as? [String: [String]] ?? [:]
        seen[filmKey] = availableColumns.map(\.name).sorted()
        store["seenColumns"] = seen
        var dials = store["widths"] as? [String: [String: Double]] ?? [:]
        dials[filmKey] = columnWidths
        store["widths"] = dials
        keep(store)
    }

    // ------------------------------------------------------------- presets

    /// The preset he is standing in, or nil for As in Table.
    private var presetInUse: ExportPreset? {
        presetId.isEmpty ? nil : presets.preset(presetId)
    }

    /// **Changed since the preset was picked** — "Edited", with Update
    /// Preset beside it.
    private var presetEdited: Bool {
        guard presetInUse != nil, let presetBase else { return false }
        return !current().sameSettings(as: presetBase)
    }

    /// **Everything on screen, as a preset.** Rules where a rule is what he
    /// meant: the Table's columns stay "as in Table" while they match it, and
    /// the days are a rule, never day ids.
    private func current() -> ExportPreset {
        var p = presetInUse ?? ExportPreset(id: "", name: "")
        p.arrange = arrange.rawValue
        p.filter = useFilter ? "table" : "none"
        p.filterWords = useFilter ? info.filter : []
        p.days = arrange == .schedule && wholeProject ? ExportDays.rule(for: selectedDays, in: info) : nil
        p.pages = ExportSection.allCases.filter { include.contains($0) }.map(\.rawValue)
        let visible = Set(availableColumns.filter(\.visible).map(\.name))
        if includedColumns == visible {
            p.columns = nil; p.columnsExcept = nil
        } else if let except = presetInUse?.columnsExcept, includedColumns == visible.subtracting(except) {
            p.columns = nil; p.columnsExcept = except
        } else {
            p.columns = orderedColumns; p.columnsExcept = nil
        }
        p.widths = columnWidths.filter { abs($0.value - 1) > 0.01 }
        p.auto = tableAuto
        p.autoAsk = autoAsk
        p.looks = looks.reduce(into: [String: ExportPreset.Dial]()) { out, pair in
            out[pair.key.rawValue] = ExportPreset.Dial(
                orientation: pair.value.orientation.rawValue, scale: pair.value.scale,
                frames: pair.value.frames.rawValue)
        }
        p.output = delivery == .perDay ? "perday" : "one"
        p.pattern = nameTyped ? patternFrom(typedName) : pattern
        p.fileKind = fileKind.wrappedValue
        p.workbook = alsoWorkbook
        return p
    }

    private func patternFrom(_ typed: String) -> String {
        ExportChoice.pattern(from: typed, project: projectSlug, ext: fileExtension)
    }

    /// **A preset, all at once, then one redraw.**
    private func applyPreset(_ p: ExportPreset) {
        presetId = p.id
        arrange = ExportArrange(rawValue: p.arrange) ?? .table
        useFilter = p.filter == "table"
        filterNotUsed = p.filter == "table" && !p.filterWords.isEmpty && info.filter.isEmpty
        selectedDays = p.days.map { ExportDays.pick($0, in: info) } ?? allDayIds
        let pages = Set(p.pages.compactMap(ExportSection.init(rawValue:)))
        include = pages.isEmpty ? [.table] : pages
        let visible = availableColumns.filter(\.visible).map(\.name)
        if let columns = p.columns {
            let known = Set(availableColumns.map(\.name))
            includedColumns = Set(columns.filter { known.contains($0) })
        } else {
            includedColumns = Set(visible).subtracting(p.columnsExcept ?? [])
        }
        columnWidths = p.widths
        tableAuto = p.auto
        autoAsk = p.autoAsk
        var fresh: [ExportSection: Printing.Look] = [:]
        for (raw, dial) in p.looks {
            guard let section = ExportSection(rawValue: raw) else { continue }
            var look = Printing.Look.standard(for: raw)
            if let sheet = Printing.Orientation(rawValue: dial.orientation) { look.orientation = sheet }
            look.scale = dial.scale
            if let frames = Printing.FrameSize(rawValue: dial.frames) { look.frames = frames }
            fresh[section] = look
        }
        looks = fresh
        delivery = p.output == "perday" && wholeProject && arrange == .schedule ? .perDay : .wholeFilm
        // A day's own file has no Shoot Day column (the split takes it off).
        if delivery == .perDay, p.columns == nil { includedColumns.remove("day") }
        pattern = p.pattern
        nameTyped = false
        typedName = ""
        fileKind.wrappedValue = p.fileKind
        alsoWorkbook = p.workbook
        sanitize()
        unfoldPicked()
        // What "Edited" compares against: the preset as it lands here.
        presetBase = current()
        remember()
        loadColumnWeights()
        schedulePreview()
    }

    /// **As in Table**: the Table's order and filter, every day, one file,
    /// the automatic name. Pages, columns and looks stay as he left them.
    private func asInTable() {
        presetId = ""
        presetBase = nil
        filterNotUsed = false
        arrange = .table
        useFilter = true
        selectedDays = allDayIds
        delivery = .wholeFilm
        pattern = nil
        nameTyped = false
        typedName = ""
        schedulePreview()
    }

    private func saveAsPreset(_ name: String) {
        var p = current()
        p.id = presets.named(name)?.id ?? ("p-" + UUID().uuidString.prefix(8).lowercased())
        p.name = name
        let kept = presets.save(p)
        presetId = kept.id
        presetBase = kept
    }

    private func updatePreset() {
        guard let inUse = presetInUse else { return }
        var p = current()
        p.id = inUse.id
        p.name = inUse.name
        presets.save(p)
        presetBase = p
    }

    /// Every view that is ticked *and* possible — Script drops out of a
    /// per-day export, which has no notion of whose pages are whose day.
    private var includedSections: [ExportSection] {
        ExportSection.allCases.filter { include.contains($0) && availableSections.contains($0) }
    }

    /// Which view he is looking at and tuning. **Not a place in a
    /// navigation** — the box has one screen now. His note, 2026-09-02: the
    /// summary screen beside the views "doesn't make any sense to me", and he
    /// was right; the four ticks lived in two places and neither looked like
    /// the master.
    @State private var pane: ExportSection = .table
    /// Renders already made, by everything they were made from.
    ///
    /// **A page costs the better part of a second** — measured: the engine
    /// answers in 1–2ms and WKWebView takes 560–1200ms. Flipping between two
    /// views redrew both, every time. This is the difference between a box
    /// that feels slow and one that does not.
    @State private var drawn: [String: PDFDocument] = [:]
    /// True once the box has finished opening. **Every setting written during
    /// `onAppear` fires its own `onChange`**, so opening used to draw the
    /// preview two and three times over before he had touched anything.
    @State private var opened = false
    /// What is being drawn right now, if anything.
    ///
    /// **The gate on `opened` is not enough on its own**: SwiftUI notices a
    /// change made during `onAppear` on the *next* pass, so the settings the
    /// box restores as it opens each fire after it has opened, and each booked
    /// a second draw of the page already being drawn. The cache cannot catch
    /// those — it is only filled when a render finishes, and these all start
    /// inside the first one's second.
    @State private var inFlight: String?
    /// The keyboard watch, so it can be taken down again.
    @State private var keyWatch: Any?
    @State private var include: Set<ExportSection> = [.table, .storyboard, .document]
    /// **Each view's own paper, text size and picture size.**
    ///
    /// One look per view rather than one for the export, because the three
    /// have never wanted the same page — and until 2026-09-02 a film exported
    /// as Table *and* Document could only be right about one of them.
    /// Anything not in here is the standard look for that view.
    @State private var looks: [ExportSection: Printing.Look] = [:]
    /// Which page of the preview is showing, so the bar under it can say
    /// where he is and walk him through.
    @State private var previewPage = 0
    /// The pending redraw. **Held so the next change can cancel it** — the
    /// width dials have no step, so a single drag used to fire an engine
    /// write, a web view load, a fixed 0.4s settle and a page slice on every
    /// tick of the mouse. Nothing cancelled; the results were merely thrown
    /// away at the end.
    @State private var previewWork: DispatchWorkItem?
    /// **Only meaningful for the whole film** — a scene's own pick already
    /// says what it covers. His ask, 2026-08-27: fold the folder-per-day
    /// export in here rather than leaving it a separate, unconfigurable menu
    /// item — one dialog for everything a PDF can be.
    @State private var delivery: Delivery = .wholeFilm
    /// A day's package once always meant a PDF and a workbook together
    /// (SL-377). **Off unless asked for** since 2026-09-16 — his instruction:
    /// *"The export spreadsheet feature should be off by default."*
    @State private var alsoWorkbook = false
    /// **Flat or editable** — his ask, 2026-09-16. Flat bakes every page
    /// into a picture (`Printing.flattened`), so nothing in the file can be
    /// selected or moved; editable is the PDF as it has always been.
    @State private var flat = false
    /// Which days `.perDay` actually writes — his ask, 2026-08-28: "By shoot
    /// day, and then I can select what days I want to export," rather than
    /// every day whether he wanted it or not. Starts full (every day, plus
    /// Unscheduled) the first time `.perDay` is picked, matching what the
    /// scope used to do unconditionally; he narrows from there.
    @State private var selectedDays: Set<String> = []
    /// Which fields print, and in what order — the project's own column
    /// order, same as the Table view, but picked separately: what belongs on
    /// screen and what belongs on a page are not always the same set.
    @State private var includedColumns: Set<String> = []
    // **100%, and 100% now means something** — his instruction, 2026-09-01:
    // *"default export size should be 100% and 100% should be what it looks
    // like in the document view within the app."* The engine's stylesheet
    // gives each page its own designed size at 1.0: the Document page is the
    // app's own points exactly, and the table and the storyboard keep the
    // 85% everybody was exporting them at anyway. The dial is a dial off
    // that, not off a raw 16 pixels — which is why it used to start at 85
    // and he still moved it every time.

    /// **How wide he wants each column of the printed table** — his ask,
    /// 2026-09-01: *"i would love to be able to adjust column sizes manually
    /// during export for table."*
    ///
    /// A multiplier on the weight the page already gives a column, not a
    /// width. That is what lets this dialog stay ignorant of the numbers: it
    /// asks the engine what each column is worth (`printedColumnWeights`) and
    /// only ever says "one and a half times that". One owner for the weights,
    /// no copy here to drift, and the page normalises at the end so the
    /// columns always add up to a sheet of paper.
    @State private var columnWidths: [String: Double] = [:]
    /// **Auto lays the table out** — his ask, 2026-10-15: *"an Auto mode
    /// that balances this best: it chooses landscape or portrait, all the
    /// column sizes, and the text size."* On by default. Touching any of
    /// the table's dials hands over to Manual starting from exactly the sheet
    /// Auto chose (`takeOverFromAuto`); one click on Auto returns.
    @State private var tableAuto = true
    /// **Auto's Size and paper** — his ask, 2026-10-16: *"one slider that
    /// makes the information small or larger … i can choose landscape or
    /// portrait for auto as well"*. Neither hands over to Manual; only a
    /// column's own width slider (or Manual itself) does.
    @State private var autoAsk = AutoAsk()
    /// What Auto decided, and for which narrowing and columns — a plan for
    /// another set of columns is a plan for a different table.
    @State private var autoPlan: Engine.TableLayout?
    @State private var autoPlanKey = ""
    /// The narrowing being decided right now, off the main thread.
    @State private var autoWorking = ""
    /// What the engine says each printed column is worth untouched, so the
    /// share can be shown live as he drags.
    @State private var baseWeights: [Engine.ColumnWeight] = []
    /// The real, paginated PDF for whichever tab is showing — not the raw
    /// HTML cropped to one page's height, which was never a real page at
    /// all: it never asked where a row break actually falls, so what showed
    /// was however much of the *first* row happened to fit in a box, not
    /// page one the way `Printing.pageBreaks` will actually cut it. His ask,
    /// 2026-08-24: "show a full letter page inside the preview." Rendering
    /// the same PDF the export makes is the only way that's actually true.
    @State private var previewDocument: PDFDocument?
    /// Guards against a slow render finishing after a newer one started —
    /// flip a tab twice quickly and the first, slower render would otherwise
    /// land last and show the wrong page.
    @State private var previewGeneration = 0
    @State private var scriptPreview: PDFDocument?
    @State private var exporting = false
    /// A redraw is in flight. Apart from `problem`, so a failure shows a
    /// reason instead of a wheel that never stops.
    @State private var rendering = false
    /// Which scenes have a plan, asked once as the box opens. It was asked
    /// on every redraw of the box — every tick of a slider — and with pages
    /// now written off the main thread, each ask could wait behind one.
    @State private var plannedScenes: Set<String>?
    /// The name box for a set-up, and what is typed in it.
    @State private var namingSetup = false
    @State private var setupNameTyped = ""
    @State private var problem: String?

    @State private var scriptBytes: Data?
    @State private var scriptPages: ScriptPages?
    /// The diagram page's own switches: Cadrage's Display Scale Bar, the
    /// lens cones, and the shot list under the
    /// plan (his ask, 2026-10-04: *"do I want to show the shot list next to
    /// it? Not always."*). No scale bar unless asked for: his call G on
    /// `design/32-diagram-paper.html`.
    @State private var diagramBar = false
    @State private var diagramKey = true
    @State private var diagramCones = true
    @State private var diagramDark = false
    @State private var scriptChecked = false
    /// **PNG instead of PDF**: each page a picture, which is what the
    /// Diagram's own Export… once made. Not remembered, so a picture asked
    /// for once does not become the Share export's habit.
    @State private var picture = false
    /// **The file-name field.** Until he types in it the field shows the
    /// automatic name, which follows every setting; once he has, it keeps his
    /// words exactly.
    @State private var typedName = ""
    @State private var nameTyped = false
    /// A preset's name pattern, `{project}-…-{date}`; nil is the automatic
    /// name.
    @State private var pattern: String?

    /// **The order the file is read in** — As in Table (its sort carried
    /// over), Script, or Schedule. His pick, 2026-10-15: As in Table first.
    @State private var arrange: ExportArrange = .table
    /// Whether the Table's filter comes with the export. Shown as one line
    /// so a short PDF is never a mystery.
    @State private var useFilter = true
    /// The Table's filter and sort, and every shoot day, from the engine.
    @State private var info: ExportInfo = .empty
    /// Days-list groups folded shut, by id.
    @State private var folded: Set<String> = []
    /// The last day clicked, for a shift-click range.
    @State private var anchorDay: String?
    @ObservedObject private var presets = ExportPresets.shared
    /// The preset picked, by id; empty is As in Table.
    @State private var presetId = ""
    /// The preset as it stood when picked, to tell "Edited".
    @State private var presetBase: ExportPreset?
    /// A preset's filter that this film's Table does not have.
    @State private var filterNotUsed = false
    @State private var managing = false

    /// The diagram switches as one value, so one watcher redraws for any.
    /// Wall lengths are the plan's own (View › Lengths, Back to Paper Batch
    /// 2): what the sheet on screen shows is what prints, so no switch here.
    private var diagramSwitches: [Bool] { [diagramBar, diagramCones, diagramDark, diagramKey] }

    /// PDF, Flat PDF or PNG, as one choice over `flat` and `picture`.
    private var fileKind: Binding<Int> {
        Binding(get: { picture ? 2 : (flat ? 1 : 0) },
                set: { picture = $0 == 2; if $0 != 2 { flat = $0 == 1 } })
    }

    /// Nothing to slice, nothing kept for it, or a day's page (which does not
    /// know which of its scenes' script pages belong to it) — the toggle
    /// stays off and disabled rather than pretending the section exists.
    private var scriptAvailable: Bool {
        scriptBytes != nil && scriptPages != nil && !(wholeProject && delivery == .perDay)
    }

    /// Every section this delivery can actually produce — Script drops out
    /// once the pick is "each day", whether or not a script is kept at all.
    private var availableSections: [ExportSection] {
        if plansOnly { return [.diagram] }
        let all = ExportSection.allCases.filter { ($0 != .avscript || hasAVScript) && ($0 != .diagram || hasDiagram) }
        guard wholeProject, delivery == .perDay else { return all }
        return all.filter { $0 != .script }
    }

    /// Whether the film holds a script of its own — the Script page's
    /// whole reason to exist. A film with an imported screenplay has the
    /// other Script item; a commercial has this one.
    private var hasAVScript: Bool {
        !(state.view?.scripts ?? []).isEmpty
    }

    /// Whether any scene this covers has a plan to print.
    private var hasDiagram: Bool {
        guard let engine = state.engine else { return false }
        if !plans.isEmpty { return true }
        let with = plannedScenes ?? Set(DiagramModel.scenesWithPlans(engine))
        if wholeProject { return !with.isEmpty }
        return scenes.contains { with.contains($0.id) }
    }

    /// The fields this can print, in the project's own order — every
    /// column, his own included, whether it is showing on screen right now
    /// or not.
    ///
    /// **His own columns print.** This list used to leave out every column
    /// with a `kind` (a project's own), on the word that the engine could not
    /// draw one — stale since the engine learned to (`Row.own`,
    /// `Sheet.own_columns`), so a column he added on set never reached the
    /// PDF. His report, 2026-10-06: "new columns aren't appearing in the
    /// exports for pdfs".
    private var availableColumns: [ViewModel.Column] {
        state.view?.columns ?? []
    }

    var body: some View {
        watching(frame)
    }

    /// The window's contents. **Kept apart from the pile of `onChange`
    /// handlers below it** — together they put the chain past the
    /// type-checker's budget, which this file has been over once before.
    private var frame: some View {
        VStack(spacing: 0) {
            header
            // **One surface, and only the page floats.** His ruling,
            // 2026-09-02, after two goes at this: the glass panels felt
            // "plopped on top of a black background and not integrated".
            //
            // He is right, and the reason is that glass only reads as glass
            // when there is something behind it to bend. The sidebar in
            // `Shell.swift` floats over the shot list, so it works. Here the
            // panels floated over flat ground, so all anybody saw was a
            // lighter rectangle with a hairline — a sticker, not a material.
            //
            // So nothing is a panel. The list and the settings sit straight on
            // the window, held apart by space. The one object in the room is
            // the paper, lying in a well cut into the surface — which is also
            // the only thing here anybody is actually looking at.
            HStack(spacing: 0) {
                rail.frame(width: 330)
                previewPane
                settingsPane.frame(width: 300)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 10)
            footer
        }
        // **A range, not a size.** The window is his to resize now, and a
        // fixed frame inside it would leave the box floating in a grey field.
        .frame(minWidth: 1040, idealWidth: 1220, maxWidth: .infinity,
               minHeight: 620, idealHeight: 760, maxHeight: .infinity)
        // **One background, all the way across** — the well's own colour, the
        // rule `Shell.swift` arrived at the hard way. A second tone behind the
        // panels is what makes glass read as "an awkward background separate
        // from the background underneath" rather than as glass laid over one.
        // The window's own ground, and the only tone it has. The well below
        // is cut *into* it, rather than laid on top of it.
        .background(Brand.panel(dark))
        .buttonStyle(.capsule)
        // **The bar starts at the top of the window, not below the title bar.**
        // Without this SwiftUI insets the content by the title bar's own
        // height, so a 44pt bar sat under 34pt of empty ground and the whole
        // top of the window read as wasted. `Shell.swift` does the same thing
        // for the same reason; this box simply never did.
        .ignoresSafeArea(.container, edges: .top)
    }

    /// Everything the box listens to. One place, and its own expression.
    private func watching<V: View>(_ view: V) -> some View {
        view
            .task { await loadScript() }
            .sheet(isPresented: $namingSetup) {
                NameSetup(name: $setupNameTyped) { saveAsPreset($0) }
            }
            .sheet(isPresented: $managing) {
                ManagePresets(store: presets)
            }
            .onAppear {
                info = state.engine?.exportInfo() ?? .empty
                selectedDays = allDayIds
                presets.refresh()
                if let engine = state.engine {
                    plannedScenes = Set(DiagramModel.scenesWithPlans(engine))
                }
                // **Before the defaults below**, so how he left it wins over what
                // the box would otherwise start on.
                recall()
                sanitize()
                if let opening = state.exportOpensOn {
                    pane = ExportSection(rawValue: opening) ?? .table
                }
                // From the Diagram's Export…: this plan's page and nothing else
                // ticked, standing on it. Every other page is still a tick away.
                if state.exportJustDiagram {
                    include = [.diagram]
                    pane = .diagram
                    // **What the sheet on screen shows is what prints**: the
                    // plan's own way round and scale bar (View › Sheet).
                    if let id = state.exportingScenes.first, let engine = state.engine,
                       let sheet = try? JSONDecoder().decode(DiagramPage.self, from: engine.call("diagramsheet", id)) {
                        var one = look(.diagram)
                        one.orientation = sheet.orientation == "portrait" ? .portrait : .landscape
                        looks[.diagram] = one
                        diagramBar = sheet.bar
                    }
                }
                // `--exportpaper table:portrait`, so a check can set a look and
                // then prove a second launch still has it. Written straight
                // through `remember`, the same road a click takes.
                if let said = state.exportPaperSaid {
                    let halves = said.split(separator: ":")
                    if halves.count == 2,
                       let section = ExportSection(rawValue: String(halves[0])),
                       let paper = Printing.Orientation(rawValue: String(halves[1])) {
                        // A paper said for the table is a manual choice.
                        if section == .table { tableAuto = false }
                        var one = look(section)
                        one.orientation = paper
                        looks[section] = one
                        remember()
                    }
                }
                // `--exportsetup save:Name` / `use:Name`, through the same doors the
                // menu uses. **After `--exportpaper`**, so a run can set a look
                // and then save that look, which is the order a person works in.
                if includedColumns.isEmpty {
                    includedColumns = Set(availableColumns.filter(\.visible).map(\.name))
                }
                // `--exportset arrange=schedule;days=12-18+22;output=perday;filter=none`
                // — the Order, Filter, Days and Output a click would set.
                // `--exportsetup use:Name` picks a preset *before* the
                // settings above are changed (so "Edited" can be seen);
                // `save:Name`, `update:` and `manage:` act after them.
                let setup = (state.exportSetupSaid ?? "").split(separator: ":", maxSplits: 1).map(String.init)
                if setup.count == 2, setup[0] == "use", let p = presets.named(setup[1]) { applyPreset(p) }
                if let said = state.exportSetSaid { setFromOutside(said) }
                if setup.count == 2 {
                    switch setup[0] {
                    case "save": saveAsPreset(setup[1])
                    case "manage": managing = true
                    case "update": updatePreset()
                    default: break
                    }
                }
                unfoldPicked()
                // **What the box is actually holding**, said out loud so a check
                // can assert it. The box could not be photographed until today and
                // could not be questioned either; this is the cheap half of that.
                if Launch.checking {
                    // Built up a piece at a time — one expression was too
                    // much for the type-checker under Xcode 27 (2026-09-20).
                    let sections = includedSections.map(\.rawValue).joined(separator: ",")
                    let papers = ExportSection.allCases.filter { $0 != .script }
                        .map { "\($0.rawValue)=\(look($0).orientation.rawValue)" }
                        .joined(separator: ",")
                    var box = "export box: columns \(availableColumns.count)"
                    box += " ticked \(includedColumns.count)"
                    box += " days \(info.days.count)"
                    box += " in \(sections)"
                    box += " preset \(presetInUse?.name ?? "none")"
                    box += " presets \(presets.list.count)"
                    box += " paper \(papers)"
                    box += " order \(arrange.rawValue)"
                    box += " picked \(ExportDays.summary(selectedDays, in: info))"
                    box += " caption \(orderCaption)"
                    box += " narrowing \(narrowing.joined(separator: "&"))"
                    box += " edited \(presetEdited ? "yes" : "no")"
                    box += " layout \(tableAuto ? "auto" : "manual")"
                    box += String(format: " size %.2f", autoAsk.size)
                    box += " autopaper \(autoAsk.paper)"
                    box += " name \(delivery == .perDay ? autoName + "/" : suggestedName())\n"
                    FileHandle.standardError.write(Data(box.utf8))
                }
                loadColumnWeights()
                // **Last, and once.** Everything above writes a setting, and every
                // setting fires a change; `opened` holds them all off until here.
                opened = true
                watchKeys()
                renderPreview()
                walkTheViews()
                turnPages()
                pressKeys()
                pressExport()
                dragSliders()
            }
            .onDisappear {
                if let keyWatch { NSEvent.removeMonitor(keyWatch) }
                keyWatch = nil
            }
            // Switching view is a click, not a drag — go at once, and usually
            // straight out of the shelf.
            .onChange(of: pane) { _, _ in previewPage = 0; renderPreview() }
            // **Ticking a view in or out changes the file, not this page.** It
            // used to redraw, which was most of a second spent on nothing.
            .onChange(of: include) { _, _ in remember() }
            .onChange(of: alsoWorkbook) { _, _ in remember() }
            .onChange(of: flat) { _, _ in remember() }
            .onChange(of: diagramSwitches) { _, _ in
                remember()
                if pane == .diagram { schedulePreview() }
            }
            .onChange(of: selectedDays) { _, _ in
                remember()
                if arrange == .schedule { schedulePreview() }
            }
            .onChange(of: arrange) { _, now in
                if now != .schedule, delivery == .perDay { delivery = .wholeFilm }
                if now == .schedule { unfoldPicked() }
                schedulePreview()
            }
            .onChange(of: useFilter) { _, _ in schedulePreview() }
            // Columns reach the table and the document page, and neither the
            // storyboard nor the script.
            .onChange(of: includedColumns) { _, _ in
                remember(); loadColumnWeights()
                if pane == .table || pane == .document { schedulePreview() }
            }
            // The picture column's own weight moves with the frames dial, so the
            // shares beside the sliders would be lying a moment later.
            // **Only when *this* view's look changed.** Turning the
            // storyboard portrait while standing on the table used to redraw
            // the table.
            .onChange(of: looks) { was, now in
                remember(); loadColumnWeights()
                if was[pane] != now[pane] { schedulePreview() }
            }
            .onChange(of: tableAuto) { _, _ in
                remember()
                if pane == .table { schedulePreview() }
            }
            .onChange(of: autoAsk) { _, _ in
                remember()
                if pane == .table, tableAuto { schedulePreview() }
            }
            // Widths reach the table alone.
            .onChange(of: columnWidths) { _, _ in
                remember()
                if pane == .table { schedulePreview() }
            }
            .onChange(of: delivery) { _, now in
                remember()
                guard now == .perDay else { return }
                // Neither belongs to "each day": Script has no notion of which
                // scenes are whose day, and the day itself already says which
                // day it is on every one of its own rows.
                include.remove(.script)
                includedColumns.remove("day")
                if pane == .script { pane = .table }
                // Starts full the first time — everything an unrestricted export
                // would have written — so switching to "Each day" costs nothing
                // by default; he narrows from there. A pick he already made
                // (switched away and back) is left exactly as he left it.
                if selectedDays.isEmpty {
                    selectedDays = allDayIds
                }
            }
    }

    private var header: some View {
        // The same bar every pop-out wears, so this window reads as one of
        // them rather than a sheet that escaped. It leaves room for the
        // traffic lights and claims the drag itself — the window has no title
        // bar of its own to be dragged by.
        PopoutBar(title: "Export", caption: subtitle, plain: true) { presetBar }
    }

    /// **Presets, at the top of the window** — his pick, 2026-10-15. The
    /// menu names the one in use; "Edited" and Update Preset appear once
    /// anything is changed after picking it.
    private var presetBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button { asInTable() } label: {
                    if presetInUse == nil { Label("As in Table", systemImage: "checkmark") } else { Text("As in Table") }
                }
                if !presets.list.isEmpty { Divider() }
                ForEach(presets.list) { p in
                    Button { applyPreset(p) } label: {
                        if p.id == presetId { Label(p.name, systemImage: "checkmark") } else { Text(p.name) }
                    }
                }
                Divider()
                Button("Save as Preset…") {
                    setupNameTyped = presetInUse?.name ?? ""
                    namingSetup = true
                }
                Button("Manage Presets…") { managing = true }
            } label: {
                HStack(spacing: 6) {
                    Text(presetInUse.map { "Preset: \($0.name)" } ?? "As in Table")
                        .sans(Brand.Size.body).foregroundStyle(Brand.ink(dark)).lineLimit(1)
                    if presetEdited {
                        Text("Edited").sans(Brand.Size.small).foregroundStyle(Brand.warn(dark))
                    }
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Brand.ink3(dark))
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
                    .fill(Brand.selectionQuiet(dark)))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .focusEffectDisabled()
            .fixedSize()
            if presetEdited {
                Button("Update Preset") { updatePreset() }
                    .buttonStyle(.rowAction)
            }
        }
    }

    /// Shut the window. **Not `dismiss`** — that is a sheet's word, and this
    /// has not been one since 2026-09-02.
    private func close() {
        ExportWindow.shared.close()
    }

    private var subtitle: String {
        if wholeProject {
            let title = state.view?.project.shownTitle ?? ""
            return title.isEmpty ? "The whole film" : title
        }
        if plansOnly { return plans.map(\.name).joined(separator: " · ") }
        if scenes.count == 1, let scene = scenes.first {
            return "Scene \(scene.number)" + (scene.heading.isEmpty ? "" : " · \(scene.heading)")
        }
        return "\(scenes.count) scenes — " + scenes.map(\.number).joined(separator: ", ")
    }

    /// **The four views, and which of them are in the file.** No headings
    /// over it: a list of four names does not need to be told it is a list of
    /// four names, and the two he had — *What* and *Look* — named nothing.
    ///
    /// **Fixed rows, not a `ForEach`.** `Segmented` is six hardcoded pills for
    /// a reason: a dynamic view list in window chrome was the 2026-09-02
    /// startup freeze, rebuilt over and over inside the sizing pass.
    /// **The options live in this column, under labels** — Pages, Split,
    /// Also, Settings — and the footer holds Cancel · Export… and nothing
    /// else. 2026-09-14: a footer never holds options.
    private var rail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                orderSection
                if wholeProject && !plansOnly {
                    daysSection
                    if arrange == .schedule && !info.days.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Output").fieldLabel(dark)
                            Segmented(
                                selection: $delivery,
                                items: [.init(value: Delivery.wholeFilm, title: "One file"),
                                        .init(value: Delivery.perDay, title: "File per day")],
                                quiet: true)
                            .fixedSize()
                        }
                    }
                }
                GroupGap()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pages").fieldLabel(dark)
                    VStack(alignment: .leading, spacing: 2) {
                        railItem(.table)
                        railItem(.storyboard)
                        railItem(.document)
                        if hasAVScript { railItem(.avscript) } else { railItem(.script) }
                        if hasDiagram { railItem(.diagram) }
                    }
                }
                GroupGap()
                VStack(alignment: .leading, spacing: 4) {
                    Text("File").fieldLabel(dark)
                    Segmented(
                        selection: fileKind,
                        items: [.init(value: 0, title: "PDF"),
                                .init(value: 1, title: "Flat PDF"),
                                .init(value: 2, title: "PNG")],
                        quiet: true)
                    .fixedSize()
                }
                GroupGap()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Also").fieldLabel(dark)
                    Toggle("Spreadsheet", isOn: $alsoWorkbook)
                        .toggleStyle(.checkbox).sans(Brand.Size.body)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// **Order, and the Table's filter under it.** As in Table carries the
    /// Table's sort, and says which.
    private var orderSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Order").fieldLabel(dark)
            Segmented(
                selection: $arrange,
                items: [.init(value: ExportArrange.table,
                              title: tableSortName.isEmpty ? "As in Table" : "As in Table (\(tableSortName))"),
                        .init(value: ExportArrange.script, title: "Script"),
                        .init(value: ExportArrange.schedule, title: "Schedule")],
                quiet: true)
            .fixedSize()
            if !info.filter.isEmpty {
                HStack(spacing: 6) {
                    Text(useFilter ? "Filter: " + info.filter.joined(separator: ", ") : "No filter")
                        .sans(Brand.Size.small).foregroundStyle(Brand.ink(dark))
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 4)
                    Button(useFilter ? "Clear for export" : "Use Table filter") { useFilter.toggle() }
                        .buttonStyle(.rowAction)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
                    .fill(Brand.selectionQuiet(dark)))
            }
            if filterNotUsed {
                Text("Filter not used").sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark))
            }
        }
    }

    // ---------------------------------------------------------------- days

    /// **The Days picker, made for sixty days** — quick picks, a From/To
    /// range, then the list grouped by shoot and week for the odd ones out.
    /// Only a Schedule reads it; the other orders show it greyed.
    private var daysSection: some View {
        let on = arrange == .schedule
        return VStack(alignment: .leading, spacing: 6) {
            Text("Days").fieldLabel(dark)
            quickPicks
            if on && !info.days.isEmpty {
                rangeRow
                HStack {
                    Text(ExportDays.summary(selectedDays, in: info))
                        .sans(Brand.Size.small, weight: .semibold).foregroundStyle(Brand.ink(dark))
                    Spacer(minLength: 4)
                    Button(selectedDays.isEmpty ? "Select all" : "Select none") {
                        selectedDays = selectedDays.isEmpty ? allDayIds : []
                    }
                    .buttonStyle(.rowAction)
                }
                dayList
            }
        }
        .disabled(!on)
        .opacity(on ? 1 : 0.45)
    }

    /// The rule the picks make right now, to light the quick pick it is.
    private var pickedRule: DaysRule { ExportDays.rule(for: selectedDays, in: info) }

    private var quickPicks: some View {
        let rules: [DaysRule] = [.all, DaysRule(kind: "next"), DaysRule(kind: "thisweek"), DaysRule(kind: "nextweek")]
        let shoots: [DaysRule] = info.shoots.count >= 2
            ? info.shoots.indices.map { DaysRule(kind: "shoot", shoot: $0 + 1) } : []
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) { ForEach(rules, id: \.kind) { quickPick($0) } }
            if !shoots.isEmpty {
                HStack(spacing: 4) { ForEach(shoots, id: \.shoot) { quickPick($0) } }
            }
        }
    }

    private func quickPick(_ rule: DaysRule) -> some View {
        let lit = arrange == .schedule && pickedRule.kind == rule.kind
            && (rule.kind != "shoot" || pickedRule.shoot == rule.shoot)
        return Text(rule.title)
            .sans(Brand.Size.small)
            .foregroundStyle(lit ? Brand.onAccent(dark) : Brand.ink2(dark))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(lit ? Brand.accent(dark) : Brand.selectionQuiet(dark)))
            .contentShape(Capsule())
            .onTapGesture {
                var picked = ExportDays.pick(rule, in: info)
                // The unscheduled keep their tick, except under All Days.
                if rule.kind != "all" {
                    if selectedDays.contains(ExportDays.unscheduled) && info.unscheduled > 0 && rule.unscheduled == nil
                        && rule.kind != "next" { picked.insert(ExportDays.unscheduled) }
                }
                selectedDays = picked
                unfoldPicked()
            }
    }

    /// **From and To**, by day number and date.
    private var rangeRow: some View {
        let numbers = ExportDays.numbersOf(selectedDays, in: info)
        let from = numbers.first ?? 1, to = numbers.last ?? info.days.count
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("From").sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark)).frame(width: 34, alignment: .leading)
                dayMenu(at: from) { pickRange(from: $0, to: max($0, to)) }
            }
            HStack(spacing: 6) {
                Text("To").sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark)).frame(width: 34, alignment: .leading)
                dayMenu(at: to) { pickRange(from: min(from, $0), to: $0) }
            }
        }
    }

    private func dayWords(_ number: Int) -> String {
        guard info.days.indices.contains(number - 1) else { return "" }
        let day = info.days[number - 1]
        let date = ExportDays.date(day.date).map(ExportDays.short) ?? day.date
        return "Day \(number)" + (date.isEmpty ? "" : "  \(date)")
    }

    private func dayMenu(at number: Int, pick: @escaping (Int) -> Void) -> some View {
        Menu {
            ForEach(1...max(info.days.count, 1), id: \.self) { n in
                Button(dayWords(n)) { pick(n) }
            }
        } label: {
            FieldFace(text: dayWords(number), dark: dark)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    private func pickRange(from: Int, to: Int) {
        var picked = ExportDays.pick(DaysRule(kind: "range", from: from, to: to, unscheduled: false), in: info)
        if selectedDays.contains(ExportDays.unscheduled) { picked.insert(ExportDays.unscheduled) }
        selectedDays = picked
        unfoldPicked()
    }

    /// **Groups open on their own where a pick is**, the rest folded — so
    /// sixty days show as a handful of weeks with the picked ones open.
    private func unfoldPicked() {
        guard info.days.count > 12 else { folded = []; return }
        var shut: Set<String> = []
        for group in ExportDays.groups(of: info) {
            var any = false
            for week in group.weeks {
                if week.days.contains(where: { selectedDays.contains($0.day.id) }) { any = true }
                else { shut.insert(week.id) }
            }
            if !any && !group.title.isEmpty { shut.insert("g-" + group.id) }
        }
        folded = shut
    }

    private var dayList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(ExportDays.groups(of: info)) { group in
                    if !group.title.isEmpty {
                        foldRow(id: "g-" + group.id, title: group.title,
                                ids: group.weeks.flatMap { $0.days.map(\.day.id) }, indent: 0)
                    }
                    if group.title.isEmpty || !folded.contains("g-" + group.id) {
                        ForEach(group.weeks) { week in
                            foldRow(id: week.id, title: week.title, ids: week.days.map(\.day.id),
                                    indent: group.title.isEmpty ? 0 : 12)
                            if !folded.contains(week.id) {
                                ForEach(week.days, id: \.day.id) { entry in
                                    dayRow(entry.number, entry.day, indent: group.title.isEmpty ? 14 : 26)
                                }
                            }
                        }
                    }
                }
                if info.unscheduled > 0 {
                    unscheduledRow
                }
            }
        }
        .frame(height: 230)
        .background(RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
            .fill(Brand.stage(dark)))
        .clipShape(RoundedRectangle(cornerRadius: Brand.radius, style: .continuous))
    }

    private func tick(_ state: Bool?) -> some View {
        Image(systemName: state == true ? "checkmark.square.fill" : state == nil ? "minus.square.fill" : "square")
            .font(.system(size: 12))
            .foregroundStyle(state == false ? Brand.ink4(dark) : Brand.accent(dark))
    }

    /// A shoot or a week: its fold, its tick (all, some, none), how many.
    private func foldRow(id: String, title: String, ids: [String], indent: CGFloat) -> some View {
        let on = ids.filter { selectedDays.contains($0) }.count
        let all: Bool? = on == ids.count ? true : (on == 0 ? false : nil)
        return HStack(spacing: 6) {
            Image(systemName: folded.contains(id) ? "chevron.right" : "chevron.down")
                .font(.system(size: 8, weight: .semibold)).foregroundStyle(Brand.ink3(dark))
                .frame(width: 10)
                .contentShape(Rectangle())
                .onTapGesture { if folded.contains(id) { folded.remove(id) } else { folded.insert(id) } }
            tick(all)
                .contentShape(Rectangle())
                .onTapGesture {
                    if all == true { selectedDays.subtract(ids) } else { selectedDays.formUnion(ids) }
                }
            Text(title).sans(Brand.Size.small, weight: indent == 0 ? .semibold : .regular)
                .foregroundStyle(Brand.ink(dark)).lineLimit(1)
            Spacer(minLength: 4)
            Text(on == ids.count ? "\(ids.count)" : "\(on) of \(ids.count)")
                .sans(Brand.Size.tiny).monospacedDigit().foregroundStyle(Brand.ink3(dark))
        }
        .padding(.leading, 6 + indent).padding(.trailing, 8).padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { if folded.contains(id) { folded.remove(id) } else { folded.insert(id) } }
    }

    /// One day: tick, number, date, where. **Shift-click ticks the run**
    /// from the last day clicked to this one.
    private func dayRow(_ number: Int, _ day: ExportInfo.Day, indent: CGFloat) -> some View {
        let on = selectedDays.contains(day.id)
        let date = ExportDays.date(day.date).map(ExportDays.short) ?? day.date
        return HStack(spacing: 6) {
            tick(on)
            Text("Day \(number)").sans(Brand.Size.small).foregroundStyle(Brand.ink(dark))
            Text(date).sans(Brand.Size.small).foregroundStyle(Brand.ink2(dark)).lineLimit(1)
            Spacer(minLength: 4)
            Text("\(day.count)").sans(Brand.Size.tiny).monospacedDigit().foregroundStyle(Brand.ink4(dark))
        }
        .padding(.leading, 6 + indent).padding(.trailing, 8).padding(.vertical, 3)
        .background(on ? Brand.selectionQuiet(dark) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            let now = !on
            if NSEvent.modifierFlags.contains(.shift), let anchorDay,
               let a = info.days.firstIndex(where: { $0.id == anchorDay }),
               let b = info.days.firstIndex(where: { $0.id == day.id }) {
                let run = info.days[min(a, b)...max(a, b)].map(\.id)
                if now { selectedDays.formUnion(run) } else { selectedDays.subtract(run) }
            } else if now {
                selectedDays.insert(day.id)
            } else {
                selectedDays.remove(day.id)
            }
            anchorDay = day.id
        }
    }

    private var unscheduledRow: some View {
        let on = selectedDays.contains(ExportDays.unscheduled)
        return HStack(spacing: 6) {
            tick(on)
            Text("Unscheduled").sans(Brand.Size.small).foregroundStyle(Brand.ink(dark))
            Spacer(minLength: 4)
            Text("\(info.unscheduled)").sans(Brand.Size.tiny).monospacedDigit().foregroundStyle(Brand.ink4(dark))
        }
        .padding(.leading, 6).padding(.trailing, 8).padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if on { selectedDays.remove(ExportDays.unscheduled) } else { selectedDays.insert(ExportDays.unscheduled) }
        }
    }

    /// `--exportset arrange=schedule;days=12-18+22;output=perday;filter=none`
    private func setFromOutside(_ said: String) {
        for pair in said.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "arrange": arrange = ExportArrange(rawValue: kv[1]) ?? arrange
            case "filter": useFilter = kv[1] != "none"
            case "output": delivery = kv[1] == "perday" ? .perDay : .wholeFilm
            case "name": typedName = kv[1]; nameTyped = true
            case "autosize": autoAsk = AutoAsk(size: Double(kv[1]) ?? 1, paper: autoAsk.paper)
            case "autopaper": autoAsk = AutoAsk(size: autoAsk.size, paper: kv[1])
            case "off": includedColumns.remove(kv[1])
            case "layout": if kv[1] == "manual" { takeOverFromAuto() } else { tableAuto = true }
            case "days":
                // `12-18+22`, `next`, `thisweek`, `all`, `shoot2`
                if ["all", "next", "thisweek", "nextweek"].contains(kv[1]) {
                    selectedDays = ExportDays.pick(DaysRule(kind: kv[1]), in: info)
                } else if kv[1].hasPrefix("shoot"), let n = Int(kv[1].dropFirst(5)) {
                    selectedDays = ExportDays.pick(DaysRule(kind: "shoot", shoot: n), in: info)
                } else {
                    var numbers: [Int] = []
                    for part in kv[1].split(separator: "+") {
                        let ends = part.split(separator: "-").compactMap { Int($0) }
                        if ends.count == 2 { numbers += Array(min(ends[0], ends[1])...max(ends[0], ends[1])) }
                        else if let one = ends.first { numbers.append(one) }
                    }
                    selectedDays = ExportDays.pick(DaysRule(kind: "numbers", numbers: numbers, unscheduled: false), in: info)
                }
            default: break
            }
        }
        sanitize()
    }

    /// One row. **Two hit regions**: the tick decides whether the view is in
    /// the file, the rest of the row decides which one you are looking at.
    /// One tick per view and only one — it used to appear here *and* in a list
    /// beside it, which is what he could feel.
    ///
    /// Deliberately not a `Button` with a checkbox inside it: on macOS a
    /// plain-styled outer button swallows the inner control\'s click.
    private func railItem(_ section: ExportSection) -> some View {
        let on = pane == section
        let possible = availableSections.contains(section)
        let usable = section != .script || scriptAvailable
        // **The chosen row is the quiet grey block**, ink on it, the tick in
        // the film's colour — never a solid accent row. 2026-09-14.
        return HStack(spacing: 8) {
            Text(section.title)
                .sans(Brand.Size.body, weight: on ? .semibold : .regular)
                .foregroundStyle(possible && usable ? Brand.ink(dark) : Brand.ink4(dark))
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: include.contains(section) ? "checkmark.square.fill" : "square")
                .font(.system(size: 13))
                .foregroundStyle(include.contains(section) ? Brand.accent(dark) : Brand.ink4(dark))
                .contentShape(Rectangle())
                .onTapGesture {
                    guard possible, usable else { return }
                    if include.contains(section) { include.remove(section) }
                    else { include.insert(section) }
                }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
                .fill(on ? Brand.selectionQuiet(dark) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { if possible { pane = section } }
        .opacity(possible ? 1 : 0.45)
    }

    /// **The well, and the paper in it.**
    ///
    /// Cut into the window rather than laid on it: a rounded recess in the
    /// ground, darker than everything round it, with the sheet lying on it.
    /// `Brand.desk` is the token the Document view already uses for this, and
    /// it is markedly darker on purpose — in daylight the window is nearly
    /// white and so is a sheet of Letter.
    private var previewPane: some View {
        VStack(spacing: 0) {
            previewContent
                .clipShape(RoundedRectangle(cornerRadius: Brand.radiusLarge, style: .continuous))
                .background {
                    RoundedRectangle(cornerRadius: Brand.radiusLarge, style: .continuous)
                        .fill(Brand.stage(dark))
                }
            pageBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
    }

    /// What the preview is holding: this view's own pages.
    private var shownDocument: PDFDocument? {
        pane == .script ? scriptPreview : previewDocument
    }

    /// **How long the thing actually is, and a way to reach page seven.**
    /// The box has never said either — his report, 2026-09-02, that it felt
    /// clunky, and this is one of the reasons why: nothing told him whether he
    /// was about to hand somebody four pages or forty.
    private var pageBar: some View {
        let count = shownDocument?.pageCount ?? 0
        return HStack(spacing: 14) {
            Button { previewPage = max(0, previewPage - 1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain).disabled(previewPage <= 0)
            .foregroundStyle(previewPage <= 0 ? Brand.ink4(dark) : Brand.ink2(dark))
            Text(count > 0 ? "Page \(min(previewPage + 1, count)) of \(count)"
                 : (rendering ? "" : "No pages"))
                .sans(11).foregroundStyle(Brand.ink3(dark))
                .frame(minWidth: 96)
                // **The last good page stays up while the next is drawn**,
                // and says so here, quietly — never a wheel over the page.
                .overlay(alignment: .trailing) {
                    if rendering && count > 0 {
                        Text("Updating…").sans(11).foregroundStyle(Brand.ink4(dark))
                            .fixedSize().offset(x: 76)
                    }
                }
            Button { previewPage = min(max(count - 1, 0), previewPage + 1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain).disabled(previewPage >= count - 1)
            .foregroundStyle(previewPage >= count - 1 ? Brand.ink4(dark) : Brand.ink2(dark))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var previewContent: some View {
        if pane == .script {
            if let scriptPreview {
                PDFKitPreview(document: scriptPreview, page: $previewPage, dark: dark)
            } else if scriptChecked {
                middle("No script is kept for this project")
            } else {
                Spacer(); ProgressView(); Spacer()
            }
        } else if let previewDocument {
            PDFKitPreview(document: previewDocument, page: $previewPage, dark: dark)
        } else if let problem {
            // **A render that failed used to spin here for ever.** The
            // engine's own refusal never reached the screen, so the one thing
            // he could see was a wheel that never stopped.
            middle(problem)
        } else if rendering {
            Spacer(); ProgressView(); Spacer()
        } else {
            middle("Nothing to show")
        }
    }

    private func middle(_ words: String) -> some View {
        VStack {
            Spacer()
            Text(words).sans(11).foregroundStyle(Brand.ink3(dark))
                .multilineTextAlignment(.center).padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var settingsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(wholeProject && delivery == .perDay ? "Folder name" : "File name").fieldLabel(dark)
                    FieldText(placeholder: "", text: nameField, onSubmit: {})
                    if wholeProject && delivery == .perDay {
                        let count = selectedDays.filter { $0 != ExportDays.unscheduled || info.unscheduled > 0 }.count
                        Text("\(count) PDF\(count == 1 ? "" : "s"), one a day")
                            .sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark))
                    }
                }
                lookSettings(pane)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// **Only the dials this view obeys.** Widths reach the table and nothing
    /// else; frames reach the table and the storyboard; the document takes a
    /// text size and its own paper. Showing a view a dial it ignores is how
    /// the old single column came to be lying.
    @ViewBuilder private func lookSettings(_ section: ExportSection) -> some View {
        if section == .script {
            settingsSection(section.title) {
                Text("Nothing to set").sans(Brand.Size.small).foregroundStyle(Brand.ink4(dark))
            }
        } else {
            settingsSection(section.title) {
                if section == .table {
                    Segmented(
                        selection: Binding(
                            get: { tableAuto },
                            set: { auto in if auto { tableAuto = true } else { takeOverFromAuto() } }),
                        items: [.init(value: true, title: "Auto"),
                                .init(value: false, title: "Manual")],
                        quiet: true)
                    .fixedSize()
                }
                if section == .table && tableAuto {
                    autoDials
                } else {
                    Segmented(
                        selection: lookBinding(section, \.orientation),
                        items: [.init(value: Printing.Orientation.landscape, title: "Landscape"),
                                .init(value: Printing.Orientation.portrait, title: "Portrait")],
                        quiet: true)
                    .fixedSize()
                    // **No text size on the Document page** — his instruction,
                    // 2026-09-02: the resizing belongs in the document view, not
                    // here. It is set there per kind of words, and this reads it.
                    // The line earns its place under his own rule: it says why
                    // something cannot be done here, which a label cannot.
                    if section == .diagram {
                        Toggle(isOn: $diagramKey) { Text("Shot List").sans(Brand.Size.body) }
                        Toggle(isOn: $diagramBar) { Text("Scale Bar").sans(Brand.Size.body) }
                        Toggle(isOn: $diagramCones) { Text("Lens Cones").sans(Brand.Size.body) }
                        Toggle(isOn: $diagramDark) { Text("Dark").sans(Brand.Size.body) }
                    } else if section == .document || section == .avscript {
                        Text("Text is set on the page")
                            .sans(11).foregroundStyle(Brand.ink4(dark))
                    } else {
                        HStack(spacing: 8) {
                            Slider(value: lookBinding(section, \.scale), in: 0.2...1.6, step: 0.05)
                                .background(Launch.checking ? SliderProbe(name: "scale") : nil)
                            Text("\(Int(look(section).scale * 100))%")
                                .sans(Brand.Size.tiny).monospacedDigit()
                                .foregroundStyle(Brand.ink3(dark))
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                    if section != .document && section != .avscript && section != .diagram {
                        Segmented(
                            selection: lookBinding(section, \.frames),
                            items: [.init(value: Printing.FrameSize.small, title: "Small"),
                                    .init(value: Printing.FrameSize.medium, title: "Medium"),
                                    .init(value: Printing.FrameSize.large, title: "Large")],
                            quiet: true)
                        .fixedSize()
                    }
                }
            }
            if section == .table {
                columns
            }
        }
    }

    /// **Auto's own two dials**: which way round (Auto picks unless he
    /// says) and one Size for text and pictures together. Auto still works
    /// out every width; neither makes the table Manual.
    private var autoDials: some View {
        VStack(alignment: .leading, spacing: 8) {
            Segmented(
                selection: Binding(
                    get: { autoAsk.paper },
                    set: { autoAsk = AutoAsk(size: autoAsk.size, paper: $0) }),
                items: [.init(value: "auto", title: "Best Fit"),
                        .init(value: "landscape", title: "Landscape"),
                        .init(value: "portrait", title: "Portrait")],
                quiet: true)
            .fixedSize()
            HStack(spacing: 8) {
                Text("Size").sans(11).foregroundStyle(Brand.ink3(dark))
                Slider(
                    value: Binding(
                        get: { autoAsk.size },
                        set: { autoAsk = AutoAsk(size: $0, paper: autoAsk.paper) }),
                    in: AutoAsk.sizes, step: 0.05)
                    .background(Launch.checking ? SliderProbe(name: "size") : nil)
                Text("\(Int((autoAsk.size * 100).rounded()))%")
                    .sans(Brand.Size.tiny).monospacedDigit()
                    .foregroundStyle(Brand.ink3(dark))
                    .frame(width: 34, alignment: .trailing)
            }
        }
    }

    /// **One row per column: the tick, the name, the dial, the share.**
    ///
    /// They were two lists — *Columns* and *Column widths* — three hundred
    /// pixels apart in a strip too narrow to read the names in, and turning a
    /// column off in one made it vanish from the other with no explanation.
    private var columns: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Columns").fieldLabel(dark)
                Spacer(minLength: 4)
                if !tableAuto, columnWidths.values.contains(where: { abs($0 - 1) > 0.01 }) {
                    Button("Reset widths") { columnWidths = [:] }
                        .buttonStyle(.rowAction)
                }
            }
            ForEach(availableColumns) { column in
                columnRow(column)
            }
        }
    }

    /// **The share is worked out from the engine\'s own weights**, so the
    /// number he reads is the number the page will use.
    private func columnRow(_ column: ViewModel.Column) -> some View {
        let on = includedColumns.contains(column.name)
        return HStack(spacing: 8) {
            Image(systemName: on ? "checkmark.square.fill" : "square")
                .font(.system(size: 13))
                .foregroundStyle(on ? Brand.accent(dark) : Brand.ink4(dark))
                .contentShape(Rectangle())
                .onTapGesture {
                    if on { includedColumns.remove(column.name) }
                    else { includedColumns.insert(column.name) }
                }
            Text(Columns.label(column.name)).sans(11)
                .foregroundStyle(on ? Brand.ink(dark) : Brand.ink4(dark))
                .lineLimit(1).truncationMode(.tail)
                .frame(width: 82, alignment: .leading)
            // **The width dials are Manual's.** On Auto the widths are
            // Auto's to choose, so there is nothing to move — his words,
            // 2026-10-17: otherwise "what's the difference between the modes".
            // Picking Manual starts the dials from what Auto chose.
            if tableAuto {
                Spacer(minLength: 0)
            } else {
                Slider(
                    value: Binding(
                        get: { columnWidths[column.name] ?? 1 },
                        set: { columnWidths[column.name] = $0 }
                    ),
                    in: 0.4...2.5)
                    .controlSize(.mini)
                    .background(Launch.checking && on ? SliderProbe(name: "width") : nil)
                    .disabled(!on)
                    .opacity(on ? 1 : 0.3)
            }
            Text(on ? "\(Int((share(of: column.name) * 100).rounded()))%" : "")
                .sans(Brand.Size.tiny).monospacedDigit().foregroundStyle(Brand.ink3(dark))
                .frame(width: 28, alignment: .trailing)
        }
    }

    /// Ask the engine what the printed table\'s columns are worth. **Asked
    /// with his own picks**, because both change the answer: hiding a column
    /// takes it out of the list, and the Frames size *is* the picture
    /// column\'s weight.
    private func loadColumnWeights() {
        guard let engine = state.engine else { return }
        let began = Date()
        baseWeights = engine.printedColumnWeights(scope: scope(for: .table))
        if Launch.checking {
            FileHandle.standardError.write(Data(String(
                format: "column weights asked: %.0fms\n", Date().timeIntervalSince(began) * 1000).utf8))
        }
    }

    /// What share of the printed table a column will actually take: its own
    /// weight times his dial, over everybody else\'s. The same sum
    /// `table_rows` does, which is why it can be trusted to match the page.
    private func share(of field: String) -> Double {
        if tableAuto, let plan = autoPlan { return (plan.shares[field] ?? 0) / 100 }
        let weighed = baseWeights.map { $0.weight * (columnWidths[$0.field] ?? 1) }
        let total = weighed.reduce(0, +)
        guard total > 0,
              let at = baseWeights.firstIndex(where: { $0.field == field })
        else { return 0 }
        return weighed[at] / total
    }

    /// A group with a heading. **Uppercase mono, matching Project Settings and
    /// the script importer** — this box used title-case sans and was the
    /// outlier of the three.
    @ViewBuilder
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).fieldLabel(dark)
            VStack(alignment: .leading, spacing: 8) { content() }
        }
    }

    /// **Where the file goes, beside the button that sends it there.** It was
    /// a screen of its own called *Goes out*, which he could not read; this is
    /// the row every save box on the Mac puts the same decision in.
    private var footer: some View {
        HStack(spacing: 10) {
            if exporting {
                ProgressView().controlSize(.small)
                Text("Making the PDF…").sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark))
            } else if let problem {
                Text(problem).sans(Brand.Size.small).foregroundStyle(Brand.warn(dark))
            } else if nothingToExport {
                Text("Tick a page to export").sans(Brand.Size.small).foregroundStyle(Brand.warn(dark))
            } else if wholeProject && delivery == .perDay && selectedDays.isEmpty {
                Text("Pick a day to export").sans(Brand.Size.small).foregroundStyle(Brand.warn(dark))
            }
            Spacer()
            Button("Cancel") { close() }
            Button(wholeProject && delivery == .perDay ? "Choose Folder…" : "Export…") { export() }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .disabled(nothingToExport || exporting
                          || (wholeProject && delivery == .perDay && selectedDays.isEmpty))
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .hairline(.top, Brand.rule(dark))
    }

    // ---------------------------------------------------------------- script

    /// The real PDF, and where each picked scene sits in it. Loaded once, off
    /// the main actor's own turn — a whole screenplay's bytes are real work to
    /// decode, and the dialog should not stall opening while that happens.
    private func loadScript() async {
        guard let engine = state.engine,
              let latest = engine.revisions().first(where: \.latest),
              let bytes = engine.scriptPDF(of: latest.id),
              let pages = engine.scriptPages(of: latest.id)
        else {
            scriptChecked = true
            include.remove(.script)
            return
        }
        scriptBytes = bytes
        scriptPages = pages
        include.insert(.script)
        scriptChecked = true
        if pane == .script { renderScriptPreview() }
    }

    /// Every picked scene's own pages, in script order — not selection order,
    /// so a scattered pick still reads front to back.
    ///
    /// The whole film wants the whole draft, unsliced: cutting it into scene
    /// ranges and stitching them back together would drop anything the
    /// detector never attributed to a scene — a title page, a cast list, an
    /// act break — and put back nothing in exchange.
    private func slicedScript() -> PDFDocument? {
        guard let scriptBytes, let scriptPages, let source = PDFDocument(data: scriptBytes) else {
            return nil
        }
        if wholeProject { return source }
        let ordered = scenes.sorted {
            (scriptPages.pageRange(for: $0.number)?.lowerBound ?? 0)
            < (scriptPages.pageRange(for: $1.number)?.lowerBound ?? 0)
        }
        let out = PDFDocument()
        for scene in ordered {
            guard let range = scriptPages.pageRange(for: scene.number) else { continue }
            for pageNumber in range {
                let index = pageNumber - 1
                guard index >= 0, index < source.pageCount, let page = source.page(at: index) else { continue }
                out.insert(page, at: out.pageCount)
            }
        }
        return out.pageCount > 0 ? out : nil
    }

    private func renderScriptPreview() {
        scriptPreview = slicedScript()
    }

    // ---------------------------------------------------------------- preview

    /// The picked columns, in the project's own order — not the order they
    /// were checked in.
    private var orderedColumns: [String] {
        availableColumns.filter { includedColumns.contains($0.name) }.map(\.name)
    }

    /// **Hold the redraw until his hand stops.** The width dials have no
    /// step, so a single drag fired an engine write, a web view load, a fixed
    /// 0.4-second settle and a page slice on every tick of the mouse. The
    /// generation counter threw the stale answers away; nothing stopped the
    /// work being done.
    private func schedulePreview() {
        // **Nothing draws while the box is still opening.** `recall` and the
        // defaults each write a setting, each setting fires its own change,
        // and the box used to render two and three times over before he had
        // touched anything — measured at 1.8 to 2.4 seconds of work, twice.
        guard opened else { return }
        previewWork?.cancel()
        rendering = true
        let work = DispatchWorkItem { renderPreview() }
        previewWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    /// **← and → turn the page.** His ask, 2026-09-02.
    ///
    /// A local monitor rather than a `keyboardShortcut` on the two buttons,
    /// following the pattern `Document.swift` already uses: a shortcut fires
    /// wherever the keyboard happens to be, including in the middle of a word
    /// he is typing.
    ///
    /// **Only ← and →.** A slider he has clicked into takes ↑ and ↓ for its
    /// own nudging, and leaving those two alone is what lets both live in one
    /// window without either having to win.
    private func watchKeys() {
        if let keyWatch { NSEvent.removeMonitor(keyWatch) }
        keyWatch = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // This window only. The monitor belongs to the application, not to
            // a window, so it hears the whole app.
            guard event.window?.identifier?.rawValue == "export" else { return event }
            // Somebody is typing. A text field is never the first responder —
            // the window's field editor is, on its behalf.
            if event.window?.firstResponder is NSTextView { return event }
            guard event.modifierFlags
                .intersection([.command, .option, .control, .shift]).isEmpty else { return event }
            return turn(byKey: event.keyCode) ? nil : event
        }
    }

    /// `--exportdrag width:20` / `scale:20` — **a hand on a slider, from
    /// outside.** Waits for the first page, then moves the dial that many
    /// times a frame (16ms) apart, the way a drag does, and says the longest
    /// the main thread went unanswered — during the drag, and until the page
    /// it asked for has been drawn. His report, 2026-10-15: every slider move
    /// froze the window with a rainbow wheel.
    private func dragSliders() {
        guard Launch.checking, let said = state.exportDragSaid else { return }
        let parts = said.split(separator: ":")
        let mode = parts.first.map(String.init) ?? "width"
        let count = parts.count > 1 ? Int(parts[1]) ?? 20 : 20
        func waitForPage(_ tries: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard previewDocument != nil, !rendering, inFlight == nil else {
                    if tries < 100 { waitForPage(tries + 1) }
                    else { FileHandle.standardError.write(Data("export drag: nothing drawn\n".utf8)) }
                    return
                }
                drag()
            }
        }
        func drag() {
            // `dials`: how many width dials are on screen, and on which layout.
            if mode == "dials" {
                let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "export" })
                let width = SliderProbe.made.filter {
                    $0.name == "width" && $0.held.view?.window != nil && $0.held.view?.window === window
                }.count
                FileHandle.standardError.write(Data(
                    "export dials: width \(width) layout \(tableAuto ? "auto" : "manual")\n".utf8))
                return
            }
            // The text-size and width dials are Manual's; Auto's own is `size`.
            if mode.hasSuffix("scale") || mode == "width" || mode == "hand", pane == .table, tableAuto {
                takeOverFromAuto()
                // Its slider is drawn on the next pass; wait for the page too.
                return waitForPage(0)
            }
            if mode.hasPrefix("hand") { return handDrag() }
            let column = orderedColumns.first(where: { $0 != "image" }) ?? orderedColumns.first ?? "description"
            StallWatch.shared.reset()
            let began = Date()
            for i in 0..<count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.016 * Double(i)) {
                    let step = Double(i % 10) / 10
                    if mode == "scale" {
                        lookBinding(pane, \.scale).wrappedValue = 0.6 + 0.6 * step
                    } else if mode == "size" {
                        autoAsk = AutoAsk(size: 0.7 + 0.6 * step, paper: autoAsk.paper)
                    } else {
                        columnWidths[column] = 0.6 + 1.4 * step
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016 * Double(count) + 0.05) {
                let during = StallWatch.shared.worst
                let dragMs = Date().timeIntervalSince(began) * 1000
                func settle(_ tries: Int) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        if rendering || inFlight != nil, tries < 80 { return settle(tries + 1) }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            let all = StallWatch.shared.worst
                            StallWatch.shared.stop()
                            FileHandle.standardError.write(Data(String(
                                format: "export drag: %@ %d changes in %.0fms  worst stall during %.0fms  worst stall until drawn %.0fms  knocks %d  pages %d\n",
                                mode, count, dragMs, during.ms, all.ms, all.knocks,
                                previewDocument?.pageCount ?? 0).utf8))
                        }
                    }
                }
                settle(0)
            }
        }
        /// **A real drag, through the real slider.** Events are made here and
        /// handed to the window, so the slider runs its own tracking loop
        /// exactly as under his hand — without the Mac's pointer moving.
        /// `hand` is a column-width dial, `handscale` the size dial.
        func handDrag() {
            guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "export" }),
                  let content = window.contentView else {
                FileHandle.standardError.write(Data("export drag: no window\n".utf8)); return
            }
            // SwiftUI's slider is not an `NSSlider`; each dial carries a
            // marker view (`SliderProbe`) that says where it is.
            let name = mode == "hand" ? "width" : mode == "handsize" ? "size" : "scale"
            guard let probe = SliderProbe.seen[name]?.view, probe.window === window else {
                FileHandle.standardError.write(Data("export drag: no slider\n".utf8)); return
            }
            let screenFrame = window.convertToScreen(probe.convert(probe.bounds, to: nil))
            let picked = (frame: screenFrame, value: mode == "hand"
                          ? (columnWidths.values.first ?? 1) : mode == "handsize" ? autoAsk.size : look(pane).scale)
            let box = window.convertFromScreen(picked.frame)
            let y = box.midY
            let from = box.minX + 4, to = box.maxX - 4
            let value0 = picked.value
            func event(_ type: NSEvent.EventType, _ x: CGFloat) -> NSEvent? {
                NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y),
                                   modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: window.windowNumber, context: nil,
                                   eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)
            }
            // Pressed at the middle; a SwiftUI slider jumps to the press and
            // follows from there.
            let knob = (from + to) / 2
            StallWatch.shared.reset()
            let began = Date()
            var i = 0
            let timer = Timer(timeInterval: 0.016, repeats: true) { t in
                i += 1
                if i > count {
                    t.invalidate()
                    // Let go somewhere new, so the drag always asks for a page.
                    let last = from + (to - from) * 0.3
                    if let moved = event(.leftMouseDragged, last) { NSApp.postEvent(moved, atStart: false) }
                    if let up = event(.leftMouseUp, last) { NSApp.postEvent(up, atStart: false) }
                    return
                }
                // Back and forth across the dial, the way a hand hunts for a width.
                let phase = Double(i % 20) / 20
                let x = from + (to - from) * CGFloat(phase < 0.5 ? phase * 2 : 2 - phase * 2)
                if let moved = event(.leftMouseDragged, x) { NSApp.postEvent(moved, atStart: false) }
            }
            RunLoop.main.add(timer, forMode: .common)
            DispatchQueue.main.async {
                if let down = event(.leftMouseDown, knob) { window.sendEvent(down) }
                // The slider's tracking loop returns on the mouse-up.
                let during = StallWatch.shared.worst
                let dragMs = Date().timeIntervalSince(began) * 1000
                FileHandle.standardError.write(Data(String(
                    format: "export drag: slider was %.2f; widths %@ scale %.2f size %.2f %@\n", value0,
                    columnWidths.map { "\($0.key)=\(String(format: "%.2f", $0.value))" }.joined(separator: ","),
                    look(pane).scale, autoAsk.size, tableAuto ? "auto" : "manual").utf8))
                func settle(_ tries: Int) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        if rendering || inFlight != nil, tries < 80 { return settle(tries + 1) }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            let all = StallWatch.shared.worst
                            StallWatch.shared.stop()
                            FileHandle.standardError.write(Data(String(
                                format: "export drag: %@ %d changes in %.0fms  worst stall during %.0fms  worst stall until drawn %.0fms  knocks %d  pages %d\n",
                                mode, count, dragMs, during.ms, all.ms, all.knocks,
                                previewDocument?.pageCount ?? 0).utf8))
                        }
                    }
                }
                settle(0)
            }
        }
        waitForPage(0)
    }

    /// `--exportnext 3` — turn the page N times and say where it landed, so a
    /// check can prove one press moves exactly one page. It took several
    /// presses per page before 2026-09-02 and nothing would have caught it.
    ///
    /// **It waits for the page before it presses anything.** The first version
    /// pressed on a timer and the first press landed while the render was
    /// still going, so three presses moved two pages — the door reporting the
    /// bug it was written to disprove.
    private func turnPages() {
        guard Launch.checking,
              let said = state.exportNextSaid, let times = Int(said), times >= 0 else { return }
        // **Nought means press nothing and only report.** That is how the
        // keyboard half gets checked: the harness types a real ← or → at the
        // window and this says where the page ended up, so the monitor is
        // proved rather than assumed.
        if times == 0 { watchAndSay(waited: 0) } else { press(left: times, waited: 0) }
    }

    private func watchAndSay(waited: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let count = shownDocument?.pageCount ?? 0
            guard count > 1 else {
                if waited < 30 { watchAndSay(waited: waited + 1) }
                else { FileHandle.standardError.write(Data("page: nothing drawn\n".utf8)) }
                return
            }
            // Long enough for the typist to have finished its own run.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                FileHandle.standardError.write(Data((
                    "page: \(previewPage + 1) of \(count)\n").utf8))
            }
        }
    }

    private func press(left: Int, waited: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let count = shownDocument?.pageCount ?? 0
            guard count > 1 else {
                // Still drawing. Give it a while, then say so rather than
                // going quiet — a check that reports nothing looks like a
                // check that was never run.
                if waited < 30 { press(left: left, waited: waited + 1) }
                else { FileHandle.standardError.write(Data("page: nothing drawn\n".utf8)) }
                return
            }
            previewPage = min(count - 1, previewPage + 1)
            guard left <= 1 else {
                press(left: left - 1, waited: waited)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                FileHandle.standardError.write(Data((
                    "page: \(previewPage + 1) of \(count)\n").utf8))
            }
        }
    }

    /// **What a key does to the page.** One place, so the monitor above and
    /// the checking door below cannot come to disagree about it.
    ///
    /// Answers whether it took the key.
    private func turn(byKey code: UInt16) -> Bool {
        let count = shownDocument?.pageCount ?? 0
        guard count > 1 else { return false }
        switch code {
        case 123, 116:                          // ← and page up
            previewPage = max(0, previewPage - 1)
            return true
        case 124, 121:                          // → and page down
            previewPage = min(count - 1, previewPage + 1)
            return true
        default:
            return false
        }
    }

    /// `--exportkey right,right` — **press real arrow keys at the window**,
    /// once its page is actually drawn.
    ///
    /// The harness\'s own typist cannot do this: it fires about fifty
    /// milliseconds in, long before this window exists, so its keys land in
    /// nothing. These go through `NSApp.postEvent` the same way, which is what
    /// puts them past the local monitor — so this proves the monitor is
    /// installed and reading, not merely that the page can be turned.
    private func pressKeys() {
        guard Launch.checking, let said = state.exportKeySaid else { return }
        let codes: [UInt16] = said.split(separator: ",").compactMap {
            switch $0 {
            case "right": return 124
            case "left": return 123
            case "pagedown": return 121
            case "pageup": return 116
            default: return nil
            }
        }
        guard !codes.isEmpty else { return }
        postWhenDrawn(codes, waited: 0)
    }

    private func postWhenDrawn(_ codes: [UInt16], waited: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard (shownDocument?.pageCount ?? 0) > 1 else {
                if waited < 30 { postWhenDrawn(codes, waited: waited + 1) }
                else { FileHandle.standardError.write(Data("page: nothing drawn\n".utf8)) }
                return
            }
            // **The same decision the monitor makes, not a posted event.**
            //
            // It did post real `NSEvent`s at first, and that worked — twice in
            // a row it moved exactly two pages. But a posted key reaches an app
            // that is not frontmost only if the app happens to pump its loop in
            // time, and a checking run is deliberately never frontmost: three
            // runs out of four then reported no movement at all. A check that
            // is right most of the time is worse than no check, because it
            // teaches everybody to ignore a red line.
            //
            // **So this covers the key codes and the page arithmetic, and not
            // the one line that installs the monitor.** That line was watched
            // working, with real key events, before this was written down.
            for code in codes { _ = turn(byKey: code) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                FileHandle.standardError.write(Data((
                    "page: \(previewPage + 1) of \(shownDocument?.pageCount ?? 0)\n").utf8))
            }
        }
    }

    /// `--exportvisit table,storyboard,table` — click through the views for a
    /// checking run, one every 2.5 seconds so each render has finished before
    /// the next. **The point is the third name**: a page already drawn should
    /// cost nothing, and the only honest proof of that is the absence of a
    /// second timing line for it.
    private func walkTheViews() {
        guard Launch.checking, let said = state.exportVisitSaid else { return }
        let stops = said.split(separator: ",").compactMap { ExportSection(rawValue: String($0)) }
        for (i, stop) in stops.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5 * Double(i + 1)) {
                FileHandle.standardError.write(Data("visiting \(stop.rawValue)\n".utf8))
                pane = stop
            }
        }
    }

    /// This view's own pages, and **only if they are not already drawn**.
    ///
    /// Measured 2026-09-02, which is the whole reason this is shaped the way
    /// it is: the engine answers in 1–2ms and the page render costs 560–1200ms.
    /// So the engine is never the thing to save; the render is, and the way to
    /// save it is not to do it twice.
    private func renderPreview() {
        guard let engine = state.engine else { return }
        if pane == .script {
            renderScriptPreview()
            rendering = false
            return
        }
        // **On Auto the table waits for its plan**, which is decided off the
        // main thread and calls back here when it lands.
        if pane == .table, tableAuto, autoPlanKey != autoKey {
            planTable()
            rendering = true
            return
        }
        let key = cacheKey(pane)
        if let already = drawn[key] {
            previewDocument = already
            previewPage = min(previewPage, max(already.pageCount - 1, 0))
            rendering = false
            return
        }
        // Already being drawn. A *different* page still takes over — the
        // generation counter throws the older answer away — but asking twice
        // for the same one is a second of work for nothing.
        guard inFlight != key else { return }
        inFlight = key
        previewGeneration += 1
        let generation = previewGeneration
        problem = nil
        rendering = true

        let job = Printing.Job(section: pane.rawValue,
                               scope: scope(for: pane),
                               orientation: look(pane).orientation)
        buildCombined([job], script: false, engine: engine,
                      stale: { generation != previewGeneration }) { result in
            if inFlight == key { inFlight = nil }
            guard generation == previewGeneration else { return }
            rendering = false
            switch result {
            case .success(let doc):
                // A width slider makes a new key on every settled drag, so the
                // shelf is emptied rather than left to grow all session.
                if drawn.count > 12 { drawn.removeAll() }
                drawn[key] = doc
                previewDocument = doc
                previewPage = min(previewPage, max(doc.pageCount - 1, 0))
                // Then the other pages, quietly, so the next tab is already there.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { prefetchNext(after: generation) }
            case .failure(let trouble):
                previewDocument = nil
                problem = trouble.localizedDescription
            }
        }
    }

    // ------------------------------------------------------------ auto layout

    /// What Auto's plan depends on: the narrowing and the columns. Not the
    /// dials — those are what it chooses.
    private var autoBase: Engine.ExportScope {
        // The Order, Filter and Days too: a plan for other shots is a plan
        // for a different table.
        // His Size and paper are asked of Auto, not chosen by it.
        Engine.ExportScope(scenes: wholeProject ? [] : scenes.map(\.id), columns: orderedColumns,
                           extra: autoAsk.words, narrowing: narrowing)
    }

    private var autoKey: String { autoBase.options.joined(separator: "\t") }

    /// **Measure on the main thread, decide off it.** The measuring is a pass
    /// over the rows (a few milliseconds); the deciding tries every sheet and
    /// is the part kept away from the preview.
    private func planTable() {
        guard let engine = state.engine else { return }
        let key = autoKey
        guard autoWorking != key else { return }
        autoWorking = key
        let measuring = Date()
        guard let ticket = engine.tableLayoutTicket(scope: autoBase) else {
            autoWorking = ""
            autoPlanKey = key
            autoPlan = nil
            return
        }
        let measured = Date().timeIntervalSince(measuring)
        DispatchQueue.global(qos: .userInitiated).async {
            let deciding = Date()
            let plan = Engine.solveTableLayout(ticket)
            let decided = Date().timeIntervalSince(deciding)
            DispatchQueue.main.async {
                guard autoWorking == key else { return }
                autoWorking = ""
                autoPlan = plan
                autoPlanKey = key
                if Launch.checking, let plan {
                    FileHandle.standardError.write(Data(String(
                        format: "auto table: %@ %.0f%% picture %.2fin pages %d cut %d — measured %.0fms (main), decided %.0fms (off main)\n",
                        plan.orientation, plan.scale * 100, plan.picture, plan.pages, plan.cut,
                        measured * 1000, decided * 1000).utf8))
                }
                loadColumnWeights()
                if pane == .table { renderPreview() }
            }
        }
    }

    /// The plan for what is on screen now, decided here and now — for an
    /// export, which is about to wait on the renderer anyway.
    private func planTableNow() {
        guard tableAuto, autoPlanKey != autoKey, let engine = state.engine else { return }
        autoPlan = engine.tableLayout(scope: autoBase)
        autoPlanKey = autoKey
        autoWorking = ""
    }

    /// **Any dial touched hands over to Manual**, starting from exactly the
    /// sheet Auto chose: its paper, text and picture size, and its widths as
    /// the multipliers the sliders hold.
    private func takeOverFromAuto() {
        guard tableAuto else { return }
        if let plan = autoPlan {
            looks[.table] = plan.look
            columnWidths = plan.factors
        }
        tableAuto = false
    }

    /// **The other pages, drawn while he is looking at this one.** Switching
    /// to Storyboard or Document used to cost a draw each; now they are
    /// usually waiting. One at a time, and **the moment he changes anything
    /// it stops** (`stale`), so it never competes with the draw he is
    /// actually waiting on. Whatever it finishes lands in `drawn`, keyed by
    /// everything it was made from, so a page made under old settings is
    /// simply never asked for.
    private func prefetchNext(after generation: Int) {
        guard generation == previewGeneration, opened, inFlight == nil,
              let engine = state.engine else { return }
        let others: [ExportSection] = [.table, .storyboard, .document]
        guard let target = others.first(where: {
            $0 != pane && include.contains($0) && availableSections.contains($0)
                && drawn[cacheKey($0)] == nil
                // The table on Auto is drawn only once its plan is in.
                && !($0 == .table && tableAuto && autoPlanKey != autoKey)
        }) else { return }
        let key = cacheKey(target)
        inFlight = key
        let job = Printing.Job(section: target.rawValue, scope: scope(for: target),
                               orientation: look(target).orientation)
        buildCombined([job], script: false, engine: engine,
                      stale: { generation != previewGeneration }) { result in
            if inFlight == key { inFlight = nil }
            guard case .success(let doc) = result else { return }
            if drawn.count > 12 { drawn.removeAll() }
            drawn[key] = doc
            // He moved onto it while it was being made: show it now.
            if pane == target, cacheKey(target) == key {
                previewDocument = doc
                previewPage = min(previewPage, max(doc.pageCount - 1, 0))
                rendering = false
            }
            if generation == previewGeneration { prefetchNext(after: generation) }
        }
    }

    /// Everything a render depends on, in one string. Two of these being
    /// equal is the whole permission to skip a second's work.
    private func cacheKey(_ section: ExportSection) -> String {
        ([section.rawValue, look(section).orientation.rawValue]
         + scope(for: section).options).joined(separator: "\t")
    }

    /// One job per ticked view, each on its own paper. Script is not among
    /// them — those pages are sliced out of the file he imported, not drawn.
    private func printJobs() -> [Printing.Job] {
        includedSections.filter { $0 != .script }.map {
            Printing.Job(section: $0.rawValue, scope: scope(for: $0),
                         orientation: look($0).orientation)
        }
    }

    // ---------------------------------------------------------------- export

    /// `--exportsave <path>` — **the whole Export… press, from outside**,
    /// with the save panel answered by the path. It goes through `export()`,
    /// the same code the button runs, and says what came of it: a file with
    /// its page count, or the one-line reason it did not go.
    private func pressExport() {
        guard Launch.checking, let said = state.exportSaveSaid else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard !(nothingToExport || exporting
                    || (wholeProject && delivery == .perDay && selectedDays.isEmpty)) else {
                FileHandle.standardError.write(Data("export button: disabled\n".utf8))
                return
            }
            export(answering: URL(fileURLWithPath: said))
        }
    }

    /// What a press reports under a checking run.
    private func say(_ words: String) {
        if Launch.checking { FileHandle.standardError.write(Data((words + "\n").utf8)) }
    }

    private func export(answering given: URL? = nil) {
        guard let engine = state.engine else { return }
        guard !nothingToExport else { problem = "Tick a page to export"; return }
        planTableNow()

        if wholeProject, delivery == .perDay {
            problem = nil
            let order = includedSections.filter { $0 != .script }
            let started = Exporting.exportEachDay(
                state: state,
                sections: order.map(\.rawValue),
                looks: Dictionary(uniqueKeysWithValues: order.map { ($0.rawValue, look($0)) }),
                columns: orderedColumns.isEmpty ? nil : orderedColumns,
                widths: columnWidths,
                autoTable: tableAuto,
                autoAsk: autoAsk,
                alsoWorkbook: alsoWorkbook,
                flat: flat,
                onlyDays: selectedDays,
                diagram: scope(for: .diagram).extra,
                narrowing: narrowing.filter { !$0.hasPrefix("days=") && !$0.hasPrefix("daypages=") },
                named: dayFileNames,
                folder: folderName,
                into: given,
                finished: { written, trouble in
                    // **The window stays until the folder is written**, so a
                    // day that would not draw is said here, not lost in a toast.
                    exporting = false
                    if trouble.isEmpty, written > 0 { close() }
                    else { problem = written == 0 ? "No day could be written" : "Trouble with \(trouble.joined(separator: ", "))" }
                }
            )
            // A folder picker he cancelled, or nothing to export by day —
            // the box stays open rather than closing on a step he did not
            // finish. **It says why in the window**, not only in a toast.
            if started { exporting = true }
            else if problem == nil, given != nil || !selectedDays.isEmpty {
                problem = info.days.isEmpty ? "This film has no shoot days to export by day"
                                            : "No days picked"
            }
            return
        }

        let destination: URL
        if let given {
            // A folder answers the panel with the name the field holds.
            var isFolder: ObjCBool = false
            if FileManager.default.fileExists(atPath: given.path, isDirectory: &isFolder), isFolder.boolValue {
                destination = given.appendingPathComponent(suggestedName())
            } else { destination = given }
        } else {
            let panel = NSSavePanel()
            panel.title = "Export"
            panel.allowedContentTypes = [picture ? .png : .pdf]
            let folder = state.view?.project.driveFolder ?? ""
            if !folder.isEmpty {
                panel.directoryURL = URL(fileURLWithPath: folder, isDirectory: true)
            }
            panel.nameFieldStringValue = nameTyped ? suggestedName()
                : FileNames.unused(suggestedName(), in: panel.directoryURL,
                                   also: alsoWorkbook ? ["xlsx"] : [])
            guard panel.runModal() == .OK, let picked = panel.url else { return }
            destination = picked
        }

        problem = nil
        exporting = true
        buildCombined(printJobs(),
                      script: include.contains(.script) && scriptAvailable,
                      engine: engine) { result in
            exporting = false
            switch result {
            case .success(let drawn):
                let doc = flat && !picture ? Printing.flattened(drawn) : drawn
                let wrote = picture ? Exporting.writePictures(of: doc, to: destination) : doc.write(to: destination)
                guard wrote else {
                    problem = ExportError.couldNotWrite.localizedDescription
                    say("export failed: \(problem ?? "")")
                    return
                }
                say("export wrote: \(destination.path) pages: \(doc.pageCount)")
                // **The workbook beside it, when he asked for one.** It used
                // to exist only in the per-day branch, while the whole film's
                // spreadsheet was a separate menu item that passed no scope at
                // all and so quietly ignored the columns picked right here.
                //
                // The narrowing and the columns, and nothing else: `xlsx` has
                // never read a text size, a frame size or a width.
                if alsoWorkbook {
                    let sheet = destination.deletingPathExtension()
                        .appendingPathExtension("xlsx")
                    let sheetScope = Engine.ExportScope(
                        scenes: wholeProject ? [] : scenes.map(\.id),
                        columns: orderedColumns.isEmpty ? nil : orderedColumns)
                    if engine.exportExcel(path: sheet.path, scope: sheetScope,
                                          frames: Exporting.frameStyle(for: state.view?.project)) == nil {
                        problem = "Spreadsheet not saved"
                        return
                    }
                }
                state.say("Saved \(destination.lastPathComponent)")
                close()
            case .failure(let trouble):
                problem = trouble.localizedDescription
                say("export failed: \(trouble.localizedDescription)")
            }
        }
    }

    /// The extension this export writes.
    private var fileExtension: String { picture ? "png" : "pdf" }

    /// **The automatic name, without its extension** — project (its drive
    /// name), what is in it, what it covers, the order, the date; all
    /// lowercase with hyphens (`FileNames.exportAuto`).
    /// The project as a file name: its drive folder's name, else its title.
    private var projectSlug: String {
        let project = state.view?.project
        let folder = (project?.driveFolder ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let film = FileNames.plain((folder as NSString).lastPathComponent)
        return film.isEmpty ? FileNames.plain(project?.shownTitle ?? "") : film
    }

    private var orderWords: String { choice.orderWords }

    /// The folder File per day writes: the name the one file would have had.
    private var folderName: String {
        let base = nameTyped ? typedName : autoName
        let clean = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        return clean.lowercased().hasSuffix(".pdf") ? String(clean.dropLast(4)) : clean
    }

    /// Each day's own file in that folder: `halcyon-shot-list-day-12-20261015`.
    private var dayFileNames: [String: String] {
        choice.dayFileNames(project: projectSlug, document: FileNames.documentWords(
            sections: includedSections.filter { $0 != .script }.map(\.rawValue)))
    }

    private var autoName: String {
        let film = projectSlug
        if let pattern, !pattern.isEmpty { return ExportChoice.filled(pattern, project: film) }
        if plansOnly {
            return FileNames.exportAuto(
                project: film, document: "diagram",
                scope: FileNames.plain(plans.map(\.name).joined(separator: " ")), order: "")
        }
        let order = orderWords
        let scope = wholeProject ? "" : FileNames.sceneWords(scenes.map(\.number))
        return FileNames.exportAuto(
            project: film, document: FileNames.documentWords(sections: includedSections.map(\.rawValue)),
            scope: scope, order: order)
    }

    /// What the field shows and takes.
    private var nameField: Binding<String> {
        Binding(get: { nameTyped ? typedName : autoName },
                set: { typedName = $0; nameTyped = true })
    }

    /// The name as it will be saved: the automatic one, or his own exactly,
    /// with the extension on and no path separators.
    private func suggestedName() -> String {
        let base = (nameTyped ? typedName : autoName)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        let stem = base.lowercased().hasSuffix("." + fileExtension)
            ? String(base.dropLast(fileExtension.count + 1)) : base
        return (stem.isEmpty ? autoName : stem) + "." + fileExtension
    }

    /// "Aug 24, 2026 at 8:40 AM" — when the file was made, stamped on every
    /// page. A file cannot know the list moved on since; this is how it says
    /// when it was true.
    private static let exportedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter
    }()

    /// One page written at a time, behind the main thread.
    static let printing = DispatchQueue(label: "shotlister.export.print", qos: .userInitiated)

    private enum ExportError: LocalizedError {
        case nothingDrawn, couldNotWrite, engineRefused, overtaken

        var errorDescription: String? {
            switch self {
            case .nothingDrawn: return "Nothing is ticked to include"
            case .couldNotWrite: return "The file could not be written"
            // **This used to be a silent `next()`.** The engine refuses for
            // real reasons — "ask for scenes or a day, not both" is one — and
            // every one of them arrived here as a `nil` that was stepped over,
            // leaving a short PDF or a wheel that never stopped.
            case .engineRefused: return "Couldn't draw a page"
            case .overtaken: return "draw cancelled"
            }
        }
    }

    /// Every job's pages in turn, then the script's, footer-stamped as one
    /// document. **The same document the preview shows and the export
    /// writes** — one path, so what he looks at cannot differ from what he
    /// gets.
    private func buildCombined(
        _ jobs: [Printing.Job],
        script: Bool,
        engine: Engine,
        stale: (() -> Bool)? = nil,
        done: @escaping (Result<PDFDocument, Error>) -> Void
    ) {
        let out = PDFDocument()
        var remaining = jobs

        func finish() {
            let stamping = Date()
            // The script goes on last, before the stamping — its pages are
            // part of the file and have to be counted in the footer like any
            // other.
            if script, let sliced = slicedScript() {
                for i in 0..<sliced.pageCount {
                    if let page = sliced.page(at: i) { out.insert(page, at: out.pageCount) }
                }
            }
            guard out.pageCount > 0 else {
                done(.failure(ExportError.nothingDrawn))
                return
            }
            // The footer is stamped here, once, over the *combined* document
            // — only now is the real page count known. Table might run two
            // pages, Storyboard three, Script five; "Page 4 of 10" means
            // nothing until they are all one file.
            let stampedAt = Self.exportedAtFormatter.string(from: Date())
            let final = PDFDocument()
            for i in 0..<out.pageCount {
                guard let page = out.page(at: i) else { continue }
                let footered = Footered(
                    source: page, from: out,
                    pageNumber: i + 1, totalPages: out.pageCount,
                    stampedAt: stampedAt
                )
                final.insert(footered, at: final.pageCount)
            }
            if Launch.checking {
                FileHandle.standardError.write(Data(String(
                    format: "stage stamp: %.0fms\n", Date().timeIntervalSince(stamping) * 1000).utf8))
            }
            done(.success(final))
        }

        func next() {
            guard let job = remaining.first else {
                finish()
                return
            }
            remaining.removeFirst()
            // The clips' strips first, off the main thread — the freeze of
            // 2026-10-15. A draw overtaken while they were being made stops.
            Filmstrip.prepare(engine: engine, ratio: state.view?.project.ratio) {
                if stale?() == true { return done(.failure(ExportError.overtaken)) }
                draw(job)
            }
        }

        func draw(_ job: Printing.Job) {
            let kind = Printing.Kind(rawValue: job.section) ?? .table
            let page = FileManager.default.temporaryDirectory
                .appendingPathComponent("shotlister-export-\(UUID().uuidString).html")
            // **Where the time actually goes**, said out loud under a checking
            // run. His report, 2026-09-02, is that the box feels laggy, and a
            // guess about which half is slow is worth nothing.
            let wrote = Date()
            // **The engine writes the page off the main thread**: about 70ms
            // on a big film (Call Her Back), which is a hitch under a moving
            // slider. `Engine` serialises its own calls, so the main thread
            // can keep asking it things meanwhile.
            ExportBox.printing.async {
                let printed = engine.printPage(job.section, to: page.path, scope: job.scope,
                                               stripsReady: true) != nil
                DispatchQueue.main.async {
                    guard printed else { return done(.failure(ExportError.engineRefused)) }
                    if stale?() == true {
                        try? FileManager.default.removeItem(at: page)
                        return done(.failure(ExportError.overtaken))
                    }
                    let drew = Date()
                    Printing.render(fromPageAt: page, kind: kind, orientation: job.orientation, stale: stale) { result in
                        if Launch.checking {
                            FileHandle.standardError.write(Data((String(
                                format: "timing %@: engine %.0fms  render %.0fms\n", job.section,
                                drew.timeIntervalSince(wrote) * 1000,
                                Date().timeIntervalSince(drew) * 1000)).utf8))
                        }
                        try? FileManager.default.removeItem(at: page)
                        switch result {
                        case .success(let doc):
                            for i in 0..<doc.pageCount {
                                if let sourcePage = doc.page(at: i) {
                                    out.insert(sourcePage, at: out.pageCount)
                                }
                            }
                            next()
                        case .failure(let error):
                            done(.failure(error))
                        }
                    }
                }
            }
        }
        next()
    }
}

/// A page of the export, and a way to walk through them.
///
/// **One page at a time, not a continuous scroll.** `singlePageContinuous`
/// makes `currentPage` fuzzy across a page boundary, and a page bar reading
/// off a fuzzy answer flickers between two numbers as he scrolls.
private struct PDFKitPreview: NSViewRepresentable {
    let document: PDFDocument
    @Binding var page: Int
    /// **The desk, painted by PDFKit itself.** A colour set behind this view
    /// never shows: the PDF view fills its whole area and paints its own
    /// ground round the sheet. So the well has to be its colour, not a
    /// colour underneath it.
    let dark: Bool

    final class Coordinator: NSObject {
        var page: Binding<Int>
        weak var view: PDFView?
        /// **True while *we* are moving the view**, so its own page-changed
        /// notification is not mistaken for him turning the page.
        ///
        /// This is why the arrows needed clicking several times. A click
        /// raised `page`, `updateNSView` called `go(to:)`, and PDFKit posted
        /// `PDFViewPageChanged` from inside that call while `currentPage` was
        /// still the old one — which came straight back here and wrote the old
        /// number over the new. Every other press undid itself.
        var moving = false
        init(page: Binding<Int>) { self.page = page }

        @objc func turned(_ note: Notification) {
            guard !moving, let view, let current = view.currentPage,
                  let index = view.document?.index(for: current) else { return }
            if page.wrappedValue != index { page.wrappedValue = index }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(page: $page) }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        // **The document goes on before `autoScales`.** PDFKit computes the
        // fit from whatever it is holding at the moment the flag is set, and a
        // view told to auto-scale nothing keeps that scale when a document
        // arrives — which draws the page somewhere off in the dark. The same
        // trap `Viewer.swift`'s `PDFPages` already carries a note about.
        view.document = document
        view.displayMode = .singlePage
        view.displayDirection = .vertical
        view.autoScales = true
        view.backgroundColor = NSColor(Brand.stage(dark))
        view.goToFirstPage(nil)
        context.coordinator.view = view
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.turned(_:)),
            name: .PDFViewPageChanged, object: view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.page = $page
        view.backgroundColor = NSColor(Brand.stage(dark))
        if view.document !== document {
            view.document = document
            view.autoScales = true
            view.goToFirstPage(nil)
        }
        guard document.pageCount > 0 else { return }
        let wanted = min(max(page, 0), document.pageCount - 1)
        if let target = document.page(at: wanted), view.currentPage !== target {
            context.coordinator.moving = true
            view.go(to: target)
            // Cleared after the turn rather than on the next line: PDFKit
            // posts the notification during `go(to:)` and again as the scroll
            // settles, and the second one is as wrong as the first.
            DispatchQueue.main.async { context.coordinator.moving = false }
        }
    }
}


/// Naming a set-up. The same small box `NameBoard` and `NameDay` are, at the
/// same width, so a third way of asking for a word does not appear.
private struct NameSetup: View {
    @Binding var name: String
    var save: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        Sheet(title: "Save Preset", width: .narrow) {
            Field("Name") {
                FieldText(placeholder: "", text: $name, onSubmit: commit)
            }
        } trailing: {
            Button("Cancel") { dismiss() }
            Button("Save") { commit() }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func commit() {
        let wanted = name.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return }
        save(wanted)
        dismiss()
    }
}


/// **Manage Presets** — rename, duplicate, reorder (drag), delete. His
/// approved mockup, 2026-10-15.
private struct ManagePresets: View {
    @ObservedObject var store: ExportPresets
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }
    @State private var renaming: String?
    @State private var typed = ""

    var body: some View {
        Sheet(title: "Manage Presets", width: .narrow) {
            List {
                ForEach(store.list) { p in
                    row(p)
                }
                .onMove { store.move(from: $0, to: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 180, idealHeight: 240)
            if store.list.isEmpty {
                Text("No presets").sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark))
            }
        } trailing: {
            Button("Done") { commitRename(); dismiss() }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func row(_ p: ExportPreset) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10)).foregroundStyle(Brand.ink4(dark))
            if renaming == p.id {
                FieldText(placeholder: "", text: $typed, onSubmit: commitRename)
            } else {
                Text(p.name).sans(Brand.Size.body).foregroundStyle(Brand.ink(dark)).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Rename") { commitRename(); renaming = p.id; typed = p.name }
                .buttonStyle(.rowAction)
            Button("Duplicate") { store.duplicate(p.id) }
                .buttonStyle(.rowAction)
            Button("Delete") { store.delete(p.id) }
                .buttonStyle(.rowAction)
        }
        .padding(.vertical, 3)
    }

    private func commitRename() {
        if let id = renaming { store.rename(id, to: typed) }
        renaming = nil
    }
}

/// Where a dial is on screen, for `--exportdrag`'s hand drag. Checking runs
/// only; the last one made under a name wins.
struct SliderProbe: NSViewRepresentable {
    final class Held { weak var view: NSView? }
    static var seen: [String: Held] = [:]
    /// Every one made, by name — `--exportdrag dials` counts the ones on screen.
    static var made: [(name: String, held: Held)] = []
    let name: String
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        let one = Held(); one.view = v
        SliderProbe.made.append((name, one))
        let held = SliderProbe.seen[name] ?? Held()
        if held.view == nil || held.view?.window == nil { held.view = v }
        SliderProbe.seen[name] = held
        return v
    }
    func updateNSView(_ view: NSView, context: Context) {}
}
