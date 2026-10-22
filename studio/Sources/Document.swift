import AppKit
import SwiftUI

/// The page — ours, not Cadrage's.
///
/// The same list as the table, read as a document: the scene is a heading, a
/// shot is a paragraph with its frames, and the technical line sits under the
/// words in the order the table's columns are in. Ported from the old app's
/// `DocumentView`, whose reading this keeps unchanged; the one deliberate
/// difference is scope — the shell works one scene at a time, so the page
/// shows the scene that is open rather than the whole film.
///
/// What is editable here writes through the same engine paths as everywhere
/// else: the words (with their emphasis, stored beside the plain text), the
/// note under them, the technical line's own fields (the old page's combo
/// fields, ported), and the frames' side and size — the side by dragging the
/// frame itself where it should sit.
/// One editable place on the page. Tab's whole job is to walk these in
/// reading order: title, words, each technical field in the table's column
/// order, then the note — and on to the next shot.
/// **The page's measurements, in one place** — Ref 53.
///
/// His report: *"right now the formatting is way too big — very little
/// information per sheet. font and text are too large right now."* He was
/// right, and the number that says so is the body: it was **13.5 point on a
/// Letter page**, which is a large-print book, not a shot list. His own
/// exported shot lists — the StudioBinder one for *Alone*, the storyboarder.ai
/// one for *Son of a Bikram* — set their body between nine and ten and fit ten
/// to fifteen shots on a sheet. This page fitted between two and three.
///
/// So the scale lives here rather than scattered through the file as forty
/// literals, because the next time it is wrong it should be one edit and not a
/// hunt. **Everything is in points on a 612 × 792 page**, which is what the
/// PDF will be, so what is set here is what prints.
///
/// ## And that is now literally true — `engine/src/export/html.rs`, `mod doc`
///
/// His instruction, 2026-09-01: *"Whatever I see in the document view in the
/// app, should be reflected in the export."* Every number below has a twin in
/// `doc` over in the engine, which is what the printed stylesheet is written
/// from, and the export dialog's 100% means exactly these points. **If one
/// moves, the other moves.** `engine/tests/export.rs` proves the Rust half
/// reaches the stylesheet; nothing can prove this half from there, so it is on
/// whoever edits this file.
enum Page {
    /// US Letter, portrait, at 72 points to the inch — his call: *"the paper
    /// size should just be standard Letter no matter what."*
    static let paperWidth: CGFloat = 612
    static let paperHeight: CGFloat = 792
    /// One inch all round. `Printing.Kind.document.margin` is this number, and
    /// so is `doc::MARGIN`.
    static let margin: CGFloat = 72

    /// The words of a shot. The one number that decides how much fits.
    static let body: CGFloat = 10.5
    /// The short name over the sentence — the body, one point up, bold.
    static let title: CGFloat = 11.5
    /// The number in the margin — a landmark, not a heading.
    static let shotNumber: CGFloat = 9
    /// Size · angle · movement · lens · equipment, under the words.
    static let technical: CGFloat = 8.5
    static let notes: CGFloat = 11.5
    static let sceneNumber: CGFloat = 10.5
    static let sceneHeading: CGFloat = 11
    static let sheetTitle: CGFloat = 13
    /// The small capitals: SHOT LIST, 5 SHOTS, the credits under the title.
    static let caption: CGFloat = 8

    /// The margin the shot numbers hang in, taken out of the measure.
    static let gutter: CGFloat = 60
    /// Between the number, the frame and the words.
    static let besideFrame: CGFloat = 9
    /// Between a frame and the words when the frame is above or below them.
    static let underFrame: CGFloat = 6
    /// **Between one shot and the next.** At 14 it was 28 points of air
    /// between shots — a third of an inch, for nothing. Hung under a shot
    /// only, never over it, so a shot that lands at the top of a page starts
    /// at the top of the page the way the printed one does.
    static let betweenShots: CGFloat = 5
    /// Over a scene heading. Under it, `betweenShots * 2`, same as a shot.
    static let overScene: CGFloat = 13
    /// Between the title, the words, the technical line and the note.
    static let withinShot: CGFloat = 3

    /// What is left for the words once the margins and the number column are
    /// out of the way — 408 points, and the width every frame's own fraction
    /// is a fraction *of*, on the page and on paper alike.
    static var measure: CGFloat { paperWidth - margin * 2 - gutter }
    /// The whole text column, number included.
    static var column: CGFloat { paperWidth - margin * 2 }
    /// How much of a sheet a page's content may fill.
    static var usable: CGFloat { paperHeight - margin * 2 }
}

/// **How this film's page is set** — the engine's answer, ready to draw with.
///
/// His ask, 2026-09-02: the resizing belongs in the document view, and the
/// page wants real text classes with their own size, font and case.
///
/// Every number here used to be a constant in `Page` above *and* a constant in
/// the engine's stylesheet, with a note on each saying "if one moves, the other
/// moves". Now the engine owns them and this reads them, so the page on screen
/// and the page that prints cannot drift.
///
/// **The constants in `Page` are still the fallback**, for a film opened by an
/// engine too old to have an opinion — it draws what it has always drawn.
struct PageType: Equatable {
    private let byClass: [String: ViewModel.TextClass]

    static func == (a: PageType, b: PageType) -> Bool { a.byClass == b.byClass }

    init(_ project: ViewModel.Project?) {
        byClass = Dictionary(
            (project?.docStyle ?? []).map { ($0.class, $0) },
            uniquingKeysWith: { _, last in last })
    }

    /// The nine names, as the engine spells them. Written here so a typo is a
    /// compile error rather than a silently unstyled line.
    enum Kind: String, CaseIterable {
        case sheetTitle = "sheet_title"
        case credits
        case sceneHeading = "scene_heading"
        case sceneNumber = "scene_number"
        case shotTitle = "shot_title"
        case body, technical, notes
        case shotNumber = "shot_number"

        /// What this class was before it could be changed.
        var standardSize: CGFloat {
            switch self {
            case .sheetTitle: return Page.sheetTitle
            case .credits: return Page.caption
            case .sceneHeading: return Page.sceneHeading
            case .sceneNumber: return Page.sceneNumber
            case .shotTitle: return Page.title
            case .body: return Page.body
            case .technical: return Page.technical
            case .notes: return Page.notes
            case .shotNumber: return Page.shotNumber
            }
        }

        var standardFace: String {
            switch self {
            case .sheetTitle, .sceneHeading: return "sans"
            case .credits, .sceneNumber, .technical, .shotNumber: return "mono"
            case .shotTitle, .body, .notes: return "serif"
            }
        }

        var standardCase: String { self == .credits ? "upper" : "as" }

        /// **The ink it has always been drawn in.** Six hex digits, the way
        /// the engine spells them — `docstyle::standard` is the only real
        /// owner, and these are the fallback for a film opened by an engine
        /// too old to have an opinion.
        var standardColour: String {
            switch self {
            case .credits, .technical, .notes: return "5c5c63"
            default: return "17171a"
            }
        }

        /// What he sees. **A label names the thing** — the app's own law.
        var label: String {
            switch self {
            case .sheetTitle: return "Title"
            case .credits: return "Credits"
            case .sceneHeading: return "Scene Heading"
            case .sceneNumber: return "Scene Number"
            case .shotTitle: return "Shot Title"
            case .body: return "Body"
            case .technical: return "Technical Line"
            case .notes: return "Notes"
            case .shotNumber: return "Shot number"
            }
        }

        /// **Whether a case may be forced on this class.**
        ///
        /// Not on the three he types into. A page that draws WHAT HE TYPED
        /// while the file holds what he typed is a page disagreeing with
        /// itself, and the moment he edits that line he is looking at letters
        /// he never wrote. The engine refuses one on these too, so the panel
        /// is not the only thing holding the line.
        var takesCase: Bool {
            switch self {
            case .shotTitle, .body, .notes: return false
            default: return true
            }
        }
    }

    func size(_ kind: Kind) -> CGFloat {
        byClass[kind.rawValue].map { CGFloat($0.size) } ?? kind.standardSize
    }

    func face(_ kind: Kind) -> String {
        byClass[kind.rawValue]?.face ?? kind.standardFace
    }

    func casing(_ kind: Kind) -> String {
        byClass[kind.rawValue]?.case ?? kind.standardCase
    }

    /// The ink, as the engine spells it.
    func hex(_ kind: Kind) -> String {
        let said = byClass[kind.rawValue]?.colour ?? ""
        return said.isEmpty ? kind.standardColour : said
    }

    /// The ink, ready to draw with.
    func colour(_ kind: Kind) -> Color { Brand.hex(hex(kind)) }
    func nsColour(_ kind: Kind) -> NSColor { Brand.nsHex(hex(kind)) }

    /// The words, as this class asks for them.
    func cased(_ words: String, _ kind: Kind) -> String {
        switch casing(kind) {
        case "upper": return words.uppercased()
        case "lower": return words.lowercased()
        default: return words
        }
    }

    /// What he last set it to, for the panel to show — or the standard.
    func setting(_ kind: Kind)
        -> (size: CGFloat, face: String, case: String, colour: String) {
        (size(kind), face(kind), casing(kind), hex(kind))
    }

    /// Whether anything on this page has been moved off the standard, so the
    /// panel can offer to put it back and not otherwise.
    var touched: Bool {
        Kind.allCases.contains { kind in
            let one = setting(kind)
            return one.size != kind.standardSize
                || one.face != kind.standardFace
                || one.case != kind.standardCase
                || one.colour != kind.standardColour
        }
    }
}

/// **The inks the page offers.**
///
/// His ask, 2026-09-03: *"we should include font color as an option across the
/// board"*. A short named list rather than the system colour wheel, for the
/// same reason there are three faces and not four hundred: this page gets
/// printed, and an ink he can name and pick again next film is worth more than
/// one he has to match by eye. Every one of them reads on white at eight point.
///
/// The engine stores six hex digits and knows nothing about these names — so
/// the list can grow without anything on disk having to change.
enum Inks {
    static let all: [(name: String, hex: String)] = [
        ("Black", "17171a"),
        ("Graphite", "3a3a40"),
        ("Grey", "5c5c63"),
        ("Silver", "8c8c94"),
        ("Red", "b3261e"),
        ("Rust", "9a5216"),
        ("Green", "2c6b41"),
        ("Teal", "1e6a6a"),
        ("Blue", "1f4e9c"),
        ("Purple", "5a3a9c"),
    ]

    /// The hex, lower-cased the way the engine writes it — so a colour that
    /// arrives as `17171A` still finds its name in the list.
    static func known(_ hex: String) -> String { hex.lowercased() }

    static func name(of hex: String) -> String {
        all.first { $0.hex == known(hex) }?.name ?? "Custom"
    }
}

extension View {
    /// One class's face and size, in one place — so a call site cannot ask for
    /// the size from the engine and the family from a habit.
    func faced(_ face: String, _ size: CGFloat,
               weight: Font.Weight = .regular, tracking: CGFloat = 0) -> some View {
        let design: Font.Design
        switch face {
        case "mono": design = .monospaced
        case "serif": design = .serif
        default: design = .default
        }
        return font(.system(size: size, weight: weight, design: design))
            .tracking(tracking)
    }
}

/// The same choice for AppKit, where the words live in a text view rather than
/// a `Text` — the shot's title, its sentence and its note.
enum Faces {
    /// **Worked out once per face and size.**
    ///
    /// Asking the system for a designed font is three trips — a system font, a
    /// descriptor `withDesign`, and sometimes an italic conversion — and it was
    /// happening for the title and the note of every shot on every pass. Nine
    /// classes and a handful of sizes is the whole of what this ever holds.
    private static let made = Memo<String, NSFont>()

    static func font(_ face: String, size: CGFloat, bold: Bool = false,
                     italic: Bool = false) -> NSFont {
        made.value(for: "\(face)|\(size)|\(bold)|\(italic)") { _ in
            build(face, size: size, bold: bold, italic: italic)
        }
    }

    private static func build(_ face: String, size: CGFloat, bold: Bool,
                              italic: Bool) -> NSFont {
        let base = bold
            ? NSFont.boldSystemFont(ofSize: size)
            : NSFont.systemFont(ofSize: size)
        let design: NSFontDescriptor.SystemDesign
        switch face {
        case "mono": design = .monospaced
        case "serif": design = .serif
        default: design = .default
        }
        var font = base
        if let described = base.fontDescriptor.withDesign(design),
           let made = NSFont(descriptor: described, size: size) {
            font = made
        }
        if italic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        return font
    }
}

/// **One thing on the page that a break must never cut in two.**
///
/// The printed page says the same thing in CSS (`break-inside: avoid` on a
/// shot, `break-after: avoid` on a heading) and `Printing.pageBreaks` honours
/// it by measuring the real blocks in the web view. This is the same list, in
/// the same order, so the sheets on screen fall where the sheets on paper do.
enum Slab: Hashable, Identifiable {
    case head
    /// A section's chapter head, keyed by the first scene of its run.
    case section(String)
    case scene(String)
    case shot(String)
    var id: Self { self }
}

/// How tall each of them came out. Measured where it is drawn, because a
/// second hidden copy of the document would mean two of every text view and
/// the caret could only be in one of them.
struct SlabHeights: PreferenceKey {
    static let defaultValue: [Slab: CGFloat] = [:]
    static func reduce(value: inout [Slab: CGFloat], nextValue: () -> [Slab: CGFloat]) {
        value.merge(nextValue()) { _, mine in mine }
    }
}

/// **How big a frame may be, where it is.** One rule, one place.
///
/// Beside the words a frame past ~55% of the measure crushes the text into a
/// sliver, and the reflow makes every pixel of a drag feel like three — the
/// touchiness he named. Above or below, the whole measure is fair game. Every
/// menu item, every drag and every drop asks here rather than each remembering
/// its own number, which is how two of them came to disagree.
enum Layouts {
    static func ceiling(on position: String) -> Double {
        ["left", "right"].contains(position) ? 0.55 : 1.0
    }

