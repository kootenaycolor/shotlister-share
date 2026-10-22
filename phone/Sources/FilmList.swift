import SwiftUI

/// **The whole shot list in one scroll** — his ask, 2026-10-06 (Ref 1541,
/// `design/33-one-app.html` section 2): "I just enjoy going through the way the
/// web portal organizes the shot list more when I'm actually trying to view
/// it … The way we do it currently on the app is just more frustrating. It's
/// good for data input, but … it doesn't feel like it's for actually
/// presenting it."
///
/// So the scene index stops being a gate. Every scene is a band (its number,
/// heading and synopsis) and under it every shot, with its frame, description,
/// notes and the craft columns as coloured tags, the way the portal lays it
/// out. Nothing here edits: a shot opens its own page, which is where the
/// editing has always been, and a band opens the scene's screen with its tools
/// (picking many, the script beside, export).
struct FilmShotList: View {
    @EnvironmentObject private var session: Session
    @AppStorage("shotlist.mode") private var mode: SceneShotsView.Mode = .list
    @State private var jumping = false
    @Binding var removing: Engine.Scene?
    @Binding var editing: Bool
    @Binding var editingFrom: Engine.Row.ID?
    /// **The one shot whose details are open**, in List and Storyboard alike
    /// (his ruling, 2026-10-09): tapping a shot's words opens them under it,
    /// in place, and only one is open at a time.
    @State private var open: Engine.Row.ID?

    /// Edit under a shot: into Editing, starting at that shot.
    private func edit(_ row: Engine.Row) {
        editingFrom = row.id
        withAnimation(.snappy) { editing = true }
    }

    var body: some View {
        if mode == .document {
            // **Document** (the Mac's): every scene shown, as it prints.
            DocumentPhoneView(scenes: session.shownScenes.map(\.id))
                .safeAreaInset(edge: .top, spacing: 0) { ModeBar(mode: $mode) { EmptyView() } }
        } else {
            shotList
        }
    }

    private var shotList: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    let layout = mode == .list ? session.editLayout() : PhoneEditLayout()
                    ForEach(session.shownScenes) { scene in
                        if let section = session.sectionStarts(at: scene, in: session.shownScenes) {
                            SectionBreak(section: section)
                                .overlay { if let p = layout.through["band:" + scene.id] { PhoneBandThrough(pieces: p) } }
                        }
                        Section {
                            SceneShots(scene: scene, mode: mode, open: $open, edit: edit, layout: layout)
                                .sectionWash(of: scene)
                        } header: {
                            // **Opaque, or the shots show through it.** The
                            // headers are pinned, so without a ground of its
                            // own a frame scrolls up behind the slugline and
                            // reads through it (his note, 2026-10-07).
                            SceneBand(scene: scene, removing: $removing, margin: layout.any)
                                .sectionWash(of: scene, over: Style.page)
                                .overlay { if let p = layout.through["band:" + scene.id] { PhoneBandThrough(pieces: p) } }
                        }
                        .id(scene.id)
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Style.page)
            .safeAreaInset(edge: .top, spacing: 0) {
                ModeBar(mode: $mode) {
                    // **The way into Editing** (Ref 1615). It was to sit in
                    // the tools pill beside +, but iOS folds a fourth button
                    // there into a ••• menu, which would hide it; here it is
                    // always in sight, beside Scenes.
                    if !session.isReadOnly {
                        Button {
                            editingFrom = open
                            withAnimation(.snappy) { editing = true }
                        } label: {
                            BarCircle(symbol: "pencil")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit")
                        .accessibilityIdentifier("editing.start")
                    }
                    // **A glyph, not the word** (his ask, 2026-10-09: "instead
                    // of writing out scenes, it could be smaller").
                    Button { jumping = true } label: { BarCircle(symbol: "list.number") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Scenes")
                        .accessibilityIdentifier("scenes")
                }
            }
            // `--jumpscene 34`: a checking run opens the list at that scene.
            .onAppear {
                let args = ProcessInfo.processInfo.arguments
                if let at = args.firstIndex(of: "--jumpscene"), at + 1 < args.count,
                   let scene = session.shownScenes.first(where: { $0.number == args[at + 1] }) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { reader.scrollTo(scene.id, anchor: .top) }
                }
            }
            .sheet(isPresented: $jumping) {
                SceneJump { scene in
                    jumping = false
                    // After the sheet has gone, or the scroll is lost under it.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.snappy) { reader.scrollTo(scene.id, anchor: .top) }
                    }
                }
                .environmentObject(session)
                .presentationDetents([.medium, .large])
            }
        }
    }
}

/// The bar over a list of shots: List or Storyboard on the left, whatever
/// belongs to the screen on the right (Scenes here, nothing in Shooting Order).
struct ModeBar<Trailing: View>: View {
    @Binding var mode: SceneShotsView.Mode
    @ViewBuilder var trailing: () -> Trailing
    @EnvironmentObject private var session: Session
    @State private var display = false

