import SwiftUI

/// **The app's own look, in one place** — the one-app design pass, 2026-10-06
/// (`design/33-one-app.html`, `design/33-one-app/style.css`). His words after
/// using the first build: *"right now the app doesn't feel like the mockups …
/// Just feels like a basic apple app."*
///
/// The mockup is iOS 26 underneath — grouped grey page, Liquid Glass bars —
/// and what makes it read as Shotlister rather than Settings is a handful of
/// small, repeated decisions. They live here so every screen makes them the
/// same way:
///
/// - **the grey page and the white card**: content sits on cards with large,
///   continuous corners (22 for a scene's shots, 16 for a list of rows);
/// - **a section is named in bold black**, not in small grey capitals;
/// - **a switch between views is a glass capsule** whose chosen side is solid
///   ink, not the system's grey segmented control;
/// - **a column's values are tags in the mockup's own six inks**;
/// - **a field is named by a small grey capital kicker** over its words.
enum Style {
    /// The page behind everything.
    ///
    /// **Shotlister's own dark, not iOS's** (2026-10-07,
    /// `design/37-accent.html`). His two notes in one afternoon: the app read
    /// as Settings beside the portal, and then *"maybe it shouldn't be FULL
    /// black, slightly more gery"*. Both were already answered on the Mac —
    /// `Brand` in `studio/Sources/Theme.swift` has had a dark palette for
    /// months and the phone never used it. These are those values, so the two
    /// apps finally agree about what dark means:
    /// surface `0E0E11`, ground `16161A`, rule `232329`,
    /// inks `EDEDF0` / `A0A0A8` / `74747C` / `55555C`.
    static let page = Color(kit: Kit.Ink.phonePage)
    /// A card on it. In the dark it lifts off the page rather than sinking
    /// into it, which is the one place this differs from the Mac — a phone
    /// card has no window chrome to separate it.
    static let card = Color(kit: Kit.Ink.phoneGroup)
    /// The mockup's `--ink3`: counts, kickers, a scene line.
    static let ink3 = Color(kit: Kit.Ink.ink3)
    /// The mockup's `--ink2`: a synopsis, a sub-line.
    static let ink2 = Color(kit: Kit.Ink.ink2)
    /// A hairline between rows (`Brand.rule`).
    static let rule = Color(kit: Kit.Ink.rule)

    /// **Shotlister's own blue**, worn by a film that has no colour of its
    /// own — `Brand.accent` with nothing in `worn`.
    static let blue = Color(kit: Kit.Ink.blue)

    /// **The accent is the film's colour, not the app's.** `Brand.accent` on
    /// the Mac draws every film in the colour of its row in Notion; the phone
    /// drew in a system blue it never chose. The colour arrives on the film's
    /// record (`PortalFront.Film.colour`, the portal's `mark.colour`), so a
    /// film with no record and no colour falls back to the program's blue.
    static func accent(_ hex: String?) -> Color {
        guard let hex, !hex.isEmpty else { return blue }
        return Color(markHex: hex)
    }

    /// Corner sizes, by what the card is.
    enum Radius {
        static let group: CGFloat = Kit.Radius.card   // a scene's shots, a day (one look: 11)
        static let card: CGFloat = 0     // a cover card (Visual Bible): its pictures run to its edge
        static let list: CGFloat = Kit.Radius.card    // rows of a list, a table (one look: 11)
        static let tile: CGFloat = 0     // a storyboard tile — a picture
        /// **A frame is not rounded.** His note, 2026-10-07: *"no rounded
        /// corners on media"*. A photograph is the thing itself, not a card
        /// with a picture on it, and a rounded corner crops the top of a
        /// frame line he composed.
        static let frame: CGFloat = 0    // a frame inside a row
    }
}

extension Color {
    /// A colour out of the one-look kit (`shared/Kit.swift`).
    init(kit pair: Kit.Pair) {
        self.init(light: UInt32(pair.light, radix: 16) ?? 0, dark: UInt32(pair.dark, radix: 16) ?? 0)
    }