    static func clamp(_ width: Double, on position: String) -> Double {
        min(ceiling(on: position), max(0.1, width))
    }

    /// **How much of the measure a frame takes** — his ask, 2026-09-01:
    /// *"More global sizing options, half size, quarter size."* A fraction, so
    /// the page keeps its shape whatever the paper is, and the same fraction
    /// the printed page reads.
    static let sizes: [(String, Double)] = [
        ("Full width", 1.0),
        ("Two thirds", 0.66),
        ("Half", 0.5),
        ("A third", 0.34),
        ("A quarter", 0.25),
        ("Thumbnail", 0.15),
    ]

    /// **Where it sits.** Four places, because a frame above the words reads
    /// differently from one below them, and which side it takes changes how
    /// the page scans.
    static let places: [(String, String)] = [
        ("Above the text", "above"),
        ("Below the text", "below"),
        ("Left of the text", "left"),
        ("Right of the text", "right"),
    ]

    /// Left, right, left — the magazine spread, keeping each frame's own size.
    static func alternating(_ at: Int, width: Double) -> (String, Double) {
        let side = at.isMultiple(of: 2) ? "left" : "right"
        return (side, clamp(width, on: side))
    }

    /// **Mix it up** — his words. Not random: the same shots always come out
    /// the same way, so it can be undone, checked, and asked for twice
    /// without the page moving underneath him. A four-beat pattern that reads
    /// like a laid-out document rather than a list — two beside the words at a
    /// third, one full-width plate, one half-width above.
    static let mixture: [(String, Double)] = [
        ("left", 0.34), ("below", 1.0), ("right", 0.34), ("above", 0.5),
    ]

    static func mixed(_ at: Int) -> (String, Double) {
        mixture[at % mixture.count]
    }
}

enum PagePart: Hashable {
    case title, words, note
    case field(String)
}

/// A one-shot instruction: "put the keyboard here." Set by Tab (or anything
/// that moves focus by name), consumed by the view that takes the keyboard,
/// then cleared — clicks never touch it, because a click IS the focus move.
struct PageFocus: Equatable {
    let shot: String
    let part: PagePart
}

struct DocumentTab: View {
    @ObservedObject var state: ShellState
    /// Whether the type strip is showing.
    @State private var settingType = false
    /// Which kind of words the strip is setting. **One at a time** — nine rows
    /// of three controls is a panel, and a panel over the page is the one
    /// thing this view cannot afford: it *is* the preview.
    @State private var typeClass: PageType.Kind = .body
    let scene: ViewModel.Scene
    @Environment(\.colorScheme) private var scheme

    /// **Letter, always** — his call: *"the paper size should just be standard
    /// Letter no matter what."* 8½ × 11 inches is 612 × 792 points at 72 to
    /// the inch, with one-inch margins. The measure slider went with it: a
    /// document you can stretch is not a document, it is a panel.
    static let paperWidth: CGFloat = Page.paperWidth
    static let margin: CGFloat = Page.margin
    /// What is left for the words once the margins and the number column are
    /// out of the way.
    private var measure: CGFloat { Page.measure }
    /// How tall each block came out, so the sheets can be cut where the
    /// printed ones are. Filled in by the blocks themselves as they draw.
    @State private var heights: [Slab: CGFloat] = [:]
    /// When a PDF made now would say it was made. Drawn in the foot of every
    /// sheet, because `Printing.Footered` stamps exactly that on the export.
    @State private var stamped = Date()
    @State private var focused: NSTextView?
    @State private var focusedShot: String?
    @State private var focus: PageFocus?
    /// The page's key watcher — **one for the app, not one per drawing of
    /// the view.** It was view state, and SwiftUI can bring the new page on
    /// before it takes the old one off: the new one's watcher went in, then
    /// the old one's departure took *that* watcher out, and the page stopped
    /// answering for Tab and ⌘↩ with nothing to show for it. Now the watcher
    /// goes only when the last page showing has gone.
    private static var watcher: Any?
    private static var showing = 0
    /// Where ⇧↑ ⇧↓ reach from: the shot a keyboard pick began on.
    @State private var reachFrom: String?
    /// "Bring this shot into view" — asked by the keys that move to a shot
    /// (arrows, Return, a new shot). Counted, so asking twice for the same
    /// shot still asks. A click never asks: the shot is already under the
    /// hand, and scrolling it would move it out from under the pointer.
    @State private var follow = Follow()
    struct Follow: Equatable {
        var shot: String?
        var count = 0
    }

    private var dark: Bool { scheme == .dark }

    /// **The page is white, whatever the app is wearing.**
    ///
    /// His instruction, 2026-09-03: *"the color of the document page should be
    /// white given that it will be printed on white in the export."* A dark
    /// page here and a white one in the exporter is the same document drawn
    /// two ways, and the whole point of this view is that it is the page.
    ///
    /// So everything **on the paper** is drawn light — the sheet, its ink, its
    /// chips, its selection. Everything **around** the paper follows the app:
    /// the desk it lies on, the toolbar over it, the sidebar beside it.
    private let onPaper = false

    /// **How this film's page is set.** Rebuilt whenever the view model
    /// changes, which is what makes a change in the panel land on the page as
    /// he makes it.
    private var type: PageType { PageType(state.view?.project) }
    /// **The words of a shot are Body**, so the page's ink is Body's ink. It
    /// used to be white on a dark page and black on a light one; the page is
    /// white now, and the colour is his to set per class.
    private var ink: NSColor { type.nsColour(.body) }

    /// The page's face.
    ///
    /// **By design, not by name.** This asked for `NSFont(name: "New York")`
    /// and `NSFont(name: "SF Pro Text")` — and *neither of those resolves*, so
    /// both fell through to the same system font and the Serif/Sans switch had
    /// never once changed a letter on the page. Half of his "the text editor
    /// doesn't seem to affect any of the text" was this; the other half was
    /// that a change to the face never reached words already written.
    /// `withDesign` is the supported way to ask the system for its serif.
    private var bodyFont: NSFont {
        Faces.font(type.face(.body), size: type.size(.body))
    }

    private var rows: [ViewModel.Row] {
        state.view?.allRows.filter { $0.sceneId == scene.id } ?? []
    }

    /// Which parts the technical line is made of, in the order the table has
    /// its columns in — his rule: the document follows the table, not its own
    /// order.
    private var technicalFields: [String] {
        let technical = ["size", "angle", "movement", "lens", "support"]
        // Filters and Modifiers are not columns any more; the page still
        // draws and edits them, straight after the lens.
        return (state.view?.columns ?? [])
            .filter { $0.visible && technical.contains($0.name) }
            .flatMap { $0.name == "lens" ? ["lens", "modifiers", "lens_filters"] : [$0.name] }
    }

    var body: some View {
        VStack(spacing: 0) {
            formattingBar
            if settingType || state.showTypePanel { typeStrip }
            page
        }
        .onAppear {
            Self.showing += 1
            watchTab()
        }
        .onDisappear {
            Self.showing -= 1
            guard Self.showing <= 0 else { return }
            Self.showing = 0
            if let watcher = Self.watcher { NSEvent.removeMonitor(watcher) }
            Self.watcher = nil
            PageKeys.page = nil
        }
        // The watcher holds this view as it was when it was made; a new
        // scene makes a new one.
        .onChange(of: scene.id) { _, _ in watchTab() }
        .onChange(of: focus) { _, now in
            PageProbe.part = now.map { "\($0.part)" } ?? "-"
        }
    }