    var body: some View {
        // Tight enough that List, Storyboard, Display, the pencil and Scenes
        // all fit a 402-point phone without the switch shortening to "Story…".
        HStack(spacing: 6) {
            GlassSegments(options: SceneShotsView.Mode.allCases.map { ($0, $0.rawValue) }, selection: $mode,
                          compact: true)
                .layoutPriority(1)
            // **Display: how this screen looks** (`design/42-one-home`).
            // One sheet for Picture Size, Mark Shots, Sort and Filter; the
            // filter button in the bar and the Scenes sheet's half of it went.
            Button { display = true } label: {
                BarCircle(symbol: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Display")
            .accessibilityIdentifier("display")
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .sheet(isPresented: $display) {
            DisplaySheet()
                .environmentObject(session)
                .presentationDetents([.medium, .large])
                .presentationBackground(Style.page)
        }
        // **A ground of its own.** The bar sits in the top safe area and had
        // none, so shots scrolled up behind it and showed in the strip above
        // the pinned scene header — his note, 2026-10-07: *"There's still a
        // gap above the scene header as the shot list scrolls"*.
        .frame(maxWidth: .infinity)
        .background(Style.page)
    }
}

/// A section's name across the list, on a commercial: the break between two
/// scripts on one job, in the section's own colour.
private struct SectionBreak: View {
    @EnvironmentObject private var session: Session
    let section: Engine.Sequence

    var body: some View {
        Text(section.title)
            .font(.title3.weight(.bold))
            .foregroundStyle(session.tint(of: section) ?? .primary)
            .lineLimit(1)
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sectionWash(tint: session.tint(of: section))
    }
}

/// **A commercial's section as a light wash** over its head, its scene bands
/// and its shots (his call, 2026-10-16, in place of the side bar). Same
/// strength as the Mac and the portal (kit `sectionWash`).
private struct SectionWash: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let tint: Color?
    let over: Color?
    func body(content: Content) -> some View {
        content.background {
            ZStack {
                if let over { over }
                if let tint {
                    tint.opacity(Kit.sectionWash(dark: scheme == .dark))
                }
            }
        }
    }
}

private extension View {
    func sectionWash(tint: Color?, over: Color? = nil) -> some View {
        modifier(SectionWash(tint: tint, over: over))
    }
    func sectionWash(of scene: Engine.Scene, over: Color? = nil) -> some View {
        modifier(SceneWash(scene: scene, over: over))
    }
}

private struct SceneWash: ViewModifier {
    @EnvironmentObject private var session: Session
    let scene: Engine.Scene
    let over: Color?
    func body(content: Content) -> some View {
        content.sectionWash(tint: session.tint(of: session.section(of: scene)), over: over)
    }
}

/// **A scene's band**: its number, its heading, its synopsis in two lines.
/// Pinned while its shots go by, so the scene being read is always named.
/// Tapping it opens the scene's own screen.
private struct SceneBand: View {
    @EnvironmentObject private var session: Session
    let scene: Engine.Scene
    @Binding var removing: Engine.Scene?
    /// Stepped in beside an Edit Reference bracket's margin.
    var margin = false

    private var commercial: Bool { session.isCommercial && !scene.title.isEmpty }

    var body: some View {
        NavigationLink(value: scene) {
            HStack(alignment: .top, spacing: 12) {
                Text(scene.number)
                    .font(.system(size: 28, weight: .bold).monospacedDigit())
                    .foregroundStyle(commercial ? .secondary : .primary)
                    .frame(minWidth: 28, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        TimeDot(said: scene.timeOfDay)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        if scene.archived {
                            Image(systemName: "archivebox").font(.system(size: 11)).foregroundStyle(Style.ink3)
                                .accessibilityLabel("Archived")
                        }
                        Text(commercial ? scene.title : scene.heading)
                            .font(.system(size: 13, weight: .bold))
                            .kerning(commercial ? 0 : 0.3)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    if commercial, !scene.slug.isEmpty {
                        Text(scene.slug)
                            .font(.kitLabel.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if !scene.description.isEmpty {
                        Text(scene.description)
                            .font(.system(size: 13))
                            .foregroundStyle(Style.ink2)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 4)
                let count = session.rows(inScene: scene.id).count
                Text(count == 1 ? "1 shot" : "\(count) shots")
                    .font(.system(size: 13))
                    .foregroundStyle(Style.ink3)
                    .padding(.top, 3)
            }
            .padding(.leading, margin ? PhoneEditMargin.width + 4 : 18)
            .padding(.trailing, 18)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Style.page)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            NavigationLink(value: scene) { Label("Open Scene", systemImage: "film") }
            // **Order** (the Mac drags in its scene list): one place up or
            // down; numbers stay the script's.
            if session.sceneOrder == .script {
                let all = session.view?.scenes ?? []
                if let at = all.firstIndex(where: { $0.id == scene.id }) {
                    Section {
                        if at > 0 {
                            Button { session.moveScene(scene, after: at > 1 ? all[at - 2] : nil) } label: {
                                Label("Move Up", systemImage: "arrow.up")
                            }
                        }
                        if at < all.count - 1 {
                            Button { session.moveScene(scene, after: all[at + 1]) } label: {
                                Label("Move Down", systemImage: "arrow.down")
                            }
                        }
                    }
                }
            }
            if scene.locationIds.isEmpty, !scene.location.trimmingCharacters(in: .whitespaces).isEmpty {
                Button { session.makeLocation(from: scene) } label: {
                    Label("Make a Location from \(scene.location)", systemImage: "mappin.and.ellipse")
                }
            }
            Button { session.archive(scene, !scene.archived) } label: {
                Label(scene.archived ? "Unarchive" : "Archive",
                      systemImage: scene.archived ? "tray.and.arrow.up" : "archivebox")
            }
            if session.manyShoots {
                Menu {
                    ForEach(session.shoots) { shoot in
                        Button(shoot.label + (scene.shoot == shoot.id ? "  ✓" : "")) {
                            session.moveScene(scene, toShoot: shoot)
                        }
                        .disabled(scene.shoot == shoot.id)
                    }
                } label: { Label("Move to Shoot", systemImage: "arrow.right.square") }
            }
            Button(role: .destructive) { removing = scene } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

/// One scene's shots under its band, as a list of rich rows or as frames.
private struct SceneShots: View {
    @EnvironmentObject private var session: Session
    let scene: Engine.Scene
    let mode: SceneShotsView.Mode
    @Binding var open: Engine.Row.ID?
    let edit: (Engine.Row) -> Void
    /// The Edit Reference brackets down the whole list (the mod), worked out
    /// once per drawing of the list.
    var layout = PhoneEditLayout()

    var body: some View {
        let rows = session.rows(inScene: scene.id)
        if rows.isEmpty {
            Text("No shots")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
        } else if mode == .list {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    // **Not a link any more** (2026-10-09): the words open the
                    // shot's details in place, the picture opens the viewer,
                    // and Edit in the details is the way to its page.
                    PresentedShot(row: row, open: $open, opening: opening(row), edit: edit)
                        .anchorPreference(key: PhoneRowBounds.self, value: .bounds) { [row.id: $0] }
                    if index < rows.count - 1 {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .card(Style.Radius.group)
            // **The bracket's margin** (Edit Reference): with one drawn, the
            // cards step in and the bracket runs beside them, over the bands.
            .padding(.leading, layout.any ? PhoneEditMargin.width : 10)
            .padding(.trailing, 10)
            .padding(.bottom, 6)
            .overlayPreferenceValue(PhoneRowBounds.self) { anchors in
                if layout.any {
                    PhoneSceneBracket(rows: rows, layout: layout, anchors: anchors)
                }
            }
        } else {
            StoryboardTiles(rows: rows, opening: opening, open: $open, edit: edit)
        }
    }

    private func opening(_ row: Engine.Row) -> SceneShotsView.Opening {
        SceneShotsView.Opening(rowId: row.id, sceneId: scene.id, heading: scene.heading)
    }
}

/// **A shot in the list** (his rulings, 2026-10-09, mocked up on the "Shot
/// List · iPhone Refined" canvas): the picture always on the left, so List
/// reads as a list and Storyboard is the only wall of pictures; Picture Size
/// changes only how big that picture is. Beside it the number, the title, and
/// the craft columns as the Mac's pills ("A · The Mac's Pills, As Is").
///
/// **Two things to tap, and neither leaves the list.** The words open the
/// shot's details underneath, the picture staying where it is; the picture
/// opens the media viewer. Where `open` is nil (Shooting Order, whose rows are
/// links) it is the same row drawn, and the link does the tapping.
struct PresentedShot: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var frames: Frames
    let row: Engine.Row
    /// Where the shot lives, one small line over it: Shooting Order mixes
    /// scenes inside a day, so it says which.
    var scene: Engine.Scene? = nil
    /// The one open shot on the list, shared so opening one closes the last.
    var open: Binding<Engine.Row.ID?>? = nil
    /// The shot's own page, for Edit in its details.
    var opening: SceneShotsView.Opening? = nil
    /// Into Editing at this shot: the one Editing, the same as the pencil.
    var edit: ((Engine.Row) -> Void)? = nil

    @State private var browsing: Engine.Still?

    private var columns: [Engine.Column] { session.view?.columns ?? [] }

    @AppStorage(FrameSize.key) private var frameSize = FrameSize.full.rawValue
    private var size: FrameSize { FrameSize(rawValue: frameSize) ?? .full }

    private var isOpen: Bool { open?.wrappedValue == row.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                picture
                words
            }
            if isOpen {
                ShotDetails(row: row, opening: opening, edit: edit)
                    .padding(.top, 12)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity))
            }
        }
        .padding(12)
        // **Its highlight, as a wash across the row** — the Mac's, which
        // dropped the dot for the wash on his word.
        .background {
            if let hex = row.colour, !hex.isEmpty {
                Color(markHex: hex).opacity(0.17)
            }
        }
        .clipped()
        // No coloured stripe down the card's edge: his rule (2026-10-05);
        // the section's name over the list carries its colour.
        .contentShape(Rectangle())
        // Hold a shot: the Mac's right-click, Highlight and master shots.
        .contextMenu { ShotActions(row: row) }
        .fullScreenCover(item: $browsing) { still in
            StillViewer(still: still, all: row.stills, onDelete: { session.detach($0) },
                        cropTo: session.ratio)
                .environmentObject(session)
                .environmentObject(frames)
        }
    }

    /// The picture, beside the words, in the film's own shape.
    private var picture: some View {
        FramePlate(frame: row.frame, ratio: session.ratio, board: row.board)
            .frame(width: size.listWidth)
            .opacity(row.struck ? 0.45 : 1)
            .overlay(alignment: .topLeading) {
                if row.struck { Badge(text: "Shot", ground: .accentColor, word: .white) }
            }
            .contentShape(Rectangle())
            .tapping(open != nil) {
                if let still = row.stills.first(where: { $0.key == true }) ?? row.stills.first {
                    browsing = still
                } else {
                    toggle()
                }
            }
            .accessibilityAddTraits(open != nil ? .isButton : [])
            .accessibilityLabel(open != nil ? "View \(row.number)" : row.number)
    }

    /// The number and the mark, the title, and the pills, or Less when open.
    private var words: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text(row.number)
                    .font(.system(size: 15, weight: .heavy).monospacedDigit())
                    .foregroundStyle(row.struck ? Style.ink3 : Color(.label))
                MasterMark(row: row)
                Spacer(minLength: 0)
                if marking {
                    ShotMark(on: row.struck) { session.strike(row, !row.struck) }
                }
            }
            .frame(minHeight: 28)
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .strikethrough(row.struck)
                    .foregroundStyle(row.struck ? Style.ink3 : Color(.label))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let scene {
                Text(sceneLine(scene))
                    .font(.system(size: 13))
                    .foregroundStyle(Style.ink3)
                    .lineLimit(1)
            }
            if isOpen {
                Label("Less", systemImage: "chevron.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Style.ink2)
                    .labelStyle(LessLabel())
                    .padding(.top, 4)
            } else if !tags.isEmpty {
                Chips(tags: tags, struck: row.struck)
                    .padding(.top, 4)
            }
            if !isOpen, !(row.lensFilters.isEmpty && row.modifiers.isEmpty) {
                LensStackLine(filters: row.lensFilters, modifiers: row.modifiers, struck: row.struck)
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .contentShape(Rectangle())
        .tapping(open != nil) { toggle() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(open != nil ? .isButton : [])
        .accessibilityHint(open == nil ? "" : (isOpen ? "Less" : "Details"))
        .accessibilityIdentifier("shot.words")
    }

    private func toggle() {
        guard let open else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            open.wrappedValue = isOpen ? nil : row.id
        }
    }

    @AppStorage(MarkingShots.key) private var marks = ""
    /// The round mark shows on a shoot day, or when he has turned it on.
    private var marking: Bool { MarkingShots.showing(choice: marks, shootDay: session.isShootDay) }

    private var title: String { shows("title") ? row.title : "" }

    private func sceneLine(_ scene: Engine.Scene) -> String {
        let name = session.isCommercial && !scene.title.isEmpty ? scene.title : scene.heading
        return name.isEmpty ? scene.number : "\(scene.number) \u{00B7} \(name)"
    }

    private func shows(_ name: String) -> Bool {
        columns.first { $0.name == name }?.visible ?? true
    }

    /// Every craft column as a pill in its column's colour, in the film's
    /// column order: the Mac's table, the way it reads in a row.
    private var tags: [Chips.Tag] { Chips.tags(of: row, columns, colours: session.termColour) }

}

/// **Lens Stack, the second line**: a shot's filters and modifiers under its
/// lens, small and quiet in the lens colour, a ring for a filter and a diamond
/// for a modifier. No box, no outline.
struct LensStackLine: View {
    let filters: [String]
    let modifiers: [String]
    var struck = false
    var roomy = false

    var body: some View {
        let ink = TagInk.lens.word.opacity(struck ? 0.5 : 0.85)
        Wrap(spacing: roomy ? 12 : 9) {
            ForEach(filters, id: \.self) { item($0, ring: true, ink: ink) }
            ForEach(modifiers, id: \.self) { item($0, ring: false, ink: ink) }
        }
    }

    private func item(_ name: String, ring: Bool, ink: Color) -> some View {
        HStack(spacing: 4) {
            Group {
                if ring {
                    Circle().strokeBorder(ink, lineWidth: 1)
                } else {
                    Rectangle().strokeBorder(ink, lineWidth: 1).rotationEffect(.degrees(45)).scaleEffect(0.82)
                }
            }
            .frame(width: 6, height: 6)
            Text(name)
                .font(.system(size: roomy ? 12.5 : 11.5))
                .foregroundStyle(ink)
        }
    }
}

private extension View {
    /// A tap only where the row is not a link. Shooting Order's rows sit under
    /// an invisible link, and a gesture here, even one that does nothing,
    /// would take the tap from it.
    @ViewBuilder
    func tapping(_ on: Bool, _ action: @escaping () -> Void) -> some View {
        if on { onTapGesture(perform: action) } else { self }
    }
}

/// The arrow after the word, the way a disclosure reads.
private struct LessLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 10, weight: .bold))
            configuration.title
        }
    }
}

