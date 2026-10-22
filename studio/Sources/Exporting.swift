import AppKit
import PDFKit
import SwiftUI

/// Getting the list out of the app.
///
/// The spreadsheet lives here — the one-off export, the link that
/// keeps a file current, and the day-by-day writer the PDF dialog calls into
/// for its own "one for each day" option. The scene's own PDF dialog lives in
/// `ScenePDFExport.swift` because it is a screen; these are the actions
/// behind the share button and Project Settings.
/// Which program a workbook is laid out for.
///
/// **It is the same `.xlsx` either way, and that is the point he had to correct
/// me on.** 2026-09-04: *"the clarification is more about saying it's not the
/// file that changes itself, but that we're formatting for Google Sheets or
/// formatting for Excel."* My first two names — *In the Cells* and *In the
/// File* — described a technique, and the pair after them, *Google Sheet* and
/// *Excel Sheet*, read as two different kinds of file. Neither is true. One
/// file, laid out for one program or the other, and only the frames differ.
///
/// - **Google Sheets** writes an `IMAGE()` formula the sheet fetches from the
///   relay. The frame is then the cell's *contents*, so it travels with its row
///   when he sorts — which no picture in a spreadsheet has ever done. Nothing
///   but Sheets resolves it, the film has to have been synced, and Sheets asks
///   the reader to allow outside data once per file.
/// - **Excel** carries the picture inside the workbook, pasted over the grid,
///   exactly as every version before this. Opens anywhere, needs no relay and
///   no permission — and gets left behind by a sort. **This is the one to send
///   to somebody else.**
///
/// **The stored values are `cells` and `file` and must stay that way.** They are
/// in his films already; the names above them are what he reads.
enum FrameStyle: String {
    case forGoogleSheets = "cells"
    case forExcel = "file"

    /// What he sees. The program, because that is the choice he is making.
    var label: String {
        switch self {
        case .forGoogleSheets: return "Google Sheets"
        case .forExcel: return "Excel"
        }
    }

    /// The one line that earns its place beside the name.
    ///
    /// **It leads with the thing he asked to be made clear** — that the file
    /// itself does not change — and then says the only thing that does. This is
    /// the exception the language law allows, not a description for its own
    /// sake: nothing in either name warns a reader that one layout draws
    /// nothing outside Sheets, and choosing wrongly means sending somebody a
    /// spreadsheet with an empty column in it. Do not tidy it away.
    var difference: String {
        switch self {
        case .forGoogleSheets:
            return "Frames in cells"
        case .forExcel:
            return "Frames over rows"
        }
    }

    static var choices: [Dropdown<FrameStyle>.Item] {
        [Dropdown.Item(.forGoogleSheets, FrameStyle.forGoogleSheets.label),
         Dropdown.Item(.forExcel, FrameStyle.forExcel.label)]
    }
}

/// Holds the choice while a save panel is up, so the panel's own control and the
/// code after `runModal` are looking at one value rather than two.
final class FrameChoice: ObservableObject {
    @Published var style: FrameStyle
    init(_ style: FrameStyle) { self.style = style }
}

/// The dropdown and its line, for a save panel.
///
/// Hosted rather than an `NSPopUpButton` so the save dialog carries the same
/// control as everywhere else — his ruling, 2026-09-04, that the system ones
/// are ugly.
private struct FramePanel: View {
    @ObservedObject var held: FrameChoice
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FORMAT FOR").sectionLabel(dark)
            Dropdown(selection: $held.style, items: FrameStyle.choices)
            Text(held.style.difference)
                .sans(10).foregroundStyle(Brand.ink4(dark))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 420, alignment: .leading)
    }
}

enum Exporting {

    // ---------------------------------------------------------------- excel

    /// Which way this film writes its frames.
    ///
    /// **Empty means `forGoogleSheets`** — the behaviour this build shipped with,
    /// and the one that suits the workbook he keeps in Drive and opens in
    /// Sheets. A film that has never been asked carries an empty value, the
    /// same bargain `autoUpdateEnabled` strikes for the switch beside it.
    static func frameStyle(for project: ViewModel.Project?) -> FrameStyle {
        FrameStyle(rawValue: project?.excelFrames ?? "") ?? .forGoogleSheets
    }

