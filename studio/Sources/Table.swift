import SwiftUI
import AppKit

/// The shot list.
///
/// Studio shows **one scene's shots**, because that is what a scene tab is —
/// the whole film lives in the sidebar. So there is no grouping to draw here;
/// the group is the scene you are standing in.
///
/// The old app's table was fixed by hand after Nathaniel said it felt cheap, and
/// those fixes are behaviour rather than code — they are reproduced here
/// deliberately and each one is commented with what it is for. See
/// `handoff/from-app.md`, 2026-08-17. Regressions against them are bugs.
/// What the table's scrollbar is drawn from — and **its own object, which is
/// the whole point**.
///
/// These three numbers change on every tick of a scroll wheel. While they sat
/// on `ShellState`, every tick invalidated the sidebar, the chrome and all
/// sixteen rows, because everything in the window observes that one object.
/// Here only the bar observes them, so only the bar redraws. The table holds
/// it in `@State` rather than `@StateObject` deliberately: `@State` keeps the
/// instance alive without subscribing the table to its changes.
final class ScrollModel: ObservableObject {
    @Published var offset: CGFloat = 0
    @Published var content: CGFloat = 0
    @Published var viewport: CGFloat = 0
}

struct ShotTable: View {
    @ObservedObject var state: ShellState
    let scene: ViewModel.Scene
    @State private var scroll = ScrollModel()

    @Environment(\.colorScheme) private var scheme
    @State private var keys: Any?
    @State private var mouse: Any?
    /// How tall the open text view's words came out.
    @State private var typedHeight: CGFloat = 17
    /// The column whose right edge is being pulled, for the glow.
    @State private var resizing: String?
    /// **The pictures ⌫ is asking about.** Empty when it is not asking. His
    /// ask, 2026-08-29: *"backspace needs to delete a photo with warning in
    /// the table."* Delete has always cleared a *cell*; the image column was
    /// deliberately not clearable, so the one column where the thing on screen
    /// is a photograph did nothing at all.
    @State private var removingFrames: [ViewModel.Still] = []

    private var dark: Bool { scheme == .dark }

    private var columns: [String] {
        (state.view?.columns ?? []).filter(\.visible).map(\.name)
    }

    private var rows: [ViewModel.Row] { state.rows(of: scene.id) }

    /// **Every row the table is showing, in script order.** `rows` above is
    /// *this scene's* and the drawing wants exactly that; the cursor, the
    /// keyboard and a selection want the whole script, because the table has
    /// been the whole script since the 19th.
    ///
    /// Asking `rows` where the cursor is was the same mistake as asking the
    /// sidebar which scene a shot belongs to — a fact about the **chrome**,
    /// read as a fact about the shot. It failed silently and in the worst
    /// possible way: `firstIndex` returned nil for any cursor outside the
    /// chrome's scene, `?? 0` turned that into row zero, and every arrow key
    /// threw him back to the first scene in the script. The same nil made
    /// `cursorRow` empty, so ⌘C and ⌘V simply did nothing. One property,
    /// two reports.
    ///
    /// Narrowed scenes are already out of `scenes`, so a filtered-away row is
    /// not something the keyboard can walk onto.
    private var everyRow: [ViewModel.Row] {
        if state.shootingOrder { return days.flatMap(\.rows) }
        return scenes.flatMap { rows(of: $0) }
    }

    /// **Sorted by Shooting Order**: the days in order, each its shots in
    /// the order they are shot, the unscheduled last — as the engine groups.
    private var days: [ViewModel.Group] { state.orderGroups }

    /// What a dragged row moves within: its day in shooting order
    /// (`day:<id>`), its scene otherwise.
    private func bucket(_ id: String) -> String? {
        state.shootingOrder ? state.dayOfRow[id] : everyRow.first { $0.id == id }?.sceneId
    }

    /// **The whole script, one table** — his ask. Every scene in order, each
    /// under its own line, and picking one in the sidebar carries you to it
    /// rather than swapping the page underneath you. Archived scenes are set
    /// aside, so they are not in the read-through.
    private var scenes: [ViewModel.Scene] {
        // **The same order the sidebar is reading in** — Ref 102. A sidebar
        // sorted by shoot day beside a table still in script order is two
        // answers to one question, six inches apart, which is the fault the
        // scene list already had under a filter.
        let all = state.inViewOrder((state.view?.scenes ?? []).filter { !$0.archived })
        guard state.view?.filter.narrowed == true else { return all }
        // **Under a filter, a scene with nothing left in it is not empty —
        // it is narrowed out.** Drawing its band anyway, with an "Add shot"
        // underneath, says the film changed when only the question did. The
        // count in the bar already says how many scenes went out of sight.
        return all.filter { !rows(of: $0).isEmpty }
    }

    /// **A lookup, not a scan** — see `ShellState.rowsByScene`. This filtered
    /// every row in the film, and the table called it once per scene to lay
    /// the list out, again per scene for the shot count on each band, and
    /// again for every row it drew. On a scroll that is thousands of rows
    /// rebuilt and thrown away per frame.
    private func rows(of scene: ViewModel.Scene) -> [ViewModel.Row] {
        state.rows(of: scene.id)
    }

