import SwiftUI
import AppKit

/// **A value worked out once and kept.**
///
/// Small, deliberate and used only for things that are pure and cheap to key:
/// a colour from a hex string, a font from a face and a size. Nothing that can
/// go stale goes in one — a memo whose answer can change is a cache, and a
/// cache is a bug waiting for a reason.
/// **How much of the film a single pass actually builds.**
///
/// A `LazyVStack` is a promise, not a guarantee: nest it wrongly and it builds
/// every row it has. Nothing could see that — a check draws once, and once is
/// cheap however much of the film it drew. This counts.
enum Built {
    nonisolated(unsafe) static var rows = 0
    nonisolated(unsafe) static var paragraphs = 0
    static func reset() { rows = 0; paragraphs = 0 }
}

final class Memo<Key: Hashable, Value> {
    private var kept: [Key: Value] = [:]
    private let gate = NSLock()

    func value(for key: Key, _ work: (Key) -> Value) -> Value {
        gate.lock()
        if let already = kept[key] { gate.unlock(); return already }
        gate.unlock()
        let made = work(key)
        gate.lock(); kept[key] = made; gate.unlock()
        return made
    }
}

/// The design system, in Swift.
///
/// Same token *shape* as the old app's `Theme.swift`, so views port across
/// mechanically — every accessor here has the name it had there. What changed
/// are the values: the old app wears cream and a deep blue, Studio wears
/// Cadrage's near-white chrome, hairline rules and one system-ish blue.
///
/// Where SwiftUI has a default, it is not used: a default control is a decision
/// made by somebody who has not seen this project.
enum Brand {
    /// **Every colour in the app comes through here, and it used to parse a
    /// string every single time.**
    ///
    /// `Brand.ink(dark)` is `pick` is `hex("17171A")` — a trim, a character
    /// walk and a radix parse, for a value that has never once been different.
    /// SwiftUI re-runs a body whenever anything it reads changes, so on a
    /// document of two hundred shots that is tens of thousands of string parses
    /// to redraw one page. Part of his *"it's feeling sluggish"*, 2026-09-04.
    ///
    /// Held behind a lock because a colour is also asked for while a page is
    /// being printed, which does not always happen on the drawing thread.
    private static let inks = Memo<String, Color>()

    static func hex(_ s: String) -> Color {
        inks.value(for: s) { said in
            var t = said.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            if t.count == 3 { t = t.map { "\($0)\($0)" }.joined() }
            guard let v = UInt64(t, radix: 16), t.count == 6 else { return .gray }
            return Color(
                .sRGB,
                red: Double((v >> 16) & 0xFF) / 255,
                green: Double((v >> 8) & 0xFF) / 255,
                blue: Double(v & 0xFF) / 255
            )
        }
    }

    /// The same colour as AppKit's. **`NSColor(Color)` crosses the SwiftUI
    /// bridge**, which is far more expensive than it looks and was being paid
    /// once per shot per pass for the page's title and note ink.
    private static let appkitInks = Memo<String, NSColor>()

    static func nsHex(_ s: String) -> NSColor {
        appkitInks.value(for: s) { NSColor(hex($0)) }
    }

    /// A colour out of the one-look kit (`shared/Kit.swift`).
    static func kit(_ dark: Bool, _ pair: Kit.Pair) -> Color { pick(dark, pair.light, pair.dark) }

    static func pick(_ dark: Bool, _ light: String, _ night: String) -> Color {
        hex(dark ? night : light)
    }

    // ---- ground ---------------------------------------------------------
    // **The glass palette** — a prototype, on its own branch, from his
    // Raycast/Glaze mock-up of 2026-08-20. He did not want its layout ("a
    // little too condensed") and did not want its right-hand inspector. What
    // he wanted was the *look*: glassier elements, rounded panels, pill tabs,
    // rounded chrome buttons, and above all a darker palette where **the inner
    // panel is close to black**.
    //
    // That last one is an inversion. Studio's dark mode had the content
    // *lighter* than the chrome around it — a white sheet's logic carried into
    // the dark. The mock does the opposite: the chrome is grey and the list is
    // a well cut into it. It reads far more like a current Mac app, and it is
    // the single change that does most of the work here.

