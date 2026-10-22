import SwiftUI

/// Narrowing the list, and saying so.
///
/// The whole script is one table now, which is what makes this worth having:
/// "every handheld shot in the film", "everything on Day 2", "the drive
/// sequence" — questions that could not be asked while the table showed one
/// scene. The engine has done the work all along (`filter`, `facet`, `sort`);
/// this is the chrome for it.
///
/// **Rebuilt 2026-08-19 on his verdict — "the filter area is especially ugly,
/// tight and jam packed".** It was: a search box and every facet the project
/// had, all shoulder to shoulder in a 34-point strip, so a project with eight
/// choice columns wore eight dropdowns whether or not any of them was in use.
/// Now there are two controls and nothing else at rest — **Filter** and
/// **Sort** — and what is actually *on* shows as a chip you can take off. The
/// bar grows with the work instead of announcing everything it could do.
///
/// Two rules it keeps:
///
/// - **A narrowed list always says it is narrowed.** A filter left on is how
///   a person concludes that half their shots have vanished. The chips say
///   what is on, the count says what it costs, and one click clears it.
/// - **Nothing here is stored in the document.** What you are looking at is
///   not a fact about the film, so it lives in the session and dies with it.
struct FilterBar: View {
    @ObservedObject var state: ShellState
    @Environment(\.colorScheme) private var scheme
    @State private var searchOpen = false
    @FocusState private var searchTyping: Bool
    @State private var searchHadFocus = false

    private var dark: Bool { scheme == .dark }
    private var filter: ViewModel.Filter? { state.view?.filter }

    /// The columns worth narrowing by: the ones that hold a value off a
    /// list, plus the project's own choice columns.
    private var facetable: [String] {
        (state.view?.columns ?? [])
            .filter { $0.visible && Columns.isVocabulary($0.name) }
            .map(\.name)
    }

    private var active: [(field: String, icon: String, label: String)] {
        Self.chips(state)
    }

    /// Everything currently narrowing the list, as one flat list — so the
    /// chips can be drawn without knowing which kind of thing each one is.
    ///
    /// **Static, and handed the state**, so a checking run can print the exact
    /// words the chips draw rather than an instrument's guess at them. Ref 301
    /// was a chip printing an id, and no report could see it: every one of
    /// them prints the *value* being narrowed by, which is the id, and is
    /// correct.
    static func chips(_ state: ShellState) -> [(field: String, icon: String, label: String)] {
        var out: [(String, String, String)] = []
        for (field, value) in state.facets.sorted(by: { $0.key < $1.key })
        where !value.isEmpty {
            switch field {
            case "day":
                out.append((field, "calendar", dayLabel(value, state) ?? value))
            case "sequence":
                let title = state.view?.sequences.first { $0.id == value }?.title
                out.append((field, "square.stack", title ?? value))
            // A scene narrowing wears the scene's own icon, so a glance at the
            // chips says which of the two kinds just shortened the list —
            // which is the whole point of splitting the controls up.
            //
            // **Read off the sidebar's own list rather than repeated here.**
            // This switch used to name the six scene fields itself, and when a
            // seventh — the location *record* — was added to the menu it was
            // added in one place only. The chip fell through to `default` and
            // printed the raw value, which for that field is an id: his
            // report, "filter by location shows up as a hash of numbers and
            // letters".
            default:
                if let facet = Sidebar.sceneFacets.first(where: { $0.field == field }) {
                    out.append((field, facet.icon, shown(field, value, state)))
                } else {
                    out.append((field, Columns.icon(field), value))
                }
            }
        }
        return out.map { (field: $0.0, icon: $0.1, label: $0.2) }
    }

    /// What a value is called, for the one field where the value narrowed by
    /// and the words on screen are not the same thing. A location is held as
    /// an id so that renaming the place does not strand the filter; the chip
    /// has to say the name back — the house's and the room's both, per Ref 269
    /// — because the id says nothing to anybody.
    static func shown(_ field: String, _ value: String, _ state: ShellState) -> String {
        guard field == "location_id" else { return value }
        guard let place = state.view?.locations.first(where: { $0.id == value })
        else { return "Location" }
        return place.fullName.isEmpty ? place.name : place.fullName
    }