    /// Tab belongs to the page for as long as the page holds the caret.
    ///
    /// Each line and field handles its own Tab while it has the keyboard.
    /// But between one part giving it up and the next taking it there is an
    /// instant when nobody on the page is the first responder — and a Tab
    /// arriving in that instant is handled by AppKit's own key-view loop,
    /// which walked out of the document entirely and pressed the sidebar's
    /// "+" (a dialog asking for a new scene number, mid-sentence). The page
    /// knows where its caret is even when no view is holding it, so it
    /// answers for Tab itself in that gap.
    private func watchTab() {
        // Always replaced, so the watcher holds the page as it is now.
        if let watcher = Self.watcher { NSEvent.removeMonitor(watcher) }
        let watch: (NSEvent) -> NSEvent? = { event in
            let responder = event.window?.firstResponder
            // A text FIELD is never the first responder — the window's field
            // editor is, on its behalf, with the field as its delegate. Asking
            // `responder is ClaimField` therefore always said no, so an open
            // picker looked like "nobody is typing" and this monitor advanced
            // the caret a second time on top of the field's own Tab: two
            // fields skipped per press, which is what made the walk land in
            // the wrong place.
            let editor = responder as? NSTextView
            let typing = responder is GrowText
                || editor?.delegate is FieldFilter.ClaimField
            // Nobody holds the keyboard — not the page, and not the sidebar's
            // search, its list, or any other control in the window. Only
            // then do the arrows, Return and Escape belong to the page.
            let idle = !(responder is NSText) && !(responder is NSControl)
                && !(responder is NSTableView)
            if let window = event.window, window.identifier?.rawValue == "main",
               typing || idle,
               pageKey(event, in: window, typing: typing, editor: editor) {
                return nil
            }
            if event.keyCode == 48 {
                // A page view holding the keyboard answers for itself.
                if typing { return event }
                if let here = focus {
                    advance(from: here, forward: !event.modifierFlags.contains(.shift))
                    return nil
                }
                // Tab with the page open but no caret yet — the very first
                // Tab of a session, or one arriving in the beat after a
                // click while the text view is still taking the keyboard.
                // It puts the caret at the top of the shot you are in.
                // Letting it through instead handed the key to AppKit's own
                // loop, which left the document for the sidebar.
                // With no shot yet, the first of the scene on screen — not
                // the first of the film, pages away.
                if let shot = state.cursorShot ?? rows.first?.id ?? everyRow.first?.id {
                    state.cursorShot = shot
                    state.marked.removeAll()
                    focus = PageFocus(shot: shot, part: .title)
                    return nil
                }
            }
            // Everything a shot answers to — ⌘Z, ⌘⏎, ⌘⌫, ⌘D, ⌘K, ⌘↑/⌘↓,
            // ⌘A, ⌘V, ⌘+/⌘− — is the same on all three surfaces and lives in
            // one file (`Shortcuts`). It was three different sets before, and
            // the page's was the thinnest: no undo, no strike, no way to
            // paste a picture onto the shot you were writing about.
            return Shortcuts.handle(event, state: state, typing: typing,
                                    surface: shortcutSurface)
        }
        Self.watcher = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: watch)
        // The check drives the page through the same watcher.
        PageKeys.page = watch
    }

    /// What the page tells the shared keyboard about itself.
    private var shortcutSurface: Shortcuts.Surface {
        .init(
            scene: scene.id,
            // ⌘+ and ⌘− mean "make this bigger" everywhere. On the page the
            // thing that gets bigger is the type.
            // ⌘+ and ⌘− mean "make this bigger" everywhere. On the page the
            // thing that gets bigger is **the words you have selected** — the
            // paper itself is Letter and stays Letter.
            resize: { step in
                switch step {
                case 1: resize(by: 0.5)
                case -1: resize(by: -0.5)
                default: reface(.serif)
                }
            }
        )
    }

    // -------------------------------------------------- the shots themselves

    /// **The page without the mouse** — his ask, 2026-09-30: *"the goal is to
    /// not need to touch the mouse while adding shots and details to shots."*
    ///
    /// Two ways of standing on the page, and Escape and Return step between
    /// them, the way a block editor works:
    ///
    /// - **Writing** — the caret is in a part of a shot. Tab walks the parts.
    ///   ⌘↩ (or ⇧↩, or ⌃↩) starts the next shot under this one, from any
    ///   part, and the caret goes straight into its words. Escape keeps what
    ///   was typed and picks the whole shot.
    /// - **Picking** — whole shots, no caret. ↑ ↓ walk the shots, ⇧ reaches.
    ///   Return goes back into the words. Escape lets go. ⌘⌫, ⌘↑ ⌘↓, ⌘D and
    ///   ⌘K act on what is picked, as they always have.
    ///
    /// Answers whether it took the key.
    private func pageKey(_ event: NSEvent, in window: NSWindow,
                         typing: Bool, editor: NSTextView?) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command), shift = flags.contains(.shift)
        let control = flags.contains(.control), option = flags.contains(.option)
        switch event.keyCode {
        case 36, 76:                                            // Return, Enter
            if command || control || (shift && !option) {
                newShot(in: window, editor: editor)
                return true
            }
            guard !typing, !command, !control, !option, !shift else { return false }
            guard let shot = state.cursorShot
                    ?? everyRow.first(where: { state.marked.contains($0.id) })?.id
            else { return false }
            write(shot)
            return true
        case 53:                                                // Escape
            if typing {
                stepOut(in: window)
                return true
            }
            guard !state.marked.isEmpty else { return false }
            state.marked.removeAll()
            return true
        case 125, 126:                                          // ↓ ↑
            guard !typing, !command, !option, !control else { return false }
            return walkShots(down: event.keyCode == 125, reach: shift)
        default:
            return false
        }
    }

    /// A new shot under the one you are in, and the caret in its words.
    ///
    /// Whatever was being written is put away first — a line by letting go of
    /// the keyboard (which writes it), an open field by taking what its list
    /// has highlighted, if a hand chose anything. The old ⇧↩ added the shot at
    /// the foot of the scene and left the caret where it was, so on a long
    /// scene nothing seemed to happen at all.
    private func newShot(in window: NSWindow, editor: NSTextView?) {
        guard let engine = state.engine else { return }
        if let field = editor?.delegate as? FieldFilter.ClaimField,
           let open = field.delegate as? FieldFilter.Coordinator {
            open.parent.onCommand(.settle)
        }
        window.makeFirstResponder(nil)
        let all = everyRow
        let here = all.first { $0.id == state.cursorShot }
            ?? all.last { state.marked.contains($0.id) }
        let into = here?.sceneId ?? scene.id
        let before = Set(state.view?.allRows.map(\.id) ?? [])
        state.replace(engine.addShot(scene: into, after: here?.placement))
        guard let made = state.view?.allRows.first(where: {
            !before.contains($0.id) && $0.sceneId == into
        }) else { return }
        state.marked.removeAll()
        state.cursorShot = made.id
        focus = PageFocus(shot: made.id, part: .words)
        follow = Follow(shot: made.id, count: follow.count + 1)
    }

    /// The ＋ in a scene's heading: a shot at the foot of the scene, and the
    /// caret in its words, the same as ⌘↩.
    private func addShot(to scene: String) {
        guard let engine = state.engine else { return }
        let before = Set(state.view?.allRows.map(\.id) ?? [])
        state.replace(engine.addShot(scene: scene))
        guard let made = state.view?.allRows.first(where: {
            !before.contains($0.id) && $0.sceneId == scene
        }) else { return }
        state.marked.removeAll()
        state.cursorShot = made.id
        focus = PageFocus(shot: made.id, part: .words)
        follow = Follow(shot: made.id, count: follow.count + 1)
    }

    /// Escape while writing: keep the words, put the caret away, and pick the
    /// whole shot — so the next key can move it, delete it, or walk on.
    /// An open field lets go without writing: its filter is a search.
    private func stepOut(in window: NSWindow) {
        window.makeFirstResponder(nil)
        focus = nil
        guard let shot = state.cursorShot else { return }
        state.marked = [shot]
        reachFrom = shot
    }

    /// Return on a picked shot: back into its words.
    private func write(_ shot: String) {
        state.marked.removeAll()
        state.cursorShot = shot
        focus = PageFocus(shot: shot, part: .words)
        follow = Follow(shot: shot, count: follow.count + 1)
    }

    /// ↑ ↓ with shots picked: the next one up or down. ⇧ reaches from the
    /// shot the walk began on. With nothing picked, the first press picks the
    /// shot you were in.
    private func walkShots(down: Bool, reach: Bool) -> Bool {
        let all = everyRow
        guard !all.isEmpty else { return false }
        let at = all.firstIndex { $0.id == state.cursorShot }
        if state.marked.isEmpty {
            let start = at ?? all.firstIndex { $0.sceneId == scene.id } ?? 0
            pickOnly(all[start].id)
            return true
        }
        let from = at ?? all.firstIndex { state.marked.contains($0.id) } ?? 0
        let to = min(max(from + (down ? 1 : -1), 0), all.count - 1)
        let id = all[to].id
        if reach, let anchor = reachFrom,
           let a = all.firstIndex(where: { $0.id == anchor }) {
            state.marked = Set(all[min(a, to)...max(a, to)].map(\.id))
            state.cursorShot = id
        } else {
            pickOnly(id)
        }
        follow = Follow(shot: id, count: follow.count + 1)
        return true
    }

    /// Nothing picked, no caret. A line being written is written first —
    /// letting go of the keyboard is what writes it.
    private func letGo() {
        state.marked.removeAll()
        focus = nil
        let window = NSApp.windows.first { $0.identifier?.rawValue == "main" }
        let responder = window?.firstResponder
        if responder is GrowText
            || (responder as? NSTextView)?.delegate is FieldFilter.ClaimField {
            window?.makeFirstResponder(nil)
        }
    }

    private func pickOnly(_ id: String) {
        state.marked = [id]
        state.cursorShot = id
        reachFrom = id
        focus = nil
    }

    /// Click a shot's number to select it. Plain takes just that one, ⌘ adds
    /// or removes, ⇧ reaches from the last one — the sidebar's and table's
    /// grammar, kept. **A second plain click lets it go** — picking was easy
    /// and letting go was not.
    private func select(_ row: ViewModel.Row) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        let all = everyRow
        if flags.contains(.command) {
            if state.marked.contains(row.id) { state.marked.remove(row.id) }
            else { state.marked.insert(row.id) }
        } else if flags.contains(.shift), let anchor = state.cursorShot,
                  let from = all.firstIndex(where: { $0.id == anchor }),
                  let to = all.firstIndex(where: { $0.id == row.id }) {
            state.marked = Set(all[min(from, to)...max(from, to)].map(\.id))
        } else if state.marked == [row.id] {
            state.marked = []
        } else {
            state.marked = [row.id]
            reachFrom = row.id
        }
        state.cursorShot = row.id
        // Selecting a shot is not editing it: the caret goes away, so ⌘⌫
        // means the shot rather than a letter.
        focus = nil
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    // ------------------------------------------------------------- the bar

    /// Special to this view on purpose: none of it reaches the table, because
    /// none of it is a fact about the shot — it is how the page reads.
    /// **How the page is set** — one kind of words at a time.
    ///
    /// His ask, 2026-09-02: the resizing belongs here rather than in the
    /// exporter, and the page wants real classes with their own size, font and
    /// case. This is where they are set, and **the page underneath changes as
    /// he sets them** — which is the whole point of doing it here.
    ///
    /// A strip rather than a panel, and one class at a time rather than nine:
    /// this view *is* the preview, and anything laid over it is in the way. It
    /// is also the only shape a check can photograph — a popover is a window
    /// of its own and does not appear in a picture of this one.
    private var typeStrip: some View {
        let now = type.setting(typeClass)
        return HStack(spacing: 10) {
            Dropdown(selection: $typeClass,
                     items: PageType.Kind.allCases.map { Dropdown.Item($0, $0.label) },
                     width: 150)

            Stepper(value: Binding(
                get: { now.size },
                set: { write(size: $0, face: now.face, case: now.case,
                             colour: now.colour) }
            ), in: 6...30, step: 0.5) {
                Text(pointsRead(now.size))
                    .mono(11).foregroundStyle(Brand.ink2(dark))
                    // Wide enough for `10.5 pt` on one line. At 46 it broke
                    // after the number and the strip grew a second row.
                    .frame(width: 54, alignment: .leading)
                    .fixedSize()
            }

            Dropdown(selection: Binding(
                get: { now.face },
                set: { write(size: now.size, face: $0, case: now.case,
                             colour: now.colour) }
            ), items: [Dropdown.Item("serif", "Serif"),
                       Dropdown.Item("sans", "Sans"),
                       Dropdown.Item("mono", "Mono")],
               width: 86)

            // **The ink, one class at a time** — his ask, 2026-09-03. A short
            // list rather than the system colour panel, for the same reason
            // the faces are three: this is a page that gets printed, and a
            // named ink he can pick again next film beats a wheel he cannot.
            // The swatch beside it is the answer at a glance.
            HStack(spacing: 6) {
                // **The swatch sits on paper**, because the ink is for paper:
                // a black dot on the dark strip was a black dot on a dark
                // strip, and every dark ink would have been.
                RoundedRectangle(cornerRadius: Brand.radiusSmall, style: .continuous)
                    .fill(Brand.paper(onPaper))
                    .frame(width: 16, height: 16)
                    .overlay {
                        Circle().fill(Brand.hex(now.colour))
                            .frame(width: 9, height: 9)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Brand.radiusSmall, style: .continuous)
                            .strokeBorder(Brand.rule2(dark), lineWidth: 0.5)
                    }
                Dropdown(selection: Binding(
                    get: { Inks.known(now.colour) },
                    set: { write(size: now.size, face: now.face, case: now.case,
                                 colour: $0) }
                ), items: Inks.all.map { Dropdown.Item($0.hex, $0.name) }
                    // Only ever there when a file carries an ink this list does
                    // not — a hand-edited project, or a newer app.
                    + (Inks.known(now.colour) == now.colour
                       && !Inks.all.contains(where: { $0.hex == now.colour })
                       ? [Dropdown.Item(now.colour, "Custom")] : []),
                   width: 104)
            }

            // **Only where it can be honest.** The shot title, the words and
            // the note are his to type; a page that shouts them back is a page
            // disagreeing with the file. The engine refuses one on those too.
            if typeClass.takesCase {
                Dropdown(selection: Binding(
                    get: { now.case },
                    set: { write(size: now.size, face: now.face, case: $0,
                                 colour: now.colour) }
                ), items: [Dropdown.Item("as", "As typed"),
                           Dropdown.Item("upper", "UPPER"),
                           Dropdown.Item("lower", "lower")],
                   width: 104)
            }

            Spacer()
            if type.touched {
                Button("Reset") { resetType() }
                    .buttonStyle(.plain).sans(11)
                    .foregroundStyle(Brand.accent(dark))
            }
            // **Two levels, and the film always wins.** His ask, 2026-09-04:
            // the page he has set here should be what every other film starts
            // from, and any film should still be free to differ.
            //
            // A film that has never been set takes the default when it opens,
            // once. From the moment he touches this strip on that film, the
            // film keeps its own and the default stops reaching it — which is
            // the whole of "set new defaults per project".
            Menu {
                Button("Save as default") { state.savePageDefault() }
                if !state.pageDefault.isEmpty {
                    Button("Use default") { state.usePageDefault() }
                    Divider()
                    Button("Clear default") { state.clearPageDefault() }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Default").sans(11)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(Brand.ink2(dark))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Brand.surface2(dark))
        .hairline(.bottom, Brand.rule(dark))
    }

    /// `10.5 pt`, not `10.50 pt` — the number he set is the number he reads.
    private func pointsRead(_ size: CGFloat) -> String {
        (size == size.rounded() ? String(Int(size)) : String(format: "%.1f", size)) + " pt"
    }

    private func write(size: CGFloat, face: String, case casing: String,
                       colour: String) {
        guard let engine = state.engine else { return }
        state.replace(engine.setDocStyle(typeClass.rawValue, size: Double(size),
                                         face: face, case: casing,
                                         colour: colour))
    }

    private func resetType() {
        guard let engine = state.engine else { return }
        state.replace(engine.resetDocStyle())
    }

    private var formattingBar: some View {
        HStack(spacing: 6) {
            Group {
                barButton("bold", help: "Bold") { emphasise(.boldFontMask) }
                barButton("italic", help: "Italic") { emphasise(.italicFontMask) }
                barButton("underline", help: "Underline") { underline() }
            }
            Divider().frame(height: 16).opacity(0.4)

            // **Every one of these acts on what you have selected**, the way
            // bold does — his correction. Nothing selected, nothing happens,
            // and the page says so rather than leaving you wondering.
            Button { reface(.serif) } label: {
                Text("Serif").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Brand.ink2(dark))
            .help("Serif")
            Button { reface(.default) } label: {
                Text("Sans").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Brand.ink2(dark))
            .help("Sans")

            HStack(spacing: 2) {
                barButton("textformat.size.smaller",
                          help: "Smaller — the selected words") { resize(by: -0.5) }
                barButton("textformat.size.larger",
                          help: "Larger — the selected words") { resize(by: 0.5) }
            }

            Divider().frame(height: 16).opacity(0.4)

            barButton("textformat", help: "Type") {
                settingType.toggle()
                state.showTypePanel = false
            }

            layoutMenu

            Spacer()

            Text("⌘⏎ NEW SHOT")
                .mono(10)
                .foregroundStyle(Brand.ink4(dark))
        }
        // **A floating glass bar.** It was a strip with a system material
        // behind it — which, as of today's measurement, photographs as nothing
        // at all. Painted glass in a capsule with air round it: it reads as a
        // toolbar you can pick up, and it can be checked.
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background {
            Capsule(style: .continuous)
                .fill(Brand.panel(dark))
                .overlay { Capsule(style: .continuous)
                    .strokeBorder(Brand.glassEdge(dark), lineWidth: 1) }
                .shadow(color: Color.black.opacity(dark ? 0.40 : 0.12), radius: 10, y: 2)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func barButton(_ symbol: String, help: String,
                           action: @escaping () -> Void) -> some View {
        BarButton(symbol: symbol, help: help, dark: dark, action: action)
    }

    /// Every frame on the page at once. Per-shot layout is the page's whole
    /// idea, but a scene of forty full-measure frames needs one move to become
    /// a page you can read — not forty.
    private var layoutMenu: some View {
        Menu {
            Section("This scene") {
                sizeMenu(everywhere: false)
                placeMenu(everywhere: false)
                Button("Mix it up") { mixUp(everywhere: false) }
            }
            // Doing it a scene at a time is doing it forty times on a feature.
            Section("The whole document") {
                sizeMenu(everywhere: true)
                placeMenu(everywhere: true)
                Button("Mix it up") { mixUp(everywhere: true) }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "rectangle.3.group").font(.system(size: 10))
                Text("Layout").sans(11, weight: .medium)
            }
            .foregroundStyle(Brand.ink2(dark))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Apply to every frame")
    }

    private func sizeMenu(everywhere: Bool) -> some View {
        Menu("Size") {
            ForEach(Layouts.sizes, id: \.0) { name, width in
                // Size alone, keeping whichever side each frame is already on.
                Button(name) { lay(everywhere: everywhere, position: nil, width: width) }
            }
        }
    }

    private func placeMenu(everywhere: Bool) -> some View {
        Menu("Place") {
            ForEach(Layouts.places, id: \.1) { name, where_ in
                // Side alone, keeping the size he set — re-clamped, because
                // full width beside the words is not a thing.
                Button(name) { lay(everywhere: everywhere, position: where_, width: nil) }
            }
            Divider()
            Button("Alternate sides") { alternate(everywhere: everywhere) }
        }
    }

    /// One pass over the shots, whichever set he asked for. **Either half can
    /// be left alone**: a size with no side keeps each frame where it is, a
    /// side with no size keeps how big he made it. The view is asked for once
    /// at the end rather than once per shot — a feature is several hundred
    /// shots and redrawing the page between each is the difference between a
    /// click and a wait.
    private func lay(everywhere: Bool, position: String?, width: Double?) {
        change(everywhere: everywhere) { _, row in
            let side = position ?? row.framePosition
            return (side, Layouts.clamp(width ?? row.frameWidth, on: side))
        }
    }

    private func alternate(everywhere: Bool) {
        change(everywhere: everywhere) { at, row in
            Layouts.alternating(at, width: row.frameWidth)
        }
    }

    private func mixUp(everywhere: Bool) {
        change(everywhere: everywhere) { at, _ in Layouts.mixed(at) }
    }

    private func change(everywhere: Bool,
                        _ decide: (Int, ViewModel.Row) -> (String, Double)) {
        guard let engine = state.engine else { return }
        let shots = everywhere ? everyRow : rows
        var last: ViewModel?
        for (at, row) in shots.enumerated() {
            let (position, width) = decide(at, row)
            last = engine.layout(shot: row.shot, position: position, width: width)
        }
        state.replace(last)
        FileHandle.standardError.write(Data((
            "laid out: \(shots.count) shots\n").utf8))
    }

    /// Emphasis lands on the selection, the way it does in any editor. Nothing
    /// happens with no selection rather than silently changing the whole shot.
    private func emphasise(_ trait: NSFontTraitMask) {
        guard let view = focused, let storage = view.textStorage else { return }
        let range = view.selectedRange()
        guard range.length > 0 else { return }
        let manager = NSFontManager.shared
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, sub, _ in
            let current = value as? NSFont ?? bodyFont
            let next = manager.traits(of: current).contains(trait)
                ? manager.convert(current, toNotHaveTrait: trait)
                : manager.convert(current, toHaveTrait: trait)
            storage.addAttribute(.font, value: next, range: sub)
        }
        storage.endEditing()
        view.didChangeText()
        commitFocused()
    }

    /// The face of the selection. Same shape as `emphasise`: the selection or
    /// nothing at all.
    private func reface(_ design: NSFontDescriptor.SystemDesign) {
        guard let view = focused, let storage = view.textStorage,
              view.selectedRange().length > 0 else {
            state.say("Select text first")
            return
        }
        Rich.reface(storage, in: view.selectedRange(), design: design, size: nil)
        view.didChangeText()
        commitFocused()
    }

    /// The size of the selection, half a point at a time.
    private func resize(by step: CGFloat) {
        guard let view = focused, let storage = view.textStorage,
              view.selectedRange().length > 0 else {
            state.say("Select text first")
            return
        }
        Rich.resize(storage, in: view.selectedRange(), by: step)
        view.didChangeText()
        commitFocused()
    }

    private func underline() {
        guard let view = focused, let storage = view.textStorage else { return }
        let range = view.selectedRange()
        guard range.length > 0 else { return }
        let existing = storage.attribute(.underlineStyle, at: range.location,
                                         effectiveRange: nil) as? Int
        storage.addAttribute(
            .underlineStyle,
            value: (existing ?? 0) == 0 ? NSUnderlineStyle.single.rawValue : 0,
            range: range
        )
        view.didChangeText()
        commitFocused()
    }

    private func commitFocused() {
        guard let view = focused, let storage = view.textStorage,
              let shot = focusedShot else { return }
        write(shot: shot, text: NSAttributedString(attributedString: storage))
    }

    /// The words and their emphasis go together, so nothing else in the app
    /// ever sees a description that does not match what is on the page.
    private func write(shot: String, text: NSAttributedString) {
        guard let engine = state.engine else { return }
        state.replace(engine.set(shot: shot, field: "description", value: text.string))
        state.replace(engine.set(shot: shot, field: "description_rich",
                                 value: Rich.encode(text)))
    }

    // ------------------------------------------------------------- the page

    /// **Sheets of paper, not one long strip** — his ask, 2026-09-01: *"You
    /// see the document in pages so you know what it will look like on
    /// export."* Every sheet is 612 × 792 with an inch of margin, the shots
    /// flow into them the way they flow into the PDF, and the foot of each one
    /// carries the same stamp `Printing.Footered` puts on the export.
    private var page: some View {
        ScrollViewReader { reader in
            ScrollView {
                // **Worked out once for the whole draw.** The sheets, and a
                // way to find a scene or a shot by its id without walking
                // every row again — this runs on every keystroke, and looking
                // each block up in a list of several hundred, several hundred
                // times, is how a document view gets slow on a feature.
                let plan = self.plan
                VStack(spacing: 26) {
                    ForEach(Array(plan.sheets.enumerated()), id: \.offset) { at, slabs in
                        sheet(slabs, plan: plan, number: at + 1, of: plan.sheets.count)
                            // The sheet with the shot you are in draws over the
                            // one after it: a list opened near the foot of a
                            // page hangs past the paper, and the next sheet
                            // was painted over it.
                            .zIndex(slabs.contains(.shot(state.cursorShot ?? "")) ? 1 : 0)
                    }
                }
                .padding(.vertical, 26)
                .frame(maxWidth: .infinity)
                // **A click on empty paper or the desk lets go** — of picked
                // shots, and of the caret. Anything drawn on the page answers
                // its own click first; this only hears the empty places.
                .contentShape(Rectangle())
                .onTapGesture { letGo() }
                // The heights arrive as a preference rather than as a write
                // from inside the layout pass — the same lesson that cost a
                // frozen app on the 19th, and the reason a block measures
                // itself where it is drawn instead of being drawn twice.
                .onPreferenceChange(SlabHeights.self) { found in
                    var next = heights
                    var moved = false
                    for (slab, tall) in found where abs((next[slab] ?? -1) - tall) > 0.5 {
                        next[slab] = tall
                        moved = true
                    }
                    guard moved else { return }
                    heights = next
                    // **Where the sheets fell, told to the rest of the app.**
                    // Nothing else can work it out: the cut depends on how
                    // tall each block came out, which is only known once it
                    // has been drawn. `--pages` reads this, which is the only
                    // way a check can see a page break at all.
                    state.documentSheets = cut(slabs, with: next)
                }
            }
            .background(Brand.desk(dark))
            .onChange(of: follow) { _, now in
                guard let shot = now.shot else { return }
                // The least scroll that shows the whole shot — nothing moves
                // if it is already in view.
                withAnimation(.easeOut(duration: 0.18)) {
                    reader.scrollTo(Slab.shot(shot), anchor: nil)
                }
            }
            // Picking a scene in the sidebar takes you to that scene's place
            // in the document rather than swapping the page under you.
            .onChange(of: scene.id) { _, id in
                withAnimation(.easeInOut(duration: 0.28)) {
                    reader.scrollTo(Slab.scene(id), anchor: .top)
                }
            }
            .onAppear {
                // Opening on the film's first scene shows the top of the
                // document — the head of the first sheet, margin and all.
                // Asking to scroll there instead put the masthead itself at
                // the top of the window and the inch of paper above it out of
                // sight, which is the one thing this screen exists to show.
                guard documentScenes.first?.id != scene.id else { return }
                reader.scrollTo(Slab.scene(scene.id), anchor: .top)
            }
        }
    }

    /// One sheet of paper.
    private func sheet(_ slabs: [Slab], plan: Plan,
                       number: Int, of total: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(slabs) { slab in
                view(of: slab, plan: plan)
                    .id(slab)
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: SlabHeights.self, value: [slab: geo.size.height])
                        }
                    }
            }
        }
        .frame(width: Page.column, height: Page.usable, alignment: .topLeading)
        .padding(Page.margin)
        // Paper on a desk, not a panel in a window: the sheet is its own
        // lighter surface and the ground behind it is markedly darker, which
        // is the whole difference between "a document I am writing" and "a
        // narrow app view".
        .background(Brand.paper(onPaper))
        .overlay(alignment: .bottom) { foot(number: number, of: total) }
        .overlay(Rectangle().strokeBorder(Brand.paperEdge(onPaper), lineWidth: 0.5))
        .shadow(color: .black.opacity(dark ? 0.5 : 0.18), radius: 16, y: 5)
        .shadow(color: .black.opacity(dark ? 0.3 : 0.08), radius: 2, y: 1)
    }

    /// The running foot: when it was made, and where this sheet sits in the
    /// file. **The same two things in the same two corners** as
    /// `Printing.Footered`, which draws them 24 points in from the edge.
    private func foot(number: Int, of total: Int) -> some View {
        HStack {
            Text(Self.stampFormatter.string(from: stamped))
            Spacer()
            Text("Page \(number) of \(total)")
        }
        .font(.system(size: 8))
        .foregroundStyle(Brand.ink4(onPaper))
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter
    }()

    /// Everything the document holds, in reading order, one entry per thing a
    /// page break must not cut in two.
    private var slabs: [Slab] {
        let scenes = documentScenes
        var out: [Slab] = [.head]
        for sc in scenes {
            if state.sectionHeadBefore(sc, in: scenes) { out.append(.section(sc.id)) }
            out.append(.scene(sc.id))
            out.append(contentsOf: rows(of: sc).map { Slab.shot($0.id) })
        }
        return out
    }

    /// The whole document, worked out once: which sheet everything is on, and
    /// where to find a scene or a shot by its id.
    struct Plan {
        var sheets: [[Slab]] = []
        var scenes: [String: ViewModel.Scene] = [:]
        var rows: [String: ViewModel.Row] = [:]
    }

    private var plan: Plan {
        var made = Plan()
        var order: [Slab] = [.head]
        let scenes = documentScenes
        for sc in scenes {
            made.scenes[sc.id] = sc
            if state.sectionHeadBefore(sc, in: scenes) { order.append(.section(sc.id)) }
            order.append(.scene(sc.id))
            for row in rows(of: sc) {
                made.rows[row.id] = row
                order.append(.shot(row.id))
            }
        }
        made.sheets = cut(order, with: heights)
        return made
    }

    /// **Where the sheets are cut.** Fill a page until the next block will not
    /// fit, then start another — which is exactly what `Printing.pageBreaks`
    /// does to the printed page, from the same blocks in the same order.
    ///
    /// A scene heading carries the first shot under it with it: stranded at
    /// the foot of a sheet it announces a scene that then does not begin.
    private func cut(_ all: [Slab], with heights: [Slab: CGFloat]) -> [[Slab]] {
        var out: [[Slab]] = []
        var page: [Slab] = []
        var used: CGFloat = 0
        let tallness = { (slab: Slab) in heights[slab] ?? Self.guess(slab) }
        for (at, slab) in all.enumerated() {
            let tall = tallness(slab)
            var needs = tall
            if case .scene = slab, at + 1 < all.count {
                needs += tallness(all[at + 1])
            }
            if !page.isEmpty, used + needs > Page.usable {
                out.append(page)
                page = []
                used = 0
            }
            page.append(slab)
            used += tall
        }
        if !page.isEmpty { out.append(page) }
        return out.isEmpty ? [[]] : out
    }

    /// A block's measured height, or a first guess at it. The guess only ever
    /// decides the very first draw, before anything has been measured — one
    /// beat later every number here is the real one.
    private static func guess(_ slab: Slab) -> CGFloat {
        switch slab {
        case .head: return 46
        case .section: return 70
        case .scene: return 40
        case .shot: return 120
        }
    }

    @ViewBuilder
    private func view(of slab: Slab, plan: Plan) -> some View {
        switch slab {
        case .head:
            sheetHead
        case .section(let id):
            if let sc = plan.scenes[id] { sectionHead(sc) }
        case .scene(let id):
            if let sc = plan.scenes[id] { heading(sc) }
        case .shot(let id):
            if let row = plan.rows[id] { shotBlock(row) }
        }
    }

    /// Every scene the document shows, in the script's order. Archived
    /// scenes are set aside, so they are not in the read-through.
    /// **The same scenes the table is showing, in the same order** — Ref 53,
    /// his rule: *"It should always be in line with whatever the table is
    /// doing."* The technical line already followed the table's columns; the
    /// scenes did not follow its filter or the order it is being read in, so
    /// narrowing the film to one location left the document printing the whole
    /// script, and reading by shoot day left it in script order. Three answers
    /// to one question.
    private var documentScenes: [ViewModel.Scene] {
        let all = state.inViewOrder((state.view?.scenes ?? []).filter { !$0.archived })
        guard state.view?.filter.narrowed == true else { return all }
        // Under a filter a scene with nothing left in it is not empty, it is
        // narrowed out — printing its heading with nothing under it says the
        // film changed when only the question did. Same rule as the table's.
        return all.filter { !rows(of: $0).isEmpty }
    }

    /// The sequence a scene belongs to, by the name a person gave it.
    private func sequenceName(of scene: ViewModel.Scene) -> String? {
        guard let id = scene.sequence, !id.isEmpty,
              let title = state.view?.sequences.first(where: { $0.id == id })?.title,
              !title.isEmpty
        else { return nil }
        return title
    }

    private func rows(of scene: ViewModel.Scene) -> [ViewModel.Row] {
        state.view?.allRows.filter { $0.sceneId == scene.id } ?? []
    }

    /// Every shot in the document, in reading order — what Tab walks and
    /// what ⌘↑/⌘↓ move through.
    private var everyRow: [ViewModel.Row] {
        documentScenes.flatMap { rows(of: $0) }
    }

    /// The head of the sheet: the film, what this document is, what order it
    /// is in, and who made it. **`doc_masthead` in `engine/src/export/html.rs`
    /// draws the same four things in the same four places** — the credits line
    /// came from there so a page exported to somebody else is signed, and the
    /// order caption goes the other way, carried out to the export as
    /// `order=` because only the app knows how the list is being read.
    private var sheetHead: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: Page.besideFrame) {
                Text(type.cased(state.view?.project.shownTitle ?? "", .sheetTitle))
                    .faced(type.face(.sheetTitle), type.size(.sheetTitle), weight: .bold)
                    .foregroundStyle(type.colour(.sheetTitle))
                // **One class, one ink.** These three were black, black and
                // near-white grey, and the printed sheet made its own third
                // choice again — for one kind of words. They all read Credits.
                Text(type.cased("Shot List", .credits))
                    .faced(type.face(.credits), type.size(.credits), tracking: 1.4)
                    .foregroundStyle(type.colour(.credits))
                Spacer()
                // **It used to say SCRIPT ORDER whatever order it was in.**
                // A printed sheet that names its own order wrongly is worse
                // than one that names none, because somebody on the day
                // believes it.
                Text(type.cased(orderCaption, .credits))
                    .faced(type.face(.credits), type.size(.credits), tracking: 0.8)
                    .foregroundStyle(type.colour(.credits))
            }
            Text(type.cased(credits, .credits))
                .faced(type.face(.credits), type.size(.credits), tracking: 0.8)
                .foregroundStyle(type.colour(.credits))
            Rectangle().fill(Brand.ink(onPaper)).frame(height: 1)
        }
        .padding(.bottom, 2)
    }

    /// What the sheet says about its own order — `ShellState.orderCaption`,
    /// because the export needs the same words and cannot reach into a view.
    private var orderCaption: String { state.orderCaption }

    /// **The same words `doc_masthead` writes**, upper-cased by the stylesheet
    /// there and by hand here. His name is a constant on both sides
    /// (`CINEMATOGRAPHER` in `engine/src/export/html.rs`) because this is his
    /// program and every sheet it makes is his.
    private var credits: String {
        let director = state.view?.project.director ?? ""
        let producer = state.view?.project.producer ?? ""
        var parts = ["CINEMATOGRAPHY BY NATHANIEL REGIER"]
        if !director.isEmpty { parts.append("DIRECTED BY \(director.uppercased())") }
        if !producer.isEmpty { parts.append("PRODUCED BY \(producer.uppercased())") }
        return parts.joined(separator: " · ")
    }

    /// **A section's chapter head on the page** — his finding, 2026-09-19:
    /// the scripts were not told apart in the document at all. A run of
    /// scenes opens with its section's name at the sheet title's size, on a
    /// light wash of the section's color, and air above, so a fast scroll says
    /// which script you are in. The printed page draws the same
    /// (`section-head` in `engine/src/export/html.rs`).
    private func sectionHead(_ sc: ViewModel.Scene) -> some View {
        let section = state.sectionOf(sc)
        let ink = section.map { Brand.hex($0.colour) } ?? Brand.ink3(onPaper)
        return HStack(alignment: .center, spacing: Page.besideFrame) {
            Text(type.cased(section?.title ?? "", .sheetTitle))
                .faced(type.face(.sheetTitle), type.size(.sheetTitle), weight: .bold)
                .foregroundStyle(type.colour(.sheetTitle))
            Spacer()
        }
        // The section's color as a light wash behind its name (his call,
        // 2026-10-16), the same strength as the Table's.
        .padding(.vertical, 8).padding(.horizontal, Page.besideFrame)
        .background(RoundedRectangle(cornerRadius: Kit.Radius.control, style: .continuous)
            .fill(ink.opacity(Kit.sectionWash(dark: onPaper))))
        .padding(.top, Page.overScene * 1.5)
        .padding(.bottom, 2)
    }

    /// The real shot lists set a scene header bold and underlined at body
    /// size — the heading is a landmark you scan for, not a chapter title.
    private func heading(_ sc: ViewModel.Scene) -> some View {
        let count = rows(of: sc).count
        return HStack(alignment: .firstTextBaseline, spacing: Page.besideFrame) {
            Text(type.cased(sc.number, .sceneNumber))
                .faced(type.face(.sceneNumber), type.size(.sceneNumber), weight: .bold)
                .foregroundStyle(type.colour(.sceneNumber))
            // Day or night, at a glance — the same dot the sidebar wears, and
            // the one the printed sheet draws in front of the same words.
            if let ink = Brand.timeInk(sc.timeOfDay, onPaper) {
                Circle().fill(ink)
                    .frame(width: type.size(.sceneHeading) * 0.45,
                           height: type.size(.sceneHeading) * 0.45)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            }
            Text(type.cased(sc.heading, .sceneHeading))
                .faced(type.face(.sceneHeading), type.size(.sceneHeading),
                       weight: .bold, tracking: 0.4)
                .underline()
                .foregroundStyle(type.colour(.sceneHeading))
            // Which sequence it belongs to, where it belongs to one — the
            // printed sheet has always said so and this did not.
            //
            // **By its name, not its id.** `Scene.sequence` is the engine's
            // own identifier and drawing it put a thirty-seven-digit number
            // across the heading; the title lives in `view.sequences`, which
            // is how the filter menu and the scene sheet already read it.
            if let sequence = sequenceName(of: sc) {
                Text(type.cased(sequence, .credits))
                    .faced(type.face(.credits), type.size(.credits), tracking: 0.5)
                    .foregroundStyle(type.colour(.credits))
            }
            Spacer()
            Text(type.cased("\(count) \(count == 1 ? "shot" : "shots")", .credits))
                .faced(type.face(.credits), type.size(.credits))
                .foregroundStyle(type.colour(.credits))
            // **The ＋ lives in the heading now.** It was a row of its own
            // under the last shot, which is an editing control taking up
            // space on a sheet of paper — and the printed page has no such
            // row, so every scene pushed the page break a line further along
            // on screen than it falls on paper. Here it rides in a line that
            // is already there and costs the page nothing.
            Button { addShot(to: sc.id) } label: {
                Image(systemName: "plus").font(.system(size: 8, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Brand.ink3(onPaper))
            .help("Add shot")
        }
        .foregroundStyle(Brand.ink(onPaper))
        .padding(.top, Page.overScene)
        .padding(.bottom, Page.betweenShots)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Brand.rule2(onPaper)).frame(height: 0.5)
        }
        .padding(.bottom, Page.betweenShots * 2)
        // Clicking a heading takes the sidebar with it, so the two agree
        // about which scene you are reading.
        .contentShape(Rectangle())
        .onTapGesture { state.sceneId = sc.id }
    }

    @ViewBuilder
    private func shotBlock(_ row: ViewModel.Row) -> some View {
        // **The stills themselves, not pictures of them.** They used to be
        // decoded to `NSImage` here, which is fine for a photograph and is
        // exactly what turned a clip on the page into a frozen frame. The
        // paragraph gets what it needs to draw a moving thing moving.
        let frames = row.stills.filter {
            Frames.something($0.hash, $0.filename, state.engine)
        }
        ShotParagraph(
            row: row,
            // On the paper, so drawn as paper — chips, selection and ink all
            // light, on a white sheet, whatever the app is wearing.
            dark: onPaper,
            // **The page follows the column, and Camera is off unless he
            // turns it on** — Ref 326. It is there for a multicam day or a
            // second body on set, and is a column of one repeated answer on
            // every other film, so `false` is the right answer when a project
            // has no such column at all rather than `true`.
            showCamera: state.view?.columns
                .first { $0.name == "camera" }?.visible ?? false,
            paint: state.paint,
            arrivals: Thumbs.shared.arrivals,
            fields: technicalFields,
            options: { field in Columns.options(field, state: state) },
            canCreate: { field in Columns.canCreate(field, state: state) },
            chip: { field, option in
                Columns.chipColour(field, option, state: state, dark: dark)
            },
            ratio: CGFloat(state.view?.project.ratio ?? 2.39),
            font: bodyFont,
            type: type,
            ink: ink,
            measure: measure,
            images: frames,
            engine: state.engine,
            selected: state.cursorShot == row.id,
            marked: state.marked.contains(row.id),
            focusPart: focus?.shot == row.id ? focus?.part : nil,
            // A click on the shot itself — its words, its blank space — is
            // being in it, not picking it: whatever was picked lets go.
            onSelect: {
                state.cursorShot = row.id
                state.marked.removeAll()
            },
            onPick: { select(row) },
            onFocus: { view in focused = view; focusedShot = row.shot },
            onGo: { part in
                state.cursorShot = row.id
                if part != nil { state.marked.removeAll() }
                focus = part.map { PageFocus(shot: row.id, part: $0) }
            },
            onAdvance: { part, forward in
                advance(from: PageFocus(shot: row.id, part: part), forward: forward)
            },
            onWrite: { text in write(shot: row.shot, text: text) },
            onField: { field, value in
                // The table's own routing — camera births units, multi
                // toggles — one writer, two costumes.
                Columns.write(row, field, typed: value, state: state)
            },
            onRemoveOption: { field, option in
                guard let engine = state.engine else { return }
                _ = engine.removeValue(field: field, value: option)
                state.replace(engine.view())
            },
            onNewShot: {
                if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                    newShot(in: window, editor: nil)
                }
            },
            onLayout: { position, width in
                guard let engine = state.engine else { return }
                state.replace(engine.layout(shot: row.shot,
                                            position: position, width: width))
            },
            onDropMedia: { providers in
                Drops.take(providers, onto: row, state: state)
            }
        )
        .equatable()
        // **Under, never over.** The printed page hangs the same gap under a
        // shot and nothing above it, so a shot that lands at the top of a
        // sheet starts at the top of the sheet on both.
        .padding(.bottom, Page.betweenShots * 2)
        // The shot with the cursor may have a list hanging under one of its
        // fields; it has to draw over the paragraphs after it.
        .zIndex(state.cursorShot == row.id ? 1 : 0)
    }

    /// Tab, from anywhere on the page: the next editable part, in reading
    /// order, crossing into the next shot after the note. Landing on a shot
    /// selects it, so its fields are there to land on.
    private func advance(from: PageFocus, forward: Bool) {
        let parts = [PagePart.title, .words]
            + technicalFields.map { PagePart.field($0) }
            + [PagePart.note]
        let all = everyRow.flatMap { row in
            parts.map { PageFocus(shot: row.id, part: $0) }
        }
        guard let at = all.firstIndex(of: from) else { return }
        let next = at + (forward ? 1 : -1)
        guard all.indices.contains(next) else { return }
        state.cursorShot = all[next].shot
        focus = all[next]
    }

}

