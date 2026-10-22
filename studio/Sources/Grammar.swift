import SwiftUI
import AppKit

/// **The grammar of the small parts** — `design/23-softer.html`, his rulings
/// of 2026-09-14 and 15.
///
/// Five kinds of small thing, one look each, and no look shared by two kinds:
///
/// - **a value** (typed): plain ink, no box, no icon
/// - **a category** (picked from a list): a soft tinted capsule, coloured by
///   *column* — `Chip`, `Brand.chipInk`
/// - **a choice** (one of N, one on): the on one gets a soft fill — `Segmented`
///   quiet, `ChoicePill`
/// - **a button**: a hairline capsule, 24pt tall; a sheet's primary is the same
///   capsule in the film's tint — `CapsuleButton`
/// - **an action in a row**: ghost text with a leading `+` — `PlusLabel`,
///   `RowAction`
///
/// And every sheet is built to one anatomy — `Sheet`. The palette is not
/// touched: every colour here is one Theme.swift already had.

// MARK: - a button

/// The one button shape. Hairline capsule, no fill; the primary (Done, Add,
/// Export…) is the same capsule filled with the film's tint and lettered in
/// the film's colour. No grey filled rounded rectangles anywhere.
struct CapsuleButton: ButtonStyle {
    var primary = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, primary: primary,
             dark: scheme == .dark, enabled: enabled)
    }

    private struct Face: View {
        let configuration: Configuration
        let primary: Bool
        let dark: Bool
        let enabled: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .sans(Brand.Size.body, weight: primary ? .semibold : .regular)
                .foregroundStyle(primary ? Brand.accent(dark) : Brand.ink(dark))
                .lineLimit(1)
                .padding(.horizontal, Brand.barPadding)
                .frame(height: Brand.barHeight)
                .background {
                    Capsule(style: .continuous)
                        .fill(primary ? Brand.accentTint(dark)
                                      : (hovering ? Brand.cellHover(dark) : .clear))
                }
                .overlay {
                    if !primary {
                        Capsule(style: .continuous)
                            .strokeBorder(Brand.rule2(dark), lineWidth: 1)
                    }
                }
                .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
                .contentShape(Capsule(style: .continuous))
                .onHover { hovering = $0 }
        }
    }
}

extension ButtonStyle where Self == CapsuleButton {
    static var capsule: CapsuleButton { CapsuleButton() }
    static var primary: CapsuleButton { CapsuleButton(primary: true) }
}

// MARK: - an action in a row

/// `+ Add shot`, `+ Add tag`, `+ Show a column` — ghost text with a plus.
/// Never a field icon, never an accent circle.
struct PlusLabel: View {
    let text: String
    let dark: Bool
    var size: CGFloat = Brand.Size.body
    @Environment(\.onGlass) private var glass

    var body: some View {
        HStack(spacing: 4) {
            Text("+").sans(size, weight: .medium)
            Text(text).sans(size)
        }
        .foregroundStyle(Brand.ghost(dark, glass: glass))
        .lineLimit(1)
    }
}

/// The style a row action wears when it is a `Button`: the ghost words, and a
/// soft capsule only under the pointer. A `Menu` gets the same through
/// `.rowAction(dark)` on its label.
struct RowAction: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.onGlass) private var glass

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .sans(Brand.Size.body)
            .foregroundStyle(Brand.ghost(scheme == .dark, glass: glass))
            .rowAction(scheme == .dark)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == RowAction {
    static var rowAction: RowAction { RowAction() }
}

private struct RowActionFace: ViewModifier {
    let dark: Bool
    @State private var over = false

    func body(content: Self.Content) -> some View {
        content
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                Capsule(style: .continuous).fill(over ? Brand.cellHover(dark) : .clear)
            }
            .contentShape(Capsule(style: .continuous))
            .onHover { over = $0 }
    }
}

extension View {
    func rowAction(_ dark: Bool) -> some View { modifier(RowActionFace(dark: dark)) }
}

// MARK: - a choice

/// One pill of a choice where none may be on — Add Scene's time of day. The
/// same look as `Segmented`'s quiet pill: soft fill, ink text, semibold when
/// it is the one.
struct ChoicePill: View {
    let title: String
    let on: Bool
    let dark: Bool
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .sans(Brand.Size.body, weight: .semibold)
                .hidden()
                .overlay {
                    Text(title).sans(Brand.Size.body, weight: on ? .semibold : .regular)
                        .fixedSize()
                }
                .foregroundStyle(on ? Brand.ink(dark) : Brand.ink2(dark))
                .padding(.horizontal, Brand.barPadding)
                .frame(height: Brand.barHeight)
                .background {
                    Capsule(style: .continuous)
                        .fill(on ? Brand.cellHover(dark)
                                 : (hovering ? Brand.rowHover(dark) : .clear))
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
    }
}