    /// One colour for light, another for dark.
    init(light: UInt32, dark: UInt32) {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        self = Color(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
}

extension View {
    /// Content on a white card with continuous corners.
    func card(_ radius: CGFloat = Style.Radius.list) -> some View {
        background(Style.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Liquid Glass in a capsule on iOS 26, a material before it.
    @ViewBuilder
    func glassCapsule(interactive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: .capsule)
        } else {
            background(.regularMaterial, in: Capsule())
        }
    }

    /// **A root screen's name, leading, 26 bold** (the mockup's `.navtitle`):
    /// Shot List, Library, Look, Diagrams. The system draws an inline title
    /// centred and small, or a large one too large; this is the size between,
    /// on the left, beside the screen's glass buttons.
    ///
    /// **At the root of a tab inside a film, the film's name instead** (his
    /// pick, 2026-10-09, `design/42-one-home`): the bar already says which
    /// tab this is, and a tap on the name is the film's one menu. Pushed or in
    /// a sheet, a screen keeps its own name.
    func leadingTitle(_ title: String) -> some View {
        modifier(LeadingTitle(title: title))
    }

    /// A search field that folds to a button on iOS 26.
    @ViewBuilder
    func searchFolded() -> some View {
        if #available(iOS 26.0, *) {
            searchToolbarBehavior(.minimize)
        } else {
            self
        }
    }

    /// Liquid Glass in a rounded rectangle on iOS 26, a material before it.
    @ViewBuilder
    func glassRounded(_ radius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

/// **This screen is a tab's root inside a film**: set by `FilmTabs` on each
/// tab's first screen, false on anything pushed (`PlaceView(root: false)`)
/// and inside anything that names itself. `isPresented` cannot say it: a
/// whole film is a presented cover, so it is true everywhere in one.
private struct TabRootKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var tabRoot: Bool {
        get { self[TabRootKey.self] }
        set { self[TabRootKey.self] = newValue }
    }
}

/// Reads where the screen is from the screen's own environment, which a
/// toolbar item cannot be trusted to see; and tells everything inside it
/// that it is not a root, so a sheet's own title stays its own.
private struct LeadingTitle: ViewModifier {
    let title: String
    @Environment(\.tabRoot) private var film

    func body(content: Content) -> some View {
        content
            .environment(\.tabRoot, false)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarLeading) { label(film) }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) { label(film) }
                }
            }
    }

    @ViewBuilder
    private func label(_ film: Bool) -> some View {
        if film { FilmTitleButton() } else { RootTitle(text: title) }
    }
}

private struct RootTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: Kit.Size.title, weight: .bold))
            .foregroundStyle(Color(.label))
            .lineLimit(1)
            .fixedSize()
            .accessibilityAddTraits(.isHeader)
    }
}

/// **A section's name**: bold, black, 20 (the mockup's `.lh`): Scenes,
/// Boards, Decks, a shelf.
struct SectionTitle: View {
    let text: String
    var size: CGFloat = 20
    init(_ text: String, size: CGFloat = 20) {
        self.text = text
        self.size = size
    }
    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(Color(.label))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// **A field's name over its words** (the mockup's `.ph`): small, bold, grey
/// capitals. Description, Notes, Script.
struct Kicker: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        // One look: a label, the kit's 11 semibold grey, in his own case.
        Text(text)
            .font(.system(size: Kit.Size.label, weight: .semibold))
            .foregroundStyle(Style.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// **A switch between views** (the mockup's `.seg2`): a glass capsule, the
/// chosen side solid ink with white words. List | Storyboard, Native |
/// Designed, Free | a sort.
struct GlassSegments<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var compact = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = option.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.system(size: compact ? 13 : 15, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, compact ? 10 : 16)
                        .padding(.vertical, compact ? 7 : 8)
                        .foregroundStyle(on ? Color(.systemBackground) : Color(.label))
                        .background {
                            if on { Capsule().fill(Color(.label)) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .glassCapsule()
    }
}

/// **A word on glass** (the mockup's `.scenesbtn`, `.xbtn`): Scenes, Done.
struct GlassPillButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(.label))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 15)
                .frame(height: 42)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // **A ground under the glass.** His note, 2026-10-07: the Scenes
        // button was *"way too clear"* — glass alone over a dark page is
        // almost nothing, and a control you cannot see the edge of does not
        // read as a control.
        .background(Color(.tertiarySystemFill), in: Capsule())
        .glassCapsule()
    }
}

