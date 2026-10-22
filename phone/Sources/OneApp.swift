import SwiftUI
import PDFKit

/// **The bar: his four pins and the Library** — Ref 1541 Stage B,
/// `design/33-one-app.html` section 1. His rulings, 2026-10-06:
///
/// - the portal's Library comes to the phone: everything the film holds, on
///   the same shelves the portal files it on — the film's own, renamed and
///   added to as he likes since 2026-10-10 (`shelvesOf` in `hub/src/front.js`);
/// - the other four buttons are pins, a whole shelf or a single page,
///   Shot List · Script · Schedule · Look until he changes them with Edit;
/// - his pins are his alone. The portal's sidebar, which the crew sees, is not
///   touched.
///
/// The film's own places stand on their shelves beside the portal's pages,
/// decks, look boards and documents, which come down the phone's line to the
/// portal (Stage C, `PortalLine`). Any one of those can be a pin: `.page`,
/// by the portal's key for it (a slug, or `doc:` and a document's name).
enum Place: Hashable, Identifiable {
    case shotList, script, schedule, locations, references, diagrams
    case shelf(Shelf)
    case library
    case page(String)
    /// The film's record (2026-10-06, his "everything should feel native"):
    /// its front page, its shoots, one shoot, and one shoot's spec sheet,
    /// People or Documents (`record("camera", "shoot-1")`).
    case film
    case shoots
    case shoot(String)
    case record(String, String)

    static func camera(_ shoot: String) -> Place { .record("camera", shoot) }
    static func people(_ shoot: String) -> Place { .record("people", shoot) }
    static func documents(_ shoot: String) -> Place { .record("documents", shoot) }

    var id: String { key }

    var key: String {
        switch self {
        case .shotList: return "shotlist"
        case .script: return "script"
        case .schedule: return "schedule"
        case .locations: return "locations"
        case .references: return "references"
        case .diagrams: return "diagrams"
        case .shelf(let shelf): return "shelf:" + shelf.id
        case .library: return "library"
        // The pins are kept as one comma-separated line, and a document's
        // name may hold a comma.
        case .page(let key):
            return "page:" + key.replacingOccurrences(of: "%", with: "%25").replacingOccurrences(of: ",", with: "%2C")
        case .film: return "film"
        case .shoots: return "shoots"
        case .shoot(let slug): return "shoot:" + slug
        case .record(let what, let shoot): return "record:\(what):\(shoot)"
        }
    }

    init?(key: String) {
        switch key {
        case "shotlist": self = .shotList
        case "script": self = .script
        case "schedule": self = .schedule
        case "locations": self = .locations
        case "references": self = .references
        case "diagrams": self = .diagrams
        case "library": self = .library
        case "film": self = .film
        case "shoots": self = .shoots
        case _ where key.hasPrefix("shoot:") && key.count > 6:
            self = .shoot(String(key.dropFirst(6)))
        case _ where key.hasPrefix("record:"):
            let parts = key.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, ["camera", "people", "documents"].contains(parts[1]) else { return nil }
            self = .record(String(parts[1]), String(parts[2]))
        case _ where key.hasPrefix("page:") && key.count > 5:
            self = .page(String(key.dropFirst(5)).replacingOccurrences(of: "%2C", with: ",").replacingOccurrences(of: "%25", with: "%"))
        default:
            // By id since 2026-10-10; a pin kept before then says the shelf's
            // starting name ("shelf:Look"), which finds the same shelf.
            guard key.hasPrefix("shelf:"), key.count > 6 else { return nil }
            self = .shelf(Shelf.named(String(key.dropFirst(6))))
        }
    }

    var title: String {
        switch self {
        case .shotList: return "Shot List"
        case .script: return "Script"
        case .schedule: return "Schedule"
        case .locations: return "Locations"
        case .references: return "Reference Images"
        case .diagrams: return "Diagrams"
        case .shelf(let shelf): return shelf.short
        case .library: return "Library"
        case .page(let key): return key.hasPrefix("doc:") ? String(key.dropFirst(4)) : key.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        case .film: return "Overview"
        case .shoots: return "Shoots"
        case .shoot(let slug): return slug.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        case .record(let what, _): return ["camera": "Camera Spec Sheet", "people": "People", "documents": "Documents"][what] ?? what
        }
    }

    var symbol: String {
        switch self {
        case .shotList: return "list.bullet.rectangle"
        case .script: return "doc.plaintext"
        case .schedule: return "calendar"
        case .locations: return "mappin.and.ellipse"
        case .references: return "square.grid.2x2"
        case .diagrams: return "pencil.and.ruler"
        case .shelf(let shelf): return shelf.symbol
        case .library: return "books.vertical"
        case .page: return "doc.text"
        case .film: return "film"
        case .shoots, .shoot: return "calendar.badge.clock"
        case .record(let what, _): return ["camera": "camera", "people": "person.2", "documents": "folder"][what] ?? "doc.text"
        }
    }

    /// Which shelf the film's own places stand on, as the portal files them
    /// (`SHELF_BUILT` in `hub/src/front.js`).
    var shelf: Shelf? {
        switch self {
        case .shotList, .script, .references: return .creative
        case .diagrams: return .technical
        case .schedule, .locations: return .logistical
        case .shoots, .shoot: return .logistical
        case .shelf, .library, .page, .film, .record: return nil
        }
    }

    /// Everything the film itself holds, in shelf order.
    static let built: [Place] = [.shotList, .script, .diagrams, .references, .schedule, .locations]

