import Foundation

// Keeping a project's location photographs the same in Shotlister and in Drive.
//
// **This asks the engine.** It used to walk two folder trees and guess: matching
// locations by the name of a folder, and copying anything missing in either
// direction. Guessing is why it could not tell a photograph somebody deleted
// from a photograph somebody added — so it never deleted anything, and a picture
// removed on a scout came back five minutes later.
//
// Now the engine is the truth. It knows what a location is called, which
// photographs belong to it, and what changed. Drive is made to match.
//
// A compiled program in a bundle of its own, because macOS will not let anything
// read Google Drive's folder in the background without Full Disk Access, and
// that is granted to a thing you can point at.

let fm = FileManager.default
let home = fm.homeDirectoryForCurrentUser

let arguments = CommandLine.arguments

/// A checking door, the way the apps have them. `--projects` and `--drive` point
/// the whole thing at scratch folders, which is the only way to watch a
/// deletion cross the bridge without deleting one of his photographs to do it.
func argument(_ name: String) -> String? {
    guard let flag = arguments.firstIndex(of: name) else { return nil }
    let next = arguments.index(after: flag)
    return next < arguments.endIndex ? arguments[next] : nil
}

/// `Documents/Shotlister` since 2026-09-15 — the films left iCloud Drive
/// when the relay became the only road between devices (Projects.swift).
let projectsFolder = argument("--projects").map { URL(fileURLWithPath: $0) }
    ?? home.appending(path: "Documents/Shotlister")
let driveFolder = argument("--drive").map { URL(fileURLWithPath: $0) }
    ?? home.appending(path: "Library/CloudStorage/GoogleDrive-you@example.com/My Drive/cinematography/projects")
let apply = arguments.contains("--apply")
let quiet = arguments.contains("--quiet")

/// Where this machine keeps what it has carried. **Outside the project**, because
/// the project syncs: a memory inside it travels to every device, gets rewritten
/// whole by each of them, and iCloud answers that with conflict copies. What was
/// carried across is a fact about *this computer's* Drive, not about the film.
let memoryRoot = argument("--memory").map { URL(fileURLWithPath: $0) }
    ?? home.appending(path: "Library/Application Support/Shotlister/drive-sync")

/// How long a Drive folder must stay empty before its emptiness is believed.
/// See `Memory.emptySince`.
let settleTime: TimeInterval = argument("--settle").flatMap(Double.init) ?? 600

var plan: [(String, String)] = []
func note(_ kind: String, _ what: String) { plan.append((kind, what)) }

// ---- names ----------------------------------------------------------------

/// What a name is called on disk. A folder the Finder shows as `Sc 1-7/8/20` is
/// stored with colons, because a slash cannot be a path component. His real
/// location folders are full of them.
func onDisk(_ name: String) -> String {
    let cleaned = name.replacingOccurrences(of: "/", with: ":")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? "Untitled" : cleaned
}

func shown(_ name: String) -> String { name.replacingOccurrences(of: ":", with: "/") }

func slug(of project: URL) -> String {
    let stem = project.deletingPathExtension().lastPathComponent.lowercased()
    return stem.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "-")
}