    /// The content well. White in the day; **near black at night**.
    static func surface(_ d: Bool) -> Color { kit(d, Kit.Ink.surface) }
    /// Chrome: the sidebar, the toolbar, anything that is not content — and
    /// now *lighter* than the content in the dark, not darker.
    static func surface2(_ d: Bool) -> Color { kit(d, Kit.Ink.panel) }
    static func surface3(_ d: Bool) -> Color { pick(d, "F8F8F9", "17171B") }

    /// The ground the content surfaces float on — a shade back from the card
    /// so a rounded table reads as a sheet lying on a desk rather than as a
    /// rectangle with its corners cut off.
    /// The window's own ground. **Darker than the panels that float on it** —
    /// the first cut had them within four values of each other and the air
    /// round a panel said nothing at all, which is the whole effect. Three
    /// levels now, and they mean three different things: panels *lift* above
    /// this, and the content well is *cut into* it.
    static func ground(_ d: Bool) -> Color { kit(d, Kit.Ink.ground) }

    static func rowAlt(_ d: Bool) -> Color { pick(d, "FCFCFD", "121216") }
    static func rowHover(_ d: Bool) -> Color { pick(d, "F5F5F7", "1A1A1F") }
    static func cellHover(_ d: Bool) -> Color { pick(d, "EAEAEE", "26262C") }
    /// A selected row when the list does not have the keyboard — grey, not blue.
    static func selectionQuiet(_ d: Bool) -> Color { pick(d, "E9E9EE", "26262E") }

    // ---- ink ------------------------------------------------------------
    static func ink(_ d: Bool) -> Color { kit(d, Kit.Ink.ink) }
    static func ink2(_ d: Bool) -> Color { kit(d, Kit.Ink.ink2) }
    static func ink3(_ d: Bool) -> Color { kit(d, Kit.Ink.ink3) }
    static func ink4(_ d: Bool) -> Color { kit(d, Kit.Ink.ink4) }

    // ---- rules ----------------------------------------------------------
    static func rule(_ d: Bool) -> Color { kit(d, Kit.Ink.rule) }
    /// The line *between columns*. Much quieter than the line between rows,
    /// deliberately: a full-strength grid in both directions is what makes a
    /// table read as a spreadsheet, and his verdict on this app was that it
    /// felt too technical. Rows are what a person reads; columns are only how
    /// the row is arranged.
    /// **Nothing at all**, in the glass palette. The mock draws no vertical
    /// grid whatsoever, and that is most of why its table reads as a list of
    /// shots rather than as a spreadsheet. Kept as a token rather than deleted
    /// so the two branches stay diffable.
    static func ruleFaint(_ d: Bool) -> Color { .clear }
    static func rule2(_ d: Bool) -> Color { kit(d, Kit.Ink.chip) }

    /// **Ink on a picture**, where the ground is somebody's photograph and no
    /// palette colour can be trusted to sit on it. The one place a raw white
    /// is right — and it is a token so it reads as a decision rather than as
    /// nine views that each reached for `.white`.
    static let onImage: Color = .white
    /// Something is wrong and the words have to say so. Rare on purpose.
    static func warn(_ d: Bool) -> Color { pick(d, "C0392B", "FF6B5E") }
    static func ruleStrong(_ d: Bool) -> Color { pick(d, "B7B7BE", "4E4E56") }

    // ---- accent ---------------------------------------------------------
    // ---- the accent, and whose it is ------------------------------------
    // **The film's colour, when the film has one.**
    //
    // His instruction, 2026-09-05: *"lets have the desktop app respect what the
    // web app is doing. using the project accent color, and icon."* The website
    // already does exactly this — a film's pages, and the app inside them, are
    // drawn in the colour of that film's Notion row (`film.js`, `accent()`).
    // The Mac reads the same Notion row, out of the copy his Projects Console
    // keeps on disk, so the two cannot drift.
    //
    // **One global, written from one place.** Every accent in the app comes
    // through `accent(_:)` — sixty-odd views, none of which knows or should
    // know which film is open. Threading a colour through all of them would be
    // sixty changes to carry one fact that is the same everywhere in the
    // window. `ShellState.wearTheFilmsColour()` is the only writer, and it
    // writes on opening a film and on the link changing, never mid-draw.
    nonisolated(unsafe) private static var worn = ""

    /// Wear a film's colour, or `""` to go back to the program's own blue.
    static func wear(colour: String) {
        let said = colour.trimmingCharacters(in: .whitespaces)
        worn = said.count == 7 && said.hasPrefix("#")
            && said.dropFirst().allSatisfy(\.isHexDigit) ? said : ""
    }