/// **A shot's details, opened in place** under its row or its tile: every
/// craft column as a labelled set of pills, then the description and notes,
/// then Edit, which is the way to the shot's own page.
struct ShotDetails: View {
    @EnvironmentObject private var session: Session
    let row: Engine.Row
    let opening: SceneShotsView.Opening?
    var edit: ((Engine.Row) -> Void)? = nil

    private var columns: [Engine.Column] { session.view?.columns ?? [] }

    private struct Field: Identifiable {
        let id: String
        let label: String
        let tags: [Chips.Tag]
        /// Lens Stack: the shot's filters and modifiers, under the lens chip.
        var filters: [String] = []
        var modifiers: [String] = []
    }

    private var groups: [Field] {
        columns.compactMap { column in
            guard column.visible, let ink = Chips.ink(column.name, kind: column.kind) else { return nil }
            let values = row.cell(column.name)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let under = column.name == "lens"
            guard !values.isEmpty || (under && !(row.lensFilters.isEmpty && row.modifiers.isEmpty)) else { return nil }
            return Field(id: column.name, label: label(column),
                         tags: values.map { value in
                             Chips.Tag(text: value, ink: session.termColour(column.name, value).map(TagInk.chosen) ?? ink)
                         },
                         filters: under ? row.lensFilters : [],
                         modifiers: under ? row.modifiers : [])
        }
    }

