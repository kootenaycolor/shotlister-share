import SwiftUI
import UniformTypeIdentifiers

/// **The schedule, on the phone** — the fourth thing the Mac has and the phone
/// did not.
///
/// A day is a lane and a scene on it is a strip, exactly as the Mac's board
/// draws them, because both read the same answer from the engine. A scene split
/// across two days is two strips, each saying how many of its shots fall here
/// and where the rest of it runs.
///
/// **Two views, because there are two jobs.** His instruction, 2026-08-30:
/// *"there needs to be an easier way to schedule scenes on mobile and tapping a
/// scene doesn't need to open it."*
///
/// - **Days** answers the question a set asks: *what are we shooting today.*
///   Tapping a strip no longer opens the scene — it offers the days, and one
///   more tap moves it. No sheet, no push, no going back.
/// - **Plan** is for laying a film out in one sitting: pick a day along the top
///   and tap scenes onto it, one tap each, in script order. It is the fastest
///   this can be on a phone, and it is where dragging a card around a board
///   would have been the wrong answer.
///
/// **And a third, for the day itself.** His ask, 2026-09-16: *"see it
/// organized by day, with the shots I'm shooting that day … fade them out in
/// a very simple, easy action so that I know what I've shot and what I have
/// coming up … manually drag around the order of the shots … just for my own
/// sanity on a shoot day."*
///
/// - **Shoot** is each day as a flat run of shots, in the order the day runs
///   them. Tap a shot and it fades — the engine's *struck*, which its own
///   words define as *we got this*. Hold and drag to put the day in the order
///   he wants. Nothing here schedules; that is the other two.
struct ScheduleView: View {
    @EnvironmentObject private var session: Session

    enum Mode: String, CaseIterable, Identifiable {
        case shoot = "Shoot"
        case days = "Days"
        case plan = "Plan"
        var id: String { rawValue }
    }

    @AppStorage("schedule.mode") private var mode: Mode = .shoot

    @State private var renaming: Engine.Lane?
    @State private var newName = ""
    @State private var dating: Engine.Lane?
    @State private var pickedDate = Date()
    @State private var removing: Engine.Lane?
    /// The day being filled in, in Plan.
    @State private var filling: String?
    /// Whether the Shoot list is showing its drag handles.
    @State private var ordering: EditMode = .inactive

    private var schedule: Engine.Schedule { session.schedule }
    @State private var calendar = false

    /// A day whose scenes are all archived is shot out: folded away at the
    /// foot of Days until asked for, and not offered as somewhere to go.
    @State private var showShotDays = false
    /// Waiting scenes opened to show their shots still on no day.
    @State private var openWaiting: Set<String> = []
    /// Where a long-press drag would land now: `day|scene` (ahead of that
    /// strip) or `day|` (the day itself, last) — drawn as a line or a glow.
    @State private var target: String?
    /// A scene opened from a strip (the Mac's Open Scene).
    @State private var openScene: Engine.Scene?
    private var shotOut: [Engine.Lane] { schedule.days.filter(\.wrapped) }
    private var shownDays: [Engine.Lane] {
        showShotDays ? schedule.days : schedule.days.filter { !$0.wrapped }
    }
    private var openDays: [Engine.Lane] { schedule.days.filter { !$0.wrapped } }

