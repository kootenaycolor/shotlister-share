import AppKit
import SwiftUI

/// **The strip board** — the old app's schedule, brought across.
///
/// Scheduling happens scene by scene, the way a board has always worked: you
/// drag a scene onto a day, not fifteen shots. A scene that will not finish in
/// one day can be split, and then it is two strips that each say where the rest
/// of it is — the case the first prototype could not express at all, and the
/// ordinary one, because a scene rarely finishes in an afternoon.
///
/// **Nothing here is new engine work.** `board`, `scene`, `place` and `day`
/// have been in the bridge since the old app, and `BoardModel` was already
/// decoded in `Engine.swift` waiting for a view. This is that view.
///
/// Text first. Frames are a switch, because this is the one screen that is read
/// as a grid rather than looked at.
struct Schedule: View {
    @ObservedObject var state: ShellState
    @Environment(\.colorScheme) private var scheme

    /// **On `ShellState` rather than here**, so `--synopsis` can reach it. A
    /// control nothing outside the app can press is a control nothing can
    /// check or photograph — the bargain `--daysheet` and `--excellink` strike.
    private var showSynopsis: Bool { state.stripSynopsis }
    /// **What is being carried and where it would land** — one answer for
    /// the whole window, kept by the hand in `ScheduleHands.swift`. His
    /// report, 2026-09-29: dragging "just get stuck, won't come over, start
    /// multi selecting". The board draws from this and nothing else, so two
    /// places can never light at once and a drop always goes where the line
    /// is.
    @ObservedObject private var hands = BoardHands.shared
    /// A day whose scenes are all archived is shot out: it is folded away
    /// at the foot of the list until asked for.
    @State private var showShotDays = false
    /// True in the window of its own, which has no shell around it to draw
    /// the carried thing under the pointer.
    var standalone = false
    /// Which strips are open, on `ShellState` so `--openstrip` can reach
    /// them: the chevron is the only way to see a scene's synopsis, and a
    /// thing no check can open is a thing no check can photograph.
    private var opened: Set<String> { state.openStrips }
    /// Which day band's menu is open, so the sheets below can find their lane.
    /// The day itself is held on `ShellState` — see `namingDay`.
    private var naming: Binding<BoardModel.Lane?> { lane(\.namingDay) }
    private var dating: Binding<BoardModel.Lane?> { lane(\.datingDay) }

    /// **Pulled out of the `.sheet` call on purpose**, the same lesson
    /// `boardBeingRenamed` in `Shell.swift` records: written inline, a binding
    /// like this puts the view body past the type-checker's budget and the file
    /// stops compiling with a message that names no cause.
    private func lane(_ key: ReferenceWritableKeyPath<ShellState, String?>)
        -> Binding<BoardModel.Lane?> {
        Binding(
            get: {
                let days = state.stripBoard?.days ?? []
                return days.first { $0.id == state[keyPath: key] }
            },
            set: { state[keyPath: key] = $0?.id }
        )
    }

    private var dark: Bool { scheme == .dark }