    /// What the app is wearing, for a check to read back.
    static var wearing: String { worn }

    static func accent(_ d: Bool) -> Color {
        worn.isEmpty ? kit(d, Kit.Ink.blue) : hex(worn)
    }
    static func accentTint(_ d: Bool) -> Color { accent(d).opacity(d ? 0.22 : 0.11) }
    static func accentLine(_ d: Bool) -> Color { accent(d).opacity(d ? 0.45 : 0.30) }
    /// **White on a film's colour, in both lights.** Which is what the website
    /// switches to the moment a film's hue takes over (`--on-accent:#fff`). The
    /// program's own blue is bright enough at night to want dark text on it; a
    /// Notion icon colour never is.
    static func onAccent(_ d: Bool) -> Color {
        worn.isEmpty ? pick(d, "FFFFFF", "141416") : hex("FFFFFF")
    }

    // ---- glass ----------------------------------------------------------
    /// The hairline where a floating thing meets the ground, and the light
    /// caught on its top edge. Without the second one glass reads as flat grey.
    static func glassLine(_ d: Bool) -> Color {
        d ? Color.black.opacity(0.46) : Color.black.opacity(0.10)
    }
    static func glassEdge(_ d: Bool) -> Color {
        d ? Color.white.opacity(0.07) : Color.white.opacity(0.80)
    }
    /// A band lying on a surface — a scene's heading inside the table. It has
    /// to read as a band in daylight too, where a translucent white on white
    /// reads as nothing at all.
    static func band(_ d: Bool) -> Color { pick(d, "F4F4F7", "1A1A20") }

    /// A floating panel's own ground — a touch lighter than the window behind
    /// it, so it lifts without needing a border to say so.
    static func panel(_ d: Bool) -> Color { pick(d, "FAFAFC", "212127") }

    static func glass2(_ d: Bool) -> Color {
        d ? hex("2C2C33").opacity(0.55) : hex("FFFFFF").opacity(0.74)
    }

    // ---- paper ----------------------------------------------------------
    /// The document view's page and the desk it lies on. The desk is markedly
    /// darker than the app's surfaces on purpose — it is what makes the page
    /// read as a sheet of paper rather than as a narrower window.
    static func paper(_ d: Bool) -> Color { pick(d, "FFFFFF", "202024") }
    static func desk(_ d: Bool) -> Color { pick(d, "A8A8AF", "0E0E10") }
    /// **The stage a page lies on when the page nearly fills it.**
    ///
    /// `desk` above is the Document view's answer to the same question and is
    /// deliberately heavy — there a narrow page sits on a wide desk and the
    /// contrast is what makes it read as paper. In the export box the sheet
    /// fills the well, so the same tone comes back as a thick grey border
    /// round a picture rather than as a surface under it. This is the quieter
    /// one: still darker than the window in both themes, so white paper is
    /// still paper, but a rim of it does not shout.
    static func stage(_ d: Bool) -> Color { pick(d, "E6E6EA", "09090C") }
    static func paperEdge(_ d: Bool) -> Color {
        d ? Color.white.opacity(0.10) : Color.black.opacity(0.13)
    }

    // ---- frames ---------------------------------------------------------
    static func frameEmpty(_ d: Bool) -> Color { pick(d, "EFEFF2", "2A2A2E") }
    static func frameLine(_ d: Bool) -> Color {
        d ? Color.white.opacity(0.11) : Color.black.opacity(0.13)
    }
    static func frameMask(_ d: Bool) -> Color {
        d ? Color.black.opacity(0.34) : Color.black.opacity(0.06)
    }

    // ---- measurements ---------------------------------------------------
    /// Table density. Row height and frame size follow it, so making the table
    /// bigger makes the whole row bigger rather than stretching a fixed row
    /// until the type looks lost in it.
    static var density: CGFloat = CGFloat(
        UserDefaults.standard.object(forKey: "tableDensity") as? Double ?? 1.0)
    /// The four sizes ⌘+ and ⌘− walk — the old app's steps, kept.
    static let comfortable: [CGFloat] = [0.85, 1.0, 1.18, 1.4]
    static var rowHeight: CGFloat { 64 * density }
    static var frameWidth: CGFloat { 104 * density }