// ------------------------------------------------------------------ one shot

/// A shot as a paragraph: its number in the margin, its frames on whichever
/// side it asks for, the words, and the technical line under them.
/// **Why a shot can be skipped, and exactly when it cannot.**
///
/// The document draws the whole film — every shot of every scene, so the page
/// breaks can be measured where they actually fall. That is the right design
/// and it is not changing. What was wrong is that **every one of those shots
/// was built again whenever anything in the app changed**: clicking a row,
/// moving the cursor, typing a letter that reached the engine. Measured
/// 2026-09-04 on his own film: 56 paragraphs rebuilt per pass, 73ms a change,
/// against 38ms for the table beside it. His report: *"it's feeling
/// sluggish."*
///
/// SwiftUI will skip a view whose inputs have not changed — but only if it can
/// *tell*, and this view carries fourteen closures, which never compare equal.
/// So it could never tell, and never skipped.
///
/// This says what a shot is actually made of. Everything a closure reads is
/// either in this list already (`row`, `type`, `engine`) or represented by
/// something in it (`paint`, for the term colours a chip is painted with).
///
/// **Adding a stored property? Add it here.** A property left out is a shot
/// that does not redraw when it should, and that failure is silent.
extension ShotParagraph: Equatable {
    static func == (a: ShotParagraph, b: ShotParagraph) -> Bool {
        a.row == b.row
            && a.dark == b.dark
            && a.showCamera == b.showCamera
            && a.paint == b.paint
            && a.arrivals == b.arrivals
            && a.fields == b.fields
            && a.ratio == b.ratio
            && a.font == b.font
            && a.type == b.type
            && a.ink == b.ink
            && a.measure == b.measure
            && a.images == b.images
            && a.engine === b.engine
            && a.selected == b.selected
            && a.marked == b.marked
            && a.focusPart == b.focusPart
    }
}

