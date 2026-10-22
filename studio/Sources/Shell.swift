import SwiftUI
import AppKit
import AVFoundation

/// What the window is looking at.
///
/// Not document state — that lives in the engine and always will. This is the
/// three facts a window has of its own: which place the sidebar is in, which
/// scene is selected, which tab is showing. They are remembered across launches
/// because reopening on scene 1 of a film you were half way through is a small
/// insult repeated daily.
final class ShellState: ObservableObject {
    /// One per process. The launch delegate reaches it to apply command-line
    /// flags before the first frame is drawn, which is how the app is checked
    /// by looking rather than by driving the screen.
    static let shared = ShellState()

    @Published var sideTab: SideTab {
        didSet {
            // **Never standing in a mode that is off** (stage 5 step 4 B):
            // anything that jumps to one — a button, a shortcut, a checking
            // flag — lands on the first mode that is on instead.
            if let first = modesShown.first, !modesShown.contains(sideTab) { sideTab = first }
            ShellState.published("sideTab"); defaults.set(sideTab.rawValue, forKey: "place")
        }
    }
    /// **The modes this project has on** (stage 5 step 4, piece B): the
    /// switcher shows only these. Every mode while the server's modes switch
    /// is off, or the film belongs to no project. `ProjectCards.lay` sets it.
    @Published private(set) var modesShown: [SideTab] = SideTab.allCases
    /// **The mods this project has on** (Mods.swift), from its card. Empty —
    /// the app exactly as before mods — for every project that uses none.
    @Published var modsOn: [String] = [] { didSet { if modsOn != oldValue { fileEditPieces() } } }
    /// **Each row's piece of an edit reference's bracket** (EditReference.swift),
    /// by row id. Empty unless the project has Edit Reference on.
    var editPieces: [String: [EditPiece]] = [:]
    /// **Where a bracket passes a heading or an "Add shot"** between its
    /// rows: `head:<scene>`, `foot:<scene>`, `head:day:<day>`.
    var editThrough: [String: [EditPiece]] = [:]
    /// The shots an Add Edit Reference sheet is open for.
    @Published var editRefAdding: [String]?
    /// The edit reference whose player is open.
    @Published var editRefPlaying: String?
    /// Where the play button pressed was, in the window, for the bloom.
    var editRefFrom: CGRect?
    /// Whether the modes are the project's (the switch on, a card found), so
    /// + and Turn Off are offered.
    @Published private(set) var modesFollowCard = false
    /// A short line under the switcher: the open mode was turned off
    /// elsewhere, or a change could not be made. Clears itself.
    @Published var modeNote: String?
    /// A mode change on its way to the server.
    @Published var modeBusy = false
    /// **All Shoots, folded by hand** (piece D): a shoot's id → folded. A
    /// shoot not here folds when it has wrapped. `ShootPicker.swift`.
    @Published var shootFolds: [String: Bool] = [:]
    @Published var tab: SceneTab {
        didSet { defaults.set(tab.rawValue, forKey: "tab") }
    }
    @Published var sceneId: String? {
        didSet {
            ShellState.published("sceneId")
            guard sceneId != oldValue else { return }
            defaults.set(sceneId, forKey: "sceneId")
            // **Naming a scene is asking to be carried to it** — from the
            // sidebar, from the document, from anywhere. The one exception is
            // the table reporting the scene the reader has just scrolled into,
            // which sets `scrollingToScene` first: that is a report, not a
            // request, and acting on it would scroll the table out from under
            // the hand that was scrolling it.
            if !scrollingToScene { goToScene = sceneId }
        }
    }
    /// **A loose plan picked in the Diagram** (`DiagramPlans`), shown in the
    /// scene's place. Nil: the Diagram shows the scene. Kept per Mac.
    @Published var diagramPlan: String? {
        didSet { defaults.set(diagramPlan, forKey: "diagramPlan") }
    }
    /// **Which of a scene's diagrams is open** (`DiagramScenes`), when it has
    /// several. Nil, or one not the scene's: its first.
    @Published var sceneDiagramPick: String?
    /// Hide Empty as set this session, by project (`DiagramScenes`) — a
    /// checking run never writes preferences, so it reads this first.
    @Published var diagramHideEmptyNow: [String: Bool] = [:]
    /// The Diagram's "N Hidden" line opened: the scenes left out (by hand or
    /// by Hide Empty) listed again, dimmed. This session only.
    @Published var diagramRevealHidden = false
    /// A scene the table has been *asked* to carry the reader to. Separate
    /// from `sceneId` for the reason above; cleared once the table has gone.
    @Published var goToScene: String? { didSet { ShellState.published("goToScene") } }
    @Published var search = ""
    /// A shot to find on the diagram — set by Show on Diagram in the shot
    /// list, read and cleared by the Diagram mode, which picks its camera.
    @Published var diagramShot: String?

    // ----------------------------------------------------------- the document

    /// The engine, and the view it last handed back.
    ///
    /// The engine is the truth. This holds no parallel copy of anything and
    /// reconciles nothing: every mutation goes engine-ward, and then the UI asks
    /// for a fresh view and draws it. That single rule is why this app does not
    /// have a class of sync bugs, and it survives from the old app intact.
    private(set) var engine: Engine?
    @Published private(set) var view: ViewModel? {
        // **Filed under its scene the moment it arrives.** See `rowsByScene`.
        didSet { fileRows() }
    }

    /// **Every row, filed under the scene it sits in.**
    ///
    /// `ViewModel.allRows` is *computed* — `groups.flatMap(\.rows)` builds a
    /// fresh array of every row in the film each time it is read — and the
    /// table read it once per scene to find that scene's rows, then again for
    /// every row it drew. Twenty-two scenes and sixty-six shots is a few
    /// thousand rows rebuilt and thrown away **per redraw**, and the table
    /// redraws on every frame of a scroll.
    ///
    /// This is not a second copy of the document: it is built from the view
    /// the engine just handed back, in the same breath, and it cannot outlive
    /// it — the same argument `describe` and `recolour` are made on. The
    /// `didSet` above is the only funnel, so it cannot be forgotten at the
    /// other place a view is assigned.
    private(set) var rowsByScene: [String: [ViewModel.Row]] = [:]

    /// The rows of one scene. A lookup, not a scan.
    func rows(of sceneId: String?) -> [ViewModel.Row] {
        guard let sceneId else { return [] }
        return rowsByScene[sceneId] ?? []
    }

    /// The scenes that still have a row in them — what a filter has left
    /// standing. Free, now the rows are filed.
    var scenesWithRows: Set<String> { Set(rowsByScene.keys) }

    /// **Sorted by Shooting Order** (2026-10-06): the list is grouped by
    /// day, each day's shots in the order they are shot.
    var shootingOrder: Bool { view?.groupBy == "day" }
    /// In shooting order, the day each row is under — `day:<id>`, or `day:`
    /// for the unscheduled — and each day's last row. Filed with the rows.
    private(set) var dayOfRow: [String: String] = [:]
    private(set) var lastInDay: Set<String> = []
    /// **The days as drawn**: a shot in an archived scene is set aside here as
    /// it is everywhere else (his report, 2026-10-06: Day 1, shot out and
    /// archived, kept coming back in Shooting Order). A day left with no
    /// shot goes with them. While the archive is open it is the archived
    /// scenes' shots that show.
    private(set) var orderGroups: [ViewModel.Group] = []
    /// **The days a person picks from**: one whose shots are all in archived
    /// scenes is left out, unless it is where the shots in hand already are.
    func pickableDays(keeping held: Set<String> = []) -> [ViewModel.Day] {
        (view?.days ?? []).filter { $0.wrapped != true || held.contains($0.id) }
    }

    private func fileRows() {
        var filed: [String: [ViewModel.Row]] = [:]
        var days: [String: String] = [:]
        var last: Set<String> = []
        var shown: [ViewModel.Group] = []
        let byDay = view?.groupBy == "day"
        let archived = Set((view?.scenes ?? []).filter(\.archived).map(\.id))
        for group in view?.groups ?? [] {
            for row in group.rows {
                guard let scene = row.sceneId else { continue }
                filed[scene, default: []].append(row)
            }
            guard byDay else { continue }
            var kept = group
            kept.rows = group.rows.filter { archived.contains($0.sceneId ?? "") == showingArchive }
            kept.count = kept.rows.count
            if kept.rows.isEmpty && !group.rows.isEmpty { continue }
            shown.append(kept)
            for row in kept.rows { days[row.id] = "day:" + (group.key ?? "") }
            if let end = kept.rows.last { last.insert(end.id) }
        }
        rowsByScene = filed
        dayOfRow = days
        lastInDay = last
        orderGroups = shown
        fileEditPieces()
    }
    @Published private(set) var projectPath: URL?

    /// **This film's own icon and colour.** Nothing for a film that has none.
    /// A reading of what the film says, never a second copy of it — see
    /// `wearTheFilmsColour`.
    @Published private(set) var mark: Console.Mark?
    /// Which film's console entry was last looked up, so the console's cache is
    /// read when the answer can have changed and not on every keystroke —
    /// `replace` is the funnel for every edit in the app.
    private var wornFor = ""
    /// Guards the one write this makes, since writing goes through `replace`
    /// and `replace` comes back here.
    private var mirroring = false

    /// **Put on the film's colour and icon.**
    ///
    /// **The film says what it wears.** Until 2026-09-11 this asked his Projects
    /// Console — a cache file a different app writes into his home folder — and
    /// so a Mac that had never run that app drew every film with no icon and the
    /// program's own blue, silently. That was his report, and his answer: *"why
    /// can't it be part of the project file data that syncs?"* It is now, so
    /// every device that has the film has the icon.
    ///
    /// Called where the answer can change and nowhere else: opening a film, and
    /// every edit — because two of the edits are the link to a Notion project
    /// being set in Project Settings and the icon being set by hand there, and
    /// the accent should follow either the moment he makes it.
    func wearTheFilmsColour() {
        mirrorTheConsole()
        let found = view?.project.mark
        Brand.wear(colour: found?.colour ?? "")
        if mark != found { mark = found }
    }

    /// **Keep a linked film's mark the same as its Notion row.**
    ///
    /// The console cache is still read — on the Mac that has one — but only as a
    /// *source*, never as the answer: what it says is written into the film,
    /// once, and from then on it travels with the film. So this Mac keeps his
    /// films current with Notion, and every other device is handed the result
    /// without needing a console, a login, or anything set up on it.
    ///
    /// **It never overwrites his own hand**, and never clears anything: a
    /// console with no entry for this film — which is every film on a Mac with
    /// no console — leaves what the film already says exactly as it is.
    private func mirrorTheConsole() {
        guard !mirroring, let engine, let view, !view.project.readOnly else { return }
        // **A film wearing its project's card keeps no copy** (stage 5 step 4):
        // the card's mark is laid over it, so nothing is written into it.
        guard !view.project.card else { return }
        // Nor one the kept cards know, before its card is laid on.
        if ProjectCards.shared.card(film: projectPath.flatMap { Relay.projectId(at: $0) },
                                    page: view.project.consolePage) != nil { return }
        guard Marks.source(view.project.markSource).mirrorable else { return }
        let page = view.project.consolePage
        // **The film's title, not the folder it sits in.** The two are the same
        // for every film he has — a package follows its title while the project
        // is new — but the title is the one he chose and the one the Notion
        // project is called. The folder name is only the fallback, for a
        // brand-new film that has not been titled yet.
        let titled = view.project.title
        let named = titled.isEmpty
            ? (projectPath?.deletingPathExtension().lastPathComponent ?? "") : titled
        let asked = "\(page)|\(named)"
        guard asked != wornFor else { return }
        wornFor = asked
        guard let found = Console.mark(page: page, named: named),
              found != view.project.mark else { return }
        mirroring = true
        defer { mirroring = false }
        replace(engine.setMark(path: found.path, colour: found.colour,
                               source: Marks.fromConsole))
        guard Launch.checking else { return }
        FileHandle.standardError.write(Data(("mark: mirrored \(found.colour)\n").utf8))
    }

    /// **He sets the film's mark himself**, for a film that is not in the larger
    /// system. From then on nothing automatic writes over it.
    func setTheMark(path: String, colour: String) {
        guard let engine else { return }
        replace(engine.setMark(path: path, colour: colour, source: Marks.byHand))
        guard Launch.checking else { return }
        FileHandle.standardError.write(Data(("mark: set by hand \(colour)\n").utf8))
    }

    /// **Back to what his Notion row says** — or to no mark at all, when there
    /// is no row to take one from.
    ///
    /// Clearing is the whole of it: the mark goes, the source goes with it, and
    /// the mirror is free again — so `replace` coming back through
    /// `wearTheFilmsColour` puts the Notion one on immediately where there is
    /// one. `wornFor` is cleared first so it asks rather than remembering the
    /// answer it gave a moment ago.
    func clearTheMark() {
        guard let engine else { return }
        wornFor = ""
        replace(engine.setMark(path: "", colour: "", source: ""))
        guard Launch.checking else { return }
        FileHandle.standardError.write(Data(("mark: cleared\n").utf8))
    }

    /// What went wrong opening a project, in a sentence a person can act on.
    @Published var problem: String?
    /// Files that were still placeholders when the project was opened — a
    /// film opened out of iCloud Drive, which the home folder no longer is.
    @Published var stillArriving: [String] = []
    /// Whether the project browser is showing.
    @Published var browsing = false
    /// Whether the Edit Columns sheet is showing.
    @Published var editingColumns = false
    @Published var editingProject = false
    /// The gear's popover in the top bar.
    @Published var gearOpen = false
    /// The page Project Settings opens on when something asks for one —
    /// the script panel's Edit… opens the Script page (2026-09-19).
    @Published var settingsPage: SettingsPage?
    /// Which list the project settings should open on, when something else
    /// sent you there — a column's own page, say. Cleared as it is used.
    @Published var settingsList: String?
    /// The column whose own page is open, by field name. Held here rather
    /// than inside the sheet so a checking run can open it directly — a
    /// sheet on a sheet cannot be reached by clicking in a photograph.
    @Published var editingColumn: String?
    /// The scene whose details are open, by id.
    @Published var editingScene: String?
    /// The scene a new sequence is being named for.
    @Published var namingSequence: String?
    /// The scene(s) whose PDF export sheet is open, by id. One scene, or
    /// several picked at once.
    @Published var exportingScenes: [String] = []
    /// The same dialog, asked for the **whole film** rather than a pick —
    /// the share button's own PDF door. Kept apart from `exportingScenes`
    /// because "no scenes picked" and "every scene" are different questions
    /// and an empty array cannot say which one is meant.
    @Published var exportingWholeProject = false
    /// The same dialog, opened from the Diagram's Export…: the scene or
    /// loose plan in `exportingScenes`, with only its Diagram page ticked.
    @Published var exportJustDiagram = false
    /// Which pane the export box opens on — the basket unless something says
    /// otherwise. **Only `--exportbox` ever sets it**, so a checking run can
    /// photograph a view's own look and not just the basket.
    @Published var exportOpensOn: String?
    /// `--exportpaper table:portrait` — one view's paper, set from outside, so
    /// a check can prove a look is kept across a relaunch. Only ever set by a
    /// checking run.
    @Published var exportPaperSaid: String?
    /// `--exportsetup save:Day package` or `use:Day package`, so a check can
    /// prove a saved set-up comes back. Only ever set by a checking run.
    @Published var exportSetupSaid: String?
    /// `--exportvisit table,storyboard,table` — walk the views, one every
    /// 2.5s, so a check can prove a page already drawn is not drawn twice.
    /// Only ever set by a checking run.
    @Published var exportVisitSaid: String?
    /// `--exportnext 3` — turn the page that many times, then say where it
    /// landed. Only ever set by a checking run.
    @Published var exportNextSaid: String?
    /// `--exportkey right,right` — press real arrow keys at the export window
    /// once its page is drawn. Only ever set by a checking run.
    @Published var exportKeySaid: String?
    /// `--exportsave <path>` — press Export… in the export window and answer
    /// its save panel with this path (a folder, for a per-day export). Only
    /// ever set by a checking run.
    @Published var exportSaveSaid: String?
    /// `--exportset arrange=schedule;days=12-18+22;output=perday;filter=none`
    /// — the export box's Order, Filter, Days and Output, set from outside.
    /// Only ever set by a checking run.
    @Published var exportSetSaid: String?
    /// `--exportdrag width:20` (or `scale:20`) — move one of the export
    /// window's sliders that many times, a frame apart, the way a hand drag
    /// does, and say the longest the main thread stalled while it happened.
    /// Only ever set by a checking run.
    @Published var exportDragSaid: String?
    /// Whether the document page's type panel opens with the window. Only
    /// ever set by a checking run — it is a popover, and a popover cannot be
    /// clicked open by one.
    @Published var showTypePanel = false
    /// The pending rewrite of the linked workbook, if one is booked. Held so
    /// the next change can cancel it — see `scheduleWorkbookRewrite`.
    private var workbookRewrite: DispatchWorkItem?
    /// Where each scene's line sits on screen, so the chrome can tell which
    /// scene is being read. Written by the table, read by nobody else.
    ///
    /// **Deliberately not `@Published`, and that is the fix for his lag.**
    /// These move on every tick of a scroll wheel. While they were published,
    /// every tick invalidated the sidebar, the chrome, the filter bar and
    /// every row on screen — three whole-window redraws per frame of scroll,
    /// which is exactly what "lag every time I slide between headers" was.
    /// Nothing *draws* from them; they are looked up when a mouse asks.
    var sceneFrames: [String: CGRect] = [:]
    /// Where the table's rows begin on screen — the line a scene has to pass
    /// to count as the one being read.
    var tableTop: CGFloat?
    /// How far down the table is scrolled. Plain storage for the same reason
    /// `sceneFrames` is: it changes on every tick of a wheel and nothing
    /// *draws* from it. A checking run reads it to say whether a scroll it
    /// asked for actually moved anything — `--scroll` silently moved nothing
    /// for weeks, and no report could see that.
    var tableOffset: CGFloat = 0
    /// Which value each facet is narrowed to, so the menus can show it. The
    /// engine holds the narrowing itself; this is only how the chrome knows
    /// what to tick. Never written to the document — what you are looking at
    /// is not a fact about the film.
    @Published var facets: [String: String] = [:] { didSet { ShellState.published("facets") } }
    /// The side panel: whether it is out, how wide, and which of its three
    /// sections is showing. Its width is remembered the way the sidebar's is.
    @Published var panelShown = false {
        didSet { defaults.set(panelShown, forKey: "panelShown") }
    }
    @Published var panelWidth: CGFloat = 320 {
        didSet { defaults.set(Double(panelWidth), forKey: "panelWidth") }
    }
    @Published var panel: PanelSection = .references {
        didSet { defaults.set(panel.rawValue, forKey: "panelSection") }
    }
    /// Set while the table is scrolling itself to a scene the sidebar named,
    /// so the scroll it causes is not mistaken for the person reading their
    /// way there — which would fight the very scroll it started.
    /// **Starts true**, and the table's opening scroll is what clears it.
    /// The table works out which scene is being read from where the bands
    /// land, and on the very first layout — before it has scrolled anywhere —
    /// that answer is always "the first scene in the script". Left ungated,
    /// that answer overwrote the scene he actually left off on, one frame
    /// before the table went to look for it.
    var scrollingToScene = true
    /// Whether the add-a-scene prompt is showing.
    @Published var addingScene = false
    /// The Paste Script sheet — a commercial's script, any shape, read back
    /// before it lands. `PasteScript.swift`.
    @Published var pastingScript = false
    /// Naming a section with no scene joining it — from the list's menu.
    @Published var namingSection = false
    /// What the New scene box opens holding — empty in his hand, and the
    /// line a check asked for when one did.
    @Published var newSceneHeading = ""
    /// A check pressing Add for itself, so the writing half of the box is
    /// watched rather than assumed. Never set in his hand.
    @Published var newSceneNow = false
    /// …and pressing *Add another*, which leaves the box open on the next
    /// number rather than closing it.
    @Published var newSceneAgain = false

    // --------------------------------------------------------- locations

    /// Which location is open on the Locations tab. Remembered, the way the
    /// scene is — coming back to a project should come back to where you were.
    @Published var locationId: String? {
        didSet {
            guard locationId != oldValue else { return }
            defaults.set(locationId, forKey: "locationId")
        }
    }
    /// Whether the name-a-location prompt is showing.
    /// The column just made, so the columns sheet can scroll to it — Ref 281.
    /// On the state rather than inside the sheet because the sheet is built
    /// fresh when it opens, and a column added from anywhere should still be
    /// the one you are looking at.
    @Published var columnLanded: String?
    /// How the wall of location photographs fills each tile — the same
    /// `original`/`square`/`project` a mood board offers, since 2026-08-24 his
    /// instruction is one set of gallery rules everywhere. Was a plain
    /// square/original bool, his own ask on 2026-08-22; migrated rather than
    /// reset, so a Mac that had it set to square keeps that on first launch
    /// after the update instead of quietly reverting to `original`.
    @Published var locationRatioMode: String = {
        // A checking run starts from a known value, not whatever this Mac's
        // real preference happens to be — the same reason `boardUnit` and
        // `cardWidth` both pin under `Launch.checking`. Without this, a
        // `--photoshape` check would pass or fail depending on which shape
        // was last chosen by hand, rather than on what the flag actually did.
        guard !Launch.checking else { return "square" }
        if let saved = Remembering().object(forKey: "locations.ratioMode") as? String { return saved }
        let old = Remembering().object(forKey: "locations.squarePhotos") as? Bool ?? true
        return old ? "square" : "original"
    }() {
        didSet { Remembering().set(locationRatioMode, forKey: "locations.ratioMode") }
    }
    /// How big a location's photographs are drawn — the same slider a mood
    /// board's wall has; this wall never had one until 2026-08-24.
    @Published var locationTile: CGFloat = Launch.checking
        ? 152
        : CGFloat(UserDefaults.standard.object(forKey: "locationTile") as? Double ?? 152) {
        didSet { defaults.set(Double(locationTile), forKey: "locationTile") }
    }
    @Published var addingLocation = false

    // ------------------------------------------------------- mood boards

    /// Which board is open on the Boards tab. Remembered, the way the scene
    /// and the location are — coming back to a project should come back to
    /// where you were.
    @Published var boardId: String? {
        didSet {
            guard boardId != oldValue else { return }
            defaults.set(boardId, forKey: "boardId")
        }
    }
    /// Whether the name-a-board prompt is showing.
    @Published var addingBoard = false
    /// The board being renamed, if one is. On the state rather than inside the
    /// list because the rename is reached from two places — the sidebar's
    /// right-click and the wall's own button — and both open the one sheet.
    @Published var renamingBoard: String?

    /// The day whose name, or whose date, is being asked for. On the state
    /// rather than inside `Schedule` for the reason `--copyto` exists: both
    /// sheets are reached only by right-clicking a day band, a synthetic mouse
    /// cannot open a context menu, and a feature nothing can reach is a feature
    /// nothing checks. Ref 341.
    @Published var namingDay: String?
    @Published var datingDay: String?

    /// The schedule's calendar panel: whether it is out, and how wide.
    /// Remembered the way the side panel's are — and pinned under a checking
    /// run, so a `--clickdate` check starts from a known posture rather than
    /// from whatever was last chosen by hand.
    @Published var calendarShown: Bool = Launch.checking
        ? false
        : UserDefaults.standard.bool(forKey: "calendarShown") {
        didSet { defaults.set(calendarShown, forKey: "calendarShown") }
    }
    @Published var calendarWidth: CGFloat = Launch.checking
        ? 300
        : CGFloat(UserDefaults.standard.object(forKey: "calendarWidth") as? Double ?? 300) {
        didSet { defaults.set(Double(calendarWidth), forKey: "calendarWidth") }
    }
    static let calendarRange: ClosedRange<CGFloat> = 280...420
    /// Whether the schedule's strips show each scene's summary. Off by
    /// default — this screen is read as a grid. Here rather than inside
    /// `Schedule` so `--synopsis` can reach it.
    @Published var stripSynopsis = false
    /// **Shooting Order** — each day drawn as its shots in the order they
    /// are shot, dragged into place one by one, instead of as scene strips.
    /// Remembered, and pinned off under a checking run (`--shootingorder`
    /// turns it on).
    @Published var stripRun: Bool = Launch.checking
        ? false
        : UserDefaults.standard.bool(forKey: "scheduleShootingOrder") {
        didSet { defaults.set(stripRun, forKey: "scheduleShootingOrder") }
    }
    /// Which strips on the board are open, showing their synopsis and shots.
    @Published var openStrips: Set<String> = []
    /// Scenes opened in the scene list on the Schedule, showing the shots
    /// still on no day — each one can be dragged onto a day by itself.
    @Published var openRemainders: Set<String> = []
    /// Shots picked among those opened remainders (placement ids): a drag on
    /// one of them carries them all.
    @Published var loosePicked: Set<String> = []
    /// The month the calendar shows, as `yyyy-MM`, when a check has pinned it.
    /// Nil is the ordinary case: the calendar seeds itself from the schedule.
    @Published var calendarMonth: String?
    /// The day a calendar click pointed at, so the board can scroll there and
    /// flash it. The flash clears it.
    @Published var highlightedDay: String?