    /// What the bar holds until he says otherwise (his ruling, 2026-10-06).
    static let defaultPins = "shotlist,script,schedule,shelf:creative"
}

/// **A shelf of the portal's Library**, by its id; its name is the film's
/// (2026-10-10: *"the categories should be renamable, and I should be able to
/// add new ones"*). The seven every film starts with keep their ids, so the
/// Look tab is `look` whatever he calls it. Two shelves are the same shelf
/// when their ids are, whatever either was called when it was read.
struct Shelf: Hashable, Identifiable {
    let id: String
    var name: String

    static func == (a: Shelf, b: Shelf) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static let creative = Shelf(id: "creative", name: "Creative")
    static let technical = Shelf(id: "technical", name: "Technical")
    static let logistical = Shelf(id: "logistical", name: "Logistical")
    static let other = Shelf(id: "other", name: "Other")

    /// The four every film starts with (his ruling, 2026-10-11, replacing the
    /// seven before them): the Library with no signal and nothing kept, or a
    /// portal from before the film had its own.
    static let defaults: [Shelf] = [.creative, .technical, .logistical, .other]

    /// Where each of the old seven went, for a pin or a move that still says
    /// one of them.
    static let legacy = ["script": "creative", "look": "creative", "notes": "other", "camera": "technical",
                         "schedule": "logistical", "people": "logistical", "paperwork": "logistical",
                         "Script & Shots": "creative", "Look": "creative", "Notes": "other", "Camera": "technical",
                         "Schedule & Locations": "logistical", "People": "logistical", "Paperwork": "logistical"]

    /// A shelf by its id, or by one of the seven's starting names.
    static func named(_ said: String) -> Shelf {
        let said = legacy[said] ?? said
        return defaults.first { $0.id == said || $0.name == said } ?? Shelf(id: said, name: said)
    }

    /// One of the seven, which can be renamed but not removed.
    var builtIn: Bool { Self.defaults.contains(self) }

    /// The shelf's name where room is short: the bar.
    var short: String { name }

    var symbol: String {
        switch id {
        case "creative": return "square.grid.2x2"
        case "technical": return "camera"
        case "logistical": return "calendar"
        case "other": return "tray"
        default: return "tag"
        }
    }

    var places: [Place] { Place.built.filter { $0.shelf == self } }
}

/// **A page asked for from outside the film**: a lock screen shortcut
/// (`shotlister://film?film=…&place=…`). Named for its film, so a film that
/// is closing while the next one opens never takes the page meant for it.
final class PlaceRoute: ObservableObject {
    static let shared = PlaceRoute()
    @Published var wanted: (film: String, place: Place)?
}

/// **One film's bar** (his ask, 2026-10-11: *"each project should carry its
/// own tab bar and library layout"*). The four pins are kept under the film's
/// own name, so Edit on one film leaves every other as it was. A film that has
/// never been edited starts from the one set every film shared before this,
/// then goes its own way. (The Library's categories were already the film's
/// own: they come from its portal.)
final class BarPins: ObservableObject {
    private let key: String

    @Published var stored: String {
        didSet { UserDefaults.standard.set(stored, forKey: key) }
    }

    init(film: String) {
        key = "bar.pins." + film.lowercased()
        let kept = UserDefaults.standard
        stored = kept.string(forKey: key) ?? kept.string(forKey: "bar.pins") ?? Place.defaultPins
    }
}

/// The film, as tabs: his four pins, then the Library.
struct FilmTabs: View {
    @EnvironmentObject private var session: Session
    var start: Place?

    init(start: Place? = nil) { self.start = start }

    var body: some View {
        // Keyed by the film, so a film switched to starts on its own bar.
        FilmTabsBody(film: session.entry.name, start: start)
            .id(session.entry.name.lowercased())
    }
}

private struct FilmTabsBody: View {
    @StateObject private var bar: BarPins
    @EnvironmentObject private var session: Session
    /// The film's line to the portal: opened with the film, kept for its life.
    @StateObject private var portal = PortalLine()
    /// The shots a checking run's Add Edit Reference sheet is open for.
    @State private var checkingAdd: [String]?
    @ObservedObject private var route = PlaceRoute.shared
    @ObservedObject private var cards = PhoneCards.shared
    @State private var selection: String
    /// A place to show although it is not pinned: the checking flag's.
    var extra: Place?
    /// The Library tab's own trail, so a lock screen shortcut to a page that
    /// is not pinned opens it there, with Library one step back.
    @State private var libraryPath = NavigationPath()
    /// Photos a Shortcuts action brought for this film, until he says where.
    @ObservedObject private var photoInbox = PhotoInbox.shared
    @State private var dropping: [Data] = []

    init(film: String, start: Place? = nil) {
        let kept = BarPins(film: film)
        _bar = StateObject(wrappedValue: kept)
        // The film opens on its first pin, which is Shot List unless it has
        // been moved off the bar.
        let first = kept.stored.split(separator: ",").compactMap { Place(key: String($0)) }.first ?? .shotList
        var start = start
        #if targetEnvironment(simulator)
        // A checking run may open any place, a portal page too:
        // `-StartPlace page:lens-character`.
        if let asked = UserDefaults.standard.string(forKey: "StartPlace"), let place = Place(key: asked) { start = place }
        #endif
        _selection = State(initialValue: start?.key ?? first.key)
        extra = start
    }