// MARK: - a field

/// **One field shape**, whether you type in it or pick from it: the hairline
/// rounded field. Picking shows a chevron at the right edge; a value with a
/// colour shows its dot inside.
private struct FieldShape: ViewModifier {
    let dark: Bool
    var minHeight: CGFloat = 28

    func body(content: Self.Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: minHeight)
            .background {
                RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
                    .fill(Brand.menu(dark))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
                    .strokeBorder(Brand.rule2(dark), lineWidth: 1)
            }
    }
}

extension View {
    func field(_ dark: Bool, minHeight: CGFloat = 28) -> some View {
        modifier(FieldShape(dark: dark, minHeight: minHeight))
    }
}

/// A single line you type in.
struct FieldText: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .sans(Brand.Size.body)
            .foregroundStyle(Brand.ink(dark))
            .onSubmit(onSubmit)
            .field(dark)
    }
}

/// What a picker says when it is shut: the value, its dot when it has one, and
/// the chevron. Wrap it in a `Menu` whose items are your own. `Dropdown` is the
/// same face over a plain list.
struct FieldFace: View {
    let text: String
    /// Drawn quiet — the field is saying what is *not* there.
    var empty: Bool = false
    var dot: Color? = nil
    var chevron: Bool = true
    /// A mark other than the chevron at the right edge — "…" on a field that
    /// opens a picker rather than a list.
    var trailing: String? = nil
    let dark: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let dot {
                Circle().fill(dot).frame(width: 7, height: 7)
            }
            Text(text)
                .sans(Brand.Size.body)
                .monospacedDigit()
                .foregroundStyle(empty ? Brand.ink3(dark) : Brand.ink(dark))
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing).sans(Brand.Size.body).foregroundStyle(Brand.ink3(dark))
            } else if chevron {
                MenuMark()
            }
        }
        .frame(maxWidth: .infinity)
        .field(dark)
        .contentShape(RoundedRectangle(cornerRadius: Brand.radius, style: .continuous))
    }
}

/// A paragraph you type in — a synopsis, a note.
struct TypingField: View {
    @Binding var text: String
    let ghost: String
    var height: CGFloat = 64

    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        TextEditor(text: $text)
            .font(Brand.sansFont(Brand.Size.body))
            .foregroundStyle(Brand.ink(dark))
            .scrollContentBackground(.hidden)
            .frame(height: height)
            // Room on the right for the scrollbar, which otherwise rides the
            // rounded corner and sits on the words.
            .padding(.leading, 6).padding(.trailing, 12)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
                    .fill(Brand.menu(dark))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
                    .strokeBorder(Brand.rule2(dark), lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    // Lined up with where the caret actually lands.
                    Text(ghost).sans(Brand.Size.body).foregroundStyle(Brand.ink4(dark))
                        .padding(.leading, 12).padding(.top, 12)
                        .allowsHitTesting(false)
                }
            }
    }
}

// MARK: - a label

extension View {
    /// **One label idiom.** Small, medium, third-rank ink, Title Case per the
    /// 2026-09-04 law — no tracking, no capitals, no typewriter. Column heads,
    /// field labels, group heads, card titles, Settings' rail heads, Schedule's
    /// day heads: all this.
    func fieldLabel(_ dark: Bool) -> some View {
        modifier(GhostLabel(dark: dark))
    }
}

private struct GhostLabel: ViewModifier {
    let dark: Bool
    @Environment(\.onGlass) private var glass
    func body(content: Self.Content) -> some View {
        content.sans(Brand.Size.small, weight: .medium)
            .foregroundStyle(Brand.ghost(dark, glass: glass))
    }
}

// MARK: - on glass

/// **Floating glass is a lighter ground than the window.** The Diagram's bars
/// and panels float over the plan on the system's material, which at night is
/// a grey (`#232323`) the app's third ink was never tuned for: ghost words
/// there fell to 3.4 : 1, and the soft fill under a choice that was on
/// (`selectionQuiet`) to 1.05 : 1 — invisible. Nothing in the palette
/// changes: under `.onGlass`, ghost words take the second ink and a choice
/// that is on takes a fill made of ink itself, so it shows on any ground.
private struct OnGlassKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var onGlass: Bool {
        get { self[OnGlassKey.self] }
        set { self[OnGlassKey.self] = newValue }
    }
}

