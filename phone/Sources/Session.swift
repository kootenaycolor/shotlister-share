import SwiftUI

/// One project, open.
///
/// Holds the three things that must live and die together: permission to be in
/// the folder, the engine reading it, and the locations notebook beside it. When
/// this goes away all three are released, which is the only reliable way to not
/// leak a security-scoped folder.
///
/// It also holds **the** view. Narrowing the list is a question asked of the
/// engine, not a rule the screen keeps for itself — so a search typed on the
/// scenes screen and the shots underneath it can never disagree about what is
/// hidden.
@MainActor
final class Session: ObservableObject {
    let entry: Projects.Known
    let folder: OpenFolder
    let store: LocationStore
    let engine: Engine?

    @Published private(set) var view: Engine.View?
    /// **Why the project looks empty, when it does.**
    ///
    /// A view that will not decode used to leave `view` nil, and a nil view
    /// draws exactly like a project with nothing in it — which is how a single
    /// missing field in one photograph emptied the entire app and looked like
    /// lost work. If it cannot be read, it says so.
    @Published private(set) var unreadable: String?
    /// Whether the trouble was opening it at all, rather than reading what came
    /// back. Two different sentences, and he can act on only one of them.
    @Published private(set) var wouldNotOpen = false


    /// **The schedule**, when a screen is showing one.
    ///
    /// Its own answer from the engine rather than part of the view, so it is
    /// asked for only while the Schedule tab is on screen — the board walks
    /// every placement in the film, and the shot list has no use for it.
    @Published private(set) var schedule = Engine.Schedule()
    /// Whether anything is looking at the schedule. Set by the screen itself,
    /// so an edit made anywhere refreshes it without every other screen paying
    /// for the walk.
    var watchingSchedule = false {
        didSet { if watchingSchedule, !oldValue { readSchedule() } }
    }

    /// What the search field holds. Sent to the engine as he types.
    @Published var search = "" { didSet { if search != oldValue { applyFilter() } } }
    @Published var hideStruck = false { didSet { if hideStruck != oldValue { applyFilter() } } }
    /// **The order the scenes are read in** — the Mac's *Read in order of*.
    /// Looking only: nothing is written, no number moves. Script order is
    /// the film's own.
    @Published var sceneOrder: SceneOrder = .script

    enum SceneOrder: String, CaseIterable, Identifiable {
        case script, day, location
        var id: String { rawValue }
        var label: String {
            switch self {
            case .script: return "Script Order"
            case .day: return "Shoot Day"
            case .location: return "Location"
            }
        }
    }

    /// Watching the folder for what another device left.
    ///
    /// **The phone was not merging at all while a project was open.** It read
    /// its own engine and nothing else, so a shot changed on the Mac — or a
    /// photograph the bridge brought in from Drive — appeared only if he closed
    /// the project and opened it again. The Mac has watched its folder for a
    /// while; this is the same thing.
    private var watcher: DispatchSourceFileSystemObject?
    private var watched: Int32 = -1
    private var pullSoon: DispatchWorkItem?
    private var heartbeat: Timer?
    /// The slow beat that keeps the *list* level with the relay. Separate from
    /// `heartbeat`, which only ever reads the folder.
    private var relayBeat: Timer?
    /// **The open line**, so a change arrives rather than being waited for.
    /// Sits on top of `relayBeat`, which stays exactly as it was: push is the
    /// fast path, the poll is the one that cannot fail.
    private lazy var watch = Watch { [weak self] in self?.syncListQuietly() }

    init(entry: Projects.Known, folder: OpenFolder) {
        self.entry = entry
        self.folder = folder
        self.store = LocationStore(project: folder.url)
        // Opening the engine is what makes this a *project* rather than a
        // folder. It is allowed to fail without taking the scout down with it:
        // photographs and scans are files, and they are the reason he is
        // standing in the room.
        //
        // **But it has to say so.** This was `try?` — the engine's own
        // explanation was thrown away on the spot, every screen drew the
        // nothing it had, and a project that would not open was indistinguishable
        // from a project with nothing in it.
        var opened: Engine?
        var refused: String?
        do { opened = try Engine(path: folder.url.path) }
        catch { refused = error.localizedDescription }
        self.engine = opened
        self.wouldNotOpen = refused != nil
        self.unreadable = refused
        refresh()
        // **The project's card over the film** (stage 5 step 4), from the
        // kept copy at once and then the server.
        PhoneCards.shared.lay(on: self)
        saveDailyVersionIfDue()
        let package = folder.url
        Task { await Cloud.bringDownQuietly(package) }
        watchForOtherDevices()
        keepListening()
        prepareStrips()
    }

    /// **The clips' four-moment strips, made now rather than at export** —
    /// Ref 1046. Called on opening and after anything that changes what a
    /// clip's strip should look like: a clip attached, a trim moved. Off the
    /// main thread, and nothing waits on it; the export checks the same list
    /// itself and finds it done.
    func prepareStrips() {
        guard let engine else { return }
        let folder = folder.url
        let ratio = self.ratio
        Task { @MainActor in
            await Filmstrip.ensure(engine: engine, folder: folder, ratio: ratio)
        }
    }

    deinit {
        watcher?.cancel()
        heartbeat?.invalidate()
        // **`relayBeat` too.** A scheduled timer is held by the run loop, not
        // by this object — `[weak self]` stops it keeping the session alive but
        // does nothing to stop it firing. Left out, switching projects all day
        // leaves a beat behind per film, each one still asking the relay.
        relayBeat?.invalidate()
        // **The line closes itself.** `Watch` has its own `deinit` that cancels
        // the socket, and this one cannot reach it anyway: `deinit` is not on
        // the main actor and the property is. Letting ARC do it is both the
        // correct answer and the only legal one.
        folder.release()
    }

    // ---- what another device left ------------------------------------------

