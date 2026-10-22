import SwiftUI
import AppIntents
import UniformTypeIdentifiers
import WidgetKit

@main
struct ShotlisterApp: App {
    @StateObject private var projects = Projects()

    init() {
        // A Control Center button's address goes where a Shortcuts action's does.
        MainActor.assumeIsolated { ControlRouter.handler = { LinkInbox.shared.url = $0 } }
    }

    /// A checking door, the way the Mac app has them. `--floorplan` draws a
    /// hand-built room; `--floorplan <path>` draws a real scan's measurements,
    /// which is the only way to see what RoomPlan actually produces without
    /// standing in the room it produced them from.
    static var checkingScan: String? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--floorplan") else { return nil }
        let next = arguments.index(after: flag)
        if next < arguments.endIndex, !arguments[next].hasPrefix("--") { return arguments[next] }
        // An empty path asks the engine for its hand-built sample room.
        return ""
    }

    /// `--avscript <film> <shot>`: a film in the app's own Documents, its
    /// script screen following that shot — the one way to look at a
    /// commercial's script in a simulator without picking a folder by hand.
    static var checkingScript: (film: String, shot: String)? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--avscript"), flag + 2 < arguments.count else { return nil }
        return (arguments[flag + 1], arguments[flag + 2])
    }

    /// `--film <film> [tab]`: a film in the app's own Documents, open on one
    /// tab (0 Shot List, 1 Locations, 2 References, 3 Schedule, 4 Script, 5 Library,
    /// 6 Diagrams) — the way to
    /// watch a real film's pictures come in on a simulator, which cannot pick
    /// an iCloud folder by hand.
    static var checkingFilm: (film: String, tab: Int)? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--film"), flag + 1 < arguments.count else { return nil }
        let tab = flag + 2 < arguments.count ? Int(arguments[flag + 2]) ?? 0 : 0
        return (arguments[flag + 1], tab)
    }

    /// `--shootingorder <film>`: a film in Documents, its shot list sorted
    /// by Shooting Order — the one way to see it in a simulator.
    static var checkingOrder: String? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--shootingorder"), flag + 1 < arguments.count else { return nil }
        return arguments[flag + 1]
    }

    /// `--shotpage <film in Documents> <shot>` opens one shot's own page.
    static var checkingShot: (film: String, shot: String)? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--shotpage"), flag + 2 < arguments.count else { return nil }
        return (arguments[flag + 1], arguments[flag + 2])
    }

    var body: some Scene {
        WindowGroup {
            Group {
            // A checking door, the way the Mac app has them: nothing in the app
            // reaches this, and it exists because the floor plan cannot
            // otherwise be looked at without a room and a LiDAR sensor.
            if let scan = Self.checkingScan {
                CheckingPlan(path: scan)
            } else if let page = Self.checkingShot {
                CheckingShot(film: page.film, shot: page.shot)
            } else if let script = Self.checkingScript {
                CheckingScript(film: script.film, shot: script.shot)
            } else if let at = CommandLine.arguments.firstIndex(of: "--exportsheet"),
                      at + 1 < CommandLine.arguments.count {
                CheckingExport(film: CommandLine.arguments[at + 1])
            } else if let at = CommandLine.arguments.firstIndex(of: "--settingsof"),
                      at + 1 < CommandLine.arguments.count {
                CheckingSettings(film: CommandLine.arguments[at + 1],
                                 page: at + 2 < CommandLine.arguments.count && !CommandLine.arguments[at + 2].hasPrefix("-")
                                    ? CommandLine.arguments[at + 2] : "")
            } else if let film = Self.checkingOrder {
                CheckingOrder(film: film)
            } else if let film = Self.checkingFilm {
                CheckingFilm(film: film.film, tab: film.tab)
            } else if CommandLine.arguments.contains("--widgetfaces") {
                CheckingWidgetFaces()
            } else if let look = LookCheck.asked {
                LookCheck(asked: look)
            } else {
                ProjectsView()
                    .environmentObject(projects)
            }
            }
            // The films list for every door, checking ones too: the film's
            // own menu lists the other films and switches to one.
            .environmentObject(projects)
            // **The light the app draws in**, his choice and dark by default
            // — here rather than inside the film, so the film list and every
            // checking door are dressed the same as the app itself.
            .appearance()
        }
    }
}