func allowedProjects() -> Set<String> {
    if let named = argument("--only") { return [named] }
    let beside = URL(fileURLWithPath: arguments[0]).deletingLastPathComponent()
    for candidate in [beside.appending(path: "../Resources/projects.txt"),
                      beside.appending(path: "projects.txt")] {
        if let text = try? String(contentsOf: candidate, encoding: .utf8) {
            return Set(text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") })
        }
    }
    return []
}

// ---- the engine ------------------------------------------------------------

/// The same engine both apps use, asked the same way.
final class Engine {
    private let handle: OpaquePointer

    /// The bridge's own name in the sync log, so its writes are its own and a
    /// photograph it brings in from Drive is never mistaken for the phone's.
    ///
    /// **Worked out from this machine, not written into the program** — Ref
    /// 186. It used to be the constant `0x0D717E0000000001`, which meant every
    /// copy of the bridge anywhere in the world was the same device: two Macs
    /// syncing one film would have had their bridges silently discarding each
    /// other's work. The role keeps it clear of the Mac app running beside it
    /// on the same machine.
    static let device = DeviceIdentity.name(role: "bridge")

    init?(path: String) {
        guard let h = path.withCString({
            sl_open_as_installed($0, Engine.device, DeviceIdentity.installation)
        }) else { return nil }
        handle = h
    }

    deinit { sl_close(handle) }

    @discardableResult
    func call(_ parts: String...) -> Data {
        let line = parts.joined(separator: "\t")
        guard let reply = line.withCString({ sl_call(handle, $0) }) else { return Data() }
        defer { sl_free(reply) }
        return Data(String(cString: reply).utf8)
    }

    func save() { call("save") }
}

struct View: Decodable {
    var locations: [Location]
    /// The film's mood boards — Ref 229's second half. Absent from an older
    /// engine's view, which is simply a film with no boards.
    var boards: [Board] = []
    /// **What the project itself says**, including the Drive folder it works
    /// out of — which is how a film opts in now, rather than by being listed
    /// in a file baked into this program. Ref 229.
    var project: ProjectRecord = ProjectRecord()
}

struct ProjectRecord: Decodable {
    /// The actual folder on this Mac, set in the project's settings. Empty
    /// means this film has not opted in to Drive at all.
    var driveFolder: String = ""
    var title: String = ""
}

struct Location: Decodable {
    var id: String
    var name: String
    var folder: String
    var driveFolder: String
    var media: [Medium]
    /// **The house this is a room in**, empty when it stands on its own —
    /// Ref 269. His ruling, 2026-08-22: *"It should go into its own subfolder
    /// within that larger location's folder. Location → Main Location
    /// Subfolder → Area Subfolders."*
    var parent: String = ""
    /// `Hillcrest House — Kitchen`, for saying which one in a log line.
    var fullName: String = ""
    /// **Whether this place's photographs travel to Drive** — Ref 229, and his
    /// ask: *"it's something that should be visible and something I can opt
    /// into if I so chose."*
    ///
    /// `"1"` on, `"0"` off, and **empty means nobody has been asked** — which
    /// is not the same as no. See `carries` below.
    var syncWithDrive: String = ""
}

/// **A mood board** — Ref 229's second half. A name and a wall of pictures,
/// and the same `Medium` a location's photographs are, because the engine
/// never cared who owned one.
struct Board: Decodable {
    var id: String
    var name: String
    var media: [Medium]
    /// Which folder under the film's reference folder holds them. Written down
    /// rather than guessed from the name, so renaming a board renames its
    /// folder instead of orphaning its pictures — exactly as for a location.
    var driveFolder: String = ""
    /// **Whether this board's pictures travel to Drive.**
    ///
    /// `"1"` on, anything else off — and unlike a location, **empty is off**.
    /// No board has ever been carried, so there is no work in progress that
    /// reading absent as no would silently stop. His call, 2026-08-30.
    var syncWithDrive: String = ""
}

/// **A location that was deleted, and the Drive folder it left behind.**
/// From `retiredlocations` — see step 5 of `syncLocations`.
struct Retired: Decodable {
    var id: String
    var driveFolder: String
}

struct Medium: Decodable {
    var ref: String
    var hash: String
    var filename: String
}

/// The engine's own picture gallery, which already knows every shot's number
/// and the pictures hanging on it — so the shot-list half needs nothing new
/// from the engine. `label` on a shot group is its display number, `3G`.
struct Gallery: Decodable {
    var groups: [Group] = []
    struct Group: Decodable {
        var kind: String
        var label: String
        var items: [Medium] = []
    }
}

// ---- what the bridge remembers ---------------------------------------------

/// **A sync needs a memory.** Without one, a file in Drive that the engine does
/// not have is indistinguishable from a file the engine used to have — one is a
/// photograph somebody added, the other is a photograph somebody deleted, and
/// treating them alike is why deletions came back.
///
/// One small file per location, listing what was carried across last time.
///
/// **An empty memory is a safe memory.** Every deletion this program carries out
/// needs the memory to name the file, so a machine that has never run it before
/// — or has lost this folder — does nothing at all until it has learned. That is
/// why it can live outside the project without a migration anybody has to think
/// about.
struct Memory {
    var names: Set<String>

    /// When this location's Drive folder was first seen holding no pictures
    /// while the memory still expected some.
    ///
    /// **A folder that has gone quiet and a folder somebody emptied read
    /// identically**: no pictures. Drive not mounted yet, a folder not sent down
    /// to this machine, a permissions blip — all of them look like every
    /// photograph being deleted at once, and the answer to that used to be to
    /// take every one of them off the location. So a clean sweep is not believed
    /// the first time it is seen; it has to still be true `settleTime` later. A
    /// glitch is gone by then. A deletion is still there.
    var emptySince: Date?

    let file: URL

    private struct Stored: Codable {
        var names: [String]
        var emptySince: Date?
    }

    init(project: URL, location: String, folder: String) {
        let safe = location.isEmpty ? folder : location
        file = memoryRoot
            .appending(path: project.deletingPathExtension().lastPathComponent)
            .appending(path: "\(safe.replacingOccurrences(of: "/", with: "-")).json")

        // Where it used to live: inside the project, beside the location's
        // scans. Read once so nothing is re-carried or re-imported on the way
        // over; the old file is left alone rather than deleted.
        let old = project.appending(path: "locations/\(folder)/.drive-sync.json")

        for candidate in [file, old] {
            guard let data = try? Data(contentsOf: candidate) else { continue }
            if let stored = try? JSONDecoder().decode(Stored.self, from: data) {
                names = Set(stored.names)
                emptySince = stored.emptySince
                return
            }
            if let list = try? JSONDecoder().decode([String].self, from: data) {
                names = Set(list)
                return
            }
        }
        names = []
    }

    func write() {
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let stored = Stored(names: names.sorted(), emptySince: emptySince)
        if let data = try? JSONEncoder().encode(stored) { try? data.write(to: file) }
    }
}

// ---- the work ---------------------------------------------------------------

let pictureKinds: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp"]
/// What a location may also hold. See `carried(in:)` for why this exists.
let movieKinds: Set<String> = ["mp4", "mov", "m4v"]

/// What is in a folder, or **nothing at all if it could not be read**.
///
/// The difference matters everywhere a conclusion is drawn from something being
/// absent. `contentsOfDirectory` fails for a folder Drive has not mounted, has
/// not sent down to this machine, or will not open for a moment — and an error
/// swallowed into an empty list says, in perfectly good faith, that somebody
/// deleted everything in it.
func entries(of folder: URL) -> [URL]? {
    // Not being there is knowable, and is genuinely nothing. Only a folder that
    // exists and still will not open is unreadable.
    if !fm.fileExists(atPath: folder.path) { return [] }
    guard let found = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])
    else { return nil }
    return found.sorted { $0.lastPathComponent < $1.lastPathComponent }
}

/// For the places that only ever *add* something on the strength of what they
/// find, where reading nothing costs a run rather than a photograph.
func children(of folder: URL) -> [URL] { entries(of: folder) ?? [] }

func isFolder(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
}

func pictures(in folder: URL) -> [String: URL]? { files(in: folder, kinds: pictureKinds) }

/// **What a location's folder holds** — pictures *and* movies.
///
/// A location carries the file itself, so a clip he shot on a scout is written
/// into Drive as the `.mp4` it is. `pictures(in:)` cannot see one, and the
/// asymmetry cost him a video: the bridge wrote `house-living-room-08.mp4`
/// into Drive, could not find it there on the next run, read that as somebody
/// having deleted it, and took it off the Living Room — so it vanished from
/// the portal while sitting in the Drive folder all along (2026-09-18).
/// What this program writes, it has to be able to read back.
///
/// **The shot list is deliberately not this.** It publishes the still that
/// stands for a clip and never the clip, so its folder is pictures only —
/// see `still`.
func carried(in folder: URL) -> [String: URL]? {
    files(in: folder, kinds: pictureKinds.union(movieKinds))
}