/// **A filter chip** (the mockup's `.chips span`): soft grey, the chosen one
/// solid ink. A page's headings, a board's sorts.
struct InkChip: View {
    let text: String
    var on = false
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .foregroundStyle(on ? Color(.systemBackground) : Color(.label))
            .background(on ? Color(.label) : Color(.tertiarySystemFill), in: Capsule())
    }
}

/// **The six inks a shot's tags wear** (the mockup's `.c-size` … `.c-tag`):
/// a pale ground and a deep word, chosen so a row of them reads as a row, not
/// as six system colours at thirteen percent.
enum TagInk: Hashable {
    case size, angle, movement, lens, support, tags, own
    /// A colour he chose for this value, on the Mac or here (`Swatches.inks`).
    case chosen(String)

    var word: Color {
        switch self {
        case .chosen(let hex): return Color(markHex: hex)
        case .size: return Color(light: 0x1F5CD6, dark: 0x8AB4FF)
        case .angle: return Color(light: 0x6A3FCF, dark: 0xC4A8FF)
        case .movement: return Color(light: 0x9A5B00, dark: 0xFFC46B)
        case .lens: return Color(light: 0x0E7461, dark: 0x6FE0C6)
        case .support: return Color(light: 0xB04C17, dark: 0xFFA37A)
        case .tags: return Color(light: 0xBC2D6B, dark: 0xFF8DBF)
        case .own: return Color(light: 0x55555A, dark: 0xC7C7CC)
        }
    }

    var ground: Color {
        switch self {
        case .chosen(let hex): return Color(markHex: hex).opacity(0.2)
        case .size: return Color(light: 0xE6EFFF, dark: 0x1C2C4A)
        case .angle: return Color(light: 0xF0E9FE, dark: 0x2C2347)
        case .movement: return Color(light: 0xFFF1D9, dark: 0x3D2E14)
        case .lens: return Color(light: 0xE0F5EF, dark: 0x123A32)
        case .support: return Color(light: 0xFFE9DC, dark: 0x40261A)
        case .tags: return Color(light: 0xFDE6EF, dark: 0x40192B)
        case .own: return Color(light: 0xEDEDF0, dark: 0x2C2C2E)
        }
    }
}

/// **A section's name over a form's card** (the mockup's `.lh`, in a
/// `Form` or an inset `List`): bold black words, the section's own buttons
/// on the right as soft round marks. Locations, a location's page.
struct FormHead<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ text: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color(.label))
            Spacer(minLength: 4)
            trailing()
        }
        .textCase(nil)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}

/// **A section's own button** (`FormHead`'s right side): a glyph on a soft
/// grey circle, the choice look, so it reads as a control beside a title
/// rather than as a link.
struct SoftRoundLabel: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(.label))
            .frame(width: 30, height: 30)
            .background(Color(.tertiarySystemFill), in: Circle())
            .contentShape(Circle())
    }
}

/// **Which light the app draws in** (2026-10-07).
///
/// The portal is black everywhere; the app followed the phone, so on a light
/// phone it was Settings-grey — and because his phone is in light mode he had
/// never once seen the app dark. Dark is the app's own default now. The
/// phone's own setting is still available, as a choice rather than the law.
enum Appearance: String, CaseIterable, Identifiable {
    case dark, light, phone

    var id: String { rawValue }

    var name: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .phone: return "Follow the Phone"
        }
    }

    var scheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .phone: return nil
        }
    }

    static let key = "appearance"
}

private struct Dressed: ViewModifier {
    @AppStorage(Appearance.key) private var chosen = Appearance.dark.rawValue
    func body(content: Content) -> some View {
        content.preferredColorScheme(Appearance(rawValue: chosen)?.scheme ?? .dark)
    }
}

extension View {
    /// The light the app draws in, his choice, dark until he says otherwise.
    func appearance() -> some View { modifier(Dressed()) }
}