    private func label(_ column: Engine.Column) -> String {
        if let said = column.label, !said.isEmpty { return said }
        switch column.name {
        case "size": return "Size"
        case "angle": return "Angle"
        case "movement": return "Move"
        case "lens": return "Lens"
        case "modifiers": return "Modifiers"
        case "lens_filters": return "Filters"
        case "support": return "Rig"
        case "tags": return "Tags"
        default: return column.name
        }
    }

    private func shows(_ name: String) -> Bool {
        columns.first { $0.name == name }?.visible ?? true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !groups.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .topLeading),
                                    GridItem(.flexible(), alignment: .topLeading)],
                          alignment: .leading, spacing: 14) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.label)
                                .font(.system(size: Kit.Size.label, weight: .semibold))
                                .foregroundStyle(Style.ink3)
                            Chips(tags: group.tags, roomy: true)
                            if !(group.filters.isEmpty && group.modifiers.isEmpty) {
                                LensStackLine(filters: group.filters, modifiers: group.modifiers, roomy: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.bottom, 4)
            }
            if shows("description"), !row.description.isEmpty {
                said("Description", row.description)
            }
            if shows("notes"), !row.notes.isEmpty {
                said("Notes", row.notes)
            }
            // **A small Edit, into the one Editing** (his note, 2026-10-09:
            // "there are two editing modes … the edit button shouldn't be so
            // big"). It goes where the pencil goes, starting at this shot.
            if !session.isReadOnly, edit != nil || opening != nil {
                HStack {
                    Spacer()
                    Group {
                        if let edit {
                            Button { edit(row) } label: { editLabel }
                        } else if let opening {
                            NavigationLink(value: opening) { editLabel }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("shot.edit")
                }
                .padding(.top, 10)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Style.page, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var editLabel: some View {
        Label("Edit", systemImage: "pencil")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(.label))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Color(.tertiarySystemFill), in: Capsule())
            .contentShape(Capsule())
            // A 32-point capsule, a 44-point target.
            .padding(.vertical, 6)
            .contentShape(Rectangle())
    }

    private func said(_ name: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.bottom, 6)
            Text(name)
                .font(.system(size: Kit.Size.label, weight: .semibold))
                .foregroundStyle(Style.ink3)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Color(.label).opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.top, 10)
    }
}