    var body: some View {
        Group {
            if schedule.days.isEmpty && schedule.unscheduled.isEmpty {
                ContentUnavailableView {
                    Label("No shoot days yet", systemImage: "calendar")
                } actions: {
                    Button("Add Shoot Day") { session.addDay() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                switch mode {
                case .shoot: shoot
                case .days: days
                case .plan: plan
                }
            }
        }
        // **The one-app look** (Ref 1582, design/33-one-app): the grey page,
        // the name on the left, and the three views a glass switch under it,
        // the way the Shot List's List | Storyboard sits.
        .background(Style.page)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !(schedule.days.isEmpty && schedule.unscheduled.isEmpty) {
                HStack {
                    GlassSegments(options: Mode.allCases.map { ($0, $0.rawValue) }, selection: $mode)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 6)
            }
        }
        .leadingTitle("Schedule")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // On the day, the one thing this bar needs is the handles;
                // adding a day belongs to the other two views.
                if mode == .shoot {
                    Button {
                        withAnimation { ordering = ordering.isEditing ? .inactive : .active }
                    } label: {
                        if ordering.isEditing {
                            Text("Done")
                        } else {
                            Label("Reorder", systemImage: "arrow.up.arrow.down")
                        }
                    }
                } else {
                    Button { session.addDay() } label: { Label("Add Shoot Day", systemImage: "plus") }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if mode != .shoot {
                    Button { calendar = true } label: { Label("Calendar", systemImage: "calendar") }
                        .accessibilityIdentifier("schedule.calendar")
                }
            }
        }
        // Asked for only while this screen is up: the board walks every
        // placement in the film, and no other screen reads it.
        .onAppear {
            session.watchingSchedule = true
            if filling == nil { filling = openDays.first?.id }
        }
        .onDisappear { session.watchingSchedule = false }
        .alert("Name Day", isPresented: Binding(get: { renaming != nil },
                                                     set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) { renaming = nil; newName = "" }
            Button("Save") {
                let lane = renaming
                let named = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                renaming = nil
                newName = ""
                if let lane { session.renameDay(lane.id, to: named) }
            }
        }
        .sheet(item: $openScene) { scene in
            NavigationStack { SceneDetailView(id: scene.id) }.environmentObject(session)
        }
        .sheet(isPresented: $calendar) {
            ShootCalendarSheet().environmentObject(session).presentationDetents([.medium, .large])
        }
        .sheet(item: $dating) { lane in
            DatePickerSheet(lane: lane, chosen: $pickedDate) { written in
                session.setDay(lane.id, date: written)
                dating = nil
            }
        }
        .confirmationDialog("Remove \(removing?.label ?? "this day")?",
                            isPresented: Binding(get: { removing != nil },
                                                 set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let lane = removing { session.removeDay(lane.id) }
                removing = nil
            }
            Button("Keep", role: .cancel) { removing = nil }
        } message: {
            Text(removing.map { $0.count == 0 ? "" : "Scenes become Not Scheduled" } ?? "")
        }
    }

    // ---- Shoot: the day, shot by shot ---------------------------------------