private struct ShotParagraph: View {
    let row: ViewModel.Row
    let dark: Bool
    /// Hiding the camera column hides it here too — one column set, one page.
    let showCamera: Bool
    /// **Which generation of term colours this was drawn with.** The chips are
    /// painted by a closure, and a closure cannot be compared — this can. See
    /// `ShellState.paint`.
    let paint: Int
    /// **And which generation of pictures.** A photograph arriving from iCloud
    /// changes what this shot looks like without changing anything about the
    /// shot. See `Thumbs.arrivals`.
    let arrivals: Int
    /// The technical fields on screen, in the table's column order.
    let fields: [String]
    let options: (String) -> [String]
    /// Whether a field's list still learns — a locked one does not offer to.
    let canCreate: (String) -> Bool
    let chip: (String, String) -> Color?
    let ratio: CGFloat
    let font: NSFont
    /// **How this film's page is set.** Handed down rather than rebuilt, the
    /// same way the body font already is.
    let type: PageType
    let ink: NSColor
    let measure: CGFloat
    let images: [ViewModel.Still]
    let engine: Engine?
    let selected: Bool
    /// Chosen for an operation — ⌘⌫ to delete, ⌘↑/⌘↓ to move.
    let marked: Bool
    /// Where the page's keyboard is, when it is on this shot. This is the
    /// page's caret: one place, owned by one state. An open field is simply
    /// the field this names — which is why a Tab out of a field and into the
    /// next part happen in the *same* render, with no instant where nothing
    /// on the page holds the keyboard. That instant used to be enough for
    /// AppKit's own tab loop to take the key and walk off into the sidebar.
    let focusPart: PagePart?
    let onSelect: () -> Void
    /// The number in the margin was clicked: choose this shot.
    let onPick: () -> Void
    let onFocus: (NSTextView?) -> Void
    /// Put the page's keyboard here (nil lets it go).
    let onGo: (PagePart?) -> Void
    let onAdvance: (PagePart, Bool) -> Void
    let onWrite: (NSAttributedString) -> Void
    let onField: (String, String) -> Void
    let onRemoveOption: (String, String) -> Void
    let onNewShot: () -> Void
    let onLayout: (String, Double) -> Void
    /// The pictures themselves: attached to the shot, however they arrived.
    let onDropMedia: ([NSItemProvider]) -> Bool