/// A word on a frame: the shot's number, or **Shot**.
private struct Badge: View {
    let text: String
    let ground: Color
    let word: Color

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(word)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(ground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .padding(9)
    }
}

/// **Shot, as one tap on the row.** It took a multi-select and a bulk edit
/// (2026-10-07): on a set that is three taps too many, and a shot's state is
/// something the row should wear.
struct ShotMark: View {
    let on: Bool
    /// In the bar it sits over a photograph, where a hairline circle is
    /// invisible: it takes a dark backing there, and none on a card.
    var overImage = false
    let tapped: () -> Void

    init(on: Bool, overImage: Bool = false, tapped: @escaping () -> Void) {
        self.on = on
        self.overImage = overImage
        self.tapped = tapped
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(on ? Color.clear
                              : (overImage ? .white.opacity(0.9) : Style.ink3.opacity(0.6)),
                              lineWidth: 1.5)
                .background(Circle().fill(on ? Color.accentColor
                                          : (overImage ? .black.opacity(0.35) : .clear)))
            if on {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 28, height: 28)
        .contentShape(Circle())
        // **Not a Button, and the gesture takes priority.** A Button inside a
        // List row that is itself a navigation link never fires: the row
        // takes the tap and opens the shot. Found by a UI test pressing it,
        // 2026-10-07 — it had shipped looking right and doing nothing.
        .highPriorityGesture(TapGesture().onEnded { tapped() })
        // And its own element, or the row merges it into one label and there
        // is nothing to press.
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("shotmark")
        .accessibilityLabel(on ? "Not Shot Yet" : "Shot")
        .accessibilityAction { tapped() }
    }
}

/// Small coloured tags that wrap onto as many lines as they need, each in
/// its column's ink (`TagInk`, the mockup's six).
struct Chips: View {
    struct Tag: Hashable {
        var text: String
        var ink: TagInk
        init(text: String, ink: TagInk) {
            self.text = text
            self.ink = ink
        }
        /// A tag with no column of its own: grey.
        init(text: String, tint: Color) {
            self.text = text
            self.ink = .own
        }
    }
    let tags: [Tag]
    /// A shot marked Shot wears its pills grey, the way its title is struck.
    var struck = false
    /// The details' pills: a size up, for reading rather than scanning.
    var roomy = false

    /// Which ink a column's tags wear. The six the portal draws keep the
    /// portal's colours; a project's own single or multi pick-list is grey.
    /// Anything that is not a short value (a description, notes) is not a tag.
    static func ink(_ column: String, kind: String?) -> TagInk? {
        switch column {
        case "size": return .size
        case "angle": return .angle
        case "movement": return .movement
        case "lens", "modifiers", "lens_filters": return .lens
        case "support": return .support
        case "tags": return .tags
        default:
            if column.hasPrefix("c_"), kind == "single" || kind == "multi" { return .own }
            return nil
        }
    }

    /// The craft columns, each value a tag in its column's ink: what the
    /// portal draws under a shot. A project's own pick-lists come after, grey.
    /// A value he gave a colour of its own (the list's Colour, on the Mac
    /// or here) wears it instead of its column's ink.
    static func tags(of row: Engine.Row, _ columns: [Engine.Column],
                     colours: (String, String) -> String? = { _, _ in nil }) -> [Tag] {
        var out: [Tag] = []
        for column in columns where column.visible {
            guard let ink = ink(column.name, kind: column.kind) else { continue }
            for value in row.cell(column.name) {
                let said = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !said.isEmpty {
                    out.append(.init(text: said, ink: colours(column.name, said).map(TagInk.chosen) ?? ink))
                }
            }
        }
        return out
    }

    var body: some View {
        // **The Mac's pill** (`Chip` in studio/Sources/Controls.swift): a box
        // with a small fixed corner, not a capsule, so a lens that wraps stays
        // a box; his pick on 2026-10-09 ("A · The Mac's Pills, As Is").
        Wrap(spacing: roomy ? 5 : 4) {
            ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                Text(tag.text)
                    // One look: the kit's tag shape; 11 here (the label size)
                    // because 10 is below what a phone reads at arm's length.
                    .font(.system(size: roomy ? Kit.Size.body : Kit.Size.label, weight: .semibold))
                    .lineLimit(roomy ? 3 : 1)
                    .padding(.horizontal, roomy ? Kit.Space.s : Kit.tagPadH)
                    .padding(.vertical, roomy ? Kit.Space.xs : Kit.tagPadV)
                    .foregroundStyle(struck ? Style.ink3 : tag.ink.word)
                    .background(struck ? Color(.tertiarySystemFill) : tag.ink.ground,
                                in: RoundedRectangle(cornerRadius: Kit.Radius.tag, style: .continuous))
            }
        }
    }
}

/// Lays its children left to right and starts a new line when one will not
/// fit: the way tags sit under a shot.
struct Wrap: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = Self.measure(view, within: width)
            if x > 0, x + size.width > width {
                y += line + spacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        // Take the whole width offered. Answering with the widest line instead
        // left placement a hair narrower than measuring, and a tag that fitted
        // when measured wrapped when placed, over the next row.
        return CGSize(width: width.isFinite ? width : widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = Self.measure(view, within: bounds.width)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += line + spacing
                x = bounds.minX
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }

    /// A child at its natural width, unless that is wider than the line: then
    /// at the line's width, so it wraps or truncates inside it. Placing it at
    /// its natural width ran a long lens out of its half of the details and
    /// over the Equipment pill beside it (2026-10-09).
    private static func measure(_ view: LayoutSubview, within width: CGFloat) -> CGSize {
        let natural = view.sizeThatFits(.unspecified)
        guard width.isFinite, natural.width > width else { return natural }
        return view.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }
}

