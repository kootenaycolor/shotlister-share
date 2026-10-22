import SwiftUI
import PhotosUI

/// One shot, open and editable — and the next one a swipe away.
///
/// **The tap count is the design.** Setting a lens used to be: open the shot,
/// open the field, open a sheet, choose, watch the sheet go. Four taps and two
/// screens for one word, one-handed, on a set. Every value the project has ever
/// used is now on screen as a pill and setting one is a single tap.
///
/// Which is also why the shots page across rather than sitting behind the list:
/// the real job is never "change this shot", it is "go through the scene" — and
/// going back out to the list between every shot is the same four taps wearing a
/// different hat.
///
/// The pills, and their formatting, are the Mac's. His instruction, and right:
/// a word in a rounded box is a target a thumb can hit without looking.
struct ShotDetailView: View {
    @EnvironmentObject private var session: Session
    @AppStorage(MarkingShots.key) private var marks = ""
    /// The Shot mark in the bar follows the list's: a shoot day, or his switch.
    private var marking: Bool { MarkingShots.showing(choice: marks, shootDay: session.isShootDay) }

    let sceneId: String
    let heading: String
    @State var showing: String
    /// **Read first, Edit to change** (the mockup's "A Shot"). A checking
    /// run opens straight on the editor with `-ShotEdit 1`.
    @State private var editing = UserDefaults.standard.bool(forKey: "ShotEdit")
    @FocusState private var focus: EditField?
    @State private var picking: EditField?

