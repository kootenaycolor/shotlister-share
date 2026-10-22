import SwiftUI
import PDFKit
import UIKit

/// **The Mac's export window, in a shape a thumb can reach.** The same four
/// pages, the same split into days, the same spreadsheet beside the PDF, the
/// same dials per page, the same saved set-ups — and the same real PDF as the
/// preview, because a preview made a different way is a promise the export
/// does not have to keep.
///
/// Opened from the ⋯ menu for the whole film, or from a scene's own menu for
/// that scene. Everything it makes goes into a scratch folder and then to the
/// share sheet; the phone has no save panel and wants none.
struct ExportSheet: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss

    /// Where it was opened from: a scene's own menu offers that scene.
    var scene: Engine.Scene?

    // ---- what he picked ------------------------------------------------------

    @State private var include: Set<Exporting.Section> = [.table, .storyboard, .document]
    @State private var looks: [Exporting.Section: Exporting.Look] = [:]
    @State private var delivery: Exporting.Delivery = .wholeFilm
    /// Off unless asked for — his instruction, 2026-09-16.
    @State private var alsoWorkbook = false
    /// **Flat or editable** — his ask, 2026-09-16. Flat bakes every page into
    /// a picture (`Exporting.flattened`); editable is the PDF as it was.
    @State private var flat = false
    @State private var frameStyle: Exporting.FrameStyle = .forGoogleSheets
    @State private var selectedDays: Set<String> = []
    @State private var includedColumns: Set<String> = []
    @State private var columnWidths: [String: Double] = [:]
    /// Which page he is looking at and tuning.
    @State private var pane: Exporting.Section = .table

    // ---- what the screen is holding -----------------------------------------

    @State private var opened = false
    @State private var script: Exporting.KeptScript?
    @State private var scriptChecked = false
    @State private var preview: PDFDocument?
    @State private var previewPage = 0
    @State private var drawn: [String: PDFDocument] = [:]
    @State private var previewWork: Task<Void, Never>?
    @State private var rendering = false
    @State private var problem: String?
    @State private var exporting = false
    @State private var made: Made?
    @State private var namingPreset = false
    @State private var presetName = ""

    // ---- order, filter, days, name, presets (the Mac's redesign, 2026-10-15)

    @State private var arrange: ExportArrange = .table
    @State private var useFilter = true
    @State private var info: ExportInfo = .empty
    @State private var typedName = ""
    @State private var nameTyped = false
    @State private var pattern: String?
    @ObservedObject private var presets = ExportPresets.shared
    @State private var presetId = ""
    @State private var presetBase: ExportPreset?
    @State private var filterNotUsed = false
    @State private var managing = false
    /// **Auto lays the table out** — the Mac's, on by default; any dial
    /// touched hands over to Manual from exactly what Auto chose.
    @State private var tableAuto = true
    /// Auto's Size and paper (2026-10-16) — the Mac's; neither makes it Manual.
    @State private var autoAsk = AutoAsk()
    @State private var autoPlan: Exporting.TableLayout?
    @State private var autoPlanKey = ""
    /// A simulator photograph of the settings alone (`--exportset form=1`).
    @State private var formOnly = false

    /// The files, ready for the share sheet.
    struct Made: Identifiable {
        let id = UUID()
        let files: [URL]
    }

    private var wholeFilm: Bool { scene == nil }

    @State private var pickingColumns = false
    @State private var pickingDays = false

    var body: some View {
        NavigationStack {
            // **The page stays put; the controls scroll under it.** His ask,
            // 2026-09-16: see the table's controls and the preview at the
            // same time. So the preview is docked above the form rather than
            // being its first section, and the page being tuned comes right
            // after the four names — the dial and the thing it moves, on one
            // screen.
            GeometryReader { space in
                VStack(spacing: 0) {
                    previewPane
                        .frame(height: formOnly ? 0 : max(220, space.size.height * 0.36))
                        .clipped()
                    pageBar
                        .padding(.horizontal, 20).padding(.vertical, 8)
                        .background(Style.card)
                    if let whyNot {
                        Text(whyNot).font(.footnote).foregroundStyle(.orange)
                            .frame(maxWidth: .infinity).padding(.bottom, 6)
                            .background(Style.card)
                    }
                    Divider()
                    Form {
                        presetSection
                        orderSection
                        if wholeFilm { daysSection }
                        nameSection
                        pagesSection
                        lookSection
                        pdfSection
                        alsoSection
                    }
                }
            }
            .navigationTitle(scene.map { "Scene \($0.number)" } ?? "Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Export") { export() }
                        .disabled(!canExport)
                }
            }
            .overlay {
                if exporting {
                    ProgressView().controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
            .alert("That didn't work", isPresented: Binding(
                get: { problem != nil && !rendering }, set: { if !$0 { problem = nil } }
            )) {
                Button("OK") { problem = nil }
            } message: {
                Text(problem ?? "")
            }
            .alert("Save Preset", isPresented: $namingPreset) {
                TextField("Name", text: $presetName)
                Button("Save") { saveAsPreset(presetName) }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $managing) {
                NavigationStack { ManagePresets(store: presets) }
            }
            .sheet(item: $made) { made in
                ShareSheet(items: made.files)
            }
            // **Half-height, so the page stays in view** — a width slider is
            // only worth moving while the table it moves is on screen.
            .sheet(isPresented: $pickingColumns) {
                NavigationStack {
                    ColumnsPicker(columns: availableColumns,
                                  picked: $includedColumns,
                                  widths: $columnWidths,
                                  withWidths: pane == .table && !tableAuto,
                                  weights: { columnWeights() })
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { pickingColumns = false }
                            }
                        }
                }
                .presentationDetents([.fraction(0.42), .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.42)))
            }
            .sheet(isPresented: $pickingDays) {
                NavigationStack {
                    DaysPicker(info: info, picked: $selectedDays)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { pickingDays = false }
                            }
                        }
                }
                .presentationDetents([.fraction(0.42), .large])
            }
        }
        .onAppear(perform: open)
        .onChange(of: pane) { _, _ in previewPage = 0; schedulePreview(now: true) }
        .onChange(of: include) { _, _ in remember() }
        .onChange(of: alsoWorkbook) { _, _ in remember() }
        .onChange(of: flat) { _, _ in remember() }
        .onChange(of: selectedDays) { _, _ in
            remember()
            if arrange == .schedule { schedulePreview() }
        }
        .onChange(of: arrange) { _, now in
            if now != .schedule, delivery == .perDay { delivery = .wholeFilm }
            schedulePreview()
        }
        .onChange(of: useFilter) { _, _ in schedulePreview() }
        .onChange(of: tableAuto) { _, _ in remember(); if pane == .table { schedulePreview() } }
        .onChange(of: autoAsk) { _, _ in remember(); if pane == .table, tableAuto { schedulePreview() } }
        .onChange(of: includedColumns) { _, _ in
            remember()
            if pane == .table || pane == .document { schedulePreview() }
        }
        .onChange(of: looks) { was, now in
            remember()
            if was[pane] != now[pane] { schedulePreview() }
        }
        .onChange(of: columnWidths) { _, _ in
            remember()
            if pane == .table { schedulePreview() }
        }
        .onChange(of: delivery) { _, now in
            remember()
            // A scene's own export has no split; a remembered "per day"
            // must not strip its Script on the way in.
            guard wholeFilm, now == .perDay else { return }
            // Neither belongs to "each day": Script has no notion of which
            // scenes are whose day, and the day already says which day it is
            // on every one of its own rows.
            include.remove(.script)
            includedColumns.remove("day")
            if pane == .script { pane = .table }
            if selectedDays.isEmpty { selectedDays = choice.allDays }
        }
    }

    // ---- the sections --------------------------------------------------------

    private var previewPane: some View {
            ZStack {
                Color(.secondarySystemBackground)
                if let preview {
                        // The page he is leaving stays up while the next one is
                    // drawn; the page bar says so, quietly (the Mac's way).
                    Paper(document: preview, page: $previewPage)
                } else if rendering {
                    ProgressView()
                } else if pane == .script {
                    Text(scriptChecked ? "No script" : "")
                        .foregroundStyle(.secondary)
                } else if let problem {
                    Text(problem).font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding()
                } else {
                    Text("Nothing to show").foregroundStyle(.secondary)
                }
            }
    }

    /// How long the thing is, and a way to reach page seven.
    private var pageBar: some View {
        let count = preview?.pageCount ?? 0
        return HStack {
            Button { previewPage = max(0, previewPage - 1) } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(previewPage <= 0)
            Spacer()
            Text(count > 0 ? "Page \(min(previewPage + 1, count)) of \(count)" : (rendering ? "" : "No pages"))
                .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                // **The last page stays up while the next is drawn**, and says
                // so here — the Mac's word, never a wheel over the page.
                .overlay(alignment: .trailing) {
                    if rendering && count > 0 {
                        Text("Updating…").font(.footnote).foregroundStyle(.tertiary)
                            .fixedSize().offset(x: 84)
                    }
                }
            Spacer()
            Button { previewPage = min(max(count - 1, 0), previewPage + 1) } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(previewPage >= count - 1)
        }
        .buttonStyle(.borderless)
    }

    /// **The four pages, and which of them are in the file.** Two hit regions
    /// per row, the Mac's own: the tick decides whether the page is in the
    /// file, the name decides which one you are looking at.
    private var pagesSection: some View {
        Section("Pages") {
            ForEach(Exporting.Section.allCases) { section in
                pageRow(section)
            }
        }
    }

    private func pageRow(_ section: Exporting.Section) -> some View {
        let on = pane == section
        let possible = availableSections.contains(section)
        let usable = section != .script || script != nil
        let ticked = include.contains(section)
        return HStack {
            Text(section.title)
                .fontWeight(on ? .semibold : .regular)
                .foregroundStyle(possible && usable ? .primary : .secondary)
            Spacer()
            // **The chosen row is the quiet grey block, the tick in the
            // film's colour** — the Mac's ruling, 2026-09-14.
            Image(systemName: ticked ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(ticked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .contentShape(Rectangle())
                .onTapGesture {
                    guard possible, usable else { return }
                    if ticked { include.remove(section) } else { include.insert(section) }
                }
        }
        .contentShape(Rectangle())
        .onTapGesture { if possible { pane = section } }
        .listRowBackground(on ? Color(.systemFill) : nil)
        .opacity(possible ? 1 : 0.45)
    }

    /// Under `-ExportCheck`, what an export made, written where a check can
    /// read it: each file, its folder and its pages.
    static func sayForCheck(_ files: [URL]) {
        guard ExportPresets.checking else { return }
        let lines = files.map { url -> String in
            let pages = PDFDocument(url: url)?.pageCount ?? 0
            return "\(url.deletingLastPathComponent().lastPathComponent)/\(url.lastPathComponent) pages: \(pages)"
        }
        let into = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? lines.joined(separator: "\n").write(to: into.appending(path: "export-check.txt"), atomically: true, encoding: .utf8)
        for url in files {
            try? FileManager.default.removeItem(at: into.appending(path: url.lastPathComponent))
            try? FileManager.default.copyItem(at: url, to: into.appending(path: url.lastPathComponent))
        }
    }

    /// `--exportset arrange=schedule;days=12-18+22;output=perday;use=Tomorrow;edit=script;manage=1`
    /// — a simulator photograph's settings, the Mac's `--exportset`.
    private func setFromOutside() {
        let args = CommandLine.arguments
        guard let at = args.firstIndex(of: "--exportset"), at + 1 < args.count else { return }
        set(said: args[at + 1])
    }

    private func set(said: String) {
        for pair in said.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "use": if let p = presets.named(kv[1]) { applyPreset(p) }
            case "arrange", "edit": arrange = ExportArrange(rawValue: kv[1]) ?? arrange
            case "filter": useFilter = kv[1] != "none"
            case "output": delivery = kv[1] == "perday" ? .perDay : .wholeFilm
            case "manage": managing = true
            case "pickdays": pickingDays = true
            case "pickcolumns": pickingColumns = true
            case "form": formOnly = true
            case "autosize": autoAsk = AutoAsk(size: Double(kv[1]) ?? 1, paper: autoAsk.paper)
            case "autopaper": autoAsk = AutoAsk(size: autoAsk.size, paper: kv[1])
            case "off": includedColumns.remove(kv[1])
            case "on": includedColumns.insert(kv[1])
            case "layout": if kv[1] == "manual" { takeOverFromAuto() } else { tableAuto = true }
            case "exportnow": DispatchQueue.main.asyncAfter(deadline: .now() + 3) { export() }
            case "days":
                var numbers: [Int] = []
                for part in kv[1].split(separator: "+") {
                    let ends = part.split(separator: "-").compactMap { Int($0) }
                    if ends.count == 2 { numbers += Array(min(ends[0], ends[1])...max(ends[0], ends[1])) }
                    else if let one = ends.first { numbers.append(one) }
                }
                selectedDays = ExportDays.pick(DaysRule(kind: "numbers", numbers: numbers, unscheduled: false), in: info)
            default: break
            }
        }
    }

    /// `-ExportCheck --exportthen "autosize=0.7|autopaper=portrait|off=notes"`
    /// — **does the page follow each change?** Waits for the first page,
    /// then makes each change in turn (`set(said:)`'s words, `|` between
    /// steps) and writes, for each, whether the page on screen was drawn
    /// again and how many pages it has: `Documents/export-preview.txt`.
    private func followFromOutside() {
        let args = CommandLine.arguments
        guard ExportPresets.checking, let at = args.firstIndex(of: "--exportthen"), at + 1 < args.count else { return }
        let steps = args[at + 1].split(separator: "|").map(String.init)
        Task { @MainActor in
            func settled() async -> PDFDocument? {
                for _ in 0..<150 {
                    try? await Task.sleep(for: .milliseconds(200))
                    if let preview, !rendering { return preview }
                }
                return nil
            }
            guard var shown = await settled() else { return }
            try? await Task.sleep(for: .milliseconds(600))
            var lines = ["start pages \(shown.pageCount)"]
            for step in steps {
                set(said: step)
                try? await Task.sleep(for: .milliseconds(900))
                guard let now = await settled() else { lines.append("\(step) nothing drawn"); break }
                try? await Task.sleep(for: .milliseconds(600))
                let fresh = preview ?? now
                lines.append("\(step) redrawn \(fresh === shown ? "no" : "yes") pages \(fresh.pageCount)"
                             + " layout \(tableAuto ? "auto" : "manual")")
                shown = fresh
            }
            let into = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try? lines.joined(separator: "\n").write(to: into.appending(path: "export-preview.txt"),
                                                      atomically: true, encoding: .utf8)
        }
    }

    // ---- presets, order, filter, days, name --------------------------------

    private var presetInUse: ExportPreset? { presetId.isEmpty ? nil : presets.preset(presetId) }

    private var presetEdited: Bool {
        guard presetInUse != nil, let presetBase else { return false }
        return !current().sameSettings(as: presetBase)
    }

    /// **Presets, first** — the same list as the Mac's, through the server.
    private var presetSection: some View {
        Section {
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
                Button("Save as Preset…") { presetName = presetInUse?.name ?? ""; namingPreset = true }
                Button("Manage Presets…") { managing = true }
            } label: {
                HStack {
                    Text("Preset")
                    Spacer()
                    if presetEdited { Text("Edited").foregroundStyle(.orange) }
                    Text(presetInUse?.name ?? "As in Table").foregroundStyle(.secondary)
                }
            }
            .tint(.primary)
            if presetEdited {
                Button("Update Preset") { updatePreset() }
            }
        }
    }

    /// **Order, and the Table's filter under it.**
    private var orderSection: some View {
        Section("Order") {
            Picker("Order", selection: $arrange) {
                Text("As in Table").tag(ExportArrange.table)
                Text("Script").tag(ExportArrange.script)
                Text("Schedule").tag(ExportArrange.schedule)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if arrange == .table, !choice.tableSortName.isEmpty {
                LabeledContent("Sorted by", value: choice.tableSortName)
            }
            if !info.filter.isEmpty {
                HStack {
                    Text(useFilter ? "Filter: " + info.filter.joined(separator: ", ") : "No filter")
                        .lineLimit(1)
                    Spacer()
                    Button(useFilter ? "Clear for export" : "Use Table filter") { useFilter.toggle() }
                        .buttonStyle(.borderless)
                }
            }
            if filterNotUsed {
                Text("Filter not used").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    /// **Days, for a Schedule** — quick picks, a range, and the list grouped
    /// by shoot and week a tap away. Greyed for the other orders.
    @ViewBuilder private var daysSection: some View {
        let on = arrange == .schedule && !info.days.isEmpty
        Section("Days") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(quickRules, id: \.title) { rule in
                        let lit = on && picked(rule)
                        Button(rule.title) {
                            selectedDays = ExportDays.pick(rule, in: info)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(lit ? Color.accentColor : Color(.tertiarySystemFill)))
                        .foregroundStyle(lit ? Color.white : Color.primary)
                        .buttonStyle(.plain)
                    }
                }
            }
            if on {
                Picker("From", selection: Binding(
                    get: { ExportDays.numbersOf(selectedDays, in: info).first ?? 1 },
                    set: { pickRange(from: $0, to: max($0, ExportDays.numbersOf(selectedDays, in: info).last ?? $0)) })) {
                    ForEach(1...max(info.days.count, 1), id: \.self) { n in Text(dayWords(n)).tag(n) }
                }
                Picker("To", selection: Binding(
                    get: { ExportDays.numbersOf(selectedDays, in: info).last ?? info.days.count },
                    set: { pickRange(from: min($0, ExportDays.numbersOf(selectedDays, in: info).first ?? $0), to: $0) })) {
                    ForEach(1...max(info.days.count, 1), id: \.self) { n in Text(dayWords(n)).tag(n) }
                }
                Button { pickingDays = true } label: {
                    LabeledContent("Picked", value: ExportDays.summary(selectedDays, in: info))
                }
                .foregroundStyle(.primary)
                Picker("Output", selection: $delivery) {
                    Text("One File").tag(Exporting.Delivery.wholeFilm)
                    Text("File per Day").tag(Exporting.Delivery.perDay)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .disabled(!on)
        .opacity(on ? 1 : 0.45)
    }

    private var quickRules: [DaysRule] {
        var out: [DaysRule] = [.all, DaysRule(kind: "next"), DaysRule(kind: "thisweek"), DaysRule(kind: "nextweek")]
        if info.shoots.count >= 2 { out += info.shoots.indices.map { DaysRule(kind: "shoot", shoot: $0 + 1) } }
        return out
    }

    private func picked(_ rule: DaysRule) -> Bool {
        let now = ExportDays.rule(for: selectedDays, in: info)
        return now.kind == rule.kind && (rule.kind != "shoot" || now.shoot == rule.shoot)
    }

    private func dayWords(_ number: Int) -> String {
        guard info.days.indices.contains(number - 1) else { return "" }
        let day = info.days[number - 1]
        let date = ExportDays.date(day.date).map(ExportDays.short) ?? day.date
        return "Day \(number)" + (date.isEmpty ? "" : "  \(date)")
    }

    private func pickRange(from: Int, to: Int) {
        var picked = ExportDays.pick(DaysRule(kind: "range", from: from, to: to, unscheduled: false), in: info)
        if selectedDays.contains(ExportDays.unscheduled) { picked.insert(ExportDays.unscheduled) }
        selectedDays = picked
    }

    private var nameSection: some View {
        Section(wholeFilm && delivery == .perDay ? "Folder Name" : "File Name") {
            TextField("", text: Binding(get: { nameTyped ? typedName : autoName },
                                        set: { typedName = $0; nameTyped = true }))
                .font(.footnote.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if wholeFilm && delivery == .perDay {
                Text("\(selectedDays.count) PDF\(selectedDays.count == 1 ? "" : "s"), one a day")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    /// The same choice the Mac makes, said the same way to the engine.
    private var choice: ExportChoice {
        ExportChoice(arrange: arrange, useFilter: useFilter, picked: selectedDays,
                     whole: wholeFilm, info: info,
                     label: { name in session.columns.first { $0.name == name }?.shown ?? name.capitalized })
    }

    private var projectSlug: String {
        let project = session.view?.project
        let folder = (project?.driveFolder ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let film = FileNames.plain((folder as NSString).lastPathComponent)
        return film.isEmpty ? FileNames.plain(filmName) : film
    }

    /// **The automatic name**, the Mac's: project, pages, scene, order, date.
    private var autoName: String {
        if let pattern, !pattern.isEmpty { return ExportChoice.filled(pattern, project: projectSlug) }
        return FileNames.exportAuto(
            project: projectSlug, document: FileNames.documentWords(sections: includedSections.map(\.rawValue)),
            scope: scene.map { FileNames.sceneWords([$0.number]) } ?? "", order: choice.orderWords)
    }

    /// The name as saved: his own words exactly, or the automatic one.
    private var savedName: String {
        let base = (nameTyped ? typedName : autoName)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        let stem = base.lowercased().hasSuffix(".pdf") ? String(base.dropLast(4)) : base
        return stem.isEmpty ? autoName : stem
    }

    private func current() -> ExportPreset {
        var p = presetInUse ?? ExportPreset(id: "", name: "")
        p.arrange = arrange.rawValue
        p.filter = useFilter ? "table" : "none"
        p.filterWords = useFilter ? info.filter : []
        p.days = arrange == .schedule && wholeFilm ? ExportDays.rule(for: selectedDays, in: info) : nil
        p.pages = Exporting.Section.allCases.filter { include.contains($0) }.map(\.rawValue)
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
            out[pair.key.rawValue] = ExportPreset.Dial(orientation: pair.value.orientation.rawValue,
                                                       scale: pair.value.scale, frames: pair.value.frames.rawValue)
        }
        p.output = delivery == .perDay ? "perday" : "one"
        p.pattern = nameTyped ? ExportChoice.pattern(from: typedName, project: projectSlug, ext: "pdf") : pattern
        p.fileKind = flat ? 1 : 0
        p.workbook = alsoWorkbook
        return p
    }

    private func applyPreset(_ p: ExportPreset) {
        presetId = p.id
        arrange = ExportArrange(rawValue: p.arrange) ?? .table
        useFilter = p.filter == "table"
        filterNotUsed = p.filter == "table" && !p.filterWords.isEmpty && info.filter.isEmpty
        selectedDays = p.days.map { ExportDays.pick($0, in: info) } ?? choice.allDays
        let pages = Set(p.pages.compactMap(Exporting.Section.init(rawValue:)))
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
        var fresh: [Exporting.Section: Exporting.Look] = [:]
        for (raw, dial) in p.looks {
            guard let section = Exporting.Section(rawValue: raw) else { continue }
            var look = Exporting.Look.standard(for: section)
            if let sheet = Exporting.Orientation(rawValue: dial.orientation) { look.orientation = sheet }
            look.scale = dial.scale
            if let frames = Exporting.FrameSize(rawValue: dial.frames) { look.frames = frames }
            fresh[section] = look
        }
        looks = fresh
        delivery = p.output == "perday" && wholeFilm && arrange == .schedule && !info.days.isEmpty ? .perDay : .wholeFilm
        if delivery == .perDay, p.columns == nil { includedColumns.remove("day") }
        pattern = p.pattern
        nameTyped = false
        typedName = ""
        flat = p.fileKind == 1
        alsoWorkbook = p.workbook
        presetBase = current()
        remember()
        schedulePreview()
    }

    private func asInTable() {
        presetId = ""
        presetBase = nil
        filterNotUsed = false
        arrange = .table
        useFilter = true
        selectedDays = choice.allDays
        delivery = .wholeFilm
        pattern = nil
        nameTyped = false
        typedName = ""
        schedulePreview()
    }

    private func saveAsPreset(_ name: String) {
        let wanted = name.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return }
        var p = current()
        p.id = presets.named(wanted)?.id ?? ("p-" + UUID().uuidString.prefix(8).lowercased())
        p.name = wanted
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

    private var pdfSection: some View {
        Section("PDF") {
            Picker("PDF", selection: $flat) {
                Text("Editable").tag(false)
                Text("Flat").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var alsoSection: some View {
        Section("Also") {
            Toggle("Spreadsheet", isOn: $alsoWorkbook)
            if alsoWorkbook {
                Picker("Format For", selection: $frameStyle) {
                    ForEach(Exporting.FrameStyle.allCases) { one in
                        Text(one.label).tag(one)
                    }
                }
                // The Mac's exception under the language law — see
                // `FrameStyle.difference` for why it stays.
                Text(frameStyle.difference)
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    /// **Only the dials this page obeys.** Widths reach the table and nothing
    /// else; frames reach the table and the storyboard; the document takes
    /// its own paper and no text size.
    @ViewBuilder private var lookSection: some View {
        Section(pane.title) {
            if pane == .script {
                Text("Nothing to set").foregroundStyle(.secondary)
            } else {
                if pane == .table {
                    Picker("Layout", selection: Binding(
                        get: { tableAuto },
                        set: { auto in if auto { tableAuto = true } else { takeOverFromAuto() } })) {
                        Text("Auto").tag(true)
                        Text("Manual").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                if pane == .table && tableAuto {
                    // Auto's own two dials; Auto still works out the widths.
                    Picker("Paper", selection: Binding(
                        get: { autoAsk.paper },
                        set: { autoAsk = AutoAsk(size: autoAsk.size, paper: $0) })) {
                        Text("Best Fit").tag("auto")
                        Text("Landscape").tag("landscape")
                        Text("Portrait").tag("portrait")
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text("Size")
                        Slider(value: Binding(
                            get: { autoAsk.size },
                            set: { autoAsk = AutoAsk(size: $0, paper: autoAsk.paper) }),
                               in: AutoAsk.sizes, step: 0.05)
                        Text("\(Int((autoAsk.size * 100).rounded()))%")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                } else {
                    Picker("Paper", selection: lookBinding(pane, \.orientation)) {
                        Text("Landscape").tag(Exporting.Orientation.landscape)
                        Text("Portrait").tag(Exporting.Orientation.portrait)
                    }
                    .pickerStyle(.segmented)
                    if pane == .document {
                        // Why the dial is not here — the Mac's own line.
                        Text("Text is set on the page itself")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        HStack {
                            Text("Text Size")
                            Slider(value: lookBinding(pane, \.scale), in: 0.2...1.6, step: 0.05)
                            Text("\(Int(look(pane).scale * 100))%")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                        Picker("Frames", selection: lookBinding(pane, \.frames)) {
                            ForEach(Exporting.FrameSize.allCases) { one in
                                Text(one.title).tag(one)
                            }
                        }
                    }
                }
                if pane == .table || pane == .document {
                    Button { pickingColumns = true } label: {
                        LabeledContent("Columns",
                                       value: "\(orderedColumns.count) of \(availableColumns.count)")
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    // ---- what is possible ----------------------------------------------------

    /// Every page this delivery can produce — Script drops out of a per-day
    /// export, which has no notion of whose pages are whose day.
    private var availableSections: [Exporting.Section] {
        guard wholeFilm, delivery == .perDay else { return Exporting.Section.allCases }
        return Exporting.Section.allCases.filter { $0 != .script }
    }

    /// Ticked *and* possible.
    private var includedSections: [Exporting.Section] {
        Exporting.Section.allCases.filter {
            include.contains($0) && availableSections.contains($0) && ($0 != .script || script != nil)
        }
    }

    /// The fields this can print, in the project's own order — every
    /// column, his own included, showing on screen or not. (His own were
    /// left out until 2026-10-06, long after the engine learned to print
    /// them: "new columns aren't appearing in the exports for pdfs".)
    private var availableColumns: [Engine.Column] {
        session.columns
    }

    /// The picked columns, in the project's own order.
    private var orderedColumns: [String] {
        availableColumns.filter { includedColumns.contains($0.name) }.map(\.name)
    }

    private var canExport: Bool { !exporting && whyNot == nil }

    /// **Why Export is off**, said under the page rather than left a mystery.
    private var whyNot: String? {
        if includedSections.isEmpty && !alsoWorkbook { return "Tick a page to export" }
        if arrange == .schedule, wholeFilm, selectedDays.isEmpty { return "Pick a day to export" }
        return nil
    }

    private func look(_ section: Exporting.Section) -> Exporting.Look {
        if section == .table, tableAuto, let plan = autoPlan { return plan.look }
        return looks[section] ?? Exporting.Look.standard(for: section)
    }

    /// What Auto's plan depends on: the narrowing and the columns.
    private var autoBase: Exporting.Scope {
        Exporting.Scope(scenes: scene.map { [$0.id] } ?? [], columns: orderedColumns, narrowing: choice.narrowing,
                        extra: autoAsk.words)
    }

    private var autoKey: String { autoBase.options.joined(separator: "\t") }

    /// The plan for what is picked now, if it is not already in hand.
    private func planTable() async {
        guard tableAuto, autoPlanKey != autoKey, let engine = session.engine else { return }
        let key = autoKey
        let plan = await Exporting.tableLayout(scope: autoBase, engine: engine)
        guard key == autoKey else { return }
        autoPlan = plan
        autoPlanKey = key
    }

    /// **Any dial touched hands over to Manual**, from exactly Auto's sheet.
    private func takeOverFromAuto() {
        guard tableAuto else { return }
        if let plan = autoPlan {
            looks[.table] = plan.look
            columnWidths = plan.factors
        }
        tableAuto = false
    }

    private func lookBinding<V>(_ section: Exporting.Section,
                                _ path: WritableKeyPath<Exporting.Look, V>) -> Binding<V> {
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

    /// The narrowing and this page's dials. **The widths ride only with the
    /// table** — the engine drops them everywhere else.
    private func scope(for section: Exporting.Section, day: Exporting.Day? = nil,
                       columns: [String]? = nil) -> Exporting.Scope {
        let look = look(section)
        return Exporting.Scope(
            scenes: day == nil ? (scene.map { [$0.id] } ?? []) : [],
            day: day,
            columns: columns ?? orderedColumns,
            scale: look.scale,
            frames: look.frames.rawValue,
            widths: section == .table && !tableAuto ? columnWidths : [:],
            order: choice.caption,
            narrowing: day == nil ? choice.narrowing
                : choice.narrowing.filter { !$0.hasPrefix("days=") && !$0.hasPrefix("daypages=") },
            shares: section == .table && tableAuto && day == nil ? (autoPlan?.shares ?? [:]) : [:],
            fitted: section == .table && tableAuto && day == nil && autoPlan?.cut == 0
        )
    }

    private func columnWeights() -> [Exporting.ColumnWeight] {
        guard let engine = session.engine else { return [] }
        return Exporting.columnWeights(scope: scope(for: .table), engine: engine)
    }

    // ---- opening -------------------------------------------------------------

    private func open() {
        guard !opened else { return }
        if let engine = session.engine { info = Exporting.info(engine: engine) }
        selectedDays = choice.allDays
        presets.refresh()
        recall()
        if delivery == .perDay { delivery = .wholeFilm }
        setFromOutside()
        followFromOutside()
        frameStyle = Exporting.FrameStyle(rawValue: session.view?.project.excelFrames ?? "")
            ?? .forGoogleSheets
        if includedColumns.isEmpty {
            includedColumns = Set(availableColumns.filter(\.visible).map(\.name))
        }
        let began = Date()
        defer { Exporting.log.notice("open: \(Int(Date().timeIntervalSince(began) * 1000)) ms to read the script and settings") }
        if let engine = session.engine, let kept = Exporting.keptScript(engine: engine) {
            script = kept
            include.insert(.script)
        } else {
            include.remove(.script)
        }
        scriptChecked = true
        opened = true
        schedulePreview(now: true)
    }

    // ---- the preview ---------------------------------------------------------

    /// Everything a render depends on, in one string. Two of these being
    /// equal is the permission to skip a second's work.
    private func cacheKey(_ section: Exporting.Section) -> String {
        ([section.rawValue, look(section).orientation.rawValue]
         + scope(for: section).options).joined(separator: "\t")
    }

    /// **Hold the redraw until his thumb stops.** A slider fires on every
    /// tick; a page costs the better part of a second.
    private func schedulePreview(now: Bool = false) {
        guard opened else { return }
        previewWork?.cancel()
        if pane == .script {
            preview = script?.sliced(for: scene.map { [$0.number] } ?? [])
            rendering = false
            return
        }
        // **On Auto, a stale plan comes first.** The key below is made from
        // the plan in hand, so with Size, paper or the columns just changed it
        // still names the page drawn before the change — and that page was
        // shown again. His report, 2026-10-17: the preview did not follow Auto.
        let replan = pane == .table && tableAuto && autoPlanKey != autoKey
        let key = cacheKey(pane)
        if !replan, let already = drawn[key] {
            preview = already
            previewPage = min(previewPage, max(already.pageCount - 1, 0))
            rendering = false
            return
        }
        rendering = true
        problem = nil
        previewWork = Task { @MainActor in
            if !now { try? await Task.sleep(for: .milliseconds(250)) }
            guard !Task.isCancelled else { return }
            if replan {
                await planTable()
                guard !Task.isCancelled else { return }
                // The plan changes what the page is: ask again with it.
                let planned = cacheKey(pane)
                if let already = drawn[planned] { preview = already; rendering = false; return }
                await renderPreview(key: planned)
                return
            }
            await renderPreview(key: key)
        }
    }

    @MainActor
    private func renderPreview(key: String) async {
        guard let engine = session.engine else { return }
        let job = Exporting.Job(section: pane, scope: scope(for: pane),
                                orientation: look(pane).orientation)
        do {
            let doc = try await Exporting.render(job, engine: engine,
                                                 folder: session.folder.url, ratio: session.ratio)
            guard !Task.isCancelled else { return }
            if drawn.count > 12 { drawn.removeAll() }
            drawn[key] = doc
            preview = doc
            previewPage = min(previewPage, max(doc.pageCount - 1, 0))
        } catch {
            guard !Task.isCancelled else { return }
            preview = nil
            problem = error.localizedDescription
        }
        rendering = false
    }

    // ---- exporting -----------------------------------------------------------

    private func export() {
        guard let engine = session.engine else { return }
        exporting = true
        problem = nil
        Task { @MainActor in
            await planTable()
            do {
                let files = wholeFilm && delivery == .perDay
                    ? try await eachDay(engine: engine)
                    : try await oneFile(engine: engine)
                made = Made(files: files)
                Self.sayForCheck(files)
            } catch {
                problem = error.localizedDescription
            }
            exporting = false
        }
    }

    /// The whole film, or the scene: one PDF, and the workbook beside it
    /// when he asked for one.
    private func oneFile(engine: Engine) async throws -> [URL] {
        let folder = Exporting.scratch(named: filmName)
        var files: [URL] = []
        let pages = includedSections.filter { $0 != .script }.map {
            Exporting.Job(section: $0, scope: scope(for: $0), orientation: look($0).orientation)
        }
        if !includedSections.isEmpty {
            let sliced = includedSections.contains(.script)
                ? script?.sliced(for: scene.map { [$0.number] } ?? []) : nil
            let drawn = try await Exporting.combined(pages, script: sliced, engine: engine,
                                                     folder: session.folder.url, ratio: session.ratio)
            let doc = flat ? Exporting.flattened(drawn) : drawn
            let out = folder.appending(path: savedName + ".pdf")
            guard doc.write(to: out) else { throw Exporting.Trouble.couldNotWrite }
            files.append(out)
        }
        if alsoWorkbook {
            let sheet = folder.appending(path: savedName + ".xlsx")
            let sheetScope = Exporting.Scope(scenes: scene.map { [$0.id] } ?? [],
                                             columns: orderedColumns.isEmpty ? nil : orderedColumns,
                                             narrowing: choice.narrowing)
            if let refusal = Exporting.exportExcel(to: sheet, scope: sheetScope, frames: frameStyle,
                                                   engine: engine, folder: session.folder.url) {
                throw Exporting.Trouble.engine(refusal)
            }
            files.append(sheet)
        }
        return files
    }

    /// One PDF and one workbook for every day he picked — each day in turn,
    /// because every PDF wants a web view and forty at once is a way to run
    /// out of memory on a long shoot.
    private func eachDay(engine: Engine) async throws -> [URL] {
        // **A named folder**, the Mac's: the name the one file would have had,
        // and each day's file in it named by its day number.
        let folder = Exporting.scratch(named: savedName)
        let names = choice.dayFileNames(project: projectSlug, document: FileNames.documentWords(
            sections: includedSections.filter { $0 != .script }.map(\.rawValue)))
        let order = info.days.map(\.id) + (info.unscheduled > 0 ? [Exporting.unscheduledDayId] : [])
        let days: [(name: String, day: Exporting.Day)] = order
            .filter { selectedDays.contains($0) }
            .map { id in (names[id] ?? id, id == Exporting.unscheduledDayId ? .unscheduled : .on(id)) }
        // A day's own file does not need a Shoot Day column — every row in
        // it says the same word.
        let columns = orderedColumns.filter { $0 != "day" }
        var files: [URL] = []
        for one in days {
            if alsoWorkbook {
                let sheet = folder.appending(path: "\(one.name).xlsx")
                let sheetScope = Exporting.Scope(day: one.day, columns: columns.isEmpty ? nil : columns,
                                                 narrowing: scope(for: .table, day: one.day).narrowing)
                if let refusal = Exporting.exportExcel(to: sheet, scope: sheetScope, frames: frameStyle,
                                                       engine: engine, folder: session.folder.url) {
                    throw Exporting.Trouble.engine(refusal)
                }
                files.append(sheet)
            }
            // **Auto lays each day's table out for that day's own shots.**
            var dayAuto: Exporting.TableLayout?
            if tableAuto, includedSections.contains(.table) {
                dayAuto = await Exporting.tableLayout(
                    scope: Exporting.Scope(day: one.day, columns: columns,
                                           narrowing: scope(for: .table, day: one.day).narrowing,
                                           extra: autoAsk.words),
                    engine: engine)
            }
            let pages = includedSections.filter { $0 != .script }.map { section -> Exporting.Job in
                var dayScope = scope(for: section, day: one.day, columns: columns)
                if section == .table, let dayAuto {
                    dayScope.scale = dayAuto.scale
                    dayScope.frames = dayAuto.frames
                    dayScope.shares = dayAuto.shares
                    dayScope.fitted = dayAuto.cut == 0
                    return Exporting.Job(section: section, scope: dayScope, orientation: dayAuto.look.orientation)
                }
                return Exporting.Job(section: section, scope: dayScope, orientation: look(section).orientation)
            }
            guard !pages.isEmpty else { continue }
            let drawn = try await Exporting.combined(pages, script: nil, engine: engine,
                                                     folder: session.folder.url, ratio: session.ratio)
            let doc = flat ? Exporting.flattened(drawn) : drawn
            let out = folder.appending(path: "\(one.name).pdf")
            guard doc.write(to: out) else { throw Exporting.Trouble.couldNotWrite }
            files.append(out)
        }
        return files
    }

    private var filmName: String {
        let title = session.view?.project.shownTitle ?? ""
        return title.isEmpty ? session.entry.name : title
    }

    // ---- remembering ---------------------------------------------------------

    /// **Everything under one key**, the same shape the Mac keeps, so the
    /// two apps remember the same things about an export.
    private let storeKey = "export"
    private var filmKey: String { session.view?.project.id ?? "default" }

    private var stored: [String: Any] {
        UserDefaults.standard.dictionary(forKey: storeKey) ?? [:]
    }

    private func keep(_ store: [String: Any]) {
        UserDefaults.standard.set(store, forKey: storeKey)
    }

    private func recall() {
        var store = stored
        // Once, the remembered tick is dropped: the page remembered the
        // spreadsheet as on from the day it opened on, and a new default
        // alone would change nothing he could see.
        if store["workbookOffByDefault"] as? Bool != true {
            store["alsoWorkbook"] = false
            store["workbookOffByDefault"] = true
            UserDefaults.standard.set(store, forKey: storeKey)
        }
        take(store)
        if let picked = (store["columns"] as? [String: [String]])?[filmKey] {
            includedColumns = Set(picked)
            // A column the film has grown since this set was remembered
            // starts ticked, as on the Mac: what was *seen* when the set was
            // kept says what is new.
            let seen = Set((store["seenColumns"] as? [String: [String]])?[filmKey] ?? [])
            for column in availableColumns where column.visible && !seen.contains(column.name)
                && (column.kind != nil || !seen.isEmpty) {
                includedColumns.insert(column.name)
            }
        }
        if let dials = (store["widths"] as? [String: [String: Double]])?[filmKey] {
            columnWidths = dials
        }
    }

    /// The part a set-up and the store share: the pages, the split, the
    /// workbook, the looks.
    private func take(_ one: [String: Any]) {
        if let names = one["included"] as? [String] {
            include = Set(names.compactMap(Exporting.Section.init(rawValue:)))
        }
        if let word = one["delivery"] as? String, let choice = Exporting.Delivery(rawValue: word) {
            delivery = choice
        }
        if let also = one["alsoWorkbook"] as? Bool { alsoWorkbook = also }
        if let baked = one["flat"] as? Bool { flat = baked }
        if let auto = one["tableAuto"] as? Bool { tableAuto = auto }
        autoAsk = AutoAsk(size: one["autoSize"] as? Double ?? 1, paper: one["autoPaper"] as? String ?? "auto")
        if let all = one["looks"] as? [String: [String: Any]] {
            var fresh: [Exporting.Section: Exporting.Look] = [:]
            for (raw, dials) in all {
                guard let section = Exporting.Section(rawValue: raw) else { continue }
                var look = Exporting.Look.standard(for: section)
                if let paper = dials["orientation"] as? String,
                   let sheet = Exporting.Orientation(rawValue: paper) { look.orientation = sheet }
                if let size = dials["scale"] as? Double { look.scale = size }
                if let frames = dials["frames"] as? String,
                   let picture = Exporting.FrameSize(rawValue: frames) { look.frames = picture }
                fresh[section] = look
            }
            looks = fresh
        }
    }

    private func looksPayload() -> [String: [String: Any]] {
        looks.reduce(into: [String: [String: Any]]()) { out, pair in
            out[pair.key.rawValue] = [
                "orientation": pair.value.orientation.rawValue,
                "scale": pair.value.scale,
                "frames": pair.value.frames.rawValue,
            ]
        }
    }

    private func remember() {
        guard opened else { return }
        var store = stored
        store["included"] = include.map(\.rawValue).sorted()
        store["delivery"] = delivery.rawValue
        store["alsoWorkbook"] = alsoWorkbook
        store["flat"] = flat
        store["tableAuto"] = tableAuto
        store["autoSize"] = autoAsk.size
        store["autoPaper"] = autoAsk.paper
        store["looks"] = looksPayload()
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

}

// ------------------------------------------------------------------ pickers

/// **The days, grouped by shoot then week**, each group ticked whole or
/// opened for the odd ones out — sixty days as a handful of weeks.
private struct DaysPicker: View {
    let info: ExportInfo
    @Binding var picked: Set<String>

    var body: some View {
        List {
            Section {
                Button(picked.isEmpty ? "Select All" : "Select None") {
                    picked = picked.isEmpty ? Set(info.days.map(\.id)).union(info.unscheduled > 0 ? [ExportDays.unscheduled] : []) : []
                }
            } footer: {
                Text(ExportDays.summary(picked, in: info))
            }
            ForEach(ExportDays.groups(of: info)) { group in
                Section(group.title) {
                    ForEach(group.weeks) { week in
                        DisclosureGroup {
                            ForEach(week.days, id: \.day.id) { entry in
                                Toggle(isOn: Binding(
                                    get: { picked.contains(entry.day.id) },
                                    set: { on in if on { picked.insert(entry.day.id) } else { picked.remove(entry.day.id) } }
                                )) {
                                    HStack {
                                        Text("Day \(entry.number)")
                                        Text(ExportDays.date(entry.day.date).map(ExportDays.short) ?? entry.day.date)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } label: {
                            let ids = week.days.map(\.day.id)
                            let on = ids.filter { picked.contains($0) }.count
                            Button {
                                if on == ids.count { picked.subtract(ids) } else { picked.formUnion(ids) }
                            } label: {
                                HStack {
                                    Image(systemName: on == ids.count ? "checkmark.circle.fill" : on == 0 ? "circle" : "minus.circle.fill")
                                    Text(week.title)
                                    Spacer()
                                    Text(on == ids.count ? "\(ids.count)" : "\(on) of \(ids.count)")
                                        .foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if info.unscheduled > 0 {
                Section {
                    Toggle("Unscheduled", isOn: Binding(
                        get: { picked.contains(ExportDays.unscheduled) },
                        set: { on in if on { picked.insert(ExportDays.unscheduled) } else { picked.remove(ExportDays.unscheduled) } }
                    ))
                }
            }
        }
        .navigationTitle("Days")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// **Manage Presets** — rename, duplicate, reorder, delete; the Mac's sheet.
private struct ManagePresets: View {
    @ObservedObject var store: ExportPresets
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: ExportPreset?
    @State private var typed = ""

    var body: some View {
        List {
            ForEach(store.list) { p in
                HStack {
                    Text(p.name)
                    Spacer()
                    Menu {
                        Button("Rename") { typed = p.name; renaming = p }
                        Button("Duplicate") { store.duplicate(p.id) }
                        Button("Delete", role: .destructive) { store.delete(p.id) }
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                    }
                }
            }
            .onMove { store.move(from: $0, to: $1) }
            .onDelete { $0.map { store.list[$0].id }.forEach(store.delete) }
        }
        .navigationTitle("Manage Presets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { EditButton() }
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $typed)
            Button("Save") { if let r = renaming { store.rename(r.id, to: typed) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }
}

/// **One row per column: the tick, the name, the dial, the share.** The share
/// is worked out from the engine's own weights, so the number he reads is the
/// number the page will use.
private struct ColumnsPicker: View {
    let columns: [Engine.Column]
    @Binding var picked: Set<String>
    @Binding var widths: [String: Double]
    /// Widths reach the table alone.
    let withWidths: Bool
    let weights: () -> [Exporting.ColumnWeight]

    @State private var base: [Exporting.ColumnWeight] = []

    var body: some View {
        List {
            if withWidths, widths.values.contains(where: { abs($0 - 1) > 0.01 }) {
                Section {
                    Button("Reset Widths") { widths = [:] }
                }
            }
            Section {
                ForEach(columns) { column in
                    row(column)
                }
            }
        }
        .navigationTitle("Columns")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { base = weights() }
        .onChange(of: picked) { _, _ in base = weights() }
    }

    private func row(_ column: Engine.Column) -> some View {
        let on = picked.contains(column.name)
        return VStack(alignment: .leading, spacing: 6) {
            Toggle(column.shown, isOn: Binding(
                get: { on },
                set: { now in if now { picked.insert(column.name) } else { picked.remove(column.name) } }
            ))
            if withWidths, on {
                HStack {
                    Slider(value: Binding(
                        get: { widths[column.name] ?? 1 },
                        set: { widths[column.name] = $0 }
                    ), in: 0.4...2.5)
                    // A number, not a sentence — the column's share of the page.
                    Text("\(Int((share(of: column.name) * 100).rounded()))%")
                        .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
    }

    /// What share of the printed table a column takes: its own weight times
    /// his dial, over everybody else's.
    private func share(of field: String) -> Double {
        let weighed = base.map { $0.weight * (widths[$0.field] ?? 1) }
        let total = weighed.reduce(0, +)
        guard total > 0, let at = base.firstIndex(where: { $0.field == field }) else { return 0 }
        return weighed[at] / total
    }
}

// ------------------------------------------------------------------ the paper

/// A PDF, shown one page at a time, with the page bar's number kept honest.
private struct Paper: UIViewRepresentable {
    let document: PDFDocument
    @Binding var page: Int

    final class Coordinator: NSObject {
        var page: Binding<Int>
        weak var view: PDFView?
        /// True while *we* are moving the view, so its own page-changed
        /// notification is not mistaken for him turning the page.
        var moving = false
        init(page: Binding<Int>) { self.page = page }

        @objc func turned(_ note: Notification) {
            guard !moving, let view, let current = view.currentPage,
                  let index = view.document?.index(for: current) else { return }
            if page.wrappedValue != index { page.wrappedValue = index }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(page: $page) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        // The document goes on before `autoScales` — PDFKit computes the fit
        // from whatever it is holding at the moment the flag is set.
        view.document = document
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        view.autoScales = true
        view.backgroundColor = .secondarySystemBackground
        view.goToFirstPage(nil)
        context.coordinator.view = view
        NotificationCenter.default.addObserver(
            context.coordinator, selector: #selector(Coordinator.turned(_:)),
            name: .PDFViewPageChanged, object: view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.page = $page
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
            DispatchQueue.main.async { context.coordinator.moving = false }
        }
    }
}

/// The system share sheet, handed the files.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