    /// The board on screen, as the engine last described it. Falls back to the
    /// first one, so a project whose remembered board has been deleted opens
    /// on a real wall rather than on nothing.
    var board: ViewModel.MoodBoard? {
        let all = view?.boards ?? []
        return all.first { $0.id == boardId } ?? all.first
    }
    /// Adding a **room inside** this location — Ref 269. Holds the house's id;
    /// nil means the Add sheet is making a location that stands on its own.
    @Published var addingAreaIn: String?

    // ------------------------------------------------------------ script

    /// The PDF being taken in, if one is. Held here rather than inside the
    /// settings sheet because a script comes in by three doors — the File menu,
    /// the project's own settings, and the empty script panel — and all three
    /// have to open the same one sheet.
    @Published var importingScript: ScriptFile?
    /// Whether the new-project setup screen is showing. Raised when a project
    /// is *made*, never when one is opened — a film gets set up once.
    @Published var settingUp = false
    /// New Project making the card on the server (`NewCard.swift`, one ID).
    @Published var makingCard = false
    /// Bumped when a draft lands. The script panel re-lays the screenplay when
    /// this changes and at no other time — laying out a whole script is real
    /// work, and the answer does not change while somebody types in the table.
    @Published var scriptStamp = 0

    /// **Which photograph is picked, by media ref.** His ask, 2026-08-21: a
    /// single click puts a blue box round a still and nothing else happens; the
    /// arrows walk from one to the next; a double-click or the space bar pops
    /// the viewer out; and once it is out, the arrows carry it with them.
    ///
    /// Held on the state rather than inside the wall so a checking run can read
    /// it back — a selection nothing can report is a selection nothing can
    /// check.
    @Published var pickedPhoto: String?
    /// **Every photograph picked, where more than one is.** His ask,
    /// 2026-08-22: *"I need to be able to multi-select multiple images anywhere
    /// you can find them … so that I can mass delete."*
    ///
    /// `pickedPhoto` stays the **anchor** — the one the arrows walk from and
    /// the one the pop-out follows — and this is the set. A plain click makes
    /// the set one picture, which is why everything that only ever wanted one
    /// still works without knowing this exists.
    @Published var pickedPhotos: Set<String> = []

    /// What a click on a picture means, given what is held down.
    ///
    /// Finder's grammar, which is the one his hands already know: plain picks
    /// one, ⌘ adds or takes away, ⇧ reaches from the anchor to here.
    func pick(photo ref: String, among all: [String]) {
        let held = NSEvent.modifierFlags
        if held.contains(.command) {
            if pickedPhotos.contains(ref) {
                pickedPhotos.remove(ref)
            } else {
                pickedPhotos.insert(ref)
            }
        } else if held.contains(.shift), let anchor = pickedPhoto,
                  let from = all.firstIndex(of: anchor),
                  let to = all.firstIndex(of: ref) {
            let reach = from <= to ? from ... to : to ... from
            pickedPhotos.formUnion(reach.map { all[$0] })
        } else {
            pickedPhotos = [ref]
        }
        pickedPhoto = ref
    }

    /// How many different values a scene facet actually has across this film.
    /// Zero means its submenu is empty, which is a filter nobody can use.
    func sceneValueCount(_ field: String) -> Int {
        let scenes = (view?.scenes ?? []).filter { !$0.archived }
        var seen = Set<String>()
        if field == "location_id" {
            // Every place each scene is at, not just its first — a location
            // used only as a scene's second stop is still a location the film
            // can be narrowed to.
            for sc in scenes { seen.formUnion(sc.locations) }
            return seen.count
        }
        for sc in scenes {
            let held: String
            switch field {
            case "location":          held = sc.location
            case "shooting_location": held = sc.shootingLocation
            case "time_of_day":       held = sc.timeOfDay
            case "int_ext":           held = sc.intExt
            case "priority":          held = sc.priority
            case "pov":               held = sc.pov
            default:                  held = ""
            }
            if !held.isEmpty { seen.insert(held) }
        }
        return seen.count
    }

    /// Take these photographs off whatever they are on. One road, so the menu
    /// and a checking run cannot do different things.
    func removePhotos(_ refs: [String]) {
        guard let engine else { return }
        for ref in refs {
            replace(engine.detach(frame: ref))
        }
        pickedPhotos = []
        pickedPhoto = nil
    }

    /// **Carrying a picture to a new place on a wall.** Ref 211's ordering,
    /// driven from a 2-D grid rather than the frames strip's single row.
    ///
    /// The arithmetic lives here rather than in the gesture for the reason the
    /// schedule's day-carry learned the hard way: **a synthetic mouse cannot
    /// drive a drag**, so a reorder written only as a gesture is a feature no
    /// check can ever reach. `--putpicture` presses this same method.
    ///
    /// `before` is the picture it was dropped on. Dropping a picture on itself,
    /// or on nothing, is not a move.
    func moveWallPicture(_ ref: String, before other: String, among all: [String]) {
        guard let engine, ref != other,
              let from = all.firstIndex(of: ref) else { return }
        // **The engine counts the slot with this picture already lifted out**
        // — `move_media_to` filters the mover out before reading its
        // neighbours. So the target has to be read from the shortened list
        // too, or every rightward move lands one place short. The same
        // off-by-one the shoot days had (Ref 342).
        var rest = all
        rest.remove(at: from)
        guard let slot = rest.firstIndex(of: other) else { return }
        replace(engine.moveFrame(ref, to: slot))
    }

    /// Whether a picture is picked — by the set, or as the lone anchor.
    func isPicked(_ ref: String) -> Bool {
        pickedPhotos.contains(ref) || (pickedPhotos.isEmpty && pickedPhoto == ref)
    }

    /// Everything a "remove these" would act on, in one place so the wall and
    /// the board cannot disagree about what "these" means.
    func photosActedOn(_ ref: String) -> [String] {
        pickedPhotos.contains(ref) ? Array(pickedPhotos) : [ref]
    }

    /// **Several scenes at once** — Ref 240.
    ///
    /// `sceneId` stays what it always was: the scene you are standing in, the
    /// one the table scrolls to and the script panel draws. This is the wider
    /// thing — what a bulk action acts on — and it is kept apart on purpose,
    /// because every other screen in the app reads `sceneId` and none of them
    /// should have to learn about a set.
    @Published var pickedScenes: Set<String> = [] { didSet { ShellState.published("pickedScenes") } }

    /// **Where the panels that float over the table are.** Ref 271.
    ///
    /// The table reads the mouse through a local event monitor rather than
    /// through SwiftUI's own hit-testing, so that dragging a shot by its
    /// gutter and dragging a column by its header are one grammar. The cost is
    /// that the monitor sees *every* click in the window, including clicks on
    /// things drawn on top of the table — and a button in the script panel that
    /// happens to sit over a column header was sorting that column as well as
    /// doing its own job. His report: *"it's like a pass-through."*
    ///
    /// Anything drawn over the table registers its frame here and the monitor
    /// leaves those clicks alone. In global coordinates, the same space
    /// `headerFrames` uses.
    var panelFrames: [String: CGRect] = [:]

    /// **Which published property republished the window, and how often.**
    ///
    /// Every view in the window observes this one object, so any write here
    /// redraws all of it. When the app hangs there is no way, from the
    /// outside, to tell "one property is firing in a loop" from "the work per
    /// write is simply too big" — and those want opposite fixes. This counts,
    /// so the question is answered rather than argued.
    ///
    /// Measured 2026-08-30, twenty seconds of driving: switching modes as well
    /// as scenes gives `sideTab 123, goToScene 54, sceneId 51` with **88 of
    /// 612 frames late**; scenes alone gives `goToScene 55, sceneId 53,
    /// sideTab 1` with **29 of 1,076**. Nothing runs away — the counts are
    /// exactly what the driver asked for. **A mode change is just very
    /// expensive**: it re-measures the whole window from its root.
    static var publishes: [String: Int] = [:]
    static func published(_ what: String) { publishes[what, default: 0] += 1 }

    /// The selection the sidebar shows, in the shape `List` wants. Reading it
    /// falls back to the scene you are standing in, so opening a project with
    /// nothing picked still highlights a row.
    var sceneSelection: Set<String> {
        get { pickedScenes.isEmpty ? Set([sceneId].compactMap { $0 }) : pickedScenes }
        set {
            pickedScenes = newValue.count > 1 ? newValue : []
            // Standing somewhere is not optional: a click that lands on one
            // scene moves the cursor there, and a ⌘-click that grows the set
            // leaves the cursor where it was.
            if newValue.count == 1, let only = newValue.first { sceneId = only }
            if newValue.isEmpty { pickedScenes = [] }
        }
    }

    /// The same rule as the photograph wall, and for the same reason: acting on
    /// a scene that is not in the picked set acts on that one; acting on one
    /// that is acts on all of them. Decided in one place so two menus cannot
    /// disagree about what "these" means.
    func scenesActedOn(_ id: String) -> [String] {
        pickedScenes.contains(id) ? Array(pickedScenes) : [id]
    }

    /// Point several scenes at one location — the reason to pick several in
    /// the first place. A method rather than a loop inside the menu, so a
    /// check can exercise the same path his mouse does.
    func setLocation(on scenes: [String], to place: String) {
        guard let engine else { return }
        for id in scenes {
            replace(engine.sceneLocation(id, place))
        }
    }

    /// **Set the time of day on several scenes at once** — his ask,
    /// 2026-09-02. A day of nights is a dozen scenes and it was a dozen trips
    /// through the scene editor.
    ///
    /// **The same call the scene editor makes**, one scene at a time, so a
    /// bulk edit and a single edit cannot come to mean different things. A
    /// method rather than a loop inside the menu, for the same reason
    /// `setLocation` is one: a check can exercise the path his mouse does.
    ///
    /// The picked set is deliberately *kept* afterwards, the way it is after
    /// setting a location — the scenes stay lit so he can see what he changed.
    func setTimeOfDay(on scenes: [String], to time: String) {
        guard let engine else { return }
        for id in scenes {
            replace(engine.set(shot: id, field: "time_of_day", value: time))
        }
    }

    /// Archive or unarchive several at once.
    func archive(_ scenes: [String], on: Bool) {
        guard let engine else { return }
        for id in scenes {
            replace(engine.archiveScene(id, on: on))
        }
        pickedScenes = []
    }
    /// How many photographs fit across the wall right now. Written by the wall
    /// as it lays out, read by the arrow keys — ↑ and ↓ cannot mean anything
    /// without it.
    var photosAcross = 1
    /// The location whose address is being found on the map, by id. Held on
    /// the state rather than inside the page so a checking run can open it.
    @Published var findingAddress: String?

