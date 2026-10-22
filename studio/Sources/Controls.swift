import SwiftUI
import AppKit

/// The controls the shell is built from.
///
/// None of them are SwiftUI's own. A system segmented control brings Apple's
/// accent colour, Apple's corner radius and Apple's type scale, none of which
/// were chosen here — and the chrome is most of what makes an app feel like
/// itself.

// ------------------------------------------------------- segmented tab strip

/// **How hard the chrome is being measured.** A tally of how many times the two
/// switchers have had to build themselves during this launch.
///
/// It exists because the startup freeze of 2026-09-02 is a *layout* fault, and a
/// layout fault leaves no wrong value behind for a check to catch — the app
/// simply never finishes drawing. What it does leave is work: a switcher that
/// settles costs a couple of dozen of these, and one that is thrashing costs
/// thousands. The number is the signal, and unlike the freeze itself it can be
/// read on a launch that came up perfectly well.
///
/// Main thread only, which is where view bodies are built.
enum LayoutCost {
    static var switcherBodies = 0
}

/// The centred tab strip at the top of the content area: a quiet track with a
/// single pill riding in it. Icon and label, because a shot list and a
/// storyboard are not distinguishable by glyph alone.
struct Segmented<T: Hashable>: View {
    struct Item: Identifiable {
        let value: T
        let title: String
        /// **Optional**, because the two rows this control now draws want
        /// different weights. The modes across the top bar wear icons — they
        /// are the loudest thing in the chrome and a glyph is what makes them
        /// findable without reading. The views over the table are words only:
        /// they sit beside a label that already says *Views*, and four more
        /// little pictures in a bar that already has a search box, two menus
        /// and a zoom is noise.
        var icon: String? = nil
        var id: T { value }
    }

    @Binding var selection: T
    let items: [Item]
    /// **The quiet weight.** One control, two jobs, and they must not look
    /// alike: the top bar says *which part of the program you are in* and gets
    /// the solid accent capsule, the strongest single signal in this chrome.
    /// The views strip says *which way you are looking at it* — a smaller
    /// question, so a smaller voice: no glass tray around it, and the chosen
    /// one filled with ink rather than colour. Making both shout is how you
    /// end up unable to tell which of the two you just changed.
    var quiet: Bool = false
    /// **A right-click menu on each pill** (stage 5 step 4 B: the modes'
    /// Show / Turn Off). Fixed for the life of a switcher, like `quiet`.
    var menu: ((T) -> AnyView)? = nil
    /// **Squeezing, for a narrow top bar.** `tight` takes the air out of the
    /// pills; `iconsOnly` draws each mode as its glyph (the word moves to the
    /// tooltip). Both are fixed for the life of a switcher, like `quiet`.
    var tight: Bool = false
    var iconsOnly: Bool = false
    @Environment(\.colorScheme) private var scheme
    @State private var hovering: T?

    private var dark: Bool { scheme == .dark }

    /// **Branching on `quiet` here is free.** It is fixed for the life of a
    /// given switcher — the top bar's is always loud, the views strip's always
    /// quiet — so no instance ever crosses from one branch to the other, and
    /// the hover lives in `@State` on this view rather than in the branch.
    @ViewBuilder var body: some View {
        let _ = { LayoutCost.switcherBodies += 1 }()
        if quiet {
            strip.padding(2)
        } else {
            strip.padding(4)
                .systemGlass(Capsule(style: .continuous), dark: dark)
        }
    }

    /// **Six fixed slots, not a `ForEach`.** This is the fix for the startup
    /// freeze of 2026-09-02, and it is worth saying why something so plain
    /// replaced something so ordinary.
    ///
    /// `ForEach` builds a *dynamic* view list — SwiftUI keeps a
    /// `DynamicContainerInfo` for it and can rebuild its items whenever it is
    /// asked to. Three captures of the frozen app all show the same thing: the
    /// window's own sizing pass asking this control how big it is, and the
    /// answer rebuilding the entire list from nothing —
    /// `SizeFittingLayoutComputer` → `DynamicContainerInfo.updateItems` →
    /// `ForEachList.applyNodes` → `HStack._makeView` — minting fresh
    /// attribute-graph nodes each time (`AG::Graph::add_attribute`). Nothing
    /// gives those back, which is the gigabyte a minute; and the enclosing
    /// stacks re-measure at every level, so the cost multiplies until the
    /// window never finishes drawing at all.
    ///
    /// A switcher has three or four items, fixed at compile time — the cases of
    /// an enum. It never needed to be dynamic. Written as fixed slots it is a
    /// plain `TupleView`: there is no dynamic list to rebuild, so the size
    /// question has a cheap answer and asking it repeatedly costs nothing.
    ///
    /// Six is headroom over the four `SideTab` has; anything past it simply
    /// would not be drawn, so the check below is a real guard and not decoration.
    private var strip: some View {
        HStack(spacing: 2) {
            pill(0); pill(1); pill(2); pill(3); pill(4); pill(5)
        }
        .animation(.easeOut(duration: 0.12), value: selection)
    }