    /// **The same look as the list, everywhere a shot is opened** (his note,
    /// 2026-10-09: "when I click shots on the script tab, it opens up the old
    /// shot detail page … make sure it opens up the same UI"). Every way into a
    /// shot comes through here: the Script tab, a scene's screen, Shooting
    /// Order, a board. Reading is the opened shot as the list draws it; Edit
    /// turns it into Editing's page for this shot. The next shot in the scene
    /// is still a swipe away.
    var body: some View {
        let rows = session.rows(inScene: sceneId)
        TabView(selection: $showing) {
            ForEach(rows) { row in
                ScrollView {
                    if editing {
                        EditingShot(row: row, focus: $focus) { column in
                            focus = nil
                            picking = EditField(row: row.id, column: column)
                        }
                        .padding(.bottom, 30)
                    } else {
                        ShotCard(row: row) { withAnimation(.snappy) { editing = true } }
                            .padding(.bottom, 30)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .tag(row.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Style.page)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $picking) { field in
            ChoiceSheet(rowId: field.row, field: field.column)
                .environmentObject(session)
                .presentationDetents([.medium, .large])
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(here(in: rows)).font(.footnote.weight(.semibold))
                    Text(editing ? "Editing" : heading)
                        .font(.caption2)
                        .foregroundStyle(editing ? Color.accentColor : .secondary)
                        .lineLimit(1)
                }
            }
            // **Shot is a control in the bar, not a slab across the foot of
            // the page** — his note, 2026-10-07.
            if !editing, marking, let row = rows.first(where: { $0.id == showing }) {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .primaryAction) {
                        ShotMark(on: row.struck) { session.strike(row, !row.struck) }
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .primaryAction) {
                        ShotMark(on: row.struck) { session.strike(row, !row.struck) }
                    }
                }
            }
            if editing {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        focus = nil
                        withAnimation(.snappy) { editing = false }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    /// "34B  ·  2 of 5". Where he is in the scene, said once, so paging past the
    /// end is never a surprise.
    private func here(in rows: [Engine.Row]) -> String {
        guard let index = rows.firstIndex(where: { $0.id == showing }) else { return "" }
        return "\(rows[index].number)   ·   \(index + 1) of \(rows.count)"
    }
}

/// One shot's page.
private struct ShotPage: View {
    @EnvironmentObject private var session: Session
    let row: Engine.Row

    @State private var picked: [PhotosPickerItem] = []
    @State private var pickingFromLibrary = false
    @State private var importing = false
    @State private var adding: String?
    @State private var fresh = ""
    /// The script, opened to tie this shot to a stretch of it.
    @State private var tying = false

    /// Held here rather than read from the row so typing does not fight the
    /// engine's answer coming back on every keystroke.
    @State private var description = ""
    @State private var title = ""
    @State private var notes = ""
    @State private var loaded = ""
    /// Which field he is typing into, so its own answer is never taken out from
    /// under him while the rest catch up.
    @FocusState private var editing: String?

    /// **The project decides what is on this page, and in what order.**
    ///
    /// It used to be a list written here: description above title, title called
    /// "Short name", a Priority field the project did not have, and no way for
    /// a column he deleted on the Mac to disappear. His words: *"the app should
    /// never expect any kind of format will always be true for every project."*
    ///
    /// So the page is the project's own column order, under the same headings
    /// the Mac's table header uses. A column the project does not have is not
    /// here; a column it deletes stops being here.
    ///
    /// **The phone may still make its own call about what to show.** His
    /// ruling, 2026-08-22: *"the phone app can hide its own columns as it
    /// chooses… the point is that the structure is not rigid."* So the Mac's
    /// hidden columns are followed as a sensible default, and where the phone
    /// has a reason it differs — cutting a shot is offered whether or not the
    /// Cut column is showing, because it is a thing you do to a shot rather
    /// than one of its fields.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Lens Stack takes Modifiers and Filters out of the table, not
                // out of the shot: they stay here to pick.
                ForEach(session.view?.columns.filter { $0.visible || $0.own == true } ?? []) { column in
                    field(column)
                }
                if let off = row.offKit {
                    OffSheetRow(off: off).padding(.horizontal, 16)
                }

                // **Cutting a shot is a thing you do to it, not one of its
                // fields**, so it stays whether or not the Cut column is
                // showing — which in every project so far it is not.
                Toggle(cutLabel, isOn: Binding(
                    get: { row.struck },
                    set: { session.strike(row, $0) }
                ))
                .padding(.horizontal, 16)
                .padding(.top, 4)

                Color.clear.frame(height: 60)
            }
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .task { load() }
        .onChange(of: row.id) { _, _ in load() }
        // **Take up the engine's answer when it changes.** These three are held
        // locally while he types, and were only ever read when the shot opened
        // — so a description changed on the Mac never arrived, and the next
        // keystroke here wrote the stale one back over it.
        .onChange(of: mirror) { _, _ in adopt() }
        // **Written as he types.** These three were held here and never sent:
        // the lines that wrote them went in the 2026-08-22 rewrite (c3dc2188),
        // so a title typed on the phone was lost. Found 2026-10-08 building
        // Editing mode. Skipped when the change is the engine's own answer.
        .onChange(of: title) { _, new in if new != row.title { session.set(row, "title", to: new) } }
        .onChange(of: description) { _, new in
            if new != row.description { session.set(row, "description", to: new) }
        }
        .onChange(of: notes) { _, new in if new != row.notes { session.set(row, "notes", to: new) } }
        .sheet(isPresented: $tying) {
            if let id = row.sceneId, let scene = session.scene(id) {
                NavigationStack {
                    AVScriptPane(scene: scene, following: row.id)
                        .navigationTitle("Script")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { tying = false }
                            }
                        }
                }
                .environmentObject(session)
            }
        }
        .photosPicker(isPresented: $pickingFromLibrary, selection: $picked,
                      matching: .any(of: [.images, .videos]))
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .movie],
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                let allowed = url.startAccessingSecurityScopedResource()
                defer { if allowed { url.stopAccessingSecurityScopedResource() } }
                if Engine.Kind(url.pathExtension) == .clip {
                    // Copied while the permission to read it is still held: the
                    // re-encode happens later, by which time this URL is closed.
                    let name = url.lastPathComponent
                    let copy = URL.temporaryDirectory.appending(path: "picked-\(UUID().uuidString)-\(name)")
                    if (try? FileManager.default.copyItem(at: url, to: copy)) != nil {
                        let shot = row.shot
                        Task {
                            await session.attach(clipAt: copy, to: shot, named: name)
                            try? FileManager.default.removeItem(at: copy)
                        }
                    }
                } else if let data = try? Data(contentsOf: url), UIImage(data: data) != nil {
                    session.attach(data, named: url.lastPathComponent, to: row)
                }
            }
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task { await bringIn(items) }
        }
        .alert(session.lensSaid ?? "", isPresented: Binding(get: { session.lensSaid != nil }, set: { if !$0 { session.lensSaid = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .alert("New \(adding ?? "value")", isPresented: Binding(
            get: { adding != nil }, set: { if !$0 { adding = nil } }
        )) {
            TextField("Value", text: $fresh)
            Button("Cancel", role: .cancel) { adding = nil }
            Button("Add") {
                let value = fresh.trimmingCharacters(in: .whitespacesAndNewlines)
                if let field = adding, !value.isEmpty {
                    if field == "camera" {
                        session.addUnit(named: value)
                    } else if field == "sequence" {
                        // Made and put on the scene in one go — a run of the
                        // film nobody is in is not what he asked for.
                        if let made = session.addSequence(named: value),
                           let scene = row.sceneId {
                            session.setSequence(ofScene: scene, to: made.id)
                        }
                    } else {
                        session.set(row, field, to: value)
                    }
                }
                adding = nil
            }
        }
    }

    // ---- the frames ---------------------------------------------------------

    private var frames: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // The column's own name, the way the Mac's header says it, with
                // the count when there is more than one.
                Text(row.stills.count > 1
                     ? "\(imageColumn) (\(row.stills.count))"
                     : imageColumn)
                    .font(.system(size: Kit.Size.label, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Menu { whereFrom } label: {
                    Image(systemName: "plus.circle").font(.footnote)
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)

            if row.stills.isEmpty {
                // **The empty frame is the button.** A shot with nothing on it
                // is mostly empty frame, and reaching past all of it for a
                // small plus in the corner is the wrong shape for a phone.
                Menu { whereFrom } label: {
                    FramePlate(frame: nil, ratio: session.ratio)
                }
                .buttonStyle(.plain)
            } else {
                Gallery(stills: row.stills, ratio: session.ratio, shot: row.shot)
            }
        }
    }

    /// The one list of ways a frame can arrive, so the plus and the empty frame
    /// offer the same thing.
    @ViewBuilder
    private var whereFrom: some View {
        Button { pickingFromLibrary = true } label: {
            Label("Photos Library", systemImage: "photo.on.rectangle")
        }
        Button { importing = true } label: { Label("Files", systemImage: "folder") }
        if !Viewfinders.installed.isEmpty {
            Section("Shoot a Frame") {
                ForEach(Viewfinders.installed) { app in
                    Button { app.open() } label: {
                        Label(app.name, systemImage: "camera.viewfinder")
                    }
                }
            }
        }
    }

    private var cutLabel: String {
        session.view?.columns.first { $0.name == "struck" }?.shown ?? "Shot"
    }

    private var imageColumn: String {
        session.view?.columns.first { $0.name == "image" }?.shown ?? "Storyboard"
    }

    /// The cameras, which are records rather than words.
    ///
    /// Typing "A-Cam" into this field did nothing at all, because the field
    /// takes the id of a camera and a name is not one. So the pills are the
    /// project's cameras, each in the colour it was given — which is how the Mac
    /// tells A-Cam from B-Cam at a glance — and the plus makes one.
    private func cameras(_ column: Engine.Column) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(column.shown)
                    .font(.system(size: Kit.Size.label, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { fresh = ""; adding = "camera" } label: {
                    Image(systemName: "plus.circle").font(.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if session.units.isEmpty {
                Text("No cameras yet")
                    .font(.kitLabel)
                    .foregroundStyle(.tertiary)
            } else {
                Flow {
                    ForEach(session.units) { unit in
                        Button {
                            session.set(row, "camera",
                                        to: row.unit?.id == unit.id ? "" : unit.id)
                        } label: {
                            Pill(text: unit.label,
                                 chosen: row.unit?.id == unit.id,
                                 tint: unit.tint)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 16)
    }

    // ---- where the shot sits ------------------------------------------------

    /// **The shoot day**, picked from the real days, never typed. It was
    /// read only ("Scheduled on the Mac") until his word from set,
    /// 2026-10-06: "can't schedule unscheduled shots on my own". A shot goes
    /// to the end of the day's shooting order; scene, number and letter stay.
    private func scheduled(_ column: Engine.Column) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(column.shown)
                .font(.system(size: Kit.Size.label, weight: .semibold))
                .foregroundStyle(.secondary)
            Menu {
                ForEach(session.pickableDays(keeping: row.dayId)) { day in
                    Button {
                        session.shoot(row, day: day.id, before: nil)
                    } label: {
                        if row.dayId == day.id {
                            Label(day.label, systemImage: "checkmark")
                        } else {
                            Text(day.label)
                        }
                    }
                }
                if !session.days.isEmpty { Divider() }
                Button {
                    session.shoot(row, day: nil, before: nil)
                } label: {
                    if (row.dayId ?? "").isEmpty {
                        Label("Not Scheduled", systemImage: "checkmark")
                    } else {
                        Text("Not Scheduled")
                    }
                }
            } label: {
                if let day = row.day, !day.isEmpty {
                    Pill(text: day, chosen: true, tint: .blue)
                } else {
                    Pill(text: session.days.isEmpty ? "No shoot days yet" : "Not Scheduled",
                         chosen: false, tint: .blue)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 16)
    }

    /// **The sequence.** It hangs on the scene, not on the shot — which is how
    /// the Mac holds it too — so setting it here moves every shot in the scene.
    /// That is worth one line, because it is a cost a label cannot state.
    @ViewBuilder
    private func run(_ column: Engine.Column) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PillField(
                label: column.shown,
                options: session.sequences.map(\.title),
                selected: row.cell("sequence"),
                tint: row.sequenceTint ?? .indigo,
                onChange: { chosen in
                    guard let scene = row.sceneId else { return }
                    let wanted = chosen.first.flatMap { title in
                        session.sequences.first { $0.title == title }
                    }
                    session.setSequence(ofScene: scene, to: wanted?.id ?? "")
                },
                onNew: { fresh = ""; adding = "sequence" }
            )
            Text("The whole scene moves with it")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
    }

    // ---- one column, drawn however the project says it behaves --------------

    @ViewBuilder
    private func field(_ column: Engine.Column) -> some View {
        switch column.name {
        // The three that are not cells in a list: the pictures, the two long
        // texts that are read rather than chosen, and the cut.
        case "image":
            frames
        case "title", "description", "notes":
            writing(column)
        case "camera":
            // A camera is a record with a colour, not a word, so it is chosen
            // from the project's cameras rather than typed.
            cameras(column)
        // Drawn once at the foot of the page whether it is showing or not —
        // see the toggle in `body`.
        case "struck":
            EmptyView()
        // Where a shot sits, rather than what it is — Ref 250. There used to be
        // nothing here at all: the row did not carry either, and a control that
        // could not write would have been worse than the gap. The row carries
        // both now.
        case "day":
            scheduled(column)
        case "sequence":
            run(column)
        // **The stretch of the script this shot quotes** — read here, tied in
        // the script itself, where the words are.
        case "script":
            quoting(column)
        default:
            if column.shape == "check" {
                // A checkmark flips, as on the Mac; it has no list to pick from.
                Toggle(column.shown, isOn: Binding(
                    get: { !row.cell(column.name).isEmpty },
                    set: { session.set(row, column.name, to: $0 ? "1" : "") }
                ))
                .padding(.horizontal, 16)
            } else if column.name.hasPrefix("c_"), column.kind == "text" {
                // **A project's own text column is typed, not picked** —
                // the Mac types it; this page offered a pick-list.
                TypedCell(row: row, column: column.name, label: column.shown)
                    .padding(.horizontal, 16)
            } else {
            PillField(
                label: column.shown,
                options: session.vocabulary(column.name),
                selected: row.cell(column.name),
                multiple: column.shape == "multi",
                tint: tint(column.name),
                onChange: { chosen in
                    session.set(row, column.name, to: chosen.joined(separator: ", "))
                },
                onNew: column.locked == true ? nil : { fresh = ""; adding = column.name }
            )
            .padding(.horizontal, 16)
            }
        }
    }

    /// The words this shot quotes, and the way to the script to change them.
    private func quoting(_ column: Engine.Column) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(column.shown)
                .font(.system(size: Kit.Size.label, weight: .semibold))
                .foregroundStyle(.secondary)
            if row.quotesScript, !row.script.isEmpty {
                Text("“\(row.script)”")
                    .font(.subheadline.italic())
                    .foregroundStyle(.primary)
            } else {
                Text("Nothing quoted")
                    .font(.kitLabel)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 12) {
                Button(row.quotesScript ? "Change…" : "Tie…") { tying = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                if row.quotesScript {
                    Button("Untie") { session.untie(row) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .disabled(session.isReadOnly)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 16)
    }

    /// A column he types into rather than chooses from.
    @ViewBuilder
    private func writing(_ column: Engine.Column) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(column.shown)
                .font(.system(size: Kit.Size.label, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField(column.shown, text: binding(column.name), axis: .vertical)
                .lineLimit(1...8)
                .focused($editing, equals: column.name)
        }
        .padding(.horizontal, 16)
    }

    /// Text is held locally while he types — reading it back from the engine
    /// mid-keystroke would fight the cursor — and written on every change.
    private func binding(_ name: String) -> Binding<String> {
        switch name {
        case "title":       return $title
        case "description": return $description
        default:            return $notes
        }
    }

    /// A colour for the pills, so two fields are not one wall of blue. Only the
    /// built-ins have one; a project's own column takes the accent.
    private func tint(_ name: String) -> Color {
        switch name {
        case "lens", "modifiers", "lens_filters": return .teal
        case "priority": return .pink
        case "tags":     return .purple
        default:         return .accentColor
        }
    }

    /// The three in one value, so one modifier watches all of them.
    private var mirror: String {
        [row.title, row.description, row.notes].joined(separator: "\u{1}")
    }

    private func adopt() {
        if editing != "title", row.title != title { title = row.title }
        if editing != "description", row.description != description { description = row.description }
        if editing != "notes", row.notes != notes { notes = row.notes }
    }

    private func load() {
        guard loaded != row.id else { return }
        loaded = row.id
        description = row.description
        title = row.title
        notes = row.notes
    }

    private func bringIn(_ items: [PhotosPickerItem]) async {
        for item in items {
            // As a file, not as bytes — a clip needs a path and a photograph
            // needs its name. See `Picked`.
            if let file = try? await item.loadTransferable(type: Picked.self) {
                defer { file.discard() }
                if file.isClip {
                    await session.attach(clipAt: file.url, to: row.shot)
                } else if let data = try? Data(contentsOf: file.url) {
                    session.attach(data, named: file.url.lastPathComponent, to: row)
                }
            } else if let data = try? await item.loadTransferable(type: Data.self) {
                session.attach(data, to: row)
            }
        }
        picked = []
    }
}

/// **A shot, read**: the opened shot exactly as the list draws it. The picture
/// beside the words opens the viewer; under them, the script lines it covers,
/// then the labelled pills, the description, the notes, and a small Edit.
struct ShotCard: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var frames: Frames
    let row: Engine.Row
    let edit: () -> Void

    @AppStorage(FrameSize.key) private var frameSize = FrameSize.full.rawValue
    @State private var viewing: Engine.Still?

    private var columns: [Engine.Column] { session.view?.columns ?? [] }
    private var width: CGFloat { (FrameSize(rawValue: frameSize) ?? .full).listWidth }

    private func shows(_ name: String) -> Bool {
        columns.first { $0.name == name }?.visible ?? true
    }

    private var sceneLine: String {
        guard let id = row.sceneId, let scene = session.scene(id) else { return "" }
        let name = session.isCommercial && !scene.title.isEmpty ? scene.title : scene.heading
        return name.isEmpty ? scene.number : "\(scene.number) \u{00B7} \(name)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                FramePlate(frame: row.frame, ratio: session.ratio, board: row.board)
                    .frame(width: width)
                    .opacity(row.struck ? 0.45 : 1)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewing = row.stills.first { $0.key == true } ?? row.stills.first
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("View \(row.number)")
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.number)
                        .font(.system(size: 15, weight: .heavy).monospacedDigit())
                        .foregroundStyle(row.struck ? Style.ink3 : Color(.label))
                        .frame(minHeight: 28, alignment: .leading)
                    if !sceneLine.isEmpty {
                        Text(sceneLine)
                            .font(.system(size: 13))
                            .foregroundStyle(Style.ink3)
                            .lineLimit(2)
                    }
                    if shows("title"), !row.title.isEmpty {
                        Text(row.title)
                            .font(.system(size: 15, weight: .semibold))
                            .strikethrough(row.struck)
                            .foregroundStyle(row.struck ? Style.ink3 : Color(.label))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let words = row.quoted(columns) {
                VStack(alignment: .leading, spacing: 6) {
                    Text((columns.first { $0.name == "script" }?.shown ?? "Script"))
                        .font(.system(size: Kit.Size.label, weight: .semibold))
                        .foregroundStyle(Style.ink3)
                    Text("\u{201C}\(words)\u{201D}")
                        .font(.system(size: 13, design: .monospaced))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 14)
            }
            ShotDetails(row: row, opening: nil, edit: { _ in edit() })
                .padding(.top, 12)
        }
        .padding(12)
        .background(Style.card, in: RoundedRectangle(cornerRadius: Style.Radius.group, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .fullScreenCover(item: $viewing) { still in
            StillViewer(still: still, all: row.stills, onDelete: { session.detach($0) },
                        cropTo: session.ratio)
                .environmentObject(session)
                .environmentObject(frames)
        }
    }
}


/// One of a project's own text columns on a shot's page: held while he
/// types, written when he leaves the field or presses Return.
private struct TypedCell: View {
    @EnvironmentObject private var session: Session
    let row: Engine.Row
    let column: String
    let label: String
    @State private var text = ""
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: Kit.Size.label, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField(label, text: $text, axis: .vertical)
                .lineLimit(1...8)
                .focused($typing)
                .onSubmit(write)
                .onChange(of: typing) { _, now in if !now { write() } }
        }
        .onAppear { text = row.cell(column).joined(separator: ", ") }
        .onChange(of: row.cell(column)) { _, now in if !typing { text = now.joined(separator: ", ") } }
    }

    private func write() {
        let had = row.cell(column).joined(separator: ", ")
        if text != had { session.set(row, column, to: text) }
    }
}


/// **Not on the Spec Sheet** (the Mac flags the lens cell and offers Add
/// to Spec Sheet): what this shot uses that the sheet lacks, one tap each.
struct OffSheetRow: View {
    @EnvironmentObject private var session: Session
    let off: Engine.Row.OffKit

    var body: some View {
        let sheet = session.specSheet
        VStack(alignment: .leading, spacing: 6) {
            Text("Not on Spec Sheet")
                .font(.system(size: Kit.Size.label, weight: .semibold))
                .foregroundStyle(Color(markHex: "D97706"))
            Wrap(spacing: 6) {
                if let lens = off.lens { add(lens) { sheet.add(off, lens: lens) } }
                if let body = off.body { add(body) { sheet.add(off, body: body, label: off.camera ?? "") } }
                ForEach(off.modifiers ?? [], id: \.self) { m in add(m) { sheet.add(off, modifier: m) } }
                ForEach(off.filters ?? [], id: \.self) { f in add(f) { sheet.add(off, filter: f) } }
            }
            if !sheet.said.isEmpty {
                Text(sheet.said).font(.kitLabel).foregroundStyle(.secondary)
            }
        }
    }

    private func add(_ name: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Label("Add \(name)", systemImage: "plus")
                .font(.footnote.weight(.medium))
        }
        .buttonStyle(.bordered)
    }
}
