import AppKit
import Foundation

// Checking the Drive bridge, on scratch folders, with real photographs.
//
// The bug this exists for: **Drive going quiet read as Drive being emptied.** A
// folder that would not open came back as an empty list, and an empty list means
// "somebody deleted every photograph in here" — so the bridge took them all off
// the location. A slow mount, a folder not yet sent down to this machine, or a
// permissions blip was enough.
//
// It cannot be checked by reading the code, and it must never be checked against
// his own photographs, so everything below happens in a temporary folder that is
// thrown away at the end. `--projects`, `--drive`, `--memory` and `--settle` are
// the doors that make that possible.

let fm = FileManager.default
let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
    .appending(path: "bridge-checks-\(UUID().uuidString)")
let projectsFolder = scratch.appending(path: "projects")
let driveFolder = scratch.appending(path: "drive")
let memoryFolder = scratch.appending(path: "memory")
let project = projectsFolder.appending(path: "test-bridge.shotlist")

/// `<drive>/test-bridge/2-logistics/locations/The Mansion` — the shape his real
/// Drive has, which is what the bridge walks looking for a locations folder.
let mansion = driveFolder
    .appending(path: "test-bridge/2-logistics/locations/The Mansion")

/// The worker to drive, built fresh beside these checks. Never the installed
/// bundle — the automatic agent is running that one every fifteen seconds.
let binary = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: CommandLine.arguments[0])
        .deletingLastPathComponent()
        .appending(path: "drivesync")

// ---- saying how it went ------------------------------------------------------

var passed = 0
var failed = 0

func check(_ what: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok {
        passed += 1
        print("  ✓ \(what)")
    } else {
        failed += 1
        print("  ✗ \(what)")
        let said = detail()
        if !said.isEmpty { print("      \(said)") }
    }
}

func heading(_ what: String) { print("\n\(what)") }

// ---- the engine, asked the way the bridge asks it -----------------------------