    private var shoot: some View {
        List {
            ForEach(openDays) { lane in
                Section {
                    ForEach(lane.run) { shot in
                        DayShotRow(shot: shot)
                            .contentShape(Rectangle())
                            .onTapGesture { got(shot) }
                            // **Another day, or off the day** (the Mac's
                            // shooting-order menu).
                            .contextMenu {
                                Menu("Move to Day") {
                                    ForEach(openDays.filter { $0.id != lane.id }) { other in
                                        Button(other.title.isEmpty ? other.label : "\(other.label) · \(other.title)") {
                                            session.shoot(placement: shot.placement, day: other.id)
                                        }
                                    }
                                }
                                Button("Off This Day") { session.shoot(placement: shot.placement, day: nil) }
                                Button("Open Scene") { openScene = session.scene(shot.scene) }
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 12))
                            .listRowBackground(Style.card)
                    }
                    .onMove { from, to in move(from, to, on: lane) }
                    if lane.run.isEmpty {
                        Empty(text: "Nothing on this day")
                    }
                } header: {
                    header(lane, count: lane.run.isEmpty ? "" : "\(lane.got) of \(lane.run.count)")
                }
            }
        }
        .modifier(DayCards())
        .environment(\.editMode, $ordering)
        .onChange(of: mode) { _, _ in ordering = .inactive }
    }

    /// One tap: got it, or not after all. The fade is the whole signal, so it
    /// is animated, and the phone taps back so it registers without looking.
    private func got(_ shot: Engine.DayShot) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.25)) {
            session.strike(shot: shot.shot, !shot.struck)
        }
    }

    /// A drag on the day's list, said to the engine as *this seat goes here*.
    ///
    /// `to` is where the row lands before the lifted one is taken out, which
    /// is how SwiftUI phrases a move; the engine wants the index among the
    /// others once it is out. One shot moves at a time.
    private func move(_ from: IndexSet, _ to: Int, on lane: Engine.Lane) {
        guard let index = from.first, lane.run.indices.contains(index) else { return }
        let landing = to > index ? to - 1 : to
        guard landing != index else { return }
        session.order(placement: lane.run[index].placement, onDayTo: landing)
    }

    // ---- Days: what are we shooting today -----------------------------------

    private var days: some View {
        List {
            ForEach(shownDays) { lane in
                Section {
                    ForEach(Array(lane.strips.enumerated()), id: \.element.id) { at, strip in
                        StripMenu(strip: strip, on: lane.id, days: openDays,
                                  up: at > 0 ? { session.order(scene: strip.scene, onDay: lane.id, before: lane.strips[at - 1].scene) } : nil,
                                  down: at < lane.strips.count - 1 ? {
                                      session.order(scene: strip.scene, onDay: lane.id,
                                                    before: at + 2 < lane.strips.count ? lane.strips[at + 2].scene : nil)
                                  } : nil,
                                  open: { openScene = session.scene(strip.scene) }) { day in
                            // A split scene moves only this day's part.
                            session.put(scene: strip.scene, toDay: day, from: lane.id)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 12))
                        .listRowBackground(Style.card)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                session.put(scene: strip.scene, toDay: nil, from: lane.id)
                            } label: {
                                Label("Off the Day", systemImage: "calendar.badge.minus")
                            }
                        }
                    }
                    // **A waiting scene or shot let go between two strips**
                    // lands there: the list opens a gap where it will go.
                    // On the list itself, not on each row — a row's own drop
                    // target never hears a drop inside a list.
                    .onInsert(of: [.plainText]) { index, providers in
                        let before = index < lane.strips.count ? lane.strips[index].scene : nil
                        Self.words(in: providers) { items in _ = drop(items, on: lane.id, before: before) }
                    }
                    if lane.strips.isEmpty {
                        Empty(text: "Nothing on this day")
                            .dropDestination(for: String.self) { items, _ in
                                drop(items, on: lane.id, before: nil)
                            } isTargeted: { on in aim("\(lane.id)|", on) }
                    }
                } header: {
                    // Let go on the day's own line: onto the day, last.
                    header(lane)
                        .padding(4)
                        .background(target == "\(lane.id)|" ? Style.blue.opacity(0.14) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .dropDestination(for: String.self) { items, _ in
                            drop(items, on: lane.id, before: nil)
                        } isTargeted: { on in aim("\(lane.id)|", on) }
                }
            }

            if !schedule.unscheduled.isEmpty {
                Section {
                    ForEach(schedule.unscheduled) { strip in
                        // **What is still on no day.** A scene partly on a day
                        // shows only its remainder here, and putting it on a
                        // day — the menu, or a long-press drag onto a day —
                        // takes only that (his report, 2026-10-17: "Day 3,
                        // 3 left" and no way to put the three anywhere).
                        let opened = openWaiting.contains(strip.scene)
                        StripMenu(strip: strip, on: nil, days: openDays,
                                  remaining: !strip.elsewhere.isEmpty,
                                  shotsOpen: strip.shots.count > 1 ? opened : nil,
                                  toggleShots: {
                                      withAnimation(.snappy(duration: 0.2)) {
                                          if opened { openWaiting.remove(strip.scene) } else { openWaiting.insert(strip.scene) }
                                      }
                                  },
                                  open: { openScene = session.scene(strip.scene) },
                                  carried: true) { day in
                            if let day { session.putRemaining(scene: strip.scene, toDay: day) }
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 12))
                        .listRowBackground(Style.card)
                        .draggable("scene:\(strip.scene)") {
                            DragChip(text: "Scene \(strip.number) · \(strip.count) shot\(strip.count == 1 ? "" : "s")")
                        }
                        if opened {
                            ForEach(strip.shots) { shot in
                                LooseShotRow(shot: shot)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 48, bottom: 0, trailing: 12))
                                    .listRowBackground(Style.card)
                                    .contextMenu {
                                        Menu("Schedule on") {
                                            ForEach(openDays) { lane in
                                                Button(lane.title.isEmpty ? lane.label : "\(lane.label) · \(lane.title)") {
                                                    session.putShots([shot.placement], toDay: lane.id)
                                                }
                                            }
                                        }
                                    }
                                    .draggable("shot:\(shot.placement)") {
                                        DragChip(text: shot.number.isEmpty ? "Shot" : shot.number)
                                    }
                            }
                        }
                    }
                } header: {
                    DayHead(name: "Not Scheduled", date: nil, today: false,
                            count: schedule.unscheduled.count == 1 ? "1 scene" : "\(schedule.unscheduled.count) scenes") {
                        EmptyView()
                    }
                }
            }

            if !shotOut.isEmpty {
                Section {
                    Button(showShotDays ? "Hide Shot Days" : "Show Shot Days (\(shotOut.count))") {
                        withAnimation(.snappy(duration: 0.25)) { showShotDays.toggle() }
                    }
                    .listRowBackground(Style.card)
                }
            }
        }
        .modifier(DayCards())
    }

    /// **A long-press drag let go on a day** — waiting scenes bring only
    /// what is still on no day, shots go by themselves. One engine call each,
    /// so one undo.
    private func drop(_ items: [String], on day: String, before: String?) -> Bool {
        target = nil
        let scenes = items.compactMap { $0.hasPrefix("scene:") ? String($0.dropFirst(6)) : nil }
        let shots = items.compactMap { $0.hasPrefix("shot:") ? String($0.dropFirst(5)) : nil }
        guard !scenes.isEmpty || !shots.isEmpty else { return false }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.snappy(duration: 0.25)) {
            for scene in scenes { session.putRemaining(scene: scene, toDay: day, before: before) }
            if !shots.isEmpty { session.putShots(shots, toDay: day, before: before) }
        }
        return true
    }

    /// The words a drop carried, read off its item providers — handed back on
    /// the main queue once every one has been read.
    static func words(in providers: [NSItemProvider], then: @escaping ([String]) -> Void) {
        var found: [String] = []
        let group = DispatchGroup()
        for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
            group.enter()
            _ = provider.loadObject(ofClass: NSString.self) { item, _ in
                if let text = item as? String { DispatchQueue.main.async { found.append(text) } }
                group.leave()
            }
        }
        group.notify(queue: .main) { then(found) }
    }

    /// One place lit at a time, whichever the finger is over now.
    private func aim(_ spot: String, _ on: Bool) {
        if on { target = spot } else if target == spot { target = nil }
    }

    /// A day's own line. The count is the day's shots unless the screen has a
    /// better one to say — the Shoot list says how many are got.
    private func header(_ lane: Engine.Lane, count: String? = nil) -> some View {
        let said: String = {
            if let count { return count }
            return lane.count > 0 ? "\(lane.count) shot\(lane.count == 1 ? "" : "s")" : ""
        }()
        return DayHead(name: lane.title.isEmpty ? lane.label : "\(lane.label) · \(lane.title)",
                       date: lane.said, today: lane.isToday, count: said) {
            Menu {
                Button { newName = lane.title; renaming = lane } label: {
                    Label("Name Day…", systemImage: "pencil")
                }
                Button { pickedDate = lane.when ?? Date(); dating = lane } label: {
                    Label("Set Date…", systemImage: "calendar")
                }
                if !lane.date.isEmpty {
                    Button { session.setDay(lane.id, date: "") } label: {
                        Label("Clear Date", systemImage: "calendar.badge.minus")
                    }
                }
                // **Day order, the Mac's** (its day menu and "Put days in
                // date order"). One step at a time: a day list is short.
                Section {
                    let all = schedule.days.map(\.id)
                    if let at = all.firstIndex(of: lane.id) {
                        if at > 0 {
                            Button { session.moveDay(lane.id, to: at - 1) } label: {
                                Label("Move Earlier", systemImage: "arrow.up")
                            }
                        }
                        if at < all.count - 1 {
                            Button { session.moveDay(lane.id, to: at + 1) } label: {
                                Label("Move Later", systemImage: "arrow.down")
                            }
                        }
                    }
                    if schedule.days.count > 1 {
                        Button { session.sortDaysByDate() } label: {
                            Label("Put Days in Date Order", systemImage: "calendar")
                        }
                    }
                }
                Section {
                    Button(role: .destructive) { removing = lane } label: {
                        Label("Remove Day", systemImage: "trash")
                    }
                }
            } label: {
                SoftRoundLabel(symbol: "ellipsis")
            }
            .springLoadingBehavior(.disabled)
            .accessibilityLabel("Day")
        }
    }

    // ---- Plan: lay the film out ---------------------------------------------

    private var plan: some View {
        List {
            Section {
                ForEach(session.scenes) { scene in
                    Button {
                        tap(scene)
                    } label: {
                        HStack(spacing: 12) {
                            Text(scene.number.isEmpty ? "·" : scene.number)
                                .font(.system(size: 20, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color(.label))
                                .frame(minWidth: 34, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(scene.heading.isEmpty ? scene.description : scene.heading)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color(.label))
                                    .lineLimit(2)
                                if scene.count > 0 {
                                    Text("\(scene.count) shot\(scene.count == 1 ? "" : "s")")
                                        .font(.system(size: 13)).foregroundStyle(Style.ink3)
                                }
                            }
                            Spacer(minLength: 0)
                            mark(scene)
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
                    .listRowBackground(Style.card)
                }
            } header: {
                chips
                    .listRowInsets(EdgeInsets())
                    .textCase(nil)
            }
        }
        .modifier(DayCards())
    }

    /// The days, along the top, as the soft chips the Look's sorts are
    /// (`InkChip`): the one being filled in solid ink.
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(openDays) { lane in
                    Button { filling = lane.id } label: {
                        InkChip(text: lane.count > 0 ? "\(lane.label) · \(lane.count)" : lane.label,
                                on: filling == lane.id)
                    }
                    .buttonStyle(.plain)
                }
                Button { session.addDay() } label: { SoftRoundLabel(symbol: "plus") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add Shoot Day")
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
    }

    /// Whether this scene is already on the day being filled in.
    private func on(_ scene: Engine.Scene) -> Bool {
        guard let filling else { return false }
        return schedule.days.first { $0.id == filling }?
            .strips.contains { $0.scene == scene.id } ?? false
    }

    /// A tick for the day being filled in; otherwise where it does run, if it
    /// runs anywhere. A scene on no day at all says nothing — the absence is
    /// the fact.
    @ViewBuilder
    private func mark(_ scene: Engine.Scene) -> some View {
        if on(scene) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color(.label))
        } else if scene.count == 0 {
            // The Mac's marks: a scene with no shots says so.
            Text("No shots")
                .font(.system(size: 13))
                .foregroundStyle(Style.ink3)
        } else if !scene.day.isEmpty {
            Text(scene.day)
                .font(.system(size: 13))
                .foregroundStyle(Style.ink3)
        } else {
            Image(systemName: "circle")
                .font(.system(size: 20))
                .foregroundStyle(Color(.quaternaryLabel))
        }
    }

    /// One tap puts the scene on the day, or takes it off again.
    private func tap(_ scene: Engine.Scene) {
        guard let filling else { return }
        session.assign(scene: scene.id, toDay: on(scene) ? nil : filling)
    }
}