private func files(in folder: URL, kinds: Set<String>) -> [String: URL]? {
    guard let files = entries(of: folder) else { return nil }
    var found: [String: URL] = [:]
    for file in files where !isFolder(file) {
        let name = file.lastPathComponent
        guard !name.hasPrefix("."), kinds.contains(file.pathExtension.lowercased()) else { continue }
        found[name] = file
    }
    return found
}

func logistics(of driveProject: URL) -> URL? {
    children(of: driveProject).first {
        isFolder($0) && $0.lastPathComponent.lowercased().contains("logistic")
    }
}

func locationsFolder(in logistics: URL) -> URL {
    if let existing = children(of: logistics).first(where: {
        isFolder($0) && $0.lastPathComponent.lowercased().contains("location")
    }) { return existing }
    return logistics.appending(path: "locations")
}

/// **Where a film's mood boards go in Drive** — his answer, 2026-08-30:
/// `1-creative/reference/<board>`, inside the film itself, mirroring the way
/// locations sit under `2-logistics/locations`. The folder he already keeps
/// exactly this kind of still in.
///
/// The two names are matched the way `logistics` is — by what the folder is
/// called rather than by a number he might renumber — so `1-creative` and
/// `01_CREATIVE` and plain `creative` all answer.
func creative(of driveProject: URL) -> URL? {
    children(of: driveProject).first {
        isFolder($0) && $0.lastPathComponent.lowercased().contains("creative")
    }
}

func referenceFolder(in creative: URL) -> URL {
    if let existing = children(of: creative).first(where: {
        isFolder($0) && $0.lastPathComponent.lowercased().contains("reference")
    }) { return existing }
    return creative.appending(path: "reference")
}

/// **Where a film's shot stills go in Drive** — his answer, 2026-09-02:
/// `1-creative/shot list/stills`, beside the `reference` folder the mood boards
/// already use. He asked for the pictures to sit in a subfolder rather than
/// loose in `shot list`, because that folder is also where the shot list
/// document itself lives.
///
/// Matched by name the way `creative` and `logistics` are, so a film that
/// already keeps one under any spelling gets that one rather than a second.
func shotListFolder(in creative: URL) -> URL {
    if let existing = children(of: creative).first(where: {
        isFolder($0) && $0.lastPathComponent.lowercased().contains("shot")
    }) { return existing }
    return creative.appending(path: "shot list")
}

/// **Whether this board's pictures travel to Drive.** Ref 229.
///
/// **Off unless he has switched it on** — the opposite of `carries` below, and
/// deliberately. A location was already being carried before its switch
/// existed, so absent had to mean yes there or the opt-in would have stopped
/// work in progress. No board has ever been carried, so absent safely means
/// no, and nothing starts leaving the app because a feature shipped.
func carriesBoard(_ board: Board) -> Bool { board.syncWithDrive == "1" }

/// **Whether this place's photographs travel to Drive.** Ref 229.
///
/// Three answers, and the third is why this is a function rather than a
/// comparison. `"1"` is yes and `"0"` is no, but **empty means nobody has ever
/// been asked** — every location made before the switch existed is empty, and
/// the bridge has been carrying some of them for days. Reading empty as no
/// would have silently stopped work that was already happening, which is the
/// worst possible way to introduce an opt-in.
///
/// So an undecided place follows its film: **the film opting in is already an
/// explicit choice he made** by giving it a Drive folder in its settings, and a
/// place inside an opted-in film carries unless he says otherwise. The switch
/// is there to *exclude* a place, and to make what is happening visible — which
/// was the actual complaint: *"It happens in the BG right now, but it's
/// something that should be visible."*
func carries(_ place: Location) -> Bool {
    switch place.syncWithDrive {
    case "0": return false
    default: return true
    }
}

// ---- one wall, kept the same on both sides ---------------------------------

/// **A wall of pictures with a folder in Drive.** A location is one; a mood
/// board is one — Ref 229's second half, built 2026-08-30 once boards existed.
///
/// The four passes below are the whole of the sync, and every one of them was
/// paid for by a bug: a deletion that came back, a photograph re-imported the
/// run after it was restored, a folder Drive had not mounted read as somebody
/// emptying it. A board copying them would be a second place for all of those
/// to come back, one at a time. So they live here once, and a location and a
/// board differ only in **where** their folder is and in **what decides**
/// whether they carry at all — which is the whole of the difference.
struct Wall {
    /// The record the pictures hang on, which is also what the memory file is
    /// keyed by. Ids are unique across the document, so a board and a location
    /// can never collide there.
    var id: String
    /// What to call it in a log line.
    var name: String
    /// Where it keeps its scans, for a location that came home from a scout —
    /// used only to find a memory file written before memories moved out of
    /// the project. Empty for a board, which never had one.
    var scansFolder: String
    var media: [Medium]
    /// Its folder in Drive, already made.
    var here: URL
}