    /// The locations, narrowed by the search box the same way the scenes are.
    /// Name and address both, because on a scout the thing you remember is as
    /// often the street as the name you gave it.
    var locations: [ViewModel.Location] {
        // Narrowed to a shoot (piece D): a place with scenes but none in
        // this shoot is another shoot's.
        let all = (view?.locations ?? []).filter(\.inShoot)
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.name.lowercased().contains(q)
                || $0.effectiveAddress.lowercased().contains(q)
        }
    }

    /// **The boards the search box has left standing.** The sidebar's search
    /// has been drawn over this list since the sidebar was built and did
    /// nothing at all on this tab — the locations list beside it has always
    /// honoured it. Here rather than inside the list for the reason everything
    /// else checkable is here: a run can set the search and read back what
    /// survived it.
    ///
    /// A board is matched by its name **and by the names of the pictures on
    /// it**, so looking for `mountain` finds the wall it is pinned to.
    var boardsShown: [ViewModel.MoodBoard] {
        let all = view?.boards ?? []
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { board in
            board.name.lowercased().contains(q)
                || board.media.contains { $0.filename.lowercased().contains(q) }
        }
    }

    /// The location being looked at. Falls back to the first, so the screen is
    /// never blank while the project plainly has locations in it.
    var location: ViewModel.Location? {
        view?.locations.first { $0.id == locationId } ?? view?.locations.first
    }

    // ------------------------------------------------------------ the cursor

    /// Where the table's cursor is, and whether a cell is open for typing.
    /// Kept here rather than inside the table so a checking run can put the
    /// cursor somewhere and photograph it.
    @Published var cursorShot: String?
    @Published var cursorColumn: String = "description"
    @Published var editing = false
    /// The character that started an edit, so arrowing to a cell and typing is
    /// one motion: the keystroke that opened the cell is also its first input,
    /// and for a choice cell it is what the list is already filtered by.
    @Published var editSeed = ""
    /// Whether the open cell's own text view has the keyboard.
    ///
    /// In front of a person it does, and every key is its own — caret, drag,
    /// ⌘A, ⌘C, Shift-Return. A checking run never brings the window forward, so
    /// there the view is never first responder and the window monitor types
    /// into the same string instead. One text either way.
    @Published var editorLive = false

    /// How the open cell was opened, because a sheet gives the two openings
    /// different arrow keys. Typing fresh onto a selected cell is *replace*
    /// mode: every arrow commits and moves, which is what the recording shows.
    /// Return or double-click is *revise* mode: the arrows belong to the text
    /// and walk the caret. Google Sheets makes exactly this distinction, and
    /// its absence is a large part of "does not feel like a sheet".
    @Published var editOpenedByTyping = false

    /// Whether the person has expressed a choice at an open picker — typed a
    /// filter, or moved the highlight. A pristine picker's Return closes it
    /// without writing: otherwise opening Size and pressing Return again would
    /// write the *first* option over what the cell held, and on a multi-value
    /// cell it would silently toggle the current value off.
    var pickTouched = false

    /// Bumped when a column width changes, so the table redraws — the widths
    /// themselves live on `Columns`, one place the header, the cells and the
    /// editor all read.
    @Published var columnBump = 0 { didSet { ShellState.published("columnBump") } }

    /// Where each column's header is, in window coordinates, top-left origin —
    /// reported live by the header cells themselves, so the mouse monitor can
    /// tell a divider from a name from a row without knowing anything about
    /// scroll offsets. The frames move when the table scrolls; the map follows.
    var headerFrames: [String: CGRect] = [:]
    /// Where each row's gutter is, in the same global coordinates — what the
    /// mouse monitor hit-tests a row carry against.
    var rowFrames: [String: CGRect] = [:]
    /// The row being carried to a new place, and the row it would land in
    /// front of — nil landing while carrying means the foot of the scene.
    @Published var carryingRow: String?
    @Published var landingRow: String?
    /// A drag-selected rectangle of cells: two corners; the rows and columns
    /// between them are read off the current orders when needed.
    struct CellRange: Equatable {
        var anchorRow: String
        var anchorColumn: String
        var endRow: String
        var endColumn: String
    }
    @Published var cellRange: CellRange?
    /// **The cells ⌘C or ⌘X last took**, drawn with a dashed outline the way a
    /// sheet's marching ants mark them. It goes on Esc, on an edit, and — for a
    /// cut — once the paste has landed. A cut empties its cells *then*, not
    /// when ⌘X is pressed, so a cut that is never pasted loses nothing.
    @Published var copiedCells: CellRange?
    /// Whether `copiedCells` is waiting to be emptied by a paste.
    var copiedCut = false
    /// The text those cells put on the clipboard. A paste only empties a cut's
    /// cells while the clipboard still holds exactly this, so something copied
    /// in another program in between cannot make a later paste take them.
    var copiedText = ""
    /// The shot picked *as a whole* — by its number column — rather than a cell
    /// of it. It draws a ring round the row and is the state a shot can be
    /// carried in. Cleared the moment a cell is picked instead, because two
    /// kinds of selection standing at once is how a person stops knowing what
    /// a key is about to act on.
    @Published var wholeShots: Set<String> = []
    /// Where a ⇧-range of whole shots counts from.
    @Published var wholeAnchor: String?
    /// **The archive is a place you go, not a menu you read.** His correction:
    /// archived scenes come out of the main list entirely, and the chevron
    /// switches the sidebar over to showing them — "that selector is selecting
    /// 'show me all the archived scenes', and then from there I can look at
    /// them again and decide to restore them". Picking one must not quietly
    /// put it back; a restore is a decision, and decisions are his.
    @Published var showingArchive = false { didSet { fileRows() } }
    /// Which scene a carried shot would land in — the one the pointer is over,
    /// which is not always the scene of the row it would sit above.
    @Published var landingScene: String?
    /// **The shots on the app's own clipboard.** Copying shots does not put
    /// text anywhere — a shot is its frames and its gear as much as its words,
    /// and none of that survives a trip through the pasteboard as columns.
    /// These are placement ids, and pasting makes copies of them.
    @Published var copiedShots: [String] = []
    /// What went on the clipboard with them, so ⌘V can tell the clipboard is
    /// still those shots and not something copied since.
    var copiedShotsText = ""
    /// Up when he is choosing a scene to send the held shots to.
    @Published var movingShots = false
    /// The shot whose frames are open in the media window, by placement id.
    @Published var mediaShown: String?
    /// The frame the frames window is looking at, so the keyboard can walk
    /// the filmstrip from the window monitor.
    @Published var frameSelected: String?
    /// Cards per storyboard row, reported by the layout for the arrow keys.
    var storyboardColumns = 1
    /// The storyboard's rows, as the layout drew them: shot ids, left to
    /// right, top to bottom. Rows are not all the same length now that a card
    /// follows its picture's shape, so ↑ and ↓ read this.
    var storyboardRows: [[String]] = []
    /// Where each storyboard frame box actually landed. Eyeballing a
    /// screenshot could not tell 2.39 from 2.44; the layout reports instead.
    var cardFrames: [String: CGRect] = [:]
    /// How wide a storyboard card is. His preference, remembered — except in
    /// a checking run, which drives it with `--card` and never writes his.
    @Published var cardWidth: CGFloat = Launch.checking
        ? 264
        : CGFloat(UserDefaults.standard.object(forKey: "storyboardCard") as? Double ?? 264) {
        didSet { defaults.set(Double(cardWidth), forKey: "storyboardCard") }
    }
    /// **How big the pictures on a mood board are.** One size for the whole
    /// wall — per-picture sizing was built and he had it taken out again on
    /// 2026-08-24, because a wall of four different tile sizes reads as a mess
    /// rather than as one thing. His, remembered, the same way a storyboard
    /// card is, and pinned in a checking run so a battery cannot inherit
    /// whatever the last drag left behind.
    @Published var boardUnit: CGFloat = Launch.checking
        ? 152
        : CGFloat(UserDefaults.standard.object(forKey: "boardUnit") as? Double ?? 152) {
        didSet { defaults.set(Double(boardUnit), forKey: "boardUnit") }
    }
    /// One quiet sentence to the person — "Read 47mm off the viewfinder
    /// frame" — shown over the table and gone on its own.
    @Published var notice: String?
    private var noticeFade: DispatchWorkItem?

    func say(_ line: String) {
        notice = line
        noticeFade?.cancel()
        let fade = DispatchWorkItem { [weak self] in self?.notice = nil }
        noticeFade = fade
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: fade)
    }

    /// A header being carried to a new place, and the column it would land in
    /// front of (nil is the far end). Published because the header draws the
    /// carried name dimmed and a landing line where it will go.
    @Published var carrying: String?
    @Published var landing: String?

    /// The ticked rows, when an action should reach more than the cursor.
    ///
    /// The old app's model, kept exactly: empty means "the cursor's row" and
    /// every operation reads through `actingOn`, so one code path serves one
    /// shot and forty. Shift-click ranges from the cursor, ⌘-click toggles,
    /// ⌘A takes the scene, Escape or a plain click lets go.
    @Published var marked: Set<String> = []

    /// Which row of an open picker is highlighted — the one Return takes.
    ///
    /// It lives here rather than inside the list because the keys are read at
    /// the window: the monitor moves the highlight, the list only draws it.
    /// Anything else puts the arrow keys and the list in two different places
    /// and they drift apart.
    @Published var pickAt = 0
    /// How many key events the table's monitor actually saw. A checking aid, and
    /// the one that separates "typing went to the wrong place" from "typing
    /// never arrived" — the same distinction the drag counter draws.
    var keysSeen = 0

    /// Takes a fresh view from the engine after a change.
    ///
    /// Every mutation goes engine-ward and then the UI asks for a new view —
    /// nothing here edits a copy. `nil` means the engine refused, and refusing
    /// is a legitimate answer, so the old view stands rather than being cleared.
    /// What undo would do next — the engine's answer, refreshed after every
    /// change so the menu of the moment is never a beat behind the document.
    @Published var history = History(
        canUndo: false, undoLabel: "", canRedo: false, redoLabel: "", depth: 0)

    /// An undo that could not bring everything back (changes another writer
    /// stacked on top were held aside). Drawn as the banner over the table;
    /// still said on stderr so a checking run can see it too.
    @Published var heldBack: UndoOutcome?
    /// **An earlier version on screen instead of now.** See `Versions.swift`:
    /// while it is set the engine shows that version, keeps and syncs today's
    /// film underneath, and refuses every edit.
    @Published var looking: VersionItem?
    /// What the other machine's work brought in, when it needs a word: the
    /// same field decided twice, independently. Ordinary catching-up is
    /// silent — being told about it would be noise.
    @Published var clashes: [Engine.Pull.Clash] = []

    /// **The frames the project has a record of and no picture for** — Ref 224,
    /// by content hash. Asked of the engine rather than guessed from a read
    /// that failed, so a photograph still coming down from iCloud is never
    /// called missing. Refreshed on open and after a merge, which are the two
    /// moments the answer can change.
    @Published var hollowFrames: Set<String> = []

    /// **Which thing the picture picker is adding to** — Ref 228. Holds the
    /// owner's id: a shot, a scene or a location, the same id `paste` takes.
    @Published var pickingPictureFor: String?
    /// **A console door into the picker's own double-click** — the one place a
    /// pop-out is opened from inside a sheet, and no check can click into a
    /// sheet or photograph one. Set to a 1-based position; the picker previews
    /// that picture and clears it.
    @Published var previewPictureAt: Int?

    /// What that thing is called, for the picker's own heading. Worked out
    /// here because the picker is opened from three different screens and none
    /// of them should have to spell it.
    func nameOfOwner(_ id: String) -> String {
        if let place = view?.locations.first(where: { $0.id == id }) {
            return place.fullName.isEmpty ? place.name : place.fullName
        }
        if let scene = view?.scenes.first(where: { $0.id == id }) {
            return "scene \(scene.number)"
        }
        if let row = view?.allRows.first(where: { $0.shot == id || $0.id == id }) {
            return row.number
        }
        return "this"
    }

    /// **Give a clip its poster back, when it has none.**
    ///
    /// A video draws as *nothing at all* without one: `Thumbs.image` asks for
    /// the poster first and falls back to the movie's own bytes, and `NSImage`
    /// cannot make a picture of an mp4. So both attempts fail and the cell is
    /// blank — which is what he found on shot 5B on 2026-08-31, for a clip that
    /// had synced perfectly.
    ///
    /// **The cause was the phone**, which stored clips without ever making a
    /// poster (fixed in `phone/Sources/Media.swift`). This is the other half:
    /// the clips already in his films, and any that arrive from a device still
    /// running an older build.
    ///
    /// **It only ever adds.** A clip that already has a poster is left exactly
    /// alone — including one he chose by hand from the viewer, which must never
    /// be overwritten by an automatic guess at the first half-second.
    ///
    /// **Except to change its format.** Posters became JPEG on 2026-09-15; a
    /// PNG one is re-encoded from its own pixels — the frame he chose stays
    /// the frame he chose — and filed under the new name, and the engine
    /// retires the old file. Every film he opens converts itself once.
    private func makeMissingPosters() {
        guard let engine, let path = projectPath else { return }
        // **Not while `--shrinkclips` is at work.** That pass retires each
        // clip's old files and re-files its poster under the new name; this
        // runs off-thread and would land a poster under the *old* name a
        // moment after the pass removed it — measured, 2026-09-15: 25 stray
        // posters, all uploaded. The pass carries every poster itself.
        if CommandLine.arguments.contains("--shrinkclips") { return }
        let proxies = path.appending(path: "media/proxies")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: proxies.path)) ?? []
        // A clip is a stem with a movie extension; its poster is the same stem
        // with `.jpg` — or `.png`, from before. All in this one folder,
        // named after the contents.
        let posters = Set(files.filter { $0.hasSuffix(".jpg") }
                               .map { String($0.dropLast(4)) })
        let olderPosters = Set(files.filter { $0.hasSuffix(".png") }
                                    .map { String($0.dropLast(4)) })
        let clips = files.filter { name in
            let ext = (name as NSString).pathExtension.lowercased()
            return ["mp4", "mov", "m4v"].contains(ext)
        }
        let orphans = clips.filter { !posters.contains(($0 as NSString).deletingPathExtension) }
        guard !orphans.isEmpty else { return }

        // Off the drawing thread: reading a frame out of a 28 MB movie is real
        // work, and this runs on every open.
        DispatchQueue.global(qos: .utility).async {
            var mended: [String] = []
            for clip in orphans {
                let stem = (clip as NSString).deletingPathExtension
                let image: NSImage?
                if olderPosters.contains(stem),
                   let held = NSImage(contentsOf: proxies.appending(path: stem + ".png")) {
                    // The frame it already had, whoever chose it.
                    image = held
                } else {
                    let url = proxies.appending(path: clip)
                    let asset = AVURLAsset(url: url)
                    let generator = AVAssetImageGenerator(asset: asset)
                    // Without this a clip shot upright comes back on its side: the
                    // rotation lives in the track's transform, not in the pixels.
                    generator.appliesPreferredTrackTransform = true
                    let seconds = CMTimeGetSeconds(asset.duration)
                    let at = CMTime(seconds: min(0.5, max(seconds - 0.1, 0)), preferredTimescale: 600)
                    image = (try? generator.copyCGImage(at: at, actualTime: nil))
                        .map { NSImage(cgImage: $0, size: .zero) }
                }
                guard let image, let made = Ingest.poster(image) else { continue }
                DispatchQueue.main.async { engine.poster(hash: stem, data: made) }
                mended.append(stem)
            }
            if !mended.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    // The tiles that drew blank are still holding their nothing
                    // — and `Thumbs` writes a frame off after one failed read,
                    // so without this they stay blank until the app restarts.
                    for stem in mended { Thumbs.shared.forget(stem) }
                    self?.objectWillChange.send()
                    FileHandle.standardError.write(Data((
                        "posters made: \(mended.count)\n").utf8))
                }
            }
        }
    }

    func readHollowFrames() {
        let gaps = engine?.gaps() ?? (hollow: [], gone: [:])
        hollowFrames = gaps.hollow
        Thumbs.shared.gone = gaps.gone
        Thumbs.shared.hollow = hollowFrames
        FileHandle.standardError.write(Data((
            "hollow frames: \(hollowFrames.count)\n").utf8))
    }

    /// Answer them, by keeping what is on screen.
    ///
    /// **His report, 2026-08-21:** the same notice on every launch, however
    /// many times he had clicked it away. This used to be `clashes = []` and
    /// nothing else — but a clash is worked out from the log each time it is
    /// asked for, so emptying this list ended nothing and the next open said
    /// the same thing off the same log. For ever, by construction.
    ///
    /// Settling changes no value on screen. It writes down that the question
    /// was answered, which is the only thing that can stop it being asked, and
    /// it is undoable like any other edit.
    func settleClashes() {
        guard let engine else { return }
        replace(engine.settle())
        clashes = engine.clashes()
    }

    /// Settle one disagreement by keeping what is on screen.
    func keepMineValue(_ clash: Engine.Pull.Clash) {
        guard let engine else { return }
        replace(engine.keepMine(record: clash.record, field: clash.field))
        clashes = engine.clashes()
    }

    /// Settle one disagreement the other way — Ref 231. Deciding is a write
    /// either way, so this is one undoable step like any other edit.
    func takeOtherValue(_ clash: Engine.Pull.Clash) {
        guard let engine else { return }
        replace(engine.takeOther(record: clash.record, field: clash.field))
        clashes = engine.clashes()
    }

    /// Watches the project's `changes` folder for another device's log.
    private var incoming: DispatchSourceFileSystemObject?
    /// The other half of noticing another device — see `watchForOtherDevices`.
    private var heartbeat: Timer?
    /// The slow beat that keeps the *list* level with the relay — see
    /// `syncListQuietly`. Separate from `heartbeat`, which only reads the disk.
    private var relayBeat: Timer?
    /// Coming back to the app is one of the three moments the list catches up.
    private var cameBack: NSObjectProtocol?
    /// **The open line**, so a change arrives rather than being waited for.
    /// Sits on top of `relayBeat`, which stays exactly as it was: push is the
    /// fast path, the poll is the one that cannot fail.
    private lazy var watch = Watch { [weak self] in self?.syncListQuietly() }
    private var incomingDir: CInt = -1
    private var pullSoon: DispatchWorkItem?

    func undo(quiet: Bool = false) {
        guard let engine else { return }
        let (outcome, updated) = engine.undo()
        replace(updated)
        refreshBoard()
        if !quiet, outcome.did, !outcome.label.isEmpty { diagram?.flash("Undo \(outcome.label)") }
        heldBack = outcome.did && (outcome.skipped ?? 0) > 0 ? outcome : nil
        if let held = heldBack {
            FileHandle.standardError.write(Data(
                "undo held back \(held.skipped ?? 0) newer changes\n".utf8))
        }
    }

    func redo() {
        guard let engine else { return }
        let (outcome, updated) = engine.redo()
        replace(updated)
        refreshBoard()
        if outcome.did, !outcome.label.isEmpty { diagram?.flash("Redo \(outcome.label)") }
        heldBack = outcome.did && (outcome.skipped ?? 0) > 0 ? outcome : nil
    }

    /// **⌘Z on the Schedule redraws the Schedule.** The board is asked for
    /// on its own (`loadBoard`) and `replace` only carries the view model, so
    /// taking back a drop put the scene back in the engine and left the strip
    /// drawn where it had been dropped until the tab was left and come back
    /// to — a board that disagreed with the film. Found 2026-09-29.
    func refreshBoard() {
        if stripBoard != nil { loadBoard() }
    }

    /// Read the engine's answer about what the columns are called and shaped
    /// like. **A reading, never a second copy of it**: it cannot drift because
    /// it cannot outlive the view it was read from.
    ///
    /// **Called from both doors.** Opening a project assigns `view` directly
    /// rather than going through `replace`, so for a while this ran on every
    /// change *except the first one* — which is exactly the case where it
    /// matters, and it showed up as every column header wearing its slug
    /// instead of its name until something else was edited.
    private func describe(_ fresh: ViewModel) {
        // **A `kind` is what makes a column the project's own**, not a label.
        // Since Ref 249 the engine sends a label for every column, built-in
        // ones included — and reading a label as "this is a custom column"
        // made all fifteen of them custom, which the battery caught within the
        // hour. `kind` is only ever sent for a column somebody made.
        var described: [String: (label: String, kind: String)] = [:]
        for column in fresh.columns {
            if let label = column.label, let kind = column.kind {
                described[column.name] = (label, kind)
            }
        }
        Columns.custom = described
        // The engine's names for everything, so this app holds no list of its
        // own to fall out of step with the phone's — Ref 249.
        Columns.named = fresh.fieldLabels
    }

    /// **Answers worked out from the view model, kept until it changes.**
    ///
    /// Not a cache of the document — a cache of *this* view model, thrown away
    /// whole the moment a new one arrives. It cannot go stale, because a thing
    /// that could change it is a thing that replaced the view model.
    ///
    /// It exists because of what a `Menu` costs. SwiftUI builds a menu's items
    /// as part of the body around it, not when it opens — so the filter bar
    /// asked the engine for every distinct value of every facetable column on
    /// every single pass, and the scene list did the same for its seven. On a
    /// two-hundred-shot film that is a dozen scans of the whole document to
    /// draw a shut menu. His report, 2026-09-04: *"it's feeling sluggish."*
    private var reckoned: [String: [String]] = [:]
    private var reckonedPairs: [String: [(value: String, label: String)]] = [:]

    func reckon(_ key: String, _ work: () -> [String]) -> [String] {
        if let already = reckoned[key] { return already }
        let made = work()
        reckoned[key] = made
        return made
    }

    func reckonPairs(_ key: String,
                     _ work: () -> [(value: String, label: String)])
        -> [(value: String, label: String)] {
        if let already = reckonedPairs[key] { return already }
        let made = work()
        reckonedPairs[key] = made
        return made
    }

    func replace(_ fresh: ViewModel?) {
        guard let fresh else { return }
        reckoned.removeAll(keepingCapacity: true)
        reckonedPairs.removeAll(keepingCapacity: true)
        view = fresh
        // What the project's own columns are called and shaped like, refreshed
        // from every view model — a reading of the engine's answer, never a
        // second copy of it: it cannot drift because it cannot outlive the
        // view it was read from.
        describe(fresh)
        // **The colours anybody has chosen for particular terms** — Ref 55.
        // Refilled here, *before* `view` is read by the repaint this assignment
        // causes, and by the same argument as `describe`: it is a reading of
        // the engine's answer and cannot outlive the view it came from.
        recolour()
        // **And the film's own colour**, which changes here for one reason: he
        // has just linked the film to a Notion project in Project Settings.
        // Cheap on every other edit — it compares two strings and stops.
        wearTheFilmsColour()
        // **A Print Frame whose bake no longer matches its spec is baked
        // again** — after the editor's change, an undo, or Claude's
        // connector. Cheap when there is nothing stale. (`PrintFrame.swift`)
        PrintFrameBaker.shared.notice(self)
        // Every change hits the disk the moment it lands. A sheet has no save
        // button, and neither does this — and until this line existed, neither
        // did anything else: **no code in Studio ever called `save()`**, so
        // every edit lived exactly as long as the process did. Found because a
        // checking run's write was gone when the next process looked. This is
        // the single funnel every mutation already passes through, which is
        // what makes it the right place: nothing can change the document
        // without passing the point where the document is kept.
        engine?.save()
        history = engine?.history() ?? history
        // **And the linked workbook follows the project** — SL-375. Same
        // argument as `save()` above: this is the one place every mutation
        // passes through, so it is the only place that can promise a file
        // outside the app stays current. Debounced, because a workbook is
        // real work to build and typing a description is a dozen changes a
        // second; the file is for whoever he hands it to, not for the next
        // keystroke.
        scheduleWorkbookRewrite()
    }

    /// A few seconds after the last change, not on every one.
    ///
    /// Each change cancels the pending rewrite and books another, so a burst
    /// of typing writes the file once when it stops rather than once per
    /// letter. Nothing is scheduled at all when no workbook is linked, which
    /// is the ordinary case.
    private func scheduleWorkbookRewrite() {
        workbookRewrite?.cancel()
        // **Never while an old version is on screen**: the workbook is built
        // from what the engine shows, and that is last Tuesday's film. His
        // linked spreadsheet would be written back a week. Returning to now
        // passes through `replace` and books the rewrite then.
        guard looking == nil else { return }
        guard Exporting.autoUpdateEnabled(for: view?.project) else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.looking == nil else { return }
            self.workbookRewrite = nil
            Exporting.refreshLinkedWorkbook(state: self)
        }
        workbookRewrite = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    // ------------------------------------------------------------ the schedule

    /// The strip board, as the engine last described it.
    ///
    /// Like `view`, this is a *reading* of the engine's answer and never a
    /// second copy of the document. Every drag goes engine-ward and the board
    /// is asked for again — the same law the table lives by.
    @Published private(set) var stripBoard: BoardModel?

    /// Refill `Brand.termInks` from the engine. Cheap — only terms somebody has
    /// actually coloured come back, and most projects will have none.
    /// **How many times the term colours have actually changed.**
    ///
    /// A chip's colour is drawn by a closure, and a closure is invisible to
    /// the comparison that lets a shot skip being drawn again. This number is
    /// visible: it goes into that comparison, so recolouring a term redraws
    /// the page and nothing else does.
    private(set) var paint = 0

    private func recolour() {
        var inks: [String: String] = [:]
        for chosen in engine?.termColours() ?? [] {
            inks[Brand.termKey(chosen.field, chosen.term)] = chosen.hex
        }
        if inks != Brand.termInks { paint += 1 }
        Brand.termInks = inks
    }

    /// Give a term a colour, or hand it back to the hash with an empty one.
    func colourTerm(field: String, value: String, hex: String) {
        engine?.colourValue(field: field, value: value, hex: hex)
        replace(engine?.view())
    }

    func loadBoard() { stripBoard = engine?.board() }

    /// **A board move changes the document, so it must go through `replace`.**
    ///
    /// The board commands hand back a board, not a view model — and `replace`
    /// is the single funnel where the project is saved. A board command that
    /// only stored the new board would draw the move on screen and lose it on
    /// quit, which is the silent-value-eater family this app has been bitten
    /// by three times. So: take the fresh board, then ask for a fresh view and
    /// put it through the funnel.
    func afterBoard(_ fresh: BoardModel?) {
        if let fresh { stripBoard = fresh }
        replace(engine?.view())
    }

    /// Dragging a whole strip onto a day. `nil` puts it back in the waiting
    /// column. Scheduling scene by scene is the ordinary gesture.
    func assign(scene: String, day: String?) {
        afterBoard(engine?.assign(scene: scene, day: day))
    }

    /// **Give a section one of the eight colours.** A section is a record
    /// like any other and its colour is a field on it — the door rename uses.
    func colourSection(_ section: ViewModel.Sequence, hex: String) {
        guard let engine else { return }
        replace(engine.set(shot: section.id, field: "colour", value: "#" + hex))
    }

    /// **A section goes; its scenes stay.** Asked with the cost said first
    /// — the one sentence a delete earns — from Settings, the sidebar and
    /// the table alike.
    func askToDeleteSection(_ section: ViewModel.Sequence) {
        guard let engine else { return }
        let held = scenes.filter { $0.sequence == section.id }.count
        let word = view?.project.sequenceWord.lowercased() ?? "section"
        let alert = NSAlert()
        alert.messageText = "Delete \(section.title)?"
        alert.informativeText = held == 0
            ? "No scenes are in this \(word)."
            : "\(held) scene\(held == 1 ? "" : "s") leave\(held == 1 ? "s" : "") the \(word) and stay\(held == 1 ? "s" : "")."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if Launch.checking || alert.runModal() == .alertFirstButtonReturn {
            replace(engine.deleteSequence(section.id))
        }
    }

    /// The scene list's drag: `from` and `to` as `List.onMove` gives them,
    /// against `scenes` (the list as drawn). Order only; a commercial's
    /// scene takes the section of the run it lands in.
    func moveScenes(_ from: IndexSet, to: Int) {
        guard let engine, let index = from.first, index < scenes.count else { return }
        let moving = scenes[index]
        var rest = scenes
        rest.remove(at: index)
        let at = min(max(to > index ? to - 1 : to, 0), rest.count)
        let after = at == 0 ? nil : rest[at - 1]
        replace(engine.moveScene(moving.id, after: after?.id))
        if view?.project.isCommercial == true {
            let neighbour = after ?? (at < rest.count ? rest[at] : nil)
            let section = neighbour?.sequence ?? ""
            if (moving.sequence ?? "") != section {
                replace(engine.set(shot: moving.id, field: "sequence", value: section))
            }
        }
    }

    /// **A scene moved within its day**, to sit before another scene there
    /// or last. His ask, 2026-09-19: easier to adjust the order inside a
    /// day. A scene not yet on the day is put on it first.
    func moveSceneInDay(_ scene: String, day: String, before: String?) {
        let on = stripBoard?.days.first { $0.id == day }?.strips.contains { $0.scene == scene } ?? false
        if !on { assign(scene: scene, day: day) }
        afterBoard(engine?.moveSceneInDay(scene, day: day, before: before))
    }

    /// One step up or down the day, by the same door.
    func nudgeSceneInDay(_ scene: String, day: String, up: Bool) {
        guard let strips = stripBoard?.days.first(where: { $0.id == day })?.strips,
              let at = strips.firstIndex(where: { $0.scene == scene }) else { return }
        if up {
            guard at > 0 else { return }
            moveSceneInDay(scene, day: day, before: strips[at - 1].scene)
        } else {
            guard at + 1 < strips.count else { return }
            let target = at + 2 < strips.count ? strips[at + 2].scene : nil
            moveSceneInDay(scene, day: day, before: target)
        }
    }

    /// Pulling one shot out of its scene onto another day, for a scene that
    /// will not finish in an afternoon.
    func assign(placement: String, day: String?) {
        afterBoard(engine?.assign(placement: placement, day: day))
    }

    /// Undoable with ⌘Z like everything else — the engine wraps it in a
    /// transaction called "Add shoot day". With a date it is a calendar click:
    /// the day arrives already dated, still one step to take back.
    func addDay(date: String? = nil) { afterBoard(engine?.addDay(date: date)) }

    /// A day's own name, its date, and taking one away. Ref 341 — all three
    /// were missing, so an *Add shoot day* pressed by accident outlived the
    /// session, and the `Fri 12 Sep` the board draws could only ever have been
    /// put there by a fixture.
    func nameDay(_ day: String, _ name: String) {
        afterBoard(engine?.nameDay(day, name))
    }
    func dateDay(_ day: String, _ date: String) {
        afterBoard(engine?.dateDay(day, date))
    }
    func removeDay(_ day: String) { afterBoard(engine?.removeDay(day)) }
    func moveDay(_ day: String, to index: Int) {
        afterBoard(engine?.moveDay(day, to: index))
    }

    /// A day band dropped on another day's band — Ref 342.
    ///
    /// **The numbers move with the positions**, because `day_label` has always
    /// been derived from position: drop Day 3 above Day 2 and the two swap
    /// numbers. That is right, and it is the reason a day can be given a name
    /// of its own — the name is the part that stays with the work.
    ///
    /// Here rather than in the view because `--putday` has to reach it. A drag
    /// is a *session*, not a click, so no synthetic mouse can perform one; the
    /// board's other drops are checked the same way, through the handler's own
    /// path, with the pixels left to the hands script.
    func moveDay(_ day: String, above other: String) {
        let days = stripBoard?.days ?? []
        guard let from = days.firstIndex(where: { $0.id == day }),
              var to = days.firstIndex(where: { $0.id == other }),
              from != to else { return }
        // Dragging downward, taking the day out shifts everything below it up
        // by one, so the index that *reads* as "above that band" is one less.
        if from < to { to -= 1 }
        moveDay(day, to: to)
    }

    /// Dated days into date order — the engine permutes them among the places
    /// dated days already hold, one undo step, and an undated day stays put.
    func sortDaysByDate() { afterBoard(engine?.sortDaysByDate()) }

    /// Whether the day numbers and the dates disagree — the condition the
    /// *Put days in date order* button appears on, and all it appears on.
    var daysOutOfDateOrder: Bool {
        let dates = (stripBoard?.days ?? []).map(\.date).filter { !$0.isEmpty }
        return zip(dates, dates.dropFirst()).contains { $0 > $1 }
    }

    /// What clicking a calendar date does — the one funnel the calendar cell
    /// and `--clickdate` share. A date already held highlights its day and
    /// never removes or duplicates; an empty date becomes a new day, numbered
    /// after the last, which is how days come out numbered in the order they
    /// were picked. The answer is a sentence for the check to read back.
    @discardableResult
    func calendarTap(_ date: String) -> String {
        if stripBoard == nil { loadBoard() }
        if let held = stripBoard?.days.first(where: { $0.date == date }) {
            highlightedDay = held.id
            return "highlighted \(held.label)"
        }
        addDay(date: date)
        guard let lane = stripBoard?.days.first(where: { $0.date == date }) else {
            return "could not add \(date)"
        }
        return "added \(lane.label) \(date)"
    }

    /// A day band dropped on a calendar date — the drop handler's own path,
    /// here so `--putdate` can reach it; the pixels stay with the hands script,
    /// the same bargain `moveDay(_:above:)` struck.
    func dropDay(_ day: String, onDate date: String) { dateDay(day, date) }

    var projectTitle: String {
        // A brand-new package has no title of its own yet. Falling back to the
        // file name beats showing an empty space where the project should be.
        if let title = view?.project.shownTitle, !title.isEmpty { return title }
        if let path = projectPath { return path.deletingPathExtension().lastPathComponent }
        return "No project"
    }

    /// The scenes, as the engine says they are. Filtering the sidebar's own
    /// search is done here rather than asked of the engine, because this search
    /// narrows *the list of scenes* — the engine's filter narrows shots, which
    /// is a different question and belongs to the table.
    /// **A way of looking at the film, never a change to it** — Ref 102.
    ///
    /// His own note on that row got this exactly right: scene order *is* script
    /// order, and one of the app's laws is that we never renumber a scene. So
    /// showing the film by shoot day or by location is not a rearrangement —
    /// it is the same film, read in a different order, the way sorting shots
    /// already works. Nothing is written down and a print is unaffected.
    ///
    /// Which is why it lives here and not in the engine: the engine holds the
    /// film's order, and this is not it. `Sort scenes by number` (Ref 260) is
    /// the other kind — it rewrites, so it is a button he presses.
    enum SceneOrder: String, CaseIterable {
        case script, day, location
        var label: String {
            switch self {
            case .script:   return "Script order"
            case .day:      return "Shoot day"
            case .location: return "Location"
            }
        }
    }
    @Published var sceneOrder: SceneOrder = .script { didSet { if sceneOrder != oldValue { fileEditPieces() } } }

    /// **How the Document view cut itself into sheets**, published by the
    /// page as it measures itself — the only place in the app that knows,
    /// because the cut depends on how tall each block came out and that is
    /// not known until it has been drawn. `--pages` reads it, which is how a
    /// check can see a page break at all.
    @Published var documentSheets: [[Slab]] = []

    /// **What the document sheet says about its own order, and what it is
    /// leaving out.** It lives here rather than in the view because the
    /// printed page says it too — carried out as `order=` on
    /// `Engine.ExportScope` — and a caption the app draws from one place and
    /// prints from another is a caption that will one day disagree with
    /// itself. It used to say SCRIPT ORDER whatever order it was in, and a
    /// sheet that names its own order wrongly is worse than one that names
    /// none, because somebody on the day believes it.
    var orderCaption: String {
        var said: String
        switch sceneOrder {
        case .script:   said = "SCRIPT ORDER"
        case .day:      said = "BY SHOOT DAY"
        case .location: said = "BY LOCATION"
        }
        // A filtered document is a part of the film, and must say so — it is
        // the difference between a short scene list and a missing one.
        let hidden = view?.filter.hiddenScenes ?? 0
        if hidden > 0 { said += " · \(hidden) SCENE\(hidden == 1 ? "" : "S") NOT SHOWN" }
        return said
    }

    /// The section a scene sits under in a commercial's list — the sequence
    /// record, or nothing for a scene in no section. The sidebar and the
    /// table both draw a head where this changes from one scene to the next.
    func sectionOf(_ scene: ViewModel.Scene) -> ViewModel.Sequence? {
        guard let id = scene.sequence, !id.isEmpty else { return nil }
        return view?.sequences.first { $0.id == id }
    }

    /// **A section is a label on a run of scenes, not a place every scene
    /// has to live.** His correction, 2026-09-14: *"i shouldnt have to have a
    /// section if i dont want one."* The first cut sorted a commercial into
    /// section order and put the sectionless at the foot under *No Section*
    /// — which is a section, forced on the scenes that had none. Now the list
    /// keeps its own order; a head is drawn where a section *starts* (this
    /// scene has one and the scene before did not, or had another), and
    /// where a section ends a quiet rule closes it. A scene in no section
    /// is simply a scene.
    func sectionHeadBefore(_ scene: ViewModel.Scene, in list: [ViewModel.Scene]) -> Bool {
        guard view?.project.isCommercial == true, sceneOrder == .script,
              let mine = scene.sequence, !mine.isEmpty,
              let at = list.firstIndex(where: { $0.id == scene.id }) else { return false }
        if at == 0 { return true }
        return (list[at - 1].sequence ?? "") != mine
    }

    /// Whether this scene is the last of its section's run — the row that
    /// rounds the panel's foot. The list's end counts, and so does the next
    /// scene being in no section or another one.
    func sectionEndsAfter(_ scene: ViewModel.Scene, in list: [ViewModel.Scene]) -> Bool {
        guard view?.project.isCommercial == true, sceneOrder == .script,
              let mine = scene.sequence, !mine.isEmpty,
              let at = list.firstIndex(where: { $0.id == scene.id }) else { return false }
        if at == list.count - 1 { return true }
        return (list[at + 1].sequence ?? "") != mine
    }

    /// Where a section just ended: this scene has none and the one before
    /// did. Drawn as a rule with no words — nothing is being named.
    func sectionEndsBefore(_ scene: ViewModel.Scene, in list: [ViewModel.Scene]) -> Bool {
        guard view?.project.isCommercial == true, sceneOrder == .script,
              (scene.sequence ?? "").isEmpty,
              let at = list.firstIndex(where: { $0.id == scene.id }), at > 0 else { return false }
        return !(list[at - 1].sequence ?? "").isEmpty
    }

    /// The film in the order it is being read in. Stable: scenes that tie on
    /// the sorting field keep script order between them, so turning the order
    /// on and off again gives back exactly the list he started with, and a
    /// scene with no day set does not wander.
    func inViewOrder(_ list: [ViewModel.Scene]) -> [ViewModel.Scene] {
        guard sceneOrder != .script else { return list }
        let key: (ViewModel.Scene) -> String = { scene in
            switch self.sceneOrder {
            case .script: return ""
            case .day: return scene.day
            case .location:
                return scene.shootingLocation.isEmpty ? scene.location
                                                      : scene.shootingLocation
            }
        }
        return list.enumerated().sorted { left, right in
            let a = key(left.element), b = key(right.element)
            // Scenes with nothing in that field go last rather than first —
            // an unset day is not "day zero", and a run of blanks at the top
            // reads as the sort having failed.
            if a.isEmpty != b.isEmpty { return b.isEmpty }
            if a != b {
                return a.localizedStandardCompare(b) == .orderedAscending
            }
            return left.offset < right.offset
        }.map(\.element)
    }

    var scenes: [ViewModel.Scene] {
        // Archived scenes sink to the foot rather than vanishing: a scene
        // hidden beyond reach has been destroyed in everything but name, and
        // the law says a person deletes things, never the app's chrome.
        // Archived scenes are *out* of the film until he goes and looks for
        // them. They used to sink to the foot of the same list, which is a
        // half-measure: still in the read-through, still in the way, and no
        // clearer for being last.
        var all = (view?.scenes ?? []).filter { $0.archived == showingArchive }
        // **A narrowed film has a narrowed scene list.** The table already
        // sets aside scenes a filter has emptied; the sidebar did not, so
        // filtering by location left one scene in the table and all four still
        // listed beside it, with "3 scenes hidden" written between them. Two
        // answers to one question, six inches apart. Same rule as the table's.
        if view?.filter.narrowed == true {
            let alive = scenesWithRows
            all = all.filter { alive.contains($0.id) }
        }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return inViewOrder(all) }
        return inViewOrder(all.filter {
            $0.heading.lowercased().contains(q) || $0.number.lowercased().contains(q)
        })
    }

    var scene: ViewModel.Scene? {
        view?.scenes.first { $0.id == sceneId } ?? view?.scenes.first
    }

    /// How many shots sit in a scene, per the engine's own grouping.
    func shotCount(_ scene: ViewModel.Scene) -> Int { scene.count }

    /// **What this machine calls itself**, for as long as it exists.
    ///
    /// Sync rests entirely on devices having different names: a clash is
    /// "we both changed this without seeing each other", which cannot be
    /// told from ordinary editing between two machines wearing one name —
    /// and a device never writes another's changes into its own log, a rule
    /// that would have swallowed the other Mac's work as ours. Every build
    /// until now said `DeviceId(1)`, so his Mac and his phone were the same
    /// device as far as the engine could tell.
    ///
    /// Made once, then remembered. A checking run is a device of its own and
    /// never writes the real one — the preference law — and `--device` lets a
    /// check *be* the second Mac, which is how sync is provable at all
    /// without a second Mac.
    static var deviceId: UInt64 {
        if let at = CommandLine.arguments.firstIndex(of: "--device"),
           at + 1 < CommandLine.arguments.count,
           let said = UInt64(CommandLine.arguments[at + 1]), said != 0 {
            return said
        }
        if Launch.checking { return 9_001 }
        let key = "deviceId"
        let held = UserDefaults.standard.object(forKey: key) as? NSNumber
        if let held, held.uint64Value != 0 { return held.uint64Value }
        // Random, not a counter: two machines that never met must not be
        // able to pick the same one, and there is nobody to hand them out.
        var made = UInt64.random(in: 2...UInt64(Int64.max))
        if made == 0 { made = 2 }
        UserDefaults.standard.set(NSNumber(value: made), forKey: key)
        return made
    }

    @discardableResult
    func open(_ path: URL) -> Bool {
        stillArriving = Projects.bringDown(path)
        guard let opened = Engine(path: path, device: Self.deviceId) else {
            let said = Engine.lastProblem()
            problem = said.isEmpty
                ? "Studio can't open \(path.lastPathComponent)"
                : said
            return false
        }
        engine = opened
        // A new film opens on now, never on a version of the last one.
        looking = nil
        startClean()
        // **The film as the day found it**, before any of today's work lands
        // on it — once a day, and only when it has changed. `Versions.swift`.
        saveDailyVersionIfDue()
        view = opened.view()
        if let view { describe(view) }
        // **Opening does not go through `replace`**, so everything `replace`
        // refreshes has to be done again here by hand. Ref 55 found this the
        // hard way: stored term colours were written, saved, and then ignored
        // for the whole session, because the cache they are read from was only
        // ever filled by an *edit*. Anything added to `replace` belongs here.
        recolour()
        // **A film nobody has styled starts from the default.** Once per film:
        // see `handOverTheDefault`.
        handOverTheDefault()
        // **And the Print Frames owed a bake**, which `replace` asks for on
        // every edit. Missing here until 2026-10-14, so a stale or missing
        // bake waited for his first edit of the session rather than baking
        // when the film opened. (`PrintFrame.swift`)
        PrintFrameBaker.shared.notice(self)
        // His dragged column widths for this project come back with it.
        Columns.loadWidths(project: view?.project.id)
        problem = view == nil ? "\(path.lastPathComponent) opened but said nothing." : nil
        projectPath = path
        // **The project's card over the film** (stage 5 step 4): from the
        // copy kept on this Mac at once, then read again from the server.
        // Before the colour is worn, so the card's colour is the one drawn.
        ProjectCards.shared.lay(on: self)
        ProjectCards.shared.refresh(self)
        // **Open, as far as every copy of this app can tell** — so no window
        // offloads the pictures out from under this one. `Offloading.swift`.
        InUse.hold(path)
        // **Before the window draws, not after.** The accent is read by nearly
        // every view there is, so a film opening in the program's blue and
        // turning red a frame later is a flash he would see every time.
        wearTheFilmsColour()
        // A checking run never writes the memory of which project HE had
        // open. A night of checks against scratch copies once left this
        // pointing at a deleted temp folder, and his morning launch fell
        // back to an empty project with no visible way out.
        if !Launch.checking {
            defaults.set(path.path, forKey: "lastProject")
        }
        if sceneId == nil || view?.scenes.contains(where: { $0.id == sceneId }) != true {
            sceneId = view?.scenes.first?.id
        }
        watchForOtherDevices(at: path)
        // **The first of the three moments.** Opening a film is when being
        // behind matters most — it is the shot list he is about to read.
        keepTheListLevel()
        if !Launch.checking { syncListQuietly() }
        // **The kit off the film's spec sheets** (Ref 1627): its lenses and
        // cameras, taken from the portal. A checking run only when it points
        // the app at a hub of its own (`-PortalURL`).
        SpecSheets.shared.refresh(self, auto: true)
        // Opening merges every log in the folder without a word, which is
        // right — merging never loses anything. But the one case worth
        // saying out loud (two machines decided the same field without
        // seeing each other) usually arrives exactly this way, while this
        // Mac was closed, and it was being swallowed.
        clashes = opened.clashes()
        readHollowFrames()
        // **A clip with no poster draws as nothing**, so mend those before he
        // sees a blank cell. Off the main thread; the tiles refresh when done.
        makeMissingPosters()
        // Always said, including none — a check that a settled disagreement
        // stays settled needs to read a zero, and a missing line is not one.
        FileHandle.standardError.write(Data((
            "clashes standing: \(clashes.count)\n").utf8))
        return view != nil
    }

    /// **A way of looking belongs to one film** — Ref 302, his report that
    /// *"filters that were on in the previous project carried over to the new
    /// project once i imported the script."*
    ///
    /// The narrowing itself lives in the engine and a fresh project has a
    /// fresh one, so nothing was truly hidden. What carried over was this
    /// side: the chips still named a time of day from the last film, so the
    /// menus said the new one was filtered when it was not. Two answers to
    /// one question is worse than either.
    ///
    /// Selections go with them. A marked set, a copied row and a cursor all
    /// hold shot ids from a film that is no longer open, and *"3 marked"* on a
    /// film he has just made is the same fault wearing different clothes.
    ///
    /// **`locationId` and `sceneId` are deliberately not here.** Those two are
    /// remembered on purpose — coming back to a project should come back to
    /// where you were — and `open` already drops `sceneId` when the scene it
    /// names is not in this film.
    private func startClean() {
        facets = [:]
        search = ""
        sceneOrder = .script
        marked = []
        pickedScenes = []
        pickedPhotos = []
        pickedPhoto = nil
        copiedShots = []
        copiedShotsText = ""
        wholeShots = []
        wholeAnchor = nil
        cellRange = nil
        copiedCells = nil
        copiedCut = false
        cursorShot = nil
        cursorColumn = "description"
        showingArchive = false
        frameSelected = nil
        mediaShown = nil
        pickingPictureFor = nil
    }

    // ------------------------------------------------- the other machine

    /// Notice the other Mac's work while this one is open.
    ///
    /// A project is a folder of append-only logs, one per device per session,
    /// and the relay drops the other machine's log in beside ours (iCloud
    /// Drive did, until 2026-09-15). Opening
    /// the project reads whatever is there — but until now **nothing ever
    /// looked again**, so a Mac left open all afternoon showed a list that
    /// had moved on hours ago. `pull()` existed in Swift and had no callers.
    ///
    /// Watched rather than polled: the folder itself says when something
    /// lands. The pull is debounced because a file arriving from the relay,
    /// or from the Drive bridge, is several writes, not one.
    private func watchForOtherDevices(at path: URL) {
        incoming?.cancel()
        incoming = nil
        if incomingDir >= 0 { close(incomingDir); incomingDir = -1 }

        let changes = path.appendingPathComponent("changes")
        let fd = Darwin.open(changes.path, O_EVTONLY)
        guard fd >= 0 else { return }
        incomingDir = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .attrib, .link],
            queue: .main)
        source.setEventHandler { [weak self] in self?.schedulePull() }
        source.setCancelHandler { [weak self] in
            guard let self, self.incomingDir >= 0 else { return }
            close(self.incomingDir)
            self.incomingDir = -1
        }
        source.resume()
        incoming = source

        // **And a slow heartbeat beside it.**
        //
        // Not because the watcher misses ordinary changes — it does not. This
        // engine writes **one new file per change**, and a new file in a
        // watched directory fires immediately (measured both ways on
        // 2026-08-22: appending to an existing file inside the folder produces
        // no event at all, creating one produces two). What the watcher cannot
        // cover is narrower and real:
        //
        // - **A project whose `changes` folder did not exist when it opened.**
        //   `open(…, O_EVTONLY)` fails, the watch is never installed, and
        //   nothing ever retries. A project nobody has written to yet is
        //   exactly that project.
        // - Any event the queue drops under load.
        //
        // Three seconds, because a pull with nothing in it is a directory read
        // and it stays silent unless something merged.
        heartbeat?.invalidate()
        let beat = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            self?.pullNow()
            // **A photograph landing is not a change** — Ref 218. The bytes of
            // a picture arrive from Drive or iCloud without anything being
            // written to a change log, so a pull sees nothing and the tile
            // that drew empty stays empty. Asking again here is what turns a
            // late photograph into a photograph rather than a blank.
            if Thumbs.shared.askAgain(from: self?.engine) { self?.objectWillChange.send() }
        }
        RunLoop.main.add(beat, forMode: .common)
        heartbeat = beat
    }

    private func schedulePull() {
        pullSoon?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.pullNow() }
        pullSoon = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Take in whatever the other device left, and refresh what is on screen.
    /// Says nothing when there is nothing — the ordinary case is silence.
    /// **What the three-second heartbeat costs the drawing thread.**
    ///
    /// `pull` reads the project's `changes` folder, and it does it on the main
    /// thread, on a timer, whether or not anything is there. That folder held
    /// eighty-four files and counting when this was written (in iCloud Drive
    /// then; a plain folder since 2026-09-15), so
    /// the cost is not ours to predict, and a reading of it belongs in the
    /// report rather than in an argument about whether it matters.
    private(set) var pulls = 0
    private(set) var pullWorstMs = 0.0
    private(set) var pullSpentMs = 0.0

    // ---- his own relay -----------------------------------------------------

    @Published var syncing = false
    /// What the last run did, in the toolbar's words. Empty until one has run.
    @Published var syncSaid = ""
    /// When it last ran, so the button's tooltip redraws when it changes.
    /// The truth lives in `SyncHistory`; this is what SwiftUI watches.
    @Published var syncedAt: Date? = SyncHistory.lastRan
    @Published var showingSyncHistory = false
    @Published var syncProblem: String?
    /// **How many photographs this Mac holds that the relay does not.**
    ///
    /// **Normally zero now.** Since 2026-09-08 the automatic sync carries the
    /// pictures too, so this stops being a standing backlog and becomes what it
    /// should always have meant: the relay could not be reached, or refused
    /// something, and these have not got there yet. See `syncListQuietly`.
    ///
    /// It is kept — rather than deleted with the rule that made it necessary —
    /// because the failure it reports is the one that used to be silent. On
    /// 2 September a board of twenty-one photographs was added, its list
    /// travelled on the five-minute beat, and the pictures did not; the film's
    /// page showed nineteen grey boxes to anybody holding the link, and nothing
    /// on this Mac said so. Sending them automatically removes the usual cause.
    /// A bad connection on set is still a cause, and still worth a number.
    @Published var picturesWaiting = 0

    /// Whether this Mac has been set up to sync at all.
    ///
    /// Reads what `Relay` already knows and never waits — see the long note in
    /// `Relay.swift`. Asking the Keychain here is what stopped the app from
    /// starting after a rebuild.
    var canSync: Bool { Relay.ready }

    /// The word arrived after the toolbar had already drawn itself without it.
    func watchForTheRelayWord() {
        NotificationCenter.default.addObserver(
            forName: Relay.learnedTheWord, object: nil, queue: .main
        ) { [weak self] _ in
            self?.syncBump &+= 1
        }
        Relay.warmUp()
    }

    /// Bumped when the relay's word is finally known, so the button redraws.
    @Published var syncBump = 0

    /// The setup sheet. **Reachable when the sync button is not**, which is the
    /// whole point of it: a Mac that has never been set up draws no sync
    /// button, so the way in cannot be the button. It is in the app menu.
    @Published var settingUpSync = false

    /// **Send what is ours, take what is theirs.** The button he asked for.
    ///
    /// His complaint, 2026-08-31: iCloud is *"inconsistent between devices and
    /// hard to make reliable, there's no way to force a manual sync or push
    /// one."* This is the answer to the last clause — a thing to press, that
    /// says what it did.
    ///
    /// **Logs, then merge, then pictures**, and the merge in the middle is
    /// `pullNow` rather than anything new: a film is a megabyte of list and a
    /// hundred megabytes of photographs, so today's shots appear straight away
    /// instead of after a whole film's worth of pictures on a bad connection.
    // ---- syncing, without being asked --------------------------------------

    /// Open — or reopen — the line to this film.
    private func watchAgain(waking: Bool) {
        guard !Launch.checking,
              let path = projectPath,
              let base = Relay.address,
              let token = Relay.token,
              let project = Relay.projectId(at: path)
        else { return }
        if waking {
            watch.wakeUp(base: base, project: project, token: token)
        } else {
            watch.start(base: base, project: project, token: token)
        }
    }

    /// **Everything travels on its own — the list and the pictures both.**
    ///
    /// His ruling, 2026-09-08, on being told why a clip he had added at two in
    /// the afternoon was still not on the web: *"Let's delete this rule. That
    /// should not be the case. It should just automatically sync. I don't have
    /// time for that."*
    ///
    /// **That reverses his decision of 2026-08-31**, which held that the list
    /// travelled by itself and the photographs waited for the button, because a
    /// film is 1.3 MB of list against 126 MB of media. The measurement was
    /// right and the conclusion is no longer his: a clip sitting unsent all
    /// afternoon costs him more than the bytes do. **Do not put the split
    /// back** — see the decision in Notion. If the data ever needs answering,
    /// answer it with something he does not have to press.
    ///
    /// **The order is still load-bearing: logs → merge → media.** That has
    /// nothing to do with the rule that went; it is why today's shots appear
    /// straight away instead of behind a whole film's worth of photographs on a
    /// bad connection.
    ///
    /// **The media send is caught separately**, so a picture that will not go
    /// up does not throw away a list that already arrived — and the badge is
    /// recounted in that case, because then there really is something waiting.
    ///
    /// **Silent both ways, and that is deliberate.** Nothing is said when it
    /// works, because changes arriving is the system working rather than news.
    /// Nothing is said when it fails either — a relay that cannot be reached on
    /// set is the ordinary condition of being on set, and a banner about it
    /// every five minutes is an app crying wolf. The button still reports both,
    /// because he pressed it and is owed an answer. The one exception announces
    /// itself: `pullNow` still raises a real disagreement.
    ///
    /// **The guard about checking runs is deliberately not in here.** This does
    /// what its name says; *whether it should happen on its own* is a policy,
    /// and policy lives at the call sites in `keepTheListLevel`. Putting it
    /// here made the whole feature untestable — every door that opens a film is
    /// a checking flag, so no run that could reach this was ever allowed to.
    func syncListQuietly() {
        guard let engine, let path = projectPath, !syncing, canSync else { return }
        syncing = true
        Task { @MainActor in
            defer { syncing = false }
            // **The list and the pictures are two transfers, not one.**
            //
            // `syncLogs` already holds that one file which will not move must
            // not stop the rest — it sends everything it can and *then* raises
            // the refusal. That rule stopped at its own edge: the throw landed
            // here and ended the run before a single picture was offered.
            //
            // Measured on his own Mac, 2026-09-08. One log the relay would not
            // take had been failing since the afternoon, and behind it sat the
            // clip he was asking about. Pressing the button would not have sent
            // it either. So the two halves are caught apart, and a list that
            // cannot move no longer holds the pictures hostage.
            var logs = Relay.Report()
            var merged = 0
            var trouble: String?
            do {
                logs = try await Relay.syncLogs(engine: engine, path: path)
                if logs.receivedLogs > 0, let pull = pullNow() { merged = pull.merged }
            } catch RelayCarrier.Trouble.gone(let fate) {
                // Archived or deleted elsewhere: the same happens here, and
                // the pictures are not asked about — they would be refused
                // the same way.
                syncSaid = follow(fate ?? .archived, for: path)
                return
            } catch {
                trouble = error.localizedDescription
            }

            var media = Relay.Report()
            do {
                media = try await Relay.syncMedia(engine: engine, path: path)
                // A picture arriving changes nothing the engine knows, so
                // nothing is re-merged — but the screen is still drawing grey
                // where those files now are.
                if media.receivedMedia > 0 { view = engine.view() }
                picturesWaiting = 0
            } catch {
                // The count is the true thing to show now: it is a real backlog.
                picturesWaiting = (try? await Relay.picturesWaiting(engine: engine, path: path)) ?? picturesWaiting
                if trouble == nil { trouble = error.localizedDescription }
            }

            let said = Relay.Report(
                sentLogs: logs.sentLogs, receivedLogs: logs.receivedLogs,
                sentMedia: media.sentMedia, receivedMedia: media.receivedMedia,
                merged: merged, clashes: logs.clashes
            )
            if let trouble {
                // Still silent on screen — a relay you cannot reach on set is
                // the ordinary condition of being on set. But it goes in the
                // history, which is the one place it is worth finding later.
                SyncHistory.failed(trouble, byHand: false)
            } else {
                // **The time is recorded even when nothing moved.** That is the
                // honest answer to "am I up to date"; the history stays quiet.
                //
                // **Through `Report.said`, the same sentence the button
                // writes.** It used to say "Up to date" or a merge count, which
                // was true when this only fetched a list — now that it carries
                // pictures too, that would file "Up to date" after shipping a
                // clip, and the history is the one place a sync is findable
                // later.
                SyncHistory.finished(said: said.said, moved: !said.isEmpty, byHand: false)
                syncedAt = SyncHistory.lastRan
            }
            if merged > 0 {
                // The toolbar's own line, so the last thing that happened is
                // readable without pressing anything. Not a banner.
                syncSaid = "\(merged) in"
            }
        }
    }

    /// The three moments the list catches up, set going when a film opens.
    ///
    /// **Never during a checking run** — a 170-check battery that reached his
    /// relay would be slow, would need the network, and would put its scratch
    /// films on it. `--autolist` is the way to exercise the transfer itself.
    private func keepTheListLevel() {
        guard !Launch.checking else { return }
        relayBeat?.invalidate()
        // Five minutes. The list is a megabyte and the check that finds nothing
        // is two small requests, so this is cheap — but it is a *network* beat
        // next to a three-second disk one, and confusing the two would put his
        // relay under a request every three seconds.
        let beat = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            self?.syncListQuietly()
            // The spec sheets ride the same five minutes (Ref 1627), and so
            // do the project cards (stage 5 step 4).
            MainActor.assumeIsolated {
                if let self {
                    SpecSheets.shared.refresh(self, auto: true)
                    ProjectCards.shared.refresh(self)
                }
            }
        }
        RunLoop.main.add(beat, forMode: .common)
        relayBeat = beat

        if let already = cameBack { NotificationCenter.default.removeObserver(already) }
        cameBack = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncListQuietly()
                // A socket that died while the Mac slept often does not say so,
                // so the line is thrown away and remade rather than trusted.
                self?.watchAgain(waking: true)
            }
        }
        watchAgain(waking: false)
    }

    func syncNow() {
        guard let engine, let path = projectPath, !syncing else { return }
        guard canSync else {
            syncProblem = "Sync isn't set up"
            return
        }
        syncing = true
        syncProblem = nil

        Task { @MainActor in
            defer { syncing = false }
            // **Caught apart, for the reason written out in `syncListQuietly`:**
            // a log the relay refuses must not hold back the pictures. This is
            // the path that proved it — the button would not have sent his clip
            // either, because the refusal threw before the media was offered.
            var logs = Relay.Report()
            var merged = 0
            var trouble: String?
            do {
                logs = try await Relay.syncLogs(engine: engine, path: path)
                // The existing merge, so a disagreement is announced the way it
                // always was and the screen refreshes the way it always did.
                if logs.receivedLogs > 0, let pull = pullNow() { merged = pull.merged }
            } catch RelayCarrier.Trouble.gone(let fate) {
                syncSaid = follow(fate ?? .archived, for: path)
                return
            } catch {
                trouble = error.localizedDescription
            }

            var media = Relay.Report()
            do {
                media = try await Relay.syncMedia(engine: engine, path: path)
                // A picture arriving changes nothing the engine knows, so
                // nothing is re-merged — but the screen is still drawing grey
                // where those files now are.
                if media.receivedMedia > 0 { view = engine.view() }
                // Everything that was waiting has just gone up.
                picturesWaiting = 0
            } catch {
                picturesWaiting = (try? await Relay.picturesWaiting(engine: engine, path: path)) ?? picturesWaiting
                if trouble == nil { trouble = error.localizedDescription }
            }

            let said = Relay.Report(
                sentLogs: logs.sentLogs, receivedLogs: logs.receivedLogs,
                sentMedia: media.sentMedia, receivedMedia: media.receivedMedia,
                merged: merged, clashes: logs.clashes
            )
            syncSaid = said.said
            // **What moved is said even when something else refused to.** He
            // pressed it and is owed both halves of the answer.
            if !said.isEmpty {
                SyncHistory.finished(said: said.said, moved: true, byHand: true)
                syncedAt = SyncHistory.lastRan
                // Silence when nothing happened. Changes arriving is the system
                // working; only a disagreement is an exception, and `pullNow`
                // has already said so if there was one.
                say("Synced")
            }
            if let trouble {
                syncProblem = trouble
                SyncHistory.failed(trouble, byHand: true)
            } else if said.isEmpty {
                SyncHistory.finished(said: said.said, moved: false, byHand: true)
                syncedAt = SyncHistory.lastRan
            }
        }
    }

    /// **The word that gets his phone in, onto the clipboard.**
    ///
    /// Universal Clipboard carries it to the phone on its own, which is why
    /// this is a copy rather than something to read out. It is never shown on
    /// screen — a password drawn in a window is a password in a screenshot.
    func copyRelayToken() {
        guard let word = Relay.token else {
            syncProblem = "There is no password on this Mac yet. Double-click Set Up Sync."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(word, forType: .string)
        say("Password copied")
    }

    func copyRelayAddress() {
        guard let where_ = Relay.address else {
            syncProblem = "There is no relay on this Mac yet. Double-click Set Up Sync."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(where_, forType: .string)
        say("Address copied")
    }

    @discardableResult
    func pullNow() -> Engine.Pull? {
        guard let engine else { return nil }
        let began = DispatchTime.now().uptimeNanoseconds
        let answer = engine.pull()
        let ms = Double(DispatchTime.now().uptimeNanoseconds &- began) / 1_000_000
        pulls += 1
        pullSpentMs += ms
        pullWorstMs = max(pullWorstMs, ms)
        guard let pull = answer, pull.merged > 0 else { return nil }
        // **Let go of the pictures the project no longer has.**
        //
        // Thumbnails are cached by content hash and kept for the life of the
        // process, which is right while the bytes exist: the same hash is
        // always the same picture. It stops being right when *another program*
        // changes the project underneath — the Drive bridge detaching a
        // photograph, or its proxy going with a prune. The picture then lives
        // on in this app's memory and nowhere else, so the Mac goes on showing
        // photographs the project no longer has while the phone shows none.
        //
        // Which is what he reported on 2026-08-22: *"it deleted all the
        // originals and proxy media, but the photos are still present on the
        // macOS app."* The app was not wrong about the engine; it was drawing
        // from its own memory.
        //
        // **Emptying the whole cache was the first fix and it was too blunt.**
        // The bridge runs every fifteen seconds; a location carrying a dozen
        // photographs re-read and re-decoded all of them on every merge, which
        // he felt straight away. Only what has actually gone is let go.
        let fresh = engine.view()
        Thumbs.shared.keep(only: Self.everyPicture(in: fresh))
        Clips.keep(only: Self.everyPicture(in: fresh))
        replace(fresh)
        // A merge is how a picture that was hollow stops being hollow — the
        // bytes arrive from the other device with the change that mentions
        // them — so the question is asked again rather than answered once.
        readHollowFrames()
        if pull.needsAttention {
            clashes = pull.clashes
        }
        say(pull.merged == 1
            ? "1 change arrived from another device"
            : "\(pull.merged) changes arrived from another device")
        FileHandle.standardError.write(Data((
            "pulled \(pull.merged) change(s) from \(pull.devices) device(s), "
            + "clashes: \(pull.clashes.count)\n").utf8))
        return pull
    }

    /// Every picture the project still refers to, by content hash — a shot's
    /// frames, a scene's attachments, a location's photographs.
    private static func everyPicture(in view: ViewModel?) -> Set<String> {
        guard let view else { return [] }
        var alive: Set<String> = []
        for row in view.allRows {
            if let frame = row.frame { alive.insert(frame.hash) }
            for still in row.stills { alive.insert(still.hash) }
        }
        for scene in view.scenes {
            for file in scene.attachments { alive.insert(file.hash) }
        }
        for place in view.locations {
            for file in place.media { alive.insert(file.hash) }
        }
        return alive
    }

    /// Reopens whatever was last open, or makes a first project so the app never
    /// starts on nothing.
    /// **The package follows the title — while the project is still new.**
    ///
    /// The project browser and the Finder both list the *file's* name, so a film
    /// called *Call Her Back* living in `Untitled.shotlist` is named on exactly
    /// one screen: the one you were standing on when you named it.
    ///
    /// Only while it is empty, and only inside the projects folder. Renaming a
    /// package another Mac or the Drive bridge is already watching would look to
    /// them like the old one vanished and a different one appeared, and that is
    /// not a thing to do for tidiness.
    func renameFileToTitle() {
        guard let path = projectPath, let engine,
              let named = view?.project.title else { return }
        guard view?.scenes.isEmpty ?? true else { return }
        let wanted = Projects.safeName(named)
        guard !wanted.isEmpty,
              wanted != path.deletingPathExtension().lastPathComponent else { return }
        engine.save()
        // **Renamed where it stands**, never moved. A project opened from
        // somewhere else — an old one in Documents, a copy somebody sent — is
        // somebody's file in somebody's folder, and tidying it into the
        // projects folder is not a thing to do while nobody is looking.
        let parent = path.deletingLastPathComponent()
        let free = Projects.freeName(startingAt: wanted, in: parent)
        let to = parent.appendingPathComponent(free)
            .appendingPathExtension(Projects.packageExtension)
        do {
            try FileManager.default.moveItem(at: path, to: to)
        } catch {
            return
        }
        _ = open(to)
    }

    /// **Letting go of a film before its folder moves.**
    ///
    /// Archiving and deleting both move or trash a folder the engine may have
    /// open, and pulling the floor out from under a running engine is a real
    /// fault rather than a theoretical one. The Projects screen used to dodge
    /// it by hiding the whole menu on the open film, which cost him every safe
    /// verb in order to protect two — his report, 2026-09-04: *"in the project
    /// that I have open, I can't select the contextual menu to archive, delete,
    /// or export a copy. I have to select another project first, then go back
    /// and touch it."*
    ///
    /// So: open something else first. The most recently edited other film, or —
    /// if this was the only one — a fresh empty one, which is exactly what a
    /// launch with no films at all already does just below. Nothing new is
    /// invented for him to be surprised by.
    ///
    /// **It lives here rather than on the Projects screen so a check can reach
    /// it.** The screen is a sheet and cannot be driven by the harness; the
    /// button and `--filmarchive` now call the same function, which is the only
    /// thing that makes checking the flag worth anything.
    ///
    /// Says whether the film is now safe to move. False means the app could not
    /// let go, and nothing should touch that folder.
    // ---- what was done elsewhere, done here -----------------------------------
    //
    // His ruling 2026-09-16: *"when one is archived on one, it's archived on
    // the others … I don't need to do things twice on either device."* The
    // relay keeps a film's fate beside the films; this Mac reads it at every
    // sync and every look at the Projects window and does the same to its own
    // copy. The phone's `Projects.follow` is the twin of this and must stay
    // the same shape.

    /// One film, one fate, followed. Says what it did.
    @discardableResult
    func follow(_ fate: RelayCarrier.Fate, for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        guard letGoOf(url) else { return "Couldn't archive \(name)" }
        do {
            switch fate {
            case .archived:
                _ = try Archive.put(url)
                return "Archived \(name)"
            case .deleted:
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                return "Deleted \(name)"
            }
        } catch {
            return error.localizedDescription
        }
    }

    /// Given the relay's listing: a film here the relay says was archived goes
    /// to the bin, one it says was deleted goes to the Trash, and a film in
    /// the bin the relay holds again comes back out.
    @discardableResult
    func follow(listing: [Relay.Film]) async -> [String] {
        var said: [String] = []
        let held = Set(listing.filter { $0.gone == nil && $0.logs > 0 }.map(\.project))
        let fates = Dictionary(uniqueKeysWithValues: listing.compactMap { film in
            film.gone.map { (film.project, $0) }
        })
        for url in Projects.all() {
            guard Relay.wasOnTheRelay(at: url), let id = Relay.projectId(at: url) else { continue }
            // The relay's note first. A film the listing does not mention at
            // all — taken off before the relay kept notes — is asked about
            // one film at a time, against its own relay, never the listing's
            // silence: silence from a wiped or wrong relay would bin every
            // film on the device.
            var fate = fates[id]
            if fate == nil, !held.contains(id) { fate = await Relay.fate(at: url) }
            guard let fate else { continue }
            said.append(follow(fate, for: url))
        }
        for url in Archive.all() {
            guard let id = Relay.projectId(at: url), held.contains(id) else { continue }
            do {
                let back = try Archive.back(url)
                Relay.allowResend(at: back)
                said.append("Put back \(back.deletingPathExtension().lastPathComponent)")
            } catch {
                said.append(error.localizedDescription)
            }
        }
        return said
    }

    @discardableResult
    func letGoOf(_ url: URL) -> Bool {
        guard projectPath == url else { return true }
        if let other = Projects.all().first(where: { $0 != url && !ProjectCards.shared.closed(at: $0) }), open(other) { return true }
        return open(Projects.url(named: Projects.freeName(startingAt: "Untitled")))
    }

    /// **New Project.** With the server's one-ID switch on, the card is made
    /// on the server and the Studio side fetched under its ID (`NewCard.swift`);
    /// otherwise an untitled film here and the old sheet, as before.
    func newProject() {
        Task { @MainActor in
            if await CardDoor.on() {
                makingCard = true
            } else if open(Projects.url(named: Projects.freeName(startingAt: "Untitled"))) {
                settingUp = true
            }
        }
    }

    func openLastOrMakeOne() {
        if let remembered = defaults.string(forKey: "lastProject"),
           FileManager.default.fileExists(atPath: remembered),
           !ProjectCards.shared.closed(at: URL(fileURLWithPath: remembered)),
           open(URL(fileURLWithPath: remembered)) {
            return
        }
        if let newest = Projects.all().first(where: { !ProjectCards.shared.closed(at: $0) }), open(newest) { return }
        if open(Projects.url(named: Projects.freeName(startingAt: "Untitled"))),
           !Launch.checking {
            settingUp = true
        }
    }

    /// The sidebar's width and whether it is showing. Kept here rather than
    /// left to `NavigationSplitView` because the split is drawn by hand — see
    /// `Shell` for why.
    @Published var sidebarWidth: CGFloat {
        // Not written to disk mid-drag. A drag produces a width per frame, and
        // persisting each one meant hundreds of synchronous `UserDefaults`
        // writes inside the gesture — work in the exact place that has to stay
        // smooth. The final width is written when the hand lets go.
        didSet { if dragAnchor == nil { persistSidebarWidth() } }
    }

    func persistSidebarWidth() {
        defaults.set(Double(sidebarWidth), forKey: "sidebarWidth")
    }
    /// The Diagram's Present: every control hidden, the window the plan's.
    @Published var diagramPresenting = false
    /// The Diagram on screen, while it is — so the sidebar can carry its
    /// Layers and Shots as tabs beside the scene list (design/24, 2026-09-28).
    @Published var diagram: DiagramModel?
    @Published var sidebarShown: Bool {
        didSet { defaults.set(sidebarShown, forKey: "sidebarShown") }
    }
    /// **The sidebar folds while he draws** (Back to Paper, design/32 item
    /// 9): a drawing tool picked in the Diagram tucks it away, and it comes
    /// back with its button. The Diagram's alone; every other mode keeps it.
    @Published var diagramFolded = false

    /// How narrow the sidebar may go, measured rather than guessed.
    ///
    /// The floor is the width at which "Reference Boards" would wrap to two lines in
    /// the section switcher, because that is the moment the sidebar stops
    /// looking like a sidebar. The switcher lays three equal columns inside 8pt
    /// of padding either side, so the answer is the widest label times three
    /// plus that padding — asked of the font at run time, so changing a label
    /// or a type size moves the stop with it instead of leaving a stale number.
    /// **No narrower than it is, and wider if he wants it.** His words. The
    /// floor used to be whatever three tab labels needed — around two hundred
    /// points — which let the scene list be squeezed until headings truncated
    /// to nothing useful. There is no reason to allow that: the width it opens
    /// at is the width it works at, so that is the floor now, and the ceiling
    /// went up because a long slugline is a long slugline.
    static let sidebarRange: ClosedRange<CGFloat> = Brand.sidebarWidth...620

    /// The same bargain on the right: never below what it opens at, and room
    /// to grow for a script page that wants it.
    static let panelRange: ClosedRange<CGFloat> = 320...760

    /// Where the sidebar was when the current divider drag began.
    ///
    /// It lives on this object rather than in a SwiftUI `@State` because it has
    /// to be read and written *within* one gesture update. A `@State` write is
    /// not visible until the next render, so when several drag events land in
    /// one frame they all still read `nil`, each takes the already-moved width
    /// as its anchor and adds the whole translation again — and the sidebar
    /// races away from the pointer. That was the buggy resize.
    var dragAnchor: CGFloat?

    /// How many gesture updates the divider has seen. Only a checking aid: it
    /// is what tells a drag that computed the wrong width apart from a drag
    /// that never reached the gesture at all, and those two want opposite fixes.
    var dragUpdates = 0

    /// Every width the divider passed through during the current drag.
    ///
    /// Also only a checking aid, and it is the one that can see a flutter: a
    /// drag whose waypoints only move one way must produce widths that only
    /// move one way. A handful of coarse waypoints can start and finish in
    /// exactly the right place while oscillating the whole way between, which
    /// is what a hand feels and what the first harness could not.
    var widthTrace: [CGFloat] = []

    /// His preferences. **A checking run reads them and writes none** — the
    /// law is enforced here rather than at each call site, because it was
    /// broken three times by forgetting one: `lastProject` opened his morning
    /// on an empty world, `columnWidths` shared a store with his real
    /// Daybreak, and `tab` left him — and the whole battery — on the
    /// storyboard. Every write in the app goes through this.
    let defaults = Remembering()

    // ------------------------------------------------ the page every film starts from

    /// **The page style a new film gets.** His ask, 2026-09-04: *"the
    /// formatting settings I've set right now … to be the default from here on
    /// out for all projects. also allow me to set new defaults per project."*
    ///
    /// Two levels, and the film always wins. This is the one every film starts
    /// from; the moment he sets anything on a particular film, that film keeps
    /// its own and this stops reaching it.
    ///
    /// Stored as **the engine's own shorthand**, which the app never reads
    /// inside — see `ViewModel.Project.docStyleSaid`.
    ///
    /// A checking run keys it separately, for the reason four other keys
    /// already do: the fixtures carry his real project ids and his real
    /// settings, and a battery that read this would draw his page instead of
    /// the standard one.
    static var pageDefaultKey: String {
        Launch.checking ? "docstyle.default.checking" : "docstyle.default"
    }
    static var pageSeededKey: String {
        Launch.checking ? "docstyle.seeded.checking" : "docstyle.seeded"
    }

    @Published var pageDefault: String =
        Remembering().string(forKey: ShellState.pageDefaultKey) ?? "" {
        didSet { Remembering().set(pageDefault, forKey: ShellState.pageDefaultKey) }
    }

    /// **Which films have already been handed the default.** Once each, so
    /// setting a film back to the standard is not undone the next morning.
    private var seeded: Set<String> {
        get {
            Set(Remembering().object(forKey: ShellState.pageSeededKey) as? [String] ?? [])
        }
        set {
            Remembering().set(Array(newValue).sorted(), forKey: ShellState.pageSeededKey)
            seededHere = newValue
        }
    }
    /// The same list, in memory — a checking run cannot write, and without
    /// this it would seed the same film on every pass of a single launch.
    private var seededHere: Set<String> = []

    /// Give a film the default, if it has never been set and never been given
    /// one. Called when a project opens.
    func handOverTheDefault() {
        guard !pageDefault.isEmpty,
              let project = view?.project,
              project.docStyleSaid.isEmpty else { return }
        let already = seeded.union(seededHere)
        guard !already.contains(project.id) else { return }
        // **Only counted as handed over if it landed.** A read-only film — one
        // a newer Shotlister wrote — refuses the change, and marking it done
        // would mean it never got the default even once it could take one.
        guard let after = engine?.applyDocStyle(pageDefault) else { return }
        seeded = already.union([project.id])
        replace(after)
    }

    /// **This film's page, from here on, for every film that has none.**
    func savePageDefault() {
        pageDefault = view?.project.docStyleSaid ?? ""
    }

    func clearPageDefault() { pageDefault = "" }

    /// Put this film back to the default — or, when none is saved, to the
    /// standard the page has always been.
    func usePageDefault() {
        replace(pageDefault.isEmpty
                ? engine?.resetDocStyle()
                : engine?.applyDocStyle(pageDefault))
    }

    /// One field of a scene, written where it is read. (`write` is POSIX
    /// write(2) at file scope — hence the longer name.) On the state rather
    /// than on a view because the scene's facts are edited **in the table's
    /// own band** now, not in a heading above it.
    func writeScene(_ scene: ViewModel.Scene, _ field: String, _ value: String) {
        guard let engine else { return }
        let next = value.trimmingCharacters(in: .whitespaces)
        let held: String
        switch field {
        case "description": held = scene.description
        case "location": held = scene.location
        case "time_of_day": held = scene.timeOfDay
        case "tags": held = scene.tags
        default: held = ""
        }
        guard next != held else { return }
        replace(engine.set(shot: scene.id, field: field, value: next))
    }

    /// The sequence a scene belongs to, if it has been put in one.
    func sequenceOf(_ scene: ViewModel.Scene) -> ViewModel.Sequence? {
        guard let id = scene.sequence else { return nil }
        return view?.sequences.first { $0.id == id }
    }

    /// The panel's own memory, restored at startup with everything else.
    ///
    /// **Except under a checking run**, where it starts closed unless
    /// `--panel` asks for it. Found 2026-08-20: the panel takes three hundred
    /// points off the width of the table, so two checks that click a cell on
    /// the right-hand side passed or failed depending on whether *he* had the
    /// panel out when the battery ran. A check whose result depends on his
    /// preferences is not a check. The same reasoning already keeps the
    /// battery's column widths under their own key.
    func restorePanel() {
        guard !Launch.checking else {
            panelShown = CommandLine.arguments.contains("--panel")
            if let section = defaults.string(forKey: "panelSection"),
               let held = PanelSection(rawValue: section) {
                panel = held
            }
            return
        }
        panelShown = defaults.bool(forKey: "panelShown")
        let width = defaults.double(forKey: "panelWidth")
        if width > 0 {
            panelWidth = min(Self.panelRange.upperBound,
                             max(Self.panelRange.lowerBound, CGFloat(width)))
        }
        if let section = defaults.string(forKey: "panelSection"),
           let held = PanelSection(rawValue: section) {
            panel = held
        }
    }

    /// **The project's modes laid on.** If the mode standing open went off
    /// — turned off on the console, the phone or another Mac — move to the
    /// next one that is on, with a note; at open, quietly.
    func applyModes(_ modes: [SideTab]?, fromElsewhere: Bool) {
        let shown = modes ?? SideTab.allCases
        modesFollowCard = modes != nil
        if Launch.checking {
            FileHandle.standardError.write(Data("modes laid: \(shown.map(\.rawValue).joined(separator: ",")) standing \(sideTab.rawValue)\(fromElsewhere ? " (read again)" : "")\n".utf8))
        }
        guard shown != modesShown else { return }
        let was = sideTab
        modesShown = shown
        guard !shown.isEmpty, !shown.contains(was) else { return }
        let all = SideTab.allCases
        let from = all.firstIndex(of: was) ?? 0
        let next = (1...all.count).lazy.map { all[(from + $0) % all.count] }.first { shown.contains($0) } ?? shown[0]
        sideTab = next
        if fromElsewhere { note("\(was.title) was turned off.") }
    }

    func note(_ line: String) {
        modeNote = line
        if Launch.checking { FileHandle.standardError.write(Data("mode note: \(line)\n".utf8)) }
        let said = line
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if self?.modeNote == said { self?.modeNote = nil }
        }
    }

    /// **Fetching the draft waiting in Drive** (step 4 piece C).
    @Published var fetchingDraft = false

    /// **New draft in Drive → Review…** The PDF comes down through the
    /// server and opens in the import's own review (scenes, what changed
    /// against the shot list, cast). Nothing changes until he imports it.
    func reviewDriveDraft() {
        guard !fetchingDraft, let path = projectPath else { return }
        let relay = Relay.projectId(at: path)
        guard let found = ProjectCards.shared.draftInDrive(film: relay, page: view?.project.consolePage ?? "") else { return }
        review(found.waiting, card: found.card)
    }

    /// **Pick the current draft** (his rule, 2026-10-15): `current-draft/`
    /// holds more than one, and the server never guesses. The draft already
    /// in use: the others move to `z-archive/`, nothing to import. Another:
    /// its review, as for a new draft; importing it settles the folder.
    func pickDriveDraft(_ choice: ProjectCards.ScriptCard.Waiting) {
        guard !fetchingDraft, let path = projectPath else { return }
        let relay = Relay.projectId(at: path)
        guard let found = ProjectCards.shared.draftChoices(film: relay, page: view?.project.consolePage ?? ""),
              found.choices.contains(choice) else { return }
        if Launch.checking {
            FileHandle.standardError.write(Data("pick draft: \(choice.label)\(choice.same == true ? " (in use)" : "")\n".utf8))
        }
        guard choice.same == true else { return review(choice, card: found.card) }
        // The film's newest draft names it; none kept here, the server's word stands.
        let stem = engine?.revisions().first(where: \.latest).map({ String($0.hash.prefix(32)) }) ?? ""
        let state = self
        Task { @MainActor in
            let waiting = ScriptPending.Waiting(kind: "settle", file: choice.file, stem: stem)
            if await ScriptPending.retry(waiting, card: found.card, state: state) == nil {
                state.note("Couldn't update Drive. Trying again later.")
            }
        }
    }

    private func review(_ waiting: ProjectCards.ScriptCard.Waiting, card: ProjectCards.Card) {
        let found = (card: card, waiting: waiting)
        let using = found.card.script?.label ?? ""
        fetchingDraft = true
        Task { @MainActor in
            defer { fetchingDraft = false }
            guard let url = await ProjectCards.fetchDraft(project: found.card.id, waiting: found.waiting) else {
                note("Couldn't get the draft from Drive.")
                return
            }
            let opening = Launch.checking ? (CommandLine.arguments.firstIndex(of: "--scriptdo").flatMap {
                $0 + 1 < CommandLine.arguments.count ? CommandLine.arguments[$0 + 1] : nil } ?? "") : ""
            importingScript = ScriptFile(url: url, opening: opening,
                                         drive: DriveDraft(project: found.card.id, file: found.waiting.file,
                                                           label: found.waiting.label, using: using))
        }
    }

    /// **Turn a mode on or off** for this film's project, through the server.
    /// On, it opens; off, the bar moves on. `both`: Shot List with Schedule.
    func setMode(_ tab: SideTab, on: Bool, both: Bool = false) {
        guard !modeBusy else { return }
        let relay = projectPath.flatMap { Relay.projectId(at: $0) }
        let page = view?.project.consolePage ?? ""
        modeBusy = true
        Task { @MainActor in
            defer { modeBusy = false }
            let got = await ProjectCards.shared.setMode(tab, on: on, both: both, film: relay, page: page)
            guard let modes = got.modes else {
                note(got.why ?? "Not changed.")
                return
            }
            applyModes(modes, fromElsewhere: false)
            if on, modes.contains(tab) { sideTab = tab }
            if Launch.checking {
                FileHandle.standardError.write(Data("modes: \(modes.map(\.rawValue).joined(separator: ","))\n".utf8))
            }
        }
    }

    init() {
        // Ask the Keychain for the relay's word now, on its own thread, so the
        // toolbar never has to wait for it while drawing. See `Relay.swift`.
        defer { watchForTheRelayWord() }
        sideTab = SideTab(rawValue: defaults.string(forKey: "place") ?? "") ?? .scenes
        tab = SceneTab(rawValue: defaults.string(forKey: "tab") ?? "") ?? .shots
        sceneId = defaults.string(forKey: "sceneId")
        diagramPlan = defaults.string(forKey: "diagramPlan")
        locationId = defaults.string(forKey: "locationId")
        // Clamped rather than discarded: a width stored under an older floor is
        // still the width he chose, and snapping it back to the default would
        // throw that away every launch.
        let stored = CGFloat(defaults.double(forKey: "sidebarWidth"))
        sidebarWidth = stored > 0
            ? min(Self.sidebarRange.upperBound, max(Self.sidebarRange.lowerBound, stored))
            : Brand.sidebarWidth
        sidebarShown = defaults.object(forKey: "sidebarShown") as? Bool ?? true
    }

}