    /// **A type size at the table's current density.**
    ///
    /// ⌘+ and ⌘− were making the *row* bigger and smaller while the words
    /// inside it stayed one size — so a shrunken row could not hold its own
    /// text, which is his "some of the text escapes its box", and a row whose
    /// content was already taller than the floor did not move at all, which is
    /// his "not all shots are affected". The words follow the row now. Half
    /// points, because whole ones are a visible jump at 10pt.
    static func type(_ size: CGFloat) -> CGFloat { type(size, at: density) }

    /// The same, told which density to use instead of reading the global.
    ///
    /// `density` is a plain `static var`, which SwiftUI cannot observe. A view
    /// that reads it *inside* its own body — `Chip` did — only resizes when
    /// SwiftUI runs that body, and SwiftUI decides that by comparing the
    /// view's stored properties. A chip's text and colour do not change when
    /// the zoom does, so the comparison said "identical", the body never ran,
    /// and the pill kept the size it was first built at while every
    /// measurement around it grew. Taking the density *in* is what makes the
    /// change visible to SwiftUI at all.
    static func type(_ size: CGFloat, at density: CGFloat) -> CGFloat {
        (size * density * 2).rounded() / 2
    }

    /// The air inside a cell, at the same density. Left alone at 1.0, so no
    /// coordinate a check has measured moves.
    static func pad(_ points: CGFloat) -> CGFloat { pad(points, at: density) }

    /// Same reasoning as `type(_:at:)` above.
    static func pad(_ points: CGFloat, at density: CGFloat) -> CGFloat {
        (points * density).rounded()
    }

    static let sidebarWidth: CGFloat = 258

    // ---- the scales -----------------------------------------------------
    // **Seven type sizes, eight icon sizes, a 2pt grid and five corners.**
    // Before 2026-09-08 the app drew text at 42 different sizes, gaps at 30
    // and corners at 12 — sizes half a point apart, which nobody can see one
    // at a time and everybody can see all at once. Every one of them rounded
    // to its nearest step here, ties going to whichever neighbour more of the
    // app already used, so almost nothing moved and the vocabulary is finite.
    //
    // **`studio/scale.sh` fails if a size off this list ever comes back**, so
    // reach for the nearest step rather than a new number.

    /// Text. `sans` and `mono` both draw at these and nothing between them.
    enum Size {
        /// The smallest legible mark — a frame's letter, a badge's count.
        static let micro: CGFloat = 8
        /// Section labels, chips' small print, anything under a value.
        static let tiny: CGFloat = Kit.Size.tag
        /// Secondary rows, a panel's values.
        static let small: CGFloat = Kit.Size.label
        /// The reading size. Most of the app is this.
        static let body: CGFloat = Kit.Size.body
        /// A card's name, a pane's heading, an empty state.
        static let title: CGFloat = 13
        /// A screen's title.
        static let large: CGFloat = Kit.Size.row
        /// The film's own name, and nothing else.
        static let display: CGFloat = Kit.Size.heading
    }

    /// Symbols. Bigger than the type scale at the top because an icon
    /// standing alone carries a screen and a letter never does.
    enum Icon {
        static let tiny: CGFloat = 8
        static let small: CGFloat = 10
        /// Inline beside a line of text — over half the icons in the app.
        static let inline: CGFloat = 11
        static let medium: CGFloat = 13
        static let large: CGFloat = 16
        static let tool: CGFloat = 20
        /// An empty state's mark.
        static let empty: CGFloat = 24
        static let huge: CGFloat = 30
    }

    /// The corner a thing turns. Five, and they mean five different things.
    /// A chip, a small frame, a well.
    /// **The height of every acting control in the bar over the table**, and
    /// the air inside it. These are the *views* pills' own numbers: his
    /// ruling, 2026-09-04, *"I loved the pills that we used for 'views'"* —
    /// so when the row had to become one row, they are what it became.
    ///
    /// It was three heights and two paddings in one strip: the views at 24,
    /// Filter, Sort, Columns, the search and the zoom at 27, and their words
    /// held 10 points off the ends against the views' 11. Small differences,
    /// and together they are what he meant by *"it just all kind of feels a
    /// little clunky. I've always felt that way."*
    static let barHeight: CGFloat = 24
    static let barPadding: CGFloat = 11