    var body: some View {
        // The same construction as the main window: floating glass panels on
        // one continuous ground, air on all sides, and the content between.
        // This screen wore the old flat chrome long after the shell moved on,
        // and it read as a different program.
        HStack(spacing: 0) {
            days
            if state.calendarShown {
                calendarGrab
                ScheduleCalendar(state: state)
                    .floatingGlass(dark)
                    .frame(width: state.calendarWidth)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeOut(duration: 0.2), value: state.calendarShown)
        .background(Brand.surface(dark))
        .overlay { if standalone { BoardGhost() } }
        // Asked for again on every appearance rather than cached: the day cell
        // in the table can move a scene while this screen is not showing, and
        // the engine is the only thing that knows where anything is.
        .onAppear { state.loadBoard() }
        .sheet(item: naming) { NameDay(state: state, day: $0) }
        .sheet(item: dating) { DateDay(state: state, day: $0) }
    }

    /// The calendar's handle — the side panel's grab, cloned for this window:
    /// nothing to see, nine points to catch, and the drag owned by AppKit for
    /// the reasons written on `DividerGrab`.
    private var calendarGrab: some View {
        Color.clear
            .frame(width: 1)
            .overlay { CalendarGrab(state: state).frame(width: 9) }
    }

    // ------------------------------------------------------------- the days

    private var days: some View {
        VStack(spacing: 0) {
            boardBar
            lanes
        }
    }

    /// **Synopsis is off by default**: this screen is read as a grid, and a
    /// paragraph under every strip is a different screen. The button is here
    /// because when you are deciding what can move, what the scene *is*
    /// matters more than anything else on the row.
    ///
    /// It replaced a *Frames* switch — his instruction, 2026-08-30. Frames put
    /// each scene's key picture on its strip, which in a film with no pictures
    /// on its scenes is a switch that does nothing; the synopsis is the thing
    /// he actually reaches for. The control changed shape with it: an AppKit
    /// switch was the only one of its kind in this app, and the two controls
    /// standing side by side in this bar now match each other and the chrome
    /// everywhere else — a `ToolButton`, lit in the accent when it is on.
    private var boardBar: some View {
        HStack(spacing: 12) {
            if !state.stripRun {
                BarToggle(icon: "text.alignleft", text: "Synopsis", on: state.stripSynopsis) {
                    withAnimation(.easeOut(duration: 0.15)) { state.stripSynopsis.toggle() }
                }
            }
            BarToggle(icon: "list.number", text: "Shooting Order", on: state.stripRun) {
                withAnimation(.easeOut(duration: 0.15)) { state.stripRun.toggle() }
            }
            BarToggle(icon: "calendar", text: "Calendar", on: state.calendarShown) {
                withAnimation(.easeOut(duration: 0.2)) { state.calendarShown.toggle() }
            }
            Spacer()
            // The affordance *is* the condition: the button exists exactly
            // while the day numbers and the dates disagree, and one press is
            // the whole of it. His ruling, 2026-08-28.
            if state.daysOutOfDateOrder {
                Button("Put days in date order") { state.sortDaysByDate() }
                    .buttonStyle(.capsule)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    private var lanes: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    let board = state.stripBoard?.days ?? []
                    let shotOut = board.filter { $0.wrapped == true }
                    ForEach(board.filter { $0.wrapped != true }) { day in
                        dayCard(day)
                    }
                    if !shotOut.isEmpty {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { showShotDays.toggle() }
                        } label: {
                            Text(showShotDays ? "Hide Shot Days" : "Show Shot Days (\(shotOut.count))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Brand.ink3(dark))
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        if showShotDays {
                            ForEach(shotOut) { day in
                                dayCard(day)
                            }
                        }
                    }
                    Button {
                        state.addDay()
                    } label: {
                        PlusLabel(text: "Add shoot day", dark: dark)
                    }
                    .buttonStyle(.rowAction)
                    .padding(.vertical, 10)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                // Where a held scene may be let go, and the column that
                // scrolls when one is held at its edge.
                .boardMark(.board)
            }
            // The calendar's click lands here: scroll to the day it named,
            // flash its card, and let the flash clear itself.
            .onChange(of: state.highlightedDay) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .task(id: state.highlightedDay) {
                guard state.highlightedDay != nil else { return }
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                state.highlightedDay = nil
            }
        }
    }

    /// One day as one rounded card — the band and its strips together, which
    /// is what makes this screen read as the shell's family rather than as a
    /// flat grid. The card is also what the calendar's highlight lights up.
    private func dayCard(_ day: BoardModel.Lane) -> some View {
        // Lit by the calendar's click, or by a scene held over it — the same
        // glow, because both mean "this day".
        let lit = state.highlightedDay == day.id || hands.lights(day: day.id)
        let shape = RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
        let days = state.stripBoard?.days ?? []
        let place = days.firstIndex { $0.id == day.id } ?? 0
        return VStack(spacing: 0) {
            dayBand(day)
            lane(day)
        }
        // The card is chrome, not content: a tone up from the window in the
        // dark rather than the same near-black, so the strips inside it read
        // as wells and the card reads as an object.
        .background(Brand.surface2(dark), in: RoundedRectangle(cornerRadius: Brand.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
                .strokeBorder(Brand.glassEdge(dark), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Brand.radius, style: .continuous))
        // **The whole card is where a scene is let go** — band, strips, the
        // air under the last one, the "Nothing on this day" of an empty day.
        .boardMark(.card(day: day.id))
        .shadow(color: Brand.glassLine(dark).opacity(dark ? 0.5 : 0.55),
                radius: dark ? 10 : 8, y: 2)
        .overlay {
            if lit {
                shape.fill(Brand.accent(dark).opacity(0.08))
                    .overlay { shape.strokeBorder(Brand.accent(dark), lineWidth: 1.5) }
                    .allowsHitTesting(false)
            }
        }
        // A day held over the board goes where the line is: above this card,
        // or — under the last one — to the end.
        .overlay(alignment: .top) {
            // In the gap above the card — or, above the first, inside the
            // column's 4 points of top air, which is all the room there is.
            if hands.spot == .dayAt(place) { dayLine.offset(y: place == 0 ? -3 : -6) }
        }
        .overlay(alignment: .bottom) {
            if place == days.count - 1, hands.spot == .dayAt(days.count) { dayLine.offset(y: 6) }
        }
        .opacity(hands.holds(day: day.id) ? 0.45 : 1)
        .frame(maxWidth: Self.boardWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(day.id)
    }

    private func lane(_ day: BoardModel.Lane) -> some View {
        VStack(spacing: 4) {
            if state.stripRun {
                ForEach(Array(day.run.enumerated()), id: \.element.id) { at, shot in
                    runRow(shot, in: day, at: at)
                }
            } else {
                ForEach(Array(day.strips.enumerated()), id: \.element.id) { at, strip in
                    row(strip, in: day, at: at)
                }
            }
            if day.strips.isEmpty {
                Text("Nothing on this day")
                    .sans(11)
                    .foregroundStyle(Brand.ink4(dark))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A strip is read across, not stretched across a 27-inch screen.
    private static let boardWidth: CGFloat = 1000

    /// The kinds of time of day on a set of strips, one dot each, in the order
    /// they first appear. The same `timeKey` truth the sidebar's dot draws
    /// from — and `--daydots` reads this exact function, so what the check
    /// says is what the band shows.
    static func dotKeys(_ strips: [BoardModel.Strip]) -> [String] {
        var seen: [String] = []
        for strip in strips {
            if let key = Brand.timeKey(strip.timeOfDay), !seen.contains(key) {
                seen.append(key)
            }
        }
        return seen
    }

    private func dayBand(_ day: BoardModel.Lane) -> some View {
        let keys = Self.dotKeys(day.strips)
        // **The day head in the label idiom** — "Day 1" semibold sans, the
        // date beside it in third-rank ink. No typewriter. 2026-09-14.
        return HStack(spacing: 8) {
            Text(day.label).sans(Brand.Size.body, weight: .semibold).monospacedDigit()
            if !day.title.isEmpty {
                Text(day.title).sans(Brand.Size.small, weight: .medium)
                    .foregroundStyle(Brand.ink2(dark))
            }
            if !day.date.isEmpty {
                // The engine stores `YYYY-MM-DD`, because that is the form
                // `lettering.rs` compares to decide the morning prep ends. It
                // is not the form anybody reads a callsheet in, so the day band
                // says it the way a person would — and anything that is not a
                // date is drawn exactly as it was stored rather than dropped.
                Text(Self.said(day.date)).sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark))
            }
            Spacer()
            // **What the day is made of, at a glance** — one mark per kind of
            // time of day on it, so a night scene buried in an afternoon reads
            // from across the board. His pick, 2026-08-28; drawn as the same
            // edges the strips below wear rather than as dots, his instruction
            // of 2026-08-29, so the board has one language for one fact.
            if !keys.isEmpty {
                HStack(spacing: 4) {
                    ForEach(keys, id: \.self) { key in
                        Circle()
                            .fill(Brand.timeKeyInk(key, dark))
                            .frame(width: 5, height: 5)
                    }
                }
                .padding(.trailing, 2)
            }
            Text("\(day.count) \(day.count == 1 ? "shot" : "shots")")
                .sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark))
        }
        .foregroundStyle(Brand.ink(dark))
        .padding(.horizontal, 14)
        .frame(height: 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A tone above the card it heads, so the three layers — window, card,
        // band — are told apart by their own colour rather than by hairlines.
        .background(Brand.panel(dark))
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.rule2(dark)).frame(height: 0.5) }
        .contextMenu {
            Button("Name…") { state.namingDay = day.id }
            Button("Set date…") { state.datingDay = day.id }
            Divider()
            Button("Remove day") { remove(day) }
        }
        // **The band is the handle.** Ref 342 — `moveDay` had been finished in
        // the engine and the bridge since the old app and nothing called it, so
        // days were stuck in the order they were made. Dragging a band is the
        // same gesture as dragging a strip; the hand knows which it holds.
        //
        // The strips inside a day are *not* draggable as a day: a lane full of
        // scenes you can already pull out one at a time would be two meanings
        // for one grab.
        .boardMark(.band(day: day.id))
    }

    // ---------------------------------------------------------- a day itself

    /// `2026-09-12` as `Fri 12 Sep`. Anything that will not parse comes back
    /// untouched, so a date typed in by hand before this existed still shows.
    static func said(_ stored: String) -> String {
        let iso = DateFormatter()
        iso.calendar = Calendar(identifier: .gregorian)
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.dateFormat = "yyyy-MM-dd"
        guard let date = iso.date(from: stored) else { return stored }
        let out = DateFormatter()
        out.dateFormat = "EEE d MMM"
        return out.string(from: date)
    }

    /// **The day goes and the shots stay.** Same bargain as deleting a
    /// location: the thing pointed at goes, and everything that pointed at it
    /// keeps all of its own. Said out loud rather than asked as a yes/no,
    /// because a person deleting Day 2 of a schedule wants to know where its
    /// scenes went before they press it, not after.
    private func remove(_ day: BoardModel.Lane) {
        let alert = NSAlert()
        alert.messageText = "Remove \(day.label)?"
        var cost: [String] = []
        if day.count > 0 {
            cost.append("\(day.count) shot\(day.count == 1 ? "" : "s") on it keep everything of their own. They go back to waiting.")
        }
        cost.append("The days after it come up a number.")
        alert.informativeText = cost.joined(separator: "\n\n")
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        state.removeDay(day.id)
    }

    private func row(_ strip: BoardModel.Strip, in day: BoardModel.Lane, at: Int) -> some View {
        StripRow(strip: strip,
                 day: day.id,
                 state: state,
                 hands: hands,
                 dark: dark,
                 showSynopsis: showSynopsis,
                 open: opened.contains(strip.scene),
                 onToggle: { toggle(strip.scene) },
                 onInspect: { inspect(strip.scene) },
                 synopsis: synopsis(strip.scene))
            // **Picked up by a press and a pull; a click is still a click.**
            // The hand (`ScheduleHands.swift`) reads where this strip is from
            // the mark behind it, and a scene let go on its top half goes
            // before it, on its bottom half after — the same reading as a
            // line between rows anywhere else. A scene from another day
            // comes onto this one at that place, and so does a single shot.
            .boardMark(.strip(scene: strip.scene, day: day.id))
            .opacity(hands.holds(scene: strip.scene, day: day.id) ? 0.35 : 1)
            .overlay(alignment: .top) {
                if hands.spot == .into(day: day.id, index: at) { dropLine.offset(y: -3) }
            }
            .overlay(alignment: .bottom) {
                if at == day.strips.count - 1,
                   hands.spot == .into(day: day.id, index: day.strips.count) { dropLine.offset(y: 3) }
            }
            .contextMenu {
                Button("Open scene") { inspect(strip.scene) }
                Divider()
                Button("Move Up") { state.nudgeSceneInDay(strip.scene, day: day.id, up: true) }
                Button("Move Down") { state.nudgeSceneInDay(strip.scene, day: day.id, up: false) }
                // **The no-drag way onto another day.** The same list the
                // sidebar's Day menu offers, so a scene can be scheduled
                // without a drag ever landing. Only this day's part of a
                // split scene goes — the part this strip is.
                let others = (state.stripBoard?.days ?? []).filter { $0.id != day.id && $0.wrapped != true }
                if !others.isEmpty {
                    Menu("Move to") {
                        ForEach(others) { other in
                            Button(Self.dayName(other)) {
                                state.putScenes([strip.scene], from: day.id, on: other.id, before: nil)
                            }
                        }
                    }
                }
                Divider()
                // **Taking a scene off the board** — his ask, 2026-08-29: "I
                // need to be able to remove scenes from the schedule or days."
                // The strip keeps everything of its own and simply stops
                // naming this day; a scene split across days keeps its other
                // days. Dragging it back onto the scene list does the same.
                Button("Remove from day") {
                    state.putScenes([strip.scene], from: day.id, on: nil, before: nil)
                }
            }
    }

    /// **One shot in the day's running order** — Shooting Order. Carried by
    /// the same hand as a strip: let go on a row's top half it goes before
    /// it, on its bottom half after, on another day it moves there.
    private func runRow(_ shot: BoardModel.RunShot, in day: BoardModel.Lane, at: Int) -> some View {
        let strip = day.strips.first { $0.scene == shot.scene }
        return RunRow(shot: shot, place: at + 1, strip: strip, dark: dark)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { inspect(shot.scene) }
            .boardMark(.run(placement: shot.placement, day: day.id))
            .opacity(hands.holds(shot: shot.placement) ? 0.35 : 1)
            .overlay(alignment: .top) {
                if hands.spot == .into(day: day.id, index: at) { dropLine.offset(y: -3) }
            }
            .overlay(alignment: .bottom) {
                if at == day.run.count - 1,
                   hands.spot == .into(day: day.id, index: day.run.count) { dropLine.offset(y: 3) }
            }
            .contextMenu {
                Button("Open scene") { inspect(shot.scene) }
                Divider()
                Button("Move Up") { state.nudgeShotInDay(shot.placement, day: day.id, up: true) }
                    .disabled(at == 0)
                Button("Move Down") { state.nudgeShotInDay(shot.placement, day: day.id, up: false) }
                    .disabled(at == day.run.count - 1)
                let others = (state.stripBoard?.days ?? []).filter { $0.id != day.id && $0.wrapped != true }
                if !others.isEmpty {
                    Menu("Move to") {
                        ForEach(others) { other in
                            Button(Self.dayName(other)) {
                                state.seatShot(shot.placement, on: other.id, at: other.run.count)
                            }
                        }
                    }
                }
                Divider()
                Button("Remove from day") { state.assign(placement: shot.placement, day: nil) }
            }
    }

    /// The 2-point accent line a strip wears above or below itself while a
    /// scene is held there — in the 4-point gap between strips, not over them.
    private var dropLine: some View {
        Capsule().fill(Brand.accent(dark)).frame(height: 2)
            .padding(.horizontal, 2)
            .allowsHitTesting(false)
    }

    /// The same line between two day cards, for a day being moved.
    private var dayLine: some View {
        Capsule().fill(Brand.accent(dark)).frame(height: 2)
            .allowsHitTesting(false)
    }

    /// `Day 1` or `Day 1 · Interiors` — how a menu names a day.
    static func dayName(_ day: BoardModel.Lane) -> String {
        day.title.isEmpty ? day.label : "\(day.label) · \(day.title)"
    }

    /// The scene's own one-line summary, read from the view model the engine
    /// hands back — never stored here. His ask, the same message: "if anything
    /// I want access to the synopsis to make sure I'm not forgetting what the
    /// scene is about."
    private func synopsis(_ scene: String) -> String {
        state.view?.scenes.first { $0.id == scene }?.description ?? ""
    }

    // ------------------------------------------------------------ opening

    private func toggle(_ scene: String) {
        if opened.contains(scene) { state.openStrips.remove(scene) }
        else { state.openStrips.insert(scene) }
    }

    /// Double-clicking a strip carries you to that scene's shot list, which is
    /// the same gesture as double-clicking a scene in the sidebar.
    private func inspect(_ scene: String) {
        state.sceneId = scene
        state.sideTab = .scenes
    }

}

extension ShellState {
    /// **Which day a scene is on, for the sidebar** — `Day 1`, or `Day 1, 3`
    /// for a scene split across days, or nothing. His report, 2026-09-19: the
    /// schedule was hard to use, and one reason was that the list you drag
    /// from gave no sign of what was already placed.
    func daysOf(scene: String) -> String {
        let on = (stripBoard?.days ?? []).filter { day in
            day.strips.contains { $0.scene == scene }
        }
        guard !on.isEmpty else { return "" }
        let numbers = on.map { $0.label.replacingOccurrences(of: "Day ", with: "") }
        return "Day " + numbers.joined(separator: ", ")
    }

    /// **How much of a scene is on a day**, for the sidebar's at-a-glance
    /// marks. His ask, 2026-10-13: *"for my sanity"*, a clear way to tell the
    /// scenes in the schedule from the ones not yet placed. A scene with no
    /// shots cannot be put on a day, so it is its own case and never counts as
    /// forgotten.
    struct Booking {
        var days: String
        var placed: Int
        var total: Int
        var left: Int { max(0, total - placed) }
        var hasShots: Bool { total > 0 }
        /// Every shot is on a day, or there is nothing to place.
        var settled: Bool { left == 0 }
    }

    func booking(of scene: ViewModel.Scene) -> Booking {
        var placed = 0
        for day in stripBoard?.days ?? [] {
            for strip in day.strips where strip.scene == scene.id { placed += strip.count }
        }
        return Booking(days: daysOf(scene: scene.id), placed: placed, total: scene.count)
    }

    /// Scenes in the list that still have a shot on no day.
    var scenesLeftToSchedule: Int {
        scenes.filter { booking(of: $0).left > 0 }.count
    }

    /// **A shot to a place in a day's running order** — Shooting Order's
    /// drop and menus. `index` is the row it lands ahead of, or the count for
    /// last, as the board draws the day now; from its own day the engine is
    /// told the place with the shot lifted out. One engine call, one undo.
    func seatShot(_ placement: String, on day: String, at index: Int) {
        let run = stripBoard?.days.first { $0.id == day }?.run ?? []
        var to = index
        if let from = run.firstIndex(where: { $0.placement == placement }) {
            if index > from { to -= 1 }
            guard to != from else { return }
        }
        afterBoard(engine?.putShot(placement, on: day, at: max(0, to)))
    }

    /// One step up or down the day's running order.
    func nudgeShotInDay(_ placement: String, day: String, up: Bool) {
        let run = stripBoard?.days.first { $0.id == day }?.run ?? []
        guard let at = run.firstIndex(where: { $0.placement == placement }) else { return }
        if up {
            guard at > 0 else { return }
            seatShot(placement, on: day, at: at - 1)
        } else {
            guard at + 1 < run.count else { return }
            seatShot(placement, on: day, at: at + 2)
        }
    }

    /// Put scenes on a day (at its end), or take them off every day with
    /// `nil` — the menu's way, for when a drag is not worth the trouble. One
    /// engine call and one undo step, however many scenes were picked.
    func putOnDay(_ scenes: [String], day: String?) {
        putScenes(scenes, from: nil, on: day, before: nil)
    }
}

/// One shot in a day's running order: its place, the scene's time-of-day dot,
/// its number, where, and what it is. Struck means got it — crossed out,
/// the way the table draws it.
private struct RunRow: View {
    let shot: BoardModel.RunShot
    /// 1 for the first shot of the day.
    let place: Int
    /// The scene's strip on this day, for its dot and its location.
    let strip: BoardModel.Strip?
    let dark: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text("\(place)")
                .sans(Brand.Size.tiny).monospacedDigit()
                .foregroundStyle(Brand.ink4(dark))
                .frame(width: 24, alignment: .leading)

            Circle()
                .fill(Brand.timeInk(strip?.timeOfDay ?? "", dark) ?? .clear)
                .frame(width: 5, height: 5)
                .padding(.trailing, 8)

            Text(shot.number)
                .sans(Brand.Size.body, weight: .semibold).monospacedDigit()
                .strikethrough(shot.struck)
                .frame(width: 52, alignment: .leading)

            Text((strip?.location ?? shot.heading).uppercased())
                .sans(Brand.Size.tiny)
                .foregroundStyle(Brand.ink3(dark))
                .lineLimit(1)
                .frame(width: 180, alignment: .leading)
                .padding(.trailing, 10)

            Text(shot.description.isEmpty ? shot.title : shot.description)
                .sans(13)
                .foregroundStyle(Brand.ink2(dark))
                .strikethrough(shot.struck)
                .lineLimit(1)

            Spacer(minLength: 8)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(Brand.ink4(dark))
                .padding(.trailing, 10)
        }
        .padding(.leading, 10)
        .foregroundStyle(shot.struck ? Brand.ink3(dark) : Brand.ink(dark))
        .frame(height: 30)
        .background(Brand.surface(dark), in: RoundedRectangle(cornerRadius: Brand.radiusSmall))
        .clipShape(RoundedRectangle(cornerRadius: Brand.radiusSmall))
        .shadow(color: .black.opacity(dark ? 0.18 : 0.07), radius: 1.5, y: 1)
    }
}