/// Make the two sides of one wall agree, and say whether the engine changed.
func carry(_ wall: Wall, project: URL, engine: Engine) -> Bool {
    var changed = false

    // **Not the scans folder on its own.** A location made on the Mac has no
    // folder at all, so the old memory file this looks for was hunted at
    // `locations//.drive-sync.json` — a path that cannot exist — and every
    // photograph the phone had already carried over looked new again.
    // `FileNames.locationFolder` is the one answer all three programs give
    // to "no folder": the location's own id. Ref 306.
    var memory = Memory(project: project, location: wall.id,
                        folder: FileNames.locationFolder(id: wall.id,
                                                         folder: wall.scansFolder))
    var inEngine = Set(wall.media.map(\.filename))
    guard let inDrive = carried(in: wall.here) else {
        note("trouble", "\(wall.name): its folder in Drive would not open — left alone this run")
        return changed
    }

    // 1. What the engine has and Drive does not — carry it out. **Unless it
    //    was carried before**, which makes it step 4's business instead: a
    //    photograph this program put in Drive and can no longer find is one
    //    somebody deleted there, not one Drive is missing. Writing it back
    //    would undo the deletion and then detach it in the same run, and the
    //    run after that would import the file it had just restored as a
    //    photograph nobody had seen before.
    for medium in wall.media
    where inDrive[medium.filename] == nil && !memory.names.contains(medium.filename) {
        note("→ Drive", "\(wall.name): \(medium.filename)")
        guard apply else { continue }
        guard let bytes = proxy(engine: engine, medium: medium) else {
            note("trouble", "\(wall.name): no stored copy of \(medium.filename) to send")
            continue
        }
        do {
            try bytes.write(to: wall.here.appending(path: medium.filename))
            // **Only what landed is remembered.** Writing down a file the
            // write failed on makes it look, on the next run, like a
            // photograph somebody deleted in Drive — and step 4 would take
            // it off the location to match.
            memory.names.insert(medium.filename)
        } catch {
            note("trouble", "\(wall.name): could not write \(medium.filename) to Drive — \(error.localizedDescription)")
        }
    }

    // 2. What Drive has and the engine has never seen — bring it in.
    for (filename, source) in inDrive
    where !inEngine.contains(filename) && !memory.names.contains(filename) {
        note("→ project", "\(wall.name): \(filename)")
        if apply, let image = try? Data(contentsOf: source) {
            engine.call("paste", wall.id, "0", "0",
                        source.pathExtension.lowercased(),
                        image.base64EncodedString(), "image", "0", filename)
            memory.names.insert(filename)
            // **The engine has it now.** Without this the next step, which
            // asks what the engine is missing, saw a photograph imported
            // three lines earlier as one somebody had deleted — and moved
            // it straight into z-deleted.
            inEngine.insert(filename)
            changed = true
        }
    }

    // 3. What both sides once had and the engine no longer does — somebody
    //    deleted it in the app. It leaves Drive so it stays deleted, and it
    //    goes to `z-deleted` rather than being destroyed: deleting is a
    //    person's decision, and this is only carrying one out.
    for (filename, file) in inDrive
    where !inEngine.contains(filename) && memory.names.contains(filename) {
        note("deleted", "\(wall.name): \(filename) → z-deleted")
        if apply {
            let grave = wall.here.appending(path: "z-deleted")
            try? fm.createDirectory(at: grave, withIntermediateDirectories: true)
            try? fm.moveItem(at: file, to: grave.appending(path: filename))
            memory.names.remove(filename)
        }
    }

    // 4. What the engine has, Drive had, and Drive no longer does — somebody
    //    deleted it in Drive. The photograph itself is kept, always; only
    //    this location stops pointing at it, which the app can undo.
    let vanished = wall.media.filter {
        inDrive[$0.filename] == nil && memory.names.contains($0.filename)
    }

    // **Everything going at once is Drive's doing until it proves otherwise.**
    // Somebody deleting photographs leaves the rest behind; a folder that has
    // gone quiet takes all of them. So a clean sweep waits — see
    // `Memory.emptySince`. A partial deletion is believed straight away,
    // because nothing else produces one.
    if !vanished.isEmpty && inDrive.isEmpty {
        let settled = memory.emptySince.map { Date().timeIntervalSince($0) >= settleTime } ?? false
        if !settled {
            if memory.emptySince == nil { memory.emptySince = Date() }
            note("trouble", "\(wall.name): all \(vanished.count) photo\(vanished.count == 1 ? "" : "s") gone from Drive at once — waiting to see that again before removing \(vanished.count == 1 ? "it" : "them") here")
            if apply { memory.write() }
            return changed
        }
        memory.emptySince = nil
    } else if memory.emptySince != nil {
        memory.emptySince = nil
    }

    for medium in vanished {
        note("deleted", "\(wall.name): \(medium.filename) — removed in Drive")
        if apply {
            engine.call("detach", medium.ref)
            memory.names.remove(medium.filename)
            changed = true
        }
    }

    if apply { memory.write() }
    return changed
}

func sync(project: URL) {
    guard let engine = Engine(path: project.path) else {
        note("skipped", "\(project.lastPathComponent): the engine would not open it")
        return
    }
    guard let view = try? JSONDecoder().decode(View.self, from: engine.call("view")) else {
        note("skipped", "\(project.lastPathComponent): could not read the project")
        return
    }

    // **Which films this program touches is a fact about the film, not about
    // this program.** Ref 229, and the thing Ref 193 complained about: the
    // allow-list used to be copied into the app bundle at build time, so
    // covering a new film meant editing a text file *and* rebuilding — and
    // editing the text file alone silently did nothing.
    //
    // A film opts in by carrying the Drive folder it works out of, which is set
    // in its own settings and is already exactly the "group folder in project
    // settings" he asked for. `projects.txt` still answers for a Drive folder
    // that has no Shotlister project yet — that is what `prepareDrive` uses it
    // for — and `--only` still overrides everything.
    let recorded = view.project.driveFolder.trimmingCharacters(in: .whitespaces)
    let driveProject: URL
    if !recorded.isEmpty, isFolder(URL(fileURLWithPath: recorded)) {
        driveProject = URL(fileURLWithPath: recorded)
    } else if allowedProjects().contains(slug(of: project)) {
        driveProject = driveFolder.appending(path: slug(of: project))
        guard isFolder(driveProject) else {
            note("skipped", "\(project.lastPathComponent): no Drive folder called '\(slug(of: project))'")
            return
        }
    } else if recorded.isEmpty {
        note("not linked", "\(project.lastPathComponent) — set its Drive folder in the project's settings")
        return
    } else {
        note("skipped", "\(project.lastPathComponent): its Drive folder is not there — \(shown(recorded))")
        return
    }

    // **Two halves, and neither can stop the other.** A film with no
    // `logistics` folder in Drive has nowhere to put locations, and used to
    // return here — which, once boards arrived, would have meant a missing
    // folder for one kind of picture silently cancelling the other. Ref 229.
    var changed = syncLocations(view: view, driveProject: driveProject,
                                project: project, engine: engine)
    if syncBoards(view: view, driveProject: driveProject,
                  project: project, engine: engine) {
        changed = true
    }
    // **The shot stills half is retired (2026-10-15).** The hub's Drive copies
    // now put a shot's pictures in `1-creative/shot-list/scene-NN/`, and two
    // writers for the same pictures meant two folders of them. `syncShotList`
    // below is kept for reference and is not called.

    if apply && changed { engine.save() }
}