    /// His pins, less any category he has since removed: the bar follows his
    /// categories as he rearranges them.
    private var pins: [Place] {
        let read = bar.stored.split(separator: ",").compactMap { Place(key: String($0)) }
        let all = read.isEmpty ? Place.defaultPins.split(separator: ",").compactMap { Place(key: String($0)) } : read
        let have = Set(portal.shelves.map(\.id))
        // **The bar follows the project's modes** (stage 5 step 4 B): a mode
        // that is off is not a tab; Script goes with Shot List.
        let relay = Relay.projectId(at: session.folder.url)
        let page = session.view?.project.consolePage ?? ""
        return all.filter { if case .shelf(let one) = $0 { return have.contains(one.id) } else { return true } }
            .filter { cards.shows($0, film: relay, page: page) }
    }

    private func keepOnAShownTab() {
        guard selection != Place.library.key, let place = Place(key: selection) else { return }
        let relay = Relay.projectId(at: session.folder.url)
        guard !cards.shows(place, film: relay, page: session.view?.project.consolePage ?? "") else { return }
        selection = pins.first?.key ?? Place.library.key
    }

    var body: some View {
        let shown = pins + (extra.map { e in pins.contains(e) || e == .library ? [] : [e] } ?? [])
        TabView(selection: $selection) {
            ForEach(shown) { place in
                NavigationStack {
                    PlaceView(place: place, root: true)
                        // The shoot picker under every tab's title (piece D).
                        .safeAreaInset(edge: .top, spacing: 0) { ShootPickerBar() }
                }
                    // The mockup's bar draws its glyphs in outline; iOS fills
                    // them unless told not to.
                    .tabItem {
                        Label(portal.title(of: place), systemImage: portal.symbol(of: place))
                            .environment(\.symbolVariants, .none)
                    }
                    .tag(place.key)
            }
            NavigationStack(path: $libraryPath) { LibraryView().environment(\.tabRoot, true) }
                .tabItem {
                    Label("Library", systemImage: Place.library.symbol)
                        .environment(\.symbolVariants, .none)
                }
                .tag(Place.library.key)
        }
        .environmentObject(portal)
        .environmentObject(bar)
        // **An Edit Reference playing** blooms over everything, tab bar too.
        .overlay { PhoneEditStage().ignoresSafeArea() }
        // `--editrefsheet 34C,34D`: a checking run opens the Add sheet.
        .sheet(isPresented: Binding(get: { checkingAdd != nil }, set: { if !$0 { checkingAdd = nil } })) {
            PhoneAddEditReference(shots: checkingAdd ?? []).environmentObject(session)
        }
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if let at = args.firstIndex(of: "--editrefsheet"), at + 1 < args.count {
                let rows = session.view?.groups.flatMap(\.rows) ?? []
                let shots = args[at + 1].split(separator: ",").compactMap { n in rows.first { $0.number == String(n) }?.shot }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { checkingAdd = shots }
            }
        }
        .onAppear {
            // A checking run opens the first one's player once the list is up.
            if ProcessInfo.processInfo.arguments.contains("--playeditref"), let first = session.editRefsShown.first {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { PhoneEditLive.shared.play(first, from: nil) }
            }
        }
        // A tab whose mode went off (here or elsewhere) is not stood on.
        .onAppear { keepOnAShownTab() }
        .onChange(of: cards.stamp) { _, _ in keepOnAShownTab() }
        // A lock screen shortcut for this film, on arrival and while open:
        // a pinned page is its tab; any other opens inside the Library, which
        // is where it lives (a sixth tab would fold the bar into More).
        .onReceive(photoInbox.$waiting) { waiting in
            guard let waiting, waiting.film.caseInsensitiveCompare(session.entry.name) == .orderedSame else { return }
            dropping = waiting.photos
            DispatchQueue.main.async { photoInbox.waiting = nil }
        }
        .sheet(isPresented: Binding(get: { !dropping.isEmpty }, set: { if !$0 { dropping = [] } })) {
            PhotoDrop(photos: dropping) { place in
                route.wanted = (session.entry.name, place)
            }
            .environmentObject(session)
        }
        .onReceive(route.$wanted) { wanted in
            guard let wanted, wanted.film.caseInsensitiveCompare(session.entry.name) == .orderedSame else { return }
            if pins.contains(wanted.place) {
                selection = wanted.place.key
            } else {
                libraryPath = NavigationPath()
                if wanted.place != .library { libraryPath.append(wanted.place) }
                selection = Place.library.key
            }
            DispatchQueue.main.async { route.wanted = nil }
        }
        // **The film's own colour, everywhere in it** (2026-10-07): the tint
        // a control wears is the colour of this film's row in Notion, which
        // is what `Brand.accent` already does on the Mac. It arrives on the
        // record, so a film with no record wears Shotlister's blue.
        .tint(Style.accent(portal.front?.film.colour))
        // **When the film opens**, the copy kept on the phone, then the portal.
        .task(id: session.folder.url) { await portal.open(film: session.folder.url) }
    }
}

/// Whatever a place is, drawn.
struct PlaceView: View {
    let place: Place
    /// A tab's first screen, which wears the film's name; pushed, a place
    /// wears its own.
    var root = false

    var body: some View {
        drawn.environment(\.tabRoot, root)
    }