/// The way in: which project, out of the ones in iCloud Drive.
///
/// The Mac opens a project by double-clicking it. The phone cannot — iOS hands
/// an app a folder only when somebody picks it — so **the folder his films live
/// in is picked once, and every film in it turns up on its own**, including the
/// ones started on the Mac after that.
struct ProjectsView: View {
    @EnvironmentObject private var projects: Projects
    @State private var picking = false
    /// **The films on his relay that are not on this phone yet**, listed
    /// under the ones that are. His ask, 2026-09-16: *"what is in the relay
    /// should just be in the projects."* Until then they were behind an
    /// *Open from relay…* sheet, which was a second list of the same films.
    @State private var onRelay: [Relay.Film] = []
    /// The one coming down. One at a time: a list of his own films, not a
    /// download manager.
    @State private var arriving: Relay.Film?
    @State private var relayTrouble: String?
    @State private var settingUpSync = false
    @State private var phoneSettings = false
    @State private var newProject = false
    @State private var makesProjects = false
    /// The film whose Delete is being asked about.
    @State private var deleting: Projects.Known?
    /// The film being archived or deleted, so its row shows a spinner and
    /// nothing else can start.
    @State private var busy: String?
    @State private var note: String?
    /// Set once a Projects Console link has chosen the film, so the launch
    /// that carried it does not reopen the last one over the top.
    @State private var followedLink = false
    /// The project on screen, if one is. Presented rather than pushed: inside a
    /// project the phone is a different tool with its own tabs, and a project
    /// wearing the Projects list's navigation bar was how the tabs lost their
    /// titles and their Add button.
    @State private var open: Projects.Known?
    @State private var complaint: String?
    /// The film whose *Offload* is being asked about.
    @State private var offloading: Projects.Known?
    /// An offloaded film whose pictures would not come down, asked about:
    /// open it without them, or not. The reason is the carrier's own words.
    @State private var stuck: (film: Projects.Known, why: String)?
    /// **How far a long one has got** — checking pictures against the relay,
    /// or bringing them back. Drawn beside the film as a count.
    @State private var stage: (what: String, done: Int, total: Int)?
    /// **What the Projects Console knows of each film** (stage, type, colour,
    /// next shoot), which is how the Home Screen groups them.
    @StateObject private var records = HomeRecords()
    @ObservedObject private var cards = PhoneCards.shared
    @State private var filter = ""
    @State private var showArchived = false
    @AppStorage("home.sort") private var sort = HomeSort.next.rawValue
    @FocusState private var filtering: Bool