/// The locations half — a folder per place under `2-logistics/locations`, and
/// the four passes on each. Says whether the engine changed.
func syncLocations(view: View, driveProject: URL, project: URL, engine: Engine) -> Bool {
    guard let logisticsFolder = logistics(of: driveProject) else {
        note("skipped", "\(project.lastPathComponent): no logistics folder in Drive")
        return false
    }

    let locations = locationsFolder(in: logisticsFolder)
    if apply { try? fm.createDirectory(at: locations, withIntermediateDirectories: true) }

    var changed = false
    /// The folders this run has actually used. Built as it goes rather than
    /// from the view it started with: a location renamed a moment ago is on
    /// disk under its new name, and a list made before the rename does not know
    /// that — which is how a rename came out as a rename *and* a brand-new
    /// location holding the same photographs.
    var claimed: Set<String> = []

    for place in view.locations {
        // **A place he has switched off is left completely alone** — Ref 229.
        // Not just "nothing is carried": no folder is made for it, its Drive
        // folder is not renamed to follow it, and nothing already in Drive is
        // touched. Off means this program is not in that place's business.
        //
        // **Its folder is still claimed**, though, so the sweep at the end does
        // not read a switched-off place's folder as one somebody made in Drive
        // by hand and turn it into a second location holding the same pictures.
        guard carries(place) else {
            let house = place.parent.isEmpty
                ? nil
                : view.locations.first { $0.id == place.parent }
            let held = place.driveFolder.isEmpty
                ? (house.map { "\(onDisk($0.name))/\(onDisk(place.name))" } ?? onDisk(place.name))
                : place.driveFolder
            claimed.insert(held)
            if let outer = held.split(separator: "/").first { claimed.insert(String(outer)) }
            note("off", "\(place.name): not syncing with Drive")
            continue
        }

        // **The engine owns the name.** Rename a location in the app and its
        // Drive folder follows — the pairing is a field on the record, so a
        // rename is a rename rather than a location nobody has seen before.
        // **A room goes inside its house's folder**, so Drive shows one house
        // rather than six loose rooms — his ruling, 2026-08-22. `driveFolder`
        // holds the path relative to the locations folder, so `House/Kitchen`
        // renames exactly the way a bare name always did.
        let house = place.parent.isEmpty
            ? nil
            : view.locations.first { $0.id == place.parent }
        let wanted = house.map { "\(onDisk($0.name))/\(onDisk(place.name))" }
            ?? onDisk(place.name)
        var target = locations.appending(path: wanted)

        if !place.driveFolder.isEmpty, place.driveFolder != wanted {
            let existing = locations.appending(path: place.driveFolder)
            if isFolder(existing) {
                note("rename", "\(shown(place.driveFolder))  →  \(shown(wanted))")
                if apply {
                    if fm.fileExists(atPath: target.path) {
                        note("kept apart", "'\(shown(wanted))' already exists; left the old one alone")
                        target = existing
                    } else {
                        try? fm.moveItem(at: existing, to: target)
                    }
                }
            }
        }

        if !isFolder(target) {
            note("make folder", shown(target.lastPathComponent))
            if apply { try? fm.createDirectory(at: target, withIntermediateDirectories: true) }
        }
        // The path relative to the locations folder — one component for a
        // location that stands alone, two for a room.
        let held = house == nil
            ? target.lastPathComponent
            : "\(target.deletingLastPathComponent().lastPathComponent)/\(target.lastPathComponent)"
        claimed.insert(held)
        // A house's own folder is claimed too, so the sweep below does not read
        // it as something somebody made in Drive.
        if let outer = held.split(separator: "/").first { claimed.insert(String(outer)) }
        if apply, place.driveFolder != held {
            engine.call("setlocation", place.id, "driveFolder", held)
            changed = true
        }

        if carry(Wall(id: place.id, name: place.name,
                      scansFolder: place.folder, media: place.media, here: target),
                 project: project, engine: engine) {
            changed = true
        }
    }

    // 5. A folder somebody made in Drive that is not a location here yet.
    //    Somebody put it there on purpose; the way to honour that is to make it
    //    a real place rather than to leave it lying outside the project.
    // **One level down as well**, now that a house holds rooms: a folder made
    // inside a house in Drive is a room somebody made there, and would
    // otherwise never be seen. Only one level — the engine allows no deeper.
    let houses = Set(view.locations.filter { $0.parent.isEmpty }.map { onDisk($0.name) })
    var loose: [(URL, String)] = []
    for child in children(of: locations) where isFolder(child) {
        loose.append((child, child.lastPathComponent))
        guard houses.contains(child.lastPathComponent) else { continue }
        for inside in children(of: child) where isFolder(inside) {
            loose.append((inside, "\(child.lastPathComponent)/\(inside.lastPathComponent)"))
        }
    }
    // **A folder a deleted location left behind is not a folder somebody
    // made.** The two are the same thing on disk, and telling them apart is
    // the whole of Ref 1070: deleting a location in the app leaves its folder
    // in Drive — this program destroys nothing — and this step then made it a
    // location again fifteen seconds later, for as long as the machine was on.
    // The engine's tombstones are what answer it: a folder a deleted location
    // still names is that deletion's leftover, and it goes to `z-deleted` the
    // way a deleted photograph does, so the deletion sticks without anything
    // being destroyed.
    var retired: [String: String] = [:]   // drive folder → the tombstone's id
    if let rows = try? JSONDecoder().decode([Retired].self,
                                            from: engine.call("retiredlocations")) {
        for row in rows where !row.driveFolder.isEmpty { retired[row.driveFolder] = row.id }
    }

    for (child, name) in loose {
        guard !claimed.contains(name), !child.lastPathComponent.hasPrefix("."),
              child.lastPathComponent != "z-deleted" else { continue }

        if let tombstone = retired[name] {
            // **Never out from under a live room.** A deleted house whose rooms
            // survived still names `House`, and moving that folder would take
            // their photographs with it. A folder anything live is using is
            // left exactly where it is; only the tombstone is forgotten.
            let holdsLive = claimed.contains { $0.hasPrefix("\(name)/") }
            note("deleted", "\(shown(name)) → z-deleted (deleted in the app)")
            if apply {
                if !holdsLive {
                    let grave = locations.appending(path: "z-deleted")
                    try? fm.createDirectory(at: grave, withIntermediateDirectories: true)
                    var resting = grave.appending(path: child.lastPathComponent)
                    // Two deletions of one name over a project's life; the
                    // second does not quietly land on the first.
                    var n = 2
                    while fm.fileExists(atPath: resting.path) {
                        resting = grave.appending(path: "\(child.lastPathComponent) \(n)")
                        n += 1
                    }
                    try? fm.moveItem(at: child, to: resting)
                }
                // Forgotten either way: a folder of this name made by hand
                // tomorrow is somebody's decision and is honoured as new.
                engine.call("forgetretired", tombstone)
                changed = true
            }
            continue
        }

        // **Never a second place of the same name in the same place.**
        // Belt and braces, after the night of 2026-09-18: whatever else goes
        // wrong, this program must not be able to fill his film with copies
        // of a place he already has. It runs every fifteen seconds and
        // unattended, and every record it writes reaches every device within
        // the minute and stays in the log for ever — so the one thing it must
        // never do quietly is make places. If this ever fires, something else
        // is wrong; it says so and leaves the folder alone.
        let bare = shown(child.lastPathComponent)
        let inside = name.firstIndex(of: "/").map { String(name[..<$0]) }
        let sameLevel = view.locations.first { place in
            guard place.name.caseInsensitiveCompare(bare) == .orderedSame else { return false }
            switch inside {
            case .none: return place.parent.isEmpty
            case .some(let house):
                guard let owner = view.locations.first(where: { $0.id == place.parent })
                else { return false }
                return onDisk(owner.name) == house
            }
        }
        if let sameLevel {
            note("left alone", "\(shown(name)): there is already a place called "
                 + "\(sameLevel.name) here")
            continue
        }

        let count = (carried(in: child) ?? [:]).count
        note("new location", "\(shown(name))  (\(count) photo\(count == 1 ? "" : "s"))")
        if apply {
            // A folder found inside a house becomes a room of that house.
            // **Which records existed before**, so the one made below can be
            // found by being new. It used to be found by its name, and a house
            // that already had a *Living Room* meant the room's own record was
            // stamped with the loose folder's path, its `folder` and
            // `capturedBy` — so a room in Drive changed hands every run and
            // its photographs went with it. Names are not identities.
            let before = Set(view.locations.map(\.id))
            if let slash = name.firstIndex(of: "/"),
               let inHouse = view.locations.first(where: {
                   $0.parent.isEmpty && onDisk($0.name) == String(name[..<slash])
               }) {
                engine.call("addarea", inHouse.id, bare)
            } else {
                engine.call("addlocation", bare)
            }
            guard let after = try? JSONDecoder().decode(View.self, from: engine.call("view")),
                  let made = after.locations.first(where: {
                      !before.contains($0.id) && $0.name == bare
                  })
            else { continue }
            engine.call("setlocation", made.id, "driveFolder", name)
            engine.call("setlocation", made.id, "folder", UUID().uuidString)
            engine.call("setlocation", made.id, "capturedBy", "Google Drive")
            changed = true
        }
    }

    return changed
}