/// One shot on the day, as the Shoot list draws it: the mockup's one-line
/// row (`.srow`), its frame, its number and title, its description under;
/// struck once it is got, the way a got shot is struck everywhere.
private struct DayShotRow: View {
    let shot: Engine.DayShot

    var body: some View {
        // A day mixes scenes, so the line under says which (the mockup's
        // `.sscene`); the title, else the description, beside the number.
        ShotLine(number: shot.number, title: shot.title.isEmpty ? shot.description : shot.title,
                 under: shot.heading, frame: shot.frame, struck: shot.struck)
    }
}

/// **A shot on one line** (the mockup's `.srow`, Shooting Order section 3):
/// a small frame, the number bold and the title after it, one grey line
/// under. Struck is the mockup's: the words crossed through and greyed, the
/// frame faded.
struct ShotLine: View {
    let number: String
    let title: String
    let under: String
    let frame: Engine.Frame?
    var struck = false

    var body: some View {
        HStack(spacing: 12) {
            FrameThumbnail(frame: frame, side: 64)
                .opacity(struck ? 0.55 : 1)
            VStack(alignment: .leading, spacing: 3) {
                (Text(number.isEmpty ? "·" : number).font(.system(size: 15, weight: .bold).monospacedDigit())
                 + Text(title.isEmpty ? "" : "  \(title)").font(.system(size: 15)))
                    .strikethrough(struck)
                    .foregroundStyle(struck ? Style.ink3 : Color(.label))
                    .lineLimit(1)
                if !under.isEmpty {
                    Text(under)
                        .font(.system(size: 13))
                        .foregroundStyle(Style.ink3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityValue(struck ? "Shot" : "")
    }
}

/// **A day's band** over its card (the mockup's `.dayhead`): its name bold,
/// its date in grey, its count small on the right, then its own menu.
private struct DayHead<Menu: View>: View {
    let name: String
    let date: String?
    let today: Bool
    let count: String
    @ViewBuilder var menu: () -> Menu

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // **Today is a mark on the day, and the day keeps its date**
            // (2026-10-07). It used to take the date's place, so the one day
            // he most wants dated was the one without a date on it. The mark
            // wears the film's colour.
            (Text(name).font(.system(size: 20, weight: .bold)).foregroundColor(Color(.label))
             + Text(date.map { "  \($0)" } ?? "").font(.system(size: 20)).foregroundColor(Color(.tertiaryLabel)))
                .lineLimit(1)
            if today {
                Text("Today")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor, in: Capsule())
            }
            Spacer(minLength: 4)
            if !count.isEmpty {
                Text(count)
                    .font(.system(size: 13))
                    .foregroundStyle(Style.ink3)
                    .lineLimit(1)
                    .fixedSize()
            }
            menu()
        }
        .textCase(nil)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 6, trailing: 2))
    }
}