    @ViewBuilder
    private var drawn: some View {
        switch place {
        case .shotList: ShotListView()
        case .script: WholeScriptView()
        case .schedule: ScheduleView()
        case .locations: LocationsView()
        case .references: MoodBoardsView()
        case .diagrams: DiagramsView()
        case .shelf(let shelf):
            if shelf == .creative { LookShelfView() } else { ShelfView(shelf: shelf) }
        case .library: LibraryView()
        case .page(let key): PortalItemView(key: key)
        case .film: FilmFrontView()
        case .shoots: ShootsView()
        case .shoot(let slug): ShootView(slug: slug)
        case .record("camera", let shoot): CameraSheetView(shoot: shoot)
        case .record("people", let shoot): PeopleView(shoot: shoot)
        case .record(_, let shoot): DocumentsView(shoot: shoot)
        }
    }
}

/// **The Library**: every shelf, and what stands on it, the film's own places
/// first and then the portal's. A pinned thing says so; a Private one carries
/// a lock; the Archive is last. Pull to bring the portal's copy up to date.
///
/// Drawn the way the mockup draws it (`design/33-one-app.html`, "Library"):
/// each shelf named in small grey capitals over a card of rows, every row
/// led by the same kind of glyph, its kind small on the right.
struct LibraryView: View {
    @EnvironmentObject private var bar: BarPins
    @EnvironmentObject private var portal: PortalLine
    @State private var editing = Self.checkingEdit
    @State private var archiveOpen = Self.checkingArchive
    @State private var looking = ""
    @State private var covers: [String: String] = [:]
    /// The categories (2026-10-10): Add or Rename one, Remove one he added.
    @State private var naming: ShelfMenu.Naming?
    @State private var removing: Shelf?
    @State private var sorting = Self.checkingShelves

    /// A checking run opens Edit at once (`-EditPins 1`).
    private static var checkingEdit: Bool {
        #if targetEnvironment(simulator)
        return UserDefaults.standard.bool(forKey: "EditPins")
        #else
        return false
        #endif
    }

    /// A checking run opens Categories at once (`-LibraryShelves 1`).
    private static var checkingShelves: Bool {
        #if targetEnvironment(simulator)
        return UserDefaults.standard.bool(forKey: "LibraryShelves")
        #else
        return false
        #endif
    }

    /// A checking run opens the Archive and goes to it (`-LibraryArchive 1`).
    private static var checkingArchive: Bool {
        #if targetEnvironment(simulator)
        return UserDefaults.standard.bool(forKey: "LibraryArchive")
        #else
        return false
        #endif
    }

    private var pins: [Place] { bar.stored.split(separator: ",").compactMap { Place(key: String($0)) } }

    @EnvironmentObject private var session: Session
    @ObservedObject private var cards = PhoneCards.shared

    /// A mode that is off is not in the Library either (stage 5 step 4 B).
    private func modeShows(_ place: Place) -> Bool {
        cards.shows(place, film: Relay.projectId(at: session.folder.url), page: session.view?.project.consolePage ?? "")
    }

    private func wanted(_ name: String) -> Bool {
        let q = looking.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || name.localizedCaseInsensitiveContains(q)
    }

    /// The task restarts when the Library's items move.
    private var cause: [String] {
        (portal.library?.items ?? []).map { "\($0.key)@\($0.stamp ?? 0)" } + [portal.fetching ? "…" : ""]
    }