// ------------------------------------------------------------------- window

/// The window: sidebar, a divider you can drag, content.
///
/// The split is drawn by hand rather than with `NavigationSplitView`, and the
/// reason is worth keeping. The system's sidebar column is a *material* — a
/// backdrop the compositor fills in — which means two things this project can't
/// have. It picks its own colours in dark mode, where the trajectory says dark
/// is a designed twin; and it renders as blank white into every kind of
/// offscreen bitmap, which is how this app photographs itself for checking. An
/// app that cannot be looked at cannot be verified, and verification is a law
/// here. Fifteen lines of drag gesture is a cheap price for both.
struct Shell: View {
    /// Lent to `SettingsDoor`, so code can open Settings (⌘,).
    @Environment(\.openSettings) private var openSettings
    /// **Pulled out of the `.sheet` call on purpose.** Written inline, this
    /// binding put the surrounding view body past the type-checker's budget
    /// and the whole file stopped compiling with a message that names no
    /// cause. A named property costs nothing and the error cannot come back.
    private var boardBeingRenamed: Binding<ViewModel.MoodBoard?> {
        Binding(
            get: {
                let boards = state.view?.boards ?? []
                return boards.first { $0.id == state.renamingBoard }
            },
            set: { state.renamingBoard = $0?.id }
        )
    }