/// **A day with nothing on it is one grey line**, not a card (2026-10-07).
/// A film with nothing scheduled was a wall of white boxes each saying the
/// same four words; four days now fit where three did.
private struct Empty: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Style.ink3.opacity(0.8))
            .padding(.vertical, 1)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 10, trailing: 12))
    }
}

/// **Each day a white card on the grey page** (the mockup's `.daycard`), as
/// the Shot List's Shooting Order draws its days: an inset grouped List, so
/// the drag and the swipes stay.
private struct DayCards: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .listSectionSpacing(10)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListHeaderHeight, 0)
            .contentMargins(.horizontal, 10, for: .scrollContent)
            .contentMargins(.top, 0, for: .scrollContent)
    }
}

/// One scene on one day — or one still waiting for one — and the days it could
/// go to instead.
///
/// **The row is the control.** Tapping it used to push the scene's shots, which
/// is a different job on a different screen; now it offers the days and a
/// second tap moves it. A `Picker` inside a `Menu` draws as a ticked list, so
/// where it is now needs no explaining.
private struct StripMenu: View {
    @EnvironmentObject private var frames: Frames
    @EnvironmentObject private var session: Session
    let strip: Engine.Strip
    /// The day it is on, or nothing when it is waiting.
    let on: String?
    let days: [Engine.Lane]
    /// One place up or down inside its day (the Mac's Move Up / Down).
    var up: (() -> Void)? = nil
    var down: (() -> Void)? = nil
    /// A scene partly on a day already: the day it is put on takes only what
    /// is left, and the menu says so.
    var remaining = false
    /// Whether its shots still on no day are showing, when it has several.
    var shotsOpen: Bool? = nil
    var toggleShots: () -> Void = {}
    var open: () -> Void = {}
    /// **A waiting strip is carried, not tapped into a menu.** A menu row
    /// opens on a press and hold, so a long-press drag could never start
    /// from it; a waiting strip keeps the same choices under a long press
    /// (lift and move to drag instead), and a tap opens its shots.
    var carried = false
    let move: (String?) -> Void
    @AppStorage("schedule.synopsis") private var synopsis = false