/// Frames first, two across, each with its number and title under it.
///
/// On the shot list itself (`open` given) a tile is two things to tap, the
/// same as a list row (2026-10-09): the picture opens the media viewer, the
/// caption opens the shot's details across the full width under its line of
/// tiles. Shooting Order passes no `open`, and its tiles stay links.
/// **One card's picture at the width it is given**, in its own shape: the
/// shot's Print Frame whole when it has a current one, else the project's
/// frame. The big one-card-a-row storyboard uses this; the tile wall lays
/// its plates by `BoardPlan`.
struct ShapedPlate: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var frames: Frames
    let row: Engine.Row

    var body: some View {
        if let b = row.board, let w = b.width, let h = b.height, w > 0, h > 0,
           let image = frames.image(hash: b.hash, ext: b.ext, atMost: UIScreen.main.bounds.width) {
            Color.white
                .aspectRatio(CGFloat(w) / CGFloat(h), contentMode: .fit)
                .overlay { Image(uiImage: image).resizable().aspectRatio(contentMode: .fit) }
        } else {
            FramePlate(frame: row.frame, ratio: session.ratio, board: row.board)
                .overlay {
                    let guides = FrameGuide.of(session.view?.project)
                    if !guides.isEmpty { FrameGuideLines(guides: guides) }
                }
        }
    }
}

struct StoryboardTiles: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var frames: Frames
    /// The same Picture Size the list uses: more across is smaller.
    @AppStorage(FrameSize.key) private var frameSize = FrameSize.full.rawValue
    let rows: [Engine.Row]
    let opening: (Engine.Row) -> SceneShotsView.Opening
    /// A menu held on a tile, where the screen has one (Move to Day).
    var menu: ((Engine.Row) -> AnyView)? = nil
    var open: Binding<Engine.Row.ID?>? = nil
    var edit: ((Engine.Row) -> Void)? = nil
    @Environment(\.horizontalSizeClass) private var width
    @State private var viewing: Engine.Row?

    private var across: Int { (FrameSize(rawValue: frameSize) ?? .full).across(regular: width == .regular) }

    /// The room the board has: measured, so cards can be laid by their pictures.
    @State private var room: CGFloat = UIScreen.main.bounds.width
    private let margin: CGFloat = 10
    private let gutter: CGFloat = 8

    /// A shot's picture area is its Print Frame's shape when it has a current
    /// one, else the project's frame (`BoardPlan`, shared with the Mac).
    private func baked(_ row: Engine.Row) -> (CGFloat, CGFloat)? {
        guard let b = row.board, let w = b.width, let h = b.height, w > 0, h > 0 else { return nil }
        return (CGFloat(w), CGFloat(h))
    }

    private var plan: [[BoardPlan.Slot]] {
        let usable = max(1, room - margin * 2)
        let film = CGFloat(session.ratio)
        let card = (usable - gutter * CGFloat(across - 1)) / CGFloat(across)
        return BoardPlan.rows(ratios: rows.map { BoardPlan.shape(baked($0), film: film) },
                              width: usable, cardWidth: card, film: film, gutter: gutter, chrome: 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(plan.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: gutter) {
                    ForEach(line, id: \.index) { slot in
                        if let open {
                            openTile(rows[slot.index], slot: slot, open: open)
                        } else {
                            tile(rows[slot.index], slot: slot)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let open, let row = line.map({ rows[$0.index] }).first(where: { $0.id == open.wrappedValue }) {
                    ShotDetails(row: row, opening: self.opening(row), edit: edit)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity))
                }
            }
        }
        .padding(.horizontal, margin)
        .padding(.bottom, 8)
        .background(GeometryReader { geo in
            Color.clear.onAppear { room = geo.size.width }
                .onChange(of: geo.size.width) { _, now in room = now }
        })
        .fullScreenCover(item: $viewing) { row in
            let first = row.stills.first(where: { $0.key == true }) ?? row.stills[0]
            StillViewer(still: first, all: row.stills, onDelete: { session.detach($0) },
                        cropTo: session.ratio)
                .environmentObject(session)
                .environmentObject(frames)
        }
    }

    @ViewBuilder
    private var guideLines: some View {
        let guides = FrameGuide.of(session.view?.project)
        if !guides.isEmpty { FrameGuideLines(guides: guides) }
    }

    /// The picture area of one card: the baked Print Frame whole, in its own
    /// shape, else the shot's picture in the project's frame.
    @ViewBuilder
    private func plate(_ row: Engine.Row, slot: BoardPlan.Slot) -> some View {
        if let b = row.board, baked(row) != nil,
           let image = frames.image(hash: b.hash, ext: b.ext, atMost: UIScreen.main.bounds.width) {
            Color.white
                .frame(width: slot.pictureWidth, height: slot.pictureHeight)
                .overlay { Image(uiImage: image).resizable().aspectRatio(contentMode: .fit) }
                .frame(width: slot.width)
        } else {
            FramePlate(frame: row.frame, ratio: session.ratio, board: row.board)
                .frame(width: slot.pictureWidth, height: slot.pictureHeight)
                .overlay { guideLines }
                .frame(width: slot.width)
        }
    }

    private func openTile(_ row: Engine.Row, slot: BoardPlan.Slot, open: Binding<Engine.Row.ID?>) -> some View {
        let isOpen = open.wrappedValue == row.id
        let toggle = {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                open.wrappedValue = isOpen ? nil : row.id
            }
        }
        return VStack(alignment: .leading, spacing: 0) {
            plate(row, slot: slot)
                .opacity(row.struck ? 0.45 : 1)
                .contentShape(Rectangle())
                .onTapGesture {
                    if row.stills.isEmpty { toggle() } else { viewing = row }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("View \(row.number)")
            caption(row)
                .contentShape(Rectangle())
                .onTapGesture { toggle() }
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("tile.caption")
        }
        .card(Style.Radius.tile)
        .frame(width: slot.width)
        .overlay {
            RoundedRectangle(cornerRadius: Style.Radius.tile, style: .continuous)
                .strokeBorder(isOpen ? Color(.label).opacity(0.85) : .clear, lineWidth: 1.5)
        }
        .contextMenu {
            if let menu { menu(row) } else { ShotActions(row: row) }
        }
    }

    private func caption(_ row: Engine.Row) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            (Text(row.number).font(.system(size: 13, weight: .heavy))
             + Text(row.title.isEmpty ? "" : " \(row.title)").font(.system(size: 13)))
                .lineLimit(2)
                .strikethrough(row.struck)
                .foregroundStyle(row.struck ? .secondary : .primary)
                .multilineTextAlignment(.leading)
            // **The Mac's card**: the description and the column tags under
            // the picture, where the cards are wide enough to read them.
            if across <= 2 {
                if !row.description.isEmpty {
                    Text(row.description)
                        .font(.system(size: 13))
                        .foregroundStyle(Style.ink2)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                let tags = Chips.tags(of: row, session.columns, colours: session.termColour)
                if !tags.isEmpty { Chips(tags: tags, struck: row.struck) }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 8)
        // Its highlight, the same wash as the list row.
        .background {
            if let hex = row.colour, !hex.isEmpty { Color(markHex: hex).opacity(0.17) }
        }
    }

    @ViewBuilder
    private func tile(_ row: Engine.Row, slot: BoardPlan.Slot) -> some View {
        if let menu {
            link(row, slot: slot).contextMenu { menu(row) }
        } else {
            link(row, slot: slot)
        }
    }

    private func link(_ row: Engine.Row, slot: BoardPlan.Slot) -> some View {
        NavigationLink(value: opening(row)) {
            VStack(alignment: .leading, spacing: 0) {
                // **The whole frame, not a square of it** (his note,
                // 2026-10-07). A storyboard tile used to be a 4:3 box
                // with a square thumbnail filling it, so a 2.39 shot
                // lost its sides — which is the one thing a storyboard
                // is for.
                plate(row, slot: slot)
                caption(row)
            }
            .card(Style.Radius.tile)
            .frame(width: slot.width)
        }
        .buttonStyle(.plain)
    }
}