    @State private var text = NSAttributedString(string: "")
    /// The technical field whose list is open — read from the page's caret,
    /// never held separately.
    private var openField: String? {
        if case .field(let name) = focusPart { return name }
        return nil
    }
    @State private var draggedWidth: Double?
    /// Where the frame is being carried, while it is; the side it would land
    /// on is computed from this and shown before anything is written.
    @State private var carrying: CGSize = .zero
    @State private var isCarrying = false
    /// The hand is over the resize grabber. The carry gesture covers the
    /// whole frame — grabber included — so without this a press on the edge
    /// that paused a beat became a carry, and a carry begun at the edge
    /// became a resize. The strip belongs to resizing alone.
    @State private var overHandle = false
    /// How big the paragraph came out, so a drop can be placed against it.
    @State private var block: CGSize = .zero
    @State private var dropping = false

    private var width: Double { draggedWidth ?? row.frameWidth }
    /// Beside the text a frame past ~55% of the measure crushes the words
    /// into a sliver, and the text reflow makes every pixel of drag feel like
    /// three — the touchiness he named. The cap keeps the drag linear.
    private var widthCeiling: Double { Layouts.ceiling(on: row.framePosition) }
    private var framePixels: CGFloat { measure * CGFloat(width) }

    /// The side the current carry would land the frame on: the dominant axis
    /// of the drag decides, from where the frame currently sits.
    private var carryTarget: String? {
        guard isCarrying else { return nil }
        let dx = carrying.width, dy = carrying.height
        guard abs(dx) > 30 || abs(dy) > 30 else { return row.framePosition }
        if abs(dx) > abs(dy) {
            return dx < 0 ? "left" : "right"
        }
        return dy < 0 ? "above" : "below"
    }

    var body: some View {
        let _ = { Built.paragraphs += 1 }()
        // **Top, not baseline.** A picture has no text baseline, so SwiftUI
        // gave it its bottom edge — which is why a frame beside the words hung
        // with its foot on the first line of type and the shot number sat down
        // by its ankles. His screenshot of it was the whole diagnosis.
        HStack(alignment: .top, spacing: Page.besideFrame) {
            // The number hangs in the margin, where a page reads it — and it
            // is also the shot's handle: click it to choose the shot (⌘ to
            // add, ⇧ to reach), then ⌘⌫ to delete or ⌘↑/⌘↓ to move it.
            VStack(alignment: .trailing, spacing: 4) {
                Text(type.cased(row.number, .shotNumber))
                    .faced(type.face(.shotNumber), type.size(.shotNumber), weight: .semibold)
                if !row.alsoAt.isEmpty {
                    Text("⚭").font(.system(size: 10)).foregroundStyle(Brand.ink4(dark))
                }
            }
            // **The gutter, to the point.** The number cell and the gap
            // after it are `Page.gutter` between them, so the words begin
            // exactly 60 points in — which is where `.shot { padding-left }`
            // puts them on the printed page. It was 36 wide inside 4 points
            // of padding inside 6 more on the row, and the paragraph came out
            // five points wider than the paper it was drawn on.
            .frame(width: Page.gutter - Page.besideFrame - 8, alignment: .trailing)
            .foregroundStyle(marked ? Brand.accent(dark) : Brand.ink2(dark))
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background {
                if marked {
                    RoundedRectangle(cornerRadius: Brand.radiusChip, style: .continuous).fill(Brand.accentTint(dark))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onPick)
            .help("Select · ⌘⌫ delete · ⌘↑ ⌘↓ move")

            layoutBody
                .overlay { landingLine }
                .frame(width: measure, alignment: .leading)
                // **Drop a picture anywhere on the paragraph** and it lands on
                // the shot, taking the side it was let go nearest — his ask,
                // and it removes the last reason for a placeholder to exist.
                // The size arrives as a preference rather than as a write from
                // inside the layout pass; that lesson cost a frozen app on the
                // 19th and is not being re-learned here.
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(key: BlockSize.self, value: geo.size)
                    }
                }
                .onPreferenceChange(BlockSize.self) { size in
                    if block != size { block = size }
                }
                .onDrop(of: [.fileURL, .image], isTargeted: $dropping) { providers, at in
                    place(providers, at: at)
                }
                .overlay {
                    if dropping {
                        RoundedRectangle(cornerRadius: Brand.radiusSmall)
                            .strokeBorder(Brand.accent(dark), lineWidth: 2)
                            .padding(-4)
                    }
                }
        }
        .background {
            // The accent's tint — the same mark a highlighted row of a list
            // wears. The quiet grey this was is all but invisible on white
            // paper, so a picked shot hardly looked picked.
            if marked {
                RoundedRectangle(cornerRadius: Brand.radiusSmall)
                    .fill(Brand.accentTint(dark))
                    .padding(-4)
            }
        }
        .opacity(row.struck ? 0.45 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onAppear { text = decoded }
        .onChange(of: row.description) { _, _ in text = decoded }
        .onChange(of: dark) { _, _ in text = decoded }
        // Tab landing on a field: the text views claim the keyboard
        // themselves, but a field has to open first — its editor does not
        // exist until it does.
        .onChange(of: focusPart) { _, part in
        }
    }