    @ViewBuilder private func pill(_ at: Int) -> some View {
        if at < items.count {
            let item = items[at]
            let on = item.value == selection
            Button {
                selection = item.value
            } label: {
                HStack(spacing: 6) {
                    if let icon = item.icon {
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .medium))
                    }
                    if !iconsOnly {
                    // **Every pill is as wide as its own bold**, chosen or not.
                    //
                    // His report, 2026-09-04, with a photograph of *Storyboard*
                    // and *Document* printed on top of each other: *"this build
                    // broke the views tabs."* Nothing was broken in the settled
                    // state — all three views photograph correctly — and that
                    // was the clue. Semibold is wider than regular, so moving
                    // the choice changed the width of two pills at once, and
                    // the strip's own 0.12s ease animated every pill's frame
                    // through the gap. For those four frames the words really
                    // do overlap, and a screenshot catches it.
                    //
                    // Reserving the bold width means nothing moves when the
                    // choice does: only the capsule's fill and the lettering's
                    // weight change, and both of those crossfade cleanly. The
                    // hidden copy is the measurer and never draws.
                    Text(item.title)
                        .sans(Brand.Size.body, weight: .semibold)
                        .hidden()
                        .overlay {
                            Text(item.title)
                                .sans(Brand.Size.body, weight: on ? .semibold : .regular)
                                .fixedSize()
                        }
                    }
                }
                    // **A pill, filled solid when it is the one you are on** —
                    // the mock's tab strip, and the strongest single signal in
                    // its chrome. A tinted background with coloured text reads
                    // as "highlighted"; a solid capsule reads as "selected".
                    // **The quiet one cannot use white.** Its chosen pill is
                    // filled with ink, which in dark mode *is* near-white — so
                    // white lettering on it came out white on white and the
                    // word you were standing on was the one word you could not
                    // read. Caught by looking at it; no stored value was wrong,
                    // so nothing in the battery could have seen it.
                    // **The quiet one is a choice, not a mode** — the grammar
                    // of 2026-09-14: a sub-tab's chosen pill is a soft fill
                    // with ink lettering. Solid film colour is the top bar's
                    // alone.
                    .foregroundStyle(on ? (quiet ? Brand.ink(dark) : Color.white)
                                        : Brand.ink2(dark))
                    // **The quiet pill's numbers are the bar's numbers** —
                    // `Brand.barPadding` and a height of `Brand.barHeight`,
                    // which are literally these, taken from here because they
                    // are the pills he asked everything else to look like.
                    .padding(.horizontal, quiet ? Brand.barPadding : (iconsOnly ? 11 : (tight ? 8 : 13)))
                    .padding(.vertical, quiet ? 4.5 : 5.5)
                    .background {
                        Capsule(style: .continuous)
                            .fill(on ? (quiet ? Brand.cellHover(dark) : Brand.accent(dark))
                                     : (hovering == item.value ? Brand.rowHover(dark) : .clear))
                            .shadow(color: on && !quiet ? Brand.accent(dark).opacity(0.35) : .clear,
                                    radius: 6, y: 1)
                    }
                    .contentShape(Rectangle())
                }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help(iconsOnly ? item.title : "")
            .onHover { hovering = $0 ? item.value : (hovering == item.value ? nil : hovering) }
            .modifier(PillMenu(menu: menu.map { make in { make(item.value) } }))
        }
    }
}

/// A pill's right-click menu, when its switcher has one.
private struct PillMenu: ViewModifier {
    let menu: (() -> AnyView)?

    @ViewBuilder func body(content: Self.Content) -> some View {
        if let menu {
            content.contextMenu { menu() }
        } else {
            content
        }
    }
}

// ------------------------------------------------------------------ the views

/// **`Views` and then the ways of looking.** His wording, 2026-08-23.
///
/// The pills on their own were ambiguous once the mode switcher moved up into
/// the top bar wearing the same grammar: two rows of capsules, one above the
/// other, neither saying what it was choosing between. The label is four
/// letters and it removes the whole question.
/// **The four modes, across the top bar.** Words, no icons — this project's
/// standing ruling on this control, made when it lived in the sidebar and
/// applied again to the side panel's tabs: *three words in a row of capsules
/// read faster than three little pictures, and the icons were doing no work the
/// words were not.*
///
/// It flexes for the same reason `ViewBar` does, and it is the one that
/// mattered: held open at a fixed width, this switcher — not the filter bar —
/// was what set the smallest the whole window could be, taking the floor from
/// 1015 points to 1087 and stopping the table giving its last spread back.
/// Proved rather than guessed: with this control taken out of the bar the
/// window went straight back to any width asked of it.
///
/// The menu only ever appears below about a thousand points, which is narrower
/// than the app is worth using. It is there so the *window* is not held hostage
/// by the chrome.
/// A dropdown that does not look like macOS.
///
/// **His ruling, 2026-09-04:** *"make all the dropdowns in the settings and
/// anywhere else in the program non-mac native looking. they are very ugly."*
/// Fair. The system popup button wears a tinted bezel and a stacked double
/// chevron, and it sits at odds with everything around it — the flat rules, the
/// quiet inks, `Segmented`'s capsules. This is the same control in the app's own
/// clothes: a plain rounded field, a hairline, one small chevron.
///
/// **The list it opens is still the system's, and that is deliberate.** A
/// popover is a window of its own and does not show up in a photograph of this
/// one — `Document.typeStrip` was written the shape it is for exactly that
/// reason — so a hand-drawn list would put every dropdown in the program beyond
/// the reach of a check. The part he was looking at is the part that was ugly,
/// and that part is ours now.
///
/// **The `ForEach` is inside the menu, never in the label.** Building a dynamic
/// list is what froze the app on 2026-09-02 (see `Segmented.strip`), but that
/// cost is paid when a size question is asked over and over — and a menu's
/// content is not built until it opens. The label, which *is* asked repeatedly,
/// is one `Text`.
struct Dropdown<T: Hashable>: View {
    struct Item: Identifiable {
        let value: T
        let title: String
        var id: T { value }

        init(_ value: T, _ title: String) {
            self.value = value
            self.title = title
        }
    }

    @Binding var selection: T
    let items: [Item]
    /// Nil sizes to the widest thing in it. A width is for a row of dropdowns
    /// that should line up whatever they happen to say.
    var width: CGFloat? = nil
    /// Figures read as mono, names read as sans — the same split the rest of
    /// the chrome already makes.
    var mono: Bool = false
    var size: CGFloat = Brand.Size.body
    /// A value with a colour shows its dot inside the field.
    var dot: Color? = nil

    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false
    private var dark: Bool { scheme == .dark }

    /// What the field says when it is shut. Empty when the held value is not
    /// one of the choices, which is honest — a made-up label would be worse.
    private var said: String {
        items.first { $0.value == selection }?.title ?? ""
    }

    var body: some View {
        Menu {
            Picker("", selection: $selection) {
                ForEach(items) { item in
                    Text(item.title).tag(item.value)
                }
            }
            .labelsHidden()
            .pickerStyle(.inline)
        } label: {
            // **The one field shape** — the same hairline rounded field a
            // typed value sits in, with the chevron at the right edge.
            HStack(spacing: 8) {
                if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
                shut
                Spacer(minLength: 0)
                MenuMark()
            }
            .frame(width: width.map { $0 - 20 }, alignment: .leading)
            .field(dark)
            .contentShape(RoundedRectangle(cornerRadius: Brand.radius, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .focusEffectDisabled()
        .fixedSize(horizontal: width == nil, vertical: true)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.10), value: hovering)
    }

    @ViewBuilder private var shut: some View {
        if mono {
            Text(said).mono(size).foregroundStyle(Brand.ink(dark)).lineLimit(1)
        } else {
            Text(said).sans(size).monospacedDigit()
                .foregroundStyle(Brand.ink(dark)).lineLimit(1)
        }
    }
}

struct ModeSwitcher: View {
    @Binding var selection: SideTab
    /// The modes this project has on; every mode until the server says
    /// otherwise (stage 5 step 4, piece B).
    var modes: [SideTab] = SideTab.allCases
    /// Whether + and Turn Off are offered: the modes are the project's.
    var canChange = false
    var turnOn: (SideTab) -> Void = { _ in }
    var turnOff: (SideTab) -> Void = { _ in }
    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }
    private var off: [SideTab] { SideTab.allCases.filter { !modes.contains($0) } }