    private func watchForOtherDevices() {
        let changes = folder.url.appendingPathComponent("changes")
        let fd = Darwin.open(changes.path, O_EVTONLY)
        guard fd >= 0 else { return }
        watched = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .attrib, .link], queue: .main)
        source.setEventHandler { [weak self] in self?.schedulePull() }
        source.setCancelHandler { [weak self] in
            guard let self, self.watched >= 0 else { return }
            close(self.watched)
            self.watched = -1
        }
        source.resume()
        watcher = source
    }

    /// The folder watcher only fires on `changes/`. A **photograph** arriving
    /// from iCloud lands in `media/proxies` and makes no noise there at all, so
    /// without this the picture is on the disk and the screen still shows the
    /// grey square. The Mac has had a heartbeat like this for a while.
    ///
    /// It also asks iCloud for anything still standing as a stub, which is the
    /// only thing that makes those files arrive in the first place.
    private func keepListening() {
        heartbeat = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.askTheCloud()
                self.pullNow()
            }
        }
        // **A network beat beside the disk one, and much slower.** Five
        // minutes: the list is a megabyte and a check that finds nothing is two
        // small requests. Confusing the two would put his relay under a request
        // every three seconds from a phone in his pocket.
        relayBeat = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.syncListQuietly()
        }
        watchTheRelay(waking: false)
    }

    /// Beats since the film opened, and whether the last walk found anything
    /// still coming down.
    private var beats = 0
    private var cloudBusy = true

    /// **Every beat while something is coming down, every tenth once nothing
    /// is.** A film whose files are all here has nothing to ask iCloud for;
    /// a new file from the Mac is still found within half a minute, and a
    /// picture a screen is waiting on is asked for by `Frames` straight away.
    private func askTheCloud() {
        beats += 1
        guard cloudBusy || beats % 10 == 0 else { return }
        let package = folder.url
        Task { [weak self] in
            guard let coming = await Cloud.bringDownQuietly(package) else { return }
            self?.cloudBusy = !coming.isEmpty
        }
    }

    /// Open — or reopen — the line to this film.
    func watchTheRelay(waking: Bool) {
        guard let base = Relay.address(for: folder.url),
              let token = Relay.token,
              let project = Relay.projectId(at: folder.url)
        else { return }
        if waking {
            // A socket that died in a pocket rarely says so, so it is thrown
            // away and remade rather than trusted.
            watch.wakeUp(base: base, project: project, token: token)
        } else {
            watch.start(base: base, project: project, token: token)
        }
    }

    /// Debounced: a file arriving from iCloud is several writes, not one.
    private func schedulePull() {
        pullSoon?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.pullNow() }
        pullSoon = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Takes in whatever the other device left. Silent when there is nothing,
    /// which is the ordinary case.
    func pullNow() {
        guard let engine else { return }
        struct Reply: Decodable { var merged: Int }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: engine.raw("pull")),
              reply.merged > 0 else { return }
        reload("view")
    }

    // ---- his own relay ------------------------------------------------------

    /// Whether the sync is running right now.
    @Published private(set) var syncing = false
    /// **The relay has let this film go** — archived or deleted on another
    /// device — and this copy follows: the screen closes the film and the
    /// Projects list does the same here. Nothing is sent once this is set.
    /// A relay that kept no note reads as archived, which loses nothing.
    @Published var relayFate: RelayCarrier.Fate?
    /// What the last run did. `Up to date` when it did nothing.
    @Published var syncSaid = ""
    /// When it last ran, so anything showing it redraws when it changes. The
    /// truth lives in `SyncHistory`; this is what SwiftUI watches.
    @Published var syncedAt: Date? = SyncHistory.lastRan
    /// Why the last run could not happen. A sentence, because it is a warning
    /// and he can act on it.
    @Published var syncProblem: String?

    /// Whether this phone can sync this film at all — an address and a password.
    var canSync: Bool { Relay.ready(for: folder.url) }

    /// **Push now and pull now, in one press.** His complaint about iCloud was
    /// that there is nothing to press when it lags behind; this is the thing to
    /// press, and it is the same button the Mac has.
    ///
    /// **The order is load-bearing: logs → merge → pictures.** A film is about a
    /// megabyte of list and a hundred of photographs. Merging in the middle is
    /// the difference between today's shots appearing straight away and waiting
    /// for a whole film's worth of pictures on a location's connection.
    func syncNow() {
        guard let engine, !syncing else { return }
        guard canSync else {
            syncProblem = Relay.Trouble.notSetUp.errorDescription
            return
        }
        let path = folder.url
        syncing = true
        syncProblem = nil

        Task { @MainActor in
            defer { syncing = false }
            // **The list and the pictures are caught apart**, for the reason
            // written out on the Mac's `ShellState.syncListQuietly`: `syncLogs`
            // sends everything it can and *then* raises a refusal, and that
            // throw used to end the run before a single picture was offered. So
            // one log the relay will not take could hold back every photograph
            // behind it, on the button as well as on the beat.
            var logs = Relay.Report()
            var merged = 0
            var trouble: String?
            do {
                logs = try await Relay.syncLogs(engine: engine, path: path)
                // The merge that has always run, so the screen refreshes the way
                // it already did and nothing here is a second copy of it.
                if logs.receivedLogs > 0 {
                    struct Reply: Decodable { var merged: Int }
                    if let reply = try? JSONDecoder().decode(Reply.self, from: engine.raw("pull")) {
                        merged = reply.merged
                    }
                    if merged > 0 { reload("view") }
                }
            } catch Relay.Trouble.gone(let fate) {
                // Nothing else is tried: the pictures would be refused the
                // same way, and the film is about to close.
                SyncHistory.failed(Relay.Trouble.gone(fate).errorDescription ?? "", byHand: true)
                relayFate = fate ?? .archived
                return
            } catch {
                trouble = error.localizedDescription
            }

            var media = Relay.Report()
            do {
                media = try await Relay.syncMedia(engine: engine, path: path)
                // A picture arriving changes nothing the engine knows, so nothing
                // is re-merged — but the screen is still drawing grey where those
                // files now are.
                if media.receivedMedia > 0 { reload("view") }
            } catch {
                if trouble == nil { trouble = error.localizedDescription }
            }

            var said = Relay.Report(
                sentLogs: logs.sentLogs, receivedLogs: logs.receivedLogs,
                sentMedia: media.sentMedia, receivedMedia: media.receivedMedia
            )
            said.merged = merged
            syncSaid = said.said
            // **What moved is recorded even when something else refused to.**
            if !said.isEmpty {
                SyncHistory.finished(said: said.said, moved: true, byHand: true)
                syncedAt = SyncHistory.lastRan
            }
            if let trouble {
                syncProblem = trouble
                SyncHistory.failed(trouble, byHand: true)
            } else if said.isEmpty {
                SyncHistory.finished(said: said.said, moved: false, byHand: true)
                syncedAt = SyncHistory.lastRan
            }
        }
    }

    /// **Everything travels on its own — the list and the pictures both.**
    ///
    /// His ruling, 2026-09-08: *"Let's delete this rule. That should not be the
    /// case. It should just automatically sync. I don't have time for that."*
    ///
    /// **That reverses his decision of 2026-08-31**, which held that the list
    /// travelled by itself and the photographs waited for a tap — and the phone
    /// was the reason it mattered, being the device on the worse connection.
    /// The cost is real and he has weighed it: a clip that never left is worse
    /// than a clip that left over cellular. **Do not put the split back** —
    /// see the decision in Notion. If the data ever needs answering, answer it
    /// with something he does not have to tap.
    ///
    /// **This does what `syncNow` does; only the reporting differs.** The Mac's
    /// twin is `ShellState.syncListQuietly`, and the two must stay the same
    /// shape — a phone that quietly kept its clips while the Mac sent its own
    /// would be the same surprise in a new place.
    ///
    /// **Silent both ways.** Nothing is said when it works, because changes
    /// arriving is the system working rather than news. Nothing is said when it
    /// fails either — a relay that cannot be reached on set is the ordinary
    /// condition of being on set, and a warning in the ⋯ menu every five
    /// minutes is an app crying wolf. *Sync now* still reports both, because he
    /// tapped it and is owed an answer.
    func syncListQuietly() {
        guard let engine, !syncing, canSync, relayFate == nil else { return }
        let path = folder.url
        syncing = true
        Task { @MainActor in
            defer { syncing = false }
            // **The list and the pictures are caught apart** — the same reason
            // as in `syncNow` just above: a log the relay refuses must not hold
            // back every photograph queued behind it.
            var logs = Relay.Report()
            var merged = 0
            var trouble: String?
            do {
                logs = try await Relay.syncLogs(engine: engine, path: path)
                if logs.receivedLogs > 0 {
                    struct Reply: Decodable { var merged: Int }
                    if let reply = try? JSONDecoder().decode(Reply.self, from: engine.raw("pull")) {
                        merged = reply.merged
                    }
                }
            } catch Relay.Trouble.gone(let fate) {
                // Acted on, even on the quiet beat: the film closes and the
                // copy here follows what was done elsewhere.
                relayFate = fate ?? .archived
                return
            } catch {
                trouble = error.localizedDescription
            }

            // **Send the pictures and the clips.** The half that used to wait
            // for a tap.
            var media = Relay.Report()
            do {
                media = try await Relay.syncMedia(engine: engine, path: path)
                // A picture arriving changes nothing the engine knows, so
                // nothing is re-merged — but the screen is still drawing grey
                // where those files now are.
                if media.receivedMedia > 0 { reload("view") }
            } catch {
                if trouble == nil { trouble = error.localizedDescription }
            }

            var said = Relay.Report(
                sentLogs: logs.sentLogs, receivedLogs: logs.receivedLogs,
                sentMedia: media.sentMedia, receivedMedia: media.receivedMedia
            )
            said.merged = merged
            if let trouble {
                // Still silent on screen — a relay you cannot reach on set is
                // the ordinary condition of being on set. But it goes in the
                // history, which is the one place it is worth finding later.
                SyncHistory.failed(trouble, byHand: false)
            } else {
                // **The time is recorded even when nothing moved.** That is the
                // honest answer to "am I up to date"; the history stays quiet.
                SyncHistory.finished(said: said.said, moved: !said.isEmpty, byHand: false)
                syncedAt = SyncHistory.lastRan
            }
            if merged > 0 {
                reload("view")
                // The menu's own line, so the last thing that happened is
                // readable without tapping anything. Not a warning.
                syncSaid = "\(merged) in"
            }
        }
    }

    /// Said the way it would have to be said to be acted on: which field, and
    /// where it was expected.
    static func explain(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map(\.stringValue).filter { !$0.isEmpty }.joined(separator: " → ")
        }
        switch error {
        case .keyNotFound(let key, let context):
            return "Couldn't read the response. Update Studio."
        case .typeMismatch(_, let context):
            return "Couldn't read the response. Update Studio."
        case .valueNotFound(_, let context):
            return "Couldn't read the response. Update Studio."
        default:
            return "Couldn't read the response. Update Studio."
        }
    }

    // ---- what is on screen ------------------------------------------------

    var scenes: [Engine.Scene] { view?.scenes.filter { showArchived || !$0.archived } ?? [] }
    /// **Show archived scenes** (the Mac's): they come back onto the list,
    /// marked, to unarchive or delete. Off by default.
    @Published var showArchived = false
    var archivedCount: Int { view?.scenes.filter(\.archived).count ?? 0 }
    /// **Shots copied to paste after another** (the Mac's Copy / Paste):
    /// their placements, held for this project.
    @Published var copiedShots: [String] = []
    var units: [Engine.Unit] { view?.units ?? [] }
    /// **The project's Camera Spec Sheet**, read off the portal when asked.
    lazy var specSheet = PhoneSpecSheet(session: self)
    var sequences: [Engine.Sequence] { view?.sequences ?? [] }
    var days: [Engine.Day] { view?.days ?? [] }
    /// **The days a person picks from**: one whose shots are all in archived
    /// scenes is shot out and put away, so it is left out, unless it is where
    /// the shot in hand already is.
    func pickableDays(keeping held: String? = nil) -> [Engine.Day] {
        days.filter { !$0.wrapped || $0.id == held }
    }
    /// **Shooting Order as drawn**: a shot in an archived scene is set aside
    /// here as everywhere else, and a day left with no shot goes with them.
    var orderGroups: [Engine.Group] {
        let archived = Set((view?.scenes ?? []).filter(\.archived).map(\.id))
        return groups.compactMap { group in
            let rows = group.rows.filter { !archived.contains($0.sceneId ?? "") }
            if rows.isEmpty && !group.rows.isEmpty { return nil }
            var kept = group
            kept.rows = rows
            kept.count = rows.count
            return kept
        }
    }
    var locations: [Engine.Location] { view?.locations ?? [] }
    var columns: [Engine.Column] { view?.columns ?? [] }
    /// **The scripts, as text** — on a commercial. Empty on a film.
    var scripts: [Engine.AVScript] { view?.scripts ?? [] }

    /// Whether this is a commercial — no screenplay; scenes are titled things
    /// to get; a sequence is a Section; the script is text quoted by shots.
    var isCommercial: Bool { view?.project.isCommercial ?? false }
    var sequenceWord: String { view?.project.sequenceWord ?? "Sequence" }
    /// A film a newer Shotlister wrote, which this build may read and not
    /// touch. The engine refuses every write anyway; this keeps the buttons
    /// honest.
    var isReadOnly: Bool { view?.project.readOnly ?? false }

    /// The sequence a scene is in, if it is in one. **Off the scene itself**
    /// — it used to be read off the scene's first shot, which is nothing for
    /// a scene with no shots yet, and a commercial's section head has to be
    /// drawn whether or not a scene has been given its shots.
    func sequence(ofScene id: String) -> Engine.Sequence? {
        guard let said = scene(id)?.sequence, !said.isEmpty else { return nil }
        return sequences.first { $0.id == said }
    }

    /// The section a scene sits under in a commercial's list, or nothing on
    /// a film or a scene in no section. The list draws a head where this
    /// changes from one scene to the next — the Mac's `sectionOf`.
    func section(of scene: Engine.Scene) -> Engine.Sequence? {
        guard isCommercial, let id = scene.sequence, !id.isEmpty else { return nil }
        return sequences.first { $0.id == id }
    }

    /// **A section is a label on a run of scenes, not a place every scene
    /// has to live** — his correction, 2026-09-14. A head is drawn where a
    /// section *starts*: this scene has one and the scene before did not, or
    /// had another. A scene in no section is simply a scene.
    func sectionStarts(at scene: Engine.Scene, in list: [Engine.Scene]) -> Engine.Sequence? {
        // A section is a run in script order; read any other way it is not.
        guard sceneOrder == .script, let mine = section(of: scene),
              let at = list.firstIndex(where: { $0.id == scene.id }) else { return nil }
        if at == 0 { return mine }
        return (list[at - 1].sequence ?? "") == mine.id ? nil : mine
    }

    /// The colour a section wears, as a colour.
    func tint(of section: Engine.Sequence?) -> Color? {
        guard let section, !section.colour.isEmpty else { return nil }
        return Engine.Palette.tint(section.colour)
    }

    func location(_ id: String) -> Engine.Location? { locations.first { $0.id == id } }

    /// The places that stand on their own — a house, a street, a stage.
    ///
    /// **Rooms live inside them** since 2026-08-22. *Call Her Back* is one house
    /// with one address, and a kitchen, a bedroom and a garage inside it, each
    /// scanned and photographed separately.
    /// A room whose house is not here counts as one too. The engine lets a
    /// house's rooms out rather than deleting them, so this should not happen —
    /// but a room hidden under a parent that is not in the list is a room he
    /// cannot reach at all, and showing it at the top is the harmless failure.
    var houses: [Engine.Location] {
        let here = Set(locations.map(\.id))
        return locations.filter { !$0.isArea || !here.contains($0.parent ?? "") }
    }

    /// The rooms inside one place, in the order the engine keeps them.
    func rooms(of id: String) -> [Engine.Location] {
        locations.filter { $0.parent == id }
    }
    var groups: [Engine.Group] { view?.groups ?? [] }
    var ratio: Double { view?.project.ratio ?? 1.85 }
    var narrowed: Bool { view?.filter.narrowed ?? false }
    /// **The scenes the list draws**: every scene, less the ones the filter
    /// emptied. A filter that left every scene on screen as "No shots" read
    /// as a filter that did nothing.
    var shownScenes: [Engine.Scene] {
        guard narrowed, let hidden = view?.filter.hiddenSceneIds, !hidden.isEmpty else { return inSceneOrder(scenes) }
        let gone = Set(hidden)
        return inSceneOrder(scenes.filter { !gone.contains($0.id) })
    }

    /// The scenes in the order being read, the Mac's `inViewOrder`. Stable:
    /// ties keep script order, and a scene with nothing in the field goes
    /// last, not first — an unset day is not day zero.
    func inSceneOrder(_ list: [Engine.Scene]) -> [Engine.Scene] {
        guard sceneOrder != .script else { return list }
        let key: (Engine.Scene) -> String = { scene in
            switch self.sceneOrder {
            case .script: return ""
            case .day: return scene.day
            case .location: return scene.shootingLocation.isEmpty ? scene.location : scene.shootingLocation
            }
        }
        return list.enumerated().sorted { left, right in
            let a = key(left.element), b = key(right.element)
            if a.isEmpty != b.isEmpty { return b.isEmpty }
            if a != b { return a.localizedStandardCompare(b) == .orderedAscending }
            return left.offset < right.offset
        }.map(\.element)
    }
    /// Read in a column's order, or in Shooting Order.
    var sorted: Bool { shootingOrder || !(view?.filter.sortColumn ?? "").isEmpty }
    var shotCount: Int { groups.reduce(0) { $0 + $1.rows.count } }

    /// The rows of one scene, whatever the current grouping is. Asking the
    /// engine for the scene's own group rather than sifting every row means the
    /// filter applies here exactly as it does everywhere else.
    func rows(inScene id: String) -> [Engine.Row] {
        groups.first { $0.key == id }?.rows
            ?? groups.flatMap(\.rows).filter { $0.sceneId == id }
    }

    func scene(_ id: String) -> Engine.Scene? { scenes.first { $0.id == id } }

    // ---- asking the engine -------------------------------------------------

    func refresh() {
        reload("view")
    }

    // ---- the shoot picker (stage 5 step 4, piece D) ------------------------

    var shoots: [Engine.Shoot] { view?.shoots ?? [] }
    var manyShoots: Bool { shoots.count >= 2 }
    var shootOn: Engine.Shoot? {
        let on = view?.shootOn ?? ""
        return on.isEmpty ? nil : shoots.first { $0.id == on }
    }
    private var shootKey: String { "shootPick." + (Relay.projectId(at: folder.url) ?? entry.name) }

    /// After a card is laid on: the remembered pick, else the next shoot (or
    /// today's), else the last — the console's rule. Nothing with one shoot.
    func applyShootPick() {
        guard manyShoots else {
            if !(view?.shootOn ?? "").isEmpty { reload("facet", "shoot", "") }
            return
        }
        let lead = shoots.first { ["next", "today"].contains($0.state.lowercased()) } ?? shoots.last
        var want = lead?.id ?? ""
        if let kept = UserDefaults.standard.string(forKey: shootKey) {
            want = kept == "all" ? "" : (shoots.contains { $0.id == kept } ? kept : want)
        }
        #if targetEnvironment(simulator)
        if let asked = UserDefaults.standard.string(forKey: "StartShoot") {
            if asked == "all" { want = "" } else if let n = Int(asked), n >= 1, n <= shoots.count { want = shoots[n - 1].id }
        }
        #endif
        if want != (view?.shootOn ?? "") { reload("facet", "shoot", want) }
    }

    /// Pick a shoot, or All Shoots (nil). Kept for this film on this phone.
    func pickShoot(_ id: String?) {
        reload("facet", "shoot", id ?? "")
        UserDefaults.standard.set(id ?? "all", forKey: shootKey)
    }

    func stepShoot(_ by: Int) {
        let order: [String?] = [nil] + shoots.map(\.id)
        let at = order.firstIndex { $0 == shootOn?.id } ?? 0
        let next = max(0, min(order.count - 1, at + by))
        if next != at { pickShoot(order[next]) }
    }

    private func applyFilter() {
        reload("filter", hideStruck ? "1" : "0", search)
    }

    /// Reading order only. Nothing is written and no shot letter moves — story
    /// order and the order you happen to be reading in are different facts.
    func sort(by column: String, descending: Bool) {
        reload("sort", column, descending ? "desc" : "asc")
    }

    func clearSort() { reload("sort", "") }

    /// **Sorted by Shooting Order** (2026-10-06): the list by day, each
    /// day's shots in the order they are shot, the unscheduled last.
    var shootingOrder: Bool { view?.groupBy == "day" }
    func sortByShootingOrder() { reload("sort", "shootingorder") }

    /// A shot into the shooting order, just in front of `before` on `day`,
    /// or at that day's end; no day takes it off every day. Its number and
    /// letter stay its own.
    func shoot(placement: String, day: String?) {
        reload("shootbefore", placement, day ?? "", "")
        if watchingSchedule { readSchedule() }
    }

    func shoot(_ row: Engine.Row, day: String?, before: Engine.Row?) {
        reload("shootbefore", row.placement, day ?? "", before?.placement ?? "")
    }

    /// Narrow by one field's value — every lens marked 27mm, say. An empty
    /// value clears that one field; `all` clears every kind of narrowing.
    func facet(_ field: String, is value: String) {
        facets[field] = value.isEmpty ? nil : value
        reload("facet", field, value)
    }

    /// Every shot, as last seen with no filter on.
    private(set) var everyRow: [Engine.Row] = []

    /// What each field is narrowed to. The engine keeps the same; this is
    /// what the menu ticks, since the view does not send it back.
    @Published private(set) var facets: [String: String] = [:]

    func clearNarrowing() {
        search = ""
        hideStruck = false
        facets = [:]
        reload("facet", "all", "")
    }

    /// **The engine says when it has something to write down.** Ref 194.
    ///
    /// This used to be a hand-kept list of command names — `set`, `strike`,
    /// `paste`, and twenty more — and everything on it had to reach the disk,
    /// because the engine holds a change in memory until it is told to save.
    /// The list worked, and it was a trap: **add an editing command and forget
    /// to add it here, and the edits-die-with-the-process bug comes straight
    /// back with every check still green.** Nothing could catch that, because
    /// the list was the only statement of what counts as an edit.
    ///
    /// The engine already counts its own unwritten changes and puts the number
    /// in every view it hands back. So there is no list any more: if the engine
    /// says it has something unsaved, it is told to save. A command nobody
    /// thought about is covered the day it is written.
    private func reload(_ parts: String...) { reload(parts) }

    private func reload(_ parts: [String]) {
        guard let engine else { return }
        let raw = engine.raw(parts)
        let decoded: Engine.View
        do {
            decoded = try JSONDecoder().decode(Engine.View.self, from: raw)
        } catch let error as DecodingError {
            // The engine explaining itself beats this app guessing. A refused
            // command answers with its reason, and that reason is worth more
            // on screen than "something could not be read".
            unreadable = Session.refusal(in: raw) ?? Session.explain(error)
            return
        } catch {
            unreadable = error.localizedDescription
            return
        }
        unreadable = nil
        view = decoded
        ShootDays.remember(film: entry.name, days: decoded.days)
        WidgetPublisher.soon(self)
        // **What the film actually uses**, read whenever nothing is hiding
        // shots — the Filter menu offers these, never the standing list.
        if !decoded.filter.narrowed { everyRow = decoded.groups.flatMap(\.rows) }
        if decoded.project.unsaved > 0 {
            engine.raw("save")
        }
        if watchingSchedule { readSchedule() }
        readTermColours()
    }

    // ---- colours a person chose -----------------------------------------------

    /// **The colours he gave list values**, on the Mac or here — `field` and
    /// term to hex. Terms nobody coloured are not in it and keep their
    /// column's ink.
    @Published private(set) var termColours: [String: String] = [:]

    private func readTermColours() {
        guard let engine else { return }
        struct Pick: Decodable { var field: String; var term: String; var hex: String }
        struct Reply: Decodable { var colours: [Pick] }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: engine.raw("colours")) else { return }
        var next: [String: String] = [:]
        for pick in reply.colours where !pick.hex.isEmpty { next[pick.field + "\u{1}" + pick.term] = pick.hex }
        if next != termColours { termColours = next }
    }

    func termColour(_ field: String, _ term: String) -> String? {
        termColours[field + "\u{1}" + term]
    }

    /// A list value's colour; empty hands it back to its column's ink.
    func colourTerm(_ field: String, _ term: String, hex: String) {
        guard let engine else { return }
        _ = engine.raw("list", "colour", field, term, hex)
        reload("view")
    }

    /// A shot's highlight (`Swatches.highlight`); empty takes it off.
    func highlight(_ row: Engine.Row, _ hex: String) {
        reload("set", row.shot, "colour", hex)
    }

    // ---- master shots -------------------------------------------------------

    /// Other shots can stand in for a master; the Mac's Make Master.
    func makeMaster(_ row: Engine.Row, _ on: Bool) {
        reload("master", row.shot, on ? "1" : "0")
    }

    /// Point a shot at a master, or cut it loose (`nil`).
    func link(_ row: Engine.Row, to master: Engine.Row?) {
        reload("link", row.shot, master?.shot ?? "none")
    }

    /// Every master in the film but this shot, for Link to Master.
    func masters(besides row: Engine.Row) -> [Engine.Row] {
        let all = narrowed ? everyRow : groups.flatMap(\.rows)
        var seen = Set<String>()
        return all.filter { $0.isMaster && $0.shot != row.shot && seen.insert($0.shot).inserted }
    }

    // ---- versions -----------------------------------------------------------

    /// **The old version on screen, or nil for now.** While it is set the
    /// engine answers every showing command from it and refuses every edit —
    /// safe by construction (`ffi/src/versions.rs`), nothing here has to
    /// switch anything off.
    @Published private(set) var looking: VersionItem?

    /// Today where he is — the engine keys the day's version on it.
    static var dayHere: String {
        let shape = DateFormatter()
        shape.dateFormat = "yyyy-MM-dd"
        return shape.string(from: Date())
    }

    func versions() -> [VersionItem] {
        guard let engine else { return [] }
        struct Reply: Decodable { var looking: String; var versions: [VersionItem] }
        return (try? JSONDecoder().decode(Reply.self, from: engine.raw("versions")))?.versions ?? []
    }

    /// The film as it stands, kept; an empty name is fine (the day names it).
    @discardableResult
    func saveVersion(named name: String) -> Bool {
        guard let engine, looking == nil else { return false }
        struct Reply: Decodable { var saved: String }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let reply = try? JSONDecoder().decode(Reply.self, from: engine.raw("saveversion", trimmed, Self.dayHere))
        return !(reply?.saved ?? "").isEmpty
    }

    /// **One kept on its own each day he works**, the Mac's start-of-day
    /// version: whichever device opens the film first that day saves it.
    func saveDailyVersionIfDue() {
        guard let engine, looking == nil else { return }
        _ = engine.raw("dailyversion", Self.dayHere)
    }

    func renameVersion(_ version: VersionItem, to name: String) {
        _ = engine?.raw("renameversion", version.id, name.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func deleteVersion(_ version: VersionItem) {
        if looking?.id == version.id { lookNow() }
        _ = engine?.raw("deleteversion", version.id)
    }

    func look(at version: VersionItem) {
        reload("lookat", version.id)
        if unreadable == nil { looking = version }
    }

    func lookNow() {
        guard looking != nil else { return }
        looking = nil
        reload("looknow")
    }

    /// **What is picked, back into now as it was** — shots by their shot
    /// id, scenes by theirs. One undo step. Returns how many records changed.
    @discardableResult
    func bringBack(_ ids: [String]) -> Int {
        guard let engine, let version = looking, !ids.isEmpty else { return 0 }
        struct Brought: Decodable { var records: Int }
        struct Reply: Decodable { var brought: Brought }
        let raw = engine.raw("bringback", version.id, ids.joined(separator: ","))
        guard let reply = try? JSONDecoder().decode(Reply.self, from: raw) else {
            unreadable = Session.refusal(in: raw)
            return 0
        }
        looking = nil
        reload("looknow")
        return reply.brought.records
    }

    /// The whole film back as it was. Now is saved as a version first, by
    /// the engine, before anything changes.
    func goBack(to version: VersionItem) {
        guard let engine else { return }
        let raw = engine.raw("goback", version.id, Self.dayHere)
        if let refused = Session.refusal(in: raw) { unreadable = refused; return }
        looking = nil
        reload("looknow")
    }

    // ---- cameras ------------------------------------------------------------

    /// How many shots name this camera, off the shots themselves.
    func uses(of unit: Engine.Unit) -> Int {
        let all = narrowed ? everyRow : groups.flatMap(\.rows)
        return all.filter { $0.unit?.id == unit.id }.count
    }

    /// Every shot naming it follows for free: a shot holds the camera, not
    /// a copy of its name.
    func renameUnit(_ unit: Engine.Unit, to label: String) {
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != unit.label else { return }
        reload("unit", "name", unit.id, name)
    }

    func recolourUnit(_ unit: Engine.Unit, _ hex: String) {
        reload("unit", "colour", unit.id, hex)
    }

    /// The shots that named it keep everything else and name no camera.
    func removeUnit(_ unit: Engine.Unit) {
        reload("unit", "remove", unit.id)
    }

    /// The days and their strips, asked for afresh.
    func readSchedule() {
        guard let engine else { return }
        guard let read = try? JSONDecoder().decode(Engine.Schedule.self, from: engine.raw("board")) else {
            return
        }
        schedule = read
    }

    /// **A command whose answer is not a view.**
    ///
    /// The schedule's own commands — `day`, and putting a scene on a day —
    /// hand back the board instead, and handing that to `reload` reads as *the
    /// engine's answer was not a view*: the whole project draws as unreadable
    /// over a change that in fact worked. So they go out here, and the view is
    /// asked for separately afterwards.
    private func send(_ parts: String...) { send(parts) }

    private func send(_ parts: [String]) {
        guard let engine else { return }
        let refused = Session.refusal(in: engine.raw(parts))
        reload("view")
        // Said after the reload, which clears it on the way through.
        if let refused { unreadable = refused }
    }

    /// The engine's own words, when what came back was a refusal rather than a
    /// view. `{"error": "that is not a column this project made"}`.
    static func refusal(in raw: Data) -> String? {
        struct Problem: Decodable { var error: String }
        guard let problem = try? JSONDecoder().decode(Problem.self, from: raw),
              !problem.error.isEmpty else { return nil }
        return problem.error
    }

    /// Whatever is pending, on the way out. Belt to the braces above — a phone
    /// is put in a pocket rather than quit, and iOS may never wake it again.
    func flush() {
        engine?.raw("save")
    }

    // ---- changing a shot ---------------------------------------------------

    /// Writes one field of one shot, and takes back the view the engine hands
    /// out afterwards. The screen never edits its own copy: it asks, and draws
    /// whatever comes back. That is the whole reason two devices editing the
    /// same list cannot disagree.
    func set(_ row: Engine.Row, _ field: String, to value: String) {
        reload("set", row.shot, field, value)
    }

    /// The floor plan for a scan, worked out by the engine.
    ///
    /// An empty path asks for the hand-built sample room, which is how a plan
    /// can be looked at without a LiDAR sensor and a room to stand in.
    func floorPlan(of scan: URL?) -> Plan? {
        guard let engine else { return nil }
        return try? JSONDecoder().decode(Plan.self, from: engine.raw("floorplan", scan?.path ?? ""))
    }

    /// Makes a camera. **A camera is a record with a colour**, not a word in a
    /// list — which is why typing one into the camera field did nothing: the
    /// field takes an id, and a name is not one.
    func addUnit(named label: String) {
        // Cycled rather than asked for. On a set nobody wants a colour picker,
        // and what matters is only that two cameras look different.
        // The Mac's six (`Swatches`), in turn, so the two apps agree.
        let colour = Swatches.highlight[units.count % Swatches.highlight.count]
        reload("addunit", label, colour)
    }

    /// Cutting a shot is its own command, not a field — a struck shot stays in
    /// the list with a line through it, which is a different thing from a field
    /// having a value.
    func strike(_ row: Engine.Row, _ on: Bool) {
        reload("strike", row.shot, on ? "1" : "0")
    }

    /// Takes a picture off a shot. The file stays — it is named by its
    /// contents and may be on another shot.
    func detach(_ still: Engine.Still) {
        reload("detach", still.ref)
    }

    // ---- the scanned rooms ------------------------------------------------
    //
    // **A room is read off the film, not the folder** — Ref 939. The phone
    // still writes a scan as two files into `locations/<folder>/scans/`, and
    // the film registers them as media, the way a photograph is, so a room
    // scanned here shows on the other phone, on the Mac and on the web. The
    // folder is asked only for what the film has not been told about yet — a
    // scan taken seconds ago, or one made before rooms were media — and for
    // the bytes when the copy the film keeps has not come down.

    /// A scanned room as this screen draws it: the film's name, the two files
    /// wherever they are, and the uses that let it be renamed or taken off.
    struct Room: Identifiable, Hashable {
        var name: String
        var usdz: URL?
        var json: URL?
        var shapeRef: String
        var planRef: String
        /// Whether the film knows about it yet.
        var onFilm: Bool
        /// When it was scanned, said under its name; empty when unknown.
        var taken: String = ""
        var id: String { name }
        var isMeasured: Bool { json.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }
    }

    /// The rooms of a place, newest first.
    func rooms(of place: Engine.Location) -> [Room] {
        let folder = store.scansFolder(place.home)
        var out: [Room] = []
        for scan in place.scans {
            let usdz = scan.shape.flatMap { file($0, in: folder) }
            let json = scan.plan.flatMap { file($0, in: folder) }
            out.append(Room(name: scan.name, usdz: usdz, json: json,
                            shapeRef: scan.shape?.ref ?? "", planRef: scan.plan?.ref ?? "",
                            onFilm: true, taken: scan.taken))
        }
        // A room renamed keeps its files' own name: those files are this
        // room, not another one waiting to be registered.
        let known = Set(out.map(\.name) + place.scans.map(\.file).filter { !$0.isEmpty })
        for scan in store.scans(in: place.home) where !known.contains(scan.name) {
            out.append(Room(name: scan.name, usdz: scan.usdz,
                            json: scan.isMeasured ? scan.json : nil,
                            shapeRef: "", planRef: "", onFilm: false))
        }
        return out.sorted { $0.name > $1.name }
    }

    /// Where one half of a room is on this phone: the film's own copy under
    /// its hash when it has come down, else the file the scanner wrote, else
    /// nowhere yet.
    private func file(_ half: Engine.Room.Half, in scans: URL) -> URL? {
        let ext = (half.filename as NSString).pathExtension
        let proxy = folder.url.appending(path: "media/proxies")
            .appendingPathComponent(String(half.hash.prefix(32)) + "." + ext)
        if Cloud.here(proxy) { return proxy }
        let own = scans.appendingPathComponent(half.filename)
        if FileManager.default.fileExists(atPath: own.path) { return own }
        return nil
    }

    /// The papers pinned to a place: the film's own first — each a stored
    /// file under its hash, which is how one pinned on the Mac or the other
    /// phone gets here — then anything still only in the folder, which is
    /// where a paper lands on the phone that pinned it before the next
    /// registration. The same rule as `rooms(of:)`, for the same reason.
    struct Paper: Hashable {
        var name: String
        var url: URL
    }

    func papers(of place: Engine.Location) -> [Paper] {
        let proxies = folder.url.appending(path: "media/proxies")
        var out: [Paper] = []
        var named: Set<String> = []
        for paper in place.media where paper.kind == .other {
            let ext = (paper.filename as NSString).pathExtension
            let proxy = proxies.appendingPathComponent(String(paper.hash.prefix(32)) + "." + ext)
            guard Cloud.here(proxy) else { continue }
            named.insert(paper.filename)
            out.append(Paper(name: paper.filename, url: proxy))
        }
        for file in store.attachments(in: place.home)
        where !named.contains(file.lastPathComponent) {
            out.append(Paper(name: file.lastPathComponent, url: file))
        }
        return out.sorted { $0.name < $1.name }
    }

    /// Tells the film about any scan sitting in a folder it has not seen —
    /// the moment one is made, and on opening a place, so a room never waits
    /// for a sync to exist. Cheap and safe to repeat: the engine recognises a
    /// file by its contents.
    func registerScans() {
        reload("registerscans")
    }

    /// Renames a room on the film and in the folder together.
    func rename(room: Room, to fresh: String, in place: Engine.Location) throws {
        let safe = fresh.replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safe.isEmpty, safe != room.name else { return }
        for ref in [room.shapeRef, room.planRef] where !ref.isEmpty {
            reload("renameuse", ref, safe)
        }
        let folder = store.scansFolder(place.home)
        let fm = FileManager.default
        for ext in ["usdz", "json"] {
            let old = folder.appendingPathComponent(room.name + "." + ext)
            if fm.fileExists(atPath: old.path) {
                try fm.moveItem(at: old, to: folder.appendingPathComponent(safe + "." + ext))
            }
        }
    }

    /// Takes a room off the film and deletes its files. Both, because a file
    /// left in the folder would be registered again at the next sync.
    func delete(room: Room, in place: Engine.Location) throws {
        for ref in [room.shapeRef, room.planRef] where !ref.isEmpty {
            reload("detach", ref)
        }
        let folder = store.scansFolder(place.home)
        let fm = FileManager.default
        for ext in ["usdz", "json"] {
            let file = folder.appendingPathComponent(room.name + "." + ext)
            if fm.fileExists(atPath: file.path) { try fm.removeItem(at: file) }
        }
    }

    /// Moves a picture to a different place in the shot's order.
    /// A board to another place in the list.
    func moveBoard(_ id: String, to index: Int) {
        reload("moveboard", id, String(index))
    }

    /// A picture onto another board (or any owner), off this one.
    func movePicture(_ still: Engine.Still, toOwner owner: String) {
        reload("movepictureto", still.ref, owner)
    }

    /// What is said under a picture, on this use of it.
    /// **The project's icon and color**, chosen here (`hand`); empty clears.
    func setMark(path: String, colour: String) {
        reload("setmark", path, colour, path.isEmpty ? "" : "hand")
    }

    /// **The Document page's type** (`docstyle`): a class's size, face,
    /// case and color, or `reset`, or `apply <said>`.
    func docStyle(_ args: [String]) { reload(["docstyle"] + args) }

    /// Where a shot's frame sits on the Document page, and how wide.
    func layout(_ row: Engine.Row, position: String, width: Double) {
        reload("layout", row.shot, position, String(format: "%.3f", width))
    }

    /// The arrows on one use of a picture as the film has them now.
    func stillArrows(_ ref: String) -> [Engine.Arrow]? {
        if let s = (view?.groups.flatMap(\.rows) ?? []).flatMap(\.stills).first(where: { $0.ref == ref }) { return s.arrows }
        if let s = locations.flatMap(\.media).first(where: { $0.ref == ref }) { return s.arrows }
        return nil
    }

    /// **The arrows drawn over one use of a picture**, the Mac's line; none
    /// clears them, so "no arrows" and "never had any" are one fact.
    func setArrows(ref: String, _ arrows: [Engine.Arrow]) {
        let line = Engine.Arrow.encode(arrows)
        reload("arrows", ref, line.isEmpty ? "clear" : line)
    }

    func caption(_ still: Engine.Still, _ words: String) {
        reload("caption", still.ref, words.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Which of a shot's frames stands for it (the Mac's star).
    func keyFrame(shot: String, _ still: Engine.Still) {
        reload("keyframe", shot, still.ref)
    }

    func move(_ still: Engine.Still, to index: Int) {
        reload("movemedia", still.ref, String(index))
    }

    // ---- a clip's own facts --------------------------------------------------
    //
    // Both of these belong to *this use* of the file, never to the file: the
    // same clip on two shots can be cut two ways, and nothing on disk is
    // touched by either.

    /// The seconds of a clip this use plays.
    func trim(_ still: Engine.Still, from start: Double, to end: Double) {
        reload("trim", still.ref, String(format: "%.3f", start), String(format: "%.3f", end))
        prepareStrips()
    }

    /// Back to playing the whole thing.
    func clearTrim(_ still: Engine.Still) {
        reload("trim", still.ref, "clear")
        prepareStrips()
    }

    /// **Which part of a picture is kept where it is drawn cropped**, and how
    /// far in. Belongs to this use of the file; the file is never touched.
    func crop(_ still: Engine.Still, x: Double, y: Double, scale: Double) {
        reload("crop", still.ref,
               String(format: "%.4f", x),
               String(format: "%.4f", y),
               String(format: "%.4f", scale))
    }

    /// Back to the middle, at full width.
    func clearCrop(_ still: Engine.Still) {
        reload("crop", still.ref, "clear")
    }

    /// The still that stands for a clip wherever a picture is drawn.
    ///
    /// Stored against the clip's own contents rather than against one use of
    /// it, which is why this takes a hash. The engine answers `ok` rather than
    /// a view, so it goes out through `send`.
    func poster(hash: String, jpeg: Data) {
        send("poster", hash, jpeg.base64EncodedString())
    }

    // ---- the script -----------------------------------------------------------

    /// The script, once, for the whole project.
    ///
    /// Read on demand rather than with the view: it is the biggest thing the
    /// engine can hand over and most of a scout never asks for it.
    enum Screenplay {
        case none
        case missing(String)
        case read(Script)
    }

    @Published private(set) var script: Screenplay = .none

    func readScript() {
        guard case .none = script, let engine else { return }
        let raw = engine.raw("scriptpages")
        struct Problem: Decodable { var error: String }
        if let problem = try? JSONDecoder().decode(Problem.self, from: raw) {
            script = .missing(problem.error)
            return
        }
        guard let read = try? JSONDecoder().decode(Script.self, from: raw) else {
            script = .missing("Can't read the script")
            return
        }
        script = .read(read)
    }

    // ---- editing the list ---------------------------------------------------

    /// A new shot, seated after the one he was looking at.
    ///
    /// Created and seated in one go, which is also one undo — the engine's
    /// rule, not ours.
    func addShot(toScene scene: String, after: Engine.Row? = nil) {
        reload("addshot", scene, after?.placement ?? "")
    }

    /// A second shot with the same everything, which is how coverage gets
    /// written: the same setup, one thing changed.
    func duplicate(_ row: Engine.Row) {
        reload("duplicate", row.placement)
    }

    func delete(_ row: Engine.Row) {
        reload("delete", row.placement)
    }

    /// Moves a shot within its scene. The letters follow — they belong to the
    /// order, not to the shot.
    func move(_ row: Engine.Row, to index: Int) {
        reload("reorder", row.placement, String(index))
    }

    /// A scene, by the number the script gives it. **We never renumber**, so the
    /// number is his to type.
    func addScene(numbered number: String) {
        reload("addscene", number)
    }

    /// A scene **and everything typed about it**, filed as one change — the
    /// same call the Mac's Add Scene box makes, so one undo takes the whole
    /// scene back. The pairs are the field names a cell writes, plus `place`,
    /// which points the scene at a location. Ref 940.
    func addScene(numbered number: String, fields: [(String, String)]) {
        var parts = ["addscene", number]
        for (field, value) in fields
        where !value.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(field)
            parts.append(value)
        }
        reload(parts)
    }

    /// A scene made from a title — the commercial way. The engine gives it the
    /// next whole number and lands it last; the pairs are `addScene`'s pairs.
    /// One change, like the Mac's `addTitled`.
    func addScene(titled title: String, fields: [(String, String)]) {
        var parts = ["addtitled", title]
        for (field, value) in fields
        where !value.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(field)
            parts.append(value)
        }
        reload(parts)
    }

    // ---- a commercial ------------------------------------------------------
    //
    // The engine's `kind` module owns what a commercial is; the phone reads the
    // fact and changes what it draws. Switching changes no data — a film can go
    // there and back and every scene is as it was.

    /// `film` or `commercial`.
    func setKind(_ kind: String) {
        reload("kind", kind)
    }

    /// **The frame the app draws at** (piece E): one of the project's frames
    /// off its spec sheet, by name — the same pick as Studio on the Mac.
    func pickFrame(_ name: String) {
        reload("frame", name)
    }

    /// Show the project's other frames as guide lines on the cards.
    func setFrameGuides(_ on: Bool) {
        reload("frameguides", on ? "on" : "off")
    }

    /// **The Spec Sheet switch**: `off`, `ask` or `follow` (Sync). Undoable.
    func setKitMode(_ mode: String) {
        reload("kitmode", mode)
    }

    /// The kit off the spec sheets, as the portal's kit door gave it.
    func takeKit(_ json: String) {
        reload("recordkit", json)
    }

    /// A camera's own sensor, in mm; a width of 0 clears it.
    func setSensor(_ unit: Engine.Unit, name: String, w: Double, h: Double) {
        reload("unit", "sensor", unit.id, String(w), String(h), name)
    }

    /// What saving a script did to the shots quoting it: the ties whose words
    /// were still there and re-anchored, and the ones that were lost.
    struct ScriptEdit: Decodable {
        var kept: Int
        var lost: Int
    }

    /// **The script as text**, on a section — or on the film when `section`
    /// is nil. Tabs travel as `\u{1f}` because the call is tab-separated.
    /// Ties re-anchor by their words; the answer says how many kept and lost.
    @discardableResult
    func setScript(_ text: String, section: String?, append: Bool = false) -> ScriptEdit? {
        guard let engine else { return nil }
        let carried = text.replacingOccurrences(of: "\t", with: "\u{1f}")
        let answer = engine.raw(["setscript", section ?? "", carried] + (append ? ["append=1"] : []))
        let edit = try? JSONDecoder().decode(ScriptEdit.self, from: answer)
        reload("view")
        return edit
    }

    /// The shot quotes that UTF-16 range of the section's script. `to` at or
    /// below `from` unties.
    /// The highlighter (2026-10-05): the words are added to what the shot
    /// already quotes — or, when it holds every one of them, let go.
    func tie(_ row: Engine.Row, section: String?, from: Int, to: Int) {
        reload("toggletie", row.shot, section ?? "", String(from), String(to))
    }

    func untie(_ row: Engine.Row) {
        reload("tieshot", row.shot, "", "0", "0")
    }

    /// The section goes; its scenes stay and leave it.
    func deleteSection(_ section: Engine.Sequence) {
        reload("deletesequence", section.id)
    }

    /// The Mac's two, the same writes: a new name, and one of the eight
    /// colours a section is born with (`SEQUENCE_COLOURS` in the engine).
    func renameSection(_ section: Engine.Sequence, to title: String) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != section.title else { return }
        reload("set", section.id, "title", name)
    }

    func colourSection(_ section: Engine.Sequence, hex: String) {
        reload("set", section.id, "colour", hex)
    }

    static let sectionColours: [(hex: String, name: String)] = [
        ("#2B6CB0", "Blue"), ("#B4531B", "Rust"), ("#2F7A44", "Green"), ("#7B4BC4", "Violet"),
        ("#A33574", "Plum"), ("#2C7A7B", "Teal"), ("#9A6B10", "Ochre"), ("#4C51BF", "Indigo"),
    ]

    /// What a typed heading says, without writing anything. Asked of the
    /// engine so a line typed here and a line read out of a draft are never
    /// understood two different ways.
    struct Heading: Decodable {
        var number = ""
        var intExt = ""
        var location = ""
        var timeOfDay = ""
    }

    func readHeading(_ line: String) -> Heading {
        guard let engine else { return Heading() }
        return (try? JSONDecoder().decode(Heading.self, from: engine.raw("readheading", line)))
            ?? Heading()
    }

    /// Moves a shot out of its scene and into another. **The letters follow** —
    /// they belong to where a shot sits, not to the shot, so it leaves a gap
    /// behind it and takes the next free letter where it lands.
    func move(_ row: Engine.Row, toScene scene: String) {
        reload("movescene", row.placement, scene)
    }

    /// Copies shots into another scene, keeping everything on them.
    ///
    /// **Not a cell paste.** A shot carries its frames, its camera and its
    /// notes; pasting its columns as text would lose all of it.
    func copy(_ rows: [Engine.Row], toScene scene: String) {
        guard !rows.isEmpty else { return }
        reload("copyshots", rows.map(\.placement).joined(separator: ","), scene, "")
    }

    /// Puts a scene out of the way without losing it — the honest middle
    /// between keeping a scene that is gone from the draft and deleting one
    /// that has shots on it.
    func archive(_ scene: Engine.Scene, _ on: Bool) {
        reload("archivescene", scene.id, on ? "1" : "0")
    }

    /// A scene, and everything in it. **A person's decision, always** — the
    /// screen says what it costs before it asks.
    /// **Move to Shoot…** — the scene into another of the project's shoots, one undo.
    func moveScene(_ scene: Engine.Scene, toShoot shoot: Engine.Shoot) {
        reload("shootmove", shoot.id, scene.id)
    }

    func deleteScene(_ scene: Engine.Scene) {
        reload("deletescene", scene.id)
    }

    // ---- several shots at once ----------------------------------------------
    //
    // Ref 253. The Mac has had these since the beginning; the phone could only
    // ever change one shot at a time, so setting the same lens on six shots was
    // six trips through the same screen.
    //
    // **One value onto many shots is one transaction**, which is the part that
    // matters: it is one thing to take back, not six. The engine does that on
    // its own — these hand it the whole selection rather than looping here, and
    // looping here is precisely what would break undo.

    /// One value onto every shot in a selection.
    func set(_ rows: [Engine.Row], _ field: String, to value: String) {
        guard !rows.isEmpty else { return }
        reload("setmany", rows.map(\.shot).joined(separator: ","), field, value)
    }

    /// **Lines pasted down a column**, one per shot in order (a sheet's
    /// paste); one line fills every shot. A tab-split line takes its first cell.
    func pasteColumn(_ text: String, into rows: [Engine.Row], field: String) {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0.split(separator: "\t", omittingEmptySubsequences: false).first ?? "").trimmingCharacters(in: .whitespaces) }
        let used = lines.last == "" ? Array(lines.dropLast()) : lines
        guard !used.isEmpty, !rows.isEmpty, let engine else { return }
        _ = engine.raw("undoopen", "Paste")
        if used.count == 1 {
            set(rows, field, to: used[0])
        } else {
            for (row, value) in zip(rows, used) { set([row], field, to: value) }
        }
        _ = engine.raw("undoclose")
        refresh()
    }

    /// Empties one column on every shot in a selection.
    func clear(_ field: String, on rows: [Engine.Row]) {
        guard !rows.isEmpty else { return }
        reload("clearcells", "\(field)=\(rows.map(\.shot).joined(separator: ","))")
    }

    /// **Clear Shot**: every column on these shots emptied, one undo — the
    /// Mac's `clearShots`. The shot, its number and its pictures stay.
    func clearShots(_ rows: [Engine.Row]) {
        guard !rows.isEmpty else { return }
        let words: Set<String> = ["size", "angle", "movement", "lens", "modifiers", "lens_filters", "support",
                                  "title", "description", "notes", "tags", "priority", "camera"]
        let fields = columns.filter { $0.visible && (words.contains($0.name)
            || ($0.name.hasPrefix("c_") && ["text", "single", "multi"].contains($0.kind ?? ""))) }
            .map { $0.name == "camera" ? "unit" : $0.name }
        guard !fields.isEmpty else { return }
        let shots = rows.map(\.shot).joined(separator: ",")
        reload("clearcells", fields.map { "\($0)=\(shots)" }.joined(separator: "|"))
    }

    /// **Duplicate** several shots: copies right after the last, one undo.
    func duplicateShots(_ rows: [Engine.Row]) {
        guard let last = rows.last, let scene = last.sceneId else { return }
        reload("copyshots", rows.map(\.placement).joined(separator: ","), scene, last.placement)
    }

    /// **Paste** the copied shots just after this one, in its scene.
    func pasteShots(after row: Engine.Row) {
        guard !copiedShots.isEmpty, let scene = row.sceneId else { return }
        reload("copyshots", copiedShots.joined(separator: ","), scene, row.placement)
    }

    /// A highlight onto every picked shot.
    func highlight(_ rows: [Engine.Row], _ hex: String) {
        for row in rows { reload("set", row.shot, "colour", hex) }
    }

    /// Picked shots onto a shoot day (at its end), or off every day.
    func shootDay(_ rows: [Engine.Row], day: String?) {
        for row in rows { reload("shootbefore", row.placement, day ?? "", "") }
    }

    // ---- the scene list's own tools (the Mac's scene menu) -----------------

    /// The scene moves to sit just after `after`, or first with none.
    func moveScene(_ scene: Engine.Scene, after: Engine.Scene?) {
        if let after { reload("sceneafter", scene.id, after.id) } else { reload("sceneafter", scene.id) }
    }

    func sortScenesByNumber() { reload("sortscenes") }
    func settleTimesOfDay() { reload("settletimes") }

    /// Every scene numbered by its place in the list; how many changed.
    @discardableResult
    func renumberScenes() -> Int {
        guard let engine else { return 0 }
        struct Reply: Decodable { var changed: Int? }
        let n = (try? JSONDecoder().decode(Reply.self, from: engine.raw("renumber")))?.changed ?? 0
        reload("view")
        return n
    }

    /// **A location made from the scene's slugline**, and linked to it.
    func makeLocation(from scene: Engine.Scene) {
        let name = scene.location.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let made = addLocation(named: name) else { return }
        reload("addscenelocation", scene.id, made.id)
    }

    /// Cuts, or uncuts, a whole selection at once.
    func strike(_ rows: [Engine.Row], _ on: Bool) {
        guard !rows.isEmpty else { return }
        reload("strike", rows.map(\.shot).joined(separator: ","), on ? "1" : "0")
    }

    /// Moves a selection into another scene.
    ///
    /// Back to front, and for the same reason as deleting: each move renumbers
    /// what is left behind it. The engine has no one-command form of this.
    func move(_ rows: [Engine.Row], toScene scene: String) {
        for row in rows.reversed() {
            reload("movescene", row.placement, scene)
        }
    }

    /// Deletes a selection.
    ///
    /// **Back to front.** Deleting by placement renumbers what is left, so
    /// taking them in the order they sit in would delete the wrong rows after
    /// the first. There is no one-command form of this in the engine, so each
    /// is its own step — and its own undo, which is worth saying on screen
    /// rather than pretending otherwise.
    func delete(_ rows: [Engine.Row]) {
        for row in rows.reversed() {
            reload("delete", row.placement)
        }
    }

    // ---- the columns themselves ---------------------------------------------
    //
    // Ref 253. A project's shape belonged to the Mac alone: the phone could
    // read a column and write into it, but not make one, rename one, move one
    // or take one away.

    /// A column of the project's own. `kind` is how its cells behave —
    /// `text`, `single`, `multi` or `check`.
    func addColumn(kind: String, label: String) {
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        reload("addcolumn", kind, name)
    }

    /// A ready-made column (`ColumnTemplates`, the Mac's list): the same
    /// `addcolumn`, then the terms it arrives knowing through `list add`, as
    /// the Mac does — nothing about a template is special once it exists.
    func addColumn(_ ready: ColumnTemplates.Ready) {
        let before = Set(columns.map(\.name))
        addColumn(kind: ready.kind, label: ready.label)
        guard let landed = columns.first(where: { !before.contains($0.name) })?.name,
              let engine, !ready.values.isEmpty else { return }
        for value in ready.values { _ = engine.raw("list", "add", landed, value) }
        reload("view")
    }

    /// Whether the film already has a column a person would read as this
    /// one — by its name, case-blind, so "cast" is not offered "Cast".
    func hasColumn(named label: String) -> Bool {
        columns.contains { $0.shown.compare(label, options: .caseInsensitive) == .orderedSame }
    }

    /// Renames a column. **What is written in it stays where it is** — the
    /// field keeps its own name underneath, because renaming a field would
    /// rename it in every project file ever written.
    func renameColumn(_ field: String, to label: String) {
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        reload("renamecolumn", field, name)
    }

    /// A column and everything written in it. Only a column the project made —
    /// the engine refuses a built-in, and says so.
    func deleteColumn(_ field: String) {
        reload("deletecolumn", field)
    }

    /// Shows or hides a column. A hidden column keeps its place, so showing it
    /// again puts it back where it was rather than at the end.
    func showColumn(_ name: String, _ visible: Bool) {
        reload("column", name, visible ? "1" : "0")
    }

    /// The order of the columns, which is also the order the shot's own page
    /// reads in — one order, so the two cannot disagree.
    func setColumnOrder(_ names: [String]) {
        guard !names.isEmpty else { return }
        reload("columnorder", names.joined(separator: ","))
    }

    // ---- the runs of the film -----------------------------------------------

    /// A sequence, which is a run of the film rather than a property of a shot.
    func addSequence(named title: String) -> Engine.Sequence? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let before = Set(sequences.map(\.id))
        reload("addsequence", name)
        return sequences.first { !before.contains($0.id) }
    }

    /// Puts a scene in a sequence, or takes it out of one. **It hangs on the
    /// scene**, which is where the Mac sets it too — a sequence is a run of the
    /// film, not something one setup carries.
    func setSequence(ofScene scene: String, to sequence: String) {
        reload("set", scene, "sequence", sequence)
    }

    /// Taking back the last thing, and putting it back again.
    ///
    /// The engine owns what one undo means. It answers with what it did, and
    /// with how much another device had already built on top of — which is the
    /// only honest thing to say when part of a step cannot be taken back.
    struct Undone: Decodable {
        var did: Bool
        var label: String?
        var restored: Int?
        var skipped: Int?
        var complete: Bool?
    }

    @discardableResult
    func undo() -> Undone? { step("undo") }

    @discardableResult
    func redo() -> Undone? { step("redo") }

    private func step(_ command: String) -> Undone? {
        guard let engine else { return nil }
        let answer = try? JSONDecoder().decode(Undone.self, from: engine.raw(command))
        engine.raw("save")
        reload("view")
        return answer
    }

    /// The project's own list for a field — the sizes and lenses it has used.
    /// Empty for a field that is free text.
    func vocabulary(_ field: String) -> [String] {
        guard let engine else { return [] }
        struct Reply: Decodable { var values: [String] }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: engine.raw("vocab", field)) else {
            return []
        }
        return reply.values
    }

    /// Puts a picture on a shot.
    func attach(_ image: UIImage, to row: Engine.Row) {
        attach(Media.shrunk(image, longest: 1280), to: row.shot)
        readViewfinder(image, for: row)
    }

    /// **The lens off a viewfinder frame** (the Mac's): Artemis and Cadrage
    /// stamp "47mm" on the picture. An empty Lens takes it and says so; a
    /// different one is left alone and told about.
    @Published var lensSaid: String?

    func readViewfinder(_ image: UIImage, for row: Engine.Row) {
        Viewfinder.lens(in: image) { [weak self] found in
            guard let self, let found else { return }
            let known = self.vocabulary("lens").first { $0.lowercased().replacingOccurrences(of: " ", with: "") == found }
            let value = known ?? found
            let current = self.row(row.id)?.lens ?? row.lens
            if current.isEmpty {
                self.set(row, "lens", to: value)
                self.lensSaid = "Lens set to \(value)"
            } else if current.lowercased().replacingOccurrences(of: " ", with: "") != found {
                self.lensSaid = "Frame says \(value), shot says \(current). Not changed."
            }
        }
    }

    /// The row as the engine now has it, so a screen showing one shot follows
    /// its own edits without holding a second copy of them.
    func row(_ id: String) -> Engine.Row? {
        groups.flatMap(\.rows).first { $0.id == id }
    }

    // ---- locations ---------------------------------------------------------

    /// Makes a place, and gives it a folder of its own for the files that stay
    /// files — the scans and the papers. The folder is named once and never
    /// again, so renaming the place cannot strand them.
    @discardableResult
    func addLocation(named name: String) -> Engine.Location? {
        made(by: { reload("addlocation", name) })
    }

    /// A room inside a place. The Mac calls the same command.
    func addRoom(inside parent: String, named name: String) -> Engine.Location? {
        made(by: { reload("addarea", parent, name) })
    }

    /// Whichever id was not there a moment ago — asked of the answer rather
    /// than guessed at from the order.
    ///
    /// **It no longer invents a folder.** It used to write a fresh UUID into
    /// `folder`, which the Mac never did, so a place made here and a place made
    /// there kept their files in two different shapes — and the Mac's, having
    /// no folder at all, put a room's scan outside every location where nothing
    /// looked for it. A place's folder falls back to its own id now, which both
    /// apps can work out without writing anything down.
    private func made(by ask: () -> Void) -> Engine.Location? {
        let before = Set(locations.map(\.id))
        ask()
        guard let fresh = locations.first(where: { !before.contains($0.id) }) else { return nil }
        reload("setlocation", fresh.id, "capturedBy", "iPhone")
        reload("setlocation", fresh.id, "createdAt", ISO8601DateFormatter().string(from: Date()))
        return location(fresh.id)
    }

    func setLocation(_ id: String, _ field: String, to value: String) {
        reload("setlocation", id, field, value)
    }

    func deleteLocation(_ id: String) {
        reload("deletelocation", id)
    }

    /// A room into a place, or out to stand on its own (`""`) — the Mac's
    /// Move into / Move out.
    func moveLocation(_ id: String, into parent: String) {
        reload("movelocation", id, parent)
    }

    /// A photograph on a place.
    func attach(_ image: UIImage, toLocation id: String) {
        attach(Media.shrunk(image, longest: 1600), to: id)
    }

    /// A photograph that arrived as a file, which is most of them.
    ///
    /// Given the bytes, it can do the thing a `UIImage` cannot: **refuse to make
    /// it worse.** Re-encoding a photograph can produce a bigger file than it
    /// started as, and nothing should ever be stored larger than it arrived.
    func attach(_ data: Data, named: String = "", toLocation id: String) {
        attach(Media.shrunk(data, longest: 1600), to: id, named: named)
    }

    func attach(_ data: Data, named: String = "", to row: Engine.Row) {
        attach(Media.shrunk(data, longest: 1280), to: row.shot, named: named)
        if let image = UIImage(data: data), image.images == nil { readViewfinder(image, for: row) }
    }

    /// **A file pinned to a scene** (the Mac's Notes tab): a picture sized the
    /// way a place's are; anything else — a PDF, a call sheet — kept exactly
    /// as it arrived.
    func pin(fileAt url: URL, toScene id: String) async {
        let ext = url.pathExtension.lowercased()
        if ["mov", "mp4", "m4v"].contains(ext) { await attach(clipAt: url, to: id); return }
        guard let data = try? Data(contentsOf: url) else { return }
        if ["png", "jpg", "jpeg", "heic", "tif", "tiff", "webp", "gif", "bmp"].contains(ext) {
            attach(data, named: url.lastPathComponent, toLocation: id)
        } else {
            reload("paste", id, "0", "0", ext.isEmpty ? "bin" : ext, data.base64EncodedString(),
                   "other", "0", url.lastPathComponent, "")
        }
    }

    /// `Pasted 2026-08-22 at 14.03.12` — the only thing knowable about a
    /// picture with no name is when it arrived, and it sorts by that.
    private static func stamp() -> String {
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Pasted \(clock.string(from: Date()))"
    }

    /// A clip, on a shot or on a place.
    ///
    /// It is re-encoded before it goes in — see `Media.clip` — which takes long
    /// enough on a long take to be worth being on a background task, so this is
    /// the one attaching road that is `async`.
    func attach(clipAt url: URL, to owner: String, named: String = "") async {
        // **Ask before encoding anything** — Ref 211. A clip already in this
        // project is a record away, not a re-encode and a second copy of a
        // hundred and fifty megabytes. Both doors are covered: the file may be
        // here as it arrived, or here as the small copy made from it.
        if let came = Media.fingerprint(of: url), let held = alreadyStored(came) {
            reload("use", owner, held)
            prepareStrips()
            return
        }
        let ready = await Media.clip(at: url)
        attach(ready, to: owner, named: named.isEmpty ? url.lastPathComponent : named)
        prepareStrips()
    }

    /// The record this project already keeps for a file, by what the file
    /// hashes to — or nothing. Ref 211.
    private func alreadyStored(_ came: String) -> String? {
        guard let engine,
              let reply = try? engine.call("have", came) as? [String: Any],
              reply["here"] as? Bool == true,
              let media = reply["media"] as? String, !media.isEmpty else { return nil }
        return media
    }

    /// The one road to the engine. The shell sizes and encodes, the engine
    /// hashes and stores — so the same picture in two places is one file.
    ///
    /// **The kind travels with the bytes.** Without it a GIF and a clip are
    /// filed as pictures, and the Mac — which reads the kind, not the name —
    /// draws them as one dead frame.
    private func attach(_ ready: Media.Ready?, to owner: String, named: String = "") {
        guard let ready else { return }
        let filename = naming(named, ext: ready.ext, ownedBy: owner)
        reload("paste", owner,
               String(Int(ready.pixels.width)), String(Int(ready.pixels.height)),
               ready.ext, ready.data.base64EncodedString(),
               ready.kind, String(ready.seconds), filename,
               // What it was made from, when it is a smaller copy of
               // something. The engine records it only when it differs from
               // what is actually stored, so an empty one costs nothing.
               ready.source)

        // **And the still that stands for it, straight after.**
        //
        // A clip draws as *nothing at all* without one, everywhere a picture is
        // expected. The Mac has stored a poster on import since clips landed;
        // this side only ever offered to pick one by hand, so a video added on
        // the phone reached the Mac as a blank cell — his report of shot 5B,
        // 2026-08-31.
        //
        // **After the paste, not with it**, because the poster is filed under
        // the *stored* clip's own hash and that is not known until the engine
        // has stored it. Which one it is is found by the filename just written:
        // the engine keeps one record per set of bytes, so the newest use of
        // this name is the record that was just made.
        guard let poster = ready.poster else { return }
        let hash = stills(of: owner).last { $0.filename == filename }?.hash
        guard let hash, !hash.isEmpty else { return }
        self.poster(hash: hash, jpeg: poster)
    }

    /// Every still on a shot, a location or a board — whichever this owner is.
    /// Used to find the record a paste just made.
    private func stills(of owner: String) -> [Engine.Still] {
        if let row = groups.flatMap(\.rows).first(where: { $0.shot == owner || $0.id == owner }) {
            return row.stills
        }
        if let place = locations.first(where: { $0.id == owner }) { return place.media }
        if let board = boards.first(where: { $0.id == owner }) { return board.media }
        return []
    }

    /// What the file ends up called.
    ///
    /// **A photograph on a place wears the place's name** — his ruling of
    /// 2026-08-22, `mansion-kitchen-01.jpg`, and a room carries its house
    /// because the name is built from the location's full name. The Mac does
    /// the same thing to a file dropped on a location; the rule itself lives in
    /// `shared/FileNames.swift` so the two cannot drift.
    ///
    /// Anything that is not a location keeps the name it arrived with.
    private func naming(_ named: String, ext: String, ownedBy owner: String) -> String {
        if let place = locations.first(where: { $0.id == owner }) {
            let called = place.fullName?.isEmpty == false ? place.fullName! : place.name
            if let name = FileNames.onLocation(called, ext: ext,
                                            taken: place.media.map(\.filename),
                                            from: place.media.count) {
                return name
            }
        }
        // A file keeps the name it came with, but never the extension it came
        // with: what is written is what it is now.
        //
        // Nothing chosen in the photo library has a name at all — the picker
        // hands over bytes — and those all used to land as `pasted.jpg`, so a
        // shot with six references had six files of one name and Google Drive
        // numbered them in arrival order. The stamp is the Finder's own answer
        // to the same problem, and it is what the Mac already does.
        let given = (named as NSString).deletingPathExtension
        return "\(given.isEmpty ? Session.stamp() : given).\(ext)"
    }

    // ---- a scene's own facts ------------------------------------------------
    //
    // A scene is a record like any other, so its number, slugline, synopsis and
    // notes go through the same `set` a cell uses. Only the shoot day is a
    // command of its own, because a day is an assignment rather than a word.

    func setScene(_ id: String, _ field: String, to value: String) {
        reload("set", id, field, value)
    }

    // ---- project settings --------------------------------------------------
    //
    // The Mac's Project Settings, on the phone — Ref 466. The film's own
    // facts go straight to the project record through the same door a cell
    // uses; a list is edited through the engine's `list` verbs, so renaming a
    // term reaches every shot that uses it, the whole reason to rename rather
    // than add and delete.

    /// Title, director, producer, aspect ratio — a field on the film.
    func setProject(_ field: String, to value: String) {
        guard let id = view?.project.id, !id.isEmpty else { return }
        reload("set", id, field, value.trimmingCharacters(in: .whitespaces))
    }

    /// The lists the film keeps: every column that offers terms, and the
    /// three scene lists that are lists whether or not a column shows them.
    var listFields: [String] {
        let builtIn: Set<String> = ["size", "movement", "lens", "modifiers", "lens_filters", "support", "angle", "tags"]
        var found: [String] = []
        for column in columns {
            let kind: String = column.kind ?? ""
            if builtIn.contains(column.name) || kind == "single" || kind == "multi" {
                found.append(column.name)
            }
        }
        for extra in ["tags", "priority", "pov"] where !found.contains(extra) {
            found.append(extra)
        }
        return found
    }

    func isListLocked(_ field: String) -> Bool {
        columns.first { $0.name == field }?.locked ?? false
    }

    func addTerm(_ field: String, _ value: String) {
        send("list", "add", field, value)
    }

    /// How many shots the rename reached.
    @discardableResult
    func renameTerm(_ field: String, from: String, to: String) -> Int {
        guard let engine else { return 0 }
        struct Reply: Decodable { var changed: Int }
        let n = (try? JSONDecoder().decode(Reply.self, from: engine.raw("list", "rename", field, from, to)))?.changed ?? 0
        reload("view")
        return n
    }

    @discardableResult
    func removeTerm(_ field: String, _ value: String) -> Int {
        guard let engine else { return 0 }
        struct Reply: Decodable { var changed: Int }
        let n = (try? JSONDecoder().decode(Reply.self, from: engine.raw("list", "remove", field, value)))?.changed ?? 0
        reload("view")
        return n
    }

    func lockList(_ field: String, _ on: Bool) {
        send("list", "lock", field, on ? "1" : "0")
    }

    /// Notes are stored plain **and** with emphasis, together. Typed on the
    /// phone they are plain, so the rich copy is cleared to match rather than
    /// left saying what the words no longer say — the Mac does the same.
    func setSceneNotes(_ id: String, to value: String) {
        // **Only a real change clears the emphasis.** The field's first
        // fill fired this too, and wiped the Mac's bold and italic on
        // merely opening a scene (2026-10-16).
        if let scene = view?.scenes.first(where: { $0.id == id }), scene.notes == value { return }
        reload("set", id, "notes", value)
        reload("set", id, "notes_rich", "")
    }

    /// Which shoot day this scene falls on. `nil` takes it off the schedule.
    ///
    /// The engine answers this one with the board rather than a view, which is
    /// why it goes through `send`.
    func assign(scene id: String, toDay day: String?) {
        send("scene", id, day ?? "none")
    }

    /// **Only that day's part of a split scene** (the Mac's drag): the
    /// strip lifted off `from` goes onto `day`, ahead of `before` or last.
    func put(scene id: String, toDay day: String?, from: String, before: String? = nil) {
        send("putscenes", day ?? "none", from, before ?? "", id)
    }

    /// **A waiting scene onto a day** — its shots still on no day, and only
    /// those: a scene partly on a day already keeps that part where it is
    /// (his report, 2026-10-17, "Day 3 · 3 left"). Ahead of `before`'s strip,
    /// or last. One undo step.
    func putRemaining(scene id: String, toDay day: String, before: String? = nil) {
        send("putscenes", day, "", before ?? "", id)
    }

    /// Shots still on no day onto a day, standing ahead of `before`'s strip
    /// unless their scene already has one there to join. One undo step.
    func putShots(_ placements: [String], toDay day: String, before: String? = nil) {
        guard !placements.isEmpty else { return }
        send("putshots", day, before ?? "", placements.joined(separator: ","))
    }

    /// A scene's shots on a day, as one block, before another scene's or last.
    func order(scene id: String, onDay day: String, before: String?) {
        if let before { send("sceneinday", id, day, before) } else { send("sceneinday", id, day) }
    }

    // ---- the shoot days themselves ------------------------------------------

    func addDay() { send("day", "new") }

    func renameDay(_ id: String, to name: String) { send("day", "name", id, name) }

    /// An empty date clears it — the same command undoes itself.
    func setDay(_ id: String, date: String) { send("day", "date", id, date) }

    func removeDay(_ id: String) { send("day", "remove", id) }

    func moveDay(_ id: String, to index: Int) { send("day", "move", id, String(index)) }

    /// Where a shot sits in its day's running order — the drag on the Shoot
    /// list. The seat moves, not the shot.
    func order(placement: String, onDayTo index: Int) {
        send("day", "order", placement, String(index))
    }

    /// Scratch a shot off on the day, or put it back. The same fact the Cut
    /// switch on a shot's page sets; asked for by id here because the Shoot
    /// list has no row.
    func strike(shot: String, _ on: Bool) {
        reload("strike", shot, on ? "1" : "0")
    }

    func sortDaysByDate() { send("day", "sortbydate") }

    func link(scene: String, toLocation place: String) {
        reload("addscenelocation", scene, place)
    }

    func unlink(scene: String, fromLocation place: String) {
        reload("removescenelocation", scene, place)
    }

    /// The places a scene is shot at, in the film's own order.
    func locations(ofScene id: String) -> [Engine.Location] {
        guard let scene = scene(id) else { return [] }
        let linked = Set(scene.locations)
        return locations.filter { linked.contains($0.id) }
    }

    // ---- mood boards --------------------------------------------------------
    //
    // A board is an owner like any other, so the pictures on one arrive and
    // leave through the same `paste`, `detach` and `movemedia` a location's
    // photographs use. Only the three commands that make and name a board are
    // its own.

    var boards: [Engine.Board] { view?.boards ?? [] }

    func board(_ id: String) -> Engine.Board? { boards.first { $0.id == id } }

    /// The boards a scene hangs, in the film's own order.
    func boards(ofScene id: String) -> [Engine.Board] {
        guard let scene = scene(id) else { return [] }
        let linked = Set(scene.boards)
        return boards.filter { linked.contains($0.id) }
    }

    /// Makes a board, and hands back the one that was not there a moment ago —
    /// asked of the answer rather than guessed at from the order, the same way
    /// a new location is found.
    @discardableResult
    func addBoard(named name: String) -> Engine.Board? {
        let before = Set(boards.map(\.id))
        reload("addboard", name)
        return boards.first { !before.contains($0.id) }
    }

    func renameBoard(_ id: String, to name: String) {
        reload("renameboard", id, name)
    }

    /// Takes the wall down. The pictures are addressed by their contents and
    /// stay in the project.
    func deleteBoard(_ id: String) {
        reload("deleteboard", id)
    }

    /// How the wall fills each tile — `original`, `square` or `project`.
    func setBoard(_ id: String, _ field: String, to value: String) {
        reload("set", id, field, value)
    }

    func link(scene: String, to board: String) {
        reload("addsceneboard", scene, board)
    }

    func unlink(scene: String, from board: String) {
        reload("removesceneboard", scene, board)
    }

    /// A photograph on a board. Sized the way a location's is — a wall is
    /// looked at full screen, not squinted at in a filmstrip.
    func attach(_ image: UIImage, toBoard id: String) {
        attach(Media.shrunk(image, longest: 1600), to: id)
    }

    func attach(_ data: Data, named: String = "", toBoard id: String) {
        attach(Media.shrunk(data, longest: 1600), to: id, named: named)
    }

}