    @ObservedObject var state: ShellState
    @Environment(\.colorScheme) private var scheme
    /// **The film's card, under its name** — his call, 2026-10-05: the facts
    /// and the other films in one drop-down. See `NameCard`.
    @State private var nameCard = Launch.checking && CommandLine.arguments.contains("--projectcard")
    /// The mode he asked to turn off, waiting on his confirmation.
    @State private var turningOff: SideTab?
    // (cursor is handled by an AppKit cursor rect; no state needed)
    private var dark: Bool { scheme == .dark }

    /// **Whether there is a sidebar at all right now**, which is not the same
    /// question as whether he has it switched on. Schedule draws its own two
    /// columns — everything not on a day yet, and then the days — and takes the
    /// window. A third list beside those two is not a sidebar, it is clutter,
    /// so on that mode there is none and the button that would toggle it is not
    /// drawn either. Same rule the right-hand panel has always followed: a
    /// control that does nothing is worse than its absence.
    /// **Whether there is a sidebar at all right now.** Schedule used to have
    /// none — it drew a "Not scheduled" column of its own and took the window.
    /// Since 2026-08-29 it uses the same scene list every other mode does, his
    /// instruction, so the only question left is whether he has it switched on.
    private var sidebarOut: Bool { state.sidebarShown && !(state.sideTab == .diagram && state.diagramFolded) }

    /// Shot List going off takes Schedule with it, when Schedule is on.
    private func takesSchedule(_ mode: SideTab) -> Bool {
        mode == .scenes && state.modesShown.contains(.schedule)
    }

