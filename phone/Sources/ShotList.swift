import SwiftUI

/// The shot list, arranged the way Cadrage arranges it: scenes are the index,
/// and a scene is what you open.
///
/// A phone standing in a room is answering "what am I doing *here*", and here is
/// a scene. One flat list of every shot in the film is the Mac's job.
struct ShotListView: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    @State private var removing: Engine.Scene?
    /// **Editing** (Ref 1615). Plain state, never stored: the app always
    /// opens in Display, so it is never found in Editing at call time.
    @State private var editing = false
    /// Which shot Editing starts at: the one whose Edit was tapped.
    @State private var editingFrom: Engine.Row.ID?

    var body: some View {
        Group {
            if session.shownScenes.isEmpty {
                ContentUnavailableView {
                    Label(session.narrowed ? "Nothing matches" : "No scenes yet",
                          systemImage: "list.bullet.rectangle")
                } actions: {
                    if session.narrowed {
                        Button("Show Everything") { session.clearNarrowing() }
                    }
                }
            } else if session.shootingOrder {
                ShootingOrderList()
            } else if editing {
                EditingShotList(start: editingFrom)
            } else {
                // The whole film in one scroll, presented the way the portal
                // presents it (Ref 1541). A filter that hides shots still says so.
                VStack(spacing: 0) {
                    if session.narrowed || session.sorted {
                        NarrowedBanner()
                    }
                    FilmShotList(removing: $removing, editing: $editing, editingFrom: $editingFrom)
                }
            }
        }
        // **An old version on screen says so**, above everything (Versions).
        .safeAreaInset(edge: .top, spacing: 0) {
            if let version = session.looking { LookingBanner(version: version) }
        }
        // Nothing can be edited in the past; Editing closes rather than
        // offering fields the engine will refuse.
        .onChange(of: session.looking) { _, now in if now != nil { editing = false } }
        .leadingTitle(session.shootingOrder ? "Shooting Order" : "Shot List")
        .searchable(text: $session.search, prompt: "Find a scene or a shot")
        // **Search folds into a button** until it is wanted: the mockup's
        // list starts straight under its List | Storyboard switch.
        .searchFolded()
        .toolbar {
            if editing {
                // **Done in the film's colour**, where the tools were. With
                // the tab bar gone it is the only way out, on purpose.
                ToolbarItem(placement: .primaryAction) {
                    Button { withAnimation(.snappy) { editing = false } } label: {
                        Text("Done").foregroundStyle(.white)
                    }
                        .buttonStyle(.borderedProminent)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("editing.done")
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Button { adding = true } label: { Label("Add Scene", systemImage: "plus") }
                }
            }
        }
        .toolbar(editing ? .hidden : .automatic, for: .tabBar)
        .confirmationDialog("Delete \(removing.map { session.isCommercial && !$0.title.isEmpty ? $0.title : "scene \($0.number)" } ?? "")",
                            isPresented: Binding(get: { removing != nil },
                                                 set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let scene = removing { session.deleteScene(scene) }
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: {
            // What a delete will cost, which the copy law keeps a sentence for.
            let shots = session.rows(inScene: removing?.id ?? "").count
            Text(shots == 0
                 ? "Nothing else goes with it."
                 : "\(shots) shot\(shots == 1 ? "" : "s") go with it.")
        }
        .sheet(isPresented: $adding) {
            AddSceneSheet().environmentObject(session)
        }
        // **One mechanism, not two.** A stack driven partly by a bound item and
        // partly by link values does not push the values: the item-based
        // presentation takes the stack over, and every deeper link goes quietly
        // nowhere. Everything here is a value.
        .navigationDestination(for: Engine.Scene.self) { scene in
            SceneShotsView(scene: scene).environmentObject(session)
        }
        .navigationDestination(for: SceneShotsView.Opening.self) { opening in
            ShotDetailView(sceneId: opening.sceneId, heading: opening.heading,
                           showing: opening.rowId)
        }
    }
}

/// **The shot list in the order it is shot** — his ask, 2026-10-06: "Once
/// it's in shooting order and I drag things around up and down, that changes
/// the shooting order, not the order of shots storywise." A section per day,
/// its shots in the order the Schedule keeps; hold a shot and drag it within
/// its day, or Move to Day from its menu. No number or letter changes.
private struct ShootingOrderList: View {
    @EnvironmentObject private var session: Session
    @AppStorage("shotlist.mode") private var mode: SceneShotsView.Mode = .list
    /// **Reorder**: every row one line with its handle, so a long day fits
    /// the screen while a shot is carried through it (the mockup's section
    /// 3, "Dragging"). A checking run starts in it with `-Reordering 1`.
    @State private var ordering: EditMode = Self.checkingReorder ? .active : .inactive

    private static var checkingReorder: Bool {
        #if targetEnvironment(simulator)
        return UserDefaults.standard.bool(forKey: "Reordering")
        #else
        return false
        #endif
    }

    var body: some View {
        Group {
            if mode == .list { list } else { storyboard }
        }
        .background(Style.page)
        .safeAreaInset(edge: .top, spacing: 0) {
            ModeBar(mode: $mode) {
                if mode == .list {
                    GlassPillButton(ordering.isEditing ? "Done" : "Reorder") {
                        withAnimation(.snappy(duration: 0.25)) {
                            ordering = ordering.isEditing ? .inactive : .active
                        }
                    }
                }
            }
        }
        .onChange(of: mode) { _, _ in ordering = .inactive }
    }

    /// The list keeps the drag, which only a List gives: rows are the portal's
    /// rich shots, bands pin, and the page is the grouped grey.
    private var list: some View {
        List {
            if session.narrowed { NarrowedBanner() }
            ForEach(session.orderGroups) { day in
                Section {
                    ForEach(day.rows) { row in
                        ZStack {
                            if ordering.isEditing {
                                // **One line while the order is made**: the
                                // frame, the number and title, the scene.
                                ShotLine(number: row.number,
                                         title: row.title.isEmpty ? row.description : row.title,
                                         under: sceneOf(row).map(sceneLine) ?? "",
                                         frame: row.frame, struck: row.struck)
                                    .padding(.leading, 10)
                            } else {
                                PresentedShot(row: row, scene: sceneOf(row))
                                // The link without its arrow: the row is the card.
                                NavigationLink(value: opening(row)) { EmptyView() }.opacity(0)
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Style.card)
                        .contextMenu { moveMenu(row, day: day) }
                    }
                    .onMove { from, to in
                        guard let at = from.first, let key = day.key else { return }
                        let rows = day.rows
                        let before = to < rows.count ? rows[to] : nil
                        guard before?.id != rows[at].id else { return }
                        session.shoot(rows[at], day: key, before: before)
                    }
                } header: {
                    DayBand(day: day, inList: true)
                        .listRowInsets(EdgeInsets())
                        .textCase(nil)
                }
            }
        }
        // **Each day a white card on the grey page** (the mockup's
        // `.daycard`), the drag kept: an inset grouped List.
        .listStyle(.insetGrouped)
        .listSectionSpacing(6)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListHeaderHeight, 0)
        .contentMargins(.horizontal, 10, for: .scrollContent)
        .contentMargins(.top, 0, for: .scrollContent)
        .environment(\.editMode, $ordering)
    }

    /// Which scene, one small line: its number and heading, a dot between.
    private func sceneLine(_ scene: Engine.Scene) -> String {
        let name = session.isCommercial && !scene.title.isEmpty ? scene.title : scene.heading
        return name.isEmpty ? scene.number : "\(scene.number) \u{00B7} \(name)"
    }

    private var storyboard: some View {
        ScrollView {
            if session.narrowed {
                NarrowedBanner().padding(.horizontal, 18).padding(.top, 8)
            }
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(session.orderGroups) { day in
                    Section {
                        StoryboardTiles(rows: day.rows, opening: opening,
                                        menu: { row in AnyView(moveMenu(row, day: day)) })
                    } header: {
                        DayBand(day: day)
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func opening(_ row: Engine.Row) -> SceneShotsView.Opening {
        SceneShotsView.Opening(rowId: row.id, sceneId: row.sceneId ?? "",
                               heading: sceneOf(row)?.heading ?? "")
    }

    /// The row's scene, archived or not: a shot can be scheduled in a scene
    /// that has since been put away, and the day still has to say where it is.
    private func sceneOf(_ row: Engine.Row) -> Engine.Scene? {
        guard let id = row.sceneId else { return nil }
        return session.view?.scenes.first { $0.id == id }
    }

    @ViewBuilder
    private func moveMenu(_ row: Engine.Row, day: Engine.Group) -> some View {
        Menu {
            ForEach(session.pickableDays().filter { $0.id != day.key }) { other in
                Button(other.label) { session.shoot(row, day: other.id, before: nil) }
            }
            if day.key != nil {
                Button("Not Scheduled") { session.shoot(row, day: nil, before: nil) }
            }
        } label: {
            Label("Move to Day", systemImage: "calendar")
        }
    }
}

/// **A day's band**, drawn the way a scene's is: its name large, its date, its
/// count; pinned while its shots go by.
private struct DayBand: View {
    @EnvironmentObject private var session: Session
    let day: Engine.Group
    /// Inside the List the card's own margin is already there.
    var inList = false

    var body: some View {
        let date = session.days.first { $0.id == day.key }?.date ?? ""
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(day.key == nil ? "Not Scheduled" : day.label)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color(.label))
            if let when = Self.nice(date) {
                Text(when)
                    .font(.system(size: 20))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            Spacer(minLength: 4)
            Text(day.rows.count == 1 ? "1 shot" : "\(day.rows.count) shots")
                .font(.system(size: 13))
                .foregroundStyle(Style.ink3)
        }
        .padding(.horizontal, inList ? 4 : 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(inList ? Color.clear : Style.page)
    }

    static func nice(_ iso: String) -> String? {
        let read = DateFormatter()
        read.dateFormat = "yyyy-MM-dd"
        read.locale = Locale(identifier: "en_US_POSIX")
        guard let date = read.date(from: iso) else { return nil }
        let say = DateFormatter()
        say.dateFormat = "EEE, MMM d"
        return say.string(from: date)
    }
}

/// A filter that shortens a film should never be silent. The engine counts what
/// went out of sight; this says so, and offers the way back. **A sort says so
/// too**: shots are sorted inside each scene, and in a scene of two shots a
/// sort that said nothing looked like a sort that did nothing.
private struct NarrowedBanner: View {
    @EnvironmentObject private var session: Session

    var body: some View {
        if let filter = session.view?.filter {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    if session.narrowed {
                        Text(narrowedLine(filter))
                            .font(.footnote.weight(.medium))
                    }
                    if !filter.sortColumn.isEmpty {
                        Label("Sorted by \(session.sortName)",
                              systemImage: filter.sortDescending ? "arrow.down" : "arrow.up")
                            .font(session.narrowed ? .caption : .footnote.weight(.medium))
                            .foregroundStyle(session.narrowed ? Color(.secondaryLabel) : Color(.label))
                    }
                }
                Spacer()
                Button("Clear") { session.clearSortAndFilter() }
                .font(.footnote.weight(.semibold))
                .accessibilityIdentifier("sortfilter.clear")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.08))
        }
    }

    private func narrowedLine(_ filter: Engine.Filter) -> String {
        var line = "\(filter.shown) shot\(filter.shown == 1 ? "" : "s")"
        if filter.hiddenScenes > 0 {
            line += " · \(filter.hiddenScenes) scene\(filter.hiddenScenes == 1 ? "" : "s") hidden"
        }
        return line
    }
}

/// A menu row with a tick when it is the one in force.
@ViewBuilder
func tickRow(_ title: String, on: Bool, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
        if on { Label(title, systemImage: "checkmark") } else { Text(title) }
    }
}

/// **Sort By**: Script Order, Shooting Order, then every column that is on.
/// Shots are sorted inside each scene; the scenes keep the script's order.
struct SortChoices: View {
    @EnvironmentObject private var session: Session

    var body: some View {
        Section("Sort By") {
            tickRow("Script Order", on: !session.sorted) { session.clearSort() }
            // **The order they are shot in** (2026-10-06) — by day.
            tickRow("Shooting Order", on: session.shootingOrder) {
                if session.shootingOrder { session.clearSort() } else { session.sortByShootingOrder() }
            }
            ForEach(session.sortableColumns) { column in
                Button {
                    toggle(column.name)
                } label: {
                    if let mark = mark(for: column.name) {
                        Label(column.shown, systemImage: mark)
                    } else {
                        Text(column.shown)
                    }
                }
            }
        }
    }

    private func mark(for column: String) -> String? {
        guard let filter = session.view?.filter, !session.shootingOrder,
              filter.sortColumn == column else { return nil }
        return filter.sortDescending ? "arrow.down" : "arrow.up"
    }

    /// Tapping the column you are already sorted by turns it round, which is
    /// what every table everywhere does.
    private func toggle(_ column: String) {
        let filter = session.view?.filter
        let same = filter?.sortColumn == column && !session.shootingOrder
        session.sort(by: column, descending: same ? !(filter?.sortDescending ?? false) : false)
    }
}

/// **Filter**: a value off any column that keeps a list — every 35mm, every
/// shot on B camera — and Hide Shot. The Mac's Filter menu, one column to a
/// submenu.
struct FilterChoices: View {
    @EnvironmentObject private var session: Session

    var body: some View {
        Section("Filter") {
            ForEach(session.facetableColumns) { column in
                let field = Session.facetField(column.name)
                let values = session.facetOptions(field)
                if !values.isEmpty {
                    Menu {
                        Button("Any \(column.shown)") { session.facet(field, is: "") }
                        ForEach(values, id: \.value) { option in
                            let on = session.facets[field] == option.value
                            tickRow(option.label, on: on) {
                                session.facet(field, is: on ? "" : option.value)
                            }
                        }
                    } label: {
                        if let value = session.facets[field] {
                            Label("\(column.shown): \(session.facetLabel(value, in: field))",
                                  systemImage: "checkmark")
                        } else {
                            Text(column.shown)
                        }
                    }
                }
            }
            Toggle("Hide Shot", isOn: Binding(
                get: { session.hideStruck },
                set: { session.hideStruck = $0 }
            ))
        }
        // **Scenes, the Mac's scene filter** (2026-10-09): where a scene is,
        // when, inside or out, the day it is shot, its sequence. The engine
        // narrowed by these all along; only the menu was missing.
        Section("Scenes") {
            ForEach(Session.sceneFacets, id: \.field) { facet in
                let values = session.facetOptions(facet.field)
                if !values.isEmpty {
                    let label = facet.field == "sequence"
                        ? (session.view?.project.sequenceWord ?? facet.label) : facet.label
                    Menu {
                        Button("Any \(label)") { session.facet(facet.field, is: "") }
                        ForEach(values, id: \.value) { option in
                            let on = session.facets[facet.field] == option.value
                            tickRow(option.label, on: on) {
                                session.facet(facet.field, is: on ? "" : option.value)
                            }
                        }
                    } label: {
                        if let value = session.facets[facet.field] {
                            Label("\(label): \(session.facetLabel(value, in: facet.field))",
                                  systemImage: "checkmark")
                        } else {
                            Label(label, systemImage: facet.icon)
                        }
                    }
                    .accessibilityIdentifier("filter.scene.\(facet.field)")
                }
            }
        }
    }
}

extension Session {
    /// Only columns that are actually on. A sort by something nobody can see
    /// is a list that reordered itself for no visible reason. A picture has
    /// no order.
    var sortableColumns: [Engine.Column] {
        columns.filter { $0.visible && $0.shape != "media" }
    }

    /// The columns that hold a value off a list — the ones worth narrowing by.
    var facetableColumns: [Engine.Column] {
        columns.filter { $0.visible && ($0.shape == "single" || $0.shape == "multi") }
    }

    /// What a column can be narrowed to: **the values shots actually carry.**
    /// It offered the film's standing list once — every lens the kit knows —
    /// and picking one nobody had used emptied the whole list. A camera is
    /// held as the unit's id and shown by its name.
    /// **The camera column is the `unit` field** in the engine, held as the
    /// unit's id; narrowing by `camera` matched nothing at all.
    static func facetField(_ column: String) -> String {
        column == "camera" ? "unit" : column
    }

    /// The scene facts a scene can be narrowed by. **The names are the
    /// engine's exactly** (`ffi/src/lib.rs` keeps the list of scene fields;
    /// anything else is read as a shot's and narrows to nothing). Day and
    /// sequence are kept apart from the facets in the engine but take the
    /// same `facet` command.
    static let sceneFacets: [(field: String, label: String, icon: String)] = [
        ("location_id", "Location", "mappin.and.ellipse"),
        ("location", "Script Location", "text.book.closed"),
        ("shooting_location", "Filming Location", "map"),
        ("time_of_day", "Time of Day", "sun.max"),
        ("int_ext", "Interior/Exterior", "door.left.hand.open"),
        ("priority", "Priority", "flag"),
        ("pov", "Point of View", "eye"),
        ("day", "Shoot Day", "calendar"),
        ("sequence", "Sequence", "square.stack"),
    ]

    /// What a scene field actually holds across the film, never a fixed
    /// list, so a choice always leaves something. Places are narrowed by id
    /// and read by their full name (a house's Kitchen, not just Kitchen).
    private func sceneOptions(_ field: String) -> [(value: String, label: String)]? {
        let live = scenes.filter { !$0.archived }
        var seen: [String: String] = [:]
        switch field {
        case "location_id":
            for scene in live {
                for at in scene.locations {
                    guard let place = locations.first(where: { $0.id == at }) else { continue }
                    seen[at] = (place.fullName ?? "").isEmpty ? place.name : place.fullName!
                }
            }
        case "location", "shooting_location", "time_of_day", "int_ext", "priority":
            for scene in live {
                let held: String
                switch field {
                case "location": held = scene.location
                case "shooting_location": held = scene.shootingLocation
                case "time_of_day": held = scene.timeOfDay
                case "int_ext": held = scene.intExt
                default: held = scene.priority
                }
                if !held.isEmpty { seen[held] = field == "int_ext" && held.uppercased() == "INT/EXT" ? "I/E" : held }
            }
        case "pov":
            for scene in live { for who in scene.povList where !who.isEmpty { seen[who] = who } }
        case "day":
            // In the schedule's order, with the unscheduled first.
            guard !days.isEmpty else { return [] }
            return [("none", "Not Scheduled Yet")] + days.map { ($0.id, $0.label) }
        case "sequence":
            return sequences.map { ($0.id, $0.title) }
        default:
            return nil
        }
        return seen.map { (value: $0.key, label: $0.value) }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    func facetOptions(_ field: String) -> [(value: String, label: String)] {
        if let scene = sceneOptions(field) { return scene }
        if field == "unit" {
            let used = Set(everyRow.compactMap { $0.unit?.id })
            return units.filter { used.contains($0.id) || facets[field] == $0.id }.map { ($0.id, $0.label) }
        }
        var used = Set(everyRow.flatMap { $0.cell(field) })
        if let held = facets[field] { used.insert(held) }
        return used.filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { ($0, $0) }
    }

    func facetLabel(_ value: String, in field: String) -> String {
        facetOptions(field).first { $0.value == value }?.label ?? value
    }

    /// What the list is read in, as the Sort pill says it.
    var sortName: String {
        if shootingOrder { return "Shooting Order" }
        guard let column = view?.filter.sortColumn, !column.isEmpty else { return "Script Order" }
        return columns.first { $0.name == column }?.shown ?? Engine.Column.name(of: column)
    }

    /// How many things are narrowing the list, for the Filter pill.
    var filterCount: Int {
        facets.count + (hideStruck ? 1 : 0) + (search.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : 1)
    }

    func clearSortAndFilter() {
        clearNarrowing()
        clearSort()
        sceneOrder = .script
    }
}

/// **A section's head across the list — a break, not a label.** Three scripts
/// on one job are three shot lists in one, and the line between them reads as
/// a chapter: the title at a heading's size, set in the section's own colour.
/// The Mac's sidebar draws the same off the same rule.
private struct SectionHead: View {
    @EnvironmentObject private var session: Session
    let section: Engine.Sequence
    @State private var deleting = false
    @State private var renaming = false
    @State private var renamed = ""

    var body: some View {
        Text(section.title)
            .font(.title3.weight(.bold))
            .foregroundStyle(session.tint(of: section) ?? .primary)
            .lineLimit(1)
            .padding(.top, 14)
            .padding(.bottom, 2)
            .listRowSeparator(.hidden, edges: .top)
            .contextMenu {
                Button { renamed = section.title; renaming = true } label: {
                    Label("Rename…", systemImage: "pencil")
                }
                // The Mac's sidebar Colour menu: the swatch and nothing else.
                Menu {
                    ForEach(Session.sectionColours, id: \.hex) { swatch in
                        Button { session.colourSection(section, hex: swatch.hex) } label: {
                            Label {
                                Text(swatch.name)
                            } icon: {
                                // A menu draws its icons in one ink unless the
                                // picture says it is its own colours.
                                Image(uiImage: Swatch.dot(swatch.hex,
                                                        ticked: section.colour.uppercased() == swatch.hex))
                            }
                        }
                    }
                } label: {
                    Label("Color", systemImage: "paintpalette")
                }
                Button(role: .destructive) { deleting = true } label: {
                    Label("Delete \(session.sequenceWord)", systemImage: "trash")
                }
            }
            .alert("Rename \(session.sequenceWord)", isPresented: $renaming) {
                TextField("Name", text: $renamed)
                Button("Cancel", role: .cancel) {}
                Button("Rename") { session.renameSection(section, to: renamed) }
            }
            .confirmationDialog("Delete \(section.title)", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { session.deleteSection(section) }
                Button("Cancel", role: .cancel) {}
            } message: {
                // What a delete will cost — the one sentence the copy law keeps.
                let scenes = session.scenes.filter { $0.sequence == section.id }.count
                Text("\(scenes) scene\(scenes == 1 ? "" : "s") leave it. They keep everything of their own.")
            }
    }
}

private struct SceneRow: View {
    @EnvironmentObject private var session: Session
    let scene: Engine.Scene

    /// **A commercial's row is a title, not a slug.** The number steps back
    /// to second-rank ink, the title keeps the case it was typed in (a
    /// slugline is shouted; a title is not), and the slugline — when there is
    /// one — reads small under it. `design/22-commercial.html`.
    private var commercial: Bool { session.isCommercial }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // **The number is the anchor.** A scene is found by its number on a
            // set, said out loud by its number, and written on the slate by its
            // number — so it is the biggest thing in the row, and the heading
            // is a heading rather than a sentence.
            Text(scene.number)
                .font(.kitHeading.weight(.bold).monospacedDigit())
                .foregroundStyle(commercial ? .secondary : .primary)
                .frame(minWidth: 34, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                // The time of day, as the Mac draws it — one dot, the same four
                // colours, out of `shared/TimeOfDay.swift`. A scene should read
                // the same in his hand as it does on the desk.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if !commercial || scene.title.isEmpty {
                        TimeDot(said: scene.timeOfDay)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                    }
                    Text(scene.heading)
                        .font(.subheadline.weight(.semibold))
                        .kerning(commercial ? 0 : 0.3)
                        .lineLimit(2)
                }
                if commercial, !scene.title.isEmpty, !scene.slug.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        TimeDot(said: scene.timeOfDay)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        Text(scene.slug)
                            .font(.kitLabel.monospaced())
                            .foregroundStyle(Color(.secondaryLabel))
                            .lineLimit(1)
                    }
                }

                let rows = session.rows(inScene: scene.id)
                if !rows.isEmpty {
                    // The pictures come with the list rather than waiting behind
                    // it — his note against Cadrage was that the images survive
                    // every way of looking at a shot list.
                    HStack(spacing: 3) {
                        ForEach(rows.prefix(4).filter { $0.frame != nil }, id: \.id) { row in
                            FrameThumbnail(frame: row.frame, side: 44, board: row.board)
                        }
                        Text("\(rows.count) shot\(rows.count == 1 ? "" : "s")")
                            .font(.kitLabel)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                } else {
                    Text("No shots")
                        .font(.kitLabel)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// ------------------------------------------------------------- one scene

/// One scene's shots, in either of the two ways of reading them.
///
/// Cadrage offers five modes. Two of them earn their place on a phone: the list,
/// for scanning, and the storyboard, for looking. The script is a screen of its
/// own and is not built yet.
struct SceneShotsView: View {
    @EnvironmentObject private var session: Session
    let scene: Engine.Scene

    /// Which shot is being opened. The row's own id plus the heading it sat
    /// under, so the shot's screen can say where it is without asking again.
    struct Opening: Hashable {
        var rowId: String
        var sceneId: String
        var heading: String
    }

    enum Mode: String, CaseIterable, Identifiable {
        case list = "List"
        case storyboard = "Storyboard"
        case document = "Document"
        var id: String { rawValue }
        var symbol: String { self == .list ? "list.bullet" : self == .storyboard ? "square.grid.2x2" : "doc.text" }
    }

    @AppStorage("shotlist.mode") private var mode: Mode = .list

    @State private var showingScript = false
    /// The scene's own facts — number, slugline, synopsis, notes, the places it
    /// is shot at and the boards it hangs. A sheet, the way the Mac's is.
    @State private var showingScene = false
    @State private var exportingScene = false
    @State private var moving: Engine.Row?
    @State private var copying: Engine.Row?
    /// The shots an Add Edit Reference sheet is open for (the mod).
    @State private var addingEditRef: [String]?

    // ---- more than one at a time -------------------------------------------
    //
    // Ref 253. Everything on this screen could only ever be done to one shot,
    // so setting the same lens on six of them was six trips through the same
    // page. The engine has taken a whole selection since the beginning — it was
    // only ever the phone that could not ask.

    /// Which shots are picked, by row id.
    @State private var chosen: Set<String> = []
    @State private var selecting: EditMode = .inactive
    /// Which column the selection is being written into, when one is.
    @State private var writing = false
    @State private var movingMany = false
    @State private var copyingMany = false
    @State private var deletingMany = false

    /// The picked rows, in the order they sit in rather than the order they
    /// were tapped — deleting depends on it, and so does reading the list back.
    private var picked: [Engine.Row] { rows.filter { chosen.contains($0.id) } }

    var body: some View {
        // **Turn the phone and the script sits beside the list; hold it upright
        // and the script takes the screen.** Held sideways there is room for
        // both, and reading a scene against its coverage is the whole point of
        // having it here. Held upright there is not, and half a screen of
        // screenplay is worse than none — so it comes over the top, and the
        // same button sends it back.
        GeometryReader { space in
            let sideBySide = space.size.width > space.size.height

            if showingScript && sideBySide {
                HStack(spacing: 0) {
                    shots
                    Divider()
                    script
                        .frame(width: space.size.width * 0.5)
                        .background(Color(.systemBackground))
                }
            } else {
                shots
                    .overlay {
                        if showingScript {
                            script
                                .background(Color(.systemBackground))
                                .transition(.move(edge: .trailing))
                        }
                    }
            }
        }
        .task { if !session.isCommercial { session.readScript() } }
        .sheet(isPresented: Binding(get: { addingEditRef != nil }, set: { if !$0 { addingEditRef = nil } })) {
            PhoneAddEditReference(shots: addingEditRef ?? []).environmentObject(session)
        }
        .sheet(item: $moving) { row in
            ScenePicker(title: "Move \(row.number)", except: scene.id) { into in
                session.move(row, toScene: into.id)
            }
            .environmentObject(session)
        }
        .sheet(item: $copying) { row in
            ScenePicker(title: "Copy \(row.number)", except: scene.id) { into in
                session.copy([row], toScene: into.id)
            }
            .environmentObject(session)
        }
        .navigationDestination(for: Opening.self) { opening in
            ShotDetailView(sceneId: opening.sceneId, heading: opening.heading,
                           showing: opening.rowId)
        }
        .navigationTitle("\(scene.number)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // **While shots are picked, the bar is about the picking.** The
            // usual controls are not reachable in that state anyway, and
            // crowding them in beside the count squeezed the scene heading to
            // an ellipsis.
            if selecting == .active {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { stopSelecting() }
                }
                ToolbarItem(placement: .principal) {
                    Text(picked.isEmpty ? "None picked" : "\(picked.count) picked")
                        .font(.footnote.weight(.semibold))
                }
                ToolbarItem(placement: .primaryAction) { chosenActions }
            } else {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(scene.number).font(.kitLabel).foregroundStyle(Color(.secondaryLabel))
                        Text(scene.heading).font(.footnote.weight(.semibold)).lineLimit(1)
                    }
                }
                modes
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(.snappy) { showingScript.toggle() }
                    } label: {
                        Label(showingScript ? "Hide script" : "Script",
                              systemImage: showingScript ? "doc.plaintext.fill" : "doc.plaintext")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { session.addShot(toScene: scene.id, after: rows.last) } label: {
                            Label("Add Shot", systemImage: "plus")
                        }
                        Button { showingScene = true } label: {
                            Label("Scene…", systemImage: "film")
                        }
                        Button { exportingScene = true } label: {
                            Label("Export Scene…", systemImage: "square.and.arrow.up")
                        }
                        // Only where there is a list to pick from. Selecting in
                        // the storyboard would need its own way of showing what
                        // is picked, and it does not have one.
                        if mode == .list {
                            Button {
                                withAnimation { selecting = .active }
                            } label: {
                                Label("Select Shots", systemImage: "checkmark.circle")
                            }
                        }
                        Section {
                            Button { session.undo() } label: {
                                Label("Undo", systemImage: "arrow.uturn.backward")
                            }
                            Button { session.redo() } label: {
                                Label("Redo", systemImage: "arrow.uturn.forward")
                            }
                        }
                    } label: {
                        Label("Edit", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $exportingScene) {
            ExportSheet(scene: scene).environmentObject(session)
        }
        .sheet(isPresented: $showingScene) {
            NavigationStack {
                SceneDetailView(id: scene.id)
            }
            .environmentObject(session)
        }
        .sheet(isPresented: $writing) {
            BulkField(rows: picked) { stopSelecting() }
                .environmentObject(session)
        }
        .sheet(isPresented: $movingMany) {
            ScenePicker(title: said("Move"), except: scene.id) { into in
                session.move(picked, toScene: into.id)
                stopSelecting()
            }
            .environmentObject(session)
        }
        .sheet(isPresented: $copyingMany) {
            ScenePicker(title: said("Copy"), except: scene.id) { into in
                session.copy(picked, toScene: into.id)
                stopSelecting()
            }
            .environmentObject(session)
        }
        .confirmationDialog(said("Delete"), isPresented: $deletingMany, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                session.delete(picked)
                stopSelecting()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// "Move 4 shots" — what is about to happen, and to how many.
    private func said(_ verb: String) -> String {
        "\(verb) \(picked.count) shot\(picked.count == 1 ? "" : "s")"
    }

    /// Everything that can be done to a selection.
    ///
    /// **One menu, in the top bar.** These lived along the bottom to begin
    /// with, where a thumb already is — and on iOS 26 the tab bar floats over
    /// the bottom of the screen, so half of them were drawn underneath it and
    /// could be neither read nor pressed. Found by screenshotting it; nothing
    /// in the checks can see a control that is behind another one.
    private var chosenActions: some View {
        let cut = picked.contains { !$0.struck }
        return Menu {
            Button { writing = true } label: {
                Label("Set a Column…", systemImage: "square.and.pencil")
            }
            // **Cells, the spreadsheet way** (the Mac's ⌘C / ⌘V on cells):
            // a column's words copied as lines, or lines pasted down it.
            Menu {
                ForEach(session.columns.filter { $0.visible && !["image", "struck", "day", "sequence"].contains($0.name) }) { c in
                    Button(c.shown) {
                        UIPasteboard.general.string = picked.map { $0.cell(c.name).joined(separator: ", ") }.joined(separator: "\n")
                    }
                }
            } label: { Label("Copy Column", systemImage: "doc.on.clipboard") }
            Menu {
                ForEach(session.columns.filter { $0.visible && !["image", "struck", "day", "sequence"].contains($0.name) }) { c in
                    Button(c.shown) { session.pasteColumn(UIPasteboard.general.string ?? "", into: picked, field: c.name) }
                }
            } label: { Label("Paste into Column", systemImage: "doc.on.clipboard.fill") }
            Button { session.strike(picked, cut) } label: {
                Label(cut ? "Shot" : "Not Shot Yet", systemImage: cut ? "checkmark.circle" : "arrow.uturn.backward")
            }
            // **The Mac's picked-shot actions**: Highlight, Shoot Day,
            // Copy, Duplicate, Clear.
            Menu {
                ForEach(Array(Swatches.highlight.enumerated()), id: \.offset) { at, hex in
                    Button(Swatches.highlightNames[at]) { session.highlight(picked, hex) }
                }
                Divider()
                Button("No Highlight") { session.highlight(picked, "") }
            } label: { Label("Highlight", systemImage: "paintbrush") }
            Menu {
                ForEach(session.pickableDays()) { day in
                    Button(day.label) { session.shootDay(picked, day: day.id) }
                }
                Divider()
                Button("No Day") { session.shootDay(picked, day: nil) }
            } label: { Label("Shoot Day", systemImage: "calendar") }
            Section {
                Button { session.copiedShots = picked.map(\.placement) } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                Button { session.duplicateShots(picked); stopSelecting() } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                Button { session.clearShots(picked) } label: {
                    Label("Clear", systemImage: "eraser")
                }
            }
            Section {
                Button { movingMany = true } label: {
                    Label("Move to Scene…", systemImage: "arrow.turn.down.right")
                }
                Button { copyingMany = true } label: {
                    Label("Copy to Scene…", systemImage: "doc.on.doc")
                }
            }
            if session.modsOn.contains(PhoneMods.editReference) {
                Section {
                    Button { addingEditRef = picked.map(\.shot) } label: {
                        Label("Add Edit Reference…", systemImage: "film.stack")
                    }
                }
            }
            Section {
                Button(role: .destructive) { deletingMany = true } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        } label: {
            Label("Do", systemImage: "ellipsis.circle")
        }
        .disabled(picked.isEmpty)
    }

    private func stopSelecting() {
        withAnimation { selecting = .inactive }
        chosen = []
    }

    /// **One pill, and only as wide as it needs to be.**
    ///
    /// A segmented picker draws its own capsule, and a toolbar item on iOS 26
    /// draws a glass one behind whatever it holds — so this was a pill inside a
    /// pill. Worse, a segmented picker stretches to fill what it is given, and
    /// in landscape it was given half the screen.
    @ToolbarContentBuilder
    private var modes: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .primaryAction) { modePicker }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .primaryAction) { modePicker }
        }
    }

    private var modePicker: some View {
        Picker("View", selection: $mode) {
            ForEach(Mode.allCases) { m in
                Label(m.rawValue, systemImage: m.symbol).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
        .fixedSize()
    }

    private var rows: [Engine.Row] { session.rows(inScene: scene.id) }

    private var columns: [Engine.Column] { session.view?.columns ?? [] }

    /// **A commercial's script is an AV script**, or nothing — text on the
    /// section, quoted by shots. A film's is the screenplay laid out as pages.
    @ViewBuilder
    private var script: some View {
        if session.isCommercial {
            AVScriptPane(scene: scene)
        } else {
            ScenePages(scene: scene)
        }
    }

    private var shots: some View {
        Group {
            if rows.isEmpty {
                ContentUnavailableView(
                    "No shots in this scene",
                    systemImage: "list.bullet.rectangle"
                )
            } else {
                switch mode {
                case .list: listing
                case .storyboard: storyboard
                case .document: DocumentPhoneView(scenes: [scene.id])
                }
            }
        }
    }

    private var listing: some View {
        List(selection: $chosen) {
            if session.isCommercial {
                // A commercial scene's band is its title; the slugline, when
                // it has one, is the one fact under it.
                let live = session.scene(scene.id) ?? scene
                if !live.slug.isEmpty {
                    Section("Slugline") {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            TimeDot(said: live.timeOfDay)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                            Text(live.slug).font(.subheadline.monospaced())
                        }
                    }
                }
            } else if !scene.description.isEmpty {
                Section("Synopsis") { Synopsis(text: scene.description) }
            }
            Section {
                let pieces = session.editPieces(rows)
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    NavigationLink(value: Opening(rowId: row.id, sceneId: scene.id, heading: scene.heading)) {
                        ShotRow(row: row, pieces: pieces[row.id] ?? [], play: { _ in })
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { session.delete(row) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button { session.duplicate(row) } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        .tint(.indigo)
                    }
                    .contextMenu {
                        Button { session.addShot(toScene: scene.id, after: row) } label: {
                            Label("Add Shot After", systemImage: "plus")
                        }
                        Button { session.duplicate(row) } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        Section { ShotActions(row: row) }
                        if session.modsOn.contains(PhoneMods.editReference) {
                            Button { addingEditRef = [row.shot] } label: {
                                Label("Add Edit Reference…", systemImage: "film.stack")
                            }
                        }
                        Section {
                            Button { moving = row } label: {
                                Label("Move to Scene…", systemImage: "arrow.turn.down.right")
                            }
                            Button { copying = row } label: {
                                Label("Copy to Scene…", systemImage: "doc.on.doc")
                            }
                        }
                        // Arrows, not a drag. His ruling, 2026-08-21: a drag
                        // cannot be proved to work, and this one can.
                        if index > 0 {
                            Button { session.move(row, to: index - 1) } label: {
                                Label("Move Up", systemImage: "arrow.up")
                            }
                        }
                        if index < rows.count - 1 {
                            Button { session.move(row, to: index + 1) } label: {
                                Label("Move Down", systemImage: "arrow.down")
                            }
                        }
                        Button(role: .destructive) { session.delete(row) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                // **Hold a shot and drag it.** The arrows above stay, because
                // they are exact and they are the reachable way to do it — but
                // his words: reordering by menu "will take too long", and he is
                // right. A list is dragged.
                .onMove { from, to in
                    guard let at = from.first else { return }
                    session.move(rows[at], to: at < to ? to - 1 : to)
                }
            }
            if !scene.notes.isEmpty {
                Section("Notes") { Text(scene.notes) }
            }
        }
        .environment(\.editMode, $selecting)
    }

    private var storyboard: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                ForEach(rows) { row in
                    NavigationLink(value: Opening(rowId: row.id, sceneId: scene.id, heading: scene.heading)) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(row.number)
                                .font(.title3.weight(.bold).monospacedDigit())
                            if let title = row.cell("title").first, !title.isEmpty {
                                Text(title)
                                    .font(.kitRowStrong)
                                    .foregroundStyle(Color(.secondaryLabel))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                        }
                        ShapedPlate(row: row)
                        if !row.said(columns).isEmpty {
                            Text(row.said(columns))
                                .font(.subheadline)
                                .foregroundStyle(row.struck ? .tertiary : .secondary)
                                .strikethrough(row.struck)
                        }
                        if let quote = row.quoted(columns) {
                            Text("“\(quote)”")
                                .font(.subheadline.italic())
                                .lineLimit(3)
                                .foregroundStyle(row.struck ? .tertiary : .secondary)
                        }
                        if !row.craft(columns).isEmpty {
                            Text(row.craft(columns))
                                .font(.caption2.weight(.medium))
                                .kerning(0.3)
                                .textCase(.uppercase)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    }
                    .buttonStyle(.plain)
                }
            }
            // The tab bar floats over the content on iOS 26, so the last
            // storyboard card needs room to clear it or it reads as cut off.
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 90)
        }
    }
}