/// The mood board half — Ref 229, built 2026-08-30 once boards existed.
///
/// **A folder per board under `1-creative/reference`**, his answer of
/// 2026-08-30, and the same four passes a location gets. Two things it
/// deliberately does *not* do, both of which a location does:
///
/// - **Nothing until he switches it on.** See `carriesBoard`.
/// - **No folder in Drive ever becomes a board.** A loose folder under
///   `locations` is a place somebody made on purpose and is worth honouring,
///   because that folder can only be a location. `reference` is a pile he
///   keeps stills in by hand — his own already holds a hundred of them beside
///   whatever folders he has made there — and reading each of those as a mood
///   board would invent walls he never asked for. The traffic here is one way
///   about *which boards exist*, and two ways about what is on each.
func syncBoards(view: View, driveProject: URL, project: URL, engine: Engine) -> Bool {
    let wanted = view.boards.filter(carriesBoard)
    // **A film nobody has switched a board on in costs nothing**, and says
    // nothing. Not even the creative folder is looked for — this runs every
    // fifteen seconds against every film he has.
    guard !wanted.isEmpty else {
        for board in view.boards where board.syncWithDrive == "0" {
            note("off", "\(board.name): not syncing with Drive")
        }
        return false
    }

    guard let creativeFolder = creative(of: driveProject) else {
        note("trouble", "\(project.lastPathComponent): no creative folder in Drive for its mood boards")
        return false
    }
    let reference = referenceFolder(in: creativeFolder)
    if apply { try? fm.createDirectory(at: reference, withIntermediateDirectories: true) }

    var changed = false
    for board in view.boards {
        guard carriesBoard(board) else {
            if board.syncWithDrive == "0" {
                note("off", "\(board.name): not syncing with Drive")
            }
            continue
        }

        // **The engine owns the name**, exactly as for a location: rename a
        // board in the app and its folder in Drive follows, because the two
        // are paired by a field on the record rather than by the name matching.
        let name = onDisk(board.name)
        var here = reference.appending(path: name)

        if !board.driveFolder.isEmpty, board.driveFolder != name {
            let existing = reference.appending(path: board.driveFolder)
            if isFolder(existing) {
                note("rename", "\(shown(board.driveFolder))  →  \(shown(name))")
                if apply {
                    if fm.fileExists(atPath: here.path) {
                        note("kept apart", "'\(shown(name))' already exists; left the old one alone")
                        here = existing
                    } else {
                        try? fm.moveItem(at: existing, to: here)
                    }
                }
            }
        }

        if !isFolder(here) {
            note("make folder", shown(here.lastPathComponent))
            if apply { try? fm.createDirectory(at: here, withIntermediateDirectories: true) }
        }
        let held = here.lastPathComponent
        if apply, board.driveFolder != held {
            // The generic `set`, not a verb of its own — a board is written
            // through the same door its shape and its tags go through.
            engine.call("set", board.id, "drive_folder", held)
            changed = true
        }

        if carry(Wall(id: board.id, name: board.name,
                      scansFolder: "", media: board.media, here: here),
                 project: project, engine: engine) {
            changed = true
        }
    }

    return changed
}