    /// The landing line: where the carried frame will sit if let go now —
    /// the same 2pt accent the header and the rows use, drawn on the edge of
    /// the paragraph the frame is heading for.
    @ViewBuilder
    private var landingLine: some View {
        if isCarrying, let target = carryTarget {
            let line = Rectangle().fill(Brand.accent(dark))
            switch target {
            case "above":
                line.frame(height: 2)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .offset(y: -5)
            case "below":
                line.frame(height: 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .offset(y: 5)
            case "left":
                line.frame(width: 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(x: -6)
            default:
                line.frame(width: 2)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(x: 6)
            }
        }
    }

    /// Where a dropped picture belongs: **the nearest of the four presets**,
    /// measured from where the hand let it go. Nothing to aim at, no target to
    /// find — the paragraph is the target and the corner of it you chose is
    /// the answer.
    private func place(_ providers: [NSItemProvider], at point: CGPoint) -> Bool {
        guard block.width > 0, block.height > 0 else { return false }
        let x = point.x / block.width, y = point.y / block.height
        let side = [("left", x), ("right", 1 - x), ("above", y), ("below", 1 - y)]
            .min { $0.1 < $1.1 }?.0 ?? "below"
        let ceiling = Layouts.ceiling(on: side)
        // A shot that has no frame yet gets a size that reads; one that does
        // keeps the size he set, re-clamped for the side it is landing on.
        let wanted = images.isEmpty
            ? (["left", "right"].contains(side) ? 0.38 : 0.5)
            : min(width, ceiling)
        onLayout(side, wanted)
        return onDropMedia(providers)
    }

    private var decoded: NSAttributedString {
        Rich.decode(row.descriptionRich, plain: row.description, font: font, colour: ink)
    }

    /// Four positions, because a frame above the text reads differently from
    /// one below it, and which side it takes changes how the page scans.
    @ViewBuilder
    private var layoutBody: some View {
        switch row.framePosition {
        case "left":
            HStack(alignment: .top, spacing: Page.besideFrame) { frames; words }
        case "right":
            HStack(alignment: .top, spacing: Page.besideFrame) { words; frames }
        case "above":
            VStack(alignment: .leading, spacing: Page.underFrame) { frames; words }
        default:
            VStack(alignment: .leading, spacing: Page.underFrame) { words; frames }
        }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: Page.withinShot) {
            // The title reads first and reads AS a title — the short name
            // over the sentence, the way his sheets carry both. It offers
            // itself on the shot you are in even while empty.
            // The one line that appears ABOVE the words, so it is the one
            // line that must never appear because you clicked: everything
            // you had aimed at would slide down under the pointer. It shows
            // when the shot has a title, and when Tab (or ⇧Tab from the
            // words) deliberately asks for it — never merely on selection.
            // Reserving its space instead left a blank line over every
            // untitled shot and pulled the number out of line with the text.
            // On every shot that has a title, and on the shot you are in —
            // his finding was that an untitled shot had nowhere to put one.
            // Drawing it on every shot regardless left a blank line over
            // each untitled paragraph and pulled the number out of line
            // with the words, which reads worse than it solves.
            // **Not on selection any more** (2026-09-30): an empty title
            // arriving on a click pushed the words down under the pointer,
            // one of the things that made moving about the page feel
            // clunky. It comes when the caret does — ⇧Tab from the words,
            // or Tab from the shot before.
            if !row.title.isEmpty || focusPart == .title {
                PageLine(
                    text: row.title,
                    placeholder: "Title",
                    font: Faces.font(type.face(.shotTitle),
                                     size: type.size(.shotTitle), bold: true),
                    colour: type.nsColour(.shotTitle),
                    wantsFocus: focusPart == .title,
                    onFocus: { has in
                        if has { onGo(.title) }
                    },
                    onCommit: { next in
                        guard next != row.title else { return }
                        onField("title", next)
                    },
                    onTab: { forward in onAdvance(.title, forward) }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            PageText(
                attributed: $text,
                font: font,
                colour: ink,
                wantsFocus: focusPart == .words,
                onCommit: onWrite,
                onNewShot: onNewShot,
                onFocus: { view in
                    onFocus(view)
                    if view != nil { onGo(.words) }
                },
                onTab: { forward in onAdvance(.words, forward) }
            )
            .frame(maxWidth: .infinity, minHeight: type.size(.body) + 5, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            // **The stretch of the script this shot quotes**, under its own
            // words, in the note's face with a hairline at its left — the
            // printed page's `shot-quote` (2026-09-19). Nothing on a film.
            if !row.script.isEmpty {
                Text(row.script)
                    .faced(type.face(.notes), type.size(.notes))
                    .foregroundStyle(type.colour(.notes))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(type.colour(.notes).opacity(0.5)).frame(width: 1.5)
                    }
                    .padding(.top, 3)
            }

            // Above its siblings: an open field's list hangs down over the
            // note and the frames, and has to draw over them, not under.
            technicalLine
                .zIndex(1)

            // A note is part of the page, so it is written on the page. It
            // offers itself only on the shot you are in — everywhere else an
            // empty note line would just be furniture.
            // Below the words: appearing here moves nothing a hand was
            // aiming at, so this one may follow the selection.
            if !row.notes.isEmpty || (selected && !marked) {
                PageLine(
                    text: row.notes,
                    placeholder: "Add a note",
                    font: Faces.font(type.face(.notes), size: type.size(.notes),
                                     italic: true),
                    colour: type.nsColour(.notes),
                    wantsFocus: focusPart == .note,
                    onFocus: { has in if has { onGo(.note) } },
                    onCommit: { next in
                        guard next != row.notes else { return }
                        onField("notes", next)
                    },
                    onTab: { forward in onAdvance(.note, forward) }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // …and the words above the frames, for the same hanging list.
        .zIndex(1)
    }

    /// The line reads like a line, and every part of it is a field you can
    /// edit in place. At rest it is a line of type; on the shot you are in,
    /// each part opens **the table's own picker** — same list, same chips,
    /// same Return grammar — hanging under the line instead of under a cell.
    /// The order is the table's column order, so the page and the table
    /// cannot disagree about where the lens sits.
    private var technicalLine: some View {
        // Wrapping, not a single row: beside a frame the words column can be
        // as narrow as half the measure, and a fixed row of fields overflowed
        // it — which shoved the frame clean off the paper.
        // The fields are always there — collapsed they are just the words of
        // the line, so the page reads the same on every shot, and ONE click
        // on any part of any line opens that part (selecting the shot on the
        // way). Empty parts only offer themselves on the shot you are in;
        // everywhere else they would be furniture.
        // A picked shot stays as it reads: walking the page with the arrows
        // should not make every shot grow and shrink as it is passed.
        let shown = fields.filter { (selected && !marked) || !value(of: $0).isEmpty }
        return WrappingRow(spacing: 4, runSpacing: 2) {
            if showCamera, let unit = row.unit {
                Text(type.cased(unit.label, .technical))
                    .faced(type.face(.technical), type.size(.technical), weight: .semibold)
                    .foregroundStyle(Brand.hex(unit.colour))
            }
            if shown.isEmpty, row.unit == nil {
                Text("—").faced(type.face(.technical), type.size(.technical))
                    .foregroundStyle(type.colour(.technical).opacity(0.55))
            }
            ForEach(Array(shown.enumerated()), id: \.element) { index, field in
                if index > 0 || (showCamera && row.unit != nil) {
                    Text("–").faced(type.face(.technical), type.size(.technical))
                        .foregroundStyle(type.colour(.technical).opacity(0.55))
                }
                PageField(
                    canCreate: canCreate(field),
                    field: field,
                    value: value(of: field),
                    type: type,
                    held: Columns.chosen(row, field),
                    options: { options(field) },
                    multi: Columns.isMulti(field),
                    dark: dark,
                    open: openField == field,
                    width: fieldWidth(field),
                    chip: { option in chip(field, option) },
                    onOpen: { onGo(.field(field)) },
                    onTake: { picked in onField(field, picked) },
                    onRemoveOption: { option in onRemoveOption(field, option) },
                    onClose: { if openField == field { onGo(nil) } },
                    onAdvance: { forward in onAdvance(.field(field), forward) }
                )
                // Over the parts after it, which it now floats across.
                .zIndex(openField == field ? 1 : 0)
            }
        }
        .padding(.top, 2)
    }

    private func value(of field: String) -> String {
        switch field {
        case "size": return row.size
        case "angle": return row.angle.joined(separator: ", ")
        case "movement": return row.movement
        case "lens": return row.lens
        case "modifiers": return row.modifierList.joined(separator: ", ")
        case "lens_filters": return row.lensFilters.joined(separator: ", ")
        case "support": return row.support
        default: return ""
        }
    }

    private func fieldWidth(_ field: String) -> CGFloat {
        switch field {
        case "angle": return 132
        case "size": return 78
        case "lens": return 62
        default: return 92
        }
    }

    @ViewBuilder
    private var frames: some View {
        if images.isEmpty {
            // **Nothing at all** — his call: a shot with no frames is a line
            // of prose, the way the real lists write them. A page of dashed
            // boxes reads as a form; a page of sentences reads as a shot list.
            // There is no placeholder to aim at because you do not have to
            // aim: drop a picture anywhere on the paragraph and it takes the
            // side you dropped it nearest.
            EmptyView()
        } else {
            HStack(spacing: 6) {
                ForEach(Array(images.enumerated()), id: \.offset) { _, still in
                    Frames.view(still.hash, still.filename, engine: engine,
                                trimStart: still.trimStart, trimEnd: still.trimEnd,
                                framing: still.framing, arrows: still.marks)
                        .frame(
                            width: (framePixels - CGFloat(images.count - 1) * 5)
                                / CGFloat(images.count),
                            height: (framePixels - CGFloat(images.count - 1) * 5)
                                / CGFloat(images.count) / ratio
                        )
                        // A picture is never rounded (his rule, 2026-10-07).
                        .clipShape(Rectangle())
                }
            }
            .frame(width: framePixels, alignment: .leading)
            // The resize handle lives on the frame's FREE edge. A frame on
            // the right of the text is anchored at the right margin — its
            // left edge is the one that moves, and a handle on the fixed
            // edge made every pull move the far side too: dragging right to
            // grow while the frame slid left, the "scales too quickly" feel.
            .overlay(alignment: row.framePosition == "right" ? .leading : .trailing) {
                resizeHandle
            }
            // Carried: the frame follows the hand, ghosted; where it would
            // land is drawn on the paragraph as a landing line — the same
            // blue line a carried column or row shows, not words.
            .offset(isCarrying ? carrying : .zero)
            .opacity(isCarrying ? 0.75 : 1)
            // A hold, then the carry — a plain drag stays the page's to
            // scroll with. Where the frame is let go decides its side: the
            // dominant direction of the carry, which is how a hand already
            // thinks about "put it on the right".
            .gesture(
                LongPressGesture(minimumDuration: 0.15)
                    .sequenced(before: DragGesture())
                    .onChanged { phase in
                        if case .second(true, let drag?) = phase {
                            // A press that began on the grabber, or while a
                            // resize is in flight, is never a carry.
                            guard isCarrying || (!overHandle && draggedWidth == nil)
                            else { return }
                            isCarrying = true
                            carrying = drag.translation
                        }
                    }
                    .onEnded { phase in
                        let carried = isCarrying
                        defer { isCarrying = false; carrying = .zero }
                        if carried, case .second(true, _?) = phase,
                           let target = carryTarget, target != row.framePosition {
                            // Moving between a side and above/below crosses
                            // the width cap, so the width is re-clamped for
                            // where it lands.
                            onLayout(target, Layouts.clamp(width, on: target))
                        }
                    }
            )
        }
    }

    /// Drag the edge to size it. Width is a fraction of the measure, so the
    /// page keeps its shape whatever the window or the paper is.
    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 12)
            .contentShape(Rectangle())
            .overlay {
                if selected {
                    Capsule().fill(Brand.accent(dark)).frame(width: 3, height: 22)
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { drag in
                        // On the right side the handle is the frame's LEFT
                        // edge: dragging left grows it.
                        let delta = row.framePosition == "right"
                            ? -drag.translation.width : drag.translation.width
                        let next = Double((framePixels + delta) / measure)
                        draggedWidth = min(widthCeiling, max(0.1, next))
                    }
                    .onEnded { _ in
                        if let w = draggedWidth { onLayout(row.framePosition, w) }
                        draggedWidth = nil
                    }
            )
            .onHover { inside in
                overHandle = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
    }

}

/// The text view every editable line of the page is made of. It grows with
/// its words — a sentence that outruns the line wraps to the next one, the
/// way a document behaves, never sliding off the page or clipping (the old
/// single-line fields did exactly that, his finding). It also knows how to
/// take the keyboard when Tab sends it here, and says so when a hand puts
/// the caret in it.
final class GrowText: NSTextView {
    var placeholder = ""
    var onFocusChange: ((Bool) -> Void)?
    /// Set when Tab wants this view before it has a window — the claim then
    /// happens the moment the window arrives.
    var pendingClaim = false
    private var claimTimer: Timer?

    override var intrinsicContentSize: NSSize {
        guard let container = textContainer, let manager = layoutManager else {
            return super.intrinsicContentSize
        }
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        return NSSize(width: NSView.noIntrinsicMetric,
                      height: ceil(used.height) + textContainerInset.height * 2)
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    // A new width reflows the words, and the reflow changes the height.
    override func setFrameSize(_ size: NSSize) {
        super.setFrameSize(size)
        invalidateIntrinsicContentSize()
    }

    override func becomeFirstResponder() -> Bool {
        let took = super.becomeFirstResponder()
        if took {
            cancelClaim()
            // The caret arrives after the last character — the table's rule
            // for an opened cell. A click that placed it somewhere specific
            // wins, because the click lands after this.
            setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
            onFocusChange?(true)
            needsDisplay = true
            // **The page follows the caret.** Tab onto a line below the fold
            // and the page brings it up, with a little air round it. A click
            // on a line already in view moves nothing.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scrollToVisible(self.bounds.insetBy(dx: 0, dy: -28))
            }
        }
        return took
    }

    override func resignFirstResponder() -> Bool {
        let gave = super.resignFirstResponder()
        if gave {
            onFocusChange?(false)
            needsDisplay = true
        }
        return gave
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if pendingClaim { claim() }
    }

    /// Words in a text view that is going away are words nobody asked to
    /// throw out. `textDidEndEditing` never fires for a view whose window is
    /// closing or whose paragraph is being rebuilt, so the line has to put
    /// itself away here — the silent-value-eater family, caught again.
    override func viewWillMove(toWindow window: NSWindow?) {
        super.viewWillMove(toWindow: window)
        if window == nil, isFirstResponder { onLeaving?() }
    }
    var onLeaving: (() -> Void)?

    override func draw(_ rect: NSRect) {
        super.draw(rect)
        if string.isEmpty, !placeholder.isEmpty {
            (placeholder as NSString).draw(
                at: NSPoint(x: textContainerInset.width
                                + (textContainer?.lineFragmentPadding ?? 0),
                            y: textContainerInset.height),
                withAttributes: [
                    .font: font ?? NSFont.systemFont(ofSize: 12),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ])
        }
    }

    /// Takes the keyboard — only in a key window, which a checking run's
    /// window never is. The same safety catch as the table's editor: asking
    /// for a key event without one would bring the app to the front.
    /// The claim **retries**, the way the table's editor does. A line Tab
    /// lands on may not exist yet when the key arrives — crossing into the
    /// next shot creates its title line — and a single attempt made that hop
    /// depend on winning a race with SwiftUI's layout. In front of a person
    /// it claims within a tick; in a quiet check the window never becomes
    /// key and the poll expires having asked for nothing.
    func claim() {
        guard !isFirstResponder else { return }
        claimTimer?.invalidate()
        if let window, window.isKeyWindow || PageKeys.driving {
            window.makeFirstResponder(self)
            if isFirstResponder { return }
        }
        pendingClaim = true
        var tries = 0
        let poll = Timer(timeInterval: 0.03, repeats: true) { [weak self] timer in
            guard let self, self.pendingClaim, !self.isFirstResponder else {
                timer.invalidate(); return
            }
            tries += 1
            if tries > 12 { self.cancelClaim(); return }
            guard let window = self.window, window.isKeyWindow || PageKeys.driving
            else { return }
            window.makeFirstResponder(self)
        }
        claimTimer = poll
        RunLoop.main.add(poll, forMode: .common)
    }

    /// Stop wanting the keyboard. Load-bearing: a poll that outlives the
    /// moment its line was wanted goes on calling `makeFirstResponder` and
    /// yanks the keyboard back out of wherever Tab has since moved it —
    /// several lines fighting over the caret, which is exactly the clunk
    /// this rebuild is here to remove.
    func cancelClaim() {
        pendingClaim = false
        claimTimer?.invalidate()
        claimTimer = nil
    }

    static func page(rich: Bool) -> GrowText {
        let view = GrowText()
        view.isRichText = rich
        view.allowsUndo = true
        view.drawsBackground = false
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.lineFragmentPadding = 0
        view.textContainerInset = NSSize(width: 0, height: 2)
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        return view
    }
}

/// The page's text view: `RichText` plus the page's own keys — Shift-Enter
/// starts the next shot, Tab walks to the next field, and focus is reported
/// so the formatting bar knows whose selection it is working.
private struct PageText: NSViewRepresentable {
    @Binding var attributed: NSAttributedString
    var font: NSFont
    var colour: NSColor
    var wantsFocus: Bool
    var onCommit: (NSAttributedString) -> Void
    var onNewShot: () -> Void
    var onFocus: (NSTextView?) -> Void
    var onTab: (Bool) -> Void

    func makeNSView(context: Context) -> GrowText {
        let text = GrowText.page(rich: true)
        text.delegate = context.coordinator
        text.font = font
        text.textColor = colour
        text.textStorage?.setAttributedString(attributed)
        text.onFocusChange = { [weak text] has in
            context.coordinator.parent.onFocus(has ? text : nil)
        }
        text.onLeaving = { [weak text] in
            guard let storage = text?.textStorage else { return }
            context.coordinator.parent.onCommit(
                NSAttributedString(attributedString: storage))
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak text] _ in
            guard let text, text.isFirstResponder,
                  let storage = text.textStorage else { return }
            context.coordinator.parent.onCommit(
                NSAttributedString(attributedString: storage))
        }
        context.coordinator.text = text
        return text
    }

    func updateNSView(_ text: GrowText, context: Context) {
        context.coordinator.parent = self
        if text.window?.firstResponder !== text,
           text.textStorage?.string != attributed.string {
            text.textStorage?.setAttributedString(attributed)
            text.invalidateIntrinsicContentSize()
        }
        // **A change to Body has to reach the words already on the page.**
        //
        // It did not, and that was his report of 2026-09-03: *"the body didn't
        // seem to change size with my adjustments"*. This wrote only
        // `typingAttributes` — which style the *next* character typed — and
        // replaced the storage only when the string itself differed, so moving
        // Body moved nothing that was already written.
        //
        // It was written that way on purpose, after his 2026-08-20 correction
        // that a face applies to the selection and not the paragraph. Both are
        // now true at once, because `Rich.chosen` marks the runs he sized or
        // refaced himself and `repage` steps around them.
        if context.coordinator.set != font {
            context.coordinator.set = font
            if let storage = text.textStorage { Rich.repage(storage, to: font) }
            text.invalidateIntrinsicContentSize()
        }
        // Black type written in daylight would stay black at night without
        // this, and that is not a decision anybody made.
        if context.coordinator.inked != colour {
            context.coordinator.inked = colour
            if let storage = text.textStorage { Rich.recolour(storage, to: colour) }
        }
        text.typingAttributes[.font] = font
        text.typingAttributes[.foregroundColor] = colour
        if wantsFocus { text.claim() } else { text.cancelClaim() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PageText
        weak var text: NSTextView?
        /// The ink the storage was last given, so it is only re-inked when
        /// the appearance actually changes.
        var inked: NSColor?
        /// The page font the storage was last set to, so the words are only
        /// re-set when the class actually moves.
        var set: NSFont?

        init(_ parent: PageText) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let text = notification.object as? NSTextView,
                  let storage = text.textStorage else { return }
            parent.attributed = NSAttributedString(attributedString: storage)
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let text = notification.object as? NSTextView else { return }
            commit(text)
        }

        func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                // Shift+Enter starts the next shot; plain Return stays in the
                // paragraph, because a description is prose and sometimes
                // wraps.
                if NSEvent.modifierFlags.contains(.shift) {
                    commit(view)
                    parent.onNewShot()
                    return true
                }
                return false
            case #selector(NSResponder.insertTab(_:)):
                commit(view)
                parent.onTab(true)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                commit(view)
                parent.onTab(false)
                return true
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

/// A formatting-bar button that answers the pointer, the way every other
/// control in the chrome does. A bar of buttons that give nothing back on
/// hover reads as a picture of a toolbar rather than a toolbar.
private struct BarButton: View {
    let symbol: String
    let help: String
    let dark: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11))
                .foregroundStyle(hovering ? Brand.ink(dark) : Brand.ink2(dark))
                .frame(width: 22, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: Brand.radiusSmall)
                        .fill(hovering ? Brand.cellHover(dark) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// A single line of the page — the title over the words, the note under
/// them — that behaves like a line *of a document*: it wraps when it
/// outruns its width instead of clipping, Return puts it away and stays,
/// and Tab walks on to the next field.
private struct PageLine: NSViewRepresentable {
    let text: String
    let placeholder: String
    let font: NSFont
    let colour: NSColor
    let wantsFocus: Bool
    let onFocus: (Bool) -> Void
    let onCommit: (String) -> Void
    let onTab: (Bool) -> Void

    func makeNSView(context: Context) -> GrowText {
        let view = GrowText.page(rich: false)
        view.delegate = context.coordinator
        view.placeholder = placeholder
        view.font = font
        view.textColor = colour
        view.string = text
        view.onFocusChange = { has in
            context.coordinator.parent.onFocus(has)
        }
        view.onLeaving = { [weak view] in
            guard let view else { return }
            context.coordinator.parent.onCommit(view.string)
        }
        // The app quitting is the other way a line goes away without ever
        // ending its editing.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak view] _ in
            guard let view, view.isFirstResponder else { return }
            context.coordinator.parent.onCommit(view.string)
        }
        return view
    }

    func updateNSView(_ view: GrowText, context: Context) {
        context.coordinator.parent = self
        if !view.isFirstResponder, view.string != text {
            view.string = text
            view.invalidateIntrinsicContentSize()
        }
        view.placeholder = placeholder
        view.font = font
        view.textColor = colour
        view.typingAttributes[.font] = font
        view.typingAttributes[.foregroundColor] = colour
        if wantsFocus { view.claim() } else { view.cancelClaim() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PageLine
        init(_ parent: PageLine) { self.parent = parent }

        func textDidEndEditing(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.onCommit(view.string)
        }

        func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                // Return puts the line away and stays — the app's rule. A
                // title or a note is one paragraph; it wraps, it does not
                // take a line break.
                parent.onCommit(view.string)
                return true
            case #selector(NSResponder.insertTab(_:)):
                parent.onCommit(view.string)
                parent.onTab(true)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                parent.onCommit(view.string)
                parent.onTab(false)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                // Escape walks away: the words go back to what the shot holds.
                view.string = parent.text
                view.window?.makeFirstResponder(nil)
                return true
            default:
                return false
            }
        }
    }
}

/// A part of the technical line, worn two ways. At rest it is a word in the
/// line. Open, it is **the table's picker** — the same ranked list, the same
/// chips and checkmarks, the same Return grammar — hanging under the line
/// the way the table's hangs under a cell. One picker, two costumes; the old
/// combo boxes (a third grammar nothing else had) are gone.
private struct PageField: View {
    /// Whether this field's list will take a term it has never seen. Passed in
    /// rather than looked up: the page's fields are drawn far from the shell.
    var canCreate: Bool = true
    let field: String
    let value: String
    /// How the technical line is set — the one class this field draws in.
    var type: PageType = PageType(nil)
    let held: [String]
    /// **Asked for only when the list opens.**
    ///
    /// This was the list itself, and building it means asking the engine for
    /// every distinct value of that field across the whole film. Drawn eagerly
    /// it happened once per field per shot on every single pass — five
    /// scans of a two-hundred-shot document per shot, several hundred times a
    /// redraw, to fill a dropdown that is shut. It is the cause of his
    /// *"it's feeling sluggish"*, 2026-09-04.
    let options: () -> [String]
    let multi: Bool
    let dark: Bool
    let open: Bool
    let width: CGFloat
    let chip: (String) -> Color?
    let onOpen: () -> Void
    let onTake: (String) -> Void
    let onRemoveOption: (String) -> Void
    let onClose: () -> Void
    let onAdvance: (Bool) -> Void

    /// What has been typed — a filter, never a value. The table's rule.
    @State private var filter = ""
    @State private var pickAt = 0
    /// Whether anything was typed or the highlight moved. A pristine
    /// picker's Return closes it writing nothing — Return-Return is safe.
    @State private var touched = false
    /// Return puts the LIST away and leaves the keyboard where it is — his
    /// call: "submit that answer and go back to the same cell without
    /// changing cell selection, but have the dropdown close." The field
    /// stays open (still the page's caret, still typeable), so the next Tab
    /// is what moves on. Closing the field outright made the caret vanish.
    @State private var listShown = true

    private var entries: [Pick] {
        let options = self.options()
        var out = Columns.rank(options, query: filter).map { Pick.value($0) }
        if canCreate, let novel = Columns.novel(options, query: filter) {
            out.append(.create(novel))
        }
        return out
    }

    /// **The word stays in the line; the open box floats over it.** The box
    /// used to take the word's place, and being wider it shoved every part
    /// after it along — so a click on the next part landed on something that
    /// then jumped as the first one closed. Now the line never moves.
    var body: some View {
        Text(value.isEmpty ? Columns.label(field)
             : type.cased(value, .technical))
            .faced(type.face(.technical), type.size(.technical))
            // The line is Technical, so it is drawn in Technical's ink —
            // an empty part still only offers its name, quietly.
            .foregroundStyle(value.isEmpty
                             ? type.colour(.technical).opacity(0.45)
                             : type.colour(.technical))
            .opacity(open ? 0 : 1)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .overlay(alignment: .topLeading) {
                if open { openBox.offset(x: -7, y: -4) }
            }
    }

    private var openBox: some View {
        FieldFilter(
            text: $filter,
            ghost: value.isEmpty ? "type to filter" : value,
            dark: dark,
            onType: { typed in
                filter = typed
                // Every keystroke re-filters, so the highlight goes back to
                // the top of what is left — the table's rule.
                pickAt = 0
                // "Touched" must mean a hand actually chose something —
                // typed a filter or walked the list. An *empty* text change
                // (the field being made, or cleared) is not a choice, and
                // counting it made a plain Return take whatever sat at the
                // top of the unfiltered list: on a multi field that toggled
                // the value the shot already held straight back off.
                if !typed.isEmpty { touched = true }
            },
            onCommand: command
        )
        .frame(width: width, height: 16)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background {
            RoundedRectangle(cornerRadius: Brand.radiusSmall)
                .fill(Brand.panel(dark))
                .shadow(color: .black.opacity(dark ? 0.55 : 0.16), radius: 14, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Brand.radiusSmall)
                .strokeBorder(Brand.accent(dark), lineWidth: 1.5)
        }
        .overlay(alignment: .topLeading) {
            if listShown { list.offset(y: 24) }
        }
        .onAppear(perform: arrive)
        .onChange(of: listShown) { _, shown in PageProbe.list = shown ? field : nil }
        .onDisappear { if PageProbe.list == field { PageProbe.list = nil } }
    }

    /// The list opens with the highlight on the value the field holds, so
    /// Return-Return changes nothing — the table's opening move.
    private func arrive() {
        PageProbe.list = field
        filter = ""
        touched = false
        pickAt = 0
        listShown = true
        if !multi, !value.isEmpty {
            pickAt = entries.firstIndex {
                if case .value(let option) = $0 { return option == value }
                return false
            } ?? 0
        }
    }

    private func command(_ key: FieldFilter.Command) {
        let chose = pickAt < entries.count && (touched || !filter.isEmpty)
        switch key {
        case .down, .up:
            touched = true
            // An arrow with the list away brings it back — that is what an
            // arrow means at a picker.
            if !listShown { listShown = true; return }
            pickAt = key == .down
                ? min(pickAt + 1, max(entries.count - 1, 0))
                : max(pickAt - 1, 0)
        case .ret:
            // Return takes what is highlighted, never the half-word that
            // filtered the list. Then the list goes away and the keyboard
            // stays on this field: the cursor does not move, and nothing is
            // left hanging open over the page.
            if chose { take(entries[pickAt]) }
            if multi, chose {
                // A multi field goes on gathering: the tick moves, the list
                // stays, the filter clears — pristine again, so the next
                // plain Return puts the list away like any other.
                filter = ""; touched = false; pickAt = 0
            } else {
                filter = ""; touched = false; pickAt = 0
                listShown = false
            }
        case .tab, .backtab:
            if chose { take(entries[pickAt]) }
            onAdvance(key == .tab)
        case .escape:
            // Escape gives up the whole field, list and caret together.
            onClose()
        case .settle:
            // The page is moving on without a Tab — ⌘↩ for a new shot. What
            // a hand chose is taken, exactly as Tab would take it.
            if chose { take(entries[pickAt]) }
        }
    }

    private func take(_ entry: Pick) {
        switch entry {
        case .value(let option): onTake(option)
        case .create(let novel): onTake(novel)
        case .attach(_, let name): onTake(name)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            if filter.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11)).foregroundStyle(Brand.ink4(dark))
                    Text("Search or create")
                        .sans(13).foregroundStyle(Brand.ink4(dark))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                Divider().overlay(Brand.rule(dark))
            }
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { at, entry in
                            listRow(entry, at: at).id(at)
                        }
                        if entries.isEmpty {
                            Text("Empty")
                                .sans(13).foregroundStyle(Brand.ink4(dark))
                                .padding(.horizontal, 8).padding(.vertical, 6)
                        }
                    }
                    .padding(6)
                    // A swipe over the list scrolls the list, never the page.
                    .background { ListScroll(steer: true) }
                }
                .onChange(of: pickAt) { _, at in reader.scrollTo(at, anchor: nil) }
            }
        }
        .frame(width: 268, alignment: .leading)
        .frame(maxHeight: 240, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            RoundedRectangle(cornerRadius: Brand.radiusChip)
                .fill(Brand.panel(dark))
                .shadow(color: .black.opacity(dark ? 0.55 : 0.18), radius: 12, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Brand.radiusChip).strokeBorder(Brand.rule(dark), lineWidth: 1)
        }
        // A click between the rows is still a click on the list: without
        // this it fell through to the page, which lets go of everything.
        .contentShape(Rectangle())
        .onTapGesture { }
    }

    private func listRow(_ entry: Pick, at: Int) -> some View {
        let lit = at == pickAt
        return HStack(spacing: 6) {
            Button {
                take(entry)
                filter = ""; touched = false; pickAt = 0
                if !multi { listShown = false }
            } label: {
                HStack(spacing: 6) {
                    switch entry {
                    case .value(let option):
                        Chip(text: option, colour: chip(option))
                        if held.contains(option) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Brand.accent(dark))
                        }
                    case .create(let novel):
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11)).foregroundStyle(Brand.accent(dark))
                        Text("Create “\(novel)”").sans(13, weight: .medium)
                            .foregroundStyle(Brand.ink(dark))
                    case .attach(_, let name):
                        Text(name).sans(13)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()

            // A camera is a unit the project owns, not a word on a list —
            // but camera is not on the page's line, so every field here is a
            // vocabulary with a removable term.
            if case .value(let option) = entry {
                Menu {
                    Button("Remove from the \(Columns.label(field)) list",
                           role: .destructive) {
                        onRemoveOption(option)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.ink3(dark))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 18)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            if lit {
                RoundedRectangle(cornerRadius: Brand.radiusChip, style: .continuous).fill(Brand.accentTint(dark))
            }
        }
    }
}