    private var turnOffTitle: String {
        guard let mode = turningOff else { return "" }
        return takesSchedule(mode) ? "Turn Off Shot List and Schedule?" : "Turn Off \(mode.title)?"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Above what follows, so the shoot menu a checking run lays open
            // (`--shootmenu`) draws over the window rather than under it.
            if !state.diagramPresenting { topBar.zIndex(1) }
            if let version = state.looking, !state.diagramPresenting {
                LookingBanner(state: state, version: version)
            }
            HStack(spacing: 0) {
                if sidebarOut, !state.diagramPresenting {
                    // **A panel that floats on the background**, which is
                    // where two of his notes meet.
                    //
                    // First, with iMessage as the reference: the sidebar "felt
                    // like it's on top of its own separate panel" when it
                    // "should just be on top of the background". So the slab
                    // came off and the sidebar painted nothing at all. Then,
                    // looking at that: it "doesn't feel like a floating panel
                    // with rounded corners — it feels like its own thing."
                    //
                    // Both are the same complaint about an edge you can feel.
                    // Painting nothing did not put the sidebar *on* the
                    // background, it made it *be* the background, ending in a
                    // straight cut against the well. What reads as floating is
                    // an object: rounded, glass, air on all four sides, and the
                    // ground continuous behind and around it. The window's one
                    // square-cornered surface is still the well, which is the
                    // corner rule he gave me, unchanged.
                    Sidebar(state: state)
                        .floatingGlass(dark)
                        .frame(width: state.sidebarWidth)
                        .transition(.move(edge: .leading))
                    divider
                }
                Content(state: state)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                // **The panel is the sidebar's opposite number**, and gets
                // the same treatment for the same reason — "same with the
                // right side panel". It still spans the full height rather
                // than starting below the tabs (his earlier ask, which is what
                // stopped it reading as a box bolted onto the table); it now
                // spans it as a floating panel rather than as a flush column.
                if state.panelShown, state.sideTab == .scenes, let scene = state.scene {
                    panelDivider
                    // Same reasoning on this side.
                    SidePanel(state: state, scene: scene)
                        .floatingGlass(dark)
                        .frame(width: state.panelWidth)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeOut(duration: 0.2), value: state.panelShown)
        }
        // **One background, all the way across.** This was `ground`, a tone
        // between the well and the chrome, so the window had three: the well
        // under the table, a lighter strip behind the panels, and the panels'
        // own glass on top of that. Three tones is what made the panels read
        // as "an awkward background that's separate from the background
        // underneath the table" rather than as glass laid over it.
        //
        // The window is the well's colour now, edge to edge and behind
        // everything, so the panels have something continuous to float on and
        // their glass is doing the only work.
        .background(Brand.surface(dark))
        .ignoresSafeArea(.container, edges: .top)
        // **What the Schedule's hand is carrying, under the pointer** — over
        // the whole window, so it follows a scene out of the sidebar and
        // across the board. Draws nothing unless something is held.
        .overlay { BoardGhost().ignoresSafeArea() }
        .sheet(isPresented: $state.movingShots) { MoveShots(state: state) }
        .sheet(isPresented: $state.browsing) { ProjectBrowser(state: state) }
        .sheet(isPresented: $state.showingSyncHistory) { SyncHistoryView(state: state) }
        .sheet(isPresented: $state.settingUpSync) { SyncSetupSheet(state: state) }
        .sheet(isPresented: $state.editingColumns) { EditColumnsSheet(state: state) }
        .modifier(EditRefDoors(state: state))
        .sheet(isPresented: $state.editingProject) { ProjectSettingsSheet(state: state) }
        .onAppear { SettingsDoor.open = { openSettings() } }
        .sheet(item: Binding(
            get: { state.view?.scenes.first { $0.id == state.editingScene } },
            set: { state.editingScene = $0?.id }
        )) { scene in
            SceneDetailsSheet(state: state, scene: scene)
        }
        .sheet(item: Binding(
            get: { state.view?.scenes.first { $0.id == state.namingSequence } },
            set: { state.namingSequence = $0?.id }
        )) { scene in
            NameSequenceSheet(state: state, scene: scene)
        }
        .sheet(isPresented: $state.addingScene) { AddSceneSheet(state: state) }
        .sheet(isPresented: $state.pastingScript) { PasteScriptSheet(state: state) }
        .sheet(isPresented: $state.namingSection) { NameSequenceSheet(state: state, scene: nil) }
        .sheet(isPresented: $state.addingLocation) { AddLocation(state: state) }
        .sheet(isPresented: $state.addingBoard) { NameBoard(state: state) }
        .sheet(item: boardBeingRenamed) { board in
            NameBoard(state: state, renaming: board)
        }
        .sheet(item: Binding(
            get: { state.addingAreaIn.map(Naming.init(id:)) },
            set: { state.addingAreaIn = $0?.id }
        )) { inside in
            AddLocation(state: state, inside: inside.id)
        }
        .sheet(item: $state.importingScript) { file in
            ImportScriptSheet(state: state, file: file)
        }
        .sheet(isPresented: $state.settingUp) { NewProjectSheet(state: state) }
        .sheet(isPresented: $state.makingCard) { NewCardSheet(state: state) }
        .sheet(item: Binding(
            get: { state.view?.locations.first { $0.id == state.findingAddress } },
            set: { state.findingAddress = $0?.id }
        )) { place in
            AddressFinder(state: state, place: place)
        }
        .picturePicker(state)
    }