/// One strip: a scene's presence on one day, or its absence from all of them.
private struct StripRow: View {
    let strip: BoardModel.Strip
    /// The day this strip is on — a shot pulled out of it says where from.
    let day: String
    @ObservedObject var state: ShellState
    @ObservedObject var hands: BoardHands
    let dark: Bool
    /// Whether the board is showing every scene's summary right now.
    let showSynopsis: Bool
    var open: Bool = false
    var onToggle: () -> Void = {}
    var onInspect: () -> Void = {}
    /// The scene's one-line summary, or nothing. Passed in rather than looked
    /// up here so this row still knows nothing but what it is given.
    var synopsis: String = ""

    var body: some View {
        VStack(spacing: 2) {
            bar
            // **Two ways to the same words.** The button in the bar shows them
            // for every strip at once; opening one strip shows that scene's,
            // along with its shots. A scene with nothing written shows nothing
            // either way — never an empty band, which is the same rule the
            // frames drew before they were retired.
            if (showSynopsis || open) && !synopsis.isEmpty { summary }
            if open { shots }
        }
    }

    /// **What the scene is about**, under its strip — so deciding what can
    /// move does not mean leaving the board to remember what a scene was. Quiet,
    /// and only when there is something to say.
    private var summary: some View {
        Text(synopsis)
            .sans(11)
            .foregroundStyle(Brand.ink2(dark))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Brand.band(dark), in: RoundedRectangle(cornerRadius: Brand.radiusSmall))
            .padding(.leading, 22)
    }

    /// Opened, so one shot can go somewhere the rest of the scene is not.
    private var shots: some View {
        VStack(spacing: 2) {
            ForEach(strip.shots) { shot in
                HStack(spacing: 8) {
                    Text(shot.number).sans(Brand.Size.tiny, weight: .medium).monospacedDigit()
                        .frame(width: 42, alignment: .leading)
                    Text(shot.description.isEmpty ? shot.title : shot.description)
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.ink2(dark))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10))
                        .foregroundStyle(Brand.ink4(dark))
                }
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(Brand.rowAlt(dark), in: RoundedRectangle(cornerRadius: Brand.radiusSmall))
                // One shot, carried on its own by the same hand as a strip.
                .boardMark(.shot(placement: shot.placement, day: day))
                .opacity(hands.holds(shot: shot.placement) ? 0.35 : 1)
                // One shot off the day, without taking the rest of the scene
                // with it — the other half of splitting a scene across days.
                .contextMenu {
                    Button("Remove from day") {
                        state.assign(placement: shot.placement, day: nil)
                    }
                }
            }
        }
        .padding(.leading, 22)
        .padding(.bottom, 4)
    }

    private var bar: some View {
        strippedBar
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onInspect)
    }

    private var strippedBar: some View {
        HStack(spacing: 0) {
            Button(action: onToggle) {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8))
                    .foregroundStyle(Brand.ink4(dark))
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
            .help("Show shots")

            // **The same dot the scenes sidebar draws**, in the same place
            // relative to the number — his instruction, 2026-08-29: the
            // coloured edge "feels very gen ai … doesn't match the design of
            // anything else in the program." It doesn't: nothing else in this
            // app marks a value with a bar down the side of a row. The list
            // beside this board has answered *what time of day is this scene*
            // with a five-point dot since the day he asked for it, so the
            // board answers it the same way.
            Circle()
                .fill(Brand.timeInk(strip.timeOfDay, dark) ?? .clear)
                .frame(width: 5, height: 5)
                .help(strip.timeOfDay.isEmpty ? "No time of day" : strip.timeOfDay)
                .padding(.trailing, 8)

            Text(strip.number)
                .sans(Brand.Size.body, weight: .semibold).monospacedDigit()
                .frame(width: 36, alignment: .leading)

            // Small sans, not typewriter — the one label idiom.
            Text(insideOutShown(strip.intExt.uppercased()))
                .sans(Brand.Size.tiny)
                .foregroundStyle(Brand.ink3(dark))
                .frame(width: 52, alignment: .leading)

            Text(strip.location.uppercased())
                .sans(13, weight: .medium)
                .lineLimit(1)

            Spacer(minLength: 8)

            // "also Day 2" — the band that says this scene is not finished here
            if !strip.elsewhere.isEmpty {
                Text("Also \(strip.elsewhere.joined(separator: ", "))")
                    .sans(Brand.Size.tiny, weight: .medium)
                    .foregroundStyle(Brand.accent(dark))
                    .padding(.trailing, 8)
            }

            // The word stays — this is the one screen read as a grid — but the
            // colour of it now lives on the strip's own edge, not in a second
            // mark beside the text.
            Text(strip.timeOfDay.uppercased())
                .sans(Brand.Size.tiny)
                .foregroundStyle(Brand.ink3(dark))
                .frame(width: 62, alignment: .trailing)

            Text("\(strip.count)")
                .sans(Brand.Size.tiny).monospacedDigit()
                .foregroundStyle(Brand.ink3(dark))
                .frame(width: 34, alignment: .trailing)
                .padding(.trailing, 10)
        }
        // **A strip is a well cut into the day's card**, which is the app's own
        // metaphor for these two tones — panels lift, content is cut in. It
        // was `surface` on a card that was also `surface` on a ground that was
        // also `surface`: three identical near-blacks at night, so the only
        // thing separating them was a hairline, and the screen read as flat
        // black with very bright text on it. His note, 2026-08-29: the dark is
        // "very stark and intense with contrast". The stroke goes with it —
        // a tone that does its own separating needs no outline — and the drop
        // shadow softens, since it was drawing a black edge onto black.
        .foregroundStyle(Brand.ink(dark))
        .frame(height: 34)
        .background(Brand.surface(dark), in: RoundedRectangle(cornerRadius: Brand.radiusSmall))
        .clipShape(RoundedRectangle(cornerRadius: Brand.radiusSmall))
        .shadow(color: .black.opacity(dark ? 0.18 : 0.07), radius: 1.5, y: 1)
    }

}