    /// **Gives way in steps, never before it has to.** The bar offers this
    /// switcher exactly the room left over (see `TopBarLayout`), and it takes
    /// the first of these that fits: words, words with less air, glyphs, and
    /// last the one-pill menu. The "+" rides inside each so it never falls
    /// out of the measuring.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(tight: false, iconsOnly: false)
            row(tight: true, iconsOnly: false)
            row(tight: true, iconsOnly: true)
            HStack(spacing: 6) {
                compact
                if canChange && !off.isEmpty { plus }
            }
        }
    }

    private func row(tight: Bool, iconsOnly: Bool) -> some View {
        HStack(spacing: tight ? 4 : 6) {
            pills(tight: tight, iconsOnly: iconsOnly)
            if canChange && !off.isEmpty { plus }
        }
    }

    @ViewBuilder private func pills(tight: Bool, iconsOnly: Bool) -> some View {
        let items = modes.map { Segmented<SideTab>.Item(value: $0, title: $0.title,
                                                        icon: iconsOnly ? $0.icon : nil) }
        if modes.isEmpty {
            Color.clear.frame(width: 0, height: 0)
        } else if canChange {
            Segmented(selection: $selection, items: items,
                      menu: { mode in AnyView(menu(for: mode)) },
                      tight: tight, iconsOnly: iconsOnly)
        } else {
            Segmented(selection: $selection, items: items, tight: tight, iconsOnly: iconsOnly)
        }
    }

    /// **Right-click a mode:** turn it off (asked first). Clicking shows it.
    @ViewBuilder private func menu(for mode: SideTab) -> some View {
        Button("Turn Off \(mode.title)…", role: .destructive) { turnOff(mode) }
    }

    /// **+ turns a mode on.** Only the ones that are off are listed.
    private var plus: some View {
        Menu {
            Section("Turn On") {
                ForEach(off) { mode in
                    Button(mode.title) { turnOn(mode) }
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Brand.ink2(dark))
                .frame(width: 26, height: 26)
                .background { Circle().fill(Brand.rowHover(dark)) }
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Turn On a Mode")
    }

    private var compact: some View {
        Menu {
            ForEach(modes) { mode in
                Button {
                    selection = mode
                } label: {
                    if mode == selection {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Text(mode.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selection.icon).font(.system(size: 11))
                Text(modes.contains(selection) ? selection.title : "No Modes").sans(13, weight: .semibold)
            }
            .foregroundStyle(Color.white)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        // Outside the `Menu`, or it is thrown away — see `Segmented` and the
        // note in `Filtering.barFace`. This one only shows below about a
        // thousand points of window, which is why nobody had seen it cramped.
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background { Capsule(style: .continuous).fill(Brand.accent(dark)) }
        .help("Which part of the film")
    }
}

struct ViewBar: View {
    @Binding var selection: SceneTab
    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }

    /// **Three widths, and the window may be as narrow as the smallest.**
    ///
    /// It was one width held open with `fixedSize`, which stopped the pills
    /// being crushed and had a cost nothing on screen showed: an immovable
    /// thing in the filter bar sets the smallest the *whole window* may be, and
    /// the floor went from 1015 points to 1087. `layoutPriority` does not help
    /// — a priority decides who gets the spare room, not how little a thing can
    /// live on.
    ///
    /// So: the label goes first, then the pills become the name of the view you
    /// are on with the other two behind it. At any width he actually works at,
    /// the first one fits.
    var body: some View {
        // **No "Views" label** — with a choice drawn as a choice and a button
        // as a button, the strip explains itself. 2026-09-14.
        ViewThatFits(in: .horizontal) {
            pills
            compact
        }
    }

    private var pills: some View {
        Segmented(selection: $selection,
                  items: SceneTab.allCases.map { .init(value: $0, title: $0.title) },
                  quiet: true)
    }

    /// The last resort: one button wearing the current view's name.
    private var compact: some View {
        Menu {
            ForEach(SceneTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    if tab == selection {
                        Label(tab.title, systemImage: "checkmark")
                    } else {
                        Text(tab.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selection.icon).font(.system(size: 11))
                Text(selection.title).sans(13, weight: .semibold)
            }
            .foregroundStyle(Brand.ink(dark))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 10).padding(.vertical, 6)   // outside, or dropped
        .pill(dark, radius: 9)
        .help("Which view of this scene")
    }
}

// ------------------------------------------------------------- small pieces

/// A quiet square button for chrome: the sidebar's ＋, the toolbar's icons.
///
/// **And the one button every pop-out wears.** Until 2026-08-29 the three
/// pop-outs each drew their own: 26 points in the viewer on `Brand.glass2` lit
/// blue, 28 in the frames window on plain white lit *yellow*, and none at all
/// in the scan window — so the same scissors, trimming the same clip, was two
/// different buttons depending on which window you were in. `lit` is the only
/// thing this needed to serve all three.
/// **A `ToolButton` that turns while something is happening.**
///
/// His ask, 2026-08-31: *"i want the sync button to have an animation whenever
/// they are actually in the syncing process"*.
///
/// The sync button used to be *replaced* by a `ProgressView` for the duration,
/// which reads as the app losing the control rather than using it — and the
/// thing he wanted to watch was that button working. Its icon is already a
/// circle of arrows, so it simply turns.
///
/// **One `Animation`, restarted by the flag rather than by a timer.** A
/// `repeatForever` animation attached to a rotation that flips between 0 and
/// 360 keeps its momentum across redraws; driving it from a `Timer` makes it
/// stutter every time SwiftUI rebuilds the bar, which the toolbar does often.
struct SpinningToolButton: View {
    let icon: String
    var size: CGFloat = 13
    var help: String = ""
    var spinning: Bool
    var action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false
    @State private var turn = false

    var body: some View {
        Button(action: action) {
            let dark = scheme == .dark
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(hovering ? Brand.ink(dark) : Brand.ink2(dark))
                .rotationEffect(.degrees(turn ? 360 : 0))
                .animation(spinning
                           ? .linear(duration: 1).repeatForever(autoreverses: false)
                           : .default,
                           value: turn)
                .frame(width: Brand.barHeight, height: Brand.barHeight)
                .background {
                    Capsule(style: .continuous)
                        .fill(hovering ? Brand.cellHover(dark) : .clear)
                }
                .overlay {
                    Capsule(style: .continuous).strokeBorder(Brand.rule2(dark), lineWidth: 1)
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        // **Pressing it while it turns must not start a second one.** The sync
        // itself guards against that too, but a button that looks pressable and
        // does nothing is its own small lie.
        .disabled(spinning)
        .onChange(of: spinning) { _, now in
            // Reset to a whole turn when it stops, so it never rests crooked.
            turn = now
        }
        .onAppear { turn = spinning }
    }
}

struct ToolButton: View {
    let icon: String
    var size: CGFloat = 13
    var help: String = ""
    /// **In force.** One colour for "this is on", everywhere in the app: the
    /// accent. Yellow was the frames window's alone and meant the same thing.
    var lit: Bool = false
    var action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            // **A round glass button**, always drawn rather than appearing on
            // hover. The mock's +, share and "…" sit in soft circles at the
            // top right, and that is most of why its chrome reads as a current
            // Mac app: a bare glyph is a label, a glyph in a well is a button.
            let dark = scheme == .dark
            // **A hairline capsule, 24pt, like every other button** — the
            // grammar of 2026-09-14. Lit is the film's tint with the glyph in
            // the film's colour; never a solid accent circle.
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(lit ? Brand.accent(dark)
                                     : (hovering ? Brand.ink(dark) : Brand.ink2(dark)))
                .frame(width: Brand.barHeight, height: Brand.barHeight)
                .background {
                    Capsule(style: .continuous)
                        .fill(lit ? Brand.accentTint(dark)
                                  : (hovering ? Brand.cellHover(dark) : .clear))
                }
                .overlay {
                    if !lit {
                        Capsule(style: .continuous)
                            .strokeBorder(Brand.rule2(dark), lineWidth: 1)
                    }
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        // Chrome does not take a focus ring. Without this the first button in
        // the top bar wears one the moment the window becomes key, which reads
        // as a stuck selection rather than as keyboard focus.
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// A capsule tag. The vocabulary behind it arrives with the table; the shape is
/// settled now so nothing has to be re-drawn later.
struct Chip: View {
    let text: String
    var colour: Color?
    var icon: String?
    /// **Taken in, not read inside.** The default is evaluated where the chip
    /// is built — in the table's body, which does re-run on a zoom — so the
    /// stored value changes and SwiftUI stops skipping this view. Reading
    /// `Brand.density` from inside the body instead is why pills stayed the
    /// same size while every measurement around them scaled.
    var density: CGFloat = Brand.density

    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        let tint = colour ?? Brand.ink3(dark)
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: Brand.type(Brand.Size.tiny, at: density), weight: .medium))
            }
            // Never truncated and never squeezed to one line. A chip whose
            // text has been cut is worse than no chip: "Short-Sid…" and
            // "Short-Sided" are the same shot until you go and look.
            Text(text).sans(Brand.type(Kit.Size.tag, at: density), weight: .semibold)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(tint)
        // One look: the kit's tag, the same size and shape in every app.
        .padding(.horizontal, Brand.pad(Kit.tagPadH, at: density))
        .padding(.vertical, Brand.pad(Kit.tagPadV, at: density))
        // **A box, not a capsule.** A capsule's ends are half its height, so
        // a lens name that wraps to three lines became a blob with the words
        // spilling past its curves — his report, 2026-09-30. A small fixed
        // corner holds one line and four the same way.
        .background {
            RoundedRectangle(cornerRadius: Brand.pad(Kit.Radius.tag, at: density), style: .continuous)
                .fill(tint.opacity(dark ? 0.26 : 0.13))
        }
    }
}

/// **Lens Stack, the second line** — the shot's filters and modifiers under
/// its lens, quiet: small, in the lens colour turned down, a ring for a filter
/// and a diamond for a modifier. No box and no outline; the lens chip above it
/// is the loud one. His note on variant B, 2026-10-15: "make the lines a
/// little less heavy".
struct LensStackLine: View {
    let filters: [String]
    let modifiers: [String]
    var density: CGFloat = Brand.density

    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        let ink = Brand.columnInk("lens", dark).opacity(dark ? 0.85 : 0.9)
        WrappingRow(spacing: Brand.pad(9, at: density), runSpacing: Brand.pad(2, at: density)) {
            ForEach(filters, id: \.self) { name in item(name, ring: true, ink: ink) }
            ForEach(modifiers, id: \.self) { name in item(name, ring: false, ink: ink) }
        }
    }

    private func item(_ name: String, ring: Bool, ink: Color) -> some View {
        HStack(spacing: 4) {
            Group {
                if ring {
                    Circle().strokeBorder(ink, lineWidth: 1)
                } else {
                    Rectangle().strokeBorder(ink, lineWidth: 1).rotationEffect(.degrees(45))
                        .scaleEffect(0.82)
                }
            }
            .frame(width: Brand.pad(6, at: density), height: Brand.pad(6, at: density))
            Text(name)
                .sans(Brand.type(Brand.Size.small - 1, at: density), weight: .regular)
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .help(ring ? "Filter" : "Modifier")
    }
}

/// The search field pinned to the bottom of the sidebar.
///
/// It is a plain `TextField` wearing our own chrome rather than
/// `.searchable`, which puts itself in the toolbar on macOS and cannot be
/// asked to live at the foot of a sidebar.
struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Brand.ink3(dark))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .sans(13)
                .foregroundStyle(Brand.ink(dark))
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.ink4(dark))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // The one field shape, the same as every field in every sheet.
        .background {
            RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
                .fill(Brand.menu(dark))
                .overlay {
                    RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
                        .strokeBorder(focused ? Brand.accentLine(dark) : Brand.rule2(dark),
                                      lineWidth: 1)
                }
        }
    }
}