    var body: some View {
        if carried {
            row
                .onTapGesture { if shotsOpen != nil { toggleShots() } }
                .contextMenu { items }
        } else {
            menu
        }
    }

    @ViewBuilder private var items: some View {
        if carried {
            Menu(remaining ? "Schedule Remaining on" : "Schedule on") {
                ForEach(days) { lane in
                    Button(lane.title.isEmpty ? lane.label : "\(lane.label) · \(lane.title)") { move(lane.id) }
                }
            }
        }
        Button { open() } label: { Label("Open Scene", systemImage: "film") }
        if let shotsOpen {
            Button { toggleShots() } label: {
                Label(shotsOpen ? "Hide Shots Left" : "Show Shots Left", systemImage: "list.bullet")
            }
        }
        Toggle("Synopsis", isOn: $synopsis)
    }

    private var menu: some View {
        Menu {
            Button { open() } label: { Label("Open Scene", systemImage: "film") }
            if up != nil || down != nil {
                Section {
                    if let up { Button { up() } label: { Label("Move Up", systemImage: "arrow.up") } }
                    if let down { Button { down() } label: { Label("Move Down", systemImage: "arrow.down") } }
                }
            }
            Toggle("Synopsis", isOn: $synopsis)
            Picker("Day", selection: Binding(
                get: { on ?? "" },
                set: { move($0.isEmpty ? nil : $0) }
            )) {
                ForEach(days) { lane in
                    Text(lane.title.isEmpty ? lane.label : "\(lane.label) · \(lane.title)")
                        .tag(lane.id)
                }
                Text("Not scheduled").tag("")
            }
        } label: {
            row
        }
        // **A menu paints its label like a button.** Left alone, every strip in
        // the schedule drew in accent blue and centred itself — a list of links
        // rather than a list of scenes. The row keeps the colour and the
        // alignment a row has.
        .tint(.primary)
        .foregroundStyle(.primary)
        // **A menu opens under a drag held over it** (spring loading) — and
        // then takes the drop for itself, so a waiting scene carried onto a
        // day's strip opened that strip's menu and landed nowhere. Off: the
        // strip is a place to let go, not a door.
        .springLoadingBehavior(.disabled)
    }