    static let radiusSmall: CGFloat = 4
    /// A pill, a tag, a swatch.
    static let radiusChip: CGFloat = Kit.Radius.tag
    /// The everyday corner: a button, a field, a row.
    static let radius: CGFloat = 9
    static let radiusLarge: CGFloat = 11
    /// The corner a whole surface turns — a table, a panel section, a board.
    /// Rounder in the glass palette: a 14pt corner on a big panel reads as a
    /// clipped rectangle; 18 reads as a panel.
    static let radiusCard: CGFloat = 18
    /// The corner a *row* turns. The mock draws the row you are on as a
    /// rounded block inset from the well's edges rather than as a full-bleed
    /// stripe, which is the other half of "reads like a list".
    ///
    /// **Deliberately the same value as `radius`** — it used to be one point
    /// bigger, which nobody could see and everybody had to choose between.
    /// Kept as its own name because the two are different decisions and only
    /// one of them would follow if the everyday corner ever moved.
    static let radiusRow: CGFloat = radius
    /// How far a row's block is inset from the edge of the well.
    static let rowInset: CGFloat = 6

    /// The colours a vocabulary term can wear.
    ///
    /// Eight, muted, and far enough apart to tell at a glance across a row.
    static let chipInks = Swatches.inks  // shared with the iPhone

    /// **What time of day a scene is, as a dot.** His ask, 2026-08-22; the
    /// colours and the vocabulary both remade on 2026-09-02.
    ///
    /// **The truth is `shared/TimeOfDay.swift`**, which is compiled into this
    /// app and into the phone, so the two cannot drift. Everything below is a
    /// wrapper kept for the callers that already exist — `Schedule`, `Shell`
    /// and `Document` all ask `Brand` for their colours and there is no reason
    /// to make them ask somewhere else.
    static func timeInk(_ said: String, _ dark: Bool) -> Color? {
        TimeOfDay.ink(said, dark: dark)
    }

    /// The time of day under the colour — one of the four — so a day band's
    /// dot set and `--daydots` read the same truth the dot draws.
    static func timeKey(_ said: String) -> String? { TimeOfDay.key(said) }

    /// The dot for a time `timeKey` gave back, for drawing a set of them.
    static func timeKeyInk(_ key: String, _ dark: Bool) -> Color {
        TimeOfDay.ink(key: key, dark: dark)
    }

    /// The colour of one term, derived from the term itself.
    ///
    /// Derived rather than stored, and the difference matters: the engine has
    /// no colour on a vocabulary term yet, so nothing here is claiming one
    /// exists. It is a way of *drawing* a value, like the aspect-ratio mask on
    /// a frame. **When the engine can hold a colour per term, the stored one
    /// wins and this becomes the default for terms that have not been given
    /// one.** Hashed from the text so the same lens is the same colour in every
    /// project and on every relaunch, which is the whole use of it: the eye
    /// learns that all the wides are that green.
    /// **Colours a person has actually chosen**, by `field` and term — Ref 55.
    ///
    /// A plain static for the same reason `density` is one: a table repaints
    /// hundreds of chips and none of them should be asking the engine a
    /// question. `ShellState.replace` refills this before it publishes the new
    /// document, so the repaint that the publish causes reads the fresh values.
    ///
    /// Keyed on the term **lowercased**, because everything about a vocabulary
    /// is case-blind. Terms nobody has coloured are simply not in here.
    static var termInks: [String: String] = [:]

    static func termKey(_ field: String, _ value: String) -> String {
        field + "\u{1}" + value.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// The colour of one term **on a particular list**.
    ///
    /// A stored colour wins; with none, the word is hashed exactly as before.
    /// That fallback is not a stopgap — it is the right default, and the reason
    /// the app has never needed anybody to choose a colour to be readable.
    /// **A chip's colour comes from its column, not from its word** — his
    /// ruling, 2026-09-14. Shot sizes are one family, angles another,
    /// movement another; a row stops being five random hues and a column
    /// reads as a set. A term he has coloured by hand in Settings keeps that
    /// colour; everything else on the list wears the column's.
    static func chipInk(_ field: String, _ value: String, _ dark: Bool) -> Color {
        if let hex = termInks[termKey(field, value)] { return data(hex, dark) }
        return columnInk(field, dark)
    }

    /// The named lists have a hue each; a column the project made for itself
    /// takes one from the same eight by its name, so it is the same every
    /// time it is drawn.
    static let columnInks: [String: String] = [
        "size": "2B6CB0", "angle": "7B4BC4", "movement": "9A6B10",
        "lens": "2C7A7B", "modifiers": "2C7A7B", "lens_filters": "2C7A7B", "support": "B4531B", "tags": "A33574",
        "priority": "4C51BF", "pov": "2F7A44",
    ]

    static func columnInk(_ field: String, _ dark: Bool) -> Color {
        if let hex = columnInks[field] { return data(hex, dark) }
        let key = field.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return ink3(dark) }
        var hash: UInt64 = 5381
        for byte in key.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return data(chipInks[Int(hash % UInt64(chipInks.count))], dark)
    }