/// **Sync with Drive** — Ref 229, the switch on a location and on a mood board.
///
/// His ask, 2026-08-22: *"It happens in the BG right now, but it's something
/// that should be visible and something I can opt into if I so chose."* The
/// machinery has honoured this since 2026-08-23; until now there was no way to
/// flip it except through Claude, which is the opposite of visible.
///
/// **One control for both**, because a location and a board differ in what
/// their switch is worth, never in what it looks like. A location's is on
/// unless he turns it off; a board's is off until he turns it on — and neither
/// of those is a fact this control knows or should.
///
/// **A switch that cannot do anything says so and does not move.** The film has
/// to carry a Drive folder before any of this means a thing, and a live switch
/// that quietly achieves nothing is worse than a dead one. That sentence is one
/// of the four the app is allowed: *why something cannot work here*.
struct DriveSwitch: View {
    let on: Bool
    /// Whether the film itself has a Drive folder set in its settings.
    let filmIsLinked: Bool
    let set: (Bool) -> Void

    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Sync with Drive", isOn: Binding(get: { on }, set: set))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .sans(11)
                .foregroundStyle(Brand.ink2(dark))
                .disabled(!filmIsLinked)
            if !filmIsLinked {
                Text("No Drive Folder").sans(10)
                    .foregroundStyle(Brand.ink4(dark))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// What a tab shows before its real content is built. Says which phase task
/// fills it, so an empty pane reads as unfinished rather than broken.
/// **Nothing here yet.** One mark, one line, and the way in.
///
/// There were six of these and none of them agreed: the mark came at 20, 22
/// or 26 points, the line at 11.5, 12.5, 13 or 14, and the way in was a bare
/// accent link on one screen and a pill button on the next — on two screens
/// one tab apart, reached by adjacent pills. `compact` is the only difference
/// that survived, because a sidebar's well is a fifth of a window's.
///
/// **The action lives inside it.** The old one filled whatever it was handed,
/// so a caller putting a button underneath had the message take the whole
/// height and push its own button off the bottom edge; three of them carried
/// the same `fixedSize` line to undo that, and each explained it again.
///
/// **The line is a sentence, not a title** — his law: an empty state says
/// what is missing, in one line, and stops. `No locations yet`, never `No
/// Locations Yet`.
struct EmptyState<Action: View>: View {
    let title: String
    var detail: String = ""
    /// A sidebar's well rather than a window's.
    var compact: Bool = false
    @ViewBuilder var action: () -> Action

    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        // **One line, no icon, and the way in as a "+ Verb" capsule** — his
        // call, 2026-09-15: no field-type glyphs anywhere, and an empty state
        // says what is missing and stops.
        VStack(spacing: compact ? 8 : 10) {
            Text(title)
                .sans(compact ? Brand.Size.small : Brand.Size.title,
                      weight: compact ? .regular : .medium)
                .foregroundStyle(compact ? Brand.ink3(dark) : Brand.ink2(dark))
            if !detail.isEmpty {
                Text(detail).sans(Brand.Size.body)
                    .foregroundStyle(Brand.ink3(dark))
                    .frame(maxWidth: 320)
            }
            action()
                .buttonStyle(.capsule)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 18)
    }
}

extension EmptyState where Action == EmptyView {
    init(title: String, detail: String = "", compact: Bool = false) {
        self.init(title: title, detail: detail, compact: compact) { EmptyView() }
    }
}

/// **The mark that says these words open a menu.**
///
/// A `.borderlessButton` menu drew one of these itself, and drew it in AppKit's
/// own size and ink. Moving to `.menuStyle(.button)` so the label is drawn as
/// written takes that indicator with it — which is right, because now it is
/// ours: one size, one weight, one ink, wherever a value opens a list.
///
/// **It goes only on a value you can change**, never on a button that does
/// something. `Filter` and `Add` do not get one; a scene's sequence does.
struct MenuMark: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: Brand.Icon.tiny, weight: .semibold))
            .foregroundStyle(Brand.ink4(scheme == .dark))
    }
}