/// Every scene, to jump to: the portal's Scenes button. Sort and Filter rode
/// at its head for an afternoon (2026-10-09); his pick the same evening put
/// them in Display, so this is the jump and nothing else.
///
/// **Solid, not glass.** A translucent sheet over a list of pictures is a
/// list of words over a list of pictures; that was most of "hard to read".
/// **A round button in the bar under the title** — Display, the pencil,
/// Scenes. 36 points: the row is smaller than it was (his note, 2026-10-09,
/// "make sure it's not a waste of space") and still a fair tap.
struct BarCircle: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color(.label))
            .frame(width: 36, height: 36)
            .background(Color(.tertiarySystemFill), in: Circle())
            .contentShape(Circle())
    }
}

/// **Display: how the shot list looks** — his pick, 2026-10-09
/// (`design/42-one-home`). Picture Size, Mark Shots, Sort and Filter in one
/// sheet; each was in two places before (Settings and the View menu, the
/// filter button and the Scenes sheet).
struct DisplaySheet: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    /// It sizes List and Storyboard alike (his ask, 2026-10-07: "I need
    /// options since the screen is small").
    @AppStorage(FrameSize.key) private var frameSize = FrameSize.full.rawValue
    @AppStorage(MarkingShots.key) private var marks = ""
    @State private var renumbering = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Picture Size", selection: $frameSize) {
                        ForEach(FrameSize.allCases) { Text($0.name).tag($0.rawValue) }
                    }
                    .pickerStyle(.menu)
                    Toggle("Mark Shots", isOn: Binding(
                        get: { MarkingShots.showing(choice: marks, shootDay: session.isShootDay) },
                        set: { marks = MarkingShots.choose($0) }))
                    // **Columns on the shot list's own bar** (the Mac's,
                    // back 2026-10-16), and the Working Aspect Ratio when
                    // the spec sheet gives more than one.
                    NavigationLink {
                        ColumnsView().environmentObject(session)
                    } label: {
                        LabeledContent("Columns") { Text("\(session.columns.filter(\.visible).count) Shown") }
                    }
                    .accessibilityIdentifier("display.columns")
                    if let frames = session.view?.project.frames, frames.count > 1 {
                        Picker("Aspect Ratio", selection: Binding(
                            get: { session.view?.project.frame ?? "" },
                            set: { session.pickFrame($0) })) {
                            ForEach(frames) { f in Text(f.said).tag(f.name) }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("display.aspect")
                    }
                }
                .listRowBackground(Style.card)

                Section {
                    Menu { SortChoices() } label: {
                        LabeledContent { Text(session.sortName) } label: {
                            Text("Sort").foregroundStyle(Color(.label))
                        }
                    }
                    .accessibilityIdentifier("display.sort")
                    // The Mac's *Read in order of*: how the scenes run, as
                    // against how the shots in them are sorted.
                    Picker("Scene Order", selection: $session.sceneOrder) {
                        ForEach(Session.SceneOrder.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("display.sceneorder")
                    Menu { FilterChoices() } label: {
                        LabeledContent {
                            Text(session.filterCount > 0 ? "\(session.filterCount) On" : "Off")
                        } label: {
                            Text("Filter").foregroundStyle(Color(.label))
                        }
                    }
                    .accessibilityIdentifier("display.filter")
                    if session.narrowed || session.sorted || session.sceneOrder != .script {
                        Button("Clear Sort and Filter", role: .destructive) { session.clearSortAndFilter() }
                            .accessibilityIdentifier("display.clear")
                    }
                } footer: {
                    if session.narrowed { narrowing }
                }
                .listRowBackground(Style.card)

                // **The scene list's own tools** (the Mac's scene menu).
                Section("Scenes") {
                    Toggle("Show Archived Scenes (\(session.archivedCount))", isOn: $session.showArchived)
                        .disabled(session.archivedCount == 0 && !session.showArchived)
                        .accessibilityIdentifier("display.archived")
                    Button("Sort Scenes by Number") { session.sortScenesByNumber() }
                    if session.isCommercial {
                        Button("Renumber in Order…") { renumbering = true }
                    }
                    Button("Settle Times of Day") { session.settleTimesOfDay() }
                }
                .listRowBackground(Style.card)
            }
            .confirmationDialog("Renumber every scene in list order?", isPresented: $renumbering,
                                titleVisibility: .visible) {
                Button("Renumber") { session.renumberScenes() }
                Button("Cancel", role: .cancel) {}
            }
            .scrollContentBackground(.hidden)
            .background(Style.page)
            .navigationTitle("Display")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // **Undo and Redo, whatever the screen** (⌘Z on the Mac).
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { _ = session.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .accessibilityLabel("Undo")
                    Button { _ = session.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                        .accessibilityLabel("Redo")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    /// What is narrowing the list, each a chip that takes itself off, and
    /// what is left.
    private var narrowing: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(session.facets.sorted { $0.key < $1.key }, id: \.key) { field, value in
                        chip(session.facetLabel(value, in: field)) { session.facet(field, is: "") }
                    }
                    if session.hideStruck {
                        chip("Hide Shot") { session.hideStruck = false }
                    }
                    if !session.search.isEmpty {
                        chip("“\(session.search)”") { session.search = "" }
                    }
                }
            }
            if let filter = session.view?.filter {
                Text(filter.hiddenScenes > 0
                     ? "\(filter.shown) shots · \(filter.hiddenScenes) scene\(filter.hiddenScenes == 1 ? "" : "s") hidden"
                     : "\(filter.shown) shots")
                    .font(.footnote)
                    .foregroundStyle(Style.ink2)
            }
        }
        .padding(.top, 6)
    }

    private func chip(_ text: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 5) {
                Text(text).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(Color(.label))
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(Color.orange.opacity(0.18), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(text)")
    }
}