/// The calendar panel's handle — the shell's `PanelGrab`, cloned for this
/// window and for the reasons written there: the drag belongs to AppKit, the
/// anchor to the window's own space, and the press must land in a window that
/// is not key.
struct CalendarGrab: NSViewRepresentable {
    let state: ShellState

    func makeNSView(context: Context) -> Handle {
        let handle = Handle()
        handle.state = state
        return handle
    }

    func updateNSView(_ view: Handle, context: Context) {
        view.state = state
        view.window?.invalidateCursorRects(for: view)
    }

    final class Handle: NSView {
        weak var state: ShellState?
        private var grabbedAt: CGFloat = 0
        private var widthAtGrab: CGFloat = 0

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }

        override func mouseDown(with event: NSEvent) {
            guard let state else { return }
            grabbedAt = event.locationInWindow.x
            widthAtGrab = state.calendarWidth
        }

        override func mouseDragged(with event: NSEvent) {
            guard let state else { return }
            // Minus, not plus: the handle is on the panel's leading edge, so
            // the pointer moving left has to make the panel wider. Whole
            // points, or a fractional width shimmers under the hand.
            let wanted = widthAtGrab - (event.locationInWindow.x - grabbedAt)
            state.calendarWidth = min(
                ShellState.calendarRange.upperBound,
                max(ShellState.calendarRange.lowerBound, wanted.rounded())
            )
        }
    }
}