    /// Whole points. Sub-pixel jitter is the fuel an update loop runs on.
    private func rounded(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(),
               width: rect.width.rounded(), height: rect.height.rounded())
    }

    /// **How many times the whole table has been built.**
    ///
    /// A rebuild walks every scene and every row in the film, and it is the
    /// unit of waste in this view: nothing on screen changes for most of them.
    /// Reported by a checking run, because "the scroll feels clunky" and "the
    /// table rebuilt itself four hundred times" are the same sentence and only
    /// one of them is a number.
    static var builds = 0

    var body: some View {
        // A `ViewBuilder` takes views, not statements, so the count is taken
        // in a binding it then ignores.
        let _ = { Self.builds += 1 }()
        // The reader is hoisted out here so the scrollbar — which must be
        // drawn OUTSIDE the horizontal scroll, at the window's edge — can
        // still drive the vertical one inside it.
        ScrollViewReader { bar in
        VStack(spacing: 0) {
            // One horizontal scroll around both the header and the body, so the
            // header cannot drift out of step with the columns beneath it.
            ScrollView(.horizontal, showsIndicators: true) {
                ScrollViewReader { sideways in
                VStack(spacing: 0) {
                    header
                    // The vertical reader wraps *only* the vertical scroll. In
                    // the old app it wrapped both axes, so moving the cursor
                    // scrolled sideways too and every click lurched to the
                    // right. If you restructure this, keep the reader inside
                    // the horizontal scroll or the lurch comes back.
                    ScrollViewReader { reader in
                        // The system's own vertical indicator is off: it lives
                        // inside the horizontal scroll, so it sits at the right
                        // edge of the CONTENT — which is wider than the window
                        // — and floats mid-screen or off it entirely. Ours is
                        // drawn at the window's edge instead (his ask), from
                        // the numbers reported here. Same reason this app draws
                        // its own top bar rather than taking the system's.
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                if state.shootingOrder {
                                    // **In shooting order**: a band per day,
                                    // its shots under it in the order they
                                    // are shot. A drag moves a shot in that
                                    // order; no number changes.
                                    ForEach(days) { day in
                                        dayBreak(day).id("scene:day:" + (day.key ?? ""))
                                        .overlay { editThrough("head:day:" + (day.key ?? "")) }
                                        ForEach(Array(day.rows.enumerated()),
                                                id: \.element.tag) { at, row in
                                            line(row, alternate: at.isMultiple(of: 2) == false)
                                        }
                                    }
                                } else {
                                ForEach(scenes) { sc in
                                    if state.sectionHeadBefore(sc, in: scenes) {
                                        sectionHead(state.sectionOf(sc))
                                            .overlay { editThrough("head:" + sc.id) }
                                    } else if state.sectionEndsBefore(sc, in: scenes) {
                                        Rectangle().fill(Brand.rule(dark))
                                            .frame(maxWidth: .infinity).frame(height: 1)
                                            .overlay { editThrough("head:" + sc.id) }
                                    }
                                    sceneBreak(sc).id("scene:" + sc.id)
                                        .sectionWash(spineInk(sc), dark: dark, over: true)
                                        .overlay { editThrough("head:" + sc.id) }
                                    // **The identity carries the scene.**
                                    //
                                    // A shot dragged from 34 into 33 kept
                                    // saying "34A", stayed dimmed and stayed
                                    // ringed however far away he clicked —
                                    // while the model, the shot list and the
                                    // row frames all agreed it was 33A. Three
                                    // arrow presses re-rendered every other row
                                    // and left that one frozen.
                                    //
                                    // The placement id does not change when a
                                    // shot changes scene, so the row kept the
                                    // same `ForEach` identity while moving to a
                                    // *different* `ForEach` — and inside a
                                    // `LazyVStack` SwiftUI answered that by
                                    // handing back the view it had already
                                    // built, data and all. Nothing was stale
                                    // except the thing on screen.
                                    //
                                    // Putting the scene in the identity makes a
                                    // move an actual change of identity, so the
                                    // row is built again where it now lives.
                                    ForEach(Array(rows(of: sc).enumerated()),
                                            id: \.element.tag) { at, row in
                                        let _ = { Built.rows += 1 }()
                                        line(row, alternate: at.isMultiple(of: 2) == false)
                                            .sectionWash(spineInk(sc), dark: dark)
                                    }
                                    adder(sc)
                                        .sectionWash(spineInk(sc), dark: dark)
                                        .overlay { editThrough("foot:" + sc.id) }
                                }
                                }
                                // Room for a dropdown under the last rows —
                                // a sheet scrolls past its content for the
                                // same reason.
                                Color.clear.frame(height: 280)
                            }
                            // The open cell is drawn *on the cell plane* — the
                            // same coordinate space the cells are laid out in,
                            // inside both scroll views. It has to be. SwiftUI
                            // gives an AppKit view hosted anywhere in this
                            // hierarchy its frame in this plane, so an editor
                            // positioned from any outer space is drawn in one
                            // place and *clickable* in another whenever the
                            // table is scrolled — which is how a click on the
                            // next cell landed on the invisible edge of the
                            // editor and pulled the window frontmost. On the
                            // plane, drawn and clickable are the same point,
                            // and the editor scrolls with its cell, which is
                            // what a sheet's editor does anyway.
                            // How far down, and how much there is — read from
                            // the content's own place inside the scroll.
                            .background {
                                GeometryReader { geo in
                                    let frame = geo.frame(in: .named("vscroll"))
                                    Color.clear.preference(
                                        key: Scrolling.self,
                                        value: ScrollMetrics(
                                            offset: (-frame.minY).rounded(),
                                            content: frame.height.rounded()))
                                }
                            }
                            .overlayPreferenceValue(OpenCell.self) { anchor in
                                GeometryReader { geo in
                                    if state.editing, let anchor, let row = cursorRow {
                                        openCell(row, in: geo[anchor], within: geo.size)
                                    }
                                }
                            }
                        }
                        // Picking a scene in the sidebar carries the table to
                        // it — the same move the document page makes, so the
                        // two surfaces read the same way. A change that came
                        // from *reading* (below) does not scroll: it is
                        // already where it wants to be, and scrolling would
                        // fight the hand doing the scrolling.
                        .onChange(of: state.goToScene) { _, id in
                            guard let id else { return }
                            state.goToScene = nil
                            state.scrollingToScene = true
                            withAnimation(.easeInOut(duration: 0.3)) {
                                reader.scrollTo("scene:" + id, anchor: .top)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                state.scrollingToScene = false
                            }
                        }
                        // **The chrome follows what is being read**, not what
                        // the sidebar last said — his ask. The scene in hand
                        // is the last one whose line has passed the top of
                        // the table: that is the scene whose shots fill the
                        // screen. It writes the same `sceneId` the sidebar
                        // writes, so the sidebar highlight, the big heading
                        // and the property line all move together.
                        .coordinateSpace(name: "vscroll")
                        // **One write per layout pass**, from what the pass
                        // measured — not one write per row, mid-update.
                        // **One write per layout pass, and only what
                        // changed.** The frames go into plain storage — see
                        // `ShellState.sceneFrames` for why — and the one fact
                        // anybody draws from, which scene is being read, is
                        // worked out here and written only when it moves.
                        .onPreferenceChange(Frames.self) { frames in
                            var rows: [String: CGRect] = [:]
                            var scenes: [String: CGRect] = [:]
                            for (key, rect) in frames {
                                if key.hasPrefix("scene:") {
                                    scenes[String(key.dropFirst(6))] = rect
                                } else {
                                    rows[key] = rect
                                }
                            }
                            state.rowFrames = rows
                            state.sceneFrames = scenes
                            // A day's band is not a scene: in shooting order
                            // the chrome keeps the scene it had.
                            if !state.shootingOrder { reading(scenes) }
                        }
                        .onPreferenceChange(Scrolling.self) { metrics in
                            state.tableOffset = metrics.offset
                            if scroll.offset != metrics.offset { scroll.offset = metrics.offset }
                            if scroll.content != metrics.content { scroll.content = metrics.content }
                        }
                        .background {
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear {
                                        state.tableTop = geo.frame(in: .global).minY
                                        scroll.viewport = geo.size.height
                                    }
                                    .onChange(of: geo.size.height) { _, now in
                                        scroll.viewport = now
                                    }
                            }
                        }
                        .task {
                            // Not `onAppear`: on the first pass the lazy rows
                            // do not exist yet, so a scroll to one lands
                            // nowhere and the table opens at the top of the
                            // script rather than at the scene you asked for.
                            //
                            // **The scene is read now, not after the wait.**
                            // During the wait the first layout pass reports
                            // its frames, and the reading derivation names
                            // whichever scene is at the top of an unscrolled
                            // table — so a `state.sceneId` read after the
                            // sleep is the top of the script, never the scene
                            // he left off on. `scrollingToScene` is held for
                            // the whole settle so that derivation stays quiet
                            // until the table is where it was asked to be.
                            // **The gate has to come down even when there is
                            // nowhere to scroll.** `scrollingToScene` starts
                            // *true* so the first layout cannot overwrite the
                            // scene he left off on — and this returned early
                            // with it still true whenever the project opened
                            // on no scene at all. It stays true for ever after
                            // that, and the derivation it gates — which scene
                            // the reader is on — never runs again, so scrolling
                            // stops moving the sidebar. Found while reading for
                            // Ref 113; not that bug, but real.
                            guard let id = state.sceneId else {
                                state.scrollingToScene = false
                                return
                            }
                            state.scrollingToScene = true
                            state.goToScene = nil
                            try? await Task.sleep(for: .milliseconds(140))
                            reader.scrollTo("scene:" + id, anchor: .top)
                            try? await Task.sleep(for: .milliseconds(260))
                            state.scrollingToScene = false
                        }
                        // The far corner of a stretched block is followed too,
                        // so ⇧↓ past the foot of the window scrolls with it.
                        .onChange(of: state.cellRange?.endRow) { _, shot in
                            guard let shot,
                                  let tag = everyRow.first(where: { $0.id == shot })?.tag
                            else { return }
                            withAnimation(.easeOut(duration: 0.12)) {
                                reader.scrollTo(tag, anchor: nil)
                            }
                        }
                        .onChange(of: state.cursorShot) { _, shot in
                            guard let shot,
                                  // The row answers to its scene-qualified tag
                                  // now, not to the bare placement id.
                                  let tag = everyRow.first(where: { $0.id == shot })?.tag
                            else { return }
                            // A nil anchor means *minimal* movement: a click on
                            // a visible row scrolls nothing at all, and arrowing
                            // off the bottom edge slides exactly one row.
                            withAnimation(.easeOut(duration: 0.12)) {
                                reader.scrollTo(tag, anchor: nil)
                            }
                        }
                    }
                }
                // Tab walks right past the edge of the window, and a cell you
                // cannot see is a cell you are typing into blind — which is
                // exactly what happened to Notes, six columns out. The cursor
                // pulls the sideways scroll along with it, minimally: a column
                // already on screen moves nothing.
                //
                // The reader is *inside* the horizontal scroll and moves only
                // on a column change. That separation is deliberate: when one
                // reader owned both axes, every vertical move scrolled sideways
                // too and each click lurched to the right.
                .onChange(of: state.cursorColumn) { _, name in
                    withAnimation(.easeOut(duration: 0.12)) {
                        sideways.scrollTo("head:" + name, anchor: nil)
                    }
                }
                .onChange(of: state.cellRange?.endColumn) { _, name in
                    guard let name else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        sideways.scrollTo("head:" + name, anchor: nil)
                    }
                }
                // And once when the table arrives, because the cursor's column
                // survives a relaunch: reopening on a column that is scrolled
                // out of sight would put the cursor somewhere invisible before
                // anything had changed for the watcher above to notice.
                .onAppear {
                    DispatchQueue.main.async {
                        sideways.scrollTo("head:" + state.cursorColumn, anchor: nil)
                    }
                }
                }
            }
        }
        // At the window's edge, over everything, because it belongs to the
        // window rather than to the content — his ask.
        // **Fill the window, or stop filling it.** One number per layout pass,
        // through a preference rather than a write from inside a
        // `GeometryReader` — writing published state during an update is what
        // made this table re-render itself in a loop once already.
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: TableWidth.self,
                                       value: rounded(geo.frame(in: .global)))
            }
        }
        .onPreferenceChange(TableWidth.self) { box in
            Columns.lastFrame = box
            if Columns.fit(box.width, across: columns) { state.columnBump &+= 1 }
        }
        .overlay(alignment: .trailing) { scrollBar(bar) }
        // **The bar that appears when several shots are held**, his design: it
        // arrives with the selection and goes with it, and it carries *doing*
        // rather than *looking* — no filtering, no zoom. Those are always-true
        // things and belong in the chrome; this is a thing you are in the
        // middle of.
        .overlay(alignment: .bottom) { heldShots }
        .background(Brand.surface(dark))
        .onAppear { watchKeys(); watchHeaderMouse() }
        // A scene change or a tab change with a cell open puts the words away
        // first. The alternative is an edit left dangling: its buffer alive,
        // its row belonging to a scene that is no longer on screen, and the
        // next Return writing old text into whatever the cursor lands on.
        .onChange(of: scene.id) { _, _ in closeOpenCell() }
        .onDisappear {
            closeOpenCell()
            if let keys { NSEvent.removeMonitor(keys) }
            keys = nil
            if let mouse { NSEvent.removeMonitor(mouse) }
            mouse = nil
        }
        // The same words the wall uses, because it is the same act. The
        // sentence earns its place under the copy law: what a delete costs is
        // the one thing a button label cannot say.
        .alert(removingFrames.count == 1 ? "Remove this picture?"
                                         : "Remove all \(removingFrames.count) pictures?",
               isPresented: Binding(get: { !removingFrames.isEmpty },
                                    set: { if !$0 { removingFrames = [] } })) {
            Button("Cancel", role: .cancel) { removingFrames = [] }
            Button("Remove", role: .destructive) {
                state.removePhotos(removingFrames.map(\.ref))
                removingFrames = []
            }
        }
        }
    }

    /// **The table's own scrollbar**, at the window's edge.
    ///
    /// The system's sits inside the horizontal scroll, so it rides the right
    /// edge of the *content* — wider than the window — and ends up floating
    /// mid-screen or off it. This one is drawn outside that scroll, from the
    /// three numbers the content reports: how far down it is, how tall it is,
    /// and how much of it fits.
    ///
    /// Dragging it scrolls by **row**, not by pixel: SwiftUI will carry a
    /// scroll view to a view it can name, and every row here is named. The
    /// nearest row to the dragged fraction is the one it goes to, which is
    /// close enough that a hand cannot tell, and it never lands between rows.
    // ------------------------------------------------------- what a shot can do
    //
    // **One set of actions, reachable two ways.** His question, and it was the
    // right one: "these two menus should pretty much be the same, no?" They
    // were not — the bar had Duplicate, Move and Clear, the right-click menu
    // had Paste and Cross Out, and neither had all of it. Two lists that nearly
    // agree are worse than either, because you learn one and then find it
    // short. So: these functions *are* the actions, and the menu and the bar
    // are both only ways of pointing at them.

    /// The shots an action reaches: everything ringed, or the row it was aimed
    /// at when nothing is.
    private func held(_ row: ViewModel.Row?) -> [ViewModel.Row] {
        if !state.wholeShots.isEmpty {
            return everyRow.filter { state.wholeShots.contains($0.id) }
        }
        if let row { return [row] }
        return []
    }

    private func copyShots(_ shots: [ViewModel.Row]) {
        // Onto the app's own clipboard, so a paste can make *shots*. The text
        // goes to the system clipboard as well, so a copied shot still lands in
        // a spreadsheet or an email as its columns.
        state.copiedShots = shots.map(\.placement)
        let text = CellClip.encode(shots.map { shot in
            columns.map { Columns.value(shot, $0) }
        })
        // Remembered, so ⌘V knows the clipboard is still these shots.
        state.copiedShotsText = text
        copyCell(text)
        // Whole shots are not an outlined block of cells.
        state.copiedCells = nil
        state.copiedCut = false
    }

    /// Copies of the copied shots, landing under `row` in *its* scene.
    private func pasteShots(after row: ViewModel.Row?) {
        guard let engine = state.engine, !state.copiedShots.isEmpty else { return }
        guard let scene = row?.sceneId ?? state.sceneId ?? scenes.first?.id else { return }
        state.replace(engine.copyShots(state.copiedShots,
                                       toScene: scene,
                                       after: row?.placement))
    }

    private func duplicateShots(_ shots: [ViewModel.Row]) {
        guard let engine = state.engine, let last = shots.last,
              let scene = last.sceneId else { return }
        state.replace(engine.copyShots(shots.map(\.placement),
                                       toScene: scene, after: last.placement))
    }

    private func clearShots(_ shots: [ViewModel.Row]) {
        guard let engine = state.engine, !shots.isEmpty else { return }
        let groups = columns.filter { Columns.clearable($0) }.map {
            (field: $0 == "camera" ? "unit" : $0, shots: shots.map(\.shot))
        }
        if !groups.isEmpty { state.replace(engine.clearCells(groups)) }
    }

    private func strikeShots(_ shots: [ViewModel.Row]) {
        guard let engine = state.engine, let first = shots.first else { return }
        state.replace(engine.strike(shots: shots.map(\.shot), on: !first.struck))
    }

    private func deleteShots(_ shots: [ViewModel.Row]) {
        guard let engine = state.engine, !shots.isEmpty else { return }
        state.replace(engine.deletePlacements(shots.map(\.placement)))
        state.wholeShots.removeAll()
    }

    private func colourShots(_ shots: [ViewModel.Row], _ colour: String) {
        guard let engine = state.engine else { return }
        for shot in shots {
            state.replace(engine.set(shot: shot.shot, field: "colour", value: colour))
        }
    }

    /// The one list, as menu items. The bar draws the same actions as buttons.
    @ViewBuilder
    private func shotActions(_ shots: [ViewModel.Row]) -> some View {
        let many = shots.count > 1
        let noun = many ? "\(shots.count) Shots" : "Shot"
        let onClipboard = state.copiedShots.count > 1
            ? "\(state.copiedShots.count) Shots" : "Shot"
        Button("Copy \(noun)") { copyShots(shots) }
        Button("Paste \(onClipboard)") { pasteShots(after: shots.last) }
            .disabled(state.copiedShots.isEmpty)
        Button("Duplicate \(noun)") { duplicateShots(shots) }
        Divider()
        Button("Move \(noun) to…") { state.movingShots = true }
        // **Which day it is shot** — its scene, number and letter stay.
        Menu("Shoot Day") {
            let held = Set(shots.map { $0.dayId ?? "" })
            ForEach(state.pickableDays(keeping: held)) { day in
                Button(day.label + (day.date.isEmpty ? "" : " · \(day.date)")
                       + (held == [day.id] ? "  ✓" : "")) {
                    scheduleShots(shots, on: day.id)
                }
            }
            Divider()
            Button("Not Scheduled" + (held == [""] ? "  ✓" : "")) { scheduleShots(shots, on: nil) }
        }
        if !many, let shot = shots.first {
            // The camera that stands for it, on its scene's overhead.
            Button("Show on Diagram") {
                if let scene = shot.sceneId { state.sceneId = scene }
                state.diagramShot = shot.shot
                state.sideTab = .diagram
            }
            // **Add to Spec Sheet** (Ref 1627): its lens or camera body is not
            // on the sheet of its shoot. Offered, never done on its own.
            if let off = shot.offKit {
                if let lens = off.lens {
                    Button("Add \(lens) to Spec Sheet") { SpecSheets.shared.add(lens: lens, for: off, state: state) }
                }
                if let body = off.body {
                    Button("Add \(body) to Spec Sheet") {
                        SpecSheets.shared.add(body: body, label: off.camera ?? "", for: off, state: state)
                    }
                }
                ForEach(off.modifiers ?? [], id: \.self) { modifier in
                    Button("Add \(modifier) to Spec Sheet") {
                        SpecSheets.shared.add(modifier: modifier, for: off, state: state)
                    }
                }
                ForEach(off.filters ?? [], id: \.self) { filter in
                    Button("Add \(filter) to Spec Sheet") {
                        SpecSheets.shared.add(filter: filter, for: off, state: state)
                    }
                }
            }
        }
        Menu("Highlight") {
            ForEach(Array(Columns.palette.enumerated()), id: \.offset) { at, colour in
                Button {
                    colourShots(shots, colour)
                } label: {
                    Label(Columns.paletteNames[at]
                          + (shots.first?.colour == colour ? "  ✓" : ""),
                          systemImage: "circle.fill")
                }
            }
            Divider()
            Button("No highlight") { colourShots(shots, "") }
        }
        Button(shots.first?.struck == true ? "Not Shot Yet" : "Shot") {
            strikeShots(shots)
        }
        Button("Clear \(noun)") { clearShots(shots) }
        if shots.count == 1, let one = shots.first {
            Divider()
            masterActions(one)
        }
        // **The Edit Reference mod**: only while the project has it on.
        if state.modOn(Mods.editReference) {
            Divider()
            Button("Add Edit Reference…") { state.editRefAdding = shots.map(\.shot) }
            ForEach(state.editRefsOf(shots), id: \.id) { ref in
                Button("Play \(ref.name)") { state.editRefFrom = nil; state.editRefPlaying = ref.id }
            }
        }
        Divider()
        Button("Delete \(noun)") { deleteShots(shots) }
    }

    /// **A shot other shots stand in for.**
    ///
    /// His ask, 2026-08-22, carried over from the old app: a film breaks a
    /// scene up and comes back to the same setup later, and describing it twice
    /// is how two descriptions of one thing drift apart. One shot is the
    /// master, the others point at it, and typing into any of them types into
    /// all of them — the engine resolves that, so nothing here has to.
    ///
    /// One shot at a time, deliberately: "link these five to that one" is a
    /// sentence nobody says, and a menu that offered it would mostly be a way
    /// of doing it by accident.
    @ViewBuilder
    private func masterActions(_ row: ViewModel.Row) -> some View {
        if let to = row.linkedTo {
            Button("Unlink from \(to)") {
                state.replace(state.engine?.link(row.shot, to: nil))
            }
        } else {
            Button(row.isMaster ? "Remove master" : "Make master") {
                state.replace(state.engine?.makeMaster(row.shot, on: !row.isMaster))
            }
            let masters = everyRow.filter { $0.isMaster && $0.shot != row.shot }
            if !masters.isEmpty {
                Menu("Link to master") {
                    ForEach(masters) { master in
                        Button("\(master.number)  \(master.description.prefix(40))") {
                            state.replace(state.engine?.link(row.shot, to: master.shot))
                        }
                    }
                }
            }
        }
    }

    /// Shown while any whole shot is held. One is the
    /// right-click menu's job; a bar that appeared for every single click would
    /// be a thing flashing at the bottom of the screen all day.
    @ViewBuilder
    private var heldShots: some View {
        if !state.wholeShots.isEmpty {
            let held = everyRow.filter { state.wholeShots.contains($0.id) }
            HStack(spacing: 10) {
                Text(held.count == 1 ? "1 shot selected" : "\(held.count) shots selected")
                    .sans(11, weight: .semibold)
                    .foregroundStyle(Brand.ink2(dark))
                Divider().frame(height: 16)
                heldButton("Copy", "doc.on.doc") { copyShots(held) }
                heldButton("Paste", "doc.on.clipboard") { pasteShots(after: held.last) }
                    .disabled(state.copiedShots.isEmpty)
                    .opacity(state.copiedShots.isEmpty ? 0.4 : 1)
                heldButton("Duplicate", "plus.square.on.square") { duplicateShots(held) }
                heldButton("Move to…", "arrow.right.square") { state.movingShots = true }
                heldButton("Clear", "eraser") { clearShots(held) }
                heldButton("Delete", "trash", danger: true) { deleteShots(held) }
            }
            // Sized to its words, never squeezed: the bar was being handed the
            // window's width and truncating its own buttons to "Duplica…",
            // which is a control you cannot read telling you what it does.
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background {
                Capsule(style: .continuous)
                    .fill(Brand.panel(dark))
                    .overlay { Capsule(style: .continuous)
                        .strokeBorder(Brand.glassEdge(dark), lineWidth: 1) }
                    .shadow(color: .black.opacity(dark ? 0.5 : 0.16), radius: 16, y: 4)
            }
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func heldFace(_ title: String, _ icon: String,
                          danger: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11))
            Text(title).sans(11, weight: .medium)
        }
        .foregroundStyle(danger ? Brand.hex("E5484D") : Brand.ink2(dark))
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background { Capsule().fill(Brand.glass2(dark)) }
        .contentShape(Capsule())
    }

    private func heldButton(_ title: String, _ icon: String,
                            danger: Bool = false,
                            _ act: @escaping () -> Void) -> some View {
        Button(action: act) { heldFace(title, icon, danger: danger) }
            .buttonStyle(.plain)
            .focusEffectDisabled()
    }

    private func scrollBar(_ reader: ScrollViewProxy) -> some View {
        TableScrollBar(model: scroll, dark: dark) { fraction in
            carry(to: fraction, with: reader)
        }
    }

    /// **The chrome follows what is being read**, not what the sidebar last
    /// said — his ask. The scene in hand is the last one whose band has passed
    /// the top of the table: the one whose shots fill the screen.
    private func reading(_ frames: [String: CGRect]) {
        guard !state.scrollingToScene, !frames.isEmpty else { return }
        let top = (state.tableTop ?? 0) + 1
        let reading = frames
            .filter { $0.value.minY <= top }
            .max { $0.value.minY < $1.value.minY }?
            .key
            // Nothing above the line yet — the first scene on screen is
            // the one being read.
            ?? frames.min { $0.value.minY < $1.value.minY }?.key
        guard let reading, reading != state.sceneId else { return }
        state.scrollingToScene = true
        state.sceneId = reading
        DispatchQueue.main.async { state.scrollingToScene = false }
    }

    /// Where a fraction of the way down lands: the row nearest it.
    private func carry(to fraction: CGFloat, with reader: ScrollViewProxy) {
        let all = everyRow
        guard !all.isEmpty else { return }
        let at = Int((CGFloat(all.count - 1) * fraction).rounded())
        reader.scrollTo(all[min(max(at, 0), all.count - 1)].tag, anchor: .top)
    }

    /// Commits what an open text cell holds and closes the editor. Safe to
    /// call when nothing is open.
    private func closeOpenCell() {
        guard state.editing else { return }
        commitOpenCell()
        state.editing = false
        state.editSeed = ""
    }

    private var cursorRow: ViewModel.Row? {
        everyRow.first { $0.id == state.cursorShot }
    }

    // ------------------------------------------------------------------ header

    private var header: some View {
        HStack(spacing: 0) {
            // **"Shot", not "#", and on the one left edge.**
            Text("Shot").label(dark, size: Brand.type(Brand.Size.tiny))
                .padding(.leading, Columns.edge)
                .frame(width: Columns.gutter, alignment: .leading)
                .padding(.trailing, 10)
            ForEach(columns, id: \.self) { name in
                headerCell(name)
            }
        }
        .frame(height: 32)
        .background(Brand.surface(dark))
        .hairline(.bottom, Brand.rule(dark))
    }

    /// One column's name: click sorts, drag carries it to a new place, and
    /// the trailing edge is the resize handle. All three are the old app's
    /// behaviours; the *carrying* is a plain drag gesture rather than the old
    /// app's macOS drag-and-drop, deliberately — the harness cannot drive a
    /// drag-and-drop session, and a gesture the checks cannot reach is how
    /// this table shipped broken three times.
    private func headerCell(_ name: String) -> some View {
        let sorted = state.view?.filter.sortColumn == name
        let down = state.view?.filter.sortDescending ?? false
        let carried = state.carrying == name
        // No gestures here, deliberately. SwiftUI drag gestures inside this
        // scroll view fire for taps and never for drags — the horizontal axis
        // belongs to the scroll machinery whatever priority is claimed. So
        // the header does what the table already does for keys: the window
        // mouse monitor reads presses against the frames these cells report,
        // and this view only draws. One owner, and a gesture the checks can
        // actually drive.
        // **Words only, no field-type glyph** — his call, 2026-09-15 — and the
        // text starts where the cell's content starts, so a column reads as
        // one line top to bottom.
        return HStack(spacing: 4) {
            Text(Columns.label(name)).label(dark, size: Brand.type(Brand.Size.tiny))
            if sorted {
                Image(systemName: down ? "arrow.down" : "arrow.up")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Brand.accent(dark))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Brand.pad(9))
        .frame(width: Columns.width(name), alignment: .leading)
        .frame(maxHeight: .infinity)
        .id("head:" + name)
        .contentShape(Rectangle())
        .opacity(carried ? 0.35 : 1)
        // The landing line: where the carried column will go if let go now.
        .overlay(alignment: .leading) {
            if state.carrying != nil, state.landing == name {
                Rectangle().fill(Brand.accent(dark)).frame(width: 2)
            }
        }
        // The right edge glows while it is being pulled.
        .overlay(alignment: .trailing) {
            if resizing == name {
                Rectangle().fill(Brand.accent(dark)).frame(width: 2)
            }
        }
        // The pull band wears the ↔ cursor, so the edge says what it is
        // before it is pulled. Ten points against the monitor's nine: hover
        // and hit-test are read by different machinery, and a band that
        // shows the cursor a point early is honest — one that shows it a
        // point late promises nothing where a pull would in fact work.
        .overlay(alignment: .trailing) {
            Color.clear.frame(width: 10)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                }
        }
        // Same as the rows: `hoveringHeader` was written here and read
        // nowhere, and every crossing rebuilt the table.
        .background {
            GeometryReader { geo in
                let frame = geo.frame(in: .global)
                Color.clear
                    .onAppear { state.headerFrames[name] = frame }
                    .onChange(of: frame) { _, now in state.headerFrames[name] = now }
                    .onDisappear { state.headerFrames.removeValue(forKey: name) }
            }
        }
        .help("Sort by \(Columns.label(name).lowercased()) · drag to move or resize")
        .contextMenu {
            if name == "lens" {
                Button("Sort Ascending") { state.replace(state.engine?.sortBy(name, descending: false)) }
                Button("Sort Descending") { state.replace(state.engine?.sortBy(name, descending: true)) }
                Divider()
                Button("Hide Column") { state.replace(state.engine?.column(name, visible: false)) }
            }
        }
    }


    // -------------------------------------------------------------------- rows

    private func line(_ row: ViewModel.Row, alternate: Bool) -> some View {
        let onCursor = state.cursorShot == row.id
        let carried = state.carryingRow == row.id
        let lastRow = state.shootingOrder
            ? state.lastInDay.contains(row.id)
            : rows.last?.id == row.id
        // The row is as tall as what is in it, with the old fixed height as a
        // floor. Fixed height is what clipped a cell holding three chips, and a
        // chip you cannot read is not a smaller chip — it is a wrong one.
        // **The row places its own cells** — see `RowLayout`. This was an
        // `HStack(alignment: .top)` under `.frame(minHeight:)` and
        // `.fixedSize(horizontal: false, vertical: true)`, which asked SwiftUI
        // to solve a puzzle with two contradictory clues in it, and three
        // recorded hangs died trying.
        return RowLayout(floor: Brand.rowHeight) {
            gutter(row, onCursor: onCursor)
            ForEach(columns, id: \.self) { name in
                cell(row, name, onCursor: onCursor)
            }
        }
        .background {
            // **A rounded block, inset from the well's edges** — the mock's
            // row, and the other half of "reads like a list rather than a
            // spreadsheet". A full-bleed stripe is a table row; a floating
            // block is an item.
            //
            // A shot's colour dresses the whole row — his call: a dot was too
            // quiet to find a marked shot down a long list. It sits under the
            // cursor and selection tints rather than replacing them, and it is
            // a wash, not the colour itself, because the text has to stay
            // readable on it in both appearances.
            // **Square.** His rule, once more: everything cut into the table
            // keeps its rectangle, and a row is as cut-in as a thing gets.
            // These corners were left from when a row was meant to read as a
            // floating block; the scene bands and the thumbnails went square
            // and the rows did not.
            let shape = Rectangle()
            ZStack {
                if let colour = row.colour {
                    // Softer over near-black than it was over grey: the same wash
                    // that read as a tint on #232326 reads as a solid block on
                    // #0E0E11. It stays a wash rather than becoming the dot the
                    // mock uses — a dot was his original complaint.
                    shape.fill(Brand.data(colour, dark).opacity(dark ? 0.17 : 0.15))
                }
                // **No zebra.** The mock stripes nothing: the block under the
                // row you are on carries the reading, and alternating bands
                // over near-black look like a rendering fault rather than a
                // help. The block is grey rather than blue, too — the mock
                // keeps blue for the one thing that is *chosen* (its tab), and
                // that restraint is a lot of why its chrome looks calm.
                // **Nothing under the row the cursor is in.** There was a
                // quiet grey block there and he cut it: "just the blue box
                // around the cell — it's unneeded and visually too much." He
                // is right, and the reason is that it said the same thing
                // twice. The cell already wears a blue outline saying where
                // the cursor is; a band across the whole row behind it is a
                // second answer to a question already answered, and over
                // near-black it reads as heavier than it is.
                //
                // A *selected* shot still fills — that is a different claim
                // (this shot is what a key will act on) and it earns its
                // block. Hover still fills, because it is transient and it is
                // the only thing that says a row is reachable.
                if state.marked.contains(row.id) {
                    shape.fill(Brand.accentTint(dark))
                        .overlay { shape.strokeBorder(Brand.accentLine(dark), lineWidth: 1) }
                }
                // **No hover wash.** Every row lighting up as the pointer
                // crosses it is motion nobody asked for while reading a list —
                // "it just adds too much visual stimulation". The cursor's blue
                // box says where you are; nothing needs to say where the mouse
                // merely is.
            }
            .padding(.horizontal, Brand.rowInset)
        }
        // A separator, and a faint one: the block above carries the reading.
        .overlay(alignment: .bottom) {
            // **The alpha lives in the colour, not in a layer.** An
            // `.opacity` *modifier* makes SwiftUI composite the view through
            // a constant mask — and on his HDR display that compositing is
            // done in sixteen-bit float, in software, on the CPU: it was the
            // single largest non-idle entry in a profile of a fast scroll.
            // Folding it into the colour makes the rule a plain fill.
            // Measured at about four per cent of the scroll's CPU, which is
            // inside the noise — kept because it is also simpler, not because
            // the stopwatch could see it.
            // The rule stays under the cursor's row now that no block covers
            // it — a line that vanished under an invisible block would just
            // be a gap.
            Brand.rule(dark).opacity(state.marked.contains(row.id) ? 0 : 0.7)
                .frame(height: 1)
                .padding(.horizontal, Brand.rowInset + 4)
        }
        // A picture dropped anywhere on the row lands on its shot — same one
        // door as ⌘V and the media window.
        .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
            Drops.take(providers, onto: row, state: state)
        }
        // Carried rows ghost, the way a carried header does, and the landing
        // line says where the shot will sit when let go — in front of this
        // row, or under the last one for the foot of the scene.
        .opacity(carried ? 0.35 : 1)
        // **The whole shot, ringed.** His ask: "when I do select it, I should
        // see a blue bar around the shot." A cell selection outlines one cell;
        // this outlines the row, so the two selections cannot be mistaken for
        // one another — and it is the state in which the shot can be carried.
        .overlay {
            if state.wholeShots.contains(row.id) {
                Rectangle()
                    .strokeBorder(Brand.accent(dark), lineWidth: 2)
                    .padding(.horizontal, Brand.rowInset)
            }
        }
        .overlay(alignment: .top) {
            if state.carryingRow != nil, state.landingRow == row.id {
                Rectangle().fill(Brand.accent(dark)).frame(height: 2)
            }
        }
        .overlay(alignment: .bottom) {
            if state.carryingRow != nil, state.landingRow == nil, lastRow {
                Rectangle().fill(Brand.accent(dark)).frame(height: 2)
            }
        }
        // The row being typed in draws above its neighbours, so an open cell's
        // list of what the project already knows is not clipped by the row
        // underneath it.
        .zIndex(state.cursorShot == row.id && state.editing ? 1 : 0)
        // **Nothing hovers here any more, so nothing watches for it.**
        //
        // There was an `.onHover` on every row writing `@State` that nothing
        // read — left behind when the hover wash was cut ("it just adds too
        // much visual stimulation"). Writing `@State` invalidates the *whole*
        // table, and rows stream under a still pointer while a scroll runs, so
        // a fast scroll rebuilt the entire list once per row it passed, to
        // store a value no view has ever drawn from. The cheapest work is the
        // work nobody asked for.
    }

    /// **A row measures its cells once, then places them. It does not
    /// negotiate.**
    ///
    /// This exists because of three hangs macOS recorded on 2026-08-23 and
    /// kept in `/Library/Logs/DiagnosticReports/ShotlisterStudio_*.hang`. All
    /// three are the main thread inside Apple's layout engine — 383, 1,014 and
    /// **1,167 stack frames deep**, going round `StackLayout` →
    /// `_FlexFrameLayout.sizeThatFits` → `LayoutProxy.size` → back about a
    /// hundred times, bottoming out in text measurement, with
    /// **`_FixedSizeLayout` five times inside the cycle**. Memory reached
    /// 1,208 MB, 1,258 MB and **9,433 MB**; the app was unresponsive for 59,
    /// 30 and **763 seconds**. None of our own code appears in any of the
    /// three stacks: the view bodies had already run, and this is the sizing
    /// pass afterwards failing to settle. His report, 2026-08-29: *"the
    /// freezing happens when you are scrolling really fast up and down the
    /// shot list"* — and it needed a force quit.
    ///
    /// **What it was being asked.** Every cell said `maxHeight: .infinity` —
    /// *I will take unlimited height* — and the row was then wrapped in
    /// `.fixedSize(vertical: true)`, which asks *so what is your ideal
    /// height?* Both were put there for real bugs he reported: without the
    /// ideal-height request a cell holding three chips was clipped, and
    /// without the unlimited heights a cell's background stops filling its
    /// row. Neither could simply be deleted, which is why this replaces the
    /// question rather than answering it.
    ///
    /// **What it does instead**, in a fixed number of steps that cannot grow:
    ///
    /// 1. ask each cell once, unproposed, how big it would like to be
    /// 2. the row is the tallest answer, or `floor`, whichever is greater
    /// 3. place each cell at its own width and *that* height
    ///
    /// One pass down, one pass back. There is no iteration to fail to
    /// converge, so the shape of all three hangs cannot occur here. Cells keep
    /// `maxHeight: .infinity` on purpose — step 3 hands them a concrete height
    /// and that is what makes them fill it, which is what keeps a selected
    /// cell's blue box the height of the row.
    ///
    /// **The one thing to be careful of** is step 1. An unproposed
    /// measurement of a view wearing `maxHeight: .infinity` is supposed to
    /// give its *ideal* height, not infinity — but a wrong answer there would
    /// be an infinitely tall row, so it is clamped rather than trusted, and it
    /// says so out loud during a checking run rather than drawing something
    /// strange in silence.
    private struct RowLayout: Layout {
        let floor: CGFloat

        /// Well past any row a person would make, and far short of a number
        /// that breaks layout. Only a measurement that has gone wrong reaches
        /// it.
        private static let sane: CGFloat = 4000

        private func height(of subviews: Subviews) -> CGFloat {
            var tallest = floor
            for view in subviews {
                let asked = view.sizeThatFits(.unspecified).height
                guard asked.isFinite, asked <= Self.sane else {
                    if Launch.checking {
                        FileHandle.standardError.write(Data((
                            "ROW MEASURE: a cell asked for \(asked) points of "
                            + "height — clamped. The unproposed measurement is "
                            + "not behaving as assumed; read RowLayout.\n").utf8))
                    }
                    continue
                }
                tallest = max(tallest, asked)
            }
            // **Not rounded.** Rounding up was tried on 2026-08-29 to chase a
            // one-point shift, and it made every posture differ instead of
            // fewer: the stack this replaces did not round either, and the
            // measurement it gives back already matches. Left alone, with the
            // number written down.
            return tallest
        }

        func sizeThatFits(proposal: ProposedViewSize,
                          subviews: Subviews,
                          cache: inout ()) -> CGSize {
            CGSize(width: subviews.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width },
                   height: height(of: subviews))
        }

        func placeSubviews(in bounds: CGRect,
                           proposal: ProposedViewSize,
                           subviews: Subviews,
                           cache: inout ()) {
            var x = bounds.minX
            for view in subviews {
                let width = view.sizeThatFits(.unspecified).width
                view.place(at: CGPoint(x: x, y: bounds.minY),
                           anchor: .topLeading,
                           proposal: ProposedViewSize(width: width,
                                                      height: bounds.height))
                x += width
            }
        }
    }

    /// The shot number, in a gutter of constant width.
    ///
    /// Constant is the point. In the old app ticking a box changed the gutter's
    /// width and shifted every column of every row; the slot is reserved whether
    /// anything is in it or not, so nothing ever reflows.
    private func gutter(_ row: ViewModel.Row, onCursor: Bool) -> some View {
        HStack(spacing: 0) {
            // **On the one left edge, in the sans, tabular** — numbers match
            // everywhere: scene numbers semibold, shot numbers medium.
            VStack(alignment: .leading, spacing: 2) {
                Text(row.number)
                    .sans(Brand.type(11), weight: onCursor ? .semibold : .medium)
                    .monospacedDigit()
                    .foregroundStyle(row.struck ? Brand.ink4(dark) : Brand.ink2(dark))
                    .strikethrough(row.struck, pattern: .solid, color: Brand.ink4(dark))
                // **Which shot this one is**, under its own number and in the
                // gutter's own width so nothing reflows. His ask: *"you would
                // know what shot it was referring to, even if it was in another
                // scene."* A master says so too, or the arrow would point at
                // something with no sign of being pointed at.
                //
                // **Big enough to see.** His note: the two marks were *"way
                // too small and indescrete."* They were 8.5-point text, and
                // the master's M was drawn in `ink4` — the faintest ink there
                // is, the one kept for things that are absent. A shot being a
                // master is not an absence. Both now wear a tinted pill at 10
                // point, which is what makes them read as a mark rather than
                // as a stray character under the number.
                if let to = row.linkedTo {
                    Mark(text: "→\(to)", ink: Brand.accent(dark),
                         tint: Brand.accentTint(dark))
                        .help("Standing in for \(to)")
                } else if row.isMaster {
                    Mark(text: "M", ink: Brand.ink2(dark),
                         tint: Brand.ink3(dark).opacity(dark ? 0.30 : 0.18))
                        .help("Other shots stand in for this one")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, Columns.edge)
        .frame(width: Columns.gutter, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 10)
        .padding(.trailing, 10)
        // **No dot.** The shot's colour was worn twice — as a wash across the
        // whole row and again as a dot beside the number — and the dot sat
        // exactly where the row's selection ring runs, so the two collided.
        // His call: "I don't even think we need the dot. We can just live with
        // seeing the highlighted colour." The wash says it, and says it louder.
        .contentShape(Rectangle())
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: Frames.self,
                                       value: [row.id: rounded(geo.frame(in: .global))])
            }
        }
        .onTapGesture { pick(row, column: columns.first ?? "description") }
        // **The shot's own menu**, on its number: the same actions the bar
        // carries, in the same order and in the same words.
        .contextMenu { shotActions(held(row)) }
        // **Edit Reference's bracket** (the mod's socket A), in the margin
        // left of the number; nothing at all for a project without it.
        .overlay(alignment: .topLeading) {
            if let pieces = state.editPieces[row.id] {
                ForEach(pieces, id: \.ref.id) { piece in
                    EditBracketPiece(piece: piece, dark: dark) { at in
                        state.editRefFrom = at
                        state.editRefPlaying = piece.ref.id
                    }
                        .offset(x: Columns.edge - 21 - CGFloat(piece.lane) * 8)
                }
            }
        }
    }

    /// An edit reference's bracket passing this heading or "Add shot".
    @ViewBuilder
    private func editThrough(_ spot: String) -> some View {
        if let pieces = state.editThrough[spot] {
            EditBracketThrough(pieces: pieces, dark: dark)
        }
    }

    @ViewBuilder
    private func cell(_ row: ViewModel.Row, _ name: String, onCursor: Bool) -> some View {
        let live = onCursor && state.cursorColumn == name
        let editing = live && state.editing

        Group {
            if name == "image" {
                Thumbnail(
                    row: row,
                    engine: state.engine,
                    ratio: CGFloat(state.view?.project.ratio ?? 2.39),
                    dark: dark,
                    // **Handed in, not looked up.** Same reason as `Chip`'s
                    // density: read inside the thumbnail's own body, a column
                    // width is invisible to SwiftUI's "did anything change?"
                    // check, so dragging the image column resized the cell and
                    // left the picture at its old size until some other edit
                    // forced a repaint — which is why it looked like the
                    // pictures were changing shape rather than lagging.
                    width: Columns.width("image")
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                // Belt to the floor's braces: whatever width the column
                // reaches, its picture never draws over the neighbours.
                .clipped()
            } else {
                Columns.draw(row, name, dark: dark)
            }
        }
        // The cell hands its own rectangle up to the layer that draws the open
        // editor, and nothing else. Only the live one answers.
        .anchorPreference(key: OpenCell.self, value: .bounds) { live ? $0 : nil }
        .frame(width: Columns.width(name), alignment: .topLeading)
        // **A cell keeps its words inside its column.** Squeeze Title narrow
        // enough and a word longer than the column drew straight across the
        // thumbnail next door — his screenshot. Wrapping only helps while
        // there is somewhere to wrap *to*; below a word's own width there is
        // nothing for it but to be clipped, and clipped is the honest answer.
        // Applied here, outside the open-cell anchor, so the editor that
        // deliberately grows past its column still can.
        .clipped()
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background {
            // **A dragged range reads blue, and shows its own outline** — his
            // note, with a sheet beside it: "I should see blue boxes growing
            // over every cell I'd click and drag down through… right now it's
            // just kind of this awkward grey." Grey said *something is
            // covered*; blue says *this is chosen*, which is what it is.
            //
            // The border is drawn per cell on the sides that face *out* of the
            // range, so a block of cells gets one outline around the block
            // rather than a grid of boxes.
            if state.cellRange != nil,
               let side = edges(rangeCells, row.id, name) {
                Brand.accentTint(dark)
                RangeEdge(top: side.top, bottom: side.bottom,
                          leading: side.leading, trailing: side.trailing,
                          colour: Brand.accent(dark))
            }
            // **What was copied wears a dashed outline** until Esc, an edit or
            // the paste of a cut — the sheet's marching ants.
            if let copied = state.copiedCells,
               let side = edges(rect(of: copied), row.id, name) {
                RangeEdge(top: side.top, bottom: side.bottom,
                          leading: side.leading, trailing: side.trailing,
                          colour: Brand.accent(dark), dash: [5, 4])
            }
            // The cursor's own outline stands down while the *whole shot* is
            // selected: the row already wears a ring, and a second box inside
            // it — usually over the picture — is the same fact twice. His
            // words: "the image also gets a square over it… it's just
            // redundant information."
            if live && !editing, !state.wholeShots.contains(row.id) {
                Rectangle()
                    .strokeBorder(Brand.accent(dark), lineWidth: 1.5)
                    .padding(2)
            }
        }
        .contentShape(Rectangle())
        // One gesture, reading the click count off the event. Stacking a
        // double-tap over a single-tap makes SwiftUI hold *every* click for the
        // double-click interval — about a quarter second — which is what made
        // the old table feel a beat behind the keyboard. First click lands
        // instantly; a second within the interval opens the editor.
        .contextMenu {
            // **A shot picked whole gets the shot's menu**, wherever in its row
            // the press lands. His ask: "highlights should be present in pop up
            // menu when selecting whole shots." The cell menu is about one
            // value — copy, paste, clear — and none of that is what a person
            // means when they have four whole shots picked and want to colour
            // them. The gutter's menu was already the right one; this is the
            // same menu for the rest of the row.
            if state.wholeShots.contains(row.id) {
                shotActions(held(row))
            } else if name == "image" {
                Button("Frames…") { FrameWindows.shared.open(for: row.id, state: state) }
                Button("Add image…") { Ingest.addViaPanel(to: row, state: state) }
                Button("Paste") {
                    if !Ingest.fromPasteboard(onto: [row], state: state) {
                        state.say("Nothing to paste")
                    }
                }
                if let frame = row.frame {
                    Button("Copy frame") {
                        if let picture = Thumbs.shared.image(frame, from: state.engine) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.writeObjects([picture])
                            state.say("Copied the frame.")
                        }
                    }
                }
            } else if Columns.clearable(name) {
                Button("Copy") { copyCells([row], [name]) }
                Button("Paste") { pasteCells([row], [name]) }
                Button("Cut") { cutCells([row], [name]) }
                Divider()
                Button("Clear") { write(row, name, "") }
            } else if name != "struck" {
                // The cells that hold no text of their own (the day, the
                // script's words, a project column of pictures or places)
                // still copy.
                Button("Copy") { copyCells([row], [name]) }
            }
        }
        .onTapGesture {
            let clicks = NSApp.currentEvent?.clickCount ?? 1
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            pick(row, column: name)
            // A second click opens the cell **on what is in it**. Opening it
            // empty is not a smaller version of this: it means the next commit
            // writes nothing over a value the person could still see. A click
            // carrying shift or ⌘ is *selecting*, never editing — however
            // many times it lands.
            if clicks > 1 && !flags.contains(.shift) && !flags.contains(.command) {
                openForEditing(row, name)
            }
        }
    }

    // -------------------------------------------------------- the open cell

    /// Where the cell being edited is, in the table's own coordinates.
    /// **Where things are, collected once per layout pass.**
    ///
    /// This replaced a `GeometryReader` per row and per scene line writing
    /// straight into `@Published` state — which is a write *during* the view
    /// update, so each one re-rendered the table, which recomputed the
    /// frames, which wrote again. With one scene on screen it merely churned;
    /// with the whole script it locked the app solid at 100% of a core, which
    /// is how Nathaniel found it.
    ///
    /// A preference is the sanctioned way round: SwiftUI gathers them after
    /// layout and hands them over once, outside the update. Values are
    /// rounded to whole points as well, so a half-pixel of scroll cannot
    /// start the cycle again.
    private struct Frames: PreferenceKey {
        static let defaultValue: [String: CGRect] = [:]
        static func reduce(value: inout [String: CGRect],
                           nextValue: () -> [String: CGRect]) {
            value.merge(nextValue()) { _, new in new }
        }
    }

    /// Reported the same way, for the same reason: the scrollbar needs to
    /// know where the content is, and asking for that on every frame of a
    /// scroll was half the loop.
    private struct ScrollMetrics: Equatable {
        var offset: CGFloat = 0
        var content: CGFloat = 0
    }

    private struct Scrolling: PreferenceKey {
        static let defaultValue = ScrollMetrics()
        static func reduce(value: inout ScrollMetrics, nextValue: () -> ScrollMetrics) {
            let next = nextValue()
            if next.content > 0 { value = next }
        }
    }

    private struct OpenCell: PreferenceKey {
        static let defaultValue: Anchor<CGRect>? = nil
        static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
            if let next = nextValue() { value = next }
        }
    }

    /// The editor, drawn at the cell's own place.
    ///
    /// Two shapes, and which one you get is the cell's type rather than a mode
    /// anyone has to think about. A text cell becomes a box that grows downward
    /// as the sentence runs on. A choice cell becomes the same box with the
    /// project's list hanging under its left edge — **popovers yes for choices,
    /// pop-out text entry never**, and this is in place either way: it opens on
    /// top of the cell it belongs to, at its width, not in the middle of the
    /// window.
    @ViewBuilder
    private func openCell(_ row: ViewModel.Row, in rect: CGRect, within size: CGSize) -> some View {
        let choice = Columns.isVocabulary(state.cursorColumn)
        let entries = self.entries(row)
        // A list needs room. If the cell is near the foot of the window the
        // list goes above it instead of off the bottom edge, which is the one
        // place a sheet's dropdown ever moves.
        let stackedPicker = state.cursorColumn == "lens"
        let wanted = min(CGFloat(entries.count) * 27 + 58 + (stackedPicker ? 60 : 0), stackedPicker ? 400 : 264)
        let below = size.height - rect.maxY
        let above = rect.minY
        let flip = choice && below < wanted && above > below
        let tall = min(wanted, max((flip ? above : below) - 6, 90))
        // The list hangs from the cell's left edge, except when that would put
        // it through the right-hand wall — the last columns of a wide table are
        // *always* against that wall, so this is the ordinary case rather than
        // the corner one. It slides left just far enough to fit.
        let listLeft = min(rect.minX, max(size.width - 268 - 8, 0))
        // A sheet's editor is not stuck at the width of its column: a lens
        // column is 96pt wide and a sentence typed into one at that width is
        // unreadable while you are writing it. It widens rightwards, and stops
        // at the window's edge like everything else here.
        let boxWidth = choice ? rect.width : max(rect.width, Brand.pad(260))
        let boxLeft = min(rect.minX, max(size.width - boxWidth - 8, 0))

        // Positioned with padding — real layout — and never with `.offset`.
        // An offset is a rendering transform: the pixels move, but an AppKit
        // view hosted inside keeps its untransformed frame for hit-testing.
        // The editor drew exactly on its cell while its clickable frame sat
        // eighty points to the right, so clicking the next cell clicked the
        // invisible edge of the editor instead — and a click on a text view
        // asks the window to become key, which is the one thing a checking
        // run must never cause. Layout padding moves the real frame.
        ZStack(alignment: .topLeading) {
            typedBox(row, width: boxWidth)
                .padding(.leading, max(boxLeft, 0))
                .padding(.top, max(rect.minY, 0))
            if choice {
                list(row, entries: entries, height: tall)
                    .padding(.leading, max(listLeft, 0))
                    .padding(.top, max(flip ? rect.minY - tall - 3 : rect.maxY + 3, 0))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// A left-eighth block, which reads as a text cursor at this size.
    private static let caret = "\u{258F}"

    /// The cell itself while it is open.
    ///
    /// A text cell becomes a real text view — caret, drag-to-select, ⌘A, ⌘C,
    /// Shift-Return — living exactly where the cell is. A choice cell shows
    /// what is being typed at it, which is a filter rather than a value, and
    /// keeps showing what it holds until something is typed: opening a list
    /// must not blank the value you are about to change.
    @ViewBuilder
    private func typedBox(_ row: ViewModel.Row, width: CGFloat) -> some View {
        let name = state.cursorColumn
        if Columns.isVocabulary(name) {
            HStack(alignment: .top, spacing: 0) {
                if state.editSeed.isEmpty {
                    Columns.draw(row, name, dark: dark)
                } else {
                    (Text(state.editSeed).foregroundStyle(Brand.ink(dark))
                     + Text(Self.caret).foregroundStyle(Brand.accent(dark)))
                        .sans(Brand.type(13))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    Spacer(minLength: 0)
                }
            }
            .frame(width: width, alignment: .topLeading)
            .frame(minHeight: Brand.rowHeight, alignment: .topLeading)
            .background { openCellGround }
        } else {
            CellText(
                text: $state.editSeed,
                live: $state.editorLive,
                height: $typedHeight,
                width: width - 18,
                size: Columns.fontSize(name),
                dark: dark,
                freshTyping: state.editOpenedByTyping,
                leave: { how in
                    switch how {
                    case .here: commitAndStep(rows: 0, columns: 0)
                    case .down: commitAndStep(rows: 1, columns: 0)
                    case .up: commitAndStep(rows: -1, columns: 0)
                    case .right: commitAndStep(rows: 0, columns: 1)
                    case .left: commitAndStep(rows: 0, columns: -1)
                    case .tabNext: commitAndStep(back: false)
                    case .tabBack: commitAndStep(back: true)
                    case .cancel: state.editing = false; state.editSeed = ""
                    }
                }
            )
            // A fresh view per cell. Without this SwiftUI reuses the same one
            // for the next cell opened, and a reused view does not pass through
            // `viewDidMoveToWindow` again — so it never asks for the keyboard,
            // and the second cell of the day would be typed into by the
            // fallback rather than by the editor.
            .id("\(row.id)/\(name)")
            .frame(width: width - 18, height: max(typedHeight, Brand.rowHeight - 14),
                   alignment: .topLeading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            // Grows down, never up: the top edge stays welded to the cell so
            // the row being typed in does not slide out from under the cursor.
            .frame(width: width, alignment: .topLeading)
            .frame(minHeight: Brand.rowHeight, alignment: .topLeading)
            .background { openCellGround }
        }
    }

    private var openCellGround: some View {
        // **Square, and the cell's own size.** It was a rounded card, on the
        // reasoning that a thing we draw ourselves floats. It does not: an open
        // cell is the cell, opened — you are typing *in the table*, not into a
        // panel that has appeared over it. His note: "when I double-click the
        // cell there are still rounded corners inside that cell; it should just
        // be the same size as the square cell."
        //
        // Same rule as everywhere else in this table, which is now the whole of
        // it: what is cut in keeps its rectangle.
        Rectangle()
            .fill(Brand.panel(dark))
            .overlay {
                Rectangle().strokeBorder(Brand.accent(dark), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(dark ? 0.55 : 0.16), radius: 14, y: 4)
    }

    /// What the open list is offering, in the order Return will take them.
    private func entries(_ row: ViewModel.Row) -> [Pick] {
        let name = state.cursorColumn
        guard Columns.isVocabulary(name) else { return [] }
        let options = Columns.options(name, state: state)
        var out = Columns.rank(options, query: state.editSeed).map { Pick.value($0) }
        // **Lens Stack: one picker.** The lenses, then the shoot's filters and
        // modifiers (the project's lists, which the spec sheet feeds).
        if name == "lens" {
            for filter in Columns.rank(Columns.options("lens_filters", state: state), query: state.editSeed) {
                out.append(.attach(field: "lens_filters", name: filter))
            }
            for modifier in Columns.rank(Columns.options("modifiers", state: state), query: state.editSeed) {
                out.append(.attach(field: "modifiers", name: modifier))
            }
        }
        // Creating a term comes last, so typing "Pro" and pressing Return takes
        // Profile rather than inventing a second word for the same thing. The
        // engine's rule — a new value teaches the project — is kept, but it
        // stops being what happens by accident when you type half a word.
        if Columns.canCreate(name, state: state), let novel = Columns.novel(options, query: state.editSeed) {
            out.append(.create(novel))
        }
        return out
    }

    @ViewBuilder
    private func list(_ row: ViewModel.Row, entries: [Pick], height: CGFloat) -> some View {
        let held = Columns.chosen(row, state.cursorColumn)
        VStack(alignment: .leading, spacing: 0) {
            // Cadrage's form, kept: a line saying what this is. It is a label
            // rather than a second place to type — the characters go into the
            // cell, where the caret is, and there is only ever one buffer.
            if state.editSeed.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11)).foregroundStyle(Brand.ink4(dark))
                    Text(Columns.canCreate(state.cursorColumn, state: state)
                         ? "Search for an option or create one"
                         : "This list is locked — only what is on it")
                        .sans(Brand.type(13)).foregroundStyle(Brand.ink4(dark))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                Divider().overlay(Brand.rule(dark))
            }
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { at, entry in
                            if let head = Self.heading(entries, at: at) {
                                Text(head).label(dark, size: Brand.type(Brand.Size.tiny))
                                    .padding(.horizontal, 8).padding(.top, at == 0 ? 0 : 8).padding(.bottom, 2)
                            }
                            listRow(entry, at: at, held: held).id(at)
                        }
                        if entries.isEmpty {
                            Text("Empty")
                                .sans(Brand.type(13)).foregroundStyle(Brand.ink4(dark))
                                .padding(.horizontal, 8).padding(.vertical, 6)
                        }
                    }
                    .padding(6)
                    // The scroll stays in the list — see `ListScroll`. Inside
                    // the content, so there is an enclosing scroll view to find.
                    .background { ListScroll() }
                }
                .onChange(of: state.pickAt) { _, at in reader.scrollTo(at, anchor: nil) }
            }
        }
        .frame(width: 268, alignment: .leading)
        .frame(maxHeight: max(height, 90), alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            RoundedRectangle(cornerRadius: Brand.radiusChip)
                .fill(Brand.panel(dark))
                .shadow(color: .black.opacity(dark ? 0.55 : 0.18), radius: 12, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Brand.radiusChip).strokeBorder(Brand.rule(dark), lineWidth: 1)
        }
    }

    /// Lens Stack's picker is three short lists in one: a heading where each
    /// begins. Nothing on any other picker.
    private static func heading(_ entries: [Pick], at: Int) -> String? {
        func group(_ pick: Pick) -> String {
            if case .attach(let field, _) = pick { return field == "modifiers" ? "Modifiers" : "Filters" }
            return "Lens"
        }
        guard entries.contains(where: { if case .attach = $0 { return true } else { return false } })
        else { return nil }
        let here = group(entries[at])
        if at == 0 || group(entries[at - 1]) != here { return here }
        return nil
    }

    private func listRow(_ entry: Pick, at: Int, held: [String]) -> some View {
        let name = state.cursorColumn
        let lit = at == state.pickAt
        return HStack(spacing: 6) {
            Button {
                take(entry, keepOpen: Columns.isMulti(name) || name == "lens")
            } label: {
                HStack(spacing: 6) {
                    switch entry {
                    case .value(let option):
                        Chip(text: option, colour: Columns.chipColour(name, option, state: state, dark: dark))
                        if held.contains(option) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Brand.accent(dark))
                        }
                    case .attach(let field, let option):
                        Chip(text: option, colour: Brand.chipInk(field, option, dark))
                        if (field == "modifiers" ? cursorRow?.modifierList : cursorRow?.lensFilters)?.contains(option) == true {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Brand.accent(dark))
                        }
                    case .create(let novel):
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11)).foregroundStyle(Brand.accent(dark))
                        Text("Create “\(novel)”").sans(Brand.type(13), weight: .medium)
                            .foregroundStyle(Brand.ink(dark))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()

            // A camera is a unit the project owns, not a word on a list, so
            // there is nothing here to rename or remove from a vocabulary.
            if case .value(let option) = entry, Columns.canCreate(name, state: state) {
                Menu {
                    Button("Remove from the \(Columns.label(name)) list", role: .destructive) {
                        guard let engine = state.engine else { return }
                        _ = engine.removeValue(field: name, value: option)
                        state.replace(engine.view())
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.ink3(dark))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 18)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            if lit {
                RoundedRectangle(cornerRadius: Brand.radiusChip, style: .continuous).fill(Brand.accentTint(dark))
            }
        }
        .contentShape(Rectangle())
        // **The pointer moves the highlight**, so Return takes what you are
        // pointing at — the grammar of every menu on the Mac. The list used to
        // highlight from the keyboard alone, which is what "they stay static
        // as my mouse goes over them" was.
        .onHover { inside in
            guard inside, state.pickAt != at else { return }
            state.pickAt = at
            state.pickTouched = true
        }
    }

    /// Writes one picked entry. A filter or a modifier toggles on its own field;
    /// under Lens Stack the lens toggles too — click it again and it comes off.
    private func writePick(_ entry: Pick, on row: ViewModel.Row) {
        switch entry {
        case .value(let option):
            if state.cursorColumn == "lens",
               row.lens.caseInsensitiveCompare(option) == .orderedSame {
                write(row, "lens", "")
            } else {
                write(row, state.cursorColumn, option)
            }
        case .create(let novel): write(row, state.cursorColumn, novel)
        case .attach(let field, let name): write(row, field, name)
        }
    }

    /// Takes an entry from the open list.
    private func take(_ entry: Pick, keepOpen: Bool) {
        guard let row = cursorRow else { return }
        writePick(entry, on: row)
        if keepOpen {
            // A cell that holds several values lets you go on choosing — the
            // tick moves and the list stays where it is.
            state.editSeed = ""
            state.pickAt = 0
        } else {
            state.editing = false
            state.editSeed = ""
        }
    }

    /// The line a scene starts on, inside the table: its number, its heading
    /// and how many shots it holds. It is what makes one long table readable
    /// as a script rather than as a list that changed subject without saying.
    /// **The scene's own band** — and everything the scene carries.
    ///
    /// His ask, and the right shape: the detail belongs *in* the table, at the
    /// scene it describes, not in a heading strip above the whole list. The
    /// strip had to be re-drawn every time the reading scene changed, which is
    /// what the drag between scenes felt like; and it could only ever describe
    /// one scene while the table shows the whole script.
    ///
    /// Two lines. The first is what the script says and we never touch —
    /// number, slugline, how many shots. The second is what *he* has decided:
    /// synopsis, location, sequence, shoot day, tags, each editable where it
    /// is read, each wearing its own icon.
    /// **A day's band, in shooting order**: its name, its date, how many
    /// shots — and where it is, so a drag can tell which day it is over.
    private func dayBreak(_ group: ViewModel.Group) -> some View {
        let day = state.view?.days.first { $0.id == group.key }
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(group.key == nil ? "Not Scheduled" : group.label)
                .sans(Brand.type(20), weight: .bold)
                .foregroundStyle(Brand.ink(dark))
            if let when = day.flatMap({ Self.dayDate($0.date) }) {
                Text(when).sans(Brand.type(13)).foregroundStyle(Brand.ink2(dark))
            }
            Text(group.rows.count == 1 ? "1 shot" : "\(group.rows.count) shots")
                .sans(Brand.type(11)).foregroundStyle(Brand.ink3(dark))
            Spacer(minLength: 0)
        }
        .padding(.leading, Columns.edge)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface2(dark))
        .overlay(alignment: .bottom) { Brand.rule(dark).frame(height: 1) }
        .padding(.top, 14)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: Frames.self,
                                       value: ["scene:day:" + (group.key ?? ""): rounded(geo.frame(in: .global))])
            }
        }
    }

    /// `2026-10-06` as `Tue 6 Oct`; nothing for an undated day.
    static func dayDate(_ iso: String) -> String? {
        let read = DateFormatter()
        read.dateFormat = "yyyy-MM-dd"
        read.locale = Locale(identifier: "en_US_POSIX")
        guard let date = read.date(from: iso) else { return nil }
        let say = DateFormatter()
        say.dateFormat = "EEE d MMM"
        return say.string(from: date)
    }

    private func sceneBreak(_ sc: ViewModel.Scene) -> some View {
        // **The heading outranks what is under it.** His note: "the scene
        // header text itself should be visually more prominent than the things
        // below it — right now the parameters below almost dwarf it." They did,
        // and not because they were large: 14.5 against 12 is a step you cannot
        // see, and the line underneath is longer, busier and was in the same
        // full-strength ink. Length and count win a fight that close.
        //
        // So the heading goes to 18 and bold, and the line under it drops to 11
        // in second-rank ink with quieter icons. The gap does the work; nothing
        // needed to get louder.
        let shown = state.view?.filter.narrowed == true ? rows(of: sc).count : sc.count
        // **A commercial's band is a title, not a slug.** The number steps
        // back to second-rank ink, the title keeps the case it was typed in
        // (a slugline is shouted; a title is not), the AV pair sits under it,
        // and the slugline — when there is one — reads small in the facts
        // line. `design/22-commercial.html`, his rulings of 2026-09-14.
        let commercial = state.view?.project.isCommercial ?? false
        return VStack(alignment: .leading, spacing: 8) {
            // **Semibold, not bold; the count is plain text; "···" far right.**
            // The grammar of 2026-09-14: a count is a count, never a pill.
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(sc.number).sans(Brand.type(15), weight: .semibold).monospacedDigit()
                    .foregroundStyle(commercial ? Brand.ink3(dark) : Brand.ink(dark))
                Text(sc.heading)
                    .sans(Brand.type(15), weight: .semibold)
                    .textCase(commercial ? nil : .uppercase)
                    .foregroundStyle(Brand.ink(dark))
                    .lineLimit(1)
                // The number of shots you can *see*, which under a filter
                // is not the number the scene has. Saying "5 shots" over
                // three rows is how a filter gets mistaken for a deletion.
                Text("\(shown) \(shown == 1 ? "shot" : "shots")")
                    .sans(Brand.type(Brand.Size.small))
                    .foregroundStyle(Brand.ink3(dark))
                Spacer(minLength: 0)
                sceneMenu(sc)
            }
            sceneFacts(sc)
        }
        .padding(.leading, Columns.edge)
        .padding(.trailing, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Glass, painted rather than taken from the system. A real material
        // draws nothing into an offscreen bitmap, and an app that cannot
        // photograph itself cannot be checked — this project's oldest rule.
        .background {
            // **Cut in, not floating.** It was a rounded slab in the panel
            // grey, and he cut both: "the contrast in colour for the scene
            // header shouldn't be a light grey in dark mode… it should be a
            // darker colour" and "it should be squared off perfectly… that's
            // also distracting because it's inside the table."
            //
            // Both follow from the corner rule he gave me and I had applied
            // everywhere except here: **what floats turns a corner; what is
            // cut in keeps its rectangle.** A scene heading is not an object
            // sitting on the table, it is a division *of* it — so it is
            // square, it runs the full width, and it goes *darker* than the
            // well rather than lighter. Lighter made it the brightest thing
            // on a near-black screen, which is why it pulled the eye off the
            // shots it is only meant to introduce.
            Rectangle().fill(Brand.ground(dark))
        }
        .overlay(alignment: .top) { Brand.rule(dark).frame(height: 1).opacity(0.6) }
        .overlay(alignment: .bottom) { Brand.rule(dark).frame(height: 1).opacity(0.6) }
        .padding(.top, 14)
        // Each scene's band says where it is, so the table can tell which
        // scene is actually being read.
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: Frames.self,
                                       value: ["scene:" + sc.id: rounded(geo.frame(in: .global))])
            }
        }
        .contentShape(Rectangle())
        // Clicking a scene's band makes it the one the sidebar and the rest
        // of the chrome are talking about.
        .onTapGesture { state.sceneId = sc.id }
    }

    /// The second line of the band: the facts of the scene, edited in place.
    /// Which location this scene is shot at, chosen from the ones the project
    /// has. The same control as the scene's own page, in the band.
    @ViewBuilder
    private func sceneLocation(_ sc: ViewModel.Scene) -> some View {
        let places = state.view?.locations ?? []
        let held = sc.locations
        let chosen = places.filter { held.contains($0.id) }
        let slug = sc.location.trimmingCharacters(in: .whitespaces)
        Menu {
            // **Houses at the top, their rooms inside them** — Ref 269. A flat
            // list of thirty rooms from six houses is not a menu you can find
            // anything in.
            //
            // **Every one of them is a tick, not a jump.** His ask, 2026-08-22:
            // a scene that moves between places is shot at both, and the crew
            // needs both. Picking a place the scene is already at takes it off
            // again; picking another adds it after the ones already there.
            ForEach(places.filter { !$0.isArea }) { house in
                let rooms = places.filter { $0.parent == house.id }
                if rooms.isEmpty {
                    ticked(house.name, on: held.contains(house.id)) {
                        toggle(sc, house.id)
                    }
                } else {
                    Menu(house.name) {
                        ticked(house.name, on: held.contains(house.id)) {
                            toggle(sc, house.id)
                        }
                        Divider()
                        ForEach(rooms) { room in
                            ticked(room.name, on: held.contains(room.id)) {
                                toggle(sc, room.id)
                            }
                        }
                    }
                }
            }
            if !places.isEmpty { Divider() }
            // **The one door out of free text.** A scene whose slugline says
            // COUNTY JAIL and whose project has no such record is one click
            // from having one, named after the script rather than after
            // whatever somebody would have typed.
            if !slug.isEmpty, !places.contains(where: {
                $0.name.caseInsensitiveCompare(slug) == .orderedSame
            }) {
                Button("Make a location from “\(slug)”") {
                    guard let engine = state.engine else { return }
                    state.replace(engine.addLocation(name: slug))
                    if let made = state.view?.locations.first(where: {
                        $0.name.caseInsensitiveCompare(slug) == .orderedSame
                    }) {
                        state.replace(engine.sceneLocation(sc.id, made.id))
                    }
                }
            }
            Button("New location…") { state.addingLocation = true }
            if !chosen.isEmpty {
                Divider()
                Button("None") {
                    state.replace(state.engine?.sceneLocation(sc.id, ""))
                }
            }
        } label: {
            HStack(spacing: 4) {
                // **One `Text`, not two.** A count, not a list — two full names
                // side by side is wider than the rest of the line put together
                // — but it has to be *inside* the string: a borderless menu
                // draws its label's first views and silently drops what
                // trails, which is the same trap the scene page's own location
                // row fell into and wrote a comment about.
                // **The same size and weight as the sequence and the day
                // beside it.** All three are facts about the scene and all
                // three are `ink2`; this one was regular where they are
                // medium, and a fixed 12 where they scale with the table, so
                // it read as the faintest of the three — which, being the
                // location, it should not.
                Text(placeLabel(chosen, slug: slug))
                    .sans(Brand.type(11), weight: .medium).lineLimit(1)
            }
            // A value in ink; the slugline showing through, a shade quieter;
            // nothing at all, the quiet invitation.
            .foregroundStyle(!chosen.isEmpty ? Brand.ink(dark)
                             : (slug.isEmpty ? Brand.ink3(dark) : Brand.ink2(dark)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(chosen.count > 1
              ? chosen.map(\.fullName).joined(separator: " · ")
              : "Location")
    }

    /// What the band says: the first place, and how many more there are.
    private func placeLabel(_ chosen: [ViewModel.Location], slug: String) -> String {
        guard let first = chosen.first else {
            return slug.isEmpty ? "Add location" : slug
        }
        return chosen.count > 1 ? "\(first.fullName)  +\(chosen.count - 1)" : first.fullName
    }

    /// A menu row that says whether it is already on. The same shape the
    /// filter menus use, so a tick means the same thing everywhere.
    @ViewBuilder
    private func ticked(_ title: String, on: Bool,
                        _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            if on { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    /// On if it is off, off if it is on.
    private func toggle(_ sc: ViewModel.Scene, _ place: String) {
        guard let engine = state.engine else { return }
        state.replace(sc.locations.contains(place)
                      ? engine.removeSceneLocation(sc.id, place)
                      : engine.addSceneLocation(sc.id, place))
    }

    /// **A section's head across the table — a break, not a label.** His
    /// report on the first cut, 2026-09-19: *"the section headings are kind
    /// of small and don't really separate out the different scripts in a way
    /// that feels good."* Three scripts on one job are three shot lists in
    /// one, and the line between them has to read as a chapter: air above,
    /// a rule, the title at the scene heading's own size and weight, the
    /// section's colour as the one mark. A scene in none gets no head. The
    /// sidebar draws its own, smaller, off the same rule (`sectionHeadBefore`),
    /// so the two cannot disagree about where a section starts.
    private func sectionHead(_ section: ViewModel.Sequence?) -> some View {
        let ink = section.map { Brand.hex($0.colour) } ?? Brand.ink4(dark)
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Brand.rule(dark)).frame(height: 1)
            HStack(spacing: 10) {
                Text(section?.title ?? "")
                    .sans(Brand.type(20), weight: .bold)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, Columns.edge)
            // **Centred in its band** — his note, 2026-09-19. The air that
            // makes it a break is above the rule, not inside the band.
            .padding(.vertical, 18)
            // **The section's colour is the whole band's.** His finding, the
            // same day: three scripts were not telling apart while
            // scrolling. The head is tinted with the section's ink, the
            // title is set in it, and the same ink washes every scene and
            // shot in the run (`sectionWash`). No side bar (his call,
            // 2026-10-16: a light wash instead).
            .background(ink.opacity(Kit.sectionWash(dark: dark)))
        }
        .padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface2(dark))
        .contextMenu {
            if let section {
                Button("Delete Section…") { state.askToDeleteSection(section) }
            }
        }
    }

    /// The section's ink for a scene's spine, or nothing on a film or a
    /// scene in no section.
    private func spineInk(_ sc: ViewModel.Scene) -> Color? {
        guard state.view?.project.isCommercial == true,
              let section = state.sectionOf(sc) else { return nil }
        return Brand.hex(section.colour)
    }

    /// A commercial scene's slugline in the facts line — small, mono, quiet —
    /// or the two words that open the page to give it one.
    private func slugChip(_ sc: ViewModel.Scene) -> some View {
        HStack(spacing: 6) {
            if sc.slug.isEmpty {
                PlusLabel(text: "Add slugline", dark: dark)
            } else {
                Text(sc.slug)
                    .sans(Brand.type(11), weight: .medium)
                    .foregroundStyle(Brand.ink2(dark))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { state.editingScene = sc.id }
    }

    /// **The second line of the band is two groups, not five things** — the
    /// grammar of 2026-09-14. Values first: the location in ink, the sequence
    /// with its dot, the day — one weight, one gap, no field icons. Then a
    /// hairline, then the actions, drawn exactly like "+ Add shot" below.
    private func sceneFacts(_ sc: ViewModel.Scene) -> some View {
        let commercial = state.view?.project.isCommercial == true
        let tags = sc.tags.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let hasSynopsis = commercial ? !sc.slug.isEmpty : !sc.description.isEmpty
        return HStack(spacing: 0) {
            HStack(spacing: 16) {
                if hasSynopsis {
                    if commercial {
                        slugChip(sc)
                    } else {
                        // Grows when you click it rather than opening
                        // anything: one line at rest, the whole of it while
                        // you are in it — his call.
                        SynopsisField(text: sc.description, dark: dark) {
                            state.editingScene = sc.id
                        }
                    }
                }
                sceneLocation(sc)
                sequenceMenu(sc)
                dayMenu(sc)
                if !tags.isEmpty {
                    SceneTags(held: tags, options: state.engine?.vocabulary("tags") ?? [],
                              dark: dark, part: .chips) { next in
                        state.writeScene(sc, "tags", next.joined(separator: ", "))
                    }
                }
            }
            Brand.rule2(dark).frame(width: 1, height: 16)
                .padding(.leading, 16).padding(.trailing, 12)
            HStack(spacing: 14) {
                if !hasSynopsis {
                    Button {
                        state.editingScene = sc.id
                    } label: {
                        PlusLabel(text: commercial ? "Add slugline" : "Add synopsis", dark: dark)
                    }
                    .buttonStyle(.rowAction)
                    .focusEffectDisabled()
                }
                SceneTags(held: tags, options: state.engine?.vocabulary("tags") ?? [],
                          dark: dark, part: .adder) { next in
                    state.writeScene(sc, "tags", next.joined(separator: ", "))
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// A sequence is a record the project owns, so this offers what the
    /// project has rather than free text — and can name a new one into
    /// existence, which is the one grouping the script does not dictate.
    private func sequenceMenu(_ sc: ViewModel.Scene) -> some View {
        Menu {
            Button("None") {
                state.replace(state.engine?.set(shot: sc.id, field: "sequence", value: ""))
            }
            Divider()
            ForEach(state.view?.sequences ?? []) { seq in
                Button(seq.title) {
                    state.replace(state.engine?.set(shot: sc.id,
                                                    field: "sequence", value: seq.id))
                }
            }
            Divider()
            Button(state.view?.project.isCommercial == true ? "New section…" : "New sequence…") {
                state.namingSequence = sc.id
            }
        } label: {
            HStack(spacing: 6) {
                if let seq = state.sequenceOf(sc) {
                    // The dot stays: that colour means something.
                    if !seq.colour.isEmpty {
                        Circle().fill(Brand.hex(seq.colour)).frame(width: 7, height: 7)
                    }
                    Text(seq.title).sans(Brand.type(11), weight: .medium)
                        .foregroundStyle(Brand.ink2(dark))
                } else {
                    Text(state.view?.project.isCommercial == true ? "No section" : "No sequence")
                        .sans(Brand.type(11), weight: .medium).foregroundStyle(Brand.ink3(dark))
                }
            }
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .hovering(dark)
    }

    /// Which day it shoots — an assignment to a real day record, the same
    /// one the Schedule draws a board over.
    private func dayMenu(_ sc: ViewModel.Scene) -> some View {
        Menu {
            Button("Unscheduled") {
                _ = state.engine?.call("scene", sc.id, "none")
                state.replace(state.engine?.view())
            }
            Divider()
            ForEach(state.pickableDays()) { day in
                Button(day.label) {
                    _ = state.engine?.call("scene", sc.id, day.id)
                    state.replace(state.engine?.view())
                }
            }
        } label: {
            Text(sc.day.isEmpty ? "Unscheduled" : sc.day)
                .sans(Brand.type(11), weight: .medium)
                .foregroundStyle(sc.day.isEmpty ? Brand.ink3(dark) : Brand.ink2(dark))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .hovering(dark)
    }

    /// The scene's own menu — only what belongs to this scene, or to the
    /// columns the list is drawn with. Project-wide settings live under the
    /// gear on the right, where a Mac keeps them.
    private func sceneMenu(_ sc: ViewModel.Scene) -> some View {
        Menu {
            Button("Edit scene…") { state.editingScene = sc.id }
            // (Columns moved out of here on 2026-08-22 — it is one list for the
            // whole film and stood in every scene's menu. It is a button on the
            // bar above the table now, beside the zoom.)
            Divider()
            Button(sc.archived ? "Unarchive scene" : "Archive scene") {
                state.replace(state.engine?.archiveScene(sc.id, on: !sc.archived))
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Brand.ink3(dark))
                .frame(width: 24, height: 18)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .hovering(dark, radius: 5, horizontal: 2, vertical: 1)
    }

    /// **Only the words add a shot.** His note, 2026-09-29: *"the entire row
    /// of the 'add shot' should not add a shot when clicked, just the 'add
    /// shot' text. right now it's way too easy to create a shot."* The label
    /// used to be framed to the table's full width inside the button, so a
    /// click anywhere along the foot of a scene made a shot. The button is
    /// the words now, with a hover under them to say so; the rest of the row
    /// is air, framed outside the button.
    private func adder(_ scene: ViewModel.Scene) -> some View {
        Button {
            guard let engine = state.engine else { return }
            state.replace(engine.addShot(scene: scene.id))
        } label: {
            // `hovering` pads the words and shapes the press to them: the
            // soft fill under the pointer is exactly what a click will hit.
            PlusLabel(text: "Add shot", dark: dark, size: Brand.type(12))
                .hovering(dark, horizontal: 6, vertical: 4)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityIdentifier("add-shot")
        // The hover's 6 points of air go outside the shared left edge, so the
        // "+" still starts where the scene and shot numbers do.
        .padding(.leading, Columns.edge - 6)
        .frame(height: 34, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ------------------------------------------------------------- the cursor

    /// Puts the cursor on a cell.
    ///
    /// **Leaving an open cell writes what is in it.** That is what a sheet
    /// does, and the alternative — which is what this did — is that a person
    /// types a description, clicks the next cell, and the words are gone. Worse
    /// than gone: the buffer stayed live and followed the cursor to the cell
    /// they clicked, so the next Return wrote the old text into the new place.
    private func pick(_ row: ViewModel.Row, column: String) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        // ⇧ keeps the block it is stretching; every other click lets it go.
        if !flags.contains(.shift) { state.cellRange = nil }
        // **Clicking a cell takes the keyboard back.** Any other text field in
        // the window — the filter's search box, most often — holds the
        // window's field editor as first responder, and while it does, the
        // monitor hands it keys the table was meant to have. Giving it up here
        // means a click into the list is a click into the list.
        if let window = NSApp.keyWindow,
           window.firstResponder is NSTextView || window.firstResponder is NSTextField,
           !(window.firstResponder is CellText.Editor) {
            window.makeFirstResponder(nil)
        }
        // **Working in a shot claims its scene.** The chrome above the table
        // says which scene you are in, and with the whole script on one
        // surface that has to follow what you are actually touching, not
        // what the sidebar last said. Guarded so it does not scroll the
        // table out from under the click that caused it.
        if let sceneId = row.sceneId, sceneId != state.sceneId {
            state.scrollingToScene = true
            state.sceneId = sceneId
            DispatchQueue.main.async { state.scrollingToScene = false }
        }
        if state.editing, state.cursorShot != row.id || state.cursorColumn != column {
            commitOpenCell()
            state.editing = false
            state.editSeed = ""
        }
        // **⇧-click stretches a block from the cell the cursor is in to the
        // one clicked** — both ways, rows and columns, the way a sheet does it.
        // It used to tick the rows between and act on the cursor's column,
        // which could never be a rectangle. ⌘ still toggles this row, and a
        // plain click lets everything go.
        if flags.contains(.shift) {
            extend(toRow: row.id, column: column)
            return
        }
        if flags.contains(.command) {
            if state.marked.contains(row.id) { state.marked.remove(row.id) }
            else { state.marked.insert(row.id) }
            state.cursorShot = row.id
            state.wholeShots.removeAll()
            state.cursorColumn = column
            return
        }
        state.marked.removeAll()
        state.cursorShot = row.id
        state.wholeShots.removeAll()
        state.cursorColumn = column
    }

    /// The rows and columns a block covers, in today's orders.
    private func rect(of range: ShellState.CellRange)
        -> (rows: [ViewModel.Row], columns: [String]) {
        let shown = everyRow
        let names = columns
        guard let r1 = shown.firstIndex(where: { $0.id == range.anchorRow }),
              let r2 = shown.firstIndex(where: { $0.id == range.endRow }),
              let c1 = names.firstIndex(of: range.anchorColumn),
              let c2 = names.firstIndex(of: range.endColumn)
        else { return ([], []) }
        return (Array(shown[min(r1, r2)...max(r1, r2)]),
                Array(names[min(c1, c2)...max(c1, c2)]))
    }

    /// The rectangle the selected block covers, spelled out as the rows and
    /// columns between its corners in today's orders. Empty when no block.
    private var rangeCells: (rows: [ViewModel.Row], columns: [String]) {
        guard let range = state.cellRange else { return ([], []) }
        return rect(of: range)
    }

    /// Where one cell sits against a block: inside it or not, and which of its
    /// sides face out — the sides an outline is drawn on, so a block gets one
    /// outline round the whole rather than a grid of boxes.
    private func edges(_ block: (rows: [ViewModel.Row], columns: [String]),
                       _ rowId: String, _ name: String)
        -> (top: Bool, bottom: Bool, leading: Bool, trailing: Bool)? {
        guard let r = block.rows.firstIndex(where: { $0.id == rowId }),
              let c = block.columns.firstIndex(of: name) else { return nil }
        return (r == 0, r == block.rows.count - 1, c == 0, c == block.columns.count - 1)
    }

    // ------------------------------------------------- stretching a block

    /// Makes the block run from where it started — the cursor's cell when
    /// there is no block yet — to this cell. A block of one cell is no block.
    private func extend(toRow row: String, column: String) {
        let from = state.cellRange.map { ($0.anchorRow, $0.anchorColumn) }
            ?? (state.cursorShot ?? row, state.cursorColumn)
        state.marked.removeAll()
        state.wholeShots.removeAll()
        if from.0 == row && from.1 == column {
            state.cellRange = nil
            return
        }
        state.cellRange = ShellState.CellRange(
            anchorRow: from.0, anchorColumn: from.1, endRow: row, endColumn: column)
    }

    /// ⇧ with an arrow: the far corner of the block moves, the near one stays.
    /// `toEnd` goes all the way (⇧⌘ and the home and end keys).
    private func stretch(rows dr: Int, columns dc: Int, toEnd: Bool = false) {
        let shown = everyRow
        let names = columns
        guard !shown.isEmpty, !names.isEmpty else { return }
        let endRow = state.cellRange?.endRow ?? state.cursorShot
        let endColumn = state.cellRange?.endColumn ?? state.cursorColumn
        guard let r = shown.firstIndex(where: { $0.id == endRow }),
              let c = names.firstIndex(of: endColumn) else { return }
        func land(_ at: Int, _ step: Int, _ count: Int) -> Int {
            if step == 0 { return at }
            return toEnd ? (step < 0 ? 0 : count - 1)
                         : min(max(0, at + step), count - 1)
        }
        extend(toRow: shown[land(r, dr, shown.count)].id,
               column: names[land(c, dc, names.count)])
    }

    /// Where a block of cells on the clipboard sits in today's table, or nil
    /// when what was copied is no longer one rectangle.
    private func claim(_ rows: [ViewModel.Row], _ names: [String]) -> ShellState.CellRange? {
        guard let first = rows.first, let last = rows.last,
              let left = names.first, let right = names.last else { return nil }
        let shown = everyRow
        let at = rows.compactMap { row in shown.firstIndex { $0.id == row.id } }
        guard at.count == rows.count, at == Array(at[0]...at[at.count - 1])
        else { return nil }
        return ShellState.CellRange(anchorRow: first.id, anchorColumn: left,
                                    endRow: last.id, endColumn: right)
    }

    /// The rows an action reaches: the ticked set when there is one, the
    /// cursor's row otherwise — one code path for one shot and forty.
    private var actingOn: [ViewModel.Row] {
        // Whole script, not this scene: an action reaches the shot he is
        // standing on wherever it is. Scoped to the chrome's scene, this
        // returned nothing at all whenever the two disagreed — so ⌘V, ⌘⌫,
        // ⌘K and a colour change all silently did nothing, which is the
        // worst way for a thing to be broken.
        let shown = everyRow
        // Whole shots picked by their number column count as the selection too
        // — otherwise ⌘⌫ would delete one of five ringed rows.
        if !state.wholeShots.isEmpty {
            return shown.filter { state.wholeShots.contains($0.id) }
        }
        if state.cellRange != nil { return rangeCells.rows }
        if state.marked.isEmpty {
            return shown.filter { $0.id == state.cursorShot }
        }
        return shown.filter { state.marked.contains($0.id) }
    }

    /// Opens a cell on the value it already holds, with the caret after the
    /// last character — the way double-clicking a cell in a sheet lets you
    /// carry on from where the sentence stopped.
    private func openForEditing(_ row: ViewModel.Row, _ name: String) {
        // A yes-or-no cell has nothing to open. The gesture that would start
        // an edit — Return, double-click — flips it instead.
        if Columns.isCheck(name) {
            write(row, name, Columns.chosen(row, name).isEmpty ? "1" : "")
            return
        }
        // A cell of pictures opens onto pictures: the media window, the door
        // this cell's double-click was sealed for.
        if name == "image" {
            FrameWindows.shared.open(for: row.id, state: state)
            return
        }
        // **A shoot day opens the days** — never a text box, his standing
        // call, but never sealed either: "can't schedule unscheduled shots on
        // my own" (2026-10-06, on set). The ticked shots go with it.
        if name == "day" {
            let picked = actingOn.contains { $0.id == row.id } ? actingOn : [row]
            pickDay(for: picked)
            return
        }
        // The rest of the sealed cells (custom media and location until
        // their windows exist) still refuse quietly.
        guard Columns.hasEditor(name) else { return }
        state.copiedCells = nil
        state.copiedCut = false
        state.editSeed = Columns.isVocabulary(name) ? "" : Columns.value(row, name)
        // The highlight starts on the value the cell holds, so the list opens
        // pointing at where you are rather than at whatever happens to be
        // first — a sheet's dropdown does the same.
        if Columns.isVocabulary(name) {
            let options = Columns.options(name, state: state)
            let held = Columns.chosen(row, name).first
            state.pickAt = held.flatMap { value in
                options.firstIndex { $0.caseInsensitiveCompare(value) == .orderedSame }
            } ?? 0
        } else {
            state.pickAt = 0
        }
        state.pickTouched = false
        state.editOpenedByTyping = false
        state.editing = true
    }

    private static var dayMenuPress: TimeInterval = 0

    /// Each shot to the end of a day's shooting order, or off every day.
    private func scheduleShots(_ rows: [ViewModel.Row], on day: String?) {
        guard let engine = state.engine else { return }
        for row in rows {
            state.replace(engine.shootBefore(row.id, day: day, before: nil))
        }
    }

    /// The days, and Not Scheduled, under the pointer. A shot lands at the
    /// end of the day's shooting order; its scene, number and letter stay.
    private func pickDay(for rows: [ViewModel.Row]) {
        guard state.engine != nil, !rows.isEmpty else { return }
        // **One press, one menu.** Two key watchers hear the same Return (an
        // open text cell never minded); a menu would come up twice, the
        // second after he had already picked from the first.
        let press = NSApp.currentEvent?.timestamp ?? 0
        if press != 0, press == Self.dayMenuPress { return }
        Self.dayMenuPress = press
        let menu = NSMenu()
        menu.autoenablesItems = false
        let held = Set(rows.map { $0.dayId ?? "" })
        func move(to day: String?) { scheduleShots(rows, on: day) }
        for day in state.pickableDays(keeping: held) {
            let title = day.date.isEmpty ? day.label : "\(day.label) · \(day.date)"
            let item = ClosureItem(title) { move(to: day.id) }
            if held == [day.id] { item.state = .on }
            menu.addItem(item)
        }
        if menu.items.isEmpty {
            let none = NSMenuItem(title: "No shoot days yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            menu.addItem(.separator())
        }
        let off = ClosureItem("Not Scheduled") { move(to: nil) }
        if held == [""] { off.state = .on }
        menu.addItem(off)
        if Launch.checking {
            let titles = menu.items.filter { !$0.isSeparatorItem }.map(\.title)
            FileHandle.standardError.write(Data(("day menu: " + titles.joined(separator: " | ") + "\n").utf8))
            // `--pickday "Not Scheduled"` (or a day's title) picks from it,
            // then says where the shots landed.
            let args = CommandLine.arguments
            if let at = args.firstIndex(of: "--pickday"), at + 1 < args.count,
               let item = menu.items.first(where: { $0.title.hasPrefix(args[at + 1]) }) as? ClosureItem {
                menu.performActionForItem(at: menu.index(of: item))
                let ids = Set(rows.map(\.id))
                let now = (state.view?.allRows ?? []).filter { ids.contains($0.id) }
                    .map { "\($0.number)=\($0.day ?? "none")" }.joined(separator: " ")
                FileHandle.standardError.write(Data(("day now: " + now + "\n").utf8))
            }
            return
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// Puts the copied value where ⌘V will find it. A checking run keeps it
    /// in the harness's own pocket: the general pasteboard is HIS clipboard,
    /// on the machine he is working at, and replacing what he copied is theft
    /// in the same family as taking his focus.
    private func copyCell(_ value: String) {
        if Launch.checking {
            Launch.pasteOverride = value
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    /// What the clipboard holds as text — the harness's own pocket while a
    /// check runs, never his clipboard.
    private func clipboardText() -> String? {
        Launch.pasteOverride ?? NSPasteboard.general.string(forType: .string)
    }

    /// The cells an action reaches: the dragged rectangle; else the ticked
    /// shots (or the cursor's) in the cursor's column.
    private var selectedCells: (rows: [ViewModel.Row], columns: [String]) {
        if state.cellRange != nil { return rangeCells }
        return (actingOn, [state.cursorColumn])
    }

    /// The selection as the text a sheet would put on the clipboard, and the
    /// cells themselves outlined so it is plain what was taken.
    private func copyCells(_ rows: [ViewModel.Row], _ names: [String]) {
        let text = CellClip.encode(rows.map { row in
            names.map { Columns.value(row, $0) }
        })
        copyCell(text)
        state.copiedCells = claim(rows, names)
        state.copiedCut = false
        state.copiedText = text
    }

    /// **⌘X takes nothing out until it is pasted**, the way a sheet's cut
    /// works: the cells are outlined, the words go on the clipboard, and the
    /// cells are emptied by the paste that moves them. A cut that is never
    /// pasted costs nothing, and Esc puts the outline away.
    ///
    /// A selection that is not one rectangle (ticked shots far apart) has no
    /// outline to wait behind, so it empties at once, as it always did.
    private func cutCells(_ rows: [ViewModel.Row], _ names: [String]) {
        copyCells(rows, names)
        guard names.contains(where: { Columns.clearable($0) }) else {
            if names.count == 1 {
                state.say("\(Columns.label(names[0])) can’t be cut. Copied it.")
            }
            return
        }
        if state.copiedCells == nil {
            clearCells(rows, names)
        } else {
            state.copiedCut = true
        }
    }

    /// Empties what can be emptied, in one step to take back. A column that
    /// is not text — the day, the script's words, the pictures — keeps what
    /// it holds.
    private func clearCells(_ rows: [ViewModel.Row], _ names: [String]) {
        guard let engine = state.engine else { return }
        let groups = names.filter { Columns.clearable($0) }.map {
            (field: $0 == "camera" ? "unit" : $0, shots: rows.map(\.shot))
        }
        if !groups.isEmpty { state.replace(engine.clearCells(groups)) }
    }

    /// ⌘V onto the selection. Media on the clipboard is a frame for the
    /// shots. Text is read as cells, and three things can happen:
    ///
    /// - **One value** fills every cell selected.
    /// - **A block** lands whole from the selection's top left. It is *not*
    ///   clipped to what is selected — a sheet pastes all of it — except that
    ///   a selection which is an exact multiple of the block repeats it to
    ///   fill, so a copied lens pasted down twenty rows lands twenty times.
    ///   Rows past the end of the script become new shots at its foot.
    /// - **Ticked shots far apart** take the block's rows in order, in the
    ///   cursor's column, as they always did.
    ///
    /// Whatever a paste lands on is selected afterwards, so what happened is
    /// what is highlighted. One paste is one ⌘Z.
    private func pasteCells(_ rows: [ViewModel.Row], _ names: [String],
                            oneBlock: Bool = true) {
        if Ingest.fromPasteboard(onto: rows, state: state) { return }
        guard let text = clipboardText(), let engine = state.engine else { return }
        let grid = CellClip.decode(text)
        let single = grid.count == 1 && grid[0].count == 1

        if single, rows.count == 1, names.count == 1, !Columns.clearable(names[0]) {
            state.say("\(Columns.label(names[0])) can’t be pasted into.")
            return
        }
        engine.grouped("Paste") {
            // A cut empties its cells first, so a paste that overlaps them
            // moves the words rather than wiping what it has just written.
            if state.copiedCut, let from = state.copiedCells, text == state.copiedText {
                let source = rect(of: from)
                clearCells(source.rows, source.columns)
                state.copiedCells = nil
                state.copiedCut = false
            }
            if single {
                for name in names where Columns.clearable(name) {
                    paste(grid[0][0], onto: rows, column: name)
                }
            } else if oneBlock {
                landBlock(grid, atRow: rows.first?.id, column: names.first,
                          selected: (rows.count, names.count))
            } else {
                pasteDown(grid, into: rows, column: names.first)
            }
        }
    }

    /// The block, from `atRow`/`column` down and to the right.
    private func landBlock(_ grid: [[String]], atRow: String?, column: String?,
                           selected: (rows: Int, columns: Int)) {
        guard let engine = state.engine, let atRow, let column,
              let top = everyRow.firstIndex(where: { $0.id == atRow }),
              let left = columns.firstIndex(of: column) else { return }
        let deep = grid.count
        let wide = grid.map(\.count).max() ?? 1
        // Repeats only when the selection holds the block a whole number of
        // times; anything else pastes it once, in full.
        let down = selected.rows >= deep && selected.rows % deep == 0 ? selected.rows : deep
        let across = selected.columns >= wide && selected.columns % wide == 0
            ? selected.columns : wide

        // Past the foot of the script there is nowhere to put the rest, so a
        // sheet's answer is a row each: new shots at the end of the last
        // scene. Only when the list is in its own order — under a sort or a
        // filter the foot on screen is not the foot of the scene.
        let missing = top + down - everyRow.count
        if missing > 0, canGrow, let last = everyRow.last, let scene = last.sceneId {
            var after = last.placement
            for _ in 0..<missing {
                state.replace(engine.addShot(scene: scene, after: after))
                if let placed = everyRow.last { after = placed.placement }
            }
        }
        let all = everyRow
        let landed = Array(all[top..<min(all.count, top + down)])
        let names = Array(columns[left..<min(columns.count, left + across)])
        guard !landed.isEmpty, !names.isEmpty else { return }

        for (c, name) in names.enumerated() where Columns.clearable(name) {
            // Rows sharing a value go in together, so a block with repeats
            // costs one write rather than one per cell. In row order, so the
            // same paste always makes the same history. Cells a short line of
            // the block does not reach are written empty, as a sheet does.
            var order: [String] = []
            var byValue: [String: [ViewModel.Row]] = [:]
            for (r, row) in landed.enumerated() {
                let line = grid[r % deep]
                let value = (c % wide) < line.count ? line[c % wide] : ""
                if byValue[value] == nil { order.append(value) }
                byValue[value, default: []].append(row)
            }
            for value in order { paste(value, onto: byValue[value] ?? [], column: name) }
        }
        // What it landed on is what is selected, with the cursor at its head.
        state.cursorShot = landed[0].id
        state.cursorColumn = names[0]
        state.marked.removeAll()
        state.wholeShots.removeAll()
        if landed.count == 1 && names.count == 1 {
            state.cellRange = nil
        } else {
            state.cellRange = ShellState.CellRange(
                anchorRow: landed[0].id, anchorColumn: names[0],
                endRow: landed[landed.count - 1].id,
                endColumn: names[names.count - 1])
        }
    }

    /// Ticked shots that are not neighbours: the block's rows in order down
    /// the cursor's column, one value each.
    private func pasteDown(_ grid: [[String]], into rows: [ViewModel.Row], column: String?) {
        guard let column else { return }
        for (r, row) in rows.enumerated() where r < grid.count {
            if Columns.clearable(column) {
                paste(grid[r].first ?? "", onto: [row], column: column)
            }
        }
    }

    /// Whether a paste may add shots at the foot of the script: only when the
    /// table is showing every shot in the script's own order.
    private var canGrow: Bool {
        guard let view = state.view else { return false }
        return !state.shootingOrder && !view.filter.narrowed
            && view.filter.sortColumn.isEmpty
    }

    /// One value onto every row the action reaches, in the cursor's column —
    /// one engine transaction, so a paste over forty rows is one ⌘Z.
    ///
    /// Paste **replaces**, deliberately not `write()`: write's multi-value
    /// grammar toggles, which is right for picking from a list and wrong
    /// here — pasting "VFX" onto a row that already has VFX must not take
    /// it off. The engine's `setmany` sets each kind by its shape.
    private func paste(_ value: String, onto rows: [ViewModel.Row], column name: String) {
        guard let engine = state.engine, !rows.isEmpty else { return }
        // Camera is a reference: resolve the label to a unit once — creating
        // it if the project has never heard the name, same as typing it —
        // and point every row at that one unit.
        if name == "camera" {
            let label = value.trimmingCharacters(in: .whitespaces)
            if label.isEmpty {
                state.replace(engine.setMany(shots: rows.map(\.shot), field: "unit", value: ""))
                return
            }
            // A new name births its unit and points the shots at it: one
            // thing to take back, not two.
            engine.grouped("Paste") {
                if state.view?.units.first(where: {
                    $0.label.caseInsensitiveCompare(label) == .orderedSame
                }) == nil {
                    let colour = Columns.palette[
                        (state.view?.units.count ?? 0) % Columns.palette.count]
                    state.replace(engine.addUnit(label: label, colour: colour))
                }
                guard let unit = state.view?.units.first(where: {
                    $0.label.caseInsensitiveCompare(label) == .orderedSame
                }) else { return }
                state.replace(engine.setMany(shots: rows.map(\.shot), field: "unit", value: unit.id))
            }
            return
        }
        state.replace(engine.setMany(shots: rows.map(\.shot), field: name, value: value))
    }

    /// Puts one value on one cell, through the engine.
    ///
    /// Every column's quirk lives here rather than being spread across the
    /// callers, because the two bugs this code has had were both a caller
    /// writing to the wrong record and nothing complaining.
    private func write(_ row: ViewModel.Row, _ name: String, _ typed: String) {
        Columns.write(row, name, typed: typed, state: state)
    }

    // ------------------------------------------------------------- the keys

    /// Keys are read at the window rather than fought over by each cell.
    ///
    /// The old app learned this the hard way: a window hands its first keyboard
    /// focus to the first text field it can find, so typing went into the search
    /// box. One monitor with explicit rules instead — an open editor keeps
    /// everything while it is open, a command keeps going to the menus, and the
    /// table takes the rest.
    /// The header's mouse, read at the window like the table's keys.
    ///
    /// A press in the header band is one of three things, told apart by
    /// where it lands against the frames the header cells report: within
    /// nine points of a column's right edge it is a **resize** (anchored to
    /// the width at press time — the sidebar divider's lesson), anywhere
    /// else it starts a **carry** once it has moved four points, and a press
    /// that never moves is a **sort** on release. Double-click on an edge
    /// puts the standard width back. Everything below the header passes
    /// through untouched. It lives here rather than in SwiftUI gestures
    /// because a drag gesture inside the horizontal scroll view fires for
    /// taps and never for drags, whatever priority it claims — and a gesture
    /// that cannot be reached cannot be checked.
    private func watchHeaderMouse() {
        guard mouse == nil else { return }
        var pressed: (name: String, edge: Bool, startWidth: CGFloat, at: CGPoint)?
        var moved = false
        // A press on a row's gutter that might become a carry. The down event
        // is never swallowed — a plain click is the pick, and the context
        // menu needs it — so the carry only takes the events once it is real.
        var rowPress: (id: String, at: CGPoint)?
        // Set when a press lands on a row that is already selected, so the
        // selection can collapse to it if the press turns out to be a plain
        // click rather than the start of a carry.
        var collapseOnUp: String?
        // A press on a cell that might become a drag-selected range. Same
        // rule: the down passes through, the drag takes over once it is real.
        var cellPress: (row: String, column: String, at: CGPoint)?
        var ranging = false

        // The cell under a point: a row's y-span crossed with a column's
        // x-span — the two frame sets the monitor already keeps.
        func cellAt(_ at: CGPoint) -> (row: String, column: String)? {
            // Nothing outside the table is a cell of it.
            let table = Columns.lastFrame
            guard table == .zero || (at.x >= table.minX && at.x <= table.maxX)
            else { return nil }
            guard let row = state.rowFrames.first(where: {
                at.y >= $0.value.minY && at.y <= $0.value.maxY
            }) else { return nil }
            guard let column = state.headerFrames.first(where: {
                at.x >= $0.value.minX && at.x <= $0.value.maxX
            }) else { return nil }
            return (row.key, column.key)
        }

        func place(_ event: NSEvent) -> CGPoint {
            guard let window = event.window else { return .zero }
            let raw = event.locationInWindow
            return CGPoint(x: raw.x, y: window.frame.height - raw.y)
        }

        mouse = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { event in
            // **Only the table's own window.**
            //
            // This monitor reads a point against the table's frames, and it
            // was reading every press in *every* window the app has open. A
            // viewer's coordinates mean nothing here, but they land somewhere:
            // a drag that happened to fall across a row or a header band was
            // swallowed whole, and the press never reached what it was aimed
            // at. That is his "difficulty clicking and dragging the trim
            // handles" — the handles were fine, the drag was being eaten by a
            // table in another window. No identifier at all is the main window
            // before SwiftUI stamps it.
            if let name = event.window?.identifier?.rawValue, name != "main" {
                return event
            }
            // **A click that is not into text takes the keyboard back.**
            //
            // Any text field in this window — the sidebar's search box, most
            // often — keeps the window's field editor as first responder long
            // after anybody has finished typing in it, and while it does the
            // key monitor hands it keys the table was meant to have. `pick`
            // already gives it up when a *cell* is clicked; this is the same
            // courtesy for every other click, which is what "after some period
            // of use the arrow keys stopped navigating between cells" was:
            // search for a scene, click it in the sidebar, and the field never
            // let go. A press inside the field's own rectangle is somebody
            // going back to it, and is left alone.
            if event.type == .leftMouseDown, let window = event.window,
               let responder = window.firstResponder as? NSView,
               responder is NSTextView || responder is NSTextField,
               !(responder is CellText.Editor) {
                let box = responder.convert(responder.bounds, to: nil)
                if !box.insetBy(dx: -5, dy: -5).contains(event.locationInWindow) {
                    window.makeFirstResponder(nil)
                }
            }
            guard state.sideTab == .scenes, state.tab == .shots else { return event }
            // **A sheet in front owns every click in the window.**
            //
            // His report: *"some of these buttons pass through to the element
            // behind the pop up in the table."* Exactly that — this monitor
            // sees every press in the app, and a press inside Project Settings
            // arrives carrying the *sheet's* coordinates, which land wherever
            // they happen to fall in the table's own frames. Pressing the ⊖
            // beside a term also sorted a column, or picked a shot, behind it.
            //
            // **The keys monitor learned this and the mouse one was never
            // told.** Its comment thirty lines down says the same thing about
            // the same sheets — it stopped writing typed names into the table's
            // edit buffer — and the test there is the test here.
            if NSApp.keyWindow?.isSheet == true || event.window?.isSheet == true {
                return event
            }
            // **A panel drawn over the table gets its own clicks** — Ref 271.
            // This monitor sees every press in the window, so without this a
            // button in the script panel that sits above a column header does
            // its own job *and* sorts the column behind it. Handing the event
            // back lets SwiftUI deliver it to whatever is actually on top.
            if state.panelFrames.values.contains(where: { $0.contains(place(event)) }) {
                return event
            }

            // **Edit Reference's play button gets its own click** (his report,
            // 2026-10-17: "I can't select the play button, it just selects the
            // table behind it"). The button sits in the number column's gutter,
            // and the gutter press below picks the whole shot and swallows the
            // event, so the button never saw it. Over the button the press goes
            // on to SwiftUI untouched.
            if event.type == .leftMouseDown {
                let at = place(event)
                if let row = state.rowFrames.first(where: { $0.value.contains(at) }),
                   let pieces = state.editPieces[row.key],
                   pieces.contains(where: { piece in
                       piece.first && CGRect(
                           x: row.value.minX + Columns.edge - 21 - CGFloat(piece.lane) * 8 + 8 - 11,
                           y: row.value.minY + 17 - 11, width: 22, height: 22).contains(at)
                   }) {
                    return event
                }
            }

            switch event.type {
            case .leftMouseDown:
                let at = place(event)
                guard let hit = state.headerFrames.first(where: { $0.value.contains(at) })
                else {
                    // Not the header: perhaps a row's gutter. Arm a carry —
                    // never while sorted (the order on screen is not the
                    // scene's own, so there is nowhere true to drop), never
                    // with a cell open, and never under ⇧/⌘, which are
                    // selection grammar.
                    let sorted = !(state.view?.filter.sortColumn ?? "").isEmpty
                    // **⇧ and ⌘ are welcome here**, unlike over the cells:
                    // on the number column they are how a set of whole shots
                    // gets built, so excluding them would exclude the feature.
                    if !sorted, !state.editing,
                       Columns.lastFrame == .zero
                        || (at.x >= Columns.lastFrame.minX
                            && at.x <= Columns.lastFrame.maxX),
                       let row = state.rowFrames.first(where: { $0.value.contains(at) }),
                       // Relative to the row's own left edge. `Columns.gutter`
                       // is a *width*, and comparing a window coordinate to it
                       // is how I switched dragging off entirely for one build.
                       at.x < row.value.minX + Columns.gutter + Brand.rowInset + 4 {
                        // **The number column picks the whole shot**, his ask:
                        // "it's not clear where I should select to select the
                        // whole shot… only when I've selected a cell in the
                        // first column." Pressing it says so out loud — the
                        // shot becomes the selection, and the row draws a ring
                        // round itself — and a carry is armed from the same
                        // press, so picking it up is still one motion.
                        state.cursorShot = row.key
                        // **Several whole shots, the way a list does it** —
                        // his ask. ⇧ takes everything between the anchor and
                        // this row, ⌘ adds or removes one, a plain press starts
                        // again from one. The same grammar the cells already
                        // use, so there is nothing new to learn.
                        let mods = event.modifierFlags
                        if mods.contains(.shift), let anchor = state.wholeAnchor,
                           let from = everyRow.firstIndex(where: { $0.id == anchor }),
                           let to = everyRow.firstIndex(where: { $0.id == row.key }) {
                            state.wholeShots = Set(
                                everyRow[min(from, to)...max(from, to)].map(\.id))
                        } else if mods.contains(.command) {
                            if state.wholeShots.contains(row.key) {
                                state.wholeShots.remove(row.key)
                            } else {
                                state.wholeShots.insert(row.key)
                            }
                            state.wholeAnchor = row.key
                        } else if state.wholeShots.contains(row.key) {
                            // **A press on something already selected keeps the
                            // selection.** Otherwise picking a group up by one
                            // of its own members throws the group away on the
                            // way down and only that shot travels — which is
                            // exactly what happened the first time I built
                            // this. Collapsing waits for the mouse to come up
                            // without having gone anywhere, the way every list
                            // on the Mac behaves.
                            collapseOnUp = row.key
                        } else {
                            state.wholeShots = [row.key]
                            state.wholeAnchor = row.key
                        }
                        // **Not `marked`.** Marking also fills the row with the
                        // accent, so picking a shot up drew a solid block *and*
                        // the ring — twice as loud as the "blue bar around the
                        // shot" he asked for. The ring alone says it.
                        state.marked.removeAll()
                        rowPress = (row.key, at)
                        return nil
                    }
                    // A cell, then — the start of a possible range. Not while
                    // editing (a drag in an open cell selects its text), not
                    // under ⇧/⌘ (selection grammar), and the header case
                    // above has already taken its band.
                    if !state.editing,
                       !event.modifierFlags.contains(.shift),
                       !event.modifierFlags.contains(.command),
                       let cell = cellAt(at) {
                        cellPress = (cell.row, cell.column, at)
                    }
                    return event
                }
                let edge = at.x > hit.value.maxX - 9
                if edge && event.clickCount == 2 {
                    Columns.setWidth(hit.key, to: nil)
                    state.columnBump &+= 1
                    pressed = nil
                    return nil
                }
                pressed = (hit.key, edge, Columns.stored(hit.key), at)
                moved = false
                return nil

            case .leftMouseDragged:
                if let press = cellPress {
                    let at = place(event)
                    // **Two points, not four.** A synthetic drag jumps in
                    // eighths and clears any threshold on its first move, so
                    // the harness could never feel this; a hand starts a drag
                    // with a few pixels of travel, and every one of those spent
                    // below the threshold is a frame where the selection has
                    // not started and the drag feels dead. He said it plainly:
                    // "clicking and dragging didn't work."
                    if ranging || abs(at.x - press.at.x) > 2 || abs(at.y - press.at.y) > 2 {
                        ranging = true
                        // The far corner follows the pointer; past the table's
                        // edge it holds the last cell it crossed.
                        let end = cellAt(at)
                        state.cellRange = ShellState.CellRange(
                            anchorRow: press.row,
                            anchorColumn: press.column,
                            endRow: end?.row ?? state.cellRange?.endRow ?? press.row,
                            endColumn: end?.column ?? state.cellRange?.endColumn ?? press.column)
                        state.marked.removeAll()
                        return nil
                    }
                    return event
                }
                if let press = rowPress {
                    let at = place(event)
                    if state.carryingRow != nil || abs(at.y - press.at.y) > 2 {
                        state.carryingRow = press.id
                        // It lands in front of the first row whose midline is
                        // still below the pointer — the header's rule, turned
                        // on its side. Past every midline is the foot.
                        // **The scene under the pointer decides**, and only
                        // then which row within it.
                        //
                        // Taking the first row below the pointer *anywhere*
                        // was the obvious reading of "shots can move between
                        // scenes" and it is wrong: dragging a shot just past
                        // the last one in its scene then means the next row
                        // down, which belongs to the *next scene*, so the shot
                        // is flung out of the scene he was tidying. The
                        // battery caught it — three storyboard checks came
                        // back with no cards at all, because a scene had been
                        // emptied by drags that used to land at its foot.
                        //
                        // Asking which scene the pointer is *over* keeps the
                        // gap below a scene's last shot belonging to that
                        // scene, which is what a hand means by it. Crossing
                        // into another scene now takes actually being over it.
                        // `sceneFrames` holds each scene's *heading band*,
                        // not its rows, so "is the pointer inside it" is only
                        // ever true over a header. A scene's territory is its
                        // band down to the next scene's band — the gap under
                        // its last shot included, which is exactly the gap in
                        // question.
                        let bands = state.sceneFrames.sorted { $0.value.minY < $1.value.minY }
                        var overScene = bucket(press.id)
                        for (i, band) in bands.enumerated() {
                            let floor = i + 1 < bands.count
                                ? bands[i + 1].value.minY
                                : CGFloat.greatestFiniteMagnitude
                            if at.y >= band.value.minY, at.y < floor {
                                overScene = band.key
                                break
                            }
                        }
                        let inScene = Set(everyRow.filter { bucket($0.id) == overScene }
                                                  .map(\.id))
                        state.landingRow = state.rowFrames
                            .filter { inScene.contains($0.key)
                                      && $0.key != press.id && at.y < $0.value.midY }
                            .min { $0.value.minY < $1.value.minY }?
                            .key
                        state.landingScene = overScene
                        return nil
                    }
                    return event
                }
                guard let press = pressed else { return event }
                let at = place(event)
                let dx = at.x - press.at.x
                if press.edge {
                    resizing = press.name
                    Columns.setWidth(press.name, to: press.startWidth + dx)
                    state.columnBump &+= 1
                    // A fast pull outruns the hover band, whose exit would put
                    // the arrow back mid-drag. While the edge is held, the
                    // cursor is ↔ whatever the hover machinery thinks. Real
                    // hands only — a checking run posts events without a
                    // pointer, and must change nothing a person can see.
                    if !Launch.checking { NSCursor.resizeLeftRight.set() }
                } else if moved || abs(dx) > 4 {
                    moved = true
                    state.carrying = press.name
                    // It lands in front of the first column whose midline is
                    // still to the right of the pointer; past every midline
                    // is the far end.
                    state.landing = state.headerFrames
                        .filter { $0.key != press.name && at.x < $0.value.midX }
                        .min { $0.value.minX < $1.value.minX }?
                        .key
                }
                return nil

            case .leftMouseUp:
                if cellPress != nil {
                    defer { cellPress = nil; ranging = false }
                    // A drag keeps its range and eats the up so the click
                    // underneath cannot re-pick; a press that never moved is
                    // a plain click and passes through untouched.
                    if ranging { return nil }
                    return event
                }
                if let press = rowPress {
                    defer {
                        if let only = collapseOnUp, state.carryingRow == nil {
                            state.wholeShots = [only]
                            state.wholeAnchor = only
                        }
                        collapseOnUp = nil
                        rowPress = nil
                        state.carryingRow = nil
                        state.landingRow = nil
                        state.landingScene = nil
                    }
                    guard state.carryingRow != nil else { return event }
                    // **In shooting order a drop is a place in the day**, not
                    // in the scene: the shot is shot there, and keeps its
                    // number. Placed in front of the row it was dropped
                    // above, so a filter hiding some of the day cannot send
                    // it somewhere else.
                    if state.shootingOrder, let engine = state.engine {
                        let moving = state.wholeShots.contains(press.id)
                            ? state.wholeShots : [press.id]
                        let destination = state.landingScene ?? bucket(press.id)
                        let all = everyRow
                        let from = state.landingRow.flatMap { id in all.firstIndex { $0.id == id } } ?? all.count
                        let anchor = all[from...].first {
                            bucket($0.id) == destination && !moving.contains($0.id)
                        }?.id
                        let travelling = all.filter { moving.contains($0.id) }.map(\.id)
                        let day = destination.map { String($0.dropFirst(4)) }.flatMap { $0.isEmpty ? nil : $0 }
                        for shot in travelling {
                            state.replace(engine.shootBefore(shot, day: day, before: anchor))
                        }
                        return nil
                    }
                    if let engine = state.engine {
                        // **The carried shot's own scene, not the chrome's.**
                        // This read `rows`, which is whichever scene the
                        // sidebar last named, so the destination was worked out
                        // against the wrong list of shots the moment those two
                        // disagreed — and they disagree constantly, because
                        // scrolling moves one and clicking moves the other. The
                        // shot then landed at an index that meant nothing in
                        // its own scene: sometimes right, sometimes nowhere,
                        // never predictable. His words were "some shots don't
                        // like being dragged around to certain places."
                        //
                        // Same mistake as the nine in `f23f602`; it survived
                        // that sweep because it reads `rows.map` rather than
                        // the `let shown = rows` shape I grepped for. Worth
                        // remembering that a sweep is only as wide as its
                        // pattern.
                        let home = everyRow.first { $0.id == press.id }?.sceneId
                        // Where it is going: the landing row's scene, or — when
                        // it was dragged past everything — the foot of the last
                        // scene on screen.
                        // The scene the pointer was over when he let go —
                        // not the landing row's, because letting go in the gap
                        // below a scene's last shot has no landing row at all
                        // and still means that scene.
                        let destination = state.landingScene ?? home
                        // Worked out *before* the move, while these rows are
                        // still the rows: the carried shot is excluded either
                        // way, so its arrival cannot shift the count.
                        let moving = state.wholeShots.contains(press.id)
                            ? state.wholeShots : [press.id]
                        let order = everyRow
                            .filter { $0.sceneId == destination && !moving.contains($0.id) }
                            .map(\.id)
                        let index = state.landingRow
                            .flatMap { order.firstIndex(of: $0) } ?? order.count
                        // **Everything that is ringed travels**, in script
                        // order, landing as a run — his ask: "I should also be
                        // able to select multiple whole shots… and drag them
                        // around as well." Dragging one of five and moving only
                        // that one would be the app quietly disagreeing about
                        // what is selected.
                        let travelling = state.wholeShots.contains(press.id)
                            ? everyRow.filter { state.wholeShots.contains($0.id) }.map(\.id)
                            : [press.id]
                        // **Each move shifts the ones still to come**, so a
                        // running `index + k` is wrong the moment there is more
                        // than one traveller — it scattered three shots into
                        // three unrelated places the first time. The list is
                        // simulated here instead, so every index handed to the
                        // engine is correct at the moment it is used.
                        //
                        // The run lands *before* the non-mover it was dropped
                        // above, or at the foot when it was dropped past
                        // everything. Inserting each traveller at that same
                        // anchor keeps them in script order, because every one
                        // lands after those already placed.
                        let anchorId: String? = index < order.count ? order[index] : nil
                        var current = everyRow
                            .filter { $0.sceneId == destination }.map(\.id)
                        for shot in travelling {
                            // Two steps, because they are two facts: which
                            // scene the shot belongs to, and where it sits
                            // within it. **The scene's numbering is the
                            // script's** — a shot takes a new letter in its new
                            // scene and no scene is renumbered for it.
                            let from = everyRow.first { $0.id == shot }?.sceneId
                            if let destination, destination != from {
                                state.replace(engine.movePlacement(shot, toScene: destination))
                                if !current.contains(shot) { current.append(shot) }
                            }
                            current.removeAll { $0 == shot }
                            let insertAt = anchorId
                                .flatMap { current.firstIndex(of: $0) } ?? current.count
                            current.insert(shot, at: insertAt)
                            state.replace(engine.reorder(placement: shot, to: insertAt))
                        }
                    }
                    return nil
                }
                defer {
                    pressed = nil
                    resizing = nil
                    state.carrying = nil
                    state.landing = nil
                }
                guard let press = pressed else { return event }
                if press.edge { return nil }
                if moved {
                    guard let engine = state.engine else { return nil }
                    var order = columns
                    guard let from = order.firstIndex(of: press.name) else { return nil }
                    order.remove(at: from)
                    if let landing = state.landing, let at = order.firstIndex(of: landing) {
                        order.insert(press.name, at: at)
                    } else {
                        order.append(press.name)
                    }
                    if order != columns { state.replace(engine.columnOrder(order)) }
                    return nil
                }
                // A press that never moved is a click: sort, toggling if it
                // is already the sorted column.
                if let engine = state.engine {
                    let already = state.view?.filter.sortColumn == press.name
                    let down = state.view?.filter.sortDescending ?? false
                    state.replace(engine.sortBy(press.name, descending: already ? !down : false))
                }
                return nil

            default:
                return event
            }
        }
    }

    private func watchKeys() {
        guard keys == nil else { return }
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard state.sideTab == .scenes else { return event }
            // An edit reference playing over the table has the keys.
            if state.editRefPlaying != nil { return event }

            // **Whoever actually has the keyboard keeps it.**
            //
            // This monitor answers for keys so the table can be driven when
            // no text view has first responder — which is every quiet check,
            // and the table's own fallback path. But it had no idea anything
            // else could be taking keys, and two things now are: an attached
            // sheet (Project Settings, Edit Columns, the project browser),
            // and the scene header's own fields, which are edited in place.
            // Underneath a sheet it wrote the typed name into the table's
            // edit buffer and let ⌘A select every row behind it; under the
            // header it ate the location being typed there.
            //
            // The table's own editor is `CellText.Editor` and nothing else,
            // so the test is simple: if some *other* text view holds the
            // keyboard, the keys are its own.
            if let key = NSApp.keyWindow {
                if key.isSheet { return event }
                // **Only this window's keys.** The viewer, the scan, the
                // script and the schedule are windows of our own with nothing
                // of the table in them; a shot's frames window is the one
                // exception, and it is answered a few lines below. A window
                // with no identifier is the main one before SwiftUI stamps it.
                if let name = key.identifier?.rawValue,
                   name != "main", name != "frames" { return event }
                let responder = key.firstResponder
                let mine = responder is CellText.Editor
                let typing = responder is NSTextView || responder is NSTextField
                // **Return belongs to the table even so.**
                //
                // His report: "clicking enter on a cell now does not bring up
                // the dropdown". The guard above is right about letters — a
                // search box being typed into must keep them — but it was
                // handing over *Return* as well, and the filter bar's search
                // field holds the window's field editor as first responder
                // whether or not anybody is typing in it. So Return went to a
                // search box that does nothing with it, and the cell it was
                // aimed at never opened. The table keeps Return whenever it
                // has a cursor and nothing of its own is open.
                let openingACell = event.keyCode == 36
                    && !state.editing
                    && state.cursorShot != nil
                    && state.tab == .shots
                // **An open list owns the keyboard outright.**
                //
                // A choice cell has no text view in it at all — it draws
                // `state.editSeed` with a block for a caret, and this monitor
                // is the only thing that types into it. So while one is open
                // there is nothing else in this window the keys could be for,
                // whoever happens to be holding first responder. Without this
                // they went to whatever field editor was parked — the
                // sidebar's search box, most often. All three of his reports
                // are that one fact: "backspace isnt clearing dropdown fields"
                // (it was deleting in the search box), the arrows walking a
                // caret that is not on screen, and Return escaping the table
                // altogether to press whatever button SwiftUI had focused —
                // "when I hit enter to confirm the new entry a picture of the
                // location popped up in the media viewer".
                let listOpen = state.editing
                    && state.tab == .shots
                    && Columns.isVocabulary(state.cursorColumn)
                if typing && !mine && !openingACell && !listOpen { return event }
            }

            // The frames window first, whichever tab is under it: ← and →
            // walk the filmstrip, Escape puts the window away.
            if state.mediaShown != nil, FrameWindows.shared.isKey() {
                let stills = state.view?.allRows
                    .first { $0.id == state.mediaShown }?.stills ?? []
                // **The window with the keyboard walks its own strip.** With
                // more than one frames window open, `state.frameSelected` is a
                // mirror of whichever is in front; the arrows have to move
                // *that* window's choice, not a shared one.
                let eye = FrameWindows.shared.keyEye()
                // **In Print Frame mode the keys are the editor's.** ⌫ there
                // takes a frame off the board (`PrintFrameKeys`), never a
                // picture off the shot; Escape goes back to the pictures.
                if eye?.printing == true {
                    if event.keyCode == 53 { eye?.printing = false; return nil }
                    return event
                }
                let at = stills.firstIndex {
                    $0.ref == (eye?.selected ?? stills.first { $0.key }?.ref)
                } ?? 0
                switch event.keyCode {
                case 123 where !stills.isEmpty:                         // ←
                    eye?.selected = stills[max(0, at - 1)].ref
                    return nil
                case 124 where !stills.isEmpty:                         // →
                    eye?.selected = stills[min(stills.count - 1, at + 1)].ref
                    return nil
                case 51, 117:                                           // ⌫
                    // **Backspace takes the frame off the shot** — his ask,
                    // and the key a hand reaches for. The picture itself is
                    // kept; nothing here deletes his media on a keystroke.
                    if let engine = state.engine, !stills.isEmpty {
                        let still = stills[min(at, stills.count - 1)]
                        let next = stills.indices.contains(at + 1) ? stills[at + 1]
                                 : (at > 0 ? stills[at - 1] : nil)
                        eye?.selected = next?.ref
                        state.replace(engine.detach(frame: still.ref))
                    }
                    return nil
                case 53:                                                // esc
                    FrameWindows.shared.close()
                    return nil
                default:
                    return event
                }
            }

            // The storyboard's own keyboard: arrows walk the grid of cards,
            // Return opens the frames window on the one the cursor is on.
            if state.tab == .storyboard {
                let shown = state.view?.allRows
                    .filter { $0.sceneId == state.scene?.id } ?? []
                // The shot keys first — they are the same on all three
                // surfaces. Plain arrows carry no ⌘, so they fall straight
                // through to the grid below.
                if Shortcuts.handle(event, state: state, typing: false, surface: .init(
                    scene: state.scene?.id,
                    resize: { step in
                        let steps: [CGFloat] = [150, 200, 264, 340, 420]
                        let at = steps.firstIndex { $0 >= state.cardWidth - 1 } ?? 1
                        state.cardWidth = step == 0
                            ? 200 : steps[min(steps.count - 1, max(0, at + step))]
                    }
                )) == nil { return nil }
                guard !shown.isEmpty else { return event }
                let at = shown.firstIndex { $0.id == state.cursorShot } ?? 0
                let per = max(1, state.storyboardColumns)
                func land(_ index: Int) {
                    state.cursorShot = shown[max(0, min(shown.count - 1, index))].id
                    state.wholeShots.removeAll()
                    state.marked.removeAll()
                }
                switch event.keyCode {
                case 123: land(at - 1); return nil                      // ←
                case 124: land(at + 1); return nil                      // →
                case 126: land(BoardPlan.step(-1, from: shown[at].id, rows: state.storyboardRows, frames: state.cardFrames, shown: shown.map(\.id), fallback: per)); return nil // ↑
                case 125: land(BoardPlan.step(1, from: shown[at].id, rows: state.storyboardRows, frames: state.cardFrames, shown: shown.map(\.id), fallback: per)); return nil  // ↓
                case 36:                                                // return
                    if let id = state.cursorShot {
                        FrameWindows.shared.open(for: id, state: state)
                    }
                    return nil
                case 53:                                                // esc
                    state.marked.removeAll()
                    return nil
                default:
                    // ⌘Z, ⌘V and the rest were answered above, by the shared
                    // keyboard. A ⌘V that reached here had nothing on the
                    // clipboard worth landing, and says so.
                    if event.modifierFlags.contains(.command),
                       event.charactersIgnoringModifiers?.lowercased() == "v" {
                        state.say("Nothing to paste")
                        return nil
                    }
                    return event
                }
            }

            guard state.tab == .shots else { return event }
            state.keysSeen += 1
            // The shot keys — the same set on all three surfaces, in one file.
            // Everything below this line is the *table's* keyboard: cells,
            // ranges, the cursor's walk.
            if Shortcuts.handle(event, state: state, typing: state.editing,
                                surface: .init(
                                    scene: scene.id,
                                    resize: { step in
                                        let steps = Brand.comfortable
                                        let at = steps.firstIndex {
                                            abs($0 - Brand.density) < 0.01
                                        } ?? 1
                                        Brand.density = step == 0
                                            ? 1.0
                                            : steps[min(steps.count - 1, max(0, at + step))]
                                        // His preference, not a checking
                                        // run's: the lastProject lesson,
                                        // applied before it bites twice.
                                        Remembering().set(Double(Brand.density),
                                                          forKey: "tableDensity")
                                        state.columnBump &+= 1
                                    }
                                )) == nil { return nil }
            if event.modifierFlags.contains(.command) {
                // ⌘Z, ⌘⌫, ⌘D, ⌘K, ⌘A, ⌘↑/⌘↓ and ⌘+/⌘−/⌘0 were answered
                // above by the shared keyboard — see `Shortcuts`. With a cell
                // open they never fire, because inside an editor ⌘Z un-types
                // and ⌘A selects the sentence. What is left here is the
                // table's own: cells, ranges, and the image column.
                //
                // On a selected cell — not an open one — ⌘C, ⌘V and ⌘X act on
                // the cell's value, which is what they do in a sheet. With a
                // cell open, the text view (or the menus) own them.
                // ⌘← and ⌘→ run to the ends of the row, ⌘Home and ⌘End to the
                // corners of the script — ⇧ stretches the block instead of
                // moving. (⌘↑ and ⌘↓ stay what they were: they carry the shot.)
                if !state.editing, let walk = edgeWalk(event) {
                    walk()
                    return nil
                }
                // **Shots picked whole** (the number column's ring) copy and
                // paste as shots — the same two things the right-click menu
                // offers — rather than as the one cell the cursor happens to
                // be standing in. Ahead of the image cell's own rule below:
                // the ring is the selection, whatever column the cursor sits in.
                if !state.editing, !state.wholeShots.isEmpty,
                   let key = event.charactersIgnoringModifiers?.lowercased(),
                   ["c", "x", "v"].contains(key) {
                    let held = everyRow.filter { state.wholeShots.contains($0.id) }
                    switch key {
                    case "c":
                        copyShots(held)
                        state.say(held.count == 1 ? "Copied 1 shot." : "Copied \(held.count) shots.")
                        return nil
                    case "x":
                        // Cut is his own act, the same as ⌘X on cells: it
                        // copies, then takes the originals out, and one ⌘Z
                        // puts them all back.
                        copyShots(held)
                        deleteShots(held)
                        state.say(held.count == 1 ? "Cut 1 shot." : "Cut \(held.count) shots.")
                        return nil
                    default:
                        // Only while the clipboard is still the shots he
                        // copied; anything else on it is for the cells.
                        if !state.copiedShots.isEmpty, clipboardText() == state.copiedShotsText,
                           !Ingest.fromPasteboard(onto: held, state: state) {
                            pasteShots(after: held.last)
                            return nil
                        }
                    }
                }
                // The image cell's own clipboard: ⌘C puts the lead frame's
                // picture on the clipboard; ⌘V lands whatever media the
                // clipboard holds. Neither is a checking-run path — the
                // clipboard is his.
                if !state.editing, state.cursorColumn == "image",
                   state.cellRange == nil, !Launch.checking, let row = cursorRow,
                   let key = event.charactersIgnoringModifiers?.lowercased(),
                   ["c", "v"].contains(key) {
                    if key == "c" {
                        if let frame = row.frame,
                           let picture = Thumbs.shared.image(frame, from: state.engine) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.writeObjects([picture])
                            state.say("Copied the frame.")
                        } else {
                            state.say("No frame on this shot to copy.")
                        }
                        return nil
                    }
                    if Ingest.fromPasteboard(onto: actingOn, state: state) { return nil }
                    // **Words on the clipboard are cells, even here.** The
                    // picture column is the first one on the table, so a block
                    // copied across a row and pasted back at its first cell
                    // started here, was told there was nothing to paste, and
                    // never reached the other columns. Only an empty clipboard
                    // is nothing; text falls through to the cell paste below,
                    // which skips this column and lands the rest.
                    if clipboardText() == nil {
                        state.say("Nothing to paste")
                        return nil
                    }
                }
                // **One rule for ⌘C, ⌘X and ⌘V on cells**, whatever was
                // selected: a dragged rectangle, ticked shots (the cursor's
                // column down them), or the one cell. The three used to be
                // written three times — the lone cell copied only itself while
                // its ticked neighbours took the paste, and Cut only ever
                // emptied the cursor's cell.
                if !state.editing, let key = event.charactersIgnoringModifiers?.lowercased(),
                   ["c", "x", "v"].contains(key), !selectedCells.rows.isEmpty {
                    let (rows, names) = (selectedCells.rows, selectedCells.columns)
                    switch key {
                    case "c":
                        copyCells(rows, names)
                    case "x":
                        cutCells(rows, names)
                    default:
                        // One block when the selection is one cell or one
                        // dragged rectangle; ticked shots apart are not.
                        pasteCells(rows, names,
                                   oneBlock: state.cellRange != nil || rows.count == 1)
                    }
                    return nil
                }
                return event
            }

            // There is one buffer and one owner of the keyboard.
            //
            // The bug this replaced had two of each: the monitor took the
            // character that opened the cell and handed the rest to a text
            // field that was not first responder yet, so exactly the first
            // letter landed. Nothing here is a text field. `state.editSeed` is
            // the only text there is, the monitor is the only thing that writes
            // it, and the open cell draws it.
            if state.editing {
                let picking = Columns.isVocabulary(state.cursorColumn)
                // When a real text view has the keyboard, every key is its
                // own — caret, selection, ⌘A, ⌘C, Shift-Return — and the four
                // that belong to the table come back through `leave`. The
                // monitor only types when nothing else can, which is what a
                // checking run is: the window is never brought forward, so the
                // view never becomes first responder and no key would land.
                //
                // `NSApp.isActive` is not belt and braces, it is the whole
                // safety catch. Letting a key event through means AppKit has to
                // deliver it, and delivering a key event needs a key window —
                // so it makes one, and the app comes to the front and takes
                // Nathaniel's place in whatever he was doing. A check may not
                // cost him that. When the app is not in front, nothing is
                // passed through and the monitor does the typing itself.
                if state.editorLive && NSApp.isActive && !picking { return event }
                let choices = cursorRow.map { entries($0) } ?? []
                switch event.keyCode {
                // Arrows walk an open list rather than the grid — this is the
                // behaviour in the recording: type, arrow down the options,
                // press Return, and the selection is ready to move on.
                case 125 where picking && !choices.isEmpty:             // down
                    state.pickTouched = true
                    state.pickAt = min(state.pickAt + 1, choices.count - 1)
                    return nil
                case 126 where picking && !choices.isEmpty:             // up
                    state.pickTouched = true
                    state.pickAt = max(state.pickAt - 1, 0)
                    return nil
                // Left and right at an open list are nothing — swallowed, not
                // typed. An arrow's `characters` is a private-use scalar
                // (U+F702…), not a control character, so the old guard let it
                // through and every ← pressed at a picker appended an invisible
                // character to the filter. The matches vanished and nothing on
                // screen said why.
                case 123 where picking, 124 where picking:
                    return nil
                // Return takes what is highlighted, never the half-word that
                // filtered the list. Typing "Pro" into Shot Angle used to write
                // a second term called "Pro" next to Profile — a picker that
                // teaches the project a typo is worse than one that refuses.
                case 36 where picking:
                    takeHighlighted(choices, then: (0, 0))
                    return nil
                case 48 where picking:                                  // tab
                    takeHighlighted(choices, then: nil, event: event)
                    return nil
                // Shift-Return is a second line, not a commit. The text view
                // does this itself when it has the keyboard; the monitor has to
                // agree with it, or the behaviour would depend on which of them
                // was typing — and then a check could not see the real one.
                case 36 where event.modifierFlags.contains(.shift):
                    state.editSeed += "\n"
                    return nil
                // Return puts the value in and **closes the cell where it
                // stands** — his call. A sheet drops down a row here; he
                // wants the cursor to stay put, and the arrows to be how you
                // move. Tab still commits and steps right.
                case 36: commitAndStep(rows: 0, columns: 0); return nil
                case 53: state.editing = false; state.editSeed = ""; return nil
                case 48: commitAndStep(back: event.modifierFlags.contains(.shift)); return nil
                // Replace mode: every arrow commits and moves, exactly as the
                // recording shows for fresh typing. Revise mode: the arrows are
                // the caret's. Headless there is no caret to move, so they are
                // swallowed rather than left to fall into the text.
                case 125 where state.editOpenedByTyping: commitAndStep(rows: 1, columns: 0); return nil
                case 126 where state.editOpenedByTyping: commitAndStep(rows: -1, columns: 0); return nil
                case 124 where state.editOpenedByTyping: commitAndStep(rows: 0, columns: 1); return nil
                case 123 where state.editOpenedByTyping: commitAndStep(rows: 0, columns: -1); return nil
                case 123, 124, 125, 126:
                    return nil
                case 51:                                                // delete
                    if !state.editSeed.isEmpty { state.editSeed.removeLast() }
                    state.pickAt = 0
                    state.pickTouched = true
                    return nil
                case 117:                                               // fwd delete
                    return nil
                default:
                    guard let typed = event.characters, Columns.printable(typed)
                    else { return event }
                    state.editSeed += typed
                    // Every keystroke re-filters, so the highlight goes back to
                    // the top of what is left rather than pointing at whatever
                    // used to be in that position.
                    state.pickAt = 0
                    state.pickTouched = true
                    return nil
                }
            }

            let shown = everyRow
            guard !shown.isEmpty else { return event }
            // **Never teleport.** `?? 0` used to stand here, and it is how a
            // cursor the list could not place became "go to the top of the
            // script" — silently, on every arrow key. A cursor we cannot find
            // is a bug worth doing nothing about, not a reason to move him.
            // Row zero is only correct when nothing is chosen yet.
            let at: Int
            if let here = shown.firstIndex(where: { $0.id == state.cursorShot }) {
                at = here
            } else if state.cursorShot == nil {
                at = 0
            } else {
                return event
            }
            let column = columns.firstIndex(of: state.cursorColumn) ?? 0

            // ⇧ with an arrow stretches the block from the cell the cursor is
            // in; Home, End, Page Up and Page Down move (⇧ stretches).
            let shift = event.modifierFlags.contains(.shift)
            let page = max(3, state.rowFrames.count - 2)
            switch event.keyCode {
            case 125 where shift: stretch(rows: 1, columns: 0); return nil
            case 126 where shift: stretch(rows: -1, columns: 0); return nil
            case 124 where shift: stretch(rows: 0, columns: 1); return nil
            case 123 where shift: stretch(rows: 0, columns: -1); return nil
            case 115 where !shift: move(shown, at, 0); return nil      // home
            case 119 where !shift: move(shown, at, columns.count - 1); return nil // end
            case 115: stretch(rows: 0, columns: -1, toEnd: true); return nil
            case 119: stretch(rows: 0, columns: 1, toEnd: true); return nil
            case 121 where !shift: move(shown, at + page, column); return nil // page down
            case 116 where !shift: move(shown, at - page, column); return nil // page up
            case 121: stretch(rows: page, columns: 0); return nil
            case 116: stretch(rows: -page, columns: 0); return nil
            case 125: move(shown, at + 1, column); return nil          // down
            case 126: move(shown, at - 1, column); return nil          // up
            case 124: move(shown, at, column + 1); return nil          // right
            case 123: move(shown, at, column - 1); return nil          // left
            case 48:                                                    // tab
                tab(back: shift)
                return nil
            case 36:                                                    // return
                if state.cursorShot == nil { move(shown, 0, 0) }
                // A choice cell opens showing its whole list with the value it
                // holds ticked, rather than that value pre-typed into the
                // filter — which would hide every other option behind it.
                if let here = everyRow.first(where: { $0.id == state.cursorShot }) {
                    openForEditing(here, state.cursorColumn)
                }
                return nil
            case 53:                                                    // escape
                state.editing = false
                // The outline round what was copied goes first; the block of
                // selected cells goes on the next press.
                if state.copiedCells != nil {
                    state.copiedCells = nil
                    state.copiedCut = false
                    return nil
                }
                state.marked.removeAll()
                state.cellRange = nil
                return nil
            case 51, 117:                                               // delete
                // Over a drag-selected range, Delete empties the rectangle —
                // every clearable column crossed, one engine transaction, one
                // ⌘Z. Camera is a reference, so its group clears `unit`.
                state.copiedCells = nil
                state.copiedCut = false
                if state.cellRange != nil, let engine = state.engine {
                    let (rows, names) = rangeCells
                    let groups = names.filter { Columns.clearable($0) }.map {
                        (field: $0 == "camera" ? "unit" : $0,
                         shots: rows.map(\.shot))
                    }
                    if !groups.isEmpty { state.replace(engine.clearCells(groups)) }
                    return nil
                }
                // **On the picture column, ⌫ asks first.** A photograph is
                // not a cell value — clearing it silently is how somebody
                // loses a frame they cannot type back — so this is the one
                // Delete in the table that stops and says what it will cost.
                if state.cursorColumn == "image", let row = cursorRow {
                    if !row.stills.isEmpty { removingFrames = row.stills }
                    return nil
                }
                // Delete on a selected cell clears it, which is what a sheet
                // does. A reference field clears its reference; a multi-value
                // cell drops all its values.
                if let row = cursorRow, Columns.clearable(state.cursorColumn) {
                    write(row, state.cursorColumn, "")
                }
                return nil
            default:
                // Typing a printable character starts an edit seeded with it,
                // the way a spreadsheet does. *Printable* means anything a
                // person would call typing — letters, digits, space, "+",
                // "/" — not the old alphanumerics-and-punctuation test, which
                // silently refused a space and every symbol, so "+2 stop" and
                // " 3/4" could not be started.
                guard let typed = event.charactersIgnoringModifiers,
                      Columns.printable(typed)
                else { return event }
                // On a yes-or-no cell, space flips — a sheet's checkbox key —
                // and other typing lands nowhere rather than opening an
                // editor the cell does not have.
                if Columns.isCheck(state.cursorColumn) {
                    if typed == " ", let row = cursorRow {
                        write(row, state.cursorColumn,
                              Columns.chosen(row, state.cursorColumn).isEmpty ? "1" : "")
                    }
                    return nil
                }
                // Typing on a media cell lands nowhere — there is no text
                // there, and no field that should quietly eat one.
                if !Columns.hasEditor(state.cursorColumn) { return nil }
                if state.cursorShot == nil { move(shown, 0, 0) }
                state.editSeed = typed
                state.pickAt = 0
                state.pickTouched = true
                state.editOpenedByTyping = true
                state.copiedCells = nil
                state.copiedCut = false
                state.editing = true
                return nil
            }
        }
    }

    /// Takes the highlighted row of an open list, then moves the way a sheet
    /// would. With nothing on the list at all, the keystroke closes the cell
    /// and moves on rather than writing the half-word that found nothing.
    private func takeHighlighted(_ choices: [Pick], then step: (Int, Int)?, event: NSEvent? = nil) {
        let shown = everyRow
        let at = shown.firstIndex { $0.id == state.cursorShot } ?? 0
        let column = columns.firstIndex(of: state.cursorColumn) ?? 0
        // A pristine picker's Return closes it and moves on, writing nothing.
        // Nothing was typed and the highlight was never moved, so nothing was
        // chosen — and "nothing chosen" must not mean "the first thing on the
        // list", or Return-Return would overwrite the cell, and on a
        // multi-value cell it would toggle the current value *off*.
        let chose = state.pickAt < choices.count
            && (state.pickTouched || !state.editSeed.isEmpty)
        if let row = cursorRow, chose {
            writePick(choices[state.pickAt], on: row)
        }
        // On a multi-value cell, Return *toggles* what is highlighted and the
        // list stays open for the next one — the same grammar as clicking the
        // options, so several pills go on in one visit. The filter clears and
        // the picker is pristine again, which is the way out: the next plain
        // Return closes it and moves down.
        if chose, step?.0 == 0, step?.1 == 0,
           Columns.isMulti(state.cursorColumn) || state.cursorColumn == "lens" {
            state.editSeed = ""
            state.pickTouched = false
            state.pickAt = 0
            return
        }
        state.editing = false
        state.editSeed = ""
        state.pickAt = 0
        if let step {
            move(shown, at + step.0, column + step.1)
        } else {
            tab(back: event?.modifierFlags.contains(.shift) ?? false)
        }
    }

    /// Commits whatever is in the open cell, wherever it was typed.
    private func commitOpenCell() {
        // `allRows`, not the scene's rows: a scene or tab switch with a cell
        // open has to be able to put the words away before the rows it was
        // reading go out of scope.
        guard let id = state.cursorShot,
              let row = state.view?.allRows.first(where: { $0.id == id }) else { return }
        let name = state.cursorColumn
        // Leaving an open *picker* writes nothing. The filter text is a
        // search, not a value, and clicking elsewhere is walking away from a
        // dropdown — a sheet abandons it. The deliberate paths — Return, Tab,
        // clicking an option — all commit through `takeHighlighted` and
        // `take`, never through here.
        if Columns.isVocabulary(name) { return }
        // Leaving an open *text cell* writes what is in it — that is the rule
        // a sheet lives by. Unchanged text writes nothing, so clicking through
        // a cell you opened and left alone does not stamp a no-op change into
        // the project's history.
        guard state.editSeed != Columns.value(row, name) else { return }
        write(row, name, state.editSeed)
    }

    /// Commits what is open and moves in one press.
    ///
    /// With no offsets given this is Tab: commit and step right, wrapping to the
    /// next row. With offsets it is Return or an arrow.
    private func commitAndStep(rows dr: Int, columns dc: Int) {
        let shown = everyRow
        let at = shown.firstIndex { $0.id == state.cursorShot } ?? 0
        let column = columns.firstIndex(of: state.cursorColumn) ?? 0
        commitOpenCell()
        state.editing = false
        state.editSeed = ""
        move(shown, at + dr, column + dc)
    }

    /// Tab: commit and step across, wrapping to the next row.
    private func commitAndStep(back: Bool) {
        commitOpenCell()
        state.editing = false
        state.editSeed = ""
        tab(back: back)
    }

    /// **Tab inside a block walks the block**: across each row, then down to
    /// the next, wrapping from the last cell to the first, with the block
    /// still selected — a sheet's way of filling in a rectangle. With no block
    /// it steps across the table and wraps to the next row.
    private func tab(back: Bool) {
        let shown = everyRow
        let block = rangeCells
        if state.cellRange != nil,
           let r = block.rows.firstIndex(where: { $0.id == state.cursorShot }),
           let c = block.columns.firstIndex(of: state.cursorColumn) {
            let wide = block.columns.count
            let count = block.rows.count * wide
            let next = ((r * wide + c) + (back ? -1 : 1) + count) % count
            state.cursorShot = block.rows[next / wide].id
            state.cursorColumn = block.columns[next % wide]
            return
        }
        let at = shown.firstIndex { $0.id == state.cursorShot } ?? 0
        let column = columns.firstIndex(of: state.cursorColumn) ?? 0
        move(shown, at, column + (back ? -1 : 1), wrap: true)
    }

    /// The ⌘ chords that run to an edge, as something to do — nil for any
    /// other key. ⇧ makes them stretch the block instead of moving the cursor.
    private func edgeWalk(_ event: NSEvent) -> (() -> Void)? {
        let shift = event.modifierFlags.contains(.shift)
        let shown = everyRow
        guard !shown.isEmpty, !columns.isEmpty else { return nil }
        let at = shown.firstIndex { $0.id == state.cursorShot } ?? 0
        switch event.keyCode {
        case 123 where shift: return { stretch(rows: 0, columns: -1, toEnd: true) }
        case 124 where shift: return { stretch(rows: 0, columns: 1, toEnd: true) }
        case 126 where shift: return { stretch(rows: -1, columns: 0, toEnd: true) }
        case 125 where shift: return { stretch(rows: 1, columns: 0, toEnd: true) }
        case 123: return { move(shown, at, 0) }
        case 124: return { move(shown, at, columns.count - 1) }
        case 115: return { move(shown, 0, 0) }
        case 119: return { move(shown, shown.count - 1, columns.count - 1) }
        default: return nil
        }
    }

    private func move(_ shown: [ViewModel.Row], _ row: Int, _ column: Int, wrap: Bool = false) {
        state.cellRange = nil
        var row = row, column = column
        if wrap {
            if column >= columns.count { column = 0; row += 1 }
            if column < 0 { column = columns.count - 1; row -= 1 }
        }
        guard !shown.isEmpty, !columns.isEmpty else { return }
        state.cursorShot = shown[min(max(0, row), shown.count - 1)].id
        state.wholeShots.removeAll()
        state.cursorColumn = columns[min(max(0, column), columns.count - 1)]
    }
}

// ------------------------------------------------------------------- columns

/// What a column is called, how wide it is, and how its value is drawn.
///
/// One place, so the header, the cell and the editor cannot drift apart — the
/// same reason the old app kept this in one table.
enum Columns {
    /// Constant, and reserved whether anything is in it or not.
    static var gutter: CGFloat { 62 * Brand.density }

    /// **One left edge.** The scene number, the shot number, "+ Add shot" and
    /// the first column head all start here — 2026-09-14. The band used to
    /// sit at 66 and the rows at 26.
    static var edge: CGFloat { Brand.pad(26) }

    /// Widths Nathaniel has dragged, over the standards below.
    ///
    /// A width is a way of reading this screen, not a fact about the list —
    /// the old app's words — so it stays on this Mac, per project, rather
    /// than travelling with the file the way column *order* does (order is
    /// the engine's, because the document page's technical line reads in it).
    static var overrides: [String: CGFloat] = [:]
    private static var overridesKey = "columnWidths.default"

    static func loadWidths(project: String?) {
        // A checking run gets its own store. A battery scratch is a copy of
        // the fixture, so it carries the fixture's project id — WHICH IS HIS
        // REAL DAYBREAK'S ID: without this split, every resize check read and
        // wrote his actual width preferences, and his hand-set widths fed
        // back into the battery's expected numbers. Found when three header
        // checks failed against widths nobody in the battery had set.
        overridesKey = Launch.checking
            ? "columnWidths.checking"
            : "columnWidths.\(project ?? "default")"
        let stored = UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: Double] ?? [:]
        overrides = stored.mapValues { CGFloat($0) }
    }

    /// No column shrinks below its own name — his rule: the header stays on
    /// one line, always. Measured from the label at the header's font, plus
    /// the icon, the sort arrow's slot, and the paddings around them.
    /// **Measured once per column, not once per cell per frame.**
    ///
    /// This asks Core Text how wide the header's words are — a real text
    /// measurement, with a font lookup and a dictionary built for it — and
    /// `width(_:)` calls it. `width(_:)` is asked by every cell of every row
    /// the table lays out, so on a window showing fifteen columns and thirty
    /// rows that was **four hundred and fifty string measurements per frame
    /// of a scroll**, all of them for the same fifteen answers. Profiling a
    /// fast scroll on 2026-08-29 put `minimum` and `width` at the top of the
    /// app's own cost, above everything that draws.
    ///
    /// The answer only moves when the header's words do, and the font is
    /// fixed, so it is kept — and thrown away wholesale whenever the labels
    /// are refilled from a new view model (see `custom` and `named`).
    private static var minimums: [String: CGFloat] = [:]

    /// **Measured on every call, and that is fine — it was checked.**
    ///
    /// This asks Core Text how wide the header's words are, and `width(_:)`
    /// calls it; `width(_:)` is asked by every cell of every row the table
    /// lays out, so a window of fifteen columns and thirty rows measures four
    /// hundred and fifty strings per frame of a scroll. It looks indefensible,
    /// and a profile of a fast scroll on 2026-08-29 put `minimum` and `width`
    /// at the top of the app's *own* cost — so they were memoised, keyed by
    /// column and thrown away whenever the labels are refilled.
    ///
    /// **It made no difference: 6.29/6.39/6.73 seconds of processor against
    /// 6.24/6.34/6.43 without, over the same fifteen-second scroll.** Top of
    /// our own cost turned out to be a quarter of one per cent of the whole;
    /// the scroll's time is inside SwiftUI. The cache came back out rather
    /// than stand as a thing that can go stale for nothing. The numbers are
    /// here so nobody spends the afternoon again.
    static func minimum(_ name: String) -> CGFloat {
        let label = label(name) as NSString
        let wide = label.size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold)
        ]).width
        return max(54, wide + 52)
    }

    /// Nil puts the column back to its standard width. Stored at density 1,
    /// the old app's rule, so zooming the table does not silently rewrite
    /// every width a hand ever set.
    static func setWidth(_ name: String, to points: CGFloat?) {
        if let points {
            overrides[name] = max(minimum(name), min(560, points / Brand.density))
        } else {
            overrides.removeValue(forKey: name)
        }
        // The checking store is the battery's own; his is his. Both go
        // through the one law, which no-ops the write while checking — so the
        // battery's widths live only as long as its process.
        if Launch.checking {
            UserDefaults.standard.set(overrides.mapValues(Double.init), forKey: overridesKey)
        } else {
            Remembering().set(overrides.mapValues(Double.init), forKey: overridesKey)
        }
    }

    /// The project's own columns — field slug to what the header says and
    /// what shape the cells are. Written only by `ShellState.replace()`, from
    /// the view model, so it is a reading of the engine's answer rather than
    /// a copy that could drift.
    static var custom: [String: (label: String, kind: String)] = [:] {
        // A column's floor is measured from its label, so a new set of labels
        // means the measurements are stale. Refilled from every view model.
        didSet { minimums.removeAll(keepingCapacity: true) }
    }

    /// What every field is called, straight from the engine — Ref 249.
    ///
    /// **This app used to hold its own list**, and so did the phone, which is
    /// two copies of "Camera Gear" that could disagree. Now there is one, in
    /// `engine/src/columns.rs`, and both shells read it. Refreshed from every
    /// view model, so it cannot outlive the answer it came from.
    static var named: [String: String] = [:] {
        didSet { minimums.removeAll(keepingCapacity: true) }
    }

    /// A column by the name a check gives it: a built-in's own name, or a
    /// project column's label (`Sound`), which is what a person sees.
    static func resolve(_ asked: String, state: ShellState) -> String {
        if let own = custom.first(where: {
            $0.value.label.caseInsensitiveCompare(asked) == .orderedSame }) {
            return own.key
        }
        return asked
    }

    static func label(_ name: String) -> String {
        if let own = custom[name] { return own.label }
        if let said = named[name] { return said }
        return name.capitalized
    }

    static func icon(_ name: String) -> String {
        if let own = custom[name] {
            switch own.kind {
            case "single": return "chevron.down.circle"
            case "multi": return "tag"
            case "check": return "checkmark.circle"
            case "media": return "photo"
            case "location": return "mappin.and.ellipse"
            default: return "text.alignleft"
            }
        }
        switch name {
        case "image": return "photo"
        case "title": return "textformat"
        case "description": return "text.alignleft"
        case "size": return "rectangle"
        case "angle": return "angle"
        case "movement": return "arrow.left.and.right"
        case "camera": return "camera"
        case "lens": return "circle.circle"
        case "modifiers": return "plus.magnifyingglass"
        case "lens_filters": return "camera.filters"
        // "tripod" is not in this OS's symbol set and renders as nothing —
        // an empty icon slot reads as a broken row in the columns sheet.
        case "support": return "triangle"
        case "notes": return "note.text"
        case "tags": return "tag"
        case "day": return "calendar"
        case "sequence": return "square.stack"
        case "struck": return "xmark"
        default: return "square"
        }
    }

    /// **What every column gains when the table is narrower than the window.**
    ///
    /// His ask: "when the program window expands past the table length, the end
    /// of the table should lock onto the edge of the panel and evenly
    /// distribute more width between columns while expanding, but then reset
    /// when it's small enough again." A table that stops halfway across a wide
    /// window with dead grey to its right looks unfinished, and the space is
    /// doing nothing for him.
    ///
    /// It is a *drawn* thing, never a stored one — nothing here is written to
    /// his widths, so making the window wide and narrow again leaves the
    /// columns exactly as he set them. That is the whole reason it is a
    /// separate number rather than a nudge to `overrides`.
    static var spread: CGFloat = 0
    /// The last width the table was handed, kept only so a check can say
    /// whether the measurement arrived at all.
    static var lastMeasured: CGFloat = 0
    /// Where the table actually is on screen. The mouse monitor needs it: the
    /// columns are wider than the window, so a header frame exists at an x well
    /// past the table's right edge, and without this the monitor claimed a
    /// press in the *panel* as a press on a cell — which is why the panel's new
    /// resize handle could not be grabbed at all.
    static var lastFrame: CGRect = .zero

    static func width(_ name: String) -> CGFloat {
        // The floor applies to stored values too — the width store carried
        // sub-floor widths from before the rule (and from the days it was
        // shared with his real project).
        max(minimum(name), overrides[name] ?? standard(name)) * Brand.density + spread
    }

    /// The width without the stretch — what a drag should write back, so
    /// widening one column does not quietly bake the surplus into all of them.
    static func stored(_ name: String) -> CGFloat {
        max(minimum(name), overrides[name] ?? standard(name)) * Brand.density
    }

    /// Share out whatever the window has spare, or take it back. Returns
    /// whether anything actually moved, so the table only re-draws when it did.
    @discardableResult
    static func fit(_ available: CGFloat, across names: [String]) -> Bool {
        lastMeasured = available
        guard !names.isEmpty, available > 0 else { return false }
        let held = names.reduce(0) { $0 + stored($1) } + gutter
        let over = (available - held) / CGFloat(names.count)
        let want = max(0, over)
        guard abs(want - spread) > 0.5 else { return false }
        spread = want
        return true
    }

    static func standard(_ name: String) -> CGFloat {
        switch name {
        case "image": return 132
        case "title": return 170
        case "description": return 280
        case "size": return 118
        case "angle": return 132
        case "movement": return 130
        case "camera": return 140
        // **Wide enough for a lens's whole name.** At 96 a chip had 64
        // points of text and "Canon Cine Servo 50-1000mm" came out on four
        // lines, one of them "m" — his report, 2026-09-15. Lens names are
        // the longest values in the table; 150 puts that one on two lines,
        // whole words.
        case "lens": return 200
        case "modifiers": return 150
        case "lens_filters": return 140
        case "support": return 116
        case "notes": return 190
        case "script": return 240
        case "tags": return 140
        case "day": return 92
        case "sequence": return 116
        case "struck": return 72
        default: return 110
        }
    }

    /// What is already on this cell, so the list can tick it.
    static func chosen(_ row: ViewModel.Row, _ name: String) -> [String] {
        switch name {
        case "angle": return row.angle
        case "tags": return row.tags
        case "modifiers": return row.modifierList
        case "lens_filters": return row.lensFilters
        default:
            if custom[name] != nil { return row.custom?[name] ?? [] }
            let one = value(row, name)
            return one.isEmpty ? [] : [one]
        }
    }

    /// The ones that hold more than one value at a time.
    static func isMulti(_ name: String) -> Bool {
        ["angle", "tags", "modifiers", "lens_filters"].contains(name) || custom[name]?.kind == "multi"
    }

    /// A yes-or-no cell: never opens an editor, only flips.
    static func isCheck(_ name: String) -> Bool {
        custom[name]?.kind == "check"
    }

    /// The cells typing can open. A media cell — the Storyboard column, and
    /// any custom media or location column — has no text to edit: its
    /// double-click will summon the media window when the Storyboard work
    /// lands, and until then the gesture does nothing. Opening a text box
    /// there wrote to a field nothing reads — the silent-value-eater family,
    /// third sighting.
    static func hasEditor(_ name: String) -> Bool {
        if name == "image" { return false }
        // The quoted words are the script's — tied in the script panel.
        if name == "script" { return false }
        // Day is sealed until the Schedule build (the old app's feature):
        // a shoot day is an assignment to a real day record, not a word —
        // and the text box this cell used to open wrote to a field nothing
        // reads. His call: it must not be overridable with text.
        if name == "day" { return false }
        if let kind = custom[name]?.kind, ["media", "location"].contains(kind) {
            return false
        }
        return true
    }

    /// The ones that are a project list rather than free text.
    ///
    /// Camera is here too, and it is not a vocabulary at all — it is a
    /// reference to one of the project's units. It behaves the same way to a
    /// hand on the keyboard, which is what this list is for; what it *writes*
    /// is handled where the writing happens.
    ///
    /// Tags is here because it holds *several* values — and a multi-value
    /// cell that opens as a text box is a trap: it opened seeded with every
    /// pill as comma text, and committing that string appended the lot back
    /// as one new value, doubling every pill on the cell. A cell of pills
    /// opens as a list of pills, always.
    static func isVocabulary(_ name: String) -> Bool {
        ["size", "movement", "lens", "modifiers", "lens_filters", "support", "angle", "camera", "tags"].contains(name)
            || ["single", "multi"].contains(custom[name]?.kind ?? "")
    }

    /// What a choice cell offers.
    /// **Worked out once per view model.** Asking the engine what a column
    /// holds is a scan of every shot in the film, and a `Menu`'s items are
    /// built by the body around it whether or not anybody opens it — so the
    /// filter bar was doing one scan per facetable column on every pass. The
    /// answer cannot go stale: teaching a list a new word replaces the view
    /// model, which empties this.
    static func options(_ name: String, state: ShellState) -> [String] {
        state.reckon("vocab." + name) {
            if name == "camera" { return (state.view?.units ?? []).map(\.label) }
            return state.engine?.vocabulary(name) ?? []
        }
    }

    /// Whether typing an unknown word into this cell may teach the project.
    ///
    /// Every column may, by the engine's oldest rule — and camera since the
    /// engine learned `addunit`: a new name in the camera picker births a real
    /// unit, coloured from the palette in turn. **Unless the list has been
    /// locked**, which is his ask: by the time a film is shooting, a stray
    /// "Handheld " is a near-duplicate of a term that was already right. A
    /// locked list stops *offering* to create, rather than offering and then
    /// refusing — the engine would refuse either way, but a control that does
    /// nothing is worse than its absence.
    static func canCreate(_ name: String, state: ShellState) -> Bool {
        !((state.view?.columns ?? []).first { $0.name == name }?.locked ?? false)
    }

    /// The six colours a shot (or a new camera) can wear, with the names a
    /// menu can say — a context menu draws its icons monochrome, so the name
    /// is the only part of the colour a person can actually see there.
    // `shared/Swatches.swift`, which the iPhone draws from too.
    static let palette = Swatches.highlight
    static let paletteNames = Swatches.highlightNames

    /// The options that match what has been typed, best first.
    ///
    /// Best first is the whole point: Return takes the top one, so "W" has to
    /// put W above W/OTS, and "Pro" has to put Profile above anything that
    /// merely contains those letters.
    static func rank(_ options: [String], query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return options }
        func score(_ option: String) -> Int? {
            let o = option.lowercased()
            if o == q { return 0 }
            if o.hasPrefix(q) { return 1 }
            if o.contains(q) { return 2 }
            return nil
        }
        return options
            .compactMap { option in score(option).map { (option, $0) } }
            .enumerated()
            .sorted { ($0.element.1, $0.offset) < ($1.element.1, $1.offset) }
            .map(\.element.0)
    }

    /// Whether a string is something a person would call typing: no control
    /// characters, and none of the function-key private-use scalars — an arrow
    /// key's `characters` is U+F702, which is not a control character, and the
    /// old guard let it into the buffer as an invisible letter.
    static func printable(_ typed: String) -> Bool {
        guard !typed.isEmpty else { return false }
        return typed.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
                && !(0xF700...0xF8FF).contains(scalar.value)
        }
    }

    /// The columns Delete may clear and ⌘V may write. The Storyboard column is
    /// pictures, and `struck` is a flag with its own gesture — writing text at
    /// either would put junk on the record.
    static func clearable(_ name: String) -> Bool {
        isVocabulary(name) || ["title", "description", "notes", "tags"].contains(name)
            || (custom[name] != nil && hasEditor(name))
    }

    /// The size the column's text is drawn at — and edited at. An editor whose
    /// type is a different size from the cell it sits on reads as a pop-over,
    /// not as the cell opening.
    /// The open editor's type — **at the table's density**, like the type it
    /// is standing in for. An editor still at full size inside a shrunken row
    /// is the same complaint from the other side: the words no longer fit the
    /// box they are being typed into.
    static func fontSize(_ name: String) -> CGFloat {
        switch name {
        case "description": return Brand.type(13)
        case "title": return Brand.type(12.5)
        case "notes": return Brand.type(11.5)
        default: return Brand.type(12)
        }
    }

    /// What has been typed, when it is not already on the list.
    static func novel(_ options: [String], query: String) -> String? {
        let typed = query.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return nil }
        return options.contains { $0.caseInsensitiveCompare(typed) == .orderedSame }
            ? nil : typed
    }

    /// A camera unit carries its own colour into the list, so picking one reads
    /// the way the row will read once it is picked.
    static func chipColour(_ name: String, _ option: String,
                           state: ShellState, dark: Bool) -> Color? {
        if name == "camera" {
            guard let unit = state.view?.units.first(where: { $0.label == option })
            else { return Brand.ink3(dark) }
            return Brand.data(unit.colour, dark)
        }
        // The same colour it will wear in the row, so choosing looks like what
        // you are choosing.
        return Brand.chipInk(name, option, dark)
    }

    /// One writer for a picked or typed value, shared by the table and the
    /// document page — the routing IS the behaviour (camera births units,
    /// multi toggles), so two copies of it would be two chances to disagree.
    static func write(_ row: ViewModel.Row, _ name: String, typed: String,
                      state: ShellState) {
        guard let engine = state.engine else { return }

        // Camera Gear is a **reference**: the value is a unit the project owns,
        // and the engine's field is called `unit`, not `camera`. Writing the
        // label to a field named after the column is accepted in silence and
        // read by nothing — the same family as the shot-vs-placement bug, and
        // it is why this column refused every edit while looking fine.
        if name == "camera" {
            // Empty clears the reference — that is what deleting the cell
            // means.
            if typed.isEmpty {
                state.replace(engine.set(shot: row.shot, field: "unit", value: ""))
                return
            }
            if let unit = state.view?.units.first(where: {
                $0.label.caseInsensitiveCompare(typed) == .orderedSame
            }) {
                state.replace(engine.set(shot: row.shot, field: "unit", value: unit.id))
                return
            }
            // A name the project has not seen births a real unit — the engine
            // owns the record; the colour comes from the palette in turn, so
            // the third camera is not the same red as the first.
            // Birth and pointing are one thing to take back.
            engine.grouped("Change shot") {
                let colour = Columns.palette[
                    (state.view?.units.count ?? 0) % Columns.palette.count]
                state.replace(engine.addUnit(label: typed, colour: colour))
                if let unit = state.view?.units.first(where: {
                    $0.label.caseInsensitiveCompare(typed) == .orderedSame
                }) {
                    state.replace(engine.set(shot: row.shot, field: "unit", value: unit.id))
                }
            }
            return
        }

        // A multiple-choice column gathers rather than replaces: his Angle ends
        // as "Profile 3/4", two chips in one cell. Picking a value already on
        // the cell takes it off again, so the same gesture adds and removes.
        if Columns.isMulti(name) && !typed.isEmpty {
            var held = Columns.chosen(row, name)
            if let at = held.firstIndex(where: { $0.caseInsensitiveCompare(typed) == .orderedSame }) {
                held.remove(at: at)
            } else {
                held.append(typed)
            }
            state.replace(engine.set(shot: row.shot, field: name,
                                     value: held.joined(separator: ", ")))
            return
        }

        // `row.shot`, not `row.placement`. A placement is where a shot sits in
        // a scene; the fields belong to the shot itself. Both are valid ids, so
        // passing the wrong one is accepted without complaint and writes to a
        // record nothing reads — the value simply disappears. That is what made
        // typing look like it dropped every character after the first.
        state.replace(engine.set(shot: row.shot, field: name, value: typed))
    }

    /// The value as text — what an editor starts from and what a chip shows.
    static func value(_ row: ViewModel.Row, _ name: String) -> String {
        switch name {
        case "title": return row.title
        case "description": return row.description
        case "script": return row.script
        case "size": return row.size
        case "angle": return row.angle.joined(separator: ", ")
        case "movement": return row.movement
        case "lens": return row.lens
        case "support": return row.support
        case "notes": return row.notes
        case "tags": return row.tags.joined(separator: ", ")
        case "modifiers": return row.modifierList.joined(separator: ", ")
        case "lens_filters": return row.lensFilters.joined(separator: ", ")
        case "day": return row.day ?? ""
        case "camera": return row.unit?.label ?? ""
        default: return (row.custom?[name] ?? []).joined(separator: ", ")
        }
    }

    @ViewBuilder
    static func draw(_ row: ViewModel.Row, _ name: String, dark: Bool) -> some View {
        let text = value(row, name)
        switch name {
        case "image":
            EmptyView()
        case "description":
            Text(text)
                .sans(Brand.type(13))
                .lineSpacing(Brand.pad(1.5))
                .fixedSize(horizontal: false, vertical: true)
                .strikethrough(row.struck, pattern: .solid, color: Brand.ink3(dark))
                .foregroundStyle(Brand.ink(dark))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Brand.pad(9))
                .padding(.vertical, Brand.pad(7))
        case "title":
            Text(text).sans(Brand.type(13), weight: .semibold)
                .foregroundStyle(Brand.ink(dark))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Brand.pad(9)).padding(.vertical, Brand.pad(7))
        case "notes":
            Text(text).sans(Brand.type(11))
                .foregroundStyle(Brand.ink2(dark))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Brand.pad(9)).padding(.vertical, Brand.pad(7))
        // **The words the shot quotes, read, not written.** Empty when it
        // quotes nothing; the script panel is where a shot is tied.
        //
        // **Four lines at most** — his ask, 2026-10-05: a long quote must
        // not become the tallest cell in the table. The rest is in the
        // script panel, and the whole of it on hover.
        case "script":
            Text(text).sans(Brand.type(11))
                .foregroundStyle(Brand.ink2(dark))
                .lineLimit(4)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .help(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Brand.pad(9)).padding(.vertical, Brand.pad(7))
        case "struck":
            // The empty branch is a real view, deliberately. `if` with no else
            // renders as EmptyView, and a frame wrapped around EmptyView is
            // *nothing* — the cell vanishes from layout and every column after
            // it slides over. A freshly added shot was the first row to hit
            // this, and it drew staggered out of line with the table.
            Group {
                if row.struck { Chip(text: "SHOT", colour: Brand.hex("9A6B10")) }
                else { Text("") }
            }
            .padding(.horizontal, Brand.pad(9)).padding(.vertical, Brand.pad(7))
            .frame(maxWidth: .infinity, alignment: .leading)
        case "angle", "tags", "modifiers", "lens_filters":
            // **Along the row first, down the cell only when the row is full.**
            //
            // These stacked unconditionally, from a day when side by side meant
            // a plain `HStack` — which squeezed every chip to share the width
            // and made "Short-Sided" and "3/4" fight for 132pt and lose. That
            // was the right fix for the wrong reason: the problem was the
            // squeezing, not the direction. `WrappingRow` gives each chip its
            // natural width and wraps when the line is full, so a wide column
            // uses its width and a narrow one still stacks. His ask,
            // 2026-08-22: *"they should go side by side and then start stacking
            // once they run out of room … never split a cell in half."*
            let parts = chosen(row, name)
            WrappingRow(spacing: 4, runSpacing: 3) {
                ForEach(parts, id: \.self) { value in
                    Chip(text: value, colour: Brand.chipInk(name, value, dark))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Brand.pad(9)).padding(.vertical, Brand.pad(7))
        case "camera":
            // Same rule as `struck`: the empty branch must be a real view, or
            // the cell collapses and the row mis-aligns.
            Group {
                if let unit = row.unit {
                    Chip(text: unit.label, colour: Brand.data(unit.colour, dark))
                } else {
                    Text("")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Brand.pad(9)).padding(.vertical, Brand.pad(7))
        case "lens" where !(row.lensFilters.isEmpty && row.modifierList.isEmpty):
            // **Lens Stack**: the lens chip on top, its filters and modifiers
            // on a quiet line under it, in the same cell.
            VStack(alignment: .leading, spacing: Brand.pad(4)) {
                if !text.isEmpty {
                    if row.offKit?.lens != nil {
                        Chip(text: text, colour: Brand.data(KitLinks.amber, dark))
                            .overlay {
                                RoundedRectangle(cornerRadius: Brand.pad(4), style: .continuous)
                                    .strokeBorder(Brand.data(KitLinks.amber, dark),
                                                  style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            }
                            .help("Not on Sheet")
                    } else if let mm = row.focal {
                        HStack(spacing: 5) {
                            Chip(text: text, colour: Brand.chipInk(name, text, dark))
                            Text("\(Int(mm.rounded()))mm").sans(Brand.Size.body).monospacedDigit()
                                .foregroundStyle(Brand.ink2(dark)).lineLimit(1).fixedSize()
                        }
                    } else {
                        Chip(text: text, colour: Brand.chipInk(name, text, dark))
                    }
                }
                LensStackLine(filters: row.lensFilters, modifiers: row.modifierList)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Brand.pad(9)).padding(.vertical, Brand.pad(7))
        case "size", "movement", "lens", "support":
            Group {
                if text.isEmpty {
                    Text("").frame(maxWidth: .infinity, alignment: .leading)
                } else if name == "lens", row.offKit?.lens != nil {
                    // **Not on Sheet** (Kit Links, 2026-10-14): a lens its
                    // shoot's spec sheet does not carry, amber and dashed, so
                    // it shows without opening anything.
                    HStack(spacing: 5) {
                        Chip(text: text, colour: Brand.data(KitLinks.amber, dark))
                            .overlay {
                                RoundedRectangle(cornerRadius: Brand.pad(4), style: .continuous)
                                    .strokeBorder(Brand.data(KitLinks.amber, dark),
                                                  style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            }
                            .help("Not on Sheet")
                        if let mm = row.focal {
                            Text("\(Int(mm.rounded()))mm").sans(Brand.Size.body).monospacedDigit()
                                .foregroundStyle(Brand.ink2(dark)).lineLimit(1).fixedSize()
                        }
                    }
                } else if name == "lens", let mm = row.focal {
                    // A zoom, and where it is set: `24-70mm` 35mm.
                    HStack(spacing: 5) {
                        Chip(text: text, colour: Brand.chipInk(name, text, dark))
                        Text("\(Int(mm.rounded()))mm").sans(Brand.Size.body).monospacedDigit()
                            .foregroundStyle(Brand.ink2(dark)).lineLimit(1).fixedSize()
                    }
                } else {
                    Chip(text: text, colour: Brand.chipInk(name, text, dark))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Brand.pad(9)).padding(.vertical, Brand.pad(7))
        case _ where custom[name] != nil:
            // The project's own column draws by its shape. Every empty branch
            // is a real Text("") — the EmptyView law: a frame around nothing
            // is nothing, and the whole row slides out of line.
            let kind = custom[name]?.kind ?? "text"
            let parts = row.custom?[name] ?? []
            Group {
                switch kind {
                case "check":
                    if parts.isEmpty {
                        Text("")
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Brand.accent(dark))
                    }
                case "single", "multi":
                    if parts.isEmpty {
                        Text("")
                    } else {
                        // Along the row first, the same as `angle` and `tags`.
                        WrappingRow(spacing: 4, runSpacing: 3) {
                            ForEach(parts, id: \.self) { value in
                                Chip(text: value, colour: Brand.chipInk(name, value, dark))
                            }
                        }
                    }
                default:
                    Text(text)
                        .sans(Brand.type(13))
                        .foregroundStyle(Brand.ink2(dark))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Brand.pad(9)).padding(.vertical, Brand.pad(7))
        default:
            Text(text)
                .sans(Brand.type(13))
                .foregroundStyle(Brand.ink2(dark))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Brand.pad(9)).padding(.vertical, Brand.pad(7))
        }
    }
}

// --------------------------------------------------------------- picking

/// One row of an open list: something the project already knows, or the word
/// you have typed offered as a new one.
enum Pick: Identifiable {
    case value(String)
    case create(String)
    /// A filter or a modifier, offered in the Lens picker while Lens Stack is
    /// on. `field` is `lens_filters` or `modifiers`.
    case attach(field: String, name: String)

    var id: String {
        switch self {
        case .value(let v): return "v:" + v
        case .create(let v): return "c:" + v
        case .attach(let field, let name): return "a:" + field + ":" + name
        }
    }
}

// ------------------------------------------------------------------- frames

/// Proxies, decoded once.
///
/// The engine hands a frame across the boundary as base64 and hashes it by its
/// contents, so the same picture on two shots is one file and one decode. This
/// keeps the decoded image too, because a table redraws constantly and turning
/// bytes into an `NSImage` on every pass is the kind of waste that shows up as
/// a stutter rather than as an error.
final class Thumbs {
    static let shared = Thumbs()
    private var cache: [String: NSImage] = [:]

    /// **The frames the project has a record of and no file for** — Ref 224,
    /// by content hash, straight from the engine. Kept here rather than passed
    /// down because a frame is drawn in six places and none of them should have
    /// to learn about a set; `ShellState.readHollowFrames` fills it on open and
    /// after every merge.
    ///
    /// Not the same thing as `missing` below. That is *this app failed to read
    /// it just now*, which a photograph still coming down from iCloud also
    /// does. This is *the file is not there and nothing is bringing it*.
    var hollow: Set<String> = [] {
        didSet { if hollow != oldValue { arrivals += 1 } }
    }

    /// **Pictures deleted from the Media window**, by hash, with the name each
    /// left behind — so a version that showed one draws a gap that says what
    /// was there. (`MediaShelf.swift`)
    var gone: [String: String] = [:] {
        didSet { if gone != oldValue { arrivals += 1 } }
    }

    /// **How many times the pictures have changed.**
    ///
    /// A photograph arriving from iCloud is the one thing that changes what a
    /// shot looks like without changing anything *about* the shot — so it is
    /// invisible to the comparison that lets a shot skip being drawn again,
    /// and without this a picture that came down late would stay a blank until
    /// something unrelated redrew the page. Ref 218's problem, one level up.
    private(set) var arrivals = 0

    /// **Pictures asked for that were not there.** Ref 218.
    ///
    /// A failed read is never cached — ask again and it will try again — but
    /// that is only half the problem, and the half that is easy to miss is the
    /// other one: **a file appearing on disk does not by itself cause a
    /// redraw.** A photograph still coming down from Drive or iCloud draws as
    /// nothing, and then nothing ever asks a second time, so it stays nothing
    /// until something unrelated makes the table redraw.
    ///
    /// The phone had exactly this and it made an arriving photograph look like
    /// a broken placeholder until relaunch — which is why he was deleting his
    /// own photographs. Same shape here, so: remember what was missing, and
    /// let the heartbeat ask again.
    private var missing: Set<String> = []

    /// **Decoded whole, and drawn small.**
    ///
    /// The obvious optimisation here is to decode straight to tile size with
    /// `CGImageSourceCreateThumbnailAtIndex`. It was tried on 2026-08-22 and
    /// **measured ten times slower** — 81 ms against 8.4 ms for the first draw
    /// of a 4800-pixel photograph, because that call does a full decode and
    /// then a resample, where `NSImage.draw(in:)` into a small rect lets
    /// CoreGraphics scale as it decodes. After the first draw both are free.
    ///
    /// Left as it was, with the number written down, so nobody spends the
    /// afternoon again.
    func image(_ frame: ViewModel.Frame, from engine: Engine?) -> NSImage? {
        if let held = cache[frame.hash] { return held }
        // **Asked for once, then left to `askAgain`.** A frame the project has
        // a record of and no file for used to be re-read from the engine on
        // every single body evaluation — two reads, each a full directory scan
        // of the proxies folder — for as long as the app was open. Nothing is
        // written off by this: `askAgain` on the heartbeat is what notices a
        // photograph arriving, and it fills `cache`, which is checked above.
        if missing.contains(frame.hash) {
            // Keep the newest frame for the retry: the extension decides
            // whether the poster or the file's own bytes are asked for first.
            pending[frame.hash] = frame
            return nil
        }
        guard let engine else { return nil }
        // **A movie's own bytes are not a picture** — its poster stands beside
        // it under the same hash. This used to fall back when the *read*
        // failed, and the read never fails for a clip: it hands back the
        // movie, `NSImage` cannot make a picture of it, and the poster is
        // never asked for. That is the blank grey tile he found on 34A on
        // 2026-08-22. Ask the right one first, and fall back on the decode.
        let began = DispatchTime.now().uptimeNanoseconds
        let ownBytes = { engine.proxy(hash: frame.hash, ext: frame.ext) }
        let poster = { engine.proxy(hash: frame.hash, ext: "png") }
        let order = frame.movie ? [poster, ownBytes] : [ownBytes, poster]
        let attempt = order.lazy.compactMap({ $0().flatMap(NSImage.init(data:)) }).first
        note(began)
        guard let made = attempt
        else {
            // Not there *yet* — remembered so something can ask again, never
            // written off. What is remembered is the frame, not a failure: the
            // extension matters, because a clip is asked for poster-first.
            missing.insert(frame.hash)
            pending[frame.hash] = frame
            return nil
        }
        missing.remove(frame.hash)
        pending.removeValue(forKey: frame.hash)
        cache[frame.hash] = made
        return made
    }

    /// **What a photograph costs, in milliseconds on the drawing thread.**
    ///
    /// This whole path runs inside a view body: the bytes come across the
    /// boundary as base64 in JSON, get decoded, and turn into an `NSImage` —
    /// and every millisecond of it is a millisecond the window is not
    /// answering. The numbers are reported by a checking run so the cost is a
    /// measurement rather than an opinion.
    private(set) var reads = 0
    private(set) var spentMs = 0.0
    private(set) var worstMs = 0.0

    private func note(_ began: UInt64) {
        let ms = Double(DispatchTime.now().uptimeNanoseconds &- began) / 1_000_000
        reads += 1
        spentMs += ms
        worstMs = max(worstMs, ms)
    }

    /// The frames behind the missing hashes, so asking again can ask the same
    /// way the first attempt did.
    private var pending: [String: ViewModel.Frame] = [:]

    /// Ask again for everything that was not there. **True when something has
    /// arrived**, which is the screen's cue to draw again.
    ///
    /// Costs one file read per missing picture, and only for pictures that
    /// have already been drawn and come up empty — a project whose media is
    /// all present asks nothing and returns false.
    func askAgain(from engine: Engine?) -> Bool {
        guard let engine, !missing.isEmpty else { return false }
        var arrived = false
        for hash in missing {
            guard let frame = pending[hash] else { continue }
            let began = DispatchTime.now().uptimeNanoseconds
            let ownBytes = { engine.proxy(hash: frame.hash, ext: frame.ext) }
            let poster = { engine.proxy(hash: frame.hash, ext: "png") }
            let order = frame.movie ? [poster, ownBytes] : [ownBytes, poster]
            let attempt = order.lazy.compactMap({ $0().flatMap(NSImage.init(data:)) }).first
            note(began)
            guard let made = attempt
            else { continue }
            arrivals += 1
            cache[hash] = made
            arrived = true
        }
        if arrived {
            missing = missing.filter { cache[$0] == nil }
            for hash in pending.keys where cache[hash] != nil {
                pending.removeValue(forKey: hash)
            }
        }
        return arrived
    }

    /// How many pictures are still being waited for. Reported during a
    /// checking run — waiting forever and having arrived look identical on
    /// screen once the picture is up.
    var waiting: Int { missing.count }

    /// Let go of the pictures the project no longer has.
    ///
    /// Called after a pull merges another device's work. A cached picture is
    /// safe while its bytes exist — a content hash is always the same picture —
    /// and unsafe the moment another program can take those bytes away, which
    /// is what the Drive bridge does when it carries a deletion across.
    ///
    /// **Only the ones that went.** The first version emptied the lot, which
    /// was correct and far too expensive: the bridge runs every fifteen
    /// seconds, so a location with a dozen photographs on it was re-reading and
    /// re-decoding every one of them several times a minute, and *that* is what
    /// he felt as clunky. Anything still in the view stays in hand.
    /// How many pictures are in hand. Reported during a checking run, because
    /// the cost of getting this wrong is invisible: an emptied cache looks
    /// exactly like a full one until you are the hand on the trackpad.
    var held: Int { cache.count }

    func keep(only alive: Set<String>) {
        for hash in cache.keys where !alive.contains(hash) {
            cache.removeValue(forKey: hash)
        }
        // A picture the project no longer has is not one to keep waiting for.
        missing = missing.filter { alive.contains($0) }
        for hash in pending.keys where !alive.contains(hash) {
            pending.removeValue(forKey: hash)
        }
    }

    /// **One hash, forgotten on purpose** — a clip's poster changed under a
    /// hash this class had already decoded and kept, so the old picture has
    /// to go or the next redraw would show it forever. `keep(only:)` purges
    /// in bulk after a merge; this is the single-hash version, for the
    /// moment a person picks a new still for a video themselves.
    func forget(_ hash: String) {
        cache.removeValue(forKey: hash)
        missing.remove(hash)
        pending.removeValue(forKey: hash)
        arrivals += 1
    }
}

/// One of the two marks a shot wears under its number: the arrow to the shot
/// it stands in for, or the M that says others stand in for it.
///
/// A pill rather than bare text. Ref 350 — at 8.5 point in the faintest ink
/// these read as debris beside the number rather than as something the shot
/// *is*, and the gutter is 62 points wide, so there was room all along.
private struct Mark: View {
    let text: String
    let ink: Color
    let tint: Color

    var body: some View {
        Text(text)
            .mono(Brand.type(10), weight: .semibold)
            .foregroundStyle(ink)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Capsule(style: .continuous).fill(tint))
            .fixedSize()
    }
}


/// A shot's first frame, masked to the project's aspect ratio.
///
/// Masked rather than cropped: the ratio is a way of *looking* at the picture,
/// and changing it must never touch what is stored. The badge counts the others
/// so a shot with several frames does not look like a shot with one.
struct Thumbnail: View {
    let row: ViewModel.Row
    let engine: Engine?
    let ratio: CGFloat
    let dark: Bool
    /// The column's width, taken in so that changing it re-draws this view.
    let width: CGFloat
    /// Whether clips play on their own: when they wait, the clip's own play
    /// button says it is a clip, and the corner mark would say it twice.
    @ObservedObject private var clips = ClipPlay.shared

    /// The shot's Print Frame, for its key picture, when the bake is current.
    private func board(_ hash: String) -> PrintFrameView.Baked? {
        guard let pf = row.printFrame, !pf.stale, let baked = pf.baked,
              row.frame?.hash == hash else { return nil }
        return baked
    }


    var body: some View {
        // The 18 is the horizontal padding applied around this view at the
        // call site; the picture is what is left of the column after it.
        let column = width - 18
        // **A shot with several frames shows them side by side** — Ref 78, his
        // answer: *"side by side if it shows a series of storyboards that
        // represent one shot."* Which is what several frames on one shot
        // usually are: a move drawn in three panels, not three candidate
        // frames. One thumbnail and a number could not tell him which.
        //
        // The well keeps the height it always had, so a film of ordinary shots
        // does not suddenly have taller rows because two of them are boarded.
        // The panels share the width and keep their own shape inside it.
        //
        // Four across is the limit at which a panel is still a picture rather
        // than a stamp; past that the rest are counted, and the frames window
        // is where you go to see them all.
        let strip = Array(row.stills.filter {
            Frames.something($0.hash, $0.filename, engine, kind: $0.kind)
        }.prefix(4))
        let over = row.frames - strip.count

        // **An empty well is a slot, and a slot is one size.**
        //
        // His instruction, 2026-09-04: *"for shots that dont have images, in
        // table view they should not expand larger than the largest text. the
        // empty image field should not be allowed to grow in size."*
        //
        // The well took the whole column and stood as tall as the shape a
        // picture would have been, so dragging the image column out to 320
        // points made every unboarded row 126 points tall to hold nothing, and
        // a scene of unboarded shots became a column of grey slabs. It is
        // pinned to the size it has in a column of standard width now, and it
        // still *shrinks* with a narrow column, because a well wider than its
        // column would draw over the neighbour.
        //
        // **The whole well, not only its fill.** The border, the icon and the
        // box are one thing — shrinking the fill alone left an outline the full
        // width of the column with a small grey rectangle sitting inside it.
        //
        // **Only where there is no picture at all.** A shot whose frame has a
        // file missing keeps the full shape: it is supposed to have a picture,
        // the gap mark is how you find it, and shrinking it would hide the
        // fault. Ref 224's distinction, and this is the second thing that turns
        // on it.
        let empty = row.frame == nil && strip.isEmpty
        let width = column
        // **Full width, pinned height.** His correction, 2026-09-04, with a
        // picture of one narrow well beside a row of full-width frames: *"have
        // the empty picture frame cell take up the full width (even though i
        // know it doesnt match the aspect ratio) so it doesnt look weirdly
        // truncated next to the shots with images."*
        //
        // So the well is as wide as every other cell in the column and lines up
        // with them, and it is the *height* that stops growing — which was the
        // whole of the first complaint. Pulling the image column out to 320
        // points used to make an unboarded row 126 points tall to hold nothing.
        // The well keeps the height it has at a standard column width however
        // wide the column is dragged, and it is knowingly not the film's aspect
        // ratio: an empty well is a place for a picture, not a picture.
        let wellHeight = min(column, Columns.standard("image") - 18) / ratio
        ZStack(alignment: .bottomTrailing) {
            if strip.count > 1 {
                let gap: CGFloat = 2
                let each = (width - gap * CGFloat(strip.count - 1)) / CGFloat(strip.count)
                HStack(spacing: gap) {
                    ForEach(strip, id: \.ref) { still in
                        Frames.view(still.hash, still.filename, engine: engine,
                                    trimStart: still.trimStart, trimEnd: still.trimEnd,
                                    kind: still.kind, framing: still.framing, arrows: still.marks,
                                    printFrame: board(still.hash))
                            .frame(width: each, height: each / ratio)
                            .clipped()
                    }
                }
                // **The box is as tall as the panels, and no taller.** It
                // was `width / ratio` — the shape one picture takes across the
                // whole cell — while the panels inside it are only
                // `each / ratio`, so two frames drew a band of air above them
                // and another below. He photographed both bands and crossed
                // them out: *"there should never be extra headroom on top of
                // the images. The images themselves need to conform to the
                // aspect ratio AND THEN be placed next to each other."*
                .frame(width: width, height: each / ratio)
            } else if let frame = row.frame,
               Frames.something(frame.hash, frame.filename, engine) {
                // A clip plays here and a gif goes round — his ask, and the
                // table is where he noticed it missing.
                Frames.view(frame.hash, frame.filename, engine: engine,
                            trimStart: frame.trimStart, trimEnd: frame.trimEnd,
                            framing: frame.framing, arrows: frame.marks,
                            printFrame: board(frame.hash))
                    .frame(width: width, height: width / ratio)
                    .clipped()
            } else {
                // **A shot with no picture does not make its row taller.**
                //
                // His instruction, 2026-09-04: *"for shots that dont have
                // images, in table view they should not expand larger than the
                // largest text. the empty image field should not be allowed to
                // grow in size."* It was `height: width / ratio` — the shape a
                // real picture would take — so an empty well stood a row up to
                // 48 points to hold nothing, and a scene of unboarded shots was
                // a column of grey rectangles with one line of words beside
                // each.
                //
                // **Only where there is no frame at all.** A shot whose frame
                // has a file missing keeps its full height: it is *supposed* to
                // have a picture, the gap mark is how you find it, and shrinking
                // it would hide the fault. That is Ref 224's distinction, and
                // this is the second thing that turns on it.
                //
                // No height asked for, so the row is sized by its words; capped
                // at what a picture would have taken, so a four-line description
                // does not draw a tall grey slab beside itself.
                // **An empty well is a slot, and a slot is one size.**
                //
                // It never grows past the size it has in a column of standard
                // width, however wide the column is dragged. That is the whole
                // of his complaint — the well was `width / ratio`, so pulling
                // the image column out to 320 points made every unboarded row
                // 126 points tall to hold nothing at all, and a scene of
                // unboarded shots became a column of grey slabs. It still
                // *shrinks* with a narrow column, because a well wider than its
                // column would draw over the neighbour.
                //
                // **Only where there is no frame at all.** A shot whose frame
                // has a file missing keeps the full picture shape: it is
                // supposed to have a picture, the gap mark is how you find it,
                // and shrinking it would hide the fault. Ref 224's distinction,
                // and this is the second thing that turns on it.
                Rectangle()
                    .fill(Brand.frameEmpty(dark))
                    .frame(width: width, height: empty ? wellHeight : width / ratio)
                    .overlay {
                        // A shot with no frame at all and a shot whose frame
                        // has no file behind it are two different things, and
                        // used to draw as one grey square — Ref 224.
                        if let frame = row.frame {
                            Frames.gap(frame.hash, dark: dark, small: true)
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 11, weight: .light))
                                .foregroundStyle(Brand.ink4(dark))
                        }
                    }
            }
            if strip.count > 1 ? over > 0 : row.frames > 1 {
                Text(strip.count > 1 ? "+\(over)" : "\(row.frames)")
                    .mono(Brand.type(8), weight: .semibold)
                    .foregroundStyle(Brand.onImage)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .padding(4)
            }
        }
        // **The play mark rides on the picture, not on the cell.** It used to
        // be a child of the stack above, pushed into the corner with
        // `maxWidth`/`maxHeight: .infinity` — and the table hands every cell
        // the row's full height, so on any row taller than its picture the
        // mark swelled the box to the whole row, the border drew round the
        // swollen box, and the clip (bottom-aligned in that stack) sank to the
        // floor with a well of nothing above it. His photograph, 2026-09-19:
        // *"the video should sit at the top of the row, not bottom and i dont
        // want to see the extended media frame."* An overlay is sized to what
        // it lies on, so the mark can only ever sit on the clip's own corner.
        .overlay(alignment: .topLeading) {
            if strip.count <= 1, let frame = row.frame, frame.movie,
               clips.onTheirOwn || Ingest.isGif(frame.ext, kind: frame.kind) {
                Image(systemName: "play.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Brand.onImage)
                    .padding(4)
                    .background(Circle().fill(Color.black.opacity(0.55)))
                    .padding(4)
            }
        }
        .overlay {
            // **Square.** His rule, and the one I keep having to be reminded
            // of: a photograph is content, and content keeps its own
            // rectangle. Only what *floats* turns a corner. The storyboard's
            // frames went square weeks ago on exactly this note; the table's
            // thumbnails were missed.
            Rectangle().strokeBorder(Brand.frameLine(dark), lineWidth: 1)
        }
        .clipShape(Rectangle())
    }
}


/// The bar itself, in its own view so that it — and only it — redraws while
/// the wheel is turning. See `ScrollModel`.
private struct TableScrollBar: View {
    @ObservedObject var model: ScrollModel
    let dark: Bool
    let carry: (CGFloat) -> Void
    @State private var dragging = false

    var body: some View {
        // Nothing to scroll, nothing to draw. A bar that fills its own track
        // is furniture.
        if model.content > model.viewport + 1, model.viewport > 0 {
            let visible = max(model.viewport / model.content, 0.06)
            let travel = max(model.content - model.viewport, 1)
            let at = min(max(model.offset / travel, 0), 1)
            GeometryReader { geo in
                let track = geo.size.height - 16
                let thumb = max(track * visible, 28)
                Capsule()
                    .fill(Brand.ink3(dark).opacity(dragging ? 0.55 : 0.26))
                    .frame(width: 7, height: thumb)
                    .offset(y: 8 + (track - thumb) * at)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                dragging = true
                                let want = (drag.location.y - 8 - thumb / 2)
                                    / max(track - thumb, 1)
                                carry(min(max(want, 0), 1))
                            }
                            .onEnded { _ in dragging = false }
                    )
                    .animation(.easeOut(duration: 0.1), value: dragging)
            }
            .frame(width: 11)
            .padding(.trailing, 4)
        }
    }
}

/// How wide the table has to draw in. Reported once per layout pass, the same
/// way the row and header frames are, so the columns can share out whatever the
/// window has spare without anything writing state mid-update.
struct TableWidth: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > value.width { value = next }
    }
}


/// **A section's color as a light wash** over every band and row of its
/// run, so a fast scroll through three scripts says which one this is
/// before a word is read. Same strength everywhere (kit `sectionWash`).
/// Nothing when there is no section.
private struct SectionWash: ViewModifier {
    let ink: Color?
    let dark: Bool
    /// Over the view rather than behind it, for a band that has its own opaque fill.
    var over = false
    func body(content: Self.Content) -> some View {
        let wash = ink.map { Rectangle().fill($0.opacity(Kit.sectionWash(dark: dark))).allowsHitTesting(false) }
        if over { content.overlay { wash } } else { content.background { wash } }
    }
}

extension View {
    func sectionWash(_ ink: Color?, dark: Bool, over: Bool = false) -> some View { modifier(SectionWash(ink: ink, dark: dark, over: over)) }
}