extension Brand {
    /// Ghost words — a row action, a field label, "of 4" — readable on the
    /// ground they sit on.
    static func ghost(_ d: Bool, glass: Bool = false) -> Color { glass ? ink2(d) : ink3(d) }
    /// The fill under a choice that is on, or a picked row, on floating glass.
    static func glassOn(_ d: Bool) -> Color { ink(d).opacity(d ? 0.17 : 0.09) }
    /// Under the pointer, on floating glass: half as much.
    static func glassHover(_ d: Bool) -> Color { ink(d).opacity(d ? 0.08 : 0.045) }
}

/// Twenty points between groups, where the body's own gap is twelve.
struct GroupGap: View {
    var body: some View { Color.clear.frame(height: 8) }
}

// MARK: - a sheet

/// **The one anatomy.** Header: title top-left, hairline under. Body: one
/// column, 18pt in, 12pt between fields, scrolls on its own. Footer: hairline
/// above; primary far right, Cancel beside it, anything else far left; options
/// never live here. Three widths.
enum SheetWidth: CGFloat {
    /// A name, an address.
    case narrow = 420
    /// A scene, a project.
    case standard = 560
    /// Anything with a sidebar.
    case wide = 760
}

struct Sheet<Content: View, Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String = ""
    var width: SheetWidth = .standard
    var height: CGFloat? = nil
    /// Off for a body that lays itself out — a rail beside a pane, a list that
    /// scrolls on its own.
    var scrolls: Bool = true
    @ViewBuilder let content: () -> Content
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(title).sans(Brand.Size.large, weight: .semibold)
                    .foregroundStyle(Brand.ink(dark))
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).sans(Brand.Size.small)
                        .foregroundStyle(Brand.ink3(dark))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider().overlay(Brand.rule(dark))

            Group {
                if scrolls {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) { content() }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    content()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(Brand.rule(dark))

            HStack(spacing: 8) {
                leading()
                Spacer(minLength: 8)
                trailing()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(width: width.rawValue, height: height)
        .background(Brand.panel(dark))
        // Every button in a sheet is a capsule unless it says otherwise.
        .buttonStyle(.capsule)
    }
}

extension Sheet where Leading == EmptyView {
    init(title: String, subtitle: String = "", width: SheetWidth = .standard,
         height: CGFloat? = nil, scrolls: Bool = true,
         @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(title: title, subtitle: subtitle, width: width, height: height,
                  scrolls: scrolls, content: content,
                  leading: { EmptyView() }, trailing: trailing)
    }
}

/// A field under its label, 5pt apart — the body's own spacing does the rest.
struct Field<Content: View>: View {
    let title: String
    var width: CGFloat? = nil
    let content: Content

    init(_ title: String, width: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.width = width
        self.content = content()
    }

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).fieldLabel(scheme == .dark).fixedSize()
            content
        }
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

// -------------------------------------------------- a sidebar list

/// **A sidebar list draws no system chrome of its own.** His finding,
/// 2026-09-15, with the left and right panels side by side: the scene list
/// sat on a grey slab of its own while the panel opposite floated clean, and
/// picking a scene painted the row the Mac's deep blue so the ink vanished
/// into it. Both were `.sidebar`'s doing — its source-list material under the
/// rows, and its own selection paint over them.
///
/// The list is plain, its ground is the panel's glass, and a picked row is a
/// **soft fill under ink** (`Brand.selectionQuiet`, `design/23-softer.html`
/// `.sc.on`) — the same quiet fill a chosen pill wears, because a picked row
/// is a choice, not a mode. The system's paint is switched off underneath
/// (`QuietSelection`) so the two never draw on top of each other.
///
/// The list is still a `List`: ↑↓ walk it, ⌘-click builds a set, ⇧-click
/// reaches across. Only the paint is ours.
extension View {
    func sidebarList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(QuietSelection())
    }

    /// The row's fill — the soft selection under a picked row, and the
    /// insets that make every row in a sidebar the same shape. The fill
    /// starts 12 in, where the sidebar's heading starts; a row puts its own
    /// 8 inside that so its first mark has air on both sides.
    func sidebarRow(picked: Bool, dark: Bool) -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
            .listRowSeparator(.hidden)
            .listRowBackground(
                RoundedRectangle(cornerRadius: Brand.radiusRow, style: .continuous)
                    .fill(picked ? Brand.selectionQuiet(dark) : .clear)
                    .padding(.horizontal, 12)
            )
    }
}