    /// What a field is called. The scene fields are the sidebar's to name —
    /// `location_id` has no column behind it, so asking `Columns` produces
    /// "Location_id".
    static func fieldLabel(_ field: String) -> String {
        Sidebar.sceneFacets.first { $0.field == field }?.label
            ?? Columns.label(field)
    }

    var body: some View {
        HStack(spacing: 10) {
            // **The views ride in this bar rather than in one of their own.**
            //
            // When the mode switcher took the top bar on 2026-08-23, the views
            // had to land somewhere, and the drawing put them on a strip above
            // the table. A strip above the table is what this bar already is —
            // giving them a second one would have stacked three pieces of
            // furniture over the list, which is exactly the "visually messy"
            // he cut once already. So they sit at its head, and the shot list
            // still has one bar, the same as it had yesterday.
            // **`fixedSize`, or it is the first thing crushed.** In a narrow
            // window this bar runs out of room, and SwiftUI takes that room
            // from whatever will give — which was the views: at 1016 points
            // the word *Views* stood beside a blank white lozenge with
            // Storyboard and Document squeezed out of existence entirely. It
            // built, it ran, and only a photograph of it showed anything wrong.
            // The search box gives ground instead; a shorter search box is
            // still a search box.
            ViewBar(selection: $state.tab)
                // **Priority, not `fixedSize`** — and the difference is the
                // width of the window itself.
                //
                // `fixedSize` was the first answer and it worked: the views
                // stopped being crushed. It also made them *immovable*, and an
                // immovable thing in this bar sets the smallest the whole
                // window may be. The floor went from 1015 points to 1087, and
                // the table could no longer give its last spread back in a
                // narrow window — one check saw it and nothing else could.
                //
                // A priority says the same thing about ordinary widths (the
                // search box gives ground first, and does so long before these
                // pills are touched) without claiming the views may never
                // shrink at all.
                .layoutPriority(1)
            groupRule

            search
            filterMenu
            sortMenu

            // What is on, one chip each, each with its own way off. This is
            // the whole reason the dropdowns could go: a filter that is not
            // in force does not need to be on screen.
            ForEach(active, id: \.field) { one in
                Button {
                    narrow(one.field, "")
                } label: {
                    HStack(spacing: 6) {
                        Text(one.label).sans(11, weight: .medium).lineLimit(1)
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                            .opacity(0.6)
                    }
                    .foregroundStyle(Brand.accent(dark))
                    .padding(.horizontal, Brand.barPadding)
                    .frame(height: Brand.barHeight)
                    .barPill(dark, on: true)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help("Clear \(Self.fieldLabel(one.field).lowercased())")
            }

            if filter?.hideStruck == true {
                Button {
                    state.replace(state.engine?.filter(text: filter?.text ?? "",
                                                       hideStruck: false))
                } label: {
                    HStack(spacing: 6) {
                        Text("Shot hidden").sans(11, weight: .medium)
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                            .opacity(0.6)
                    }
                    .foregroundStyle(Brand.accent(dark))
                    .padding(.horizontal, Brand.barPadding)
                    .frame(height: Brand.barHeight)
                    .barPill(dark, on: true)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
            }

            Spacer(minLength: 0)

            // What it costs you to have this on — said plainly, always.
            if filter?.narrowed == true {
                Text(hiding).sans(11, weight: .medium)
                    .foregroundStyle(Brand.ink2(dark))
                Button("Clear") {
                    state.facets.removeAll()
                    state.replace(state.engine?.facet("all", ""))
                }
                .buttonStyle(.plain)
                .sans(11, weight: .semibold)
                .foregroundStyle(Brand.accent(dark))
                .focusEffectDisabled()
            }
            // **The zoom, where he drew it** — the right-hand end of this bar,
            // and also Settings ▸ General ▸ Text Size (his call, 2026-10-15:
            // "put the text-size slider back in the shot list bar as well as
            // Settings"). One stored value (`tableDensity`); both controls
            // follow `state.columnBump`, so moving either moves the other.
            // **Columns beside it** (his call, 2026-10-16: he adjusts columns
            // often). Same sheet as Settings ▸ Columns, which keeps its own.
            groupRule
            zoom
            Button { state.editingColumns = true } label: {
                barLabel("tablecells", "Columns", on: false)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help("Edit columns")
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        // **No slab.** This was `surface2` with a hairline under it for one
        // day, put there because in daylight the old wells were white at 74%
        // on a white ground and could not be seen at all. It fixed that and
        // bought a worse thing: *"the toolbar creates a really ugly rectangle
        // and ruins the glassy feeling of the sidebars and the page."* He is
        // right — the window's rule is that the ground is continuous and only
        // things that *float* have edges, and a chrome-coloured band cut across
        // the top of the well is the opposite of that.
        //
        // So the ground is the ground again, and the daylight problem is solved
        // where it belonged: on the controls. `Brand.band` exists for exactly
        // this — its own comment says it "has to read as a band in daylight
        // too, where a translucent white on white reads as nothing at all."
        .background(Brand.surface(dark))
    }

    /// The line that separates one group of controls in this bar from the next.
    private var groupRule: some View {
        Brand.rule2(dark).frame(width: 1, height: 22)
    }

    /// Four sizes, not a free slider: the steps ⌘+ and ⌘− already walk, so the
    /// slider and the keys cannot disagree about where they are.
    private var zoom: some View {
        SizeSlider(small: "textformat.size.smaller", large: "textformat.size.larger") {
            Slider(
                value: Binding(
                    get: {
                        Double(Brand.comfortable.firstIndex {
                            abs($0 - Brand.density) < 0.01
                        } ?? 1)
                    },
                    set: { step in
                        let at = Int(step.rounded())
                        guard Brand.comfortable.indices.contains(at) else { return }
                        TextSize.set(Brand.comfortable[at], state)
                    }
                ),
                in: 0...Double(Brand.comfortable.count - 1), step: 1
            )
        }
        .help("Zoom — ⌘+ and ⌘−")
    }

    private var hiding: String {
        let shown = filter?.shown ?? 0
        let scenes = filter?.hiddenScenes ?? 0
        if scenes > 0 {
            return "\(shown) shots · \(scenes) scene\(scenes == 1 ? "" : "s") hidden"
        }
        return "\(shown) shots"
    }

    /// **A circle until you want it.** His note: *"Find in shots is way too
    /// prominent — it could just be a circle pill that when clicked expands out
    /// horizontally to accommodate text."*
    ///
    /// Right on both counts: it was the loudest thing in the bar and it is the
    /// control he reaches for least. It opens on a click and shuts again when it
    /// loses focus with nothing typed in it — **but never while it is holding a
    /// search**, because a narrowing you cannot see is what makes a list lie to
    /// you. Holding one, it stays open, showing it, with a way off on the right.
    private var search: some View {
        Group {
            if searchWanted {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11))
                        .foregroundStyle(Brand.ink2(dark))
                    TextField("Find in shots", text: Binding(
                        get: { filter?.text ?? "" },
                        set: { text in
                            state.replace(state.engine?.filter(
                                text: text, hideStruck: filter?.hideStruck ?? false))
                        }
                    ))
                    .textFieldStyle(.plain)
                    .sans(13)
                    .focused($searchTyping)
                    .frame(minWidth: 62, idealWidth: 168, maxWidth: 220)
                    if !(filter?.text ?? "").isEmpty {
                        Button {
                            state.replace(state.engine?.filter(
                                text: "", hideStruck: filter?.hideStruck ?? false))
                            searchOpen = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Brand.ink3(dark))
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                        .help("Clear the search")
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: Brand.barHeight)
            } else {
                // **A real `Button`, not an `onTapGesture`.** The gesture read
                // fine and never opened: a synthetic click — which is how this
                // app is checked, and how half its bugs are found — does not
                // reliably reach a tap gesture hung on a background. A button
                // is a button to everything.
                Button {
                    searchOpen = true
                    searchTyping = true
                } label: {
                    Image(systemName: "magnifyingglass").font(.system(size: 11))
                        .foregroundStyle(Brand.ink2(dark))
                        .frame(width: Brand.barHeight, height: Brand.barHeight)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
            }
        }
        .barPill(dark, on: false)
        .animation(.easeOut(duration: 0.18), value: searchWanted)
        .onChange(of: searchTyping) { _, typing in
            // **Only ever shut on a focus it actually had.** Set on the way in,
            // cleared on the way out. Without the latch the field opened and
            // shut in the same breath: the text field cannot take focus in the
            // frame it is created, so `searchTyping` resolved false, this fired,
            // and it collapsed before anybody could type a letter.
            if typing { searchHadFocus = true; return }
            guard searchHadFocus, (filter?.text ?? "").isEmpty else { return }
            searchHadFocus = false
            searchOpen = false
        }
        .help("Find in shots")
    }


    private var searchWanted: Bool { searchOpen || !(filter?.text ?? "").isEmpty }


    /// **One button instead of eight.** Every way of narrowing the list, as
    /// submenus — so the bar stays the same size whether the project has two
    /// choice columns or twenty.

    /// Sorting, the same shape: a button that says what is on when something
    /// is, and the project's own order when nothing is.
    /// **Back beside Sort**, his call, after a detour to the sidebar: "Filter
    /// shots should be where it was before, next to Sort, and then just Filter
    /// scenes should be down on the left sidebar." Shots are what this bar
    /// narrows; the scene half lives with the scene list.
    private var filterMenu: some View {
        Menu {
            ForEach(facetable, id: \.self) { field in
                Menu(Columns.label(field)) {
                    Button("Any \(Columns.label(field))") { narrow(field, "") }
                    Divider()
                    ForEach(Columns.options(field, state: state), id: \.self) { value in
                        Button {
                            narrow(field, value == (state.facets[field] ?? "") ? "" : value)
                        } label: {
                            if value == state.facets[field] {
                                Label(value, systemImage: "checkmark")
                            } else {
                                Text(value)
                            }
                        }
                    }
                }
            }
            Divider()
            Button {
                state.replace(state.engine?.filter(text: filter?.text ?? "",
                                                   hideStruck: !(filter?.hideStruck ?? false)))
            } label: {
                if filter?.hideStruck == true {
                    Label("Hide Shot", systemImage: "checkmark")
                } else {
                    Text("Hide Shot")
                }
            }
            if filter?.narrowed == true {
                Divider()
                Button("Show everything") {
                    state.facets.removeAll()
                    state.replace(state.engine?.facet("all", ""))
                }
            }
        } label: {
            barFace("line.3.horizontal.decrease", "Filter", on: filter?.narrowed == true)
        }
        // **`.button` and a plain button, so `barFace` is drawn as written.**
        // A `.borderlessButton` menu hands its label to AppKit, which throws
        // away the font and the ink and draws the system control's instead —
        // so *Filter* and *Sort* came out semibold white whatever their state,
        // beside *Storyboard* and *Document*, correctly grey and regular, four
        // pills along. It also meant that turning a filter on, which is meant
        // to make the word white on accent, changed nothing about the word.
        //
        // It threw away the label's *padding* too, which is why this used to
        // apply a second copy of it out here — three goes at widening these
        // inside `barFace` changed nothing, and he said so twice: *"the pill
        // doesnt look wider at all"*. `barFace`'s own padding lands now, so
        // the second copy is gone and only the pill stays outside.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .focusEffectDisabled()
        .fixedSize()
        .barPill(dark, on: filter?.narrowed == true)
        .help("Narrow the list")
    }

    private var sortMenu: some View {
        let shooting = state.shootingOrder
        let sorted = shooting ? "" : (filter?.sortColumn ?? "")
        let down = filter?.sortDescending == true
        return Menu {
            Button {
                state.replace(state.engine?.sortBy("", descending: false))
            } label: {
                if sorted.isEmpty && !shooting {
                    Label("The script’s own order", systemImage: "checkmark")
                } else {
                    Text("The script’s own order")
                }
            }
            // **The order they are shot in** (2026-10-06): by day, each
            // day's shots as the Schedule arranged them. A drag here moves a
            // shot in the shooting order and never renumbers it.
            Button {
                state.replace(state.engine?.sortBy("shootingorder", descending: false))
            } label: {
                if shooting {
                    Label("Shooting Order", systemImage: "checkmark")
                } else {
                    Text("Shooting Order")
                }
            }
            Divider()
            ForEach((state.view?.columns ?? []).filter(\.visible), id: \.name) { column in
                Button {
                    // Picking the column you are already sorted by turns it
                    // round, which is what a table header does.
                    state.replace(state.engine?.sortBy(
                        column.name,
                        descending: sorted == column.name ? !down : false))
                } label: {
                    if sorted == column.name {
                        Label(Columns.label(column.name),
                              systemImage: down ? "arrow.down" : "arrow.up")
                    } else {
                        Text(Columns.label(column.name))
                    }
                }
            }
        } label: {
            barFace(shooting ? "calendar"
                        : sorted.isEmpty ? "arrow.up.arrow.down"
                                         : (down ? "arrow.down" : "arrow.up"),
                    shooting ? "Shooting Order" : sorted.isEmpty ? "Sort" : Columns.label(sorted),
                    on: shooting || !sorted.isEmpty)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .focusEffectDisabled()
        .fixedSize()
        .barPill(dark, on: shooting || !sorted.isEmpty)   // see `filterMenu`
        .help("Sort the list")
    }

    /// The face of a control in this bar — glyph, word, and nothing behind it.
    ///
    /// **Split from `barLabel` because a `Menu` throws the background away.**
    /// Filter, Sort and Columns were all written the same way and called the
    /// same helper, and only Columns came out looking like a button: a
    /// `.borderlessButton` menu draws its label's *content* and drops what the
    /// label puts behind it. So the two controls he reaches for most looked
    /// like captions while the one he reaches for least looked like a button.
    /// The well goes on the `Menu` now, outside the label, where it survives.
    private func barFace(_ icon: String, _ text: String, on: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11))
            Text(text).sans(13, weight: on ? .semibold : .regular)
        }
        // In force is the film's tint and the film's colour — see `barPill`.
        .foregroundStyle(on ? Brand.accent(dark) : Brand.ink2(dark))
        // **A box, not a sleeve.** Padding alone gave these a capsule 15 points
        // tall around 12-point words — the arrows and the S of *Sort* running
        // into the ends of it, which is what he meant by *"too small for the
        // words inside"*.
        // **This padding only ever reached `barLabel`** — the Columns button,
        // which is a plain `Menu` label and keeps what is put around it. Filter
        // and Sort throw it away; theirs is applied outside the `Menu`, and
        // changing the number here does nothing to them. Learned the slow way.
        //
        // His note, 2026-09-04, with a picture of
        // Filter and Sort: *"more even spacing on all sides and dont look
        // almost cropped. I loved the pills that we used for 'views'."*
        //
        // The number was not the whole story — the *shape* was. These sit in a
        // `Capsule`, whose ends curve away with a radius of half the height, so
        // at 27 points tall the last 13 of the padding is curve rather than
        // room: the arrow of ↑↓ and the t of *Sort* were measuring their gap
        // against a wall that was not there. The views pills he likes are the
        // same shape but shorter, so their curve is gentler and the same
        // padding reads as air.
        //
        // **Every acting control in this bar is `Brand.barHeight`**, which is
        // the views pills' own height — see the note there. It was 27 here and
        // 24 on the views, and 10 points of padding against their 11.
        .padding(.horizontal, Brand.barPadding)
        .frame(height: Brand.barHeight)
    }

    private func barLabel(_ icon: String, _ text: String, on: Bool) -> some View {
        barFace(icon, text, on: on).barPill(dark, on: on)
    }

    private static func dayLabel(_ id: String, _ state: ShellState) -> String? {
        if id == "none" { return "Not scheduled" }
        return state.view?.days.first { $0.id == id }?.label
    }

    /// The engine holds the narrowing; the shell keeps a copy only so the
    /// chips can show which value is in force (the view model reports *that*
    /// something is narrowing, not which value).
    private func narrow(_ field: String, _ value: String) {
        if value.isEmpty { state.facets.removeValue(forKey: field) }
        else { state.facets[field] = value }
        state.replace(state.engine?.facet(field, value))
    }
}