    /// A colour of his, lifted so it reads on a dark ground.
    ///
    /// The identity is the hue — A-Cam is that red on any screen. What changes
    /// is how much light is behind it, so the same value does not go muddy at
    /// night. Only appearance moves; nothing is stored.
    static func data(_ s: String, _ dark: Bool) -> Color {
        guard dark else { return hex(s) }
        var t = s.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if t.count == 3 { t = t.map { "\($0)\($0)" }.joined() }
        guard t.count == 6, let v = UInt64(t, radix: 16) else { return hex(s) }
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255

        let high = max(r, max(g, b)), low = min(r, min(g, b))
        let lightness = (high + low) / 2
        var hue: Double = 0
        var saturation: Double = 0
        if high != low {
            let d = high - low
            saturation = lightness > 0.5 ? d / (2 - high - low) : d / (high + low)
            switch high {
            case r: hue = (g - b) / d + (g < b ? 6 : 0)
            case g: hue = (b - r) / d + 2
            default: hue = (r - g) / d + 4
            }
            hue /= 6
        }
        return Color(
            hue: hue,
            saturation: min(0.85, max(0.30, saturation)),
            brightness: min(0.94, lightness + 0.34)
        )
    }
}

// ------------------------------------------------------------------ type

extension Brand {
    /// The same two faces as the `mono`/`sans` modifiers, as fonts rather than
    /// modifiers — for the places that need one to hand, like a text field.
    static func monoFont(_ size: CGFloat) -> Font {
        .system(size: size, design: .monospaced)
    }

    static func sansFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// The ground a floating menu sits on.
    static func menu(_ d: Bool) -> Color { pick(d, "FFFFFF", "2C2C30") }
}

extension View {
    /// SF Mono, for shot numbers and technical values — instrument data, not prose.
    func mono(_ size: CGFloat, weight: Font.Weight = .regular, tracking: CGFloat = 0) -> some View {
        font(.system(size: size, weight: weight, design: .monospaced))
            .monospacedDigit()
            .tracking(tracking)
    }

    /// **The small capital label over a group of fields.**
    ///
    /// Mono, tiny, widely tracked, faint — the app's quietest heading, and the
    /// one it uses most: `TITLE`, `DRIVE FOLDER`, `SLUG LINES`, `FORMAT FOR`.
    /// Eighteen places wrote this out by hand, at two sizes, and half of them
    /// forgot the colour and took whatever their parent happened to be. It is
    /// one decision now. His ruling, 2026-09-08: keep the capitals.
    /// **One label idiom now** — `fieldLabel` in Grammar.swift under the name
    /// the older screens call it by. It was tracked typewriter capitals until
    /// 2026-09-15; every caller has been re-worded to Title Case.
    func sectionLabel(_ dark: Bool) -> some View {
        sans(Brand.Size.small, weight: .medium).foregroundStyle(Brand.ink3(dark))
    }

    /// A quiet sans label naming a bar, a pane or a column — sentence case,
    /// a shade louder than `sectionLabel` and never in capitals.
    func label(_ dark: Bool, size: CGFloat = 10) -> some View {
        font(.system(size: size, weight: .medium))
            .foregroundStyle(Brand.ink3(dark))
    }

    /// Text at a size and weight the drawings actually use. The negative
    /// tracking on the larger sizes is what stops a Mac title looking like a
    /// web page.
    func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        font(.system(size: size, weight: weight))
            .tracking(size >= 15 ? -0.28 : (size >= 13 ? -0.12 : 0))
    }
}

// ---------------------------------------------------------------- helpers

extension View {
    /// A hairline along one edge, drawn as an overlay so it never takes part in
    /// layout. Two views that each own a border is how a 1px seam becomes 2px.
    func hairline(_ edge: Edge, _ colour: Color) -> some View {
        overlay(alignment: {
            switch edge {
            case .top: return .top
            case .bottom: return .bottom
            case .leading: return .leading
            case .trailing: return .trailing
            }
        }()) {
            Group {
                if edge == .top || edge == .bottom {
                    colour.frame(height: 1)
                } else {
                    colour.frame(width: 1)
                }
            }
        }
    }
}