/// A scene's synopsis, which is as long as it is.
///
/// **Three lines, and a way to see the rest.** He asked what happens when it is
/// long: on a phone it pushed the shots off the bottom of the screen, and the
/// shots are what he came for. The button only appears when there is something
/// hidden behind it — `ViewThatFits` is asked whether the whole thing fits in
/// three lines' worth of room, and says so by choosing the other branch.
private struct Synopsis: View {
    let text: String
    @State private var whole = false
    @State private var longer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .lineLimit(whole ? nil : 3)
                .background(alignment: .top) {
                    ViewThatFits(in: .vertical) {
                        Text(text).hidden()
                        Color.clear.onAppear { longer = true }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                }

            if longer {
                Button(whole ? "Less" : "More") {
                    withAnimation(.snappy) { whole.toggle() }
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if longer { withAnimation(.snappy) { whole.toggle() } } }
    }
}

struct ShotRow: View {
    @EnvironmentObject private var session: Session
    let row: Engine.Row
    /// Its pieces of any Edit Reference bracket; none for a project without the mod.
    var pieces: [PhonePiece] = []
    var play: (Engine.EditRef) -> Void = { _ in }

    private var columns: [Engine.Column] { session.view?.columns ?? [] }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if !pieces.isEmpty { PhoneBracket(pieces: pieces, play: play) }
            FrameThumbnail(frame: row.frame, board: row.board)