/// **The board gets a window of its own**, the way the whole script does.
///
/// It was a fourth pill in the sidebar first, and the sidebar said no: four
/// capsules do not fit 258 points, so *Locations* and *Schedule* both broke
/// across two lines mid-word. `SectionSwitcher`'s own comment had already
/// written that down — "a pill row lives or dies on its longest word" — and a
/// screenshot is what made it true rather than theoretical.
///
/// A window is the better answer anyway, for the reason the script window
/// exists: a strip board is 1,300 points wide before it is comfortable, and in
/// the content area it was squeezed beside a sidebar that had nothing to say
/// about it. Here it can stand on the second monitor while the shot list is
/// worked on the first — which is what a schedule is *for*. It is also what the
/// old app did: a full screen of its own, on ⌘4, and the key is the same.
final class ScheduleWindow: NSObject, NSWindowDelegate {
    static let shared = ScheduleWindow()

    private var window: NSWindow?
    private var hosting: NSHostingView<Schedule>?

    func show(state: ShellState) {
        let view = Schedule(state: state, standalone: true)
        if let hosting {
            hosting.rootView = view
        } else {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1320, height: 820),
                styleMask: [.titled, .closable, .resizable, .miniaturizable,
                            .fullSizeContentView],
                backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 720, height: 400)
            w.delegate = self
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.title = "Schedule"
            w.identifier = NSUserInterfaceItemIdentifier("schedule")
            let host = NSHostingView(rootView: view)
            w.contentView = host
            hosting = host
            if !Launch.checking { w.setFrameAutosaveName("scheduleWindow") }
            if let main = NSApp.windows.first(where: { $0.isVisible && $0 != w }) {
                main.addChildWindow(w, ordered: .above)
                if w.frame.origin == .zero { w.center() }
            }
            window = w
        }
        // Asked for fresh on every opening: a day can be assigned from the
        // table's day cell while this window is shut.
        state.loadBoard()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        hosting = nil
    }
}