    private var row: some View {
        HStack(spacing: 12) {
            Text(strip.number.isEmpty ? "·" : strip.number)
                .font(.system(size: 20, weight: .bold).monospacedDigit())
                .frame(minWidth: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(strip.heading.isEmpty ? strip.location : strip.heading)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text("\(strip.count) shot\(strip.count == 1 ? "" : "s")")
                    if !strip.timeOfDay.isEmpty {
                        TimeDot(said: strip.timeOfDay, side: 6)
                        Text(strip.timeOfDay)
                    }
                    if let run = strip.sequence, !run.isEmpty { Text(run) }
                    // The half of a split scene that is somewhere else. Said
                    // out loud because a day that reads complete and is not is
                    // the whole reason strips exist.
                    ForEach(strip.elsewhere, id: \.self) { other in
                        Text("also \(other)")
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(Style.ink3)
                .lineLimit(1)
                // **Synopsis on the strips** (the Mac's board bar switch).
                if synopsis, let words = session.scene(strip.scene)?.description, !words.isEmpty {
                    Text(words)
                        .font(.system(size: 13))
                        .foregroundStyle(Style.ink2)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
            if strip.frame != nil {
                FrameThumbnail(frame: strip.frame, side: 64)
            }
        }
        .padding(.vertical, 9)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A date for a day, in the calendar rather than as typed digits.
private struct DatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let lane: Engine.Lane
    @Binding var chosen: Date
    let onSave: (String) -> Void

    var body: some View {
        NavigationStack {
            DatePicker("Date", selection: $chosen, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
            .navigationTitle(lane.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(Engine.Lane.written(chosen)) }
                }
            }
        }
    }
}

/// **The calendar** (the Mac's): the shoot days on their dates, a month at
/// a time. Tap an empty date to make a day on it; tap a day, then a date, to
/// move it there.
struct ShootCalendarSheet: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var moving: Engine.Lane?

    private var days: [Engine.Lane] { session.schedule.days }
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.firstWeekday = 1; return c }

    private func lane(on date: Date) -> Engine.Lane? {
        let said = Engine.Lane.written(date)
        return days.first { $0.date == said }
    }

    private var cells: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month),
              let first = cal.date(from: cal.dateComponents([.year, .month], from: month)) else { return [] }
        let lead = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        return Array(repeating: nil, count: lead) + range.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: first) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    Button { month = cal.date(byAdding: .month, value: -1, to: month) ?? month } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(month.formatted(.dateTime.month(.wide).year())).font(.kitRowStrong)
                    Spacer()
                    Button { month = cal.date(byAdding: .month, value: 1, to: month) ?? month } label: { Image(systemName: "chevron.right") }
                }
                .padding(.horizontal, 8)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(Array(cal.veryShortWeekdaySymbols.enumerated()), id: \.offset) { Text($0.element).font(.kitLabel).foregroundStyle(.secondary) }
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                        if let date { cell(date) } else { Color.clear.frame(height: 52) }
                    }
                }
                Text(moving.map { "Moving \($0.label) · tap a date" } ?? "Tap a date to add a day")
                    .font(.kitBody).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(16)
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { if moving != nil { Button("Cancel") { moving = nil } } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .onAppear {
            if let first = days.compactMap(\.when).min(),
               let m = cal.date(from: cal.dateComponents([.year, .month], from: first)) { month = m }
        }
    }

    private func cell(_ date: Date) -> some View {
        let on = lane(on: date)
        let today = cal.isDateInToday(date)
        return Button {
            if let moving {
                if on == nil { session.setDay(moving.id, date: Engine.Lane.written(date)) }
                self.moving = nil
            } else if let on {
                moving = on
            } else {
                let before = Set(days.map(\.id))
                session.addDay()
                if let made = session.schedule.days.first(where: { !before.contains($0.id) }) {
                    session.setDay(made.id, date: Engine.Lane.written(date))
                }
            }
        } label: {
            VStack(spacing: 2) {
                Text("\(cal.component(.day, from: date))")
                    .font(.kitBody.weight(today ? .bold : .regular))
                    .foregroundStyle(Color(.label))
                Text(on.map { $0.label.replacingOccurrences(of: "Day ", with: "D") } ?? " ")
                    .font(.kitLabel.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(RoundedRectangle(cornerRadius: Kit.Radius.control, style: .continuous)
                .fill(on != nil ? Color(.tertiarySystemFill) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: Kit.Radius.control, style: .continuous)
                .stroke(moving?.id == on?.id && on != nil ? Color.accentColor : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

/// One shot of a waiting scene, opened under it — long-press to drag it onto
/// a day by itself, or press and hold for Schedule on.
private struct LooseShotRow: View {
    let shot: Engine.StripShot
    var body: some View {
        HStack(spacing: 10) {
            Text(shot.number.isEmpty ? "·" : shot.number)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
            Text(shot.title)
                .font(.system(size: 14))
                .foregroundStyle(Style.ink2)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// What a long-press drag shows under the finger: `Scene 16 · 3 shots`.
private struct DragChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold).monospacedDigit())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
    }
}