// ------------------------------------------------------------------- glass

extension View {
    /// A surface that floats: rounded, hairline-edged, with the light caught
    /// on its top edge and a soft shadow under it.
    ///
    /// Painted, never `.ultraThinMaterial`. A real material draws *nothing*
    /// into an offscreen bitmap, and this app photographs itself to be
    /// checked — an app that cannot be looked at cannot be verified. So the
    /// glass here is three layers of paint that add up to the same read.
    func card(_ dark: Bool, radius: CGFloat = Brand.radiusCard) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return clipShape(shape)
            .background {
                shape.fill(Brand.surface(dark))
                    .shadow(color: Brand.glassLine(dark).opacity(dark ? 0.5 : 0.55),
                            radius: dark ? 14 : 10, y: 3)
            }
            .overlay { shape.strokeBorder(Brand.glassEdge(dark), lineWidth: 1) }
    }

    /// A small floating control — a search box, a filter button, a chip.
    /// Same idea at the size of a hand, so the chrome and the surfaces agree.
    /// **The capsule every control in the bar over the table wears.**
    ///
    /// Not `pill`: that one fills with `glass2` and strokes with `glassEdge`,
    /// which are both *white* in daylight — fine on the panels, which float on
    /// a chrome ground, and invisible here, where the ground is the page and
    /// the page is white. `band` is the token written for exactly that ("it has
    /// to read as a band in daylight too"), and there is no stroke at all,
    /// because a hairline box round every control is what he called ugly.
    ///
    /// The shape is a capsule so these read as the same family as the views
    /// beside them — his ask: *"the filter and sort pills should be closer to
    /// the pills for Table, Storyboard and Document."* Idle is a soft band;
    /// **on** is solid accent, the same way a chosen view is solid.
    /// **A button in a bar is a hairline capsule**, never a fill — the grammar
    /// of 2026-09-14. One that is in force (a filter on, a sort set) wears the
    /// film's tint, the same way the viewer's star does.
    func barPill(_ dark: Bool, on: Bool) -> some View {
        background {
            Capsule(style: .continuous)
                .fill(on ? Brand.accentTint(dark) : .clear)
        }
        .overlay {
            if !on {
                Capsule(style: .continuous).strokeBorder(Brand.rule2(dark), lineWidth: 1)
            }
        }
    }

    func pill(_ dark: Bool, radius: CGFloat = 9, lit: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background {
            shape.fill(lit ? Brand.accentTint(dark) : Brand.glass2(dark))
                .overlay {
                    shape.strokeBorder(lit ? Brand.accentLine(dark) : Brand.glassEdge(dark),
                                       lineWidth: 1)
                }
        }
    }
}


// ------------------------------------------------------- the floating panel