/// **The size slider, wherever the app has one.**
///
/// There were three, and no two alike: the table's zoom was `.mini`, 96 points
/// wide and sat in a pill; the one on a reference board and a location was
/// full size, 108 wide and had no edge at all; the storyboard's was full size
/// and 160. His report, 2026-09-08: *"the slider inside of References for
/// image size is different than the one inside of the one for the table, which
/// always kind of throws me off."*
///
/// The chrome is the bar's — `barHeight`, `barPadding`, a `barPill` — because
/// the table's lives in that bar and the others should not look like a
/// different program's control for doing the same thing.
struct SizeSlider<Slider: View>: View {
    /// The mark for the small end, and for the large.
    let small: String
    let large: String
    /// Built here rather than held as a closure — see `Labelled`.
    let slider: Slider

    init(small: String, large: String, @ViewBuilder slider: () -> Slider) {
        self.small = small
        self.large = large
        self.slider = slider()
    }

    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: small)
                .font(.system(size: Brand.Icon.small)).foregroundStyle(Brand.ink3(dark))
            slider.controlSize(.mini).frame(width: 96)
            Image(systemName: large)
                .font(.system(size: Brand.Icon.inline)).foregroundStyle(Brand.ink3(dark))
        }
        // **One object, not three loose things.** A slider with a mark floating
        // either side of it was the only item in the table's bar with no edge,
        // so it read as debris rather than as a control — and on a board it had
        // no edge at all.
        .frame(height: Brand.barHeight)
    }
}

/// **A field under its small capital label.** Two files had this function
/// written out identically and a third almost so.
struct Labelled<Content: View>: View {
    let title: String
    var width: CGFloat? = nil
    /// **Built here rather than held as a closure**, so a caller wrapping this
    /// in a function of its own does not have to mark its own parameter
    /// escaping to hand it over.
    let content: Content

    init(title: String, width: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.width = width
        self.content = content()
    }

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .fieldLabel(scheme == .dark)
                .fixedSize()
            content
        }
        .frame(width: width, alignment: .leading)
    }
}