extension View {
    /// **Room at the foot of a screen for the floating bar.**
    ///
    /// The tab bar used to reserve this; when the bar became one pill over
    /// the content, nothing did, and the last row of every list ended under
    /// glass. It belongs **inside** the navigation stack, on the screen's own
    /// content: on the TabView, and then on the stack itself, it reserved
    /// nothing the scroll views inside could see. A UI test caught both
    /// (2026-10-07) by measuring the Library's last row against the bar.
    func barRoom() -> some View { self }
}

/// **The Shot marks are for the set** — his ask, 2026-10-07: *"can that mode
/// be 'turned off' by default EXCEPT on a shoot day, BUT be turned on
/// manually if i so chose not on a shoot day?"* So the round marks show by
/// themselves only when today is one of the film's shoot days, and a switch
/// on the shot list turns them on or off by hand. **A hand choice lasts the
/// day**: it is stored with the date it was made, so turning them on to tick
/// something off on a Tuesday does not leave them on for good, and turning
/// them off on a shoot day does not hide them on the next one.
enum MarkingShots {
    static let key = "shotlist.marks"

    /// `on:2026-10-07`, `off:2026-10-07`, or nothing.
    static func showing(choice: String, shootDay: Bool) -> Bool {
        let parts = choice.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2, parts[1] == today { return parts[0] == "on" }
        return shootDay
    }

    static func choose(_ on: Bool) -> String { "\(on ? "on" : "off"):\(today)" }

    static var today: String { Engine.Lane.written(Date()) }
}

/// **How big a picture is drawn on the shot list**, in List and Storyboard
/// alike — his ask, 2026-10-07: *"we should have options for aspect ratio
/// displays for mobile in case i want full frame, or small if needed"*, and
/// then, of the shape picker that answered it: *"isnt actually about changing
/// aspect ratio but jus the size of the images in teh shot list - with
/// storyboard and list views"*. The shape is always the film's own; only the
/// size moves. `full` keeps its stored name so an old choice still reads.
enum FrameSize: String, CaseIterable, Identifiable {
    case small, medium, full

    var id: String { rawValue }

    var name: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .full: return "Large"
        }
    }

    /// **How wide the picture beside a list row is.** His ruling, 2026-10-09:
    /// *"large list should not have full frame pictures · they should always be
    /// on the side so it feels like a list"*. The list's picture is always
    /// beside the words; only Storyboard runs a frame full width.
    var listWidth: CGFloat {
        switch self {
        case .small: return 118
        case .medium: return 152
        case .full: return 200
        }
    }

    /// Storyboard tiles across a phone (`regular` is an iPad's width).
    func across(regular: Bool) -> Int {
        switch self {
        case .small: return regular ? 4 : 3
        case .medium: return regular ? 3 : 2
        case .full: return regular ? 2 : 1
        }
    }

    static let key = "shotlist.frameSize"
}

/// **A colour as a menu row's picture.** A menu draws its icons in one ink
/// unless the picture says it is its own colours, so a swatch is drawn.
enum Swatch {
    static func dot(_ hex: String, ticked: Bool = false) -> UIImage {
        let size = CGSize(width: 22, height: 22)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let colour = UIColor(Color(markHex: hex))
            colour.setFill()
            UIBezierPath(ovalIn: CGRect(x: 3, y: 3, width: 16, height: 16)).fill()
            if ticked {
                colour.setStroke()
                let ring = UIBezierPath(ovalIn: CGRect(x: 0.75, y: 0.75, width: 20.5, height: 20.5))
                ring.lineWidth = 1.5
                ring.stroke()
            }
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}

/// **The kit's sizes as fonts** (One Look): the phone's text stays on the
/// five sizes every app shares (`shared/Kit.swift`), not iOS's own steps.
extension Font {
    static var kitTitle: Font { .system(size: Kit.Size.title, weight: .bold) }
    static var kitHeading: Font { .system(size: Kit.Size.heading, weight: .semibold) }
    static var kitRow: Font { .system(size: Kit.Size.row) }
    static var kitRowStrong: Font { .system(size: Kit.Size.row, weight: .semibold) }
    static var kitBody: Font { .system(size: Kit.Size.body) }
    static var kitLabel: Font { .system(size: Kit.Size.label) }
}