extension View {
    /// **A panel that floats.**
    ///
    /// His note of 2026-08-20, pointing at the mock's sidebar: *"it has
    /// rounded corners, feels like it's floating on top, it's
    /// semi-transparent. That's the kind of stuff we want."* So a panel here
    /// is not a column of the window any more — it is a rounded, translucent
    /// slab lying on the window's ground with air all round it, and the ground
    /// showing between it and its neighbours.
    ///
    /// The air is the whole trick. A flush column with a hairline beside it
    /// reads as *structure*; the same column with six points of ground round
    /// it reads as an *object*, and objects are what a current Mac app is made
    /// of. Everything else — the corner, the translucency, the shadow — only
    /// works once the air is there.
    /// **A floating glass panel.** `floating` above fills opaquely, which is
    /// right for a card sitting on a table and wrong for a sidebar: his note
    /// was that it should read as *floating*, with the window's ground still
    /// visible around it and showing through it.
    ///
    /// Both of his asks about the sidebar are the same ask, arrived at from
    /// two sides. First: "it feels like it's on top of its own separate
    /// panel… it should just be on top of the background", so the panel came
    /// off entirely. Then: "it doesn't feel like a floating panel with rounded
    /// corners. It feels like its own thing." Taking the panel away went one
    /// step too far — a flush region of ground with nothing around it is not
    /// "on the background", it *is* the background, and its straight edge is
    /// exactly the thing he could feel. What he wants is neither: an object
    /// that floats, with air around it and the ground continuous behind.
    func floatingGlass(_ dark: Bool,
                       radius: CGFloat = 16,
                       inset: EdgeInsets = EdgeInsets(top: 8, leading: 8,
                                                      bottom: 8, trailing: 8)) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return clipShape(shape)
            // **A panel's glass is fainter than a chip's.** `systemGlass` fills
            // with `glass2`, which is right on something the size of a button
            // and far too much across a whole column: he could see the panel
            // as a different colour from the table beside it. A panel this big
            // only needs a breath of lift over the ground it sits on.
            .background {
                shape.fill(Color.white.opacity(dark ? 0.035 : 0.55))
                    .overlay { shape.strokeBorder(Brand.glassEdge(dark), lineWidth: 1) }
            }
            .glassIfAvailable(shape)
            // **No shadow.** The gap between a panel and the well is twenty
            // points; a shadow nine wide filled it and read as a grey strip
            // on a ground that is the well's own white — his report,
            // 2026-09-15: "the background color right behind the left
            // sidebar is a different color than the table." The hairline
            // edge is what says panel now.
            .padding(.top, inset.top).padding(.bottom, inset.bottom)
            .padding(.leading, inset.leading).padding(.trailing, inset.trailing)
    }

    func floating(_ dark: Bool,
                  radius: CGFloat = 14,
                  inset: EdgeInsets = EdgeInsets(top: 6, leading: 6,
                                                 bottom: 6, trailing: 6)) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return clipShape(shape)
            .background {
                shape.fill(Brand.panel(dark))
                    .shadow(color: Color.black.opacity(dark ? 0.44 : 0.13),
                            radius: dark ? 16 : 10, y: 3)
            }
            .overlay { shape.strokeBorder(Brand.glassEdge(dark), lineWidth: 1) }
            .padding(.top, inset.top).padding(.bottom, inset.bottom)
            .padding(.leading, inset.leading).padding(.trailing, inset.trailing)
    }
}

// -------------------------------------------------- the system's own glass

extension View {
    /// **Apple's Liquid Glass, where the machine has it.**
    ///
    /// His question, 2026-08-20: *"are we using the actual Apple Swift glass
    /// elements?"* Until now, no — every "glass" surface in this app is three
    /// layers of paint, and the reason was a real one: a system material draws
    /// *nothing at all* into an offscreen bitmap, and this app photographs
    /// itself in order to be checked. An app that cannot be looked at cannot
    /// be verified, and verification is a law here.
    ///
    /// He is on macOS 26.5, where `glassEffect` exists, so the question is
    /// worth re-asking rather than assuming: this is the experiment. It falls
    /// back to the painted version on anything older, and to the painted
    /// version everywhere if the photograph comes back empty.
    /// **The answer, measured 2026-08-20: it photographs as nothing.** The tab
    /// track and the three round buttons came back as bare glyphs floating on
    /// the chrome — the system draws Liquid Glass in the compositor, and an
    /// offscreen bitmap of the window layer never sees it. Exactly what this
    /// codebase already predicted for `.ultraThinMaterial`, now proved for its
    /// successor.
    ///
    /// So both, on purpose: **painted underneath, the system's glass on top.**
    /// In front of him the real thing is what he sees, with real lensing over
    /// whatever is behind it. In a photograph the paint is what survives, so
    /// the chrome can still be checked. Neither half is a hack — a fallback
    /// fill behind a material is what you do anyway; it is only unusual to
    /// care this much that the fallback be a good likeness.
    /// Apple's own glass where the OS has it, and nothing where it does not —
    /// the paint underneath has already been applied by the caller.
    @ViewBuilder
    func glassIfAvailable<S: InsettableShape>(_ shape: S) -> some View {
        if #available(macOS 26.0, *) { glassEffect(.regular, in: shape) } else { self }
    }

    @ViewBuilder
    /// `off` leaves the glass unpainted — for a control that is *lit*, where
    /// the accent is the ground and a pane of glass over it only mutes it.
    func systemGlass<S: InsettableShape>(_ shape: S, dark: Bool,
                                         off: Bool = false) -> some View {
        let painted = background {
            if !off {
                shape.fill(Brand.glass2(dark))
                    .overlay { shape.strokeBorder(Brand.glassEdge(dark), lineWidth: 1) }
            }
        }
        if #available(macOS 26.0, *) {
            painted.glassEffect(.regular, in: shape)
        } else {
            painted
        }
    }
}