/// The scene's synopsis, under its heading: **one line at rest, the whole of
/// it revealed when you click.**
///
/// Revealed, not opened for typing — his call, and the right one: the other
/// things on this line are a word each, and a click that puts a caret in
/// them is the shortest path. A synopsis is a sentence; you click it to
/// *read* it, and you write it on the scene's page where there is room.
struct SynopsisField: View {
    let text: String
    let dark: Bool
    /// Where the writing happens — the scene's own page.
    let onEdit: () -> Void

    @State private var revealed = false
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if revealed && !text.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(text)
                        .sans(13)
                        .foregroundStyle(Brand.ink(dark))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 420, alignment: .leading)
                    Button("Edit on the scene page") { onEdit() }
                        .buttonStyle(.plain)
                        .sans(10, weight: .medium)
                        .foregroundStyle(Brand.accent(dark))
                }
            } else {
                // Hugs its words when there are few, truncates at 300 when
                // there are many. A plain `maxWidth: 300` claimed all three
                // hundred points whether or not there was anything in it,
                // which is what put a hand's width of nothing between
                // "Add synopsis" and the location beside it.
                Text(text.isEmpty ? "Add synopsis" : text)
                    .sans(Brand.Size.body, weight: text.isEmpty ? .regular : .medium)
                    .foregroundStyle(text.isEmpty ? Brand.ink3(dark) : Brand.ink2(dark))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 300, alignment: .leading)
                    .fixedSize(horizontal: text.count < 46, vertical: false)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: Brand.radiusChip, style: .continuous)
                .fill(revealed ? Brand.menu(dark) : (hovering ? Brand.cellHover(dark) : .clear))
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            // The reveal is the animation — the line grows into the whole
            // sentence and folds back, rather than a panel appearing over it.
            if text.isEmpty { onEdit(); return }
            withAnimation(.easeOut(duration: 0.18)) { revealed.toggle() }
        }
        .help(text.isEmpty ? "Add a synopsis on the scene’s page" : "Click to read it all")
    }
}

/// The scene's tags, off the project's own list — pills you can add to and
/// take off, never free text that drifts from what the shots use.
struct SceneTags: View {
    /// **Two parts, because the band draws them in two groups**: the chips
    /// are values and sit with the location and the day; "+ Add tag" is an
    /// action and sits with "+ Add synopsis". A board draws both together.
    enum Part { case chips, adder, both }

    let held: [String]
    let options: [String]
    let dark: Bool
    var part: Part = .both
    let onChange: ([String]) -> Void

    var body: some View {
        HStack(spacing: 6) {
            if part != .adder {
                ForEach(held, id: \.self) { tag in
                    Chip(text: tag, colour: Brand.chipInk("tags", tag, dark))
                        .onTapGesture { onChange(held.filter { $0 != tag }) }
                        .help("Remove “\(tag)”")
                }
            }
            if part != .chips {
                Menu {
                    ForEach(options.filter { !held.contains($0) }, id: \.self) { tag in
                        Button(tag) { onChange(held + [tag]) }
                    }
                    if options.filter({ !held.contains($0) }).isEmpty {
                        Button("Nothing left") {}.disabled(true)
                    }
                } label: {
                    PlusLabel(text: "Add tag", dark: dark)
                        .rowAction(dark)
                }
                .help("Tags")
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .focusEffectDisabled()
                .fixedSize()
            }
        }
    }
}


// ---------------------------------------------------------------- the pointer

/// **A control that answers the pointer.**
///
/// His finding, 2026-08-20: *"I've lost some of my hover abilities, like over
/// top of the dropdown menus — they stay static as my mouse goes over them."*
/// A borderless SwiftUI `Menu` has no hover state of its own, so a row of them
/// reads as a photograph of controls rather than as controls. Everything the
/// pointer can press should say so under the pointer; this is that, in one
/// line, so no surface has to invent its own version.
struct Hovering: ViewModifier {
    let dark: Bool
    var radius: CGFloat = 6
    var horizontal: CGFloat = 6
    var vertical: CGFloat = 3
    @State private var over = false

    func body(content: Self.Content) -> some View {
        content
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(over ? Brand.cellHover(dark) : .clear)
            }
            .contentShape(Rectangle())
            .onHover { over = $0 }
    }
}

extension View {
    func hovering(_ dark: Bool, radius: CGFloat = 6,
                  horizontal: CGFloat = 6, vertical: CGFloat = 3) -> some View {
        modifier(Hovering(dark: dark, radius: radius,
                          horizontal: horizontal, vertical: vertical))
    }
}

/// The same idea for something that already has a background of its own: it
/// lifts a shade under the pointer instead of gaining one.
private struct Brighten: ViewModifier {
    let dark: Bool
    @State private var over = false

    func body(content: Self.Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
                    .fill(over ? Brand.ink(dark).opacity(dark ? 0.10 : 0.05) : .clear)
            }
            .contentShape(Rectangle())
            .onHover { over = $0 }
    }
}

extension View {
    func brighten(_ dark: Bool) -> some View { modifier(Brighten(dark: dark)) }
}

/// The outline around a dragged range of cells, drawn a side at a time.
///
/// A range is many cells and wants **one** outline, not one per cell, so each
/// cell draws only the sides that face out of the selection. Together they
/// make the single rectangle a sheet draws — which is what he asked for, with
/// Google Sheets held up beside it.
struct RangeEdge: View {
    let top: Bool
    let bottom: Bool
    let leading: Bool
    let trailing: Bool
    let colour: Color
    /// Dash lengths; empty is a solid line. A copied block draws dashed.
    var dash: [CGFloat] = []

    var body: some View {
        GeometryReader { geo in
            Path { line in
                let w = geo.size.width, h = geo.size.height
                if top { line.move(to: .zero); line.addLine(to: CGPoint(x: w, y: 0)) }
                if bottom { line.move(to: CGPoint(x: 0, y: h)); line.addLine(to: CGPoint(x: w, y: h)) }
                if leading { line.move(to: .zero); line.addLine(to: CGPoint(x: 0, y: h)) }
                if trailing { line.move(to: CGPoint(x: w, y: 0)); line.addLine(to: CGPoint(x: w, y: h)) }
            }
            .stroke(colour, style: StrokeStyle(lineWidth: 2, dash: dash))
        }
    }
}