/// **A section's run in the scene list is a panel**, not a run of rows with
/// a coloured dot at the top. His report, 2026-09-20: *"the colors of the
/// sections/script are too much in the side bar next to the other colors of
/// each scene — they should more be grouped in sub panels."* The dot sat in
/// the same column as the scenes' time-of-day dots and read as one more of
/// them. Now the section's scenes sit on a lifted panel and the head carries
/// the name **in the section's colour** — that is the only place the colour
/// is drawn. A bar down the panel's left edge was tried and taken away the
/// same night: *"i dont like the lines on the left side - very GEN AI."*
///
/// The panel is drawn a row at a time, because a `List` draws row
/// backgrounds and nothing else: the head rounds the top, the last scene
/// rounds the bottom, the rows between are square, and the rows abut so the
/// pieces read as one shape.
enum PanelEdge { case head, middle, foot }

extension View {
    func sectionPanelRow(edge: PanelEdge, picked: Bool, dark: Bool) -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
            .listRowSeparator(.hidden)
            .listRowBackground(SectionPanel(edge: edge, picked: picked, dark: dark))
    }
}

extension View {
    /// A scene's row: on its section's panel when it has one, plain otherwise.
    @ViewBuilder
    func sectionRow(section: ViewModel.Sequence?, foot: Bool, picked: Bool, dark: Bool) -> some View {
        if section != nil {
            sectionPanelRow(edge: foot ? .foot : .middle, picked: picked, dark: dark)
        } else {
            sidebarRow(picked: picked, dark: dark)
        }
    }
}

/// One row's slice of the panel: the ground and the soft selection fill on
/// it.
struct SectionPanel: View {
    let edge: PanelEdge
    let picked: Bool
    let dark: Bool

    /// Air above the panel's head and under its foot, so two panels in a row
    /// stay two panels.
    private var above: CGFloat { edge == .head ? 6 : 0 }
    private var below: CGFloat { edge == .foot ? 4 : 0 }
    private var corners: RectangleCornerRadii {
        let r = Brand.radiusRow
        switch edge {
        case .head: return .init(topLeading: r, bottomLeading: 0, bottomTrailing: 0, topTrailing: r)
        case .middle: return .init()
        case .foot: return .init(topLeading: 0, bottomLeading: r, bottomTrailing: r, topTrailing: 0)
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            UnevenRoundedRectangle(cornerRadii: corners, style: .continuous)
                .fill(Brand.panel(dark))
            if picked {
                RoundedRectangle(cornerRadius: Brand.radiusRow - 3, style: .continuous)
                    .fill(Brand.selectionQuiet(dark))
                    .padding(.leading, 6).padding(.trailing, 3)
            }
        }
        .padding(.top, above).padding(.bottom, below)
        .padding(.horizontal, 12)
    }
}

/// Finds the `NSTableView` under a `List` and tells it to paint no selection
/// of its own. Selection still *works* — clicks, arrows, ⌘ and ⇧ — it is
/// only the highlight that goes, so `sidebarRow` can draw the app's.
struct QuietSelection: NSViewRepresentable {
    func makeNSView(context: Context) -> Finder { Finder() }
    func updateNSView(_ view: Finder, context: Context) { view.hush() }

    final class Finder: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            hush()
        }

        func hush() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // The background view is a sibling of the list's host; the
                // table is a few levels up and then down. Nearest one wins,
                // and the walk stops short of the window so it cannot reach
                // some other list's table.
                var node: NSView? = self.superview
                var steps = 0
                while let here = node, steps < 5 {
                    if let table = Self.table(in: here) {
                        table.selectionHighlightStyle = .none
                        table.backgroundColor = .clear
                        table.enclosingScrollView?.drawsBackground = false
                        return
                    }
                    node = here.superview
                    steps += 1
                }
            }
        }

        private static func table(in node: NSView) -> NSTableView? {
            if let table = node as? NSTableView { return table }
            for sub in node.subviews {
                if let table = table(in: sub) { return table }
            }
            return nil
        }
    }
}


// MARK: - an on/off in a mode's bar

/// **The Filter and Sort pill, for every mode.** A glyph and its word in a
/// hairline capsule, lit in the film's tint while it is on. Schedule's bar
/// used bare round glyphs for the same kind of thing; one look now.
struct BarToggle: View {
    let icon: String
    let text: String
    var on: Bool = false
    var help: String = ""
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11))
                Text(text).sans(13, weight: on ? .semibold : .regular)
            }
            .foregroundStyle(on ? Brand.accent(dark) : Brand.ink2(dark))
            .padding(.horizontal, Brand.barPadding)
            .frame(height: Brand.barHeight)
            .barPill(dark, on: on)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help.isEmpty ? text : help)
    }
}