final class Engine {
    private let handle: OpaquePointer
    init?(path: String) {
        guard let h = path.withCString({ sl_open_as($0, 0x0D_71_7E_00_00_00_00_02) }) else { return nil }
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
}

struct View: Decodable {
    var locations: [Location]
    var boards: [Board] = []
    var project: ProjectRecord = ProjectRecord()
    /// The table, in groups of rows — where a shot's own id and its display
    /// number both live. The gallery labels a shot group with that number, so
    /// this is how a check knows what filename to expect.
    var groups: [Group] = []
}
struct Group: Decodable { var rows: [Row] = [] }
struct Row: Decodable { var shot: String; var number: String }
struct GalleryReply: Decodable {
    var groups: [Group] = []
    struct Group: Decodable {
        var kind: String
        var label: String
        var items: [Item] = []
        struct Item: Decodable { var ref: String; var filename: String }
    }
}
struct SceneList: Decodable {
    var scenes: [Scene] = []
    struct Scene: Decodable { var id: String; var number: String }
}
/// A mood board — Ref 229's second half.
struct Board: Decodable {
    var id: String
    var name: String
    var media: [Medium]
    var driveFolder: String = ""
    var syncWithDrive: String = ""
}
struct ProjectRecord: Decodable {
    var id: String = ""
    var driveFolder: String = ""
}
struct Location: Decodable {
    var id: String
    var name: String
    var media: [Medium]
    /// The house this is a room in, empty when it stands alone — Ref 269.
    var parent: String = ""
    var driveFolder: String = ""
    /// Whether this place's photographs travel to Drive — Ref 229.
    var syncWithDrive: String = ""
}
struct Medium: Decodable { var ref: String; var filename: String }

/// Open, read, close — so every look is at what is actually on disk rather than
/// at a handle that has been sitting open across a bridge run.
func read() -> View? {
    guard let engine = Engine(path: project.path) else { return nil }
    return try? JSONDecoder().decode(View.self, from: engine.call("view"))
}

/// Flip a place's Drive switch, the way the app's switch will.
func setSwitch(_ place: String, _ value: String) {
    guard let engine = Engine(path: project.path) else { return }
    engine.call("setlocation", place, "syncWithDrive", value)
    engine.call("save")
}

/// Make a mood board and hand back its id.
func addBoard(_ name: String) -> String? {
    guard let engine = Engine(path: project.path) else { return nil }
    engine.call("addboard", name)
    engine.call("save")
    return read()?.boards.first { $0.name == name }?.id
}

/// Flip a board's Drive switch, the way the app's switch does — through the
/// same generic `set` a board's shape and its tags go through.
func setBoardSwitch(_ board: String, _ value: String) {
    guard let engine = Engine(path: project.path) else { return }
    engine.call("set", board, "sync_with_drive", value)
    engine.call("save")
}

/// Hang a picture on a board, the way the app does when one is dropped on it.
func putOnBoard(_ board: String, _ name: String, red: CGFloat) {
    let holding = scratch.appending(path: "holding")
    writePhotograph(name, red: red, into: holding)
    guard let bytes = try? Data(contentsOf: holding.appending(path: name)),
          let engine = Engine(path: project.path) else { return }
    engine.call("paste", board, "0", "0", "jpg", bytes.base64EncodedString(), "image", "0", name)
    engine.call("save")
}

func boardPictures(_ name: String) -> [String] {
    (read()?.boards.first { $0.name == name }?.media.map(\.filename) ?? []).sorted()
}

/// Make a scene with a shot in it and hand back the shot's id and the number
/// it will be filed under — `2A`, which is what the gallery labels it.
func addShot(inScene number: String) -> (id: String, number: String)? {
    guard let engine = Engine(path: project.path) else { return nil }
    engine.call("addscene", number)
    guard let made = (try? JSONDecoder().decode(SceneList.self, from: engine.call("view")))?
        .scenes.first(where: { $0.number == number }) else { return nil }
    engine.call("addshot", made.id)
    engine.call("save")
    guard let after = try? JSONDecoder().decode(View.self, from: engine.call("view")),
          let row = after.groups.flatMap({ $0.rows }).last(where: { $0.number.hasPrefix(number) })
    else { return nil }
    return (row.shot, row.number)
}

/// Hang a picture on a shot, the way the app does when one is dropped on it.
func putOnShot(_ shot: String, _ name: String, red: CGFloat) {
    guard let engine = Engine(path: project.path) else { return }
    let size = NSSize(width: 40, height: 40)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor(calibratedRed: red, green: 0.3, blue: 0.5, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    else { return }
    engine.call("paste", shot, "0", "0", "jpg", jpeg.base64EncodedString(), "image", "0", name)
    engine.call("save")
}

/// Say where this film lives in Drive — the opt-in that replaces the list
/// baked into the program. Ref 229.
func setProjectFolder(_ path: String) {
    guard let engine = Engine(path: project.path),
          let view = try? JSONDecoder().decode(View.self, from: engine.call("view"))
    else { return }
    engine.call("set", view.project.id, "drive_folder", path)
    engine.call("save")
}

func photographs() -> [String] {
    (read()?.locations.first?.media.map(\.filename) ?? []).sorted()
}

// ---- running the bridge -------------------------------------------------------

@discardableResult
func runBridge(_ extra: [String] = [], withOnly: Bool = true) -> String {
    let task = Process()
    task.executableURL = binary
    task.arguments = [
        "--projects", projectsFolder.path,
        "--drive", driveFolder.path,
        "--memory", memoryFolder.path,
        "--settle", "0",
        "--apply",
    ] + (withOnly ? ["--only", "test-bridge"] : []) + extra
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    try? task.run()
    let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    task.waitUntilExit()
    return out
}

// ---- making a photograph ------------------------------------------------------

/// Real JPEGs, and **each a different colour on purpose**: the engine stores a
/// picture by its contents, so three identical files would be one photograph
/// wearing three names and nothing below would mean what it says.
func writePhotograph(_ name: String, red: CGFloat, into folder: URL) {
    let size = NSSize(width: 48, height: 48)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor(calibratedRed: red, green: 0.4, blue: 0.6, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    else { return }
    try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
    try? jpeg.write(to: folder.appending(path: name))
}

func inDrive() -> [String] {
    ((try? fm.contentsOfDirectory(at: mansion, includingPropertiesForKeys: nil)) ?? [])
        .map(\.lastPathComponent).filter { $0.hasSuffix(".jpg") }.sorted()
}

func removePhotographs() {
    for file in (try? fm.contentsOfDirectory(at: mansion, includingPropertiesForKeys: nil)) ?? []
    where file.pathExtension.lowercased() == "jpg" {
        try? fm.removeItem(at: file)
    }
}

func chmod(_ folder: URL, _ mode: Int) {
    try? fm.setAttributes([.posixPermissions: mode], ofItemAtPath: folder.path)
}

// ---- setting the scene ---------------------------------------------------------

guard fm.fileExists(atPath: binary.path) else {
    print("No worker to check at \(binary.path). Run bridge/checks.sh, which builds one.")
    exit(2)
}

try? fm.createDirectory(at: projectsFolder, withIntermediateDirectories: true)
writePhotograph("kitchen.jpg", red: 0.9, into: mansion)
writePhotograph("hallway.jpg", red: 0.5, into: mansion)
writePhotograph("stairs.jpg", red: 0.1, into: mansion)

// The engine makes the project when the path is not there yet.
guard Engine(path: project.path) != nil else {
    print("Could not make a scratch project.")
    exit(2)
}

heading("Setting up — a location and three photographs come in from Drive")
// Twice on purpose: a folder somebody made in Drive becomes a location at the
// end of a run, so its photographs are only seen on the run after that. With the
// agent going every fifteen seconds that is invisible; here it has to be said.
runBridge()
runBridge()
check("the Drive folder became a location", read()?.locations.count == 1,
      "locations: \(read()?.locations.map(\.name) ?? [])")
check("all three photographs came in", photographs() == ["hallway.jpg", "kitchen.jpg", "stairs.jpg"],
      "has: \(photographs())")

// ---- the bug ------------------------------------------------------------------

heading("A folder that will not open is not a folder somebody emptied")
chmod(mansion, 0o000)
let unreadable = runBridge()
chmod(mansion, 0o755)
check("all three photographs are still on the location", photographs().count == 3,
      "has: \(photographs())")
check("it said the folder would not open", unreadable.contains("would not open"),
      unreadable)

heading("Trouble is never quiet")
chmod(mansion, 0o000)
let quietRun = runBridge(["--quiet"])
chmod(mansion, 0o755)
check("a quiet run still said something went wrong", quietRun.contains("would not open"),
      "printed: \(quietRun.isEmpty ? "(nothing at all)" : quietRun)")

heading("Everything disappearing at once waits to be seen twice")
removePhotographs()
let firstSweep = runBridge()
check("nothing was taken off the location the first time", photographs().count == 3,
      "has: \(photographs())")
check("it said it was waiting", firstSweep.contains("waiting to see that again"), firstSweep)

heading("…and is believed when it is still true")
let secondSweep = runBridge()
check("the three photographs came off the location", photographs().isEmpty,
      "has: \(photographs())")
check("it said they were removed in Drive", secondSweep.contains("removed in Drive"), secondSweep)

heading("One photograph deleted in Drive goes straight away — only a sweep waits")
writePhotograph("kitchen.jpg", red: 0.9, into: mansion)
writePhotograph("hallway.jpg", red: 0.5, into: mansion)
writePhotograph("stairs.jpg", red: 0.1, into: mansion)
runBridge()
check("the three are back on the location", photographs().count == 3, "has: \(photographs())")
try? fm.removeItem(at: mansion.appending(path: "hallway.jpg"))
runBridge()
check("the deleted one went, on the first run", photographs() == ["kitchen.jpg", "stairs.jpg"],
      "has: \(photographs()), Drive has: \(inDrive())")
// **A deletion has to stay deleted.** Carrying out what the engine holds and
// noticing what Drive has lost were the same test, so the same run wrote the
// photograph back to Drive and took it off the location — and the next run
// brought the restored file in as one nobody had ever seen.
check("it was not written back to Drive", !inDrive().contains("hallway.jpg"), "Drive has: \(inDrive())")
runBridge()
runBridge()
check("and it did not come back on a later run", photographs() == ["kitchen.jpg", "stairs.jpg"],
      "has: \(photographs()), Drive has: \(inDrive())")

heading("A photograph that could not be written to Drive is not remembered as carried")
// The engine gains a photograph Drive has never had, and Drive will not take it.
// Its own colour, because a picture the engine already holds under another name
// is the same picture to it — the bytes are the identity.
let attic = scratch.appending(path: "attic")
writePhotograph("attic.jpg", red: 0.75, into: attic)
if let engine = Engine(path: project.path),
   let place = read()?.locations.first,
   let jpeg = try? Data(contentsOf: attic.appending(path: "attic.jpg")) {
    engine.call("paste", place.id, "0", "0", "jpg",
                jpeg.base64EncodedString(), "image", "0", "attic.jpg")
    engine.call("save")
}
check("the engine has the new photograph", photographs().contains("attic.jpg"), "has: \(photographs())")

chmod(mansion, 0o555)  // readable, not writable
let refused = runBridge()
chmod(mansion, 0o755)
check("it said it could not write it", refused.contains("could not write"),
      "Drive has: \(inDrive())\n\(refused)")
// The real test of the fix: having failed to carry it out, the next run must not
// read its absence from Drive as somebody having deleted it.
runBridge()
runBridge()
check("the photograph is still on the location", photographs().contains("attic.jpg"),
      "has: \(photographs())")

heading("A room's folder sits inside its house's — Ref 269")
// His ruling, 2026-08-22: *"It should go into its own subfolder within that
// larger location's folder. Location → Main Location Subfolder → Area
// Subfolders."* Six loose rooms beside each other in Drive say nothing about
// being one house.
if let engine = Engine(path: project.path),
   let house = read()?.locations.first(where: { $0.parent.isEmpty }) {
    engine.call("addarea", house.id, "Kitchen")
    // `save` is the engine's own command here; the wrapper only forwards calls.
    engine.call("save")
    runBridge()

    let inside = mansion.appending(path: "Kitchen")
    check("the room's folder is inside the house's", fm.fileExists(atPath: inside.path),
          "looked for \(inside.path)")
    check("and not beside it",
          !fm.fileExists(atPath: mansion.deletingLastPathComponent()
              .appending(path: "Kitchen").path))

    // The pairing the engine keeps has to be the path, or the next rename
    // loses the photographs.
    let room = read()?.locations.first { !$0.parent.isEmpty }
    check("the engine remembers the whole path", room?.driveFolder == "The Mansion/Kitchen",
          "holds: \(room?.driveFolder ?? "none")")

    // A folder made by hand inside a house is a room of that house, not a
    // location of its own.
    try? fm.createDirectory(at: mansion.appending(path: "Garage"),
                            withIntermediateDirectories: true)
    runBridge()
    runBridge()
    let garage = read()?.locations.first { $0.name == "Garage" }
    check("a folder made inside a house comes in as a room of it",
          garage?.parent == house.id,
          "parent: \(garage?.parent ?? "none"), house: \(house.id)")
} else {
    check("a room's folder sits inside its house's", false, "no house to put one in")
}

heading("It cannot fill the film with copies of a place he already has — Ref 1070")
// Belt and braces. Whatever else goes wrong in here, this program runs every
// fifteen seconds and unattended, and every record it writes is on every
// device within the minute and in the log for ever. So the one thing it must
// never do quietly is make a second place with a name he already uses.
if let engine = Engine(path: project.path),
   let house = read()?.locations.first(where: { $0.parent.isEmpty }) {
    // The state his film was actually in: a room called *Cellar* whose
    // pairing points at some other folder, and a folder called `Cellar`
    // sitting loose beside it. The rename would normally pull the two back
    // together — but both folders exist, so it keeps them apart and the loose
    // one falls through to step 5 wearing a name the house already uses.
    engine.call("addarea", house.id, "Cellar")
    engine.call("save")
    _ = runBridge()
    let cellar = read()?.locations.first { $0.name == "Cellar" }
    if let cellar {
        try? fm.createDirectory(at: mansion.appending(path: "Wine Store"),
                                withIntermediateDirectories: true)
        engine.call("setlocation", cellar.id, "driveFolder", "The Mansion/Wine Store")
        engine.call("save")

        let was = read()?.locations.count ?? 0
        let said = runBridge()
        _ = runBridge()

        check("it made no second Cellar",
              read()?.locations.filter { $0.name == "Cellar" }.count == 1,
              "locations: \(read()?.locations.map(\.name) ?? [])")
        check("it said why it left the folder alone",
              said.contains("there is already a place called"), said)
        check("and it invented nothing else either",
              (read()?.locations.count ?? 0) == was,
              "was \(was), now \(read()?.locations.count ?? 0)")
    } else {
        check("it cannot fill the film with copies of a place he already has",
              false, "no room to work with")
    }
}

heading("A clip on a location survives a second run — Ref 1071")
// What cost him a video on *Mirrorland*, 2026-09-18. A location carries the
// file itself, so a clip he shot on a scout is written into Drive as the
// `.mp4` it is — and the folder listing only counted still pictures, so the
// next run could not find what the last one had written, read that as somebody
// deleting it in Drive, and took the clip off the location. It was gone from
// the portal while sitting in the Drive folder the whole time.
if let engine = Engine(path: project.path),
   let place = read()?.locations.first {
    // A clip arriving the way the phone sends one: bytes into the engine,
    // then hung on the location.
    let clip = Data("not really a movie, but it is a file with a name".utf8)
    let reply = engine.call("paste", place.id, "0", "0", "mp4",
                            clip.base64EncodedString(), "video", "0", "scout-clip.mp4")
    engine.call("save")
    let landed = read()?.locations.first?.media
        .contains { $0.filename == "scout-clip.mp4" } == true

    if landed {
        runBridge()
        let after = runBridge()
        check("the clip reached Drive",
              fm.fileExists(atPath: mansion.appending(path: "scout-clip.mp4").path),
              "in Drive: \(inDrive())")
        check("and it is still on the location a run later",
              read()?.locations.first?.media.contains { $0.filename == "scout-clip.mp4" } == true,
              "has: \(photographs())")
        check("it was not read as deleted in Drive",
              !after.contains("scout-clip.mp4 — removed in Drive"), after)
    } else {
        check("a clip on a location survives a second run", false,
              "the engine would not take the clip: \(String(data: reply, encoding: .utf8) ?? "")")
    }
}

heading("A location deleted in the app stays deleted — Ref 1070")
// The fault that cost him a night on *Mirrorland*, 2026-09-18. Deleting a
// location in the app leaves its folder in Drive, because this program
// destroys nothing — and step 5 then read that folder as one somebody had
// made by hand and turned it back into a location, fifteen seconds later,
// for as long as the Mac was awake. He ended up with nine places where he
// had made four, several of them ones he had deleted hours before.
let locationsRoot = mansion.deletingLastPathComponent()
if let engine = Engine(path: project.path) {
    // A place of its own, with a photograph, carried to Drive the usual way.
    let shed = locationsRoot.appending(path: "The Shed")
    try? fm.createDirectory(at: shed, withIntermediateDirectories: true)
    writePhotograph("tools.jpg", red: 0.3, into: shed)
    runBridge()
    runBridge()
    let made = read()?.locations.first { $0.name == "The Shed" }
    check("the shed came in from Drive", made != nil,
          "locations: \(read()?.locations.map(\.name) ?? [])")

    // Now he deletes it in the app, the way he would.
    if let made {
        engine.call("deletelocation", made.id)
        engine.call("save")
    }
    runBridge()
    runBridge()
    runBridge()

    check("it did not come back",
          read()?.locations.contains { $0.name == "The Shed" } == false,
          "locations: \(read()?.locations.map(\.name) ?? [])")
    check("its folder left the locations folder",
          !fm.fileExists(atPath: shed.path))
    check("and nothing was destroyed — it is in z-deleted",
          fm.fileExists(atPath: locationsRoot
              .appending(path: "z-deleted/The Shed/tools.jpg").path))

    // And a folder of that name made by hand *afterwards* is his decision,
    // so it is honoured as new rather than swept away for ever.
    try? fm.createDirectory(at: shed, withIntermediateDirectories: true)
    runBridge()
    runBridge()
    check("a folder made again by hand is honoured as a new place",
          read()?.locations.contains { $0.name == "The Shed" } == true,
          "locations: \(read()?.locations.map(\.name) ?? [])")
    if let again = read()?.locations.first(where: { $0.name == "The Shed" }) {
        engine.call("deletelocation", again.id)
        engine.call("save")
        runBridge()
        runBridge()
    }
} else {
    check("a location deleted in the app stays deleted", false, "no engine")
}

heading("A new place never takes an existing one's record — Ref 1070")
// The other half of the same night. The record made in step 5 was found
// again by its *name*, so a loose folder called `Kitchen` handed the house's
// own Kitchen the loose folder's path, a fresh `folder` and `capturedBy` —
// and the room's photographs went with the pairing. Names are not identities.
if let engine = Engine(path: project.path),
   let room = read()?.locations.first(where: { $0.name == "Kitchen" && !$0.parent.isEmpty }) {
    let before = room.driveFolder
    try? fm.createDirectory(at: locationsRoot.appending(path: "Kitchen"),
                            withIntermediateDirectories: true)
    runBridge()
    runBridge()

    let after = read()?.locations.first { $0.id == room.id }
    check("the house's room kept its own folder", after?.driveFolder == before,
          "was \(before), now \(after?.driveFolder ?? "none")")
    check("and the loose folder became a place of its own",
          read()?.locations.contains {
              $0.parent.isEmpty && $0.name == "Kitchen" && $0.driveFolder == "Kitchen"
          } == true,
          "locations: \(read()?.locations.map { "\($0.name)=\($0.driveFolder)" } ?? [])")

    if let loose = read()?.locations.first(where: { $0.parent.isEmpty && $0.name == "Kitchen" }) {
        engine.call("deletelocation", loose.id)
        engine.call("save")
        runBridge()
        runBridge()
    }
    _ = engine
} else {
    check("a new place never takes an existing one's record", false, "no room to protect")
}

// ---- the switch, and the list that no longer needs a rebuild --------------------
//
// Ref 229, his ask: *"It happens in the BG right now, but it's something that
// should be visible and something I can opt into if I so chose."* And the half
// of Ref 193 that this closes: covering a new film used to mean editing a text
// file **and** rebuilding the app, because the list was copied into the bundle
// at build time — and editing the text file alone silently did nothing.

heading("A place he has switched off is left alone")
if let mansionPlace = read()?.locations.first(where: { $0.name == "The Mansion" }) {
    let before = photographs()
    setSwitch(mansionPlace.id, "0")
    // A name nothing else in this file uses — `attic.jpg` is already on this
    // location from the check above, and a check that cannot fail is worse
    // than no check.
    writePhotograph("porch.jpg", red: 0.7, into: mansion)
    let offRun = runBridge()
    runBridge()

    check("it said the place is off", offRun.contains("not syncing with Drive"), offRun)
    check("the new photograph did not come into the project",
          !photographs().contains("porch.jpg"), "has: \(photographs())")
    check("and the ones already there were not taken away",
          photographs() == before, "was: \(before), now: \(photographs())")
    check("nothing in Drive was moved to z-deleted",
          !fm.fileExists(atPath: mansion.appending(path: "z-deleted").path))
    check("and it did not come back as a second location",
          read()?.locations.filter { $0.name == "The Mansion" }.count == 1,
          "locations: \(read()?.locations.map(\.name) ?? [])")

    heading("Switched back on, it picks up what it missed")
    setSwitch(mansionPlace.id, "1")
    runBridge()
    check("the photograph added while it was off comes in now",
          photographs().contains("porch.jpg"), "has: \(photographs())")
} else {
    check("a place he has switched off is left alone", false, "no location to switch off")
}

heading("A film that says where it lives needs no list and no rebuild")
// No `--only`, and nothing in a projects.txt anywhere near the scratch build —
// so under the old rule this film would have been skipped as "not listed".
let driveProjectFolder = driveFolder.appending(path: "test-bridge")
setProjectFolder(driveProjectFolder.path)
writePhotograph("cellar.jpg", red: 0.3, into: mansion)
let unlisted = runBridge(withOnly: false)
check("it was not turned away for not being on a list",
      !unlisted.contains("add 'test-bridge' to projects.txt"), unlisted)
check("and it carried the new photograph",
      photographs().contains("cellar.jpg"), "has: \(photographs())")

heading("A film that has not said where it lives is left alone")
setProjectFolder("")
let unlinked = runBridge(withOnly: false)
check("it said the film is not linked to a Drive folder",
      unlinked.contains("not linked"), unlinked)

// ---- mood boards ----------------------------------------------------------------
//
// Ref 229's second half, built 2026-08-30 once boards existed. His answers that
// day: a board's pictures go to **`1-creative/reference/<board>`** inside the
// film, and a board is **off until he switches it on** — the opposite of a
// location, because no board has ever been carried and there is nothing to
// grandfather.

setProjectFolder(driveProjectFolder.path)
let reference = driveProjectFolder.appending(path: "1-creative/reference")

func inReference(_ board: String) -> [String] {
    ((try? fm.contentsOfDirectory(at: reference.appending(path: board),
                                  includingPropertiesForKeys: nil)) ?? [])
        .map(\.lastPathComponent).filter { $0.hasSuffix(".jpg") }.sorted()
}

heading("A board nobody has switched on is left alone")
try? fm.createDirectory(at: reference, withIntermediateDirectories: true)
if let tone = addBoard("Tone") {
    putOnBoard(tone, "sodium.jpg", red: 0.8)
    let untouched = runBridge(withOnly: false)
    check("no folder was made for it",
          !fm.fileExists(atPath: reference.appending(path: "Tone").path),
          untouched)
    check("and its picture did not leave the app", inReference("Tone").isEmpty,
          "in Drive: \(inReference("Tone"))")

    heading("Switched on, a board's pictures go to 1-creative/reference")
    setBoardSwitch(tone, "1")
    runBridge(withOnly: false)
    check("the folder is under reference, named after the board",
          fm.fileExists(atPath: reference.appending(path: "Tone").path),
          "looked for \(reference.appending(path: "Tone").path)")
    check("the picture is in it", inReference("Tone") == ["sodium.jpg"],
          "in Drive: \(inReference("Tone"))")
    check("the engine wrote down which folder it is",
          read()?.boards.first { $0.name == "Tone" }?.driveFolder == "Tone",
          "holds: \(read()?.boards.first { $0.name == "Tone" }?.driveFolder ?? "none")")

    heading("A picture dropped into the board's folder in Drive reaches the board")
    writePhotograph("streetlight.jpg", red: 0.2, into: reference.appending(path: "Tone"))
    runBridge(withOnly: false)
    check("the board has it now", boardPictures("Tone").contains("streetlight.jpg"),
          "board has: \(boardPictures("Tone"))")

    heading("Renaming a board renames its folder rather than orphaning it")
    if let engine = Engine(path: project.path) {
        engine.call("renameboard", tone, "Night tone")
        engine.call("save")
    }
    runBridge(withOnly: false)
    check("the new folder is there", fm.fileExists(atPath: reference.appending(path: "Night tone").path))
    check("and the old one is gone", !fm.fileExists(atPath: reference.appending(path: "Tone").path))
    check("both pictures came with it", inReference("Night tone").count == 2,
          "in Drive: \(inReference("Night tone"))")

    heading("A folder made by hand in reference does not become a board")
    // The difference from `locations`, and the reason it is deliberate: a
    // folder under `locations` can only be a location, while `reference` is a
    // pile he keeps stills in himself.
    try? fm.createDirectory(at: reference.appending(path: "Shotdeck grabs"),
                            withIntermediateDirectories: true)
    runBridge(withOnly: false)
    runBridge(withOnly: false)
    check("no board was invented for it",
          read()?.boards.contains { $0.name == "Shotdeck grabs" } == false,
          "boards: \(read()?.boards.map(\.name) ?? [])")

    heading("Switched off again, a board is left completely alone")
    setBoardSwitch(tone, "0")
    writePhotograph("neon.jpg", red: 0.6, into: reference.appending(path: "Night tone"))
    let offBoard = runBridge(withOnly: false)
    check("it said the board is off", offBoard.contains("not syncing with Drive"), offBoard)
    check("the new picture did not come into the app",
          !boardPictures("Night tone").contains("neon.jpg"),
          "board has: \(boardPictures("Night tone"))")
    check("and nothing already in Drive was moved to z-deleted",
          !fm.fileExists(atPath: reference.appending(path: "Night tone/z-deleted").path))
} else {
    check("a board nobody has switched on is left alone", false, "no board could be made")
}

// ---- the shot list's stills ------------------------------------------------------
//
// His ask, 2026-09-02: every picture on a shot published into the film's Drive
// folder, named after the shot. His three rulings that shape it — inside
// `1-creative`, in a folder called `shot list`, with the pictures in a
// subfolder; named `3G.jpg`, `3G-2.jpg`; and **out only**, so nothing here is
// ever imported and nothing of his is ever touched.

let shotStills = driveProjectFolder.appending(path: "1-creative/shot list/stills")

func inShotStills() -> [String] {
    ((try? fm.contentsOfDirectory(at: shotStills, includingPropertiesForKeys: nil)) ?? [])
        .map(\.lastPathComponent).filter { !$0.hasPrefix("z-") }.sorted()
}

heading("The shot stills half is retired: nothing is published, nothing of his is touched")
if let shot = addShot(inScene: "7") {
    putOnShot(shot.id, "whatever-the-file-was-called.jpg", red: 0.5)
    writePhotograph("someone-elses-note.jpg", red: 0.1, into: shotStills)
    runBridge(withOnly: false)
    runBridge(withOnly: false)
    check("a picture on a shot is no longer written to Drive",
          inShotStills() == ["someone-elses-note.jpg"],
          "in the folder: \(inShotStills())")
    check("a file of his own is left alone",
          inShotStills().contains("someone-elses-note.jpg"))
    check("and nothing was moved aside",
          !fm.fileExists(atPath: shotStills.appending(path: "z-deleted").path))
} else {
    check("the retired shot stills half stays quiet", false, "no shot could be made")
}

// ---- clean up ------------------------------------------------------------------

try? fm.removeItem(at: scratch)

print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