/// **RETIRED 2026-10-15 — nothing calls this.** Replaced by the hub's Drive copies
/// (`1-creative/shot-list/scene-NN/<shot>-<k>.jpg`).
///
/// **The shot list's stills, published into Drive.** His ask, 2026-09-02:
/// every picture hanging on a shot, in the film's Drive folder, named after the
/// shot it belongs to.
///
/// **One direction only, and that is his ruling.** Locations and mood boards
/// carry both ways; this one publishes. A picture named `3G.jpg` in a folder is
/// a statement about a shot, and a stranger's file dropped in beside it says
/// nothing the engine could act on — so nothing here is ever imported, and
/// nothing of his is ever touched.
///
/// **It only ever tidies up after itself.** The memory names the files this
/// program wrote; a file it did not write is left completely alone however odd
/// it looks. That is what makes a folder he also keeps his own things in safe.
func syncShotList(driveProject: URL, project: URL, engine: Engine) -> Bool {
    guard let creativeFolder = creative(of: driveProject) else {
        note("trouble", "\(project.lastPathComponent): no creative folder in Drive for its shot stills")
        return false
    }
    guard let gallery = try? JSONDecoder().decode(Gallery.self, from: engine.call("gallery", "")) else {
        note("trouble", "\(project.lastPathComponent): could not read the picture gallery")
        return false
    }

    // **The engine already knows all of this.** `gallery` groups every picture
    // by what it hangs on and labels a shot group with its display number, so
    // there is nothing to work out here and no new engine command to keep in
    // step. Ref 228 built it for the picture picker; this is its second reader.
    let shots = gallery.groups.filter { $0.kind == "shot" && !$0.items.isEmpty }

    // What should be there, and under what name. **The first picture on a shot
    // takes the clean name** — it is the one that stands for the shot — and the
    // rest follow it numbered, which is what he asked for: `3G.jpg`, `3G-2.jpg`.
    //
    // Keyed by the stem rather than the whole filename, because the extension
    // is not known until the engine has been asked: a clip publishes the poster
    // it stores, not the video, and a file re-encoded on the way in is stored
    // under the extension it became.
    var wanted: [(stem: String, medium: Medium)] = []
    for shot in shots {
        let label = onDisk(shot.label)
        guard !label.isEmpty else { continue }
        for (index, medium) in shot.items.enumerated() {
            wanted.append((index == 0 ? label : "\(label)-\(index + 1)", medium))
        }
    }
    let wantedStems = Set(wanted.map(\.stem))

    var memory = Memory(project: project, location: "shot-list", folder: "shot-list")

    // **Nothing to publish and nothing published before means nothing is made.**
    // A film with no pictures on any shot does not get an empty folder, and
    // this runs every fifteen seconds against every film he has. It still runs
    // when the memory holds names, because the last picture coming off a shot
    // is exactly when the file it wrote needs taking away.
    guard !wanted.isEmpty || !memory.names.isEmpty else { return false }

    let stills = shotListFolder(in: creativeFolder).appending(path: "stills")
    if apply { try? fm.createDirectory(at: stills, withIntermediateDirectories: true) }

    // **A folder that will not open is not an empty folder.** One Drive has not
    // sent down yet reads as every file having gone, and for a folder this
    // program publishes into that would mean writing all of them again.
    let onDrive: [String: URL]
    if let found = pictures(in: stills) {
        onDrive = found
    } else if isFolder(stills) {
        note("trouble", "\(project.lastPathComponent): the shot stills folder would not open — left alone this run")
        return false
    } else {
        onDrive = [:]
    }
    let present = Set(onDrive.keys.map { ($0 as NSString).deletingPathExtension })

    for (stem, medium) in wanted.sorted(by: { $0.stem < $1.stem }) where !present.contains(stem) {
        note("→ Drive", "shot list: \(stem)")
        guard apply else { continue }
        guard let picture = still(engine: engine, medium: medium) else {
            note("trouble", "shot list: no still stored for \(shown(medium.filename)) on \(stem)")
            continue
        }
        let name = "\(stem).\(picture.ext)"
        do {
            try picture.data.write(to: stills.appending(path: name))
            memory.names.insert(name)
        } catch {
            note("trouble", "shot list: could not write \(name) — \(error.localizedDescription)")
        }
    }

    // A picture taken off a shot, or a shot renumbered, leaves a file behind
    // whose name no longer says anything true. It goes to `z-deleted` beside
    // the others rather than being destroyed — **and only if this program is
    // the one that put it there.** A file of his own in this folder is never
    // touched, however odd its name looks.
    for name in memory.names.sorted()
    where !wantedStems.contains((name as NSString).deletingPathExtension) {
        guard let file = onDrive[name] else {
            if apply { memory.names.remove(name) }
            continue
        }
        note("deleted", "shot list: \(name) → z-deleted")
        if apply {
            let grave = stills.appending(path: "z-deleted")
            try? fm.createDirectory(at: grave, withIntermediateDirectories: true)
            try? fm.moveItem(at: file, to: grave.appending(path: name))
            memory.names.remove(name)
        }
    }

    if apply { memory.write() }

    // **Always false: this half never changes the film.** It publishes what the
    // engine already says and imports nothing, so there is never anything to save.
    return false
}