    var body: some View {
        ScrollViewReader { reader in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // The film's card that led the Library went 2026-10-09: the
                // film's name at the top opens the same menu.
                ForEach(portal.shelves) { shelf in
                    let places = (shelf.places + portal.places(on: shelf)).filter { wanted($0.title) && modeShows($0) }
                    let items = portal.items(on: shelf).filter { wanted($0.name) }
                    if !places.isEmpty || !items.isEmpty || (!shelf.builtIn && looking.isEmpty) {
                        HStack(alignment: .firstTextBaseline) {
                            NavigationLink(value: Place.shelf(shelf)) {
                                Text(shelf.name)
                                    .font(.system(size: Kit.Size.label, weight: .semibold))
                                    .foregroundStyle(Style.ink3)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { ShelfMenu(shelf: shelf, naming: $naming, removing: $removing) }
                            Spacer()
                        }
                        .padding(.horizontal, 6)
                        .padding(.top, 18)
                        .padding(.bottom, 7)
                        LibraryCard {
                            ForEach(places) { place in
                                NavigationLink(value: place) {
                                    LibraryRow(title: place.title, symbol: place.symbol, pinned: pins.contains(place))
                                }
                                .buttonStyle(.plain)
                            }
                            ForEach(items) { item in
                                NavigationLink(value: Place.page(item.key)) {
                                    LibraryRow(item: item, pinned: pins.contains(.page(item.key)))
                                }
                                .buttonStyle(.plain)
                                .itemMenu(item)
                            }
                            if places.isEmpty && items.isEmpty {
                                Text("Empty")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Style.ink3)
                                    .padding(.horizontal, 12)
                                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                            }
                        }
                    }
                }
                let archived = portal.archived.filter { wanted($0.name) }
                if !archived.isEmpty {
                    LibraryCard {
                        Button {
                            withAnimation(.snappy) { archiveOpen.toggle() }
                        } label: {
                            HStack(spacing: 10) {
                                LibraryRow.Tile(symbol: "archivebox")
                                Text("Archive").font(.system(size: 15))
                                Spacer()
                                Text("\(archived.count)")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Style.ink3)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .rotationEffect(.degrees(archiveOpen ? 90 : 0))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if archiveOpen {
                            ForEach(archived) { item in
                                NavigationLink(value: Place.page(item.key)) {
                                    LibraryRow(item: item, pinned: pins.contains(.page(item.key)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 22)
                    .id("archive")
                }
                if portal.library == nil, let trouble = portal.trouble {
                    Label(trouble, systemImage: "wifi.slash")
                        .font(.system(size: 15))
                        .foregroundStyle(Style.ink3)
                        .padding(.top, 22)
                        .padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .onChange(of: portal.archived.count) {
            if Self.checkingArchive { reader.scrollTo("archive", anchor: .bottom) }
        }
        }
        .background(Style.page)
        .environment(\.lookFiles, portal.files)
        .leadingTitle("Library")
        .searchable(text: $looking, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        .navigationDestination(for: Place.self) { place in PlaceView(place: place) }
        .refreshable { await portal.refresh() }
        .task(id: cause) { await look() }
        .toolbar {
            if portal.fetching {
                ToolbarItem(placement: .topBarLeading) { ProgressView() }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { naming = .init(shelf: nil, draft: "") } label: { Label("Add Category…", systemImage: "plus") }
                    Button { sorting = true } label: { Label("Categories…", systemImage: "list.bullet") }
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .accessibilityLabel("Categories")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editing = true }
                    .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $editing) {
            EditPins(covers: covers)
                .environmentObject(portal)
                .environment(\.tabRoot, false)
        }
        .sheet(isPresented: $sorting) {
            ShelvesSheet()
                .environmentObject(portal)
        }
        .shelfAsks(naming: $naming, removing: $removing)
    }

    /// Each page's, deck's and board's first picture, read from the copy kept
    /// on the phone, off the main thread.
    private func look() async {
        for item in (portal.library?.items ?? []) where covers[item.key] == nil {
            guard let kind = PortalNative<EmptyView>.kind(of: item),
                  let data = await portal.stored(kind, item.key) else { continue }
            let seen = await Task.detached(priority: .utility) { LookShelfView.glimpse(kind, data) }.value
            if let first = seen?.pictures.first { covers[item.key] = first }
        }
    }
}

/// A white card holding a shelf's rows, a hairline between each.
struct LibraryCard<Rows: View>: View {
    @ViewBuilder var rows: () -> Rows

    var body: some View {
        VStack(spacing: 0) {
            if #available(iOS 18.0, *) {
                Group(subviews: rows()) { subviews in
                    ForEach(Array(subviews.enumerated()), id: \.offset) { index, row in
                        row
                        if index < subviews.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
            } else {
                rows()
            }
        }
        .card(Style.Radius.list)
    }
}

/// One line of the Library: its icon and name, its kind, a lock
/// when Private, a pin when it is in the bar.
struct LibraryRow: View {
    var title: String
    var symbol: String
    var kind: String? = nil
    var locked = false
    var pinned = false

    init(title: String, symbol: String, pinned: Bool) {
        self.title = title
        self.symbol = symbol
        self.pinned = pinned
    }

    init(item: PortalItem, pinned: Bool) {
        title = item.name
        symbol = item.symbol
        kind = item.kind == "built" || item.kind == "page" ? nil : item.kindSaid
        locked = item.isPrivate
        self.pinned = pinned
    }

    /// The grey square an icon sits in where there is no cover.
    struct Tile: View {
        let symbol: String
        var body: some View {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(Color(.label))
                .frame(width: 34, height: 34)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // **One kind of icon** (2026-10-07). Three rows wore a grey glyph
            // and two wore a full-colour photograph, which is most of why the
            // Library read as jumbled. The cover art is the point on the Look
            // shelf and noise here, so every row wears the glyph.
            Tile(symbol: symbol)
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(Color(.label))
                .lineLimit(1)
            Spacer(minLength: 6)
            if locked {
                Label("Private", systemImage: "lock.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(light: 0x8A6D00, dark: 0xE0C25A))
            }
            if let kind {
                Text(kind)
                    .font(.system(size: 13))
                    .foregroundStyle(Style.ink3)
            }
            // "In the Bar" went 2026-10-10 (his note: the marker "doesn't need
            // to be there"); the bar itself shows what is in it.
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// A shelf on its own: what stands on it, to open.
struct ShelfView: View {
    let shelf: Shelf
    @EnvironmentObject private var portal: PortalLine

    var body: some View {
        let items = portal.items(on: shelf)
        let places = (shelf.places + portal.places(on: shelf)).filter { PhoneCards.shared.showsHere($0) }
        ScrollView {
            if !places.isEmpty || !items.isEmpty {
                LibraryCard {
                    ForEach(places) { place in
                        NavigationLink(value: place) {
                            LibraryRow(title: place.title, symbol: place.symbol, pinned: false)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(items) { item in
                        NavigationLink(value: Place.page(item.key)) {
                            LibraryRow(item: item, pinned: false)
                        }
                        .buttonStyle(.plain)
                        .itemMenu(item)
                    }
                }
                .padding(16)
            }
        }
        .background(Style.page)
        .environment(\.lookFiles, portal.files)
        .overlay {
            if places.isEmpty && items.isEmpty {
                ContentUnavailableView("Nothing on This Shelf", systemImage: shelf.symbol)
            }
        }
        .refreshable { await portal.refresh() }
        .navigationTitle(portal.shelf(shelf.id).name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Place.self) { place in PlaceView(place: place) }
    }
}

/// **Edit**: which four sit in the bar. Each slot takes any shelf or any
/// single place (the mockup's "Edit"): four tiles across the top, each a menu
/// of what it can hold; drag a tile onto another to swap them, or a row of
/// the Library below onto a tile to put it there.
struct EditPins: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var bar: BarPins
    @EnvironmentObject private var portal: PortalLine
    /// The Library's covers, so a row here wears the same picture.
    var covers: [String: String] = [:]
    @State private var over: Int?

    private var pins: [Place] {
        let read = bar.stored.split(separator: ",").compactMap { Place(key: String($0)) }
        return Array((read.isEmpty ? Place.defaultPins.split(separator: ",").compactMap { Place(key: String($0)) } : read).prefix(4))
    }

    private var choices: [Place] {
        [.film] + Place.built + (portal.front?.shoots.isEmpty == false ? [.shoots] : []) + portal.shelves.map { .shelf($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Kicker("In the Bar")
                        .padding(.horizontal, 4)
                        .padding(.bottom, 8)
                    HStack(spacing: 6) {
                        ForEach(Array(pins.enumerated()), id: \.offset) { index, place in
                            slot(index, place)
                        }
                    }
                    Kicker("Library")
                        .padding(.horizontal, 4)
                        .padding(.top, 22)
                        .padding(.bottom, 8)
                    if portal.front != nil {
                        LibraryCard {
                            LibraryRow(title: Place.film.title, symbol: Place.film.symbol, pinned: pins.contains(.film))
                                .draggable(Place.film.key)
                        }
                    }
                    ForEach(portal.shelves) { shelf in
                        let places = (shelf.places + portal.places(on: shelf)).filter { PhoneCards.shared.showsHere($0) }
                        let items = portal.items(on: shelf)
                        if !places.isEmpty || !items.isEmpty {
                            SectionTitle(shelf.name, size: 15)
                                .padding(.horizontal, 4)
                                .padding(.top, 12)
                                .padding(.bottom, 6)
                            LibraryCard {
                                ForEach(places) { place in
                                    LibraryRow(title: place.title, symbol: place.symbol, pinned: pins.contains(place))
                                        .draggable(place.key)
                                }
                                ForEach(items) { item in
                                    LibraryRow(item: item, pinned: pins.contains(.page(item.key)))
                                        .draggable(Place.page(item.key).key)
                                }
                            }
                        }
                    }
                    Button("Reset Tabs") { bar.stored = Place.defaultPins }
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.top, 22)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Style.page)
            .environment(\.lookFiles, portal.files)
            .leadingTitle("Edit")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// One place in the bar: its glyph and short name on a white tile, a menu
    /// of what else it could hold, and a place to drop.
    private func slot(_ index: Int, _ place: Place) -> some View {
        Menu {
            ForEach(choices) { choice in
                Button {
                    set(index, to: choice)
                } label: {
                    Label(portal.libraryTitle(of: choice), systemImage: choice.symbol)
                }
                .disabled(pins.contains(choice) && choice != place)
            }
            // **A single page of the portal's** (his ruling,
            // 2026-10-06), shelf by shelf.
            ForEach(portal.shelves) { shelf in
                let items = portal.items(on: shelf)
                if !items.isEmpty {
                    Menu(shelf.name) {
                        ForEach(items) { item in
                            Button {
                                set(index, to: .page(item.key))
                            } label: {
                                Label(item.name, systemImage: item.symbol)
                            }
                            .disabled(pins.contains(.page(item.key)) && .page(item.key) != place)
                        }
                    }
                }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: portal.symbol(of: place))
                    .font(.system(size: 20))
                    .symbolVariant(.none)
                Text(portal.title(of: place))
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Color(.label))
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .padding(.horizontal, 4)
            .background(over == index ? Color.accentColor.opacity(0.08) : Style.card,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                if over == index {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.tint, lineWidth: 2)
                }
            }
        }
        .draggable(place.key)
        .dropDestination(for: String.self) { keys, _ in
            guard let key = keys.first, let dropped = Place(key: key) else { return false }
            var now = pins
            if let from = now.firstIndex(of: dropped) {
                now.swapAt(from, index)
            } else {
                now[index] = dropped
            }
            bar.stored = now.map(\.key).joined(separator: ",")
            return true
        } isTargeted: { over = $0 ? index : (over == index ? nil : over) }
    }

    private func set(_ index: Int, to place: Place) {
        var now = pins
        guard index < now.count else { return }
        now[index] = place
        bar.stored = now.map(\.key).joined(separator: ",")
    }
}

extension Place {
    /// What a place is called in a list, where there is room: a shelf by its
    /// whole name.
    var libraryTitle: String {
        if case .shelf(let shelf) = self { return shelf.name }
        return title
    }
}

/// **A portal page, document or deck, opened on the phone** — all of it
/// native (his ask, 2026-10-06: *"Don't want to click a link to the
/// portal."*).
///
/// A document opens here: a PDF in the phone's own reader, anything else in
/// Quick Look, a link on the site it is on. The record's own pages are the
/// phone's screens (`PortalRecord.swift`): the Camera Spec Sheet, People,
/// Documents. A written page, deck or board is drawn natively (`PortalNative`,
/// Stage E's views); a page the portal keeps only as designed HTML arrives
/// from the door already read back into blocks and is drawn as any written
/// page is. **No web view, anywhere** (his ruling: *"I do not want to combine
/// a web app into an iOS app"*). Only a kind of page the phone has never heard
/// of still offers **Open on Portal**: a new kind is not finished until the
/// phone draws it.
struct PortalItemView: View {
    let key: String
    @EnvironmentObject private var portal: PortalLine
    @Environment(\.openURL) private var openURL
    @State private var file: URL?
    @State private var looked = false

    /// The record's own pages, which the phone draws from `front.json`.
    static let record: Set<String> = ["camera", "people", "documents"]

    var body: some View {
        if Self.record.contains(key) {
            switch key {
            case "camera": CameraSheetView()
            case "people": PeopleView()
            default: DocumentsView()
            }
        } else if let item = portal.item(key) {
            content(item)
                .navigationTitle(item.name)
                .navigationBarTitleDisplayMode(.inline)
                .task(id: item.file ?? item.pdf?.file ?? "") {
                    guard let name = item.file ?? item.pdf?.file else { return }
                    file = await portal.fetch(file: name)
                    looked = true
                }
        } else if portal.fetching {
            ProgressView()
        } else {
            ContentUnavailableView("Not on This iPhone", systemImage: "doc.text")
        }
    }

    @ViewBuilder
    private func content(_ item: PortalItem) -> some View {
        switch item.kind {
        case "file":
            if let file {
                if item.ext == "pdf" {
                    PortalPDF(url: file)
                } else if ["jpg", "jpeg", "png", "gif", "webp", "heic"].contains(item.ext ?? "") {
                    PortalPicture(url: file)
                } else {
                    PortalFileView(url: CameraSheet.named(file, item.named ?? item.name), name: item.name,
                                   symbol: item.symbol, bytes: item.bytes ?? 0)
                }
            } else if looked {
                ContentUnavailableView("Not on This iPhone", systemImage: item.symbol)
            } else {
                ProgressView()
            }
        case "link":
            linkCard(item)
        default:
            // **The portal's own page, inside the app** (his trial,
            // 2026-10-08, `PortalWeb.swift`): a page, deck or board as the
            // portal draws it. `PortalNative` stands unused until he decides.
            if item.kind != "film" {
                PortalWebPage(item: item)
            } else {
                otherwise(item)
            }
        }
    }

    /// **A link to another site** (a Drive file, a video): where it goes and
    /// the one button that goes there. Not the portal.
    private func linkCard(_ item: PortalItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let url = item.url.flatMap(URL.init(string:)) {
                    HStack(spacing: 12) {
                        LibraryRow.Tile(symbol: "link")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.system(size: 15, weight: .semibold))
                            Text(url.host()?.replacingOccurrences(of: "www.", with: "") ?? "")
                                .font(.system(size: 13))
                                .foregroundStyle(Style.ink3)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .card(Style.Radius.list)
                    GlassPillButton("Open Link") { openURL(url) }
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.leading, 6)
                }
            }
            .padding(16)
        }
        .background(Style.page)
    }

    /// What has no data the phone draws: a deck's printed copy, and only for
    /// a kind the phone has never heard of, its name and the way to the
    /// portal.
    @ViewBuilder
    private func otherwise(_ item: PortalItem) -> some View {
        if item.pdf != nil, let file {
            PortalPDF(url: file)
        } else if ["built", "page", "deck", "board"].contains(item.kind) {
            ContentUnavailableView(item.kind == "built" ? "Nothing here yet" : "Not on This iPhone", systemImage: item.symbol)
        } else {
            VStack(spacing: 16) {
                Image(systemName: item.symbol).font(.kitTitle).foregroundStyle(.secondary)
                Text(item.name).font(.title3.weight(.semibold))
                if let url = portal.portalURL(for: item) {
                    Button("Open on Portal") { openURL(url) }.buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }
}


/// A kept PDF in the phone's own reader.
struct PortalPDF: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        guard view.document?.documentURL != url else { return }
        // Opening a document reads its first pages; off the screen's thread.
        let target = url
        Task.detached {
            let document = PDFDocument(url: target)
            await MainActor.run { view.document = document }
        }
    }
}

/// A kept picture, read off the screen's thread.
struct PortalPicture: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView()
            }
        }
        .task(id: url) {
            let target = url
            image = await Task.detached { UIImage(contentsOfFile: target.path) }.value
        }
    }
}


// MARK: - The Library's categories, from the phone (2026-10-10)

/// **Move To** on a Library row: every shelf of the film, the one it stands on
/// ticked. His ask: moving an item to another category must work from the
/// apps, not only the portal.
struct MoveToMenu: View {
    let item: PortalItem
    @EnvironmentObject private var portal: PortalLine

    var body: some View {
        Menu {
            ForEach(portal.shelves) { shelf in
                Button {
                    guard shelf.id != item.shelfKey else { return }
                    Task { if let why = await portal.move(item, to: shelf) { portal.failed = why } }
                } label: {
                    if shelf.id == item.shelfKey { Label(shelf.name, systemImage: "checkmark") } else { Text(shelf.name) }
                }
            }
        } label: {
            Label("Move To", systemImage: "folder")
        }
    }
}

/// **The long-press menu on a Library row**: Rename for a pinned file or link,
/// then Move To. A page is renamed where it is written, so it gets Move To alone.
private struct ItemMenu: ViewModifier {
    let item: PortalItem
    @EnvironmentObject private var portal: PortalLine
    @State private var renaming = false
    @State private var draft = ""

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if item.isDocument {
                    Button { draft = item.name; renaming = true } label: { Label("Rename…", systemImage: "pencil") }
                }
                MoveToMenu(item: item)
            }
            .alert("Rename \(item.name)", isPresented: $renaming) {
                TextField("Name", text: $draft)
                Button("Cancel", role: .cancel) { }
                Button("Rename") {
                    let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty, name != item.name else { return }
                    Task { if let why = await portal.rename(item, to: name) { portal.failed = why } }
                }
            }
    }
}

extension View {
    func itemMenu(_ item: PortalItem) -> some View { modifier(ItemMenu(item: item)) }
}

/// A shelf heading's menu: Rename, Move Up and Down, and Remove for one he added.
struct ShelfMenu: View {
    struct Naming { var shelf: Shelf?; var draft: String }
    let shelf: Shelf
    @Binding var naming: Naming?
    @Binding var removing: Shelf?
    @EnvironmentObject private var portal: PortalLine

    var body: some View {
        let all = portal.shelves
        let at = all.firstIndex(of: shelf) ?? 0
        Button { naming = .init(shelf: shelf, draft: portal.shelf(shelf.id).name) } label: { Label("Rename…", systemImage: "pencil") }
        if at > 0 {
            Button { change(["action": "move", "shelf": shelf.id, "to": "up"]) } label: { Label("Move Up", systemImage: "arrow.up") }
        }
        if at < all.count - 1 {
            Button { change(["action": "move", "shelf": shelf.id, "to": "down"]) } label: { Label("Move Down", systemImage: "arrow.down") }
        }
        if !shelf.builtIn {
            Button(role: .destructive) { removing = shelf } label: { Label("Remove Category…", systemImage: "trash") }
        }
    }

    private func change(_ ask: [String: Any]) {
        Task { if let why = await portal.changeShelves(ask) { portal.failed = why } }
    }
}

extension View {
    /// The questions a category change asks: its name (Add, Rename), whether
    /// to remove it (and where its items go), and why one did not land.
    func shelfAsks(naming: Binding<ShelfMenu.Naming?>, removing: Binding<Shelf?>) -> some View {
        modifier(ShelfAsks(naming: naming, removing: removing))
    }
}

private struct ShelfAsks: ViewModifier {
    @Binding var naming: ShelfMenu.Naming?
    @Binding var removing: Shelf?
    @EnvironmentObject private var portal: PortalLine

    func body(content: Content) -> some View {
        content
            .alert(naming?.shelf == nil ? "Add Category" : "Rename Category",
                   isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
                TextField("Category", text: Binding(get: { naming?.draft ?? "" }, set: { naming?.draft = $0 }))
                Button("Cancel", role: .cancel) { naming = nil }
                Button(naming?.shelf == nil ? "Add" : "Rename") {
                    guard let ask = naming else { return }
                    naming = nil
                    let name = ask.draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    let body: [String: Any] = ask.shelf.map { ["action": "rename", "shelf": $0.id, "name": name] } ?? ["action": "add", "name": name]
                    Task { if let why = await portal.changeShelves(body) { portal.failed = why } }
                }
            }
            .confirmationDialog("Remove \(removing.map { portal.shelf($0.id).name } ?? "")?",
                                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                                titleVisibility: .visible) {
                Button("Remove Category", role: .destructive) {
                    guard let shelf = removing else { return }
                    removing = nil
                    Task { if let why = await portal.changeShelves(["action": "remove", "shelf": shelf.id]) { portal.failed = why } }
                }
                Button("Cancel", role: .cancel) { removing = nil }
            } message: {
                let n = removing.map { portal.items(on: $0).count } ?? 0
                Text((n == 0 ? "" : n == 1 ? "Its item moves to its default category. "
                      : "Its \(n) items move to their default categories. ") + "Nothing is deleted.")
            }
            .alert("Not Changed", isPresented: Binding(get: { portal.failed != nil }, set: { if !$0 { portal.failed = nil } })) {
                Button("OK", role: .cancel) { portal.failed = nil }
            } message: {
                Text(portal.failed ?? "")
            }
    }
}

/// **Categories**: the film's shelves in order. Drag to reorder, the pencil
/// to rename, swipe to remove one he added, and Add Category.
struct ShelvesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var portal: PortalLine
    @State private var naming: ShelfMenu.Naming?
    @State private var removing: Shelf?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(portal.shelves) { shelf in
                        HStack(spacing: 12) {
                            Image(systemName: shelf.symbol)
                                .frame(width: 24)
                                .foregroundStyle(Style.ink3)
                            Text(shelf.name)
                            Spacer()
                            Text("\(portal.items(on: shelf).count + (shelf.places + portal.places(on: shelf)).filter { PhoneCards.shared.showsHere($0) }.count)")
                                .font(.system(size: 13))
                                .foregroundStyle(Style.ink3)
                            Button { naming = .init(shelf: shelf, draft: shelf.name) } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Rename \(shelf.name)")
                        }
                        .deleteDisabled(shelf.builtIn)
                    }
                    .onMove { from, to in
                        var ids = portal.shelves.map(\.id)
                        ids.move(fromOffsets: from, toOffset: to)
                        Task { if let why = await portal.changeShelves(["action": "order", "ids": ids]) { portal.failed = why } }
                    }
                    .onDelete { at in
                        if let first = at.first { removing = portal.shelves[first] }
                    }
                } footer: {
                    Text("Starting categories can't be removed")
                }
                Section {
                    Button { naming = .init(shelf: nil, draft: "") } label: { Label("Add Category", systemImage: "plus") }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .shelfAsks(naming: $naming, removing: $removing)
        }
    }
}