    /// The top bar, drawn rather than handed to `.toolbar`.
    ///
    /// The system toolbar puts a glass capsule behind every item on current
    /// macOS. It looks fine on screen and photographs as a white blob, which
    /// makes the chrome the one part of the app that could never be checked —
    /// and the chrome is most of what Nathaniel is judging. So it is ours, the
    /// way the old app's is.
    private var topBar: some View {
        TopBarLayout {
            // **The left flank and the right flank are both `maxWidth:
            // .infinity`, and that is what centres the modes.** Two flexible
            // flanks either side of a fixed middle share the leftover space
            // equally, so the middle of this bar is the middle of the window —
            // which is where an overlay used to put it, without an overlay's
            // one flaw: nothing underneath an overlay knows it is there, and at
            // 1016 points the switcher was drawn straight across the film's
            // name.
            //
            // The sidebar's own patch has to be *inside* this flank rather than
            // beside it, or the left side is 260 points wider than the right
            // and the switcher sits half a sidebar off centre.
            HStack(spacing: 0) {
                if sidebarOut {
                    HStack(spacing: 2) {
                        // The traffic lights own this patch. 68 was right when
                        // the button beside them was a 22pt square; it became a
                        // 27pt circle when the chrome went glassy and nobody
                        // re-measured, so the two sat shoulder to shoulder —
                        // his screenshot.
                        Color.clear.frame(width: 76, height: 1)
                        Spacer(minLength: 0)
                        ToolButton(icon: "sidebar.leading", help: "Hide the sidebar") {
                            toggleSidebar()
                        }
                    }
                    .frame(width: state.sidebarWidth)
                    .padding(.trailing, 12)
                }

                HStack(spacing: 8) {
                    if !sidebarOut {
                        // **Clear of the traffic lights.** 60 points put the
                        // toggle hard against the green button — close enough
                        // that the two read as one crowded cluster, which is
                        // what he photographed. The lights end around 70; 78
                        // leaves a gap you can see rather than a collision you
                        // can feel.
                        Color.clear.frame(width: 78, height: 1)
                        // Only where there is one to show. On Schedule there is
                        // no sidebar, so this button had nothing to do — see
                        // `sidebarOut`.
                        if state.sideTab != .schedule {
                            ToolButton(icon: "sidebar.leading", help: "Show the sidebar") {
                                toggleSidebar()
                            }
                        }
                        Spacer().frame(width: 4)
                    }
                    Button { nameCard.toggle() } label: {
                        HStack(spacing: 6) {
                            // **The film's name, and nothing under it.** The
                            // scene used to be spelled out here too; every
                            // scene wears its own heading inside the table now,
                            // so this was the same words said twice.
                            //
                            // It truncates rather than pushing: in a narrow
                            // window the name is the thing that can afford to
                            // lose a few letters, and the switcher is not.
                            // **A floor of 74 points, and truncation below
                            // that.** Two flexible flanks split the leftover
                            // space evenly, which centres the switcher on the
                            // window — right, until the window is narrow, when
                            // an even split gave the left flank less than the
                            // sidebar's own patch and the film was called "…".
                            //
                            // A minimum makes the flanks stop being even only
                            // when they have to: at any ordinary width the
                            // switcher is dead centre, and in a cramped one it
                            // slides a little right rather than eating the
                            // name.
                            // **The film's own mark, beside its name** — where
                            // the website puts it, in the same corner, off the
                            // same Notion row. Nothing at all when the film has
                            // no icon: a name and no gap where a picture should
                            // be.
                            if let mark = state.mark {
                                FilmIcon(mark: mark, size: 15)
                            }
                            // **The film's name is the largest word in this
                            // bar.** It was 13pt beside mode pills at 12.5 in
                            // a solid accent capsule, so the loudest thing up
                            // here was the tab you were on and the quietest
                            // was the film — his report, 2026-09-08: *"the
                            // title of the film … looks kind of small."*
                            Text(state.projectTitle)
                                .sans(Brand.Size.large, weight: .semibold)
                                .foregroundStyle(Brand.ink(dark))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(minWidth: 74, alignment: .leading)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(Brand.ink4(dark))
                            // **Which film this is, and which program.** A
                            // commercial wears its kind so the different
                            // band under every scene is not a surprise; the
                            // Labs build wears its name so two Shotlisters
                            // side by side are never mistaken for each other.
                            //
                            // **A tag is shown whole or not at all.** It used
                            // to give ground with the name, so a narrow window
                            // wrapped it to COMMERCIA over L — his report,
                            // 2026-10-02. Now the tags go first in line for
                            // space (`layoutPriority`) but only after the name
                            // keeps its 74-point floor; when that leaves too
                            // little, COMMERCIAL steps aside, then LABS.
                            if state.view?.project.isCommercial == true || ChromeTag.labs {
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 6) {
                                        if state.view?.project.isCommercial == true {
                                            ChromeTag(word: "Commercial", accent: false)
                                        }
                                        #if SHOTLISTER_LABS
                                        ChromeTag(word: "LABS", accent: false)
                                        #endif
                                    }
                                    #if SHOTLISTER_LABS
                                    ChromeTag(word: "LABS", accent: false)
                                    #endif
                                    Color.clear.frame(width: 0, height: 0)
                                }
                                .layoutPriority(1)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .help("Project")
                    // **The name opens the film's card** — his call,
                    // 2026-10-05, replacing a separate Project button that
                    // "feels clunky and redundant": the facts, Open in
                    // Projects Console, and the other films below them, so
                    // switching is still this one click. See `NameCard`.
                    .popover(isPresented: $nameCard, arrowEdge: .bottom) {
                        NameCard(state: state) { nameCard = false }
                    }
                    // **The shoot picker**, beside the name (piece D): nothing
                    // at all with fewer than two shoots.
                    ShootPicker(state: state)
                        .layoutPriority(2)
                    Spacer(minLength: 0)
                }
                .padding(.leading, sidebarOut ? 12 : 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // **The modes live in the chrome**, centred on the window.
            //
            // This strip used to hold the views of a scene — Shot List,
            // Storyboard, Document — which meant the most prominent furniture
            // in the window was blank in three modes out of four, while the
            // switch that changes the whole program was a row of pills hidden
            // inside a panel you can close. His finding, 2026-08-23; the fix is
            // simply to put the bigger question in the bigger place. The views
            // moved down onto the bar over the table, which is what they act on.
            //
            // `fixedSize` so it is the one thing in this bar that never gives
            // ground. Everything else here can truncate; a switcher with a
            // squeezed-out label is a switcher you cannot read.
            //
            // **Words, no icons** — which is this project's standing ruling on
            // this exact control, made when it lived in the sidebar and applied
            // again to the side panel's tabs: *three words in a row of capsules
            // read faster than three little pictures, and the icons were doing
            // no work the words were not.* I put icons back on it by reflex and
            // they cost more than they looked: `fixedSize` on a wider switcher
            // raised the **window's own minimum width** from 1015 points to
            // 1064, and the table could no longer give its last ten points of
            // spread back in a narrow window. One check caught that; the ruling
            // would have prevented it.
            ModeSwitcher(selection: $state.sideTab,
                         modes: state.modesShown,
                         canChange: state.modesFollowCard,
                         turnOn: { state.setMode($0, on: true) },
                         turnOff: { turningOff = $0 })
                .padding(.horizontal, 10)
                .opacity(state.modeBusy ? 0.6 : 1)
                .confirmationDialog(turnOffTitle, isPresented: Binding(get: { turningOff != nil }, set: { if !$0 { turningOff = nil } }),
                                    titleVisibility: .visible) {
                    Button("Turn Off", role: .destructive) {
                        if let mode = turningOff { state.setMode(mode, on: false, both: takesSchedule(mode)) }
                        turningOff = nil
                    }
                    Button("Cancel", role: .cancel) { turningOff = nil }
                } message: {
                    Text(turningOff.map(takesSchedule) == true
                         ? "Also turns off Schedule. Nothing is deleted."
                         : "Nothing is deleted.")
                }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                // **The iCloud tick used to sit here.** His ruling,
                // 2026-08-31: *"it seems to be useless."* It was — it reported
                // where the folder lives, which does not change, cannot be
                // acted on, and says nothing about whether anything has
                // actually moved. The Sync button next door is the honest
                // answer to the question it looked like it was answering.
                // Since 2026-09-15 the films are not in iCloud at all.

                // **The thing to press.** His complaint about iCloud was that
                // there is nothing to press when it lags behind. Only drawn
                // where his relay has actually been set up — a button that
                // cannot work is worse than its absence, which is why the
                // panel handle next door is conditional too.
                if state.canSync {
                    // **The button itself turns, rather than being replaced by
                    // a spinner.** His ask, 2026-08-31: *"i want the sync button
                    // to have an animation whenever they are actually in the
                    // syncing process"*. Swapping in a `ProgressView` made the
                    // button vanish for the duration, which reads as the app
                    // losing the control rather than using it — and the thing
                    // he wanted to see was *this* button working.
                    //
                    // The icon is already a circle of arrows, so it turns.
                    SpinningToolButton(
                        icon: state.syncProblem == nil
                            ? "arrow.triangle.2.circlepath"
                            : "exclamationmark.arrow.triangle.2.circlepath",
                        // **A tooltip is a label**, and this one now carries the
                        // one fact he asked to see on hover. The problem is the
                        // exception and still earns its sentence.
                        help: state.syncProblem
                            ?? (state.syncing ? "Syncing…"
                                : state.picturesWaiting > 0
                                    ? "\(state.picturesWaiting) picture\(state.picturesWaiting == 1 ? "" : "s") not sent"
                                    : SyncHistory.said),
                        spinning: state.syncing
                    ) {
                        state.syncNow()
                    }
                    // **The count, on the button rather than under the cursor.**
                    //
                    // A tooltip nobody hovers is the same as silence, and
                    // silence here is what put nineteen grey boxes on his crew
                    // link. Photographs no longer wait to be asked for, so this
                    // should sit at zero — a number now means they could not be
                    // sent, which is the thing worth seeing.
                    .overlay(alignment: .topTrailing) {
                        if state.picturesWaiting > 0, !state.syncing {
                            Text(state.picturesWaiting > 99 ? "99+" : "\(state.picturesWaiting)")
                                .font(.system(size: 10, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Brand.onImage)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                // **The app's accent, not the system's.** A
                                // macOS blue capsule beside a film wearing its
                                // own red was the one thing in the chrome that
                                // did not follow. 2026-09-05.
                                .background(Capsule().fill(Brand.accent(dark)))
                                .offset(x: 2, y: -2)
                                .allowsHitTesting(false)
                        }
                    }
                    // `syncedAt` is read so SwiftUI redraws the tooltip when a
                    // sync finishes; without it the help text is whatever it was
                    // when the bar was last built.
                    .id(state.syncedAt ?? .distantPast)
                    // **Everything about syncing that is not "do it now".**
                    //
                    // The password copy is here because it is about *this Mac
                    // and his phone* rather than about the film. The history
                    // joined it for the same reason: it is this device's own
                    // account of its comings and goings, and the button it
                    // belongs to is this one.
                    .contextMenu {
                        Button("Sync history…") { state.showingSyncHistory = true }
                        Divider()
                        Button("Copy password for iPhone") { state.copyRelayToken() }
                        Button("Copy relay address") { state.copyRelayAddress() }
                    }
                }
                // **Share is back**, his ask 2026-08-24: one button for the
                // whole project's export, beside settings the way Cadrage
                // puts it. A per-scene export lives on the scene itself,
                // in its right-click menu, not here.
                //
                // A menu rather than a button now that there are three ways
                // out — the workbook, the whole film's pages, and a folder of
                // one package per shoot day.
                exportMenu
                // **The gear opens quick jumps** (his mockup, 2026-10-16):
                // Columns, Spec Sheet, Tags, Project Settings, Studio Settings,
                // and the working aspect ratio when the sheet gives several.
                ToolButton(icon: "gearshape", help: "Settings") {
                    state.gearOpen.toggle()
                }
                .popover(isPresented: $state.gearOpen, arrowEdge: .bottom) {
                    GearPopover(state: state) { state.gearOpen = false }
                }
                // The panel's handle, mirroring the sidebar's on the left —
                // and so it sits **last, at the edge it opens**, the way the
                // sidebar's sits first at the edge it opens. His question,
                // 2026-09-15, was whether the order was right; it was not:
                // this stood between Sync and Share, two buttons away from
                // its own panel. Actions on the film (sync, share, settings)
                // now stand together; the one control that changes the
                // layout stands where the layout changes.
                //
                // **Only where there is a panel.** It belongs to a scene —
                // that scene's script, its references, its notes — and the
                // Locations screen has none, so on that tab this button
                // toggled a preference and changed nothing on screen. A
                // control that does nothing is worse than its absence.
                if state.sideTab == .scenes {
                    ToolButton(icon: state.panelShown
                               ? "sidebar.trailing" : "sidebar.right",
                               help: state.panelShown
                               ? "Put the panel away" : "Script, references and notes") {
                        state.panelShown.toggle()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 12)
        }
        .frame(height: 52)
        .background(Brand.surface2(dark))
        .hairline(.bottom, Brand.rule(dark))
    }

    /// The two ways out of the app, behind the share glyph.
    ///
    /// **Matter-of-fact names, not sentences** — his correction, 2026-08-27:
    /// a menu says what it does, not "…" trailing off into a description.
    /// Two items rather than the four this once grew to: a workbook's
    /// location and its auto-update switch moved to Project Settings, which
    /// is where a standing arrangement belongs, and per-day export moved
    /// inside the PDF dialog itself as a scope — see `ScenePDFExportSheet`.
    ///
    /// **`ToolMenu`, the same control as its neighbours.** This was the one
    /// button in the row built its own way — a 27pt glass circle behind a
    /// `.borderlessButton` menu, beside three 24pt hairline capsules — and
    /// that menu style throws away the label's measurements, which is what
    /// left the glyph sitting off-centre in its well. His eye caught it,
    /// 2026-09-15. `ToolMenu` exists for exactly this and every other
    /// pop-out already wears it.
    private var exportMenu: some View {
        ToolMenu(icon: "square.and.arrow.up", help: "Export…") {
            Button("Export spreadsheet…") { Exporting.exportExcel(state: state) }
            Button("Export PDF…") { Exporting.exportProjectPDF(state: state) }
        }
    }

    private func toggleSidebar() {
        withAnimation(.easeOut(duration: 0.18)) {
            // Folded while drawing: the button brings it back.
            if state.sideTab == .diagram, state.diagramFolded {
                state.diagramFolded = false
                state.sidebarShown = true
            } else {
                state.sidebarShown.toggle()
            }
        }
    }

    /// A hairline you can grab. The line is one pixel because that is what it
    /// should look like; the target is nine, because that is what a hand needs.
    ///
    /// Pulling past either stop is deliberately silent: the width holds at the
    /// stop and the anchor is kept, so pushing back the other way picks up
    /// exactly where it left off instead of jumping. A drag that fights back is
    /// worse than one that simply stops.
    /// The right panel's grab, drawn the same as the sidebar's: nothing to see,
    /// nine points to catch.
    private var panelDivider: some View {
        Color.clear
            .frame(width: 1)
            .overlay { PanelGrab(state: state).frame(width: 9) }
    }

    private var divider: some View {
        Color.clear
            .frame(width: 1)
            .overlay {
                DividerGrab(state: state)
                    .frame(width: 9)
            }
    }

    /// The divider's drag, owned by AppKit rather than by SwiftUI.
    ///
    /// `DragGesture` produced three separate bugs in this one control — an
    /// anchor that raced the render loop, a translation measured against a
    /// coordinate space the resize itself kept moving, and finally a press that
    /// could not be delivered at all unless the window was key, which is the one
    /// thing a check is not allowed to take. A divider is a plain AppKit control
    /// and behaves like one here: `mouseDown` remembers where the grab started,
    /// `mouseDragged` reads `locationInWindow` — a space that cannot move
    /// underneath it — and `acceptsFirstMouse` lets the press land in a window
    /// that is not key, which is both what a checking run needs and what a real
    /// person clicking an inactive window expects.
    /// The right panel's own handle. Same idea as the sidebar's, mirrored:
    /// this edge is on the panel's *left*, so dragging left makes it wider.
    private struct PanelGrab: NSViewRepresentable {
        let state: ShellState

        func makeNSView(context: Context) -> Handle {
            let handle = Handle()
            handle.state = state
            return handle
        }

        func updateNSView(_ view: Handle, context: Context) {
            view.state = state
            view.window?.invalidateCursorRects(for: view)
        }

        final class Handle: NSView {
            weak var state: ShellState?
            private var grabbedAt: CGFloat = 0
            private var widthAtGrab: CGFloat = 0

            override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

            override func resetCursorRects() {
                addCursorRect(bounds, cursor: .resizeLeftRight)
            }

            override func mouseDown(with event: NSEvent) {
                guard let state else { return }
                grabbedAt = event.locationInWindow.x
                widthAtGrab = state.panelWidth
            }

            override func mouseDragged(with event: NSEvent) {
                guard let state else { return }
                // Minus, not plus: the handle is on the panel's leading edge,
                // so the pointer moving left has to make the panel wider.
                // Whole points, for the same reason the sidebar rounds — a
                // fractional width shimmers a pixel either side of the hand.
                let wanted = widthAtGrab - (event.locationInWindow.x - grabbedAt)
                state.panelWidth = min(
                    ShellState.panelRange.upperBound,
                    max(ShellState.panelRange.lowerBound, wanted.rounded())
                )
            }
        }
    }

    private struct DividerGrab: NSViewRepresentable {
        let state: ShellState

        func makeNSView(context: Context) -> Handle {
            let handle = Handle()
            handle.state = state
            return handle
        }

        func updateNSView(_ view: Handle, context: Context) {
            view.state = state
            view.window?.invalidateCursorRects(for: view)
        }

        final class Handle: NSView {
            weak var state: ShellState?
            private var grabbedAt: CGFloat = 0
            private var widthAtGrab: CGFloat = 0

            /// So a click lands rather than being eaten as the blow that brings
            /// an inactive app forward.
            override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

            override func resetCursorRects() {
                addCursorRect(bounds, cursor: .resizeLeftRight)
            }

            override func mouseDown(with event: NSEvent) {
                guard let state else { return }
                grabbedAt = event.locationInWindow.x
                widthAtGrab = state.sidebarWidth
                state.dragAnchor = widthAtGrab
                state.dragUpdates = 0
                state.widthTrace = []
            }

            override func mouseDragged(with event: NSEvent) {
                guard let state else { return }
                state.dragUpdates += 1
                let wanted = widthAtGrab + (event.locationInWindow.x - grabbedAt)
                // Whole points. A pointer reports fractional movement, and the
                // sidebar, the divider and the content each round to device
                // pixels on their own — so a width of 300.37 could put the line
                // a pixel either side of the hand while the numbers marched
                // along perfectly monotonic. That shimmer is what he felt and
                // what a harness sampling the model could never see.
                state.sidebarWidth = min(
                    ShellState.sidebarRange.upperBound,
                    max(ShellState.sidebarRange.lowerBound, wanted.rounded())
                )
                state.widthTrace.append(state.sidebarWidth)
            }

            override func mouseUp(with event: NSEvent) {
                state?.dragAnchor = nil
                state?.persistSidebarWidth()
            }
        }
    }

}

// ------------------------------------------------------------------ sidebar

struct Sidebar: View {
    @ObservedObject var state: ShellState
    /// What the Schedule's hand holds — so a scene picked up from this list
    /// stands dimmed while it is carried, and the list lights when a strip is
    /// held over it to come off its day.
    @ObservedObject private var hands = BoardHands.shared
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        // In the Diagram the one sidebar carries three tabs — Scenes, Layers,
        // Shots — so there is no second list floating beside the first.
        if state.sideTab == .diagram, let model = state.diagram {
            DiagramSidebar(state: state, model: model) { sceneColumn }
        } else {
            sceneColumn
        }
    }

    private var sceneColumn: some View {
        VStack(spacing: 0) {
            // **Search and the filters live at the foot now**, his call,
            // reversing the mock's order and my argument for it ("the thing
            // you reach for most often should not be at the bottom of a column
            // that grows"). His reason is better than mine was: the scene
            // filter had ended up alone under the heading and read as an
            // afterthought, and three narrowing controls together at the foot
            // read as a set. The list gets the whole column, which is what the
            // column is for.
            // **The mode switcher used to stand here** and moved into the top
            // bar on 2026-08-23. His finding, and it was the right way round:
            // the window's loudest strip was answering the smallest question —
            // which view of a scene — while the question that changes the whole
            // program was a row of pills inside a panel you can close. Closing
            // the sidebar left you with no way back to Locations at all.
            //
            // **Not in the Diagram**: its tab already says Scenes, and the
            // filter and + ride on the list's own Scenes head under the Plans
            // (`DiagramPlanRows.head`), where they are not a row of buttons
            // with nothing beside them. His report, 2026-10-02.
            if state.sideTab != .diagram { heading }

            Group {
                switch state.sideTab {
                // **Schedule gets the same scene list as Shot List** — his
                // instruction, 2026-08-29: "the left sidebar should have the
                // exact same sidebar for scenes as Shot List does … that way
                // it's consistent." It had a column of its own listing only
                // the unscheduled, which was a second way of drawing scenes
                // that agreed with nothing else in the program. The board's
                // scenes now come from the one list, and a scene is taken off
                // a day from the strip's own menu rather than by dragging it
                // back to a column that no longer exists.
                case .scenes, .schedule, .diagram: sceneList
                case .locations: LocationList(state: state)
                case .boards: BoardList(state: state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // **The foot is the narrowing.** Search, then the two filters —
            // scenes and shots — one under the other so neither is the odd
            // one out. What each has *found* is reported above the table,
            // beside the count, rather than chipped twice.
            //
            // (The old foot line — the film's name, its ratio, the first
            // camera — is gone and stays gone: he cut it as redundant, and it
            // was.)
            // **Search, and nothing under it.** The scene filter and its chips
            // lived here and the foot grew as filters went on — so the search
            // box moved under his hand depending on how many were set, and the
            // same facts appeared twice: here, and again beside the shot count
            // above the table. His words: "it changes where the search bar
            // lives depending on how many things are selected."
            //
            // The filter is a fixed button in the heading now, and what is on
            // is reported once, above the table, where the count already is.
            VStack(alignment: .leading, spacing: 6) {
                Brand.rule(dark).frame(height: 1).opacity(0.7)
                    .padding(.bottom, 2)
                SearchField(placeholder: state.sideTab.searching,
                            text: $state.search)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        // Painted rather than left to the system's sidebar material. Two
        // reasons: dark mode is a designed twin here rather than whatever
        // vibrancy produces, and a material draws nothing at all into a cached
        // bitmap — which is how this app photographs itself for checking.
    }

    /// The scene's own fields, and what each one is called on screen.
    ///
    /// **Scene filters live here rather than in the bar above the table**, his
    /// call, and the reason is that they are not the same kind of thing. A
    /// shot filter hides *shots inside* scenes; a scene filter takes whole
    /// scenes out of the film. Putting both behind one "Filter" button is how
    /// you end up unable to say which of the two just shortened your list.
    /// The sidebar *is* the scene list, so the control that narrows it sits on
    /// it — and this chevron was drawn for exactly this from the start.
    ///
    /// The engine already narrows by these; it was only ever the menu that did
    /// not offer them, because the bar's list is built from *shot* columns.
    /// **The names are the engine's, exactly.** `ffi/src/lib.rs` keeps the
    /// authoritative list of which fields belong to a scene — location,
    /// shooting_location, time_of_day, int_ext, priority, pov — and anything
    /// not on it is read as a fact about a *shot*. So a near-miss spelling
    /// does not fail loudly, it quietly asks the wrong question and comes back
    /// with an empty list: `timeOfDay` was my first guess here and it narrowed
    /// to nothing. Tags are a shot's, per that same list, and are not offered.
    ///
    /// Day and sequence are scene facts too, but the engine keeps them apart
    /// from the facets, so they are set through their own doors below.
    static let sceneFacets: [(field: String, label: String, icon: String)] = [
        // **The location record**, which is the one that means anything now
        // that scenes point at the Locations screen. Its values are ids, not
        // words, so `sceneValues` hands back the name to show and the id to
        // narrow by.
        ("location_id",       "Location",         "mappin.and.ellipse"),
        ("location",          "Script location",  "text.book.closed"),
        ("shooting_location", "Filming location", "map"),
        ("time_of_day",       "Time of day",      "sun.max"),
        ("int_ext",           "Interior/Exterior", "door.left.hand.open"),
        ("priority",          "Priority",         "flag"),
        ("pov",               "Point of view",    "eye"),
    ]

    /// What a field actually holds across this film — never a fixed list, so a
    /// menu can only ever offer a narrowing that returns something.
    private func sceneValues(_ field: String) -> [(value: String, label: String)] {
        state.reckonPairs("facet." + field) { self.readSceneValues(field) }
    }

    private func readSceneValues(_ field: String) -> [(value: String, label: String)] {
        let scenes = (state.view?.scenes ?? []).filter { !$0.archived }
        var seen: [String: String] = [:]
        // A location is narrowed by its id and read by its name, so it is the
        // one field where the two halves differ.
        if field == "location_id" {
            let places = state.view?.locations ?? []
            for sc in scenes {
                for at in sc.locations {
                    guard let place = places.first(where: { $0.id == at }) else { continue }
                    // The full name, so filtering can tell a house's Kitchen
                    // from the one down the road — Ref 269.
                    seen[at] = place.fullName.isEmpty ? place.name : place.fullName
                }
            }
            return seen.map { (value: $0.key, label: $0.value) }
                .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        }
        for sc in scenes {
            let held: String
            switch field {
            case "location":          held = sc.location
            case "shooting_location": held = sc.shootingLocation
            case "time_of_day":       held = sc.timeOfDay
            case "int_ext":           held = sc.intExt
            case "priority":          held = sc.priority
            case "pov":               held = sc.pov
            default:                  held = ""
            }
            if !held.isEmpty { seen[held] = field == "int_ext" ? insideOutShown(held) : held }
        }
        return seen.map { (value: $0.key, label: $0.value) }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    private func narrowScenes(_ field: String, _ value: String) {
        if value.isEmpty { state.facets.removeValue(forKey: field) }
        else { state.facets[field] = value }
        state.replace(state.engine?.facet(field, value))
    }

    /// "Scenes ⌄" with the ＋ opposite it. **The chevron is the archive**, his
    /// call — the scenes a script revision took out, and the ones set aside by
    /// hand. It is not the filter: a filter is a way of *looking* at the film
    /// and the archive is a statement about what is still in it, and one
    /// chevron cannot be both without being neither.
    private var heading: some View {
        HStack(spacing: 4) {
            // The same heading and menu on the Schedule tab: the archive is
            // reached one way everywhere (his word, 2026-10-13).
            if state.sideTab == .scenes || state.sideTab == .schedule {
                Menu {
                    let archived = (state.view?.scenes ?? []).filter(\.archived)
                    Button(state.showingArchive
                           ? "Back to the film"
                           : "Show archived scenes\(archived.isEmpty ? "" : "  (\(archived.count))")") {
                        state.showingArchive.toggle()
                        // The chosen scene may not be in the list any more.
                        state.sceneId = state.scenes.first?.id
                    }
                    .disabled(archived.isEmpty && !state.showingArchive)
                } label: {
                    HStack(spacing: 4) {
                        Text(state.showingArchive ? "Archived" : state.sideTab.heading)
                            .sans(Brand.Size.small, weight: .semibold)
                            .foregroundStyle(state.showingArchive ? Brand.accent(dark)
                                                                  : Brand.ink2(dark))
                        Image(systemName: "chevron.down")
                            .font(.system(size: Brand.Icon.tiny, weight: .semibold))
                            .foregroundStyle(Brand.ink4(dark))
                    }
                }
                // **`.button` and a plain button, not `.borderlessButton`.**
                // A borderless menu is drawn by AppKit, which throws the
                // label's font and ink away and uses the system control's —
                // so this heading came out large and white while the identical
                // one on the Schedule tab, which is not a menu, was small and
                // grey. His report, 2026-09-08: *"the words Scenes in the left
                // sidebar between the Schedule tab and the Shotlist tab are
                // different sizes."* `ToolMenu` has always used this pair and
                // has always drawn what it was told to.
                //
                // Moving the modifiers *outside* the menu does not help; the
                // style is the whole of it.
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .focusEffectDisabled()
                .fixedSize()
            } else if state.sideTab != .diagram || state.diagram == nil {
                // (In the Diagram its tab already says Scenes.)
                Text(state.sideTab.heading).sans(Brand.Size.small, weight: .semibold)
                    .foregroundStyle(Brand.ink2(dark))
            }
            if state.sideTab == .schedule { leftToSchedule }
            Spacer()
            if state.sideTab == .scenes || state.sideTab == .schedule || state.sideTab == .diagram { sceneFilterMenu }
            // **The ＋ makes whatever the list is made of.** It added a scene
            // whichever list was showing, which on the Locations tab is a
            // button that does something to a screen you cannot see.
            switch state.sideTab {
            case .scenes, .schedule:
                ToolButton(icon: "plus", help: "Add a scene") { state.addingScene = true }
            case .diagram:
                // Scenes are added in the Shot List; the Diagram only adds diagrams.
                EmptyView()
            case .locations:
                ToolButton(icon: "plus", help: "Add a location") { state.addingLocation = true }
            case .boards:
                ToolButton(icon: "plus", help: "Add a reference board") { state.addingBoard = true }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
    }

    /// **How many scenes still have shots on no day**, beside the Schedule
    /// heading. Pressing it lists only those, the same narrowing the filter's
    /// *Shoot Day › Not scheduled yet* makes; pressing again shows every scene.
    @ViewBuilder private var leftToSchedule: some View {
        let left = state.scenesLeftToSchedule
        let only = state.facets["day"] == "none"
        if state.showingArchive {
            EmptyView()
        } else if only || left > 0 {
            Button { narrowScenes("day", only ? "" : "none") } label: {
                Text(only ? "Show All" : "\(left) not scheduled")
                    .sans(Brand.Size.tiny, weight: .semibold)
                    .foregroundStyle(Brand.accent(dark))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help(only ? "Show every scene" : "Show only the scenes still to schedule")
        } else {
            Text("All scheduled")
                .sans(Brand.Size.tiny)
                .foregroundStyle(Brand.ink3(dark))
                .lineLimit(1)
        }
    }

    /// The scene narrowings. Same look as the shot one directly beneath it —
    /// his note that the filter button should not sit awkwardly by itself, and
    /// two buttons that match are a pair where two that differ are an accident.
    ///
    /// No chips here: what is on is chipped once, above the table beside the
    /// count. The same fact drawn in two places is the thing he cut the old
    /// foot line for.
    private var sceneFilterMenu: some View {
        Menu {
            ForEach(Self.sceneFacets, id: \.field) { facet in
                let values = sceneValues(facet.field)
                if !values.isEmpty {
                    Menu {
                        ForEach(values, id: \.value) { option in
                            Button {
                                narrowScenes(facet.field,
                                             state.facets[facet.field] == option.value
                                             ? "" : option.value)
                            } label: {
                                Text(state.facets[facet.field] == option.value
                                     ? option.label + "  ✓" : option.label)
                            }
                        }
                    } label: { Label(facet.label, systemImage: facet.icon) }
                }
            }
            if !(state.view?.days ?? []).isEmpty {
                Menu {
                    Button("Any day") { narrowScenes("day", "") }
                    Button("Not scheduled yet") { narrowScenes("day", "none") }
                    Divider()
                    ForEach(state.pickableDays()) { day in
                        Button(day.label) { narrowScenes("day", day.id) }
                    }
                } label: { Label("Shoot day", systemImage: "calendar") }
            }
            if !(state.view?.sequences ?? []).isEmpty {
                Menu {
                    Button(state.view?.project.isCommercial == true ? "Any section" : "Any sequence") {
                        narrowScenes("sequence", "")
                    }
                    Divider()
                    ForEach(state.view?.sequences ?? []) { seq in
                        Button(seq.title) { narrowScenes("sequence", seq.id) }
                    }
                } label: { Label(state.view?.project.sequenceWord ?? "Sequence", systemImage: "square.stack") }
            }
            if scenesNarrowed {
                Divider()
                Button("Show every scene") {
                    for field in Self.sceneNarrowings where state.facets[field] != nil {
                        narrowScenes(field, "")
                    }
                }
            }
            Divider()
            // **Asked for, never automatic.** A project that took a draft in
            // before new scenes landed in their place is out of order and
            // nothing moves it — his report of a film reading 33, 34, 35, 54,
            // 1, 2, 3. Rearranging the film behind him would be worse than the
            // mess, so it is a thing he presses.
            if state.view?.project.isCommercial == true {
                Button("Paste Script…") { state.pastingScript = true }
                Button("Add Section…") { state.namingSection = true }
                Divider()
            }
            Button("Sort scenes by number") {
                state.replace(state.engine?.sortScenes())
            }
            // **A commercial's numbers are ours, so a commercial may renumber
            // — as a person's decision, with the cost said first.** A film
            // never sees this: the script owns its numbers. The engine's
            // `kind` module has the law.
            if state.view?.project.isCommercial == true {
                Button("Renumber in Order…") { renumberInOrder() }
            }
            // **Above the line is looking; below it is writing.** Ref 102. The
            // two sit in one menu and must not be mistaken for each other, so
            // one is an order you are reading in and the other is a button
            // that rewrites the film and says so.
            Menu("Read in order of") {
                ForEach(ShellState.SceneOrder.allCases, id: \.self) { order in
                    Button(state.sceneOrder == order ? "✓ \(order.label)" : order.label) {
                        state.sceneOrder = order
                    }
                }
            }
            // The same shape, and for the same reason: a film imported before
            // Ref 257 carries CONTINUED in the column, and only he can decide
            // his old projects should be rewritten.
            Button("Settle times of day") {
                state.replace(state.engine?.settleTimes())
            }
        } label: {
            // **A funnel beside the ＋**, the same size and the same weight, in
            // a row whose height never changes. Wherever this control has stood
            // so far it has been pushed around by whatever was next to it; in
            // the heading there is nothing to push it. It goes accent when a
            // filter is on, which is the whole of what it needs to say — the
            // *what* is reported once, above the table.
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(scenesNarrowed ? Brand.accent(dark) : Brand.ink3(dark))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(scenesNarrowed ? "Scenes are filtered" : "Filter scenes")
    }

    /// Says what it costs, then does it as one undoable step. Shot IDs are
    /// never stored — `34A` is the scene's number plus the letter, read fresh
    /// — so they follow without being touched.
    private func renumberInOrder() {
        guard let engine = state.engine else { return }
        let count = state.view?.scenes.count ?? 0
        let alert = NSAlert()
        alert.messageText = "Renumber in Order?"
        alert.informativeText = "\(count) scene\(count == 1 ? "" : "s") will be renumbered. Shot IDs change with them."
        alert.addButton(withTitle: "Renumber")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        _ = engine.renumberInOrder()
        state.replace(engine.view())
    }

    private static func icon(for field: String) -> String {
        sceneFacets.first { $0.field == field }?.icon
            ?? (field == "day" ? "calendar" : "square.stack")
    }

    // (The chip's own wording lives in `FilterBar` — `Filtering.swift`. A
    // second copy of it stood here, unread, while the chips printed a raw
    // location id: Ref 301.)

    /// Whether any scene-level narrowing is in force, so the chevron can say so
    /// without the person opening it to find out.
    private var scenesNarrowed: Bool {
        Self.sceneNarrowings.contains { state.facets[$0]?.isEmpty == false }
    }

    /// Every field this menu can narrow by, facets and the two that the engine
    /// keeps apart from them.
    static var sceneNarrowings: [String] {
        sceneFacets.map(\.field) + ["day", "sequence"]
    }

    private var sceneList: some View {
        // In the Diagram the loose plans head the list (`DiagramPlanRows`),
        // and one picked stands in for the scene.
        let diagram = state.sideTab == .diagram
        let planPicked = diagram ? state.diagramPlanLive : nil
        return List(selection: Binding(
            get: {
                if let plan = planPicked { return [DiagramPlanRows.tagPrefix + plan.id] }
                return state.sceneSelection
            },
            set: { new in
                let plans = new.filter { $0.hasPrefix(DiagramPlanRows.tagPrefix) }
                if diagram, let plan = plans.first {
                    state.diagramPlan = String(plan.dropFirst(DiagramPlanRows.tagPrefix.count))
                    return
                }
                if diagram { state.diagramPlan = nil }
                state.sceneSelection = new.subtracting(plans)
            }
        )) {
            if diagram {
                DiagramPlanRows(state: state)
                DiagramPlanRows.head("Scenes", dark: dark) {
                    // **Hide Empty** (his ask, 2026-10-17): scenes with
                    // nothing drawn on any diagram leave the list.
                    ToolButton(icon: state.diagramHideEmpty ? "eye.slash" : "eye", help: "Hide Empty",
                               lit: state.diagramHideEmpty) { state.diagramHideEmpty.toggle() }
                        .accessibilityIdentifier("diagram.hideEmpty")
                    sceneFilterMenu
                }
                .padding(.top, 8)
            }
            if state.groupingByShoot {
                // **All Shoots** (piece D): grouped by shoot, wrapped ones
                // folded away; sections stay his own inside each.
                ForEach(state.shootGroups) { group in
                    shootHead(group)
                    if !state.shootFolded(group.shoot) {
                        ForEach(group.scenes.filter { !(diagram && state.diagramHides($0)) }) { scene in
                            sceneRow(scene, in: group.scenes, planPicked: planPicked)
                        }
                    }
                }
            } else {
            ForEach(diagram ? state.scenes.filter { !state.diagramHides($0) } : state.scenes) { scene in
                sceneRow(scene, in: state.scenes, planPicked: planPicked)
            }
            // **Scenes are dragged into order here.** His ask, 2026-09-19:
            // "change order of items in lists". Script order only — a sorted
            // reading is a way of looking, not a list to rearrange — and not
            // on the Schedule tab, where a dragged scene is going onto a day.
            // Order only: numbers never move with a scene. On a commercial a
            // scene dropped inside another section's run joins that section,
            // because that is what the picture says.
            .onMove(perform: state.sideTab == .scenes && state.sceneOrder == .script
                    ? { from, to in state.moveScenes(from, to: to) } : nil)
            }
            // **Where the eye goes.** *Add Section…* lived in the ≡ menu and
            // he could not find it — his report, 2026-09-19: *"i can't really
            // see any place to add a section right now in the scene sidebar."*
            // A ghost row at the foot of the list, the same grammar as
            // `+ Add shot` under a scene. Commercials only: a film's
            // sequences come from the script.
            // How many are left out of the list, by hand or by Hide Empty;
            // clicking lists them again (each has Show), and again puts them away.
            if diagram {
                let hidden = state.diagramHiddenCount
                if hidden > 0 {
                    Button { state.diagramRevealHidden.toggle() } label: {
                        Text(state.diagramRevealHidden ? "Hide \(hidden)" : "\(hidden) Hidden").sans(11).foregroundStyle(Brand.ink3(dark))
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("diagram.hiddenCount")
                    .padding(.vertical, 6).padding(.horizontal, 8)
                    .selectionDisabled()
                    .sidebarRow(picked: false, dark: dark)
                }
            }
            if state.view?.project.isCommercial == true, state.sideTab == .scenes,
               !state.scenes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Button { state.namingSection = true } label: {
                        PlusLabel(text: "Add Section", dark: dark, size: 11)
                    }
                    .buttonStyle(.rowAction)
                    .focusEffectDisabled()
                    .accessibilityIdentifier("add-section")
                    Button { state.pastingScript = true } label: {
                        PlusLabel(text: "Paste Script", dark: dark, size: 11)
                    }
                    .buttonStyle(.rowAction)
                    .focusEffectDisabled()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .selectionDisabled()
                .sidebarRow(picked: false, dark: dark)
            }
        }
        .sidebarList()
        .environment(\.defaultMinListRowHeight, 30)
        // …and a strip let go back here comes off its day, which is the
        // gesture the old "Not scheduled" column used to answer. The list
        // lights while one is held over it.
        .background {
            if state.sideTab == .schedule { BoardMarkTag(.list) }
        }
        .overlay {
            if state.sideTab == .schedule, hands.spot == .off {
                RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
                    .strokeBorder(Brand.accent(dark), lineWidth: 1.5)
                    .background(Brand.accent(dark).opacity(0.06),
                                in: RoundedRectangle(cornerRadius: Brand.radius, style: .continuous))
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if state.scenes.isEmpty {
                // Two different empties, and saying the wrong one sends someone
                // hunting for a filter that is not on.
                Text(state.search.isEmpty
                     ? "No scenes in this project yet"
                     : "No scene matches “\(state.search)”")
                    .sans(11).foregroundStyle(Brand.ink3(dark))
                    .padding(.horizontal, 18)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// One scene's row in the sidebar — `list` is the run it is drawn in
    /// (the whole list, or one shoot's under All Shoots), which is what its
    /// section heads are worked out against.
    @ViewBuilder private func sceneRow(_ scene: ViewModel.Scene, in list: [ViewModel.Scene], planPicked: DiagramPlanItem?) -> some View {
            if state.sectionHeadBefore(scene, in: list) {
                sectionHead(state.sectionOf(scene))
            } else if state.sectionEndsBefore(scene, in: list) {
                // The panel above has closed; a scene in no section
                // starts after a breath of air, with nothing drawn.
                Color.clear.frame(height: 4)
                    .selectionDisabled()
                    .sidebarRow(picked: false, dark: dark)
            }
            let section = state.sectionOf(scene)
            let inSection = section != nil && state.view?.project.isCommercial == true
                && state.sceneOrder == .script
            let booking = state.sideTab == .schedule ? state.booking(of: scene) : nil
            // Settled scenes sit back so the ones still to place stand out.
            let settled = !state.showingArchive && (booking?.settled ?? false)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if scene.archived {
                    Image(systemName: "archivebox")
                        .font(.system(size: 10))
                        .foregroundStyle(Brand.ink4(dark))
                }
                // **Day or night, at a glance.** His ask: the little dots
                // beside the scenes for time of day. The space is held even
                // where the slugline did not say, so the numbers stay in
                // one column down the list.
                //
                // **The dot sits in a column of its own**, 8 wide, so it
                // has as much air on its left as on its right — his
                // report, 2026-09-15: "off-center and too far to the
                // left". `design/23-softer.html` `.sc`: 8px dot column,
                // 6px dot, 8px gaps, 8 in from the fill's edge.
                Circle()
                    .fill(Brand.timeInk(scene.timeOfDay, dark) ?? .clear)
                    .frame(width: 6, height: 6)
                    .frame(width: 8)
                    .help(scene.timeOfDay.isEmpty ? "No time of day" : scene.timeOfDay)
                Text(scene.number)
                    .sans(11, weight: .semibold)
                    .foregroundStyle(scene.archived ? Brand.ink4(dark)
                                     : settled ? Brand.ink3(dark) : Brand.ink(dark))
                    .frame(minWidth: 18, alignment: .trailing)
                Text(scene.heading)
                    .sans(11)
                    .foregroundStyle(scene.archived ? Brand.ink4(dark)
                                     : settled ? Brand.ink4(dark) : Brand.ink2(dark))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                // **On the Schedule, the day it is on** — so the list
                // you drag from says what is already placed. His report,
                // 2026-09-19. And since 2026-10-13 what is *not*: a scene
                // wholly on days sits back and says which; one with shots
                // still to place stays at full strength and says so, in
                // words as well as ink. A scene with no shots cannot go on
                // a day, so it says that and is never counted as forgotten.
                if let book = booking {
                    if state.showingArchive {
                        // Set-aside scenes are not part of the plan; say
                        // only where their shots still sit.
                        if !book.days.isEmpty {
                            Text(book.days)
                                .sans(Brand.Size.tiny).monospacedDigit()
                                .foregroundStyle(Brand.ink3(dark))
                                .lineLimit(1)
                                .fixedSize()
                        }
                    } else if !book.hasShots {
                        Text("No shots")
                            .sans(Brand.Size.tiny)
                            .foregroundStyle(Brand.ink4(dark))
                            .lineLimit(1)
                            .fixedSize()
                    } else if book.placed == 0 {
                        Text("Unscheduled")
                            .sans(Brand.Size.tiny, weight: .semibold)
                            .foregroundStyle(Brand.accent(dark))
                            .lineLimit(1)
                            .fixedSize()
                    } else {
                        Text(book.left == 0 ? book.days : "\(book.days) · \(book.left) left")
                            .sans(Brand.Size.tiny, weight: book.left == 0 ? .regular : .semibold)
                            .monospacedDigit()
                            .foregroundStyle(book.left == 0 ? Brand.ink3(dark) : Brand.accent(dark))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    // **Open it to see the shots still on no day** — each
                    // one can then be dragged onto a day by itself. His
                    // report, 2026-10-17: "Day 3 · 3 left" and no way to
                    // take the three anywhere.
                    if !state.showingArchive, book.hasShots, book.left > 0 {
                        // The click is the hand's (`BoardMark.opener`): a
                        // list row passes no click on to a button inside it.
                        let open = state.openRemainders.contains(scene.id)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Brand.ink3(dark))
                            .rotationEffect(.degrees(open ? 90 : 0))
                            .frame(width: 12, height: 14)
                            .background { BoardMarkTag(.opener(scene: scene.id)) }
                            .help(open ? "Hide shots left" : "Show shots left")
                            .accessibilityLabel(open ? "Hide shots left" : "Show shots left")
                    }
                }
            }
            // **A row is 30 high**, the mockup's `padding: 8px 10px` —
            // the system's sidebar style had been adding height of its own,
            // and taking it away left the rows too tight: "a little too
            // narrow for me", 2026-09-15.
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            // The last scene of a section keeps a little air under it,
            // inside the panel, so the foot's corners have room to turn.
            .padding(.bottom, state.sectionEndsAfter(scene, in: list) ? 4 : 0)
            .tag(scene.id)
            .sectionRow(section: inSection ? section : nil,
                        foot: state.sectionEndsAfter(scene, in: list),
                        picked: planPicked == nil && state.sceneSelection.contains(scene.id), dark: dark)
            .contextMenu { sceneMenu(scene) }
            // **On the schedule, a scene is something you drag onto a
            // day.** Only there: in Shot List this list is read and
            // picked from, and a drag that lands nowhere is a gesture
            // that teaches the hand a lie. Several picked scenes go
            // together, the same rule the context menu follows
            // (`scenesActedOn`).
            //
            // Not a system drag any more — his report, 2026-09-29, that
            // pulling a scene "start[s] multi selecting". A press the drag
            // source missed went to the table, which answers a pull by
            // selecting every row it crosses. The hand in
            // `ScheduleHands.swift` watches the press, across the row's
            // whole width: a click stays the table's own, and a pull
            // becomes a carry with the table's selecting switched off.
            .background {
                if state.sideTab == .schedule { BoardMarkTag(.row(scene: scene.id)) }
            }
            .opacity(state.sideTab == .schedule && hands.holds(listScene: scene.id) ? 0.45
                     : state.sideTab == .diagram && state.diagramRevealHidden && state.diagramLeftOut(scene) ? 0.5 : 1)
            if state.sideTab == .schedule, !state.showingArchive, state.openRemainders.contains(scene.id) {
                ForEach(state.remainder(of: scene.id), id: \.placement) { shot in
                    looseRow(shot)
                }
            }
    }

    /// **One shot of an opened scene that is still on no day** — dragged
    /// onto a day by itself, or picked with others (click, ⌘ or ⇧) and
    /// dragged together. Right-click is the way without a drag.
    private func looseRow(_ shot: BoardModel.StripShot) -> some View {
        let picked = state.loosePicked.contains(shot.placement)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(shot.number)
                .sans(11, weight: .semibold)
                .monospacedDigit()
                .foregroundStyle(Brand.ink(dark))
                .frame(minWidth: 30, alignment: .trailing)
            Text(shot.title.isEmpty ? shot.description : shot.title)
                .sans(11)
                .foregroundStyle(Brand.ink2(dark))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.leading, 22)
        .padding(.trailing, 8)
        .contentShape(Rectangle())
        // A click picks it (⌘ or ⇧ adds) — the hand's, in `released`.
        .contextMenu {
            if let days = state.stripBoard?.days, !days.isEmpty {
                let shots = state.dragLoose(for: shot.placement)
                Menu(shots.count > 1 ? "Schedule \(shots.count) Shots on" : "Schedule on") {
                    ForEach(days) { day in
                        Button(Schedule.dayName(day)) { state.putShots(shots, on: day.id, before: nil) }
                    }
                }
            }
        }
        .selectionDisabled()
        .sidebarRow(picked: picked, dark: dark)
        .background { BoardMarkTag(.loose(placement: shot.placement)) }
        .opacity(hands.holds(loose: shot.placement) ? 0.45 : 1)
        .accessibilityIdentifier("loose-\(shot.number)")
    }

    /// **A shoot's head under All Shoots** (piece D): its name, dates and
    /// state; a click folds or opens it. Wrapped shoots start folded.
    private func shootHead(_ group: ShellState.ShootGroup) -> some View {
        let folded = state.shootFolded(group.shoot)
        return Button { state.toggleShootFold(group.shoot) } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Brand.ink3(dark))
                    .rotationEffect(.degrees(folded ? -90 : 0))
                    .frame(width: 10)
                Text(group.shoot.label)
                    .sans(Brand.Size.body, weight: .semibold)
                    .foregroundStyle(Brand.ink(dark))
                    .lineLimit(1)
                    .layoutPriority(1)
                // The dates give way before the name does.
                Text(ShootWords.range(group.shoot.start, group.shoot.end))
                    .sans(Brand.Size.small)
                    .foregroundStyle(Brand.ink3(dark))
                    .lineLimit(1)
                Spacer(minLength: 0)
                ShootTag(shoot: group.shoot)
            }
            .padding(.top, 10).padding(.bottom, 4)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .selectionDisabled()
        .sidebarRow(picked: false, dark: dark)
    }

    /// **A section's head in the list** — its name, small caps, not
    /// selectable, at the top of the panel its scenes sit on. Only where a
    /// section starts; a scene in none gets no head at all. **The name is
    /// drawn in the section's colour, and that is the only place the colour
    /// goes**: not a dot (it read as one more scene's time of day — his
    /// report, 2026-09-20) and not a bar down the panel's edge (*"very GEN
    /// AI"* — his ruling the same night). `design/24-lined-script.html`.
    private func sectionHead(_ section: ViewModel.Sequence?) -> some View {
        HStack(spacing: 8) {
            // The colour goes on before the label style: the modifier nearest
            // the text is the one that paints it.
            Text(section?.title ?? "")
                .foregroundStyle(section.map { Brand.hex($0.colour) } ?? Brand.ink3(dark))
                .fieldLabel(dark)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.top, 8).padding(.bottom, 2)
        .padding(.leading, 12).padding(.trailing, 8)
        .selectionDisabled()
        .sectionPanelRow(edge: .head, picked: false, dark: dark)
        .contentShape(Rectangle())
        // **A section can be recoloured and taken away from where it is
        // drawn.** His asks, 2026-09-19: "i also need to be able to delete
        // sections" and "i also want to be able to choose a sections color".
        // The colours are the eight a section is born with; the swatch and
        // nothing else, as the term menu does. Delete is the same asker
        // Settings uses, so the cost is said the same way everywhere.
        .contextMenu {
            if let section {
                Menu("Color") {
                    ForEach(Array(Brand.chipInks.enumerated()), id: \.offset) { at, hex in
                        Button(Swatches.inkNames[at] + (section.colour.uppercased().hasSuffix(hex) ? "  ✓" : "")) {
                            state.colourSection(section, hex: hex)
                        }
                    }
                }
                Button("Delete Section…") { state.askToDeleteSection(section) }
            }
        }
    }

    /// What a right-click on a scene offers — one scene, or every picked one.
    @ViewBuilder private func sceneMenu(_ scene: ViewModel.Scene) -> some View {
        let acting = state.scenesActedOn(scene.id)
        let many = acting.count > 1
        // **Hide from Diagrams** (his ask, 2026-10-17): the scene leaves the
        // Diagram's list only. On one already hidden (listed again by the
        // "N Hidden" line) the same place says Show.
        if state.sideTab == .diagram {
            if scene.diagramHidden == true {
                Button("Show") { state.hideFromDiagrams(acting.filter { state.diagramHandHidden($0) }, hidden: false) }
            } else {
                Button("Hide from Diagrams") { state.hideFromDiagrams(acting, hidden: true) }
            }
            Divider()
        }
        if !many {
            Button("Edit scene…") { state.editingScene = scene.id }
        }
        Button(exportVerb(acting)) { Exporting.exportScenes(acting, state: state) }
        // **Move to Shoot…** (piece D): only with two or more shoots.
        if state.manyShoots {
            let here = Set(acting.compactMap { id in state.view?.scenes.first { $0.id == id }?.shoot })
            Menu(many ? "Move \(acting.count) Scenes to Shoot" : "Move to Shoot") {
                ForEach(state.shoots) { shoot in
                    Button(shoot.label + (here == [shoot.id] ? "  ✓" : "")) {
                        state.moveScenes(Array(acting), toShoot: shoot)
                    }
                    .disabled(here == [shoot.id])
                }
            }
        }
        Divider()
        // **The no-drag way onto a day.** On the Schedule only, where the
        // days are: pick the day from a list and the scene goes to its end.
        // His report, 2026-09-19 — dragging was "unreliable and messy", and
        // a thing that can only be done by dragging is a thing that
        // sometimes cannot be done.
        if state.sideTab == .schedule, let days = state.stripBoard?.days, !days.isEmpty {
            // A scene partly on a day already: the menu takes its remainder,
            // the same as a drag from here does, and says so.
            let book = state.booking(of: scene)
            let remaining = !many && book.placed > 0 && book.left > 0
            Menu(remaining ? "Schedule Remaining on" : many ? "Day for \(acting.count) scenes" : "Day") {
                ForEach(days) { day in
                    Button(Schedule.dayName(day)) { state.putOnDay(acting, day: day.id) }
                }
                Divider()
                Button("None") { state.putOnDay(acting, day: nil) }
            }
            Divider()
        }
        // **Set the time of day on all of them at once** — his ask,
        // 2026-09-02, and the second reason to pick several: a night shoot is
        // a dozen scenes and each one was its own trip through the editor.
        //
        // The four come from `TimeOfDay.all` rather than being typed here, so
        // this menu and the scene editor's own picker cannot come to offer
        // different lists.
        Menu(many ? "Time of day for \(acting.count) scenes" : "Time of day") {
            ForEach(TimeOfDay.all, id: \.self) { time in
                Button(time) { state.setTimeOfDay(on: acting, to: time) }
            }
            Divider()
            Button("None") { state.setTimeOfDay(on: acting, to: "") }
        }
        // **Set the location on all of them at once** — the reason to pick
        // several scenes in the first place, now that a location can hold
        // rooms: a whole day in one house is a dozen scenes pointing at the
        // same kitchen.
        Menu(many ? "Location for \(acting.count) scenes" : "Location") {
            ForEach(state.view?.locations ?? []) { place in
                Button(place.fullName.isEmpty ? place.name : place.fullName) {
                    state.setLocation(on: acting, to: place.id)
                }
            }
            if !(state.view?.locations ?? []).isEmpty { Divider() }
            Button("None") { state.setLocation(on: acting, to: "") }
        }
        Divider()
        Button(archiveVerb(acting, like: scene)) {
            state.archive(acting, on: !scene.archived)
        }
        // **Only once it is archived** — his ask, 2026-08-22. Archiving is the
        // reversible step and it has to be taken first, so nothing goes from a
        // working list in one click.
        if scene.archived {
            Button("Delete scene…", role: .destructive) { erase(scene) }
        }
    }

    /// What a delete costs, said before it happens — the same shape as
    /// deleting a location or a column.
    private func erase(_ scene: ViewModel.Scene) {
        guard let engine = state.engine else { return }
        let shots = (state.view?.allRows ?? []).filter { $0.sceneId == scene.id }.count
        let ask = NSAlert()
        ask.messageText = "Delete scene \(scene.number)?"
        ask.informativeText = shots == 0
            ? "It has no shots."
            : "\(shots) shot\(shots == 1 ? "" : "s") go\(shots == 1 ? "es" : "") with it."
        ask.addButton(withTitle: "Delete")
        ask.addButton(withTitle: "Cancel")
        ask.alertStyle = .warning
        guard ask.runModal() == .alertFirstButtonReturn else { return }
        if state.sceneId == scene.id { state.sceneId = nil }
        state.pickedScenes.remove(scene.id)
        state.replace(engine.deleteScene(scene.id))
    }

    /// `Archive scene` / `Archive 4 scenes`, following whichever scene was
    /// clicked — so a mixed selection does what the one under the cursor says,
    /// rather than toggling each and leaving the set as mixed as it started.
    private func archiveVerb(_ acting: [String], like scene: ViewModel.Scene) -> String {
        let verb = scene.archived ? "Unarchive" : "Archive"
        return acting.count == 1 ? "\(verb) scene" : "\(verb) \(acting.count) scenes"
    }

    /// `Export scene…` / `Export 4 scenes…`.
    private func exportVerb(_ acting: [String]) -> String {
        acting.count == 1 ? "Export scene…" : "Export \(acting.count) scenes…"
    }

}

// ------------------------------------------------------------------ content

struct Content: View {
    @ObservedObject var state: ShellState
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        ZStack {
            Brand.surface(dark).ignoresSafeArea()
            // **No mode on** (stage 5 step 4 B): one line, and + in the bar.
            if state.modesShown.isEmpty {
                EmptyState(title: "No modes on") {
                    Menu("+ Turn On a Mode") {
                        ForEach(SideTab.allCases) { mode in
                            Button(mode.title) { state.setMode(mode, on: true) }
                        }
                    }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
            switch state.sideTab {
            case .scenes:
                VStack(spacing: 0) {
                    DriveDraftBanner(state: state)
                    scene
                }
            case .locations: locations
            case .boards: boards
            // **In from the cold, 2026-08-23.** The strip board had been a
            // mode all along — a view of the whole film, exactly like the list
            // of locations is — and the only one reachable nowhere but ⌘4 and
            // a window of its own. `Schedule` already took nothing but the
            // state, so bringing it in was a line. ⌘4 still opens it, and the
            // window is still there for anyone who wants it beside the table:
            // "Open in New Window" now does that for every mode, not just this
            // one.
            case .schedule: Schedule(state: state)
            // The fifth mode, 2026-09-26: an overhead of the picked scene.
            case .diagram: DiagramMode(state: state)
            }
            }
        }
        // **A short line when the modes changed under him** (step 4 B): the
        // open mode was turned off elsewhere, or a change did not go. Over
        // the content, under the bar, gone by itself.
        .overlay(alignment: .top) {
            if let line = state.modeNote {
                Text(line)
                    .sans(Brand.Size.body)
                    .foregroundStyle(Brand.ink(dark))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background {
                        Capsule(style: .continuous).fill(Brand.surface2(dark))
                            .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
                    }
                    .padding(.top, 10)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: state.modeNote)
    }

    /// The Boards tab: one wall filling the window, or an invitation.
    @ViewBuilder private var boards: some View {
        if let board = state.board {
            BoardWall(state: state, board: board)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyState(title: "No reference boards yet") {
                Button("+ Add reference board…") { state.addingBoard = true }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The Locations tab: one record filling the window, or an invitation —
    /// with a line across the top whenever the phone has left something in the
    /// project folder that nobody has brought in yet.
    @ViewBuilder private var locations: some View {
        VStack(spacing: 0) {
            Homecoming(state: state)
            locationBody
        }
    }

    @ViewBuilder private var locationBody: some View {
        if let place = state.location {
            LocationPage(state: state, place: place)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyState(title: "No locations yet") {
                Button("+ Add location…") { state.addingLocation = true }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var scene: some View {
        if let scene = state.scene {
            // **No heading strip.** Everything it said now lives in the
            // scene's own band inside the table, at the scene it describes —
            // his ask, and it takes a whole redraw off every scroll tick.
            body(scene)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyState(title: "No scenes yet") {
                // **A script first.** This said *Add scene* and *Open
                // project* and nothing else, and his finding was the plain
                // one: *"there's no way to import a script on a blank
                // project."* There was — a menu item — but a menu item is not
                // a way if nobody has a reason to look in the menu.
                HStack(spacing: 10) {
                    // A commercial's script is pasted, not imported — and it
                    // may be nothing at all, which is why Add scene stands
                    // beside it at the same weight.
                    if state.view?.project.isCommercial == true {
                        Button("+ Paste script…") { state.pastingScript = true }
                            .buttonStyle(.primary)
                    } else {
                        Button("+ Import script…") { ScriptImport.pick(state: state) }
                            .buttonStyle(.primary)
                    }
                    Button("+ Add scene…") { state.addingScene = true }
                    Button("Open project…") { state.browsing = true }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private func body(_ scene: ViewModel.Scene) -> some View {
        surface(scene)
    }

    /// The bar over the storyboard and the document: the views, and then —
    /// on the storyboard — a line saying which scene.
    ///
    /// **One bar per view, never two.** The shot list carries its views inside
    /// the filter bar it already had; these two had no bar of their own, so
    /// this is it. The scene's name is here because the storyboard shows *one*
    /// scene and nothing else on that screen says which; the table needs no
    /// such line, since every scene wears its own band inside it.
    private func viewLine(_ scene: ViewModel.Scene, naming: Bool) -> some View {
        HStack(spacing: 10) {
            ViewBar(selection: $state.tab)
            if naming {
                Brand.rule(dark).frame(width: 1, height: 20)
                Text(scene.number).sans(Brand.Size.title, weight: .semibold).monospacedDigit()
                    .foregroundStyle(Brand.ink(dark))
                Text(scene.title.isEmpty ? scene.heading : scene.title)
                    .sans(Brand.Size.title, weight: .semibold)
                    .foregroundStyle(Brand.ink(dark))
                    .lineLimit(1)
                let shots = state.rows(of: scene.id).count
                Text(shots == 1 ? "1 shot" : "\(shots) shots")
                    .sans(Brand.Size.small, weight: .medium)
                    .foregroundStyle(Brand.ink3(dark))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        // No ground of its own, the same as the filter bar — see the note
        // there. The window's rule is that only floating things have edges.
    }

    @ViewBuilder private func surface(_ scene: ViewModel.Scene) -> some View {
        Group {
            switch state.tab {
            case .shots:
                // The filter bar belongs to the shot list alone: it narrows
                // shots, and the other surfaces show a scene's own things
                // rather than a run of shots to sift. It floats on the ground
                // above the table rather than being a strip bolted to it.
                // **The well has square corners and fills its column.**
                //
                // His correction, and he is right: with the table rounded
                // *and* the panels rounded, the ground left between them read
                // as a hard rectangle drawn round the sidebar — two rounded
                // things with a sharp gap between them, which is the worst of
                // both. One rule instead: the content is a well cut straight
                // into the window, edge to edge, and everything that *floats*
                // is what turns a corner.
                VStack(spacing: 0) {
                    FilterBar(state: state)
                    ShotTable(state: state, scene: scene)
                }
                .background(Brand.surface(dark))
            case .storyboard:
                VStack(spacing: 0) {
                    viewLine(scene, naming: true)
                    StoryboardView(state: state, scene: scene)
                }
                .background(Brand.surface(dark))
            case .document:
                VStack(spacing: 0) {
                    viewLine(scene, naming: false)
                    DocumentTab(state: state, scene: scene)
                }
                .background(Brand.surface(dark))
            }
        }
        // The quiet sentence and the held-back banner live over whichever tab
        // is open — a viewfinder read on the storyboard deserves its line as
        // much as one at the table.
        .overlay(alignment: .bottom) {
            if let notice = state.notice {
                Text(notice)
                    .sans(13)
                    .foregroundStyle(Brand.onImage)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.78)))
                    .padding(.bottom, 52)
                    .transition(.opacity)
            }
            // Two machines decided the same thing differently while apart.
            // Nothing was lost — both values are in the log — but one of them
            // is only in the log, and a person should get to look. Said once,
            // on the ground of the tab, in the same place as the other
            // sentences the app speaks.
            ClashBanner(state: state)
            // **The Spec Sheet changed** — a film switched to Ask (2026-10-13).
            // What changed, and Take. Nothing is taken until he says.
            SpecSheetAsk(state: state)
            if let held = state.heldBack {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11))
                    Text("Undo left \(held.skipped ?? 0) newer "
                         + "change\((held.skipped ?? 0) == 1 ? "" : "s") "
                         + "from another device in place")
                        .sans(13)
                    Button("OK") { state.heldBack = nil }
                        .buttonStyle(.plain)
                        .sans(13, weight: .semibold)
                }
                .foregroundStyle(Brand.onImage)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Capsule().fill(Brand.hex("9A6B10")))
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // The frames window is a real floating window (`FramesWindow`), not
        // a sheet — his call: movable, resizable, never a takeover.
    }
}

/// The preference store, with one rule: **a checking run never writes.**
///
/// Reading is fine and useful — a check that opens the app should see the app
/// as he left it. Writing is theft: the run ends, the scratch project is
/// deleted, and whatever it stamped into his preferences outlives it.
struct Remembering {
    private let store = UserDefaults.standard

    func set(_ value: Any?, forKey key: String) {
        guard !Launch.checking else { return }
        store.set(value, forKey: key)
    }
    func string(forKey key: String) -> String? { store.string(forKey: key) }
    func bool(forKey key: String) -> Bool { store.bool(forKey: key) }
    func double(forKey key: String) -> Double { store.double(forKey: key) }
    func object(forKey key: String) -> Any? { store.object(forKey: key) }
    func dictionary(forKey key: String) -> [String: Any]? { store.dictionary(forKey: key) }
    func removeObject(forKey key: String) { 
        guard !Launch.checking else { return }
        store.removeObject(forKey: key)
    }
}

/// A small capital word in the top bar, beside the film's name — the film's
/// kind, or the program's flavour.
struct ChromeTag: View {
    let word: String
    let accent: Bool
    #if SHOTLISTER_LABS
    static let labs = true
    #else
    static let labs = false
    #endif
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }
    var body: some View {
        // `fixedSize`: a tag is one line at its own width, never wrapped.
        // One look: a status word is the kit's neutral tag.
        Text(word).sans(Kit.Size.tag, weight: .semibold)
            .lineLimit(1)
            .foregroundStyle(accent ? Brand.onAccent(dark) : Brand.ink2(dark))
            .padding(.horizontal, Kit.tagPadH).padding(.vertical, Kit.tagPadV)
            .background(RoundedRectangle(cornerRadius: Brand.radiusChip, style: .continuous)
                .fill(accent ? Brand.accent(dark) : Brand.cellHover(dark)))
            .fixedSize()
    }
}

/// **Two machines decided the same thing differently while apart.** Nothing
/// was lost — both values are in the log — so each row offers both: keep what
/// is on screen, or use the other. A long value (a whole list of lenses) is
/// cut to two lines on its button and shown whole on hover; it used to be
/// laid out at full width and squeezed the rest into a one-letter column.
struct ClashBanner: View {
    @ObservedObject var state: ShellState
    /// Put aside for now, until something new is decided twice.
    @State private var later: [Engine.Pull.Clash] = []

    var body: some View {
        if !state.clashes.isEmpty && state.clashes != later {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 11))
                    Text(state.clashes.count == 1
                         ? "Changed on Two Machines"
                         : "\(state.clashes.count) Changed on Two Machines")
                        .sans(13, weight: .semibold)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if state.clashes.count > 1 {
                        Button("Keep All") { state.settleClashes() }
                            .buttonStyle(.plain)
                            .sans(11, weight: .semibold)
                            .fixedSize()
                    }
                    Button("Later") { later = state.clashes }
                        .buttonStyle(.plain)
                        .sans(11)
                        .opacity(0.8)
                        .fixedSize()
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(state.clashes, id: \.self) { clash in
                            row(clash)
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 280)
                .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Brand.onImage)
            .frame(width: 440, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Brand.radius).fill(Brand.hex("2C5AA0")))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func row(_ clash: Engine.Pull.Clash) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name(clash))
                .sans(11, weight: .semibold)
                .lineLimit(1)
                .truncationMode(.tail)
                .opacity(0.85)
            HStack(alignment: .top, spacing: 8) {
                choice("Keep", clash.kept) { state.keepMineValue(clash) }
                if !clash.other.isEmpty {
                    choice("Use", clash.other) { state.takeOtherValue(clash) }
                }
            }
        }
    }

    /// One answer: the verb, then the value it sets.
    private func choice(_ verb: String, _ value: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verb).sans(10, weight: .semibold).opacity(0.75)
                Text(value.isEmpty ? "Nothing" : value)
                    .sans(11)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.14)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(value)
    }

    /// "Shot 2 · Lens" — the record from the engine's own sentence, the field
    /// by its name.
    private func name(_ clash: Engine.Pull.Clash) -> String {
        let what = clash.said.components(separatedBy: " — ").first ?? ""
        var field = clash.field.replacingOccurrences(of: "_", with: " ").capitalized
        // A pick list's own words ("vocab_lens") are the Lens List.
        if field.hasPrefix("Vocab ") { field = String(field.dropFirst(6)) + " List" }
        return what.isEmpty ? field : "\(what) · \(field)"
    }
}


// ------------------------------------------------------------------ a draft in Drive

/// **New draft in Drive** (stage 5 step 4, piece C; mockup screen 6). The
/// server noticed a newer PDF in the project's `1-creative/script/current-draft/`
/// than the draft in use. Nothing is imported by itself: Review… opens the
/// import's review, and until he imports it every app keeps the draft in use.
/// More than one draft in that folder: **Pick the current draft**, never guessed.
struct DriveDraftBanner: View {
    @ObservedObject var state: ShellState
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        let relay = state.projectPath.flatMap { Relay.projectId(at: $0) }
        let _ = state.scriptStamp
        if let found = ProjectCards.shared.draftChoices(film: relay, page: state.view?.project.consolePage ?? "") {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.doc").font(.system(size: 13))
                    .foregroundStyle(Brand.accent(dark))
                VStack(alignment: .leading, spacing: 2) {
                    (Text("Pick the current draft: ").fontWeight(.semibold) + Text("\(found.choices.count) in Drive"))
                        .sans(13).foregroundStyle(Brand.ink(dark))
                        .lineLimit(1).truncationMode(.middle)
                    Text(["1-creative/script/current-draft/", found.card.script.map { $0.label.isEmpty ? "" : "using \($0.label)" } ?? ""]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .sans(11).foregroundStyle(Brand.ink3(dark))
                        .lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 0)
                Menu(state.fetchingDraft ? "Getting It…" : "Pick…") {
                    ForEach(found.choices, id: \.file) { choice in
                        Button(choice.same == true ? "\(choice.label) (in use)" : choice.label) { state.pickDriveDraft(choice) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(state.fetchingDraft)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Brand.accentTint(dark))
            .onAppear {
                if Launch.checking {
                    FileHandle.standardError.write(Data("drive draft pick banner: \(found.choices.map(\.label).joined(separator: " | ")) using \(found.card.script?.label ?? "")\n".utf8))
                }
            }
        } else if let found = ProjectCards.shared.draftInDrive(film: relay, page: state.view?.project.consolePage ?? "") {
            HStack(spacing: 10) {
                Image(systemName: "doc.text").font(.system(size: 13))
                    .foregroundStyle(Brand.accent(dark))
                VStack(alignment: .leading, spacing: 2) {
                    (Text("New draft in Drive: ").fontWeight(.semibold) + Text(found.waiting.label))
                        .sans(13).foregroundStyle(Brand.ink(dark))
                        .lineLimit(1).truncationMode(.middle)
                    Text(["1-creative/script/current-draft/", found.card.script.map { $0.label.isEmpty ? "" : "using \($0.label)" } ?? ""]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .sans(11).foregroundStyle(Brand.ink3(dark))
                        .lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 0)
                Button(state.fetchingDraft ? "Getting It…" : "Review…") { state.reviewDriveDraft() }
                    .buttonStyle(.primary)
                    .disabled(state.fetchingDraft)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Brand.accentTint(dark))
            .onAppear {
                if Launch.checking {
                    FileHandle.standardError.write(Data("drive draft banner: \(found.waiting.label) using \(found.card.script?.label ?? "")\n".utf8))
                }
            }
        }
    }
}