    /// Goes through the ordinary `set`, so it undoes, saves and syncs like any
    /// other edit.
    static func setFrameStyle(_ style: FrameStyle, state: ShellState) {
        guard let engine = state.engine, let id = state.view?.project.id else { return }
        state.replace(engine.set(shot: id, field: "excel_frames", value: style.rawValue))
    }

    /// The dropdown that goes in a save panel, so a one-off copy can be made
    /// for a different program without changing what the linked workbook does.
    ///
    /// **A one-off is a one-off**: the choice starts from the film's setting
    /// and is never written back. The film he keeps and the file he sends are
    /// two different questions, which is the whole reason this control exists.
    static func framePicker(starting from: FrameStyle) -> (view: NSView, held: FrameChoice) {
        let held = FrameChoice(from)
        let view = NSHostingView(rootView: FramePanel(held: held))
        view.frame = NSRect(x: 0, y: 0, width: 420, height: 78)
        return (view, held)
    }

    /// A one-off copy of the working file, exactly as it stands. Independent
    /// of any spreadsheet this film is set to keep current — that location
    /// and this action can point at the same file or never meet at all.
    static func exportExcel(state: ShellState) {
        guard let engine = state.engine else { return }
        let project = state.view?.project
        let title = project?.shownTitle ?? ""

        let panel = NSSavePanel()
        // The Drive folder this project is linked to, when there is one —
        // the same place he already keeps everything else about the film.
        let folder = project?.driveFolder ?? ""
        if !folder.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: folder, isDirectory: true)
        }
        panel.nameFieldStringValue = FileNames.unused(
            FileNames.export(film: title, document: "Shot-List", ext: "xlsx"),
            in: panel.directoryURL)

        // **The copy he sends someone is not the copy he keeps.** It starts
        // from the film's own setting and can be changed for this one file,
        // which is what makes a universal workbook available without giving up
        // the frames that sort.
        let picker = framePicker(starting: frameStyle(for: project))
        panel.accessoryView = picker.view

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard engine.exportExcel(path: url.path, frames: picker.held.style) != nil else {
            state.say("Could not save the shot list")
            return
        }
        state.say("Saved \(url.lastPathComponent)")
    }

    /// Point this film at a workbook to keep current, or at none.
    ///
    /// Goes through the ordinary `set`, so linking and unlinking undo, save
    /// and sync like any other edit — the same bargain `Linking` strikes for
    /// the Drive fields. Separate from whether it actually updates itself —
    /// see `setAutoUpdate`.
    static func link(_ path: String, state: ShellState) {
        guard let engine = state.engine, let id = state.view?.project.id else { return }
        state.replace(engine.set(shot: id, field: "excel_path", value: path))
    }

    /// Whether the linked workbook rewrites itself, apart from whether one is
    /// linked at all — his ask, 2026-08-27: a location and an on/off switch
    /// are two different questions.
    ///
    /// **"Off" is written as `"0"`, not emptied** — emptying it would read
    /// back as "never decided", which `autoUpdateEnabled` treats as *on*.
    /// That collapse was a real bug here: turning the switch off produced an
    /// empty string, which then read back as on again.
    static func setAutoUpdate(_ on: Bool, state: ShellState) {
        guard let engine = state.engine, let id = state.view?.project.id else { return }
        state.replace(engine.set(shot: id, field: "excel_auto", value: on ? "1" : "0"))
    }

    /// What an unset switch means: "on", for a project linked before this
    /// setting existed — a workbook that was following the project should
    /// not go quiet the first time this build opens it. A project linked
    /// since always carries an explicit `"1"` or `"0"`.
    static func autoUpdateEnabled(for project: ViewModel.Project?) -> Bool {
        guard let project, !project.excelPath.isEmpty else { return false }
        return project.excelAuto.isEmpty ? true : project.excelAuto == "1"
    }

    /// **Where the always-updating workbook lives** (his ask, 2026-10-15): in
    /// its own `live-sheet` folder inside the project's `1-creative/shot-list`,
    /// so it is never mixed up with his own spreadsheets there.
    static let liveSheetFolder = "live-sheet"

    /// `<project's Drive folder>/1-creative/shot-list/live-sheet`, when the
    /// project has a `shot-list` folder to put it in (an older layout with
    /// another spine keeps asking where, as before). Not made here.
    static func liveSheetDirectory(driveFolder: String) -> URL? {
        guard !driveFolder.isEmpty else { return nil }
        let shotList = URL(fileURLWithPath: driveFolder, isDirectory: true)
            .appending(path: "1-creative", directoryHint: .isDirectory)
            .appending(path: "shot-list", directoryHint: .isDirectory)
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: shotList.path, isDirectory: &isFolder), isFolder.boolValue
        else { return nil }
        return shotList.appending(path: liveSheetFolder, directoryHint: .isDirectory)
    }

    /// A workbook linked before `live-sheet` existed sits directly in
    /// `1-creative/shot-list`; this moves that one file (a move, never a copy
    /// or a delete — Drive keeps the file's identity) into `live-sheet` and
    /// answers its new path. `nil` when it is already there, is somewhere
    /// else, is not on disk, or the move did not work: nothing changes then.
    static func movedIntoLiveSheet(_ path: String) -> String? {
        let file = URL(fileURLWithPath: path)
        let folder = file.deletingLastPathComponent()
        guard folder.lastPathComponent == "shot-list",
              folder.deletingLastPathComponent().lastPathComponent == "1-creative" else { return nil }
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return nil }
        let into = folder.appending(path: liveSheetFolder, directoryHint: .isDirectory)
        let target = into.appending(path: file.lastPathComponent)
        guard !fm.fileExists(atPath: target.path) else { return nil }
        do {
            try fm.createDirectory(at: into, withIntermediateDirectories: true)
            try fm.moveItem(at: file, to: target)
        } catch { return nil }
        return target.path
    }

    /// Rewrite the linked workbook, if there is one and it is set to keep
    /// current. Answers whether it wrote.
    ///
    /// **Silent on purpose when there is nothing to do** — this is called
    /// after every change that settles, and the ordinary answer is "no
    /// workbook linked" or "linked, but he turned auto-update off."
    @discardableResult
    static func refreshLinkedWorkbook(state: ShellState) -> Bool {
        guard let engine = state.engine else { return false }
        let project = state.view?.project
        var path = project?.excelPath ?? ""
        guard autoUpdateEnabled(for: project) else { return false }

        // A workbook still beside his own spreadsheets is moved into its own
        // `live-sheet` folder, once, and the link follows it.
        if let moved = movedIntoLiveSheet(path) {
            link(moved, state: state)
            path = moved
        }

        // **A file he has moved or thrown away is not an error to shout
        // about**, but it must not be silently recreated either — a workbook
        // reappearing in a folder he tidied is worse than one that stops
        // following. The link is dropped and said once.
        let folder = (path as NSString).deletingLastPathComponent
        guard FileManager.default.fileExists(atPath: folder) else {
            link("", state: state)
            state.say("Spreadsheet folder missing. Updates stopped.")
            return false
        }
        guard engine.exportExcel(path: path, frames: frameStyle(for: project)) != nil else {
            link("", state: state)
            state.say("Couldn't update the spreadsheet. Updates stopped.")
            return false
        }
        return true
    }

    /// Write the linked workbook right now, whether or not it is set to keep
    /// itself current — Project Settings' own export button, for when he
    /// wants this moment's numbers without waiting on the switch.
    static func exportLinkedWorkbookNow(state: ShellState) {
        guard let engine = state.engine else { return }
        let path = state.view?.project.excelPath ?? ""
        guard !path.isEmpty else { return }
        guard engine.exportExcel(path: path,
                                 frames: frameStyle(for: state.view?.project)) != nil else {
            state.say("Could not update the spreadsheet")
            return
        }
        state.say("Updated \((path as NSString).lastPathComponent)")
    }

    // ---------------------------------------------------------- whole film

    /// The whole film's PDF — the same box a scene's own export uses, with
    /// nothing picked, which is what "every scene" means to it.
    static func exportProjectPDF(state: ShellState) {
        state.exportingScenes = []
        state.exportingWholeProject = true
        state.exportJustDiagram = false
        ExportWindow.shared.show(state: state)
    }

    /// The scenes he picked, from their own right-click menu.
    ///
    /// **The flags and the window are set together, here and in
    /// `exportProjectPDF`, and nowhere else.** They used to be set on their
    /// own and a `.sheet` binding watched them; a window has nobody watching,
    /// so setting a flag without opening would do nothing at all and read as
    /// the menu item being broken.
    static func exportScenes(_ ids: [String], state: ShellState) {
        guard !ids.isEmpty else { return }
        state.exportingWholeProject = false
        state.exportJustDiagram = false
        state.exportingScenes = ids
        ExportWindow.shared.show(state: state)
    }

    /// **The Diagram's Export…**: the same window as the Share export, on one
    /// scene's or loose plan's Diagram page. One exporter, one look (his ask,
    /// 2026-10-04: the two had grown *"widely different"*).
    static func exportDiagram(_ id: String, state: ShellState) {
        state.exportingWholeProject = false
        state.exportJustDiagram = true
        state.exportingScenes = [id]
        ExportWindow.shared.show(state: state)
    }

    /// The export as pictures: one page, one PNG at `url`; more, numbered
    /// beside it (`Name 1.png`, `Name 2.png`). 3 pixels a point, so a
    /// landscape sheet is about 2500 wide.
    static func writePictures(of doc: PDFDocument, to url: URL) -> Bool {
        let base = url.deletingPathExtension()
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i), let data = picture(of: page) else { return false }
            let target = doc.pageCount == 1 ? url
                : URL(fileURLWithPath: base.path + " \(i + 1)").appendingPathExtension("png")
            do { try data.write(to: target) } catch { return false }
        }
        return doc.pageCount > 0
    }

    static func picture(of page: PDFPage, scale: CGFloat = 3) -> Data? {
        let box = page.bounds(for: .mediaBox)
        let w = Int(box.width * scale), h = Int(box.height * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        let cg = ctx.cgContext
        cg.setFillColor(NSColor.white.cgColor)
        cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
        cg.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: cg)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    // ------------------------------------------------------------ per day

    /// The id `--exportdays`/the sheet's day picker uses for "everything not
    /// on a day yet" — the same word `Engine.ExportScope.Day.unscheduled`
    /// already writes over the wire, so the one string means the same thing
    /// wherever it appears.
    static let unscheduledDayId = "unscheduled"

    /// Every shoot day, plus "Unscheduled" if anything is not on one yet —
    /// "Unscheduled" is a real answer on this board, not an absence, and a
    /// shot nobody has scheduled is exactly the shot somebody needs reminding
    /// about. `nil` when there is nothing to hand out by day at all, or
    /// nothing in `only` matches anything that exists.
    ///
    /// `only` narrows to specific days (and/or `unscheduledDayId`) — his ask,
    /// 2026-08-28: "By shoot day, and then I can select what days I want to
    /// export." `nil` keeps the old behaviour, every day and Unscheduled.
    static func dayJobs(state: ShellState, only: Set<String>? = nil,
                        all named: [String: String]? = nil) -> [(name: String, day: Engine.ExportScope.Day)]? {
        // **Named by the export box**: every day it offers, by id → file
        // stem, in its order — whatever the shoot picker is on.
        if let named {
            let order = (state.engine?.exportInfo()?.days ?? []).map(\.id) + [unscheduledDayId]
            let jobs: [(name: String, day: Engine.ExportScope.Day)] = order
                .filter { (only?.contains($0) ?? true) && named[$0] != nil }
                .map { (name: named[$0] ?? $0, day: $0 == unscheduledDayId ? .unscheduled : .on($0)) }
            return jobs.isEmpty ? nil : jobs
        }
        let days = state.view?.days ?? []
        // What no day has claimed. Counted by subtraction rather than by
        // asking each shot, because a day already knows how many it holds
        // and a shot does not carry its day in the view model at all.
        let onDays = days.reduce(0) { $0 + $1.count }
        let unscheduledCount = max(0, (state.view?.allRows.count ?? 0) - onDays)
        guard !days.isEmpty || unscheduledCount > 0 else { return nil }

        var jobs: [(name: String, day: Engine.ExportScope.Day)] = days
            .filter { only?.contains($0.id) ?? true }
            .map { (name: FileNames.day(label: $0.label, date: $0.date), day: .on($0.id)) }
        if unscheduledCount > 0, only?.contains(unscheduledDayId) ?? true {
            jobs.append((name: "Unscheduled", day: .unscheduled))
        }
        return jobs.isEmpty ? nil : jobs
    }

    /// `Day 3 – Fri 12 Sep` — the label the board shows, plus its date when it
    /// has one, made safe for a filename. A slash in a day's name would
    /// otherwise write into a folder nobody asked for.
    static func dayFileName(_ day: ViewModel.Day) -> String {
        var name = day.label
        if !day.date.isEmpty { name += " – \(day.date)" }
        return name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    /// One folder, and inside it a PDF for every shoot day — and, unless he
    /// says otherwise, a workbook alongside it. His ask (SL-377): a day's
    /// package, ready to hand to whoever needs it.
    ///
    /// `sections`, `orientation`, `scale` and `columns` are the PDF export
    /// dialog's own settings, passed straight through — this used to be its
    /// own separate, fixed-at-one-size flow (Table only, never stamped with a
    /// date or page numbers); folding it into the same dialog, 2026-08-27,
    /// means a day's page finally gets the same footer and the same choice of
    /// text size and columns as everything else does. Answers whether it
    /// actually started — `false` means either there is nothing to export by
    /// day, or he cancelled the folder picker, and the caller should not
    /// treat either as a completed export.
    @discardableResult
    static func exportEachDay(
        state: ShellState,
        sections: [String] = ["table"],
        looks: [String: Printing.Look] = [:],
        columns: [String]? = nil,
        widths: [String: Double] = [:],
        autoTable: Bool = false,
        autoAsk: AutoAsk = AutoAsk(),
        alsoWorkbook: Bool = false,
        flat: Bool = false,
        onlyDays: Set<String>? = nil,
        diagram: [String] = [],
        narrowing: [String] = [],
        named: [String: String] = [:],
        folder: String? = nil,
        into given: URL? = nil,
        finished: ((_ written: Int, _ trouble: [String]) -> Void)? = nil
    ) -> Bool {
        guard let engine = state.engine else { return false }
        guard let jobs = dayJobs(state: state, only: onlyDays, all: named.isEmpty ? nil : named) else {
            state.say(onlyDays == nil ? "No shoot days yet" : "No days picked")
            return false
        }

        // `given` is the checking run's door — a folder picker is not
        // something a synthetic click can drive, and without a way in, the
        // loop below (which writes a file per day, twice) would be
        // unverifiable. Everything after this line is the same code either
        // way; only the question of *where* is answered differently.
        let into: URL
        if let given {
            into = given
        } else {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Export here"
            panel.message = "A PDF for every shoot day"
            let folder = state.view?.project.driveFolder ?? ""
            if !folder.isEmpty {
                panel.directoryURL = URL(fileURLWithPath: folder, isDirectory: true)
            }
            guard panel.runModal() == .OK, let picked = panel.url else { return false }
            into = picked
        }
        // **A named folder of PDFs** (2026-10-15): the export box's File per
        // day writes its own folder, named like the file would have been,
        // inside the one picked — `_v2` beside an earlier issue.
        var target = into
        if let folder, !folder.isEmpty {
            var name = folder
            var n = 2
            while FileManager.default.fileExists(atPath: into.appendingPathComponent(name).path) {
                name = "\(folder)_v\(n)"; n += 1
            }
            target = into.appendingPathComponent(name, isDirectory: true)
            do { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true) }
            catch { state.say("Couldn't make the folder"); return false }
        }

        // **A day's own file does not need a Shoot Day column** — every row
        // in it says the same word, and width on a landscape page is
        // zero-sum. Only applied to the default column set; a column list he
        // picked himself is left exactly as he picked it.
        let effectiveColumns = columns ?? (state.view?.columns ?? [])
            .filter { $0.visible && $0.name != "day" }
            .map(\.name)

        state.say("Exporting \(jobs.count) day\(jobs.count == 1 ? "" : "s")…")
        write(
            jobs, sections: sections, looks: looks,
            columns: effectiveColumns.isEmpty ? nil : effectiveColumns,
            widths: widths, autoTable: autoTable, autoAsk: autoAsk,
            alsoWorkbook: alsoWorkbook, flat: flat, diagram: diagram, narrowing: narrowing,
            named: !named.isEmpty, into: target, engine: engine, state: state, finished: finished
        )
        return true
    }

    /// Each day in turn — its PDF rendered, then its workbook — one after
    /// another rather than all at once, because every PDF wants a web view
    /// and forty of those at the same moment is a way to run out of memory
    /// on a long shoot.
    private static func write(
        _ jobs: [(name: String, day: Engine.ExportScope.Day)],
        sections: [String],
        looks: [String: Printing.Look],
        columns: [String]?,
        widths: [String: Double],
        autoTable: Bool,
        autoAsk: AutoAsk,
        alsoWorkbook: Bool,
        flat: Bool,
        diagram: [String],
        narrowing: [String] = [],
        named: Bool = false,
        into: URL,
        engine: Engine,
        state: ShellState,
        finished: ((_ written: Int, _ trouble: [String]) -> Void)? = nil
    ) {
        var remaining = jobs
        var written = 0
        var problems: [String] = []

        func next() {
            guard let job = remaining.first else {
                if problems.isEmpty {
                    state.say("Exported \(written) day\(written == 1 ? "" : "s")")
                } else {
                    state.say("Exported \(written), but \(problems.count) had trouble")
                }
                if Launch.checking {
                    FileHandle.standardError.write(Data((
                        "days exported: \(written)  trouble: \(problems.count)\n").utf8))
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting([into])
                }
                finished?(written, problems)
                return
            }
            remaining.removeFirst()

            // **The file names itself** (2026-10-06): film, pages, day, the
            // day it was issued — `_v2` rather than over an earlier issue.
            let film = state.view?.project.shownTitle ?? ""
            // Named by the export box (`job.name` is the stem), or the
            // older way for the `--exportdays` door.
            let stem = (FileNames.unused(
                named ? job.name + ".pdf"
                    : FileNames.export(film: film, document: FileNames.document(sections: sections),
                                       scope: job.name, ext: "pdf"),
                in: into, also: ["xlsx"]) as NSString).deletingPathExtension

            // **The workbook takes the narrowing and the columns, and nothing
            // else** — `xlsx` has never read a text size, a frame size or a
            // width, so a scope carrying them would only be a promise it
            // cannot keep. Built off the table's look because that is the
            // view a spreadsheet is.
            let sheetScope = Engine.ExportScope(day: job.day, columns: columns, narrowing: narrowing)
            var troubled = false
            if alsoWorkbook,
               engine.exportExcel(path: into.appendingPathComponent("\(stem).xlsx").path,
                                  scope: sheetScope,
                                  frames: frameStyle(for: state.view?.project)) == nil {
                troubled = true
            }

            // One job per view, each on its own paper and at its own size.
            // **Auto lays each day's table out for that day's own shots** —
            // a two-shot day and a forty-shot day are different tables.
            let auto = autoTable && sections.contains("table")
                ? engine.tableLayout(scope: Engine.ExportScope(day: job.day, columns: columns,
                                                             extra: autoAsk.words, narrowing: narrowing))
                : nil
            let pages = sections.map { section -> Printing.Job in
                if section == "table", let auto {
                    return Printing.Job(
                        section: section,
                        scope: Engine.ExportScope(
                            day: job.day, columns: columns,
                            scale: auto.scale, frames: auto.frames, shares: auto.shares,
                            fitted: auto.cut == 0, narrowing: narrowing),
                        orientation: auto.look.orientation)
                }
                let look = looks[section] ?? Printing.Look.standard(for: section)
                return Printing.Job(
                    section: section,
                    scope: Engine.ExportScope(
                        day: job.day, columns: columns,
                        scale: look.scale, frames: look.frames.rawValue,
                        widths: section == "table" ? widths : [:],
                        // The Diagram page's own switches (Shot List, Scale Bar…).
                        extra: section == "diagram" ? diagram : [],
                        narrowing: narrowing
                    ),
                    orientation: look.orientation
                )
            }

            Printing.combinedDocument(pages, engine: engine) { result in
                switch result {
                case .success(let drawn):
                    let doc = flat ? Printing.flattened(drawn) : drawn
                    let out = into.appendingPathComponent("\(stem).pdf")
                    if doc.write(to: out) { written += 1 } else { troubled = true }
                case .failure:
                    troubled = true
                }
                if troubled { problems.append(job.name) }
                next()
            }
        }
        next()
    }
}