private struct SceneJump: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    let go: (Engine.Scene) -> Void
    /// **Several scenes at once** (the Mac's): picked here, then one change.
    @State private var picking = false
    @State private var picked: Set<String> = []
    @State private var archiving = false

    private var chosen: [Engine.Scene] { session.shownScenes.filter { picked.contains($0.id) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if session.shownScenes.isEmpty {
                        Text("Nothing matches")
                            .font(.kitRow)
                            .foregroundStyle(Style.ink3)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                    } else {
                        LazyVStack(spacing: 0) {
                            let scenes = session.shownScenes
                            ForEach(Array(scenes.enumerated()), id: \.element.id) { index, scene in
                                row(scene)
                                if index < scenes.count - 1 {
                                    Divider().padding(.leading, 64)
                                }
                            }
                        }
                        .card(Style.Radius.list)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .background(Style.page)
            .leadingTitle("Scenes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !session.isReadOnly {
                        Button(picking ? "Cancel" : "Select") { picking.toggle(); picked = [] }
                            .accessibilityIdentifier("scenes.select")
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { if picking { bar } }
            .confirmationDialog("Archive \(picked.count) scene\(picked.count == 1 ? "" : "s")?", isPresented: $archiving, titleVisibility: .visible) {
                Button("Archive", role: .destructive) {
                    for scene in chosen { session.archive(scene, true) }
                    picked = []
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationBackground(Style.page)
    }

    /// What the picked scenes can have done to them, all at once.
    private var bar: some View {
        HStack(spacing: 10) {
            Text("\(picked.count) Selected").font(.kitRowStrong)
            Spacer()
            Menu("Change") {
                Menu("Shoot Day") {
                    Button("None") { for s in chosen { session.assign(scene: s.id, toDay: nil) } }
                    ForEach(session.days) { d in
                        Button(d.label) { for s in chosen { session.assign(scene: s.id, toDay: d.id) } }
                    }
                }
                Menu("Time of Day") {
                    ForEach(TimeOfDay.all + ["CONTINUOUS"], id: \.self) { t in
                        Button(t) { for s in chosen { session.setScene(s.id, "time_of_day", to: t) } }
                    }
                }
                Menu("Add Place") {
                    ForEach(session.locations) { place in
                        Button(place.fullName?.isEmpty == false ? place.fullName! : place.name) {
                            for s in chosen where !s.locations.contains(place.id) { session.link(scene: s.id, toLocation: place.id) }
                        }
                    }
                }
                if session.manyShoots {
                    Menu("Move to Shoot") {
                        ForEach(session.shoots) { shoot in
                            Button(shoot.label) { for s in chosen { session.moveScene(s, toShoot: shoot) } }
                        }
                    }
                }
                Divider()
                Button("Archive…", role: .destructive) { archiving = true }
            }
            .font(.kitRowStrong)
            .disabled(picked.isEmpty)
            .accessibilityIdentifier("scenes.change")
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.bar)
    }

    private func row(_ scene: Engine.Scene) -> some View {
        let commercial = session.isCommercial && !scene.title.isEmpty
        let count = session.rows(inScene: scene.id).count
        return Button {
            if picking {
                if picked.contains(scene.id) { picked.remove(scene.id) } else { picked.insert(scene.id) }
            } else {
                go(scene)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                if picking {
                    Image(systemName: picked.contains(scene.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(picked.contains(scene.id) ? Color.accentColor : Style.ink3)
                        .padding(.top, 2)
                }
                Text(scene.number)
                    .font(.system(size: 20, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color(.label))
                    .frame(width: 40, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        TimeDot(said: scene.timeOfDay)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        Text(commercial ? scene.title : scene.heading)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(.label))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Text(count == 1 ? "1 shot" : "\(count) shots")
                        .font(.system(size: 13))
                        .foregroundStyle(Style.ink2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Style.ink3)
                    .padding(.top, 5)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("scenes.row")
    }
}


extension Session {
    /// **Today is one of the film's shoot days** — what brings the Shot marks
    /// out by themselves.
    var isShootDay: Bool {
        let today = MarkingShots.today
        return days.contains { $0.date == today }
    }
}