// ----------------------------------------------------------------- the sheets

/// Naming a shoot day — "Second unit", "Pickups", "Company move".
///
/// The name sits **beside** `Day 3`, never instead of it: the number is what a
/// crew counts by and comes from the day's position, while the name says what
/// this particular day is for. Emptying the field takes the name away.
struct NameDay: View {
    @ObservedObject var state: ShellState
    let day: BoardModel.Lane
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    @State private var name = ""

    var body: some View {
        Sheet(title: day.label, width: .narrow) {
            Field("Name") {
                FieldText(placeholder: "Name", text: $name, onSubmit: commit)
            }
        } trailing: {
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Name", action: commit)
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
        }
        .onAppear { name = day.title }
    }

    private func commit() {
        state.nameDay(day.id, name.trimmingCharacters(in: .whitespaces))
        dismiss()
    }
}

/// Dating a shoot day.
///
/// **This is the switch that freezes the shot letters.** The earliest date in
/// the film is the morning prep ends — `lettering.rs` reads exactly this field
/// — so the sheet says so, which is one of the sentences a label cannot carry.
struct DateDay: View {
    @ObservedObject var state: ShellState
    let day: BoardModel.Lane
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    @State private var when = Date()

    var body: some View {
        Sheet(title: day.label, width: .narrow) {
            Field("Date") {
                DatePicker("Date", selection: $when, displayedComponents: .date)
                    .datePickerStyle(.field)
                    .labelsHidden()
                    .sans(Brand.Size.body)
                    .foregroundStyle(Brand.ink(dark))
            }
            // A sentence, because it says what setting the date will do.
        } leading: {
            Button("Clear") {
                state.dateDay(day.id, "")
                dismiss()
            }
            .disabled(day.date.isEmpty)
        } trailing: {
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Set Date", action: commit)
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
        }
        .onAppear { when = Self.stored.date(from: day.date) ?? Date() }
    }

    static let stored: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func commit() {
        state.dateDay(day.id, Self.stored.string(from: when))
        dismiss()
    }
}