    var body: some View {
        NavigationStack {
            homeList
            .navigationTitle("Projects")
            // Straight back into what he was doing. The list of projects is a
            // thing you visit once a film, not a doorway you pass through every
            // time you open the app.
            .task {
                #if targetEnvironment(simulator)
                // A checking run on a fresh install watches the app's own folder
                // without a tap: `-UseOwnFolder 1`.
                if UserDefaults.standard.bool(forKey: "UseOwnFolder"), !projects.watchingOwnFolder { projects.useOwnFolder() }
                #endif
                projects.rescan()
                Task { await records.refresh() }
                Task { await cards.refresh() }
                await lookAtRelay()
                // **A link from the Projects Console wins** over reopening the
                // last film: `follow` has already chosen where this goes.
                #if targetEnvironment(simulator)
                // A checking run performs an action as Shortcuts would:
                // `--intent film CHB schedule`, `--intent shortcut 1`.
                let args = CommandLine.arguments
                if let i = args.firstIndex(of: "--intent"), i + 2 < args.count {
                    if args[i + 1] == "film" {
                        var action = OpenFilm()
                        action.film = FilmEntity(id: args[i + 2])
                        action.page = i + 3 < args.count ? PageChoice(rawValue: args[i + 3]) ?? .shotList : .shotList
                        _ = try? await action.perform()
                    } else if args[i + 1] == "photos" {
                        // Two made-up photos, as a share sheet would hand them over.
                        let made = [UIColor.systemOrange, .systemTeal].map { colour in
                            UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300)).jpegData(withCompressionQuality: 0.8) { ctx in
                                colour.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
                            }
                        }
                        var action = AddPhotos()
                        action.photos = made.enumerated().map { IntentFile(data: $1, filename: "made-\($0).jpg", type: .jpeg) }
                        action.film = FilmEntity(id: args[i + 2])
                        _ = try? await action.perform()
                    } else if args[i + 1] == "next" {
                        let said = NextShootDayIntent.answer(film: args[i + 2] == "any" ? nil : args[i + 2])
                        try? said.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("next-shoot-day.txt"),
                                        atomically: true, encoding: .utf8)
                    } else if args[i + 1] == "control" {
                        _ = try? await OpenFromControl(slot: Int(args[i + 2]) ?? 0).perform()
                    } else {
                        var action = OpenLockShortcut()
                        action.slot = SlotChoice(rawValue: Int(args[i + 2]) ?? 1) ?? .one
                        _ = try? await action.perform()
                    }
                }
                #endif
                guard open == nil, !followedLink, let recent = projects.all.first,
                      recent.lastOpened > .distantPast else { return }
                // **Not a film in the cloud.** Reopening it would start a
                // download nobody asked for; it waits on the list for a tap.
                guard !projects.away.contains(recent.id) else { return }
                // Only a film that can actually be opened. A remembered
                // folder iOS will not hand back used to be reopened at every
                // launch, straight into the failure screen.
                guard let folder = projects.resolve(recent) else { projects.forget(recent); return }
                folder.release()
                open = recent
            }
            // **`shotlister://film?page=…&film=…`** — the Projects Console's
            // *Open in Shotlister*, and the same address the Mac answers.
            .onOpenURL { follow($0) }
            // A Shortcuts action (`AppShortcuts.swift`), on arrival or while open.
            .onReceive(LinkInbox.shared.$url) { url in
                guard let url else { return }
                DispatchQueue.main.async { LinkInbox.shared.url = nil }
                follow(url)
            }
            // A film started on the Mac while the app sat in a pocket should be
            // on the list by the time he looks.
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.willEnterForegroundNotification)) { _ in
                projects.rescan()
                Task { await records.refresh() }
                Task { await lookAtRelay() }
            }
            .refreshable {
                projects.rescan()
                await records.refresh()
                await cards.refresh()
                await lookAtRelay()
            }
            // **This iPhone's own settings** (`design/42-one-home`):
            // Appearance, Sync, the films folder.
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { phoneSettings = true } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("phone.settings")
                }
                // **New Project**, while the server makes projects (the Mac's).
                if makesProjects {
                    ToolbarItem(placement: .primaryAction) {
                        Button { newProject = true } label: { Label("New Project", systemImage: "plus") }
                            .accessibilityIdentifier("phone.newproject")
                    }
                }
            }
            .task { makesProjects = await NewProjectDoor.on() }
            .sheet(isPresented: $newProject) {
                NewProjectPhone(folder: projects.filmsFolder ?? URL.documentsDirectory) { url in
                    projects.rescan()
                    open(url)
                }
            }
            .sheet(isPresented: $phoneSettings) {
                PhoneSettings(chooseFolder: { picking = true },
                              syncChanged: { Task { await lookAtRelay() } })
                    .environmentObject(projects)
                    .presentationBackground(Style.page)
            }
            .sheet(isPresented: $picking) {
                FolderPicker { url in
                    picking = false
                    open(url)
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $settingUpSync) {
                SyncSetupView { Task { await lookAtRelay() } }
            }
            .fullScreenCover(item: $open, onDismiss: {
                // **After the film has closed**, never while its engine is
                // open on the folder: a fate that arrived mid-film closes it
                // first and is followed here.
                if let (film, fate) = projects.followAfterClose {
                    projects.followAfterClose = nil
                    note = projects.follow(film, fate: fate)
                }
                // **Switch Film**, from the film's own menu: the next one
                // opens once this one is fully closed.
                if let next = projects.switchTo {
                    projects.switchTo = nil
                    if projects.away.contains(next.id) {
                        bringBack(next, thenOpen: true)
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { open = next }
                    }
                }
                Task { await lookAtRelay() }
            }) { entry in
                ProjectView(entry: entry)
                    .environmentObject(projects)
            }
            .confirmationDialog("Delete \(deleting?.name ?? "this project")?",
                                isPresented: Binding(get: { deleting != nil },
                                                     set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let entry = deleting { delete(entry) }
                    deleting = nil
                }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: {
                // What it costs — the one thing a label cannot say. The Mac's
                // words, for the Mac's own delete.
                Text("Deletes from iPhone, relay, Mac and crew links")
            }
            .confirmationDialog("Offload \(offloading?.name ?? "this project")?",
                                isPresented: Binding(get: { offloading != nil },
                                                     set: { if !$0 { offloading = nil } }),
                                titleVisibility: .visible) {
                Button("Offload") {
                    if let entry = offloading { offload(entry) }
                    offloading = nil
                }
                Button("Cancel", role: .cancel) { offloading = nil }
            } message: {
                // What it costs: how much leaves the phone, and how it comes
                // back — the one thing the button cannot say.
                Text("\(offloadWeight) of pictures and clips leave this iPhone. They stay on your relay and come back when you open the project.")
            }
            .alert("Open \(stuck?.film.name ?? "this project") without its pictures?",
                   isPresented: Binding(get: { stuck != nil }, set: { if !$0 { stuck = nil } })) {
                Button("Open") {
                    if let film = stuck?.film { open = film }
                    stuck = nil
                }
                Button("Cancel", role: .cancel) { stuck = nil }
            } message: {
                Text(stuck?.why ?? "")
            }
            .alert("That folder isn't a project", isPresented: .constant(complaint != nil)) {
                Button("OK") { complaint = nil }
            } message: {
                Text(complaint ?? "")
            }
        }
    }

    // ---- the Home Screen -------------------------------------------------------

    /// One project on the list: a film on this phone, or one the relay holds
    /// that this phone does not, with what the Projects Console says of it.
    private struct Item: Identifiable {
        let id: String
        let name: String
        var local: Projects.Known?
        var cloud: Relay.Film?
        var row: HomeRecords.Row?
        var stage: String { row?.stage ?? "" }
    }

    private var items: [Item] {
        let pages = projects.consolePages
        let here = projects.all.map {
            Item(id: $0.id, name: $0.name, local: $0, cloud: nil, row: records.row(for: $0.name, consolePages: pages))
        }
        let away = awayFilms.map {
            Item(id: "relay:" + $0.id, name: $0.title, local: nil, cloud: $0, row: records.row(for: $0.title, consolePages: pages))
        }
        // **Jobs and projects with no modes on stay off this list** while
        // the server's modes switch is on (stage 5 step 4 B).
        // **A closed project is left out of Studio** (Close Project,
        // 2026-10-16): it lives on as a saved file in its Drive folder.
        return (here + away).filter { item in
            !cards.leavesOut(ids: [item.row?.page ?? "", item.cloud?.id ?? ""], name: item.name)
                && item.stage.lowercased() != "closed"
        }
    }

    private var query: String { filter.trimmingCharacters(in: .whitespaces).lowercased() }

    private func sorted(_ list: [Item]) -> [Item] {
        let byName: (Item, Item) -> Bool = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        switch HomeSort(rawValue: sort) ?? .next {
        case .name:
            return list.sorted(by: byName)
        case .recent:
            func opened(_ i: Item) -> Date { i.local?.lastOpened ?? .distantPast }
            return list.sorted { opened($0) == opened($1) ? byName($0, $1) : opened($0) > opened($1) }
        case .next:
            // The console's rule: shoots to come first, soonest on top; then
            // the ones past, latest first; then the undated, by name.
            let today = Calendar.current.startOfDay(for: .now)
            func key(_ i: Item) -> (Int, Double, String) {
                guard let shoot = i.row?.shoot else { return (2, 0, i.name.lowercased()) }
                if shoot.end >= today { return (0, shoot.start.timeIntervalSince1970, i.name.lowercased()) }
                return (1, -shoot.start.timeIntervalSince1970, i.name.lowercased())
            }
            return list.sorted { key($0) < key($1) }
        }
    }

    private var matching: [Item] {
        let list = items.filter { query.isEmpty || $0.name.lowercased().contains(query) || ($0.row?.kind.lowercased().contains(query) ?? false) }
        return sorted(list)
    }

    /// Active, Development, Post, Released, then what has no record. Archived
    /// has its own group below, behind a button.
    private var groups: [(title: String, items: [Item])] {
        let list = matching
        guard !records.rows.isEmpty else { return [("", list)] }
        let live = HomeRecords.Row.stages.filter { $0 != "Archived" }
        let known = Set(HomeRecords.Row.stages)
        var out = live.map { stage in (stage, list.filter { $0.stage == stage }) }
        out.append(("Other", list.filter { !known.contains($0.stage) }))
        return out.filter { !$0.1.isEmpty }
    }

    /// **A project on the shared record is archived and deleted in Projects
    /// Console** (the Mac's `askConsole`): that is where every part of it is
    /// taken down together. A Studio-only project still goes from here.
    private func archiveOrAsk(_ item: Item, _ entry: Projects.Known) {
        if let row = item.row { askConsole(row, "archive", item.name) } else { archive(entry) }
    }

    private func remove(_ item: Item, _ entry: Projects.Known) {
        if let row = item.row { askConsole(row, "delete", item.name) } else { deleting = entry }
    }

    private func askConsole(_ row: HomeRecords.Row, _ action: String, _ name: String) {
        var parts = URLComponents()
        parts.scheme = "projectsconsole"
        parts.host = "project"
        parts.queryItems = [URLQueryItem(name: "page", value: row.page), URLQueryItem(name: "name", value: name),
                            URLQueryItem(name: "action", value: action)]
        if let link = parts.url { UIApplication.shared.open(link) }
    }

    private var archivedItems: [Item] { matching.filter { $0.stage == "Archived" } }
    private var archivedCount: Int { items.filter { $0.stage == "Archived" }.count + projects.archived.count }

    private func shootLine(_ shoot: (start: Date, end: Date)) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let start = f.string(from: shoot.start), end = f.string(from: shoot.end)
        return start == end ? start : "\(start) – \(end)"
    }

    private func line(_ item: Item) -> String {
        if busy == item.id, let stage { return "\(stage.what) \(stage.done) of \(stage.total)" }
        var parts: [String] = []
        if item.local == nil || projects.away.contains(item.local?.id ?? "") { parts.append("In the Cloud") }
        if let kind = item.row?.kind, !kind.isEmpty { parts.append(kind) }
        if let row = item.row, row.daysToShoot != nil, let shoot = row.shoot {
            parts.append(shootLine(shoot))
        } else if parts.isEmpty, let opened = item.local?.lastOpened, opened > .distantPast {
            parts.append(opened.formatted(.relative(presentation: .named)))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func homeRow(_ item: Item) -> some View {
        let mark = item.local?.mark ?? item.cloud.flatMap {
            $0.markPath.isEmpty ? nil : FilmMark(path: $0.markPath, colour: $0.markColour)
        }
        let away = item.local.map { projects.away.contains($0.id) } ?? true
        let working = busy == item.id || (item.cloud != nil && arriving == item.cloud)
        let tap = Button {
            if let film = item.cloud {
                fetch(film)
            } else if let entry = item.local {
                // **In the cloud: the pictures first, then the film.**
                if away { bringBack(entry, thenOpen: true) } else { open = entry }
            }
        } label: {
            HomeRow(name: item.name, mark: mark, colour: item.row?.colour ?? "", type: item.row?.type ?? "",
                    line: line(item), days: working ? nil : item.row?.daysToShoot,
                    end: working ? .busy : (away ? .cloud : .chevron))
        }
        .buttonStyle(.plain)
        .disabled(busy != nil || arriving != nil)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        if let entry = item.local {
            tap
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { remove(item, entry) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button { archiveOrAsk(item, entry) } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .tint(.orange)
                }
                // **Where the pictures live**, on the other edge from the
                // two that take a film off the list: this one keeps it.
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if away {
                        Button { bringBack(entry, thenOpen: false) } label: {
                            Label("Download", systemImage: "icloud.and.arrow.down")
                        }
                        .tint(.accentColor)
                    } else {
                        Button { offloading = entry } label: {
                            Label("Offload", systemImage: "icloud.and.arrow.up")
                        }
                        .tint(.indigo)
                    }
                }
                // **The same three on a long press** (2026-10-09): a swipe
                // shows nothing until it is done, so nothing said they
                // were there.
                .contextMenu {
                    if away {
                        Button { bringBack(entry, thenOpen: false) } label: {
                            Label("Download", systemImage: "icloud.and.arrow.down")
                        }
                    } else {
                        Button { offloading = entry } label: {
                            Label("Offload", systemImage: "icloud.and.arrow.up")
                        }
                    }
                    Button { archiveOrAsk(item, entry) } label: {
                        Label(item.row == nil ? "Archive" : "Archive in Console", systemImage: "archivebox")
                    }
                    Button(role: .destructive) { remove(item, entry) } label: {
                        Label(item.row == nil ? "Delete" : "Delete in Console", systemImage: "trash")
                    }
                }
        } else {
            tap
        }
    }

    /// The console's filter field, with the sort folded into the end of it.
    private var filterField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Style.ink3)
            TextField("Filter projects", text: $filter)
                .font(.system(size: 15))
                .focused($filtering)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !filter.isEmpty {
                Button { filter = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear filter")
            }
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(HomeSort.allCases) { Text($0.label).tag($0.rawValue) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Style.ink2)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Sort")
        }
        .padding(.leading, 12)
        .padding(.trailing, 2)
        .frame(height: 42)
        .background(Style.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(filtering ? Color.accentColor : Style.rule, lineWidth: filtering ? 1.5 : 1))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var homeList: some View {
        List {
            filterField

            if items.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No projects yet")
                            .font(.kitRowStrong)
                        // The one thing he has to do himself, once.
                        Button("Choose Folder") { picking = true }
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.vertical, 6)
                }
            } else if matching.isEmpty && archivedItems.isEmpty {
                Text("Nothing matches “\(filter)”")
                    .font(.system(size: 15))
                    .foregroundStyle(Style.ink3)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(groups, id: \.title) { group in
                Section {
                    ForEach(group.items) { homeRow($0) }
                } header: {
                    if !group.title.isEmpty { HomeHeader(title: group.title, count: group.items.count) }
                }
                .listSectionSeparator(.hidden)
            }

            // **Archived**: the projects the console has archived, which open
            // as any other, and the bin — a film off the relay and off the
            // list, which Put Back moves up a level.
            if showArchived || (!query.isEmpty && !archivedItems.isEmpty) {
                Section {
                    ForEach(archivedItems) { homeRow($0) }
                    if query.isEmpty {
                        ForEach(projects.archived, id: \.self) { film in
                            HStack(spacing: 13) {
                                Image(systemName: "archivebox")
                                    .foregroundStyle(Style.ink3)
                                    .frame(width: 36, height: 36)
                                Text(film.deletingPathExtension().lastPathComponent)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Style.ink2)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .frame(minHeight: 58)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button { restore(film) } label: {
                                    Label("Put Back", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.accentColor)
                            }
                        }
                    }
                } header: {
                    HomeHeader(title: "Archived",
                               count: archivedItems.count + (query.isEmpty ? projects.archived.count : 0))
                }
                .listSectionSeparator(.hidden)
            }
            if archivedCount > 0 && query.isEmpty {
                Button(showArchived ? "Hide archived" : "Show \(archivedCount) archived") {
                    withAnimation(.easeOut(duration: 0.2)) { showArchived.toggle() }
                }
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // Nothing can be listed from the relay until this phone has
            // its password — the one thing he has to do himself, once.
            if !relayReady {
                Button { settingUpSync = true } label: {
                    Label("Set Up Sync…", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else if let relayTrouble {
                Text(relayTrouble)
                    .font(.kitLabel)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            if let note {
                Text(note)
                    .font(.kitLabel)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .environment(\.defaultMinListHeaderHeight, 0)
        .scrollContentBackground(.hidden)
        .background(Style.page)
        .scrollDismissesKeyboard(.immediately)
    }

    // ---- the relay's films ---------------------------------------------------

    /// **Both halves, not just the password.** The Keychain survives an app
    /// being reinstalled and `UserDefaults` does not, so a phone can have the
    /// word and no idea where to send it.
    private var relayReady: Bool {
        Relay.token != nil && Relay.address(for: nil) != nil
    }

    /// The relay's films that this phone does not have.
    private var awayFilms: [Relay.Film] {
        onRelay.filter { film in
            !projects.all.contains { $0.name.caseInsensitiveCompare(film.title) == .orderedSame }
        }
    }

    private func lookAtRelay() async {
        guard relayReady else { return }
        do {
            let listing = try await Relay.films()
            relayTrouble = nil
            // **Do here what was done elsewhere**, before the list draws.
            let followed = await projects.follow(listing: listing)
            if let last = followed.last { note = last }
            onRelay = listing.filter { $0.gone == nil }
        } catch {
            relayTrouble = error.localizedDescription
        }
    }

    private func archive(_ entry: Projects.Known) {
        busy = entry.id
        note = nil
        Task { @MainActor in
            defer { busy = nil }
            do {
                let pictures = try await projects.archive(entry)
                note = "Archived \(entry.name)"
                await lookAtRelay()
            } catch {
                note = error.localizedDescription
            }
        }
    }

    private var offloadWeight: String {
        ByteCountFormatter.string(fromByteCount: Int64(offloading.map { projects.weight($0) } ?? 0),
                                  countStyle: .file)
    }

    /// **Offload, after the question.** The check asks the relay about every
    /// log and picture first; a refusal is one line under the list and the
    /// film is exactly as it was.
    private func offload(_ entry: Projects.Known) {
        busy = entry.id
        note = nil
        Task { @MainActor in
            defer { busy = nil; stage = nil }
            do {
                let gone = try await projects.offload(entry) { done, total in
                    stage = ("Checking", done, total)
                }
                note = "Offloaded \(entry.name)"
            } catch {
                note = error.localizedDescription
            }
        }
    }

    /// **The pictures back, then — when a tap on the row asked — the film.**
    ///
    /// With no connection he decides: the list is on the phone and opens
    /// without its pictures, and the film's own sync fetches them when it can.
    /// A film taken off the relay elsewhere is the exception, and says so.
    /// **Open the film a Projects Console link names.** By folder name — the
    /// phone has no way to read a film's linked page without opening it, and
    /// the console sends the name of the folder it found the film in.
    private func follow(_ url: URL) {
        guard url.scheme == "shotlister", url.host == "film" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let given = items.first { $0.name == "film" }?.value ?? ""
        let page = (items.first { $0.name == "page" }?.value ?? "")
            .replacingOccurrences(of: "-", with: "").lowercased()
        // The film the page was last seen on, then the folder name the
        // console found it in.
        let name = projects.consolePages[page] ?? given
        // A lock screen shortcut also names the page to open at.
        let place = (items.first { $0.name == "place" }?.value).flatMap { Place(key: $0) }
        followedLink = true
        projects.rescan()
        guard let entry = projects.all.first(where: {
            !name.isEmpty && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            note = name.isEmpty ? "No project named in that link" : "\(name) is not on this iPhone"
            return
        }
        if let place { PlaceRoute.shared.wanted = (entry.name, place) }
        // A sheet left up on Projects (Settings, say) would hold the film
        // back: iOS will not present it over one. Down first, then the film.
        if phoneSettings || settingUpSync || picking {
            phoneSettings = false; settingUpSync = false; picking = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { follow(url) }
            return
        }
        if projects.away.contains(entry.id) { bringBack(entry, thenOpen: true); return }
        if let showing = open, showing.id != entry.id {
            // One film closes before the next opens.
            open = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { open = entry }
        } else {
            open = entry
        }
    }

    private func bringBack(_ entry: Projects.Known, thenOpen: Bool) {
        busy = entry.id
        note = nil
        Task { @MainActor in
            defer { busy = nil; stage = nil }
            do {
                try await projects.bringBack(entry) { done, total in
                    stage = ("Downloading", done, total)
                }
                if thenOpen { open = entry } else { note = "Downloaded \(entry.name)" }
            } catch {
                if case Relay.Trouble.gone = error {
                    note = error.localizedDescription
                    await lookAtRelay()
                } else if thenOpen {
                    stuck = (entry, error.localizedDescription)
                } else {
                    note = error.localizedDescription
                }
            }
        }
    }

    private func delete(_ entry: Projects.Known) {
        busy = entry.id
        note = nil
        Task { @MainActor in
            defer { busy = nil }
            do {
                try await projects.delete(entry)
                note = "Deleted \(entry.name)"
                await lookAtRelay()
            } catch {
                note = error.localizedDescription
            }
        }
    }

    private func restore(_ film: URL) {
        note = nil
        busy = film.path
        Task { @MainActor in
            defer { busy = nil }
            do { try await projects.restore(film) } catch { note = error.localizedDescription }
        }
    }

    /// **The list only.** A clone fetches the manifest and every change log
    /// and stops there — everything needed to *open* a film. The photographs
    /// are the hundred megabytes and come afterwards on the same *Sync now*
    /// as always, so a film opens on a location's connection in seconds.
    private func fetch(_ film: Relay.Film) {
        // **Into the folder he already chose**, so a fetched film lands beside
        // the others. **Its own Documents folder when he has not chosen one**
        // — a phone that has never seen one of his films has no folder to
        // choose yet, and that folder is *On My iPhone ▸ Shotlister* in
        // Files, which is where a film belongs on a phone anyway.
        var landing = projects.filmsFolder
        if landing == nil {
            let documents = URL.documentsDirectory
            try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
            projects.watchFolder(documents)
            landing = projects.filmsFolder ?? documents
        }
        guard let folder = landing else {
            relayTrouble = "Choose a projects folder"
            return
        }
        arriving = film
        Task { @MainActor in
            defer { arriving = nil }
            do {
                let arrived = try await Relay.clone(film, into: folder)
                projects.rescan()
                open(arrived)
            } catch {
                relayTrouble = error.localizedDescription
            }
        }
    }

    /// What he picked decides what happens.
    ///
    /// **A film opens. A folder with films in it becomes the folder to watch**,
    /// and every film in it — the ones there now and the ones the Mac makes
    /// later — turns up on the list without being asked for.
    ///
    /// A folder with no films in it is refused rather than quietly made into
    /// one. `sl_open` creates a project when it finds nothing, which is right
    /// on the Mac where the path was chosen deliberately; here the path came
    /// from a file browser, and one wrong tap would scatter a manifest and a
    /// changes folder into, say, his Documents.
    private func open(_ url: URL) {
        let reachable = url.startAccessingSecurityScopedResource()
        defer { if reachable { url.stopAccessingSecurityScopedResource() } }

        let manager = FileManager.default
        let isProject = url.pathExtension == "shotlist"
            || manager.fileExists(atPath: url.appendingPathComponent("manifest.json").path)

        if isProject {
            guard let entry = projects.remember(url: url) else {
                complaint = "iOS wouldn't give the app lasting access to that folder. Try picking it again."
                return
            }
            open = entry
            return
        }

        let films = (try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                                                      options: [.skipsHiddenFiles])) ?? []
        guard films.contains(where: { $0.pathExtension == "shotlist" }) else {
            complaint = "No projects in \(url.lastPathComponent)"
            return
        }
        projects.watchFolder(url)
    }
}


/// A commercial's script screen on its own, following one shot.
private struct CheckingScript: View {
    let shot: String
    @StateObject private var session: Session

    init(film: String, shot: String) {
        self.shot = shot
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(film + ".shotlist")
        _session = StateObject(wrappedValue: Session(
            entry: .init(name: film, bookmarkKey: "checking", lastOpened: .now),
            folder: OpenFolder(url: url, scoped: false)))
    }

    var body: some View {
        if let row = session.groups.flatMap(\.rows).first(where: { $0.number == shot }),
           let id = row.sceneId, let scene = session.scene(id) {
            AVScriptPane(scene: scene, following: row.id)
                .environmentObject(session)
        } else {
            Text("No shot \(shot)")
        }
    }
}

/// One shot's own page, for its fields (the Shoot Day menu, 2026-10-06).
private struct CheckingShot: View {
    let shot: String
    @StateObject private var session: Session
    @StateObject private var frames: Frames

    init(film: String, shot: String) {
        self.shot = shot
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(film + ".shotlist")
        let session = Session(
            entry: .init(name: film, bookmarkKey: "checking", lastOpened: .now),
            folder: OpenFolder(url: url, scoped: false))
        _session = StateObject(wrappedValue: session)
        _frames = StateObject(wrappedValue: Frames(engine: session.engine, folder: url))
    }

    var body: some View {
        NavigationStack {
            if let row = session.groups.flatMap(\.rows).first(where: { $0.number == shot }),
               let id = row.sceneId, let scene = session.scene(id) {
                ShotDetailView(sceneId: scene.id, heading: scene.heading, showing: row.id)
            } else {
                Text("No shot \(shot)")
            }
        }
        .environmentObject(session)
        .environmentObject(frames)
    }
}

/// A whole film on its own, for watching its pictures arrive.
private struct CheckingFilm: View {
    @StateObject private var session: Session
    @StateObject private var frames: Frames
    @State private var tab: Int

    init(film: String, tab: Int) {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(film + ".shotlist")
        let session = Session(entry: .init(name: film, bookmarkKey: "checking", lastOpened: .now),
                              folder: OpenFolder(url: url, scoped: false))
        _session = StateObject(wrappedValue: session)
        _frames = StateObject(wrappedValue: Frames(engine: session.engine, folder: url))
        _tab = State(initialValue: tab)
    }

    var body: some View {
        // The numbers were fixed before the bar was his to arrange; each
        // still opens the same place, pinned or not.
        FilmTabs(start: [0: .shotList, 1: .locations, 2: .references, 3: .schedule,
                         4: .script, 5: .library, 6: .diagrams, 7: .shelf(.creative),
                         8: .film][tab] ?? .shotList)
        .environmentObject(session)
        .environmentObject(frames)
    }
}

/// `--exportsheet <film> [--exportset arrange=schedule;days=12-18+22]`:
/// the Export screen on a film in Documents, set from outside, for a
/// photograph.
private struct CheckingExport: View {
    @StateObject private var session: Session

    init(film: String) {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(film + ".shotlist")
        _session = StateObject(wrappedValue: Session(entry: .init(name: film, bookmarkKey: "checking", lastOpened: .now),
                                                     folder: OpenFolder(url: url, scoped: false)))
    }

    var body: some View {
        ExportSheet().environmentObject(session)
    }
}

/// A film's shot list in shooting order, on its own.
private struct CheckingOrder: View {
    @StateObject private var session: Session
    @StateObject private var frames: Frames

    init(film: String) {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(film + ".shotlist")
        let opened = Session(entry: .init(name: film, bookmarkKey: "checking", lastOpened: .now),
                             folder: OpenFolder(url: url, scoped: false))
        opened.sortByShootingOrder()
        _session = StateObject(wrappedValue: opened)
        _frames = StateObject(wrappedValue: Frames(engine: opened.engine, folder: url))
    }

    var body: some View {
        NavigationStack { ShotListView() }
            .environmentObject(session)
            .environmentObject(frames)
    }
}

/// The floor plan on its own, for looking at without a room.
///
/// It has to open a project to have an engine to ask, since the plan arithmetic
/// lives there now. Any project will do — the plan comes from the scan file, not
/// from the document.
private struct CheckingPlan: View {
    let path: String
    @State private var plan: Plan?

    var body: some View {
        Group {
            if let plan {
                FloorPlanView(plan: plan)
            } else {
                ProgressView()
            }
        }
        .task {
            let scratch = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Checking.shotlist")
            guard let engine = try? Engine(path: scratch.path) else { return }
            plan = try? JSONDecoder().decode(Plan.self, from: engine.raw("floorplan", path))
        }
    }
}

/// `--widgetfaces [looks|info]`: every widget in every size, drawn in the
/// app. A simulator cannot be told to put a widget on its lock screen, so
/// this is how a change to how they look gets photographed. `looks` is the
/// first shortcut and the longest names in Badge, Film Colour and Eyebrow;
/// `info` is Shoot Day and Next Shots for the film they follow.
private struct CheckingWidgetFaces: View {
    private let page = CommandLine.arguments.drop { $0 != "--widgetfaces" }.dropFirst().first ?? "looks"
    private static let longest = LockShortcut(slot: 5, film: "Harbour Light Affair", place: "references",
                                              placeTitle: "Reference Images", symbol: "square.grid.2x2")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if page == "info" { info(sample: false) }
                else if page == "sample" { info(sample: true) }
                else { looks }
            }
            .padding()
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var looks: some View {
        let first = LockShortcuts.one(1)
        let shown = WidgetLook(rawValue: page).map { [$0] } ?? WidgetLook.allCases
        ForEach(shown) { look in
            Text(look.name).font(.kitLabel.bold()).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 10) {
                ForEach([first, Self.longest], id: \.slot) { base in
                    var s = base
                    let _ = (s.look = look.rawValue)
                    VStack(spacing: 8) {
                        frame(ShortcutFace(shortcut: s, size: .accessoryCircular), .accessoryCircular)
                        frame(ShortcutFace(shortcut: s, size: .accessoryRectangular), .accessoryRectangular)
                    }
                }
            }
            HStack(spacing: 10) {
                ForEach([first, Self.longest], id: \.slot) { base in
                    var s = base
                    let _ = (s.look = look.rawValue)
                    frame(ShortcutFace(shortcut: s, size: .systemSmall), .systemSmall,
                          fill: look == .colour ? Color(markHex: s.markColour ?? "#0A84FF") : nil)
                }
            }
        }
    }

    /// A day with shots on it, part got, today: what a shoot day looks like.
    private static let sample = FilmSnapshot(
        film: "Call Her Back", markPath: LockShortcuts.one(1).markPath, markColour: LockShortcuts.one(1).markColour,
        days: [.init(label: "Day 2", title: "", date: FilmSnapshot.read.string(from: .now), count: 23, got: 9,
                     scenes: ["12", "14", "15"], wrapped: false)],
        next: FilmSnapshots.followed(nil)?.next ?? [], written: .now)

    @ViewBuilder
    private func info(sample: Bool) -> some View {
        let film = sample ? Self.sample : FilmSnapshots.followed(InfoChoices.shootDayFilm)
        Text("Shoot Day · \(film?.film ?? "no project")").font(.kitLabel.bold()).foregroundStyle(.secondary)
        HStack(spacing: 10) {
            frame(ShootDayFace(film: film, size: .accessoryCircular), .accessoryCircular)
            frame(ShootDayFace(film: film, size: .accessoryRectangular), .accessoryRectangular)
        }
        frame(ShootDayFace(film: film, size: .accessoryInline).padding(.horizontal, 10), .accessoryInline)
        frame(ShootDayFace(film: film, size: .systemSmall), .systemSmall)
        Text("Next Shots").font(.kitLabel.bold()).foregroundStyle(.secondary)
        frame(NextShotsFace(film: FilmSnapshots.followed(InfoChoices.nextShotsFilm), size: .systemMedium), .systemMedium)
    }

    private func frame<V: View>(_ face: V, _ family: WidgetFamily, fill: Color? = nil) -> some View {
        let sizes: [WidgetFamily: CGSize] = [.accessoryCircular: .init(width: 72, height: 72),
                                             .accessoryRectangular: .init(width: 160, height: 72),
                                             .accessoryInline: .init(width: 300, height: 26),
                                             .systemSmall: .init(width: 158, height: 158),
                                             .systemMedium: .init(width: 338, height: 158)]
        let side = sizes[family] ?? .zero
        let round: CGFloat = family == .accessoryCircular ? 36 : family.isSystem ? 22 : 14
        return face
            .foregroundStyle(.white)
            .frame(width: side.width, height: side.height)
            .background(fill ?? (family.isSystem ? Color(white: 0.075) : Color.white.opacity(0.12)),
                        in: RoundedRectangle(cornerRadius: round))
    }
}

private extension WidgetFamily {
    var isSystem: Bool { self == .systemSmall || self == .systemMedium }
}


/// `--settingsof <film in Documents> [page]`: a project's Settings page on
/// its own, for a photograph. `-FakeCard <json>` lays a made-up project card
/// on the scratch copy first, so the record-backed rows can be seen offline.
private struct CheckingSettings: View {
    let page: String
    @StateObject private var session: Session

    init(film: String, page: String) {
        self.page = page
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(film + ".shotlist")
        let session = Session(entry: .init(name: film, bookmarkKey: "checking", lastOpened: .now),
                              folder: OpenFolder(url: url, scoped: false))
        // Read off the command line: a value in braces would be taken as a
        // property list by UserDefaults.
        func arg(_ flag: String) -> String? {
            let a = CommandLine.arguments
            guard let i = a.firstIndex(of: flag), i + 1 < a.count else { return nil }
            return a[i + 1]
        }
        if let card = arg("-FakeCard"), let engine = session.engine {
            let said = engine.raw(["card", card])
            FileHandle.standardError.write(Data("card: ".utf8) + said.prefix(300) + Data("\n".utf8))
            session.refresh()
        }
        if let kit = arg("-FakeKit") {
            session.takeKit(kit)
            session.setKitMode("follow")
        }
        _session = StateObject(wrappedValue: session)
    }

    var body: some View {
        NavigationStack {
            switch page {
            case "aspect": AspectRatioView()
            case "camera": SpecSheetView(sheet: session.specSheet)
            case "lists": ListsView()
            case "cameras": CamerasView()
            case "sequences": SequencesView()
            case "display": DisplaySheet()
            case "": ProjectSettingsForm()
            default: ListView(field: page)
            }
        }
        .environmentObject(session)
    }
}