/// The open field's text box: what is typed filters the list; the keys that
/// are the picker's — arrows, Return, Tab, Escape — come back as commands.
private struct FieldFilter: NSViewRepresentable {
    @Binding var text: String
    let ghost: String
    let dark: Bool
    let onType: (String) -> Void
    let onCommand: (Command) -> Void

    enum Command { case up, down, ret, tab, backtab, escape, settle }

    /// Takes the keyboard the moment it is in a window — the field only
    /// exists while its picker is open, which only happens under a hand.
    /// Key-window-only, the same safety catch as everywhere else.
    final class ClaimField: NSTextField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            claim(tries: 0)
        }

        /// **A text field never *is* the first responder** — the window's
        /// field editor is, on its behalf. Testing `isFirstResponder` here
        /// therefore always said "no", so the retry below went on calling
        /// `makeFirstResponder` every 30ms; each call re-installs the field
        /// editor and selects all its text, so every letter typed replaced
        /// the one before it. "Pro" arrived as "P", "r", "o" and the picker
        /// filtered on a single letter. `currentEditor()` is the real test.
        private var holdsKeyboard: Bool { currentEditor() != nil }

        /// **The field and its list, in view.** The page never followed the
        /// caret, so a field opened low in the window hung its list off the
        /// bottom edge — out of sight, and out of reach of the wheel. The
        /// least scroll that shows the box and the list hanging under it.
        func showList() {
            let under: CGFloat = 300
            let reach = isFlipped
                ? NSRect(x: -8, y: -8, width: 280, height: bounds.height + under)
                : NSRect(x: -8, y: bounds.height + 8 - (bounds.height + under),
                         width: 280, height: bounds.height + under)
            DispatchQueue.main.async { [weak self] in self?.scrollToVisible(reach) }
        }

        /// Retried, for the same reason the page's lines retry: a field that
        /// Tab opened is created and laid out over more than one pass, and a
        /// single attempt made the hop a race.
        private func claim(tries: Int) {
            // A field taken out of the page — because its picker closed, or
            // Tab moved on — must stop asking, or its poll pulls the caret
            // back out of wherever the keyboard has since gone.
            guard window != nil, !holdsKeyboard, tries < 12 else { return }
            if let window, window.isKeyWindow || PageKeys.driving {
                window.makeFirstResponder(self)
                if holdsKeyboard { showList(); return }
            }
            let poll = Timer(timeInterval: 0.03, repeats: false) { [weak self] _ in
                self?.claim(tries: tries + 1)
            }
            RunLoop.main.add(poll, forMode: .common)
        }
    }

    func makeNSView(context: Context) -> ClaimField {
        let field = ClaimField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        field.textColor = NSColor(Brand.ink(dark))
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: ClaimField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        field.placeholderAttributedString = NSAttributedString(
            string: ghost,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
                .foregroundColor: NSColor(Brand.ink4(dark)),
            ])
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FieldFilter
        init(_ parent: FieldFilter) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.onType(field.stringValue)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            // Deliberately does **not** put the page's caret away. Ending
            // editing happens *because* Tab already moved the caret on, and
            // this fires after — so clearing here wiped the destination that
            // had just been set, leaving the page with no caret and the next
            // Tab free to walk out of the document into the sidebar.
            // Walking away writes nothing either way: the filter text is a
            // search, not a value, and every deliberate path (Return, Tab,
            // clicking an option) has already committed by now.
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveDown(_:)): parent.onCommand(.down); return true
            case #selector(NSResponder.moveUp(_:)): parent.onCommand(.up); return true
            case #selector(NSResponder.insertNewline(_:)): parent.onCommand(.ret); return true
            case #selector(NSResponder.insertTab(_:)): parent.onCommand(.tab); return true
            case #selector(NSResponder.insertBacktab(_:)): parent.onCommand(.backtab); return true
            case #selector(NSResponder.cancelOperation(_:)): parent.onCommand(.escape); return true
            default: return false
            }
        }
    }
}

/// Children on a line, wrapping when the line is full — what the technical
/// fields need beside a frame, where the column can be half the measure.
///
/// Not private: the script import's keyword lists wrap the same way, and a
/// second copy of a layout is a second place for it to be wrong.
struct WrappingRow: Layout {
    var spacing: CGFloat = 4
    var runSpacing: CGFloat = 3

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let room = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, tallest: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > room {
                x = 0
                y += tallest + runSpacing
                tallest = 0
            }
            x += size.width + spacing
            tallest = max(tallest, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: room == .infinity ? widest : room, height: y + tallest)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, tallest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += tallest + runSpacing
                tallest = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            tallest = max(tallest, size.height)
        }
    }
}


/// How big a shot's paragraph came out — reported as a preference so the size
/// arrives once per layout pass rather than as a write from inside one.
private struct BlockSize: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}