/// **Which scene to send the held shots to.**
///
/// It was a flat menu of every scene, and he saw the problem before it bit:
/// "if there's hundreds of scenes in a film, that list is going to get insane."
/// A menu cannot be searched, so a menu is the wrong shape for a list that
/// grows with the film. This is a small sheet that can be: type and the list
/// narrows, ⏎ takes the first one left.
struct MoveShots: View {
    @ObservedObject var state: ShellState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var looking = ""
    private var dark: Bool { scheme == .dark }

    private var scenes: [ViewModel.Scene] {
        let live = (state.view?.scenes ?? []).filter { !$0.archived }
        let q = looking.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return live }
        return live.filter {
            $0.number.lowercased().contains(q) || $0.heading.lowercased().contains(q)
        }
    }

    private var held: [ViewModel.Row] {
        (state.view?.allRows ?? []).filter { state.wholeShots.contains($0.id) }
    }

    var body: some View {
        Sheet(title: held.count == 1 ? "Move 1 Shot" : "Move \(held.count) Shots",
              width: .narrow, height: 420, scrolls: false) {
            VStack(spacing: 0) {
            SearchField(placeholder: "Find a scene", text: $looking)
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
            List {
                ForEach(scenes) { sc in
                    Button { move(to: sc.id) } label: {
                        HStack(spacing: 8) {
                            Text(sc.number).sans(Brand.Size.small, weight: .semibold)
                                .monospacedDigit()
                                .foregroundStyle(Brand.ink(dark))
                                .frame(minWidth: 26, alignment: .trailing)
                            Text(sc.heading).sans(Brand.Size.small)
                                .foregroundStyle(Brand.ink2(dark)).lineLimit(1)
                            Spacer(minLength: 0)
                            Text("\(sc.count)").sans(Brand.Size.tiny).monospacedDigit()
                                .foregroundStyle(Brand.ink4(dark))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            }
        } trailing: {
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Move") { if let first = scenes.first { move(to: first.id) } }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .disabled(scenes.isEmpty)
        }
    }

    /// The same landing arithmetic the drag uses — a run, in script order, at
    /// the foot of the scene it is sent to.
    private func move(to scene: String) {
        guard let engine = state.engine else { return }
        for shot in held {
            if shot.sceneId != scene {
                state.replace(engine.movePlacement(shot.id, toScene: scene))
            }
            state.replace(engine.reorder(placement: shot.id, to: Int.max))
        }
        dismiss()
    }
}


// ------------------------------------------------------- the pop-out's chrome

/// **The bar every pop-out wears**, so three windows read as one app.
///
/// His ask, 2026-08-28: *"I want all the pop out windows in the app (viewing
/// pictures, 3d scans, videos) to have the same visual identity with different
/// buttons and functions depending on what they need to do."*
///
/// What was there instead: three copies of nearly this, drifted. Bars 44, 52
/// and 44 points tall; 68, 74 and 68 points of room for the traffic lights;
/// one with no fill and no hairline at all; and only two of the three claiming
/// the drag, so the scan window's drawn bar could not move its own window.
///
/// **Only the buttons differ, and they differ because the job does.** A picture
/// gets zoom; a clip gets trim and set-the-still; a shot's frames get a star
/// and a strip; a room gets its 3D-or-plan switch. The bar itself is not a
/// decision any of them gets to make.
struct PopoutBar<Buttons: View>: View {
    let title: String
    /// "3 of 12", when the thing was opened from a set.
    var count: String? = nil
    /// What was written under it on the wall, carried across.
    var caption: String = ""
    /// **No band, no rule — the title sits straight on the window.**
    ///
    /// His note, 2026-09-02, twice: the bar is ugly. It is the one full-width
    /// solid surface in a window otherwise made of floating things, so it cuts
    /// the window in half. Plain keeps everything that matters — the room for
    /// the traffic lights, the height, and the drag — and paints nothing.
    ///
    /// Offered rather than imposed: the viewer, the frames window and the scan
    /// window still wear the band, and whether they should is the question
    /// `design/14-popouts.html` puts to him.
    var plain: Bool = false
    @ViewBuilder var buttons: () -> Buttons

    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        HStack(spacing: 8) {
            // Room for the traffic lights, which are the system's to draw.
            // Anything that lands under them is unreachable.
            Color.clear.frame(width: 68, height: 1)
            // **The name, in the title bar, top-left** — the number split
            // from the name so "34A · Milo French Over" reads as a number
            // and a name rather than one bold line. 2026-09-14.
            let parts = (title.isEmpty ? "File" : title).components(separatedBy: " · ")
            Text(parts[0])
                .sans(Brand.Size.title, weight: .semibold).monospacedDigit()
                .foregroundStyle(Brand.ink(dark))
                .lineLimit(1).truncationMode(.middle)
            if parts.count > 1 {
                Text(parts.dropFirst().joined(separator: " · "))
                    .sans(Brand.Size.title)
                    .foregroundStyle(Brand.ink2(dark))
                    .lineLimit(1).truncationMode(.middle)
            }
            // The count is about *this window*; the caption is about the
            // picture — so the count comes first.
            if let count, !count.isEmpty {
                Text(count).sans(Brand.Size.small).monospacedDigit()
                    .foregroundStyle(Brand.ink3(dark))
            }
            if !caption.isEmpty {
                Text(caption)
                    .sans(11)
                    .foregroundStyle(Brand.ink3(dark))
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 8)
            buttons()
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(plain ? Color.clear : Brand.surface2(dark))
        // **Where a drag moves the window.** These windows have no title bar,
        // and `isMovableByWindowBackground` beats every gesture underneath it:
        // AppKit decides a mouse-down moves the window before asking whether
        // SwiftUI wanted it, so a clip's scrubber and the trim handles lost
        // that race every time. Only this strip may move the window.
        .background(WindowDragArea())
        .hairline(.bottom, plain ? .clear : Brand.rule(dark))
    }
}

/// **`ToolButton` with a menu behind it**, so "more" is the same button as its
/// neighbours in every pop-out.
///
/// It was `ellipsis.circle` borderless at width 38 in one window, `ellipsis` in
/// a filled circle at 28 in the next, and `square.and.arrow.up` borderless at
/// 34 in the third. A `.borderlessButton` menu also keeps its label's words and
/// throws away its background *and its size* — three faults so far — so this
/// wears `.menuStyle(.button)` with the frame on the label, which is the shape
/// that survives.
struct ToolMenu<Content: View>: View {
    var icon: String = "ellipsis"
    var size: CGFloat = 13
    var help: String = ""
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        Menu {
            content()
        } label: {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(Brand.ink2(dark))
                .frame(width: Brand.barHeight, height: Brand.barHeight)
                .overlay {
                    Capsule(style: .continuous).strokeBorder(Brand.rule2(dark), lineWidth: 1)
                }
                .contentShape(Capsule(style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .focusEffectDisabled()
        .fixedSize()
        .help(help)
    }
}


/// **Keeps a scroll inside the list it started in.**
///
/// His report: scrolling an open dropdown to the end of its options and not
/// stopping the finger in time scrolls the table behind it, which takes the
/// dropdown away with it. *"Ideal behaviour is scroll would be isolated to the
/// dropdown when the dropdown is open."*
///
/// AppKit hands the leftovers on by design, and the table's scroll view is the
/// one that gets them. The first answer to this was a silent responder slipped
/// in behind the list's scroll view — and he reported the same leak again on
/// 2026-09-30: AppKit passes a nested scroll view's leftovers to the enclosing
/// one directly, not along the responder chain, so the silent responder never
/// heard them. Now the event is stopped *before* anything sees it: a local
/// monitor drops a scroll that is over the list and pushing past its end.
///
/// **Nothing about the scrolling itself is reimplemented**, which is the point.
/// Momentum, rubber-band and precise trackpad deltas stay AppKit's; a
/// hand-rolled `scrollWheel` moving the clip view by hand is how a list starts
/// feeling wrong.
///
/// **And the class is left alone.** The first version of this swapped the
/// scroll view's class with `object_setClass`, which is the trick that shows up
/// first when you look for this. It crashed the app on the next layout pass:
/// SwiftUI's scroll view is its own subclass with its own ivars and its own
/// notification observers, and replacing the class throws all of that away —
/// the frame-change notification then calls a method that no longer exists.
/// Trapped in a build that had already been installed. Interpose, never
/// replace.
///
/// Put it in the *content* of the scroll view, never beside it, or there is no
/// enclosing scroll view to find.
struct ListScroll: NSViewRepresentable {
    /// **Every scroll over the list moves the list** — not only the ones
    /// pushing past its end. The document page's lists hang over the page
    /// inside SwiftUI's own containers, and a real trackpad swipe there was
    /// routed to the page: his report, 2026-09-30, *"page moves instead."*
    /// Steered, the window's routing is never asked (`Anchor.move`).
    var steer = false

    final class Anchor: NSView {
        /// The list open now, for the `--wheel` check to ask.
        static weak var open: Anchor?
        private weak var held: NSScrollView?
        private var monitor: Any?
        var steering = false

        /// **At the end of the list, the scroll stops here.** Whatever the
        /// wheel or trackpad sends while the pointer is over the list and the
        /// list cannot go further that way is dropped before AppKit sees it,
        /// so there are no leftovers to hand the table. Anywhere else, and in
        /// every direction the list can still go, the event is untouched.
        func swallows(_ event: NSEvent, at point: NSPoint) -> Bool {
            guard let scroll = held, let doc = scroll.documentView else { return false }
            // The check's control run: the table as it was without this.
            if ProcessInfo.processInfo.environment["LISTSCROLL_OFF"] != nil { return false }
            let at = scroll.convert(point, from: nil)
            guard scroll.bounds.contains(at) else { return false }
            let dy = event.scrollingDeltaY
            // Sideways over the list would slide the table; the list has no
            // sideways to give. A pure phase event carries no motion — let it by.
            if dy == 0 { return event.scrollingDeltaX != 0 }
            let clip = scroll.contentView.bounds
            let room = max(doc.frame.height - clip.height, 0)
            let fromTop = doc.isFlipped ? clip.origin.y : room - clip.origin.y
            let atTop = fromTop <= 0.5
            let atFoot = fromTop >= room - 0.5
            // A positive delta asks for what is above.
            return dy > 0 ? atTop : atFoot
        }

        func step(in scroll: NSScrollView) {
            held = scroll
            Self.open = self
            if ProcessInfo.processInfo.environment["LISTSCROLL_PROBE"] != nil {
                FileHandle.standardError.write(Data(
                    "listscroll: \(type(of: scroll)) \(scroll.frame.size) doc \(scroll.documentView?.frame.size ?? .zero)\n".utf8))
            }
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                // A check's made-up swipe belongs to no window; see `PageKeys.swipe`.
                guard let self, let scroll = self.held,
                      event.window === scroll.window
                        || (event.window == nil && PageKeys.driving) else { return event }
                if self.steering,
                   scroll.bounds.contains(scroll.convert(event.locationInWindow, from: nil)) {
                    self.move(by: event)
                    return nil
                }
                return self.swallows(event, at: event.locationInWindow) ? nil : event
            }
        }

        /// **The list moved by hand, by exactly what the swipe asked.** Not
        /// `scrollWheel(with:)`: handing a swipe to SwiftUI's own scroll view
        /// is asking it to route the swipe again, and the routing is what sent
        /// it to the page. Momentum still arrives as more swipes, so a flick
        /// still coasts; the ends hold, with no bounce to leak past them.
        func move(by event: NSEvent) {
            guard let scroll = held, let doc = scroll.documentView else { return }
            var dy = event.scrollingDeltaY
            // A wheel that clicks says lines, not points.
            if !event.hasPreciseScrollingDeltas { dy *= 12 }
            guard dy != 0 else { return }
            let clip = scroll.contentView
            let room = max(doc.frame.height - clip.bounds.height, 0)
            var origin = clip.bounds.origin
            // A positive delta asks for what is above.
            origin.y = doc.isFlipped
                ? min(max(origin.y - dy, 0), room)
                : min(max(origin.y + dy, 0), room)
            guard origin != clip.bounds.origin else { return }
            clip.scroll(to: origin)
            scroll.reflectScrolledClipView(clip)
        }

        func standDown() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            held = nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { standDown(); return }
            // A pass later: the enclosing scroll view is not in place yet at
            // the moment the view is added.
            DispatchQueue.main.async { [weak self] in
                guard let self, let scroll = self.enclosingScrollView else { return }
                self.step(in: scroll)
            }
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }

    func makeNSView(context: Context) -> Anchor {
        let anchor = Anchor(frame: .zero)
        anchor.steering = steer
        return anchor
    }
    func updateNSView(_ view: Anchor, context: Context) { view.steering = steer }
}