/// The stored bytes of a picture, as the engine hands them out.
func proxy(engine: Engine, medium: Medium) -> Data? {
    struct Reply: Decodable { var data: String }
    let ext = (medium.filename as NSString).pathExtension
    guard let reply = try? JSONDecoder().decode(
        Reply.self, from: engine.call("media", medium.hash, ext.isEmpty ? "jpg" : ext)
    ) else { return nil }
    return Data(base64Encoded: reply.data)
}

/// **A still for a shot, whatever the shot is holding.**
///
/// Nearly half the pictures on his shots are clips — `Cadrage_….mp4`,
/// `chb-long-zoom-reveal.mp4` — and a folder of shot stills wants the frame
/// that stands for one, not eight seconds of video. A clip's poster is stored
/// under `png` against the same hash, which is exactly why `media` refuses to
/// default its extension: asking without one used to hand back the poster when
/// the video was wanted.
///
/// The engine says which extension it actually found, because a file re-encoded
/// on the way in is stored under the extension it *became* while keeping the
/// name it came with. Trusting the filename is how a JPEG called `.png` gets
/// published under a name nothing can open.
func still(engine: Engine, medium: Medium) -> (ext: String, data: Data)? {
    struct Reply: Decodable { var ext: String?; var data: String }
    let named = (medium.filename as NSString).pathExtension.lowercased()
    let asked = pictureKinds.contains(named) ? named : "png"
    guard let reply = try? JSONDecoder().decode(
        Reply.self, from: engine.call("media", medium.hash, asked)
    ), let bytes = Data(base64Encoded: reply.data), !bytes.isEmpty else { return nil }
    let found = (reply.ext ?? asked).lowercased()
    // Only ever a picture. A film whose clip has no poster yet is skipped
    // rather than published as a video nobody asked for — and `pictures(in:)`
    // would not see that video next run, so it would be written again for ever.
    guard pictureKinds.contains(found) else { return nil }
    return (found, bytes)
}

/// Give every listed project its locations folder, whether or not there is a
/// Shotlister project for it yet.
func prepareDrive() {
    for name in allowedProjects().sorted() {
        let driveProject = driveFolder.appending(path: name)
        guard isFolder(driveProject) else { note("missing", "\(name) is not in the Drive"); continue }
        guard let logisticsFolder = logistics(of: driveProject) else {
            note("missing", "\(name) has no logistics folder"); continue
        }
        let already = children(of: logisticsFolder).contains {
            isFolder($0) && $0.lastPathComponent.lowercased().contains("location")
        }
        guard !already else { continue }
        note("make folder", "\(name)/\(logisticsFolder.lastPathComponent)/locations")
        if apply {
            try? fm.createDirectory(at: logisticsFolder.appending(path: "locations"),
                                    withIntermediateDirectories: true)
        }
    }
}

// ---- saying what happened ---------------------------------------------------

guard isFolder(projectsFolder) else {
    print("No Shotlister folder in Documents."); exit(2)
}
guard isFolder(driveFolder) else {
    print("Can't reach the cinematography Drive.")
    print("Either Google Drive isn't running, or this program hasn't been given Full Disk Access.")
    exit(2)
}

note("project", "Drive folders")
prepareDrive()

for project in children(of: projectsFolder) where project.pathExtension == "shotlist" {
    note("project", project.lastPathComponent)
    sync(project: project)
}

// **Nothing here is work.** A film with no Drive folder and a place he has
// switched off are both the system doing exactly what it was told; neither is a
// thing to do, and counting them as one made a quiet run print every fifteen
// seconds and the summary claim "3 things to do" when there were none. Ref 229.
let quietSkips: Set<String> = ["not listed", "skipped", "not linked", "off"]
let troubles = plan.filter { $0.0 == "trouble" }
let moves = plan.filter {
    !["project", "skipped", "not listed", "not linked", "off", "missing", "trouble"].contains($0.0)
}

// **Trouble is never quiet.** The automatic runs print only when they moved
// something, so a run where every folder failed to open used to look exactly
// like a run with nothing to do — and the log only ever held its successes.
if quiet && moves.isEmpty && troubles.isEmpty { exit(0) }

for (kind, what) in plan {
    if kind == "project" {
        print("\n\(what)")
    } else if !quiet || !quietSkips.contains(kind) {
        print("  \(kind.padding(toLength: 14, withPad: " ", startingAt: 0)) \(what)")
    }
}

if moves.isEmpty && troubles.isEmpty {
    print("\nNothing to do — both sides already agree.")
} else if moves.isEmpty {
    print("\nNothing moved.")
} else if !apply {
    print("\n\(moves.count) thing(s) to do. Nothing has been changed.")
} else {
    print("\nDone — \(moves.count) thing(s).")
}

if !troubles.isEmpty {
    print("\n\(troubles.count) thing(s) needed a person. Nothing was taken off a location because of them.")
}