            VStack(alignment: .leading, spacing: 3) {
                // **What the shot is called reads louder than what it says.**
                // It was the other way round: the number was smaller than the
                // sentence under it, so a list of shots read as a wall of
                // description with the numbers lost in it.
                HStack(spacing: 6) {
                    Text(row.number)
                        .font(.kitRowStrong.monospacedDigit())
                    if let title = row.cell("title").first, !title.isEmpty {
                        Text(title)
                            .font(.kitRowStrong)
                            .foregroundStyle(Color(.secondaryLabel))
                            .lineLimit(1)
                    }
                    if row.frames > 1 {
                        Label("\(row.frames)", systemImage: "photo.on.rectangle")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if !row.said(columns).isEmpty {
                    Text(row.said(columns))
                        .font(.subheadline)
                        // Three lines is a glance. A shot with a paragraph on
                        // it is read on its own page, not in the list.
                        .lineLimit(3)
                        .strikethrough(row.struck)
                        .foregroundStyle(row.struck ? .tertiary : .secondary)
                }
                if let quote = row.quoted(columns) {
                    // **The stretch of the script this shot quotes**, the way
                    // the Mac's Script column shows it — its own voice, in
                    // quotes, two lines at most.
                    Text("“\(quote)”")
                        .font(.subheadline.italic())
                        .lineLimit(2)
                        .foregroundStyle(row.struck ? .tertiary : .secondary)
                }
                if !row.craft(columns).isEmpty {
                    Text(row.craft(columns))
                        .font(.caption2.weight(.medium))
                        .kerning(0.3)
                        .textCase(.uppercase)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 1)
                }
            }
        }
        .padding(.vertical, 3)
    }
}
