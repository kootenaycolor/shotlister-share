import Foundation

/// The checks' side of `shared/ExportPresets.swift`: a copy of its own, no server.
extension ExportPresets {
    nonisolated static var platformChecking: Bool { true }
    nonisolated static var platformFolder: String { "" }
    nonisolated static var platformSetupsKey: String { "export.phonechecks" }
    nonisolated static var platformMachine: String { "checks" }
    nonisolated static func platformServer() -> (String, String)? { nil }
}

// What the phone cannot be allowed to get wrong.
//
// Two bugs on 2026-08-21 were each a single assertion away from being caught,
// and both of them looked to him like lost work:
//
// - **Nothing was saving.** Every edit was perfect on screen and gone on the
//   next open. Found by accident, in a screenshot taken for something else.
// - **One missing field emptied the whole app.** A location's photograph has no
//   lead-frame flag; a shot's has. Swift's decoder is all-or-nothing, so the
//   view refused to decode and every screen drew as an empty film.
//
// This runs the phone's own `Engine.View` — the real structs, not a copy — over
// his real projects, and exercises the writing on scratch copies. It never
// writes to anything of his, and it launches nothing, so it cannot disturb him.

let fm = FileManager.default
var passed = 0, failed = 0

func check(_ what: String, _ body: () throws -> Bool) {
    do {
        if try body() { passed += 1; print("  ✓ \(what)") }
        else { failed += 1; print("  ✗ \(what)") }
    } catch {
        failed += 1
        print("  ✗ \(what) — \(error)")
    }
}

// ---- talking to the engine --------------------------------------------------

final class Project {
    private let handle: OpaquePointer
    init?(_ path: String, device: UInt64 = 4242) {
        guard let h = path.withCString({ sl_open_as($0, device) }) else { return nil }
        handle = h
    }
    deinit { sl_close(handle) }

    @discardableResult
    func call(_ parts: String...) -> Data { call(parts) }

    @discardableResult
    func call(_ parts: [String]) -> Data {
        let line = parts.joined(separator: "\t")
        guard let reply = line.withCString({ sl_call(handle, $0) }) else { return Data() }
        defer { sl_free(reply) }
        return Data(String(cString: reply).utf8)
    }

    func view() throws -> Engine.View {
        try JSONDecoder().decode(Engine.View.self, from: call("view"))
    }

    /// The days and their strips — the engine's own answer, which is *not* a
    /// view. Handing this to the view decoder is the mistake the schedule
    /// screen exists to avoid.
    func schedule() throws -> Engine.Schedule {
        try JSONDecoder().decode(Engine.Schedule.self, from: call("board"))
    }

    /// Changes made and not yet written down, as the engine counts them. This
    /// is what the phone now watches to decide whether to save.
    func unsaved() throws -> Int { try view().project.unsaved }
}

/// A copy nobody minds being written to.
func scratch(_ name: String) -> URL? {
    let source = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .deletingLastPathComponent()
        .appending(path: "studio/fixtures/Daybreak.shotlist")
    let into = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "phone-checks-\(name).shotlist")
    try? fm.removeItem(at: into)
    guard (try? fm.copyItem(at: source, to: into)) != nil else { return nil }
    return into
}

// ---- 1. his real projects still open ---------------------------------------

print("\nEvery project this Mac can see, read with the phone's own decoder")

var looked = 0
for folder in [
    fm.homeDirectoryForCurrentUser.appending(path: "Library/Mobile Documents/com~apple~CloudDocs/Shotlister"),
    URL(fileURLWithPath: fm.currentDirectoryPath).deletingLastPathComponent().appending(path: "studio/fixtures"),
] {
    for project in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    where project.pathExtension == "shotlist" {
        looked += 1
        // Named by where it came from: his own projects and the fixtures can
        // share a name, and "Daybreak.shotlist decodes" twice says nothing
        // about which one broke.
        let where_ = folder.lastPathComponent == "fixtures" ? "fixture" : "iCloud"
        check("\(project.lastPathComponent) (\(where_)) decodes") {
            // **Read from a copy, never from his own film.**
            //
            // This opened his projects where they lie, on the belief that
            // opening one only ever *reads* it. That was never quite true —
            // `storage::open_as` folds old logs together and reclaims orphaned
            // pictures, both of which write — and it stops being true the
            // moment anything is added to that list. A battery that quietly
            // rewrites the three films he is working in is a check causing the
            // class of failure it exists to catch. Noticed 2026-08-31 while a
            // migration was being written; the migration was dropped and this
            // was worth keeping.
            //
            // The copy is `media`-less on purpose: the decode is what is being
            // tested and the pictures are the slow, large half.
            let copy = URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "phone-checks-read-\(project.lastPathComponent)")
            try? fm.removeItem(at: copy)
            try fm.createDirectory(at: copy, withIntermediateDirectories: true)
            for part in ["manifest.json", "changes", "locations"] {
                let from = project.appending(path: part)
                if fm.fileExists(atPath: from.path) {
                    try? fm.copyItem(at: from, to: copy.appending(path: part))
                }
            }
            defer { try? fm.removeItem(at: copy) }
            guard let p = Project(copy.path) else { return false }
            _ = try p.view()
            return true
        }
    }
}
if looked == 0 { print("  (no projects found to read)") }

// ---- 2. the relaunch law ----------------------------------------------------

print("\nThe relaunch law — nothing counts as working unless it survives reopening")

check("a shot's field is still there after closing and reopening") {
    guard let path = scratch("save") else { return false }
    var shot = ""
    do {
        guard let p = Project(path.path) else { return false }
        let view = try p.view()
        guard let row = view.groups.flatMap(\.rows).first else { return false }
        shot = row.shot
        p.call("set", shot, "lens", "999mm")
        p.call("save")
    }
    guard let again = Project(path.path) else { return false }
    let after = try again.view()
    return after.groups.flatMap(\.rows).first(where: { $0.shot == shot })?.lens == "999mm"
}

check("a location is still there after closing and reopening") {
    guard let path = scratch("location") else { return false }
    do {
        guard let p = Project(path.path) else { return false }
        p.call("addlocation", "Checking Barn")
        p.call("save")
    }
    guard let again = Project(path.path) else { return false }
    return try again.view().locations.contains { $0.name == "Checking Barn" }
}

// **Sync with Drive, both ways round** — Ref 229. The phone hand-writes its
// `CodingKeys`, so a field the engine emits and the phone forgets to list is
// silently nought — and a switch that reads as off on the phone and on on the
// Mac is the worst kind of disagreement, because both screens look right.
//
// The two defaults are the whole point of the check: a location nobody has
// asked about **carries**, a board nobody has asked about **does not**.
check("a location's Sync with Drive switch reaches the phone") {
    guard let path = scratch("drivelocation") else { return false }
    do {
        guard let p = Project(path.path) else { return false }
        p.call("addlocation", "Checking Barn")
        p.call("save")
    }
    guard let p = Project(path.path),
          let place = try p.view().locations.first(where: { $0.name == "Checking Barn" })
    else { return false }
    guard place.syncsWithDrive else { return false }   // nobody asked → carries
    p.call("setlocation", place.id, "syncWithDrive", "0")
    p.call("save")
    guard let again = Project(path.path),
          let off = try again.view().locations.first(where: { $0.name == "Checking Barn" })
    else { return false }
    return off.syncWithDrive == "0" && !off.syncsWithDrive
}

check("a board's Sync with Drive switch reaches the phone, and starts off") {
    guard let path = scratch("driveboard") else { return false }
    do {
        guard let p = Project(path.path) else { return false }
        p.call("addboard", "Night tone")
        p.call("save")
    }
    guard let p = Project(path.path),
          let board = try p.view().boards.first(where: { $0.name == "Night tone" })
    else { return false }
    guard !board.syncsWithDrive else { return false }  // nobody asked → does not
    p.call("set", board.id, "sync_with_drive", "1")
    p.call("save")
    guard let again = Project(path.path),
          let on = try again.view().boards.first(where: { $0.name == "Night tone" })
    else { return false }
    return on.syncsWithDrive
}

// ---- 2b. every editing command owns up to being one -------------------------
//
// **The check the phone did not have, for the bug that has bitten twice.**
// Ref 194.
//
// The engine holds a change in memory and writes when it is told to. Which
// commands count as a change used to be a hand-kept list of names in
// `Session.swift`, and the danger was never that the list was wrong — it is
// that **adding an editing command and forgetting the list puts the
// edits-die-with-the-process bug straight back with every check still green.**
// Nothing could catch that, because the list was the only statement of what an
// edit was.
//
// There is no list now: the phone saves when the engine says it has unsaved
// work. So this walks every editing command the phone can send and insists the
// engine owns up to each one. A new command is covered the day it is written —
// and if one ever stops reporting, this goes red instead of the work going
// quietly missing.

print("\nEvery command that changes something says so")

/// One editing command, run on a clean scratch copy, asked whether the engine
/// noticed. `build` gets the view so it can name real ids rather than guesses.
func changes(_ what: String,
             prepare: ((Project) -> Void)? = nil,
             _ build: (Engine.View) -> [String]?) {
    check("\(what)") {
        guard let path = scratch("dirty") else { return false }
        guard let p = Project(path.path) else { return false }
        // Anything the command needs to exist before it can be run — a
        // sequence to put a scene in, say. Done before the baseline, so it is
        // never mistaken for the change being measured.
        prepare?(p)
        // Start from nothing owing, so what is counted afterwards is this
        // command's doing and not the fixture's.
        p.call("save")
        guard try p.unsaved() == 0 else { return false }
        guard let parts = build(try p.view()), !parts.isEmpty else { return false }
        let reply = p.call(parts)
        // A command the engine refused proves nothing either way, and a silent
        // pass here would be worse than no check at all.
        struct Problem: Decodable { var error: String }
        if let refused = try? JSONDecoder().decode(Problem.self, from: reply) {
            print("      (engine refused: \(refused.error))")
            return false
        }
        return try p.unsaved() > 0
    }
}

func shot(_ v: Engine.View) -> Engine.Row? { v.groups.flatMap(\.rows).first }
func shots(_ v: Engine.View) -> [Engine.Row] { v.groups.flatMap(\.rows) }

/// One pixel is a photograph as far as the engine is concerned.
let pixel = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

// the shot itself
changes("setting one field") { v in shot(v).map { ["set", $0.shot, "lens", "40mm"] } }
changes("setting many shots at once") { v in
    let ids = shots(v).prefix(3).map(\.shot).joined(separator: ",")
    return ids.isEmpty ? nil : ["setmany", ids, "lens", "40mm"]
}
changes("clearing a column on many shots") { v in
    let ids = shots(v).prefix(3).map(\.shot).joined(separator: ",")
    return ids.isEmpty ? nil : ["clearcells", "lens=\(ids)"]
}
changes("cutting a shot") { v in shot(v).map { ["strike", $0.shot, "1"] } }
changes("putting a picture on a shot") { v in
    shot(v).map { ["paste", $0.shot, "1", "1", "png", pixel, "image", "0", "check.png"] }
}

// Ref 211. A picture the project already stores goes on a second shot as a
// record, with no bytes moving at all — which is exactly the shape of command
// that could quietly not report itself.
var alreadyStored = ""
changes("putting a picture the project already has on another shot",
        prepare: { p in
            guard let before = try? p.view(), let first = shot(before) else { return }
            p.call("paste", first.shot, "1", "1", "png", pixel, "image", "0", "check.png")
            struct Held: Decodable { var here: Bool; var media: String }
            guard let after = try? p.view(),
                  let stored = shot(after)?.stills.first?.hash,
                  let held = try? JSONDecoder().decode(Held.self, from: p.call("have", stored)),
                  held.here else { return }
            alreadyStored = held.media
        }) { v in
    let rows = shots(v)
    guard rows.count > 1, !alreadyStored.isEmpty else { return nil }
    return ["use", rows[1].shot, alreadyStored]
}

// the list
changes("adding a shot") { v in v.scenes.first.map { ["addshot", $0.id, ""] } }
changes("duplicating a shot") { v in shot(v).map { ["duplicate", $0.placement] } }
changes("deleting a shot") { v in shot(v).map { ["delete", $0.placement] } }
changes("moving a shot within its scene") { v in shot(v).map { ["reorder", $0.placement, "0"] } }
changes("moving a shot to another scene") { v in
    guard let row = shot(v), let into = v.scenes.first(where: { $0.id != row.sceneId }) else { return nil }
    return ["movescene", row.placement, into.id]
}
changes("copying shots into another scene") { v in
    guard let row = shot(v), let into = v.scenes.first(where: { $0.id != row.sceneId }) else { return nil }
    return ["copyshots", row.placement, into.id, ""]
}
changes("adding a scene") { _ in ["addscene", "999"] }
changes("archiving a scene") { v in v.scenes.first.map { ["archivescene", $0.id, "1"] } }
// The engine will not delete a scene that has not been archived first — his
// rule, and a good one. Archiving is the prepare step, not the thing measured.
changes("deleting a scene",
        prepare: { p in
            guard let scene = try? p.view().scenes.first else { return }
            p.call("archivescene", scene.id, "1")
        }) { v in v.scenes.first.map { ["deletescene", $0.id] } }

// the things a project owns
changes("adding a camera") { _ in ["addunit", "Z-Cam", "red"] }
changes("adding a sequence") { _ in ["addsequence", "Checking Sequence"] }
changes("putting a scene in a sequence",
        prepare: { $0.call("addsequence", "Checking Sequence") }) { v in
    guard let scene = v.scenes.first, let seq = v.sequences.last else { return nil }
    return ["set", scene.id, "sequence", seq.id]
}
changes("adding a place") { _ in ["addlocation", "Checking Barn"] }
// The fixture has no places, so one is made first — otherwise these pass by
// finding nothing to do, which is the shape of check that reads green and
// tests air.
changes("changing a place", prepare: { $0.call("addlocation", "Checking Barn") }) { v in
    v.locations.first.map { ["setlocation", $0.id, "notes", "gate code 1234"] }
}
changes("deleting a place", prepare: { $0.call("addlocation", "Checking Barn") }) { v in
    v.locations.first.map { ["deletelocation", $0.id] }
}
changes("adding a room inside a place", prepare: { $0.call("addlocation", "Checking House") }) { v in
    v.locations.first.map { ["addarea", $0.id, "Kitchen"] }
}

// the shape of the project
changes("adding a column") { _ in ["addcolumn", "single", "Filter"] }
// Only a column the project made can be renamed or deleted, and the fixture
// has none — so one is made first.
changes("renaming a column", prepare: { $0.call("addcolumn", "single", "Filter") }) { v in
    v.columns.first { $0.kind != nil }.map { ["renamecolumn", $0.name, "Renamed"] }
}
changes("deleting a column", prepare: { $0.call("addcolumn", "single", "Filter") }) { v in
    v.columns.first { $0.kind != nil }.map { ["deletecolumn", $0.name] }
}
changes("reordering the columns") { v in
    let names = v.columns.map(\.name)
    guard names.count > 1 else { return nil }
    return ["columnorder", (Array(names.dropFirst()) + [names[0]]).joined(separator: ",")]
}
changes("hiding a column") { v in
    v.columns.first { $0.visible }.map { ["column", $0.name, "0"] }
}
changes("showing a column") { v in
    v.columns.first { !$0.visible }.map { ["column", $0.name, "1"] }
}

// a clip's own facts — trim and poster, 2026-08-30. The trim is a range on
// *this use* of the file and the engine puts it on any media ref, so these run
// against the fixture's pictures: what is being checked is that the phone asks
// for it, reads it back and can take it away again.
changes("trimming a clip") { v in
    shot(v).flatMap { $0.stills.first }.map { ["trim", $0.ref, "1.5", "4.0"] }
}
changes("taking the trim off again", prepare: { p in
    guard let v = try? p.view(), let still = shot(v)?.stills.first else { return }
    p.call("trim", still.ref, "1.5", "4.0")
}) { v in
    shot(v).flatMap { $0.stills.first }.map { ["trim", $0.ref, "clear"] }
}

// how a picture is framed when it is drawn cropped — his ask, 2026-08-30.
changes("framing a picture") { v in
    shot(v).flatMap { $0.stills.first }.map { ["crop", $0.ref, "0.2", "0.8", "1.5"] }
}
changes("putting the framing back", prepare: { p in
    guard let v = try? p.view(), let still = shot(v)?.stills.first else { return }
    p.call("crop", still.ref, "0.2", "0.8", "1.5")
}) { v in
    shot(v).flatMap { $0.stills.first }.map { ["crop", $0.ref, "clear"] }
}

// the shoot days themselves — the Schedule tab, 2026-08-30
changes("adding a shoot day") { _ in ["day", "new"] }
changes("naming a shoot day") { v in v.days.first.map { ["day", "name", $0.id, "Studio"] } }
changes("dating a shoot day") { v in v.days.first.map { ["day", "date", $0.id, "2026-09-12"] } }
changes("moving a shoot day") { v in v.days.last.map { ["day", "move", $0.id, "0"] } }
changes("removing a shoot day") { v in v.days.last.map { ["day", "remove", $0.id] } }

// a scene's own facts — the page the phone gained on 2026-08-30. A scene is a
// record like any other, so these go through `set`; only the shoot day is a
// command of its own.
changes("setting a scene's synopsis") { v in
    v.scenes.first.map { ["set", $0.id, "description", "He waits for the light."] }
}
changes("setting a scene's number") { v in
    v.scenes.first.map { ["set", $0.id, "number", "12A"] }
}
changes("putting a scene on a shoot day") { v in
    guard let scene = v.scenes.first, let day = v.days.first else { return nil }
    return ["scene", scene.id, day.id]
}
changes("taking a scene off its shoot day", prepare: { p in
    guard let v = try? p.view(), let scene = v.scenes.first, let day = v.days.first else { return }
    p.call("scene", scene.id, day.id)
}) { v in
    v.scenes.first.map { ["scene", $0.id, "none"] }
}
changes("pointing a scene at a place", prepare: { $0.call("addlocation", "The Motel") }) { v in
    guard let scene = v.scenes.first, let place = v.locations.first else { return nil }
    return ["addscenelocation", scene.id, place.id]
}

// mood boards — Ref 347. A board is an owner like any other, so only the three
// commands that make and name one are its own; the picture on it goes through
// the same `paste` a shot's frame does.
func aBoard(_ p: Project) { p.call("addboard", "Night Exteriors") }
changes("making a mood board") { _ in ["addboard", "Night Exteriors"] }
changes("renaming a mood board", prepare: aBoard) { v in
    v.boards.first.map { ["renameboard", $0.id, "The Diner"] }
}
changes("deleting a mood board", prepare: aBoard) { v in
    v.boards.first.map { ["deleteboard", $0.id] }
}
changes("putting a picture on a mood board", prepare: aBoard) { v in
    v.boards.first.map { ["paste", $0.id, "1", "1", "png", pixel, "image", "0", "check.png"] }
}
changes("hanging a mood board on a scene", prepare: aBoard) { v in
    guard let board = v.boards.first, let scene = v.scenes.first else { return nil }
    return ["addsceneboard", scene.id, board.id]
}
changes("taking a mood board off a scene", prepare: { p in
    aBoard(p)
    guard let v = try? p.view(), let board = v.boards.first, let scene = v.scenes.first else { return }
    p.call("addsceneboard", scene.id, board.id)
}) { v in
    guard let board = v.boards.first, let scene = v.scenes.first else { return nil }
    return ["removesceneboard", scene.id, board.id]
}

// **And the other way round**, which is what stops all of the above from being
// a check that says yes to everything. A command that only *asks* must leave
// nothing owing — otherwise the phone would write to disk on every search
// keystroke, and this whole section would be green whatever it was pointed at.
for asking in [["view"], ["sort", "lens", "asc"], ["filter", "0", "wide"],
               ["facet", "lens", ""], ["vocab", "lens"], ["board"], ["lists"]] {
    check("\(asking[0]) only asks, and leaves nothing to save") {
        guard let path = scratch("asking") else { return false }
        guard let p = Project(path.path) else { return false }
        p.call("save")
        guard try p.unsaved() == 0 else { return false }
        p.call(asking)
        return try p.unsaved() == 0
    }
}

// ---- 2c. and it actually reaches the disk -----------------------------------
//
// Owning up is half of it. The other half is that the phone acts on the
// admission — which is what the relaunch checks above prove for `set`. This
// proves it for a command written *after* the save list was thrown away, which
// is precisely the case the old list could not cover.

check("a change made by a command nobody listed still survives a relaunch") {
    guard let path = scratch("newcommand") else { return false }
    var ids: [String] = []
    do {
        guard let p = Project(path.path) else { return false }
        ids = shots(try p.view()).prefix(3).map(\.shot)
        guard !ids.isEmpty else { return false }
        p.call("setmany", ids.joined(separator: ","), "lens", "123mm")
        // Exactly what the app does: the engine says it owes something, so it
        // is told to write.
        if try p.unsaved() > 0 { p.call("save") }
    }
    guard let again = Project(path.path) else { return false }
    let after = shots(try again.view()).filter { ids.contains($0.shot) }
    return after.count == ids.count && after.allSatisfy { $0.lens == "123mm" }
}

// ---- 2d. two devices --------------------------------------------------------
//
// **The phone had no merge check at all** — the Mac has had them for a while.
// This is the case that matters on a set: he changes something on the Mac, and
// the phone is supposed to notice without being closed and opened again.

print("\nTwo devices, one project")

check("what the Mac changed arrives when the phone pulls") {
    guard let path = scratch("merge") else { return false }
    // Two engines on one folder, each with its own name to the sync log — a
    // device that shares a name with another looks like one device agreeing
    // with itself, and nothing would ever be detected as coming from elsewhere.
    guard let mac = Project(path.path, device: 111),
          let phone = Project(path.path, device: 222) else { return false }
    guard let row = shot(try mac.view()) else { return false }

    mac.call("set", row.shot, "lens", "1000mm")
    mac.call("save")

    // Before the pull the phone is still reading its own copy, which is the
    // whole reason a pull is needed.
    let before = shots(try phone.view()).first { $0.shot == row.shot }?.lens
    struct Pull: Decodable { var merged: Int }
    let pulled = try JSONDecoder().decode(Pull.self, from: phone.call("pull"))
    let after = shots(try phone.view()).first { $0.shot == row.shot }?.lens

    return before != "1000mm" && pulled.merged > 0 && after == "1000mm"
}

check("a pull with nothing waiting changes nothing and says so") {
    guard let path = scratch("quiet") else { return false }
    guard let phone = Project(path.path, device: 222) else { return false }
    struct Pull: Decodable { var merged: Int }
    let pulled = try JSONDecoder().decode(Pull.self, from: phone.call("pull"))
    // The phone only redraws when this is above nought. If a quiet pull
    // reported work, every screen would rebuild three times a second.
    return pulled.merged == 0
}

check("both devices' edits survive, rather than the later one winning outright") {
    guard let path = scratch("both") else { return false }
    guard let mac = Project(path.path, device: 111),
          let phone = Project(path.path, device: 222) else { return false }
    let rows = shots(try mac.view())
    guard rows.count > 1 else { return false }

    mac.call("set", rows[0].shot, "lens", "18mm")
    mac.call("save")
    phone.call("set", rows[1].shot, "lens", "135mm")
    phone.call("save")
    phone.call("pull")

    let seen = shots(try phone.view())
    return seen.first { $0.shot == rows[0].shot }?.lens == "18mm"
        && seen.first { $0.shot == rows[1].shot }?.lens == "135mm"
}


// ---- 2e. a commercial ---------------------------------------------------------
//
// The phone learned a film's Kind on 2026-09-20 (Ref 961): a commercial's
// scenes are titled, its sequences are sections with a colour, its script is
// text on a section quoted by shots. Every fact here is read with the phone's
// own decoder, written through the doors the phone's screens use, and read
// again after reopening.

print("\nA commercial — titled scenes, sections, the script quoted by shots")

check("a commercial's kind, titled scene and section survive reopening") {
    guard let path = scratch("commercial") else { return false }
    var madeScene = ""
    var section = ""
    do {
        guard let p = Project(path.path) else { return false }
        p.call("kind", "commercial")
        let before = Set(try p.view().scenes.map(\.id))
        p.call("addtitled", "Kitchen", "int_ext", "INT.", "location", "KITCHEN", "time_of_day", "DAY")
        let view = try p.view()
        guard view.project.isCommercial, view.project.sequenceWord == "Section" else { return false }
        guard let made = view.scenes.first(where: { !before.contains($0.id) }) else { return false }
        madeScene = made.id
        guard made.title == "Kitchen", made.heading == "Kitchen",
              made.slug == "INT. KITCHEN - DAY", !made.number.isEmpty else { return false }
        p.call("addsequence", "Spot A")
        guard let seq = try p.view().sequences.first(where: { $0.title == "Spot A" }) else { return false }
        section = seq.id
        p.call("set", madeScene, "sequence", section)
        p.call("save")
    }
    guard let again = Project(path.path) else { return false }
    let after = try again.view()
    guard after.project.kind == "commercial" else { return false }
    guard let scene = after.scenes.first(where: { $0.id == madeScene }) else { return false }
    // The section is on the scene itself — a scene with no shots still knows.
    guard scene.sequence == section, scene.title == "Kitchen" else { return false }
    // A section is born with a colour, so the list can wear it.
    return after.sequences.first { $0.id == section }?.colour.isEmpty == false
}

check("a script is text on a section, and a shot quotes a stretch of it") {
    guard let path = scratch("avscript") else { return false }
    var shot = ""
    var section = ""
    let text = "What's up everybody, I hope you're excited.\n\nThank you Denis."
    do {
        guard let p = Project(path.path) else { return false }
        p.call("kind", "commercial")
        p.call("addsequence", "Spot A")
        guard let seq = try p.view().sequences.first(where: { $0.title == "Spot A" }) else { return false }
        section = seq.id
        p.call("setscript", section, text)
        let view = try p.view()
        guard view.scripts.first(where: { $0.section == section })?.text == text else { return false }
        // The Script column shows once the film has a script — and never
        // showed while it was a film.
        guard view.columns.first(where: { $0.name == "script" })?.visible == true else { return false }
        guard let row = view.groups.flatMap(\.rows).first else { return false }
        shot = row.shot
        // "everybody" is UTF-16 10..19 of the text.
        p.call("tieshot", shot, section, "10", "19")
        p.call("save")
    }
    guard let again = Project(path.path) else { return false }
    let after = try again.view()
    guard let row = after.groups.flatMap(\.rows).first(where: { $0.shot == shot }) else { return false }
    guard row.quotesScript, row.scriptOf == section, row.scriptFrom == 10, row.scriptTo == 19,
          row.script == "everybody" else { return false }
    // The cell reads it too, so a list row can draw the quote.
    guard row.cell("script") == ["everybody"] else { return false }
    // Untied: to at or below from.
    again.call("tieshot", shot, "", "0", "0")
    let untied = try again.view().groups.flatMap(\.rows).first { $0.shot == shot }
    return untied?.quotesScript == false && untied?.script == ""
}

check("a film shows no Script column and no scripts") {
    guard let path = scratch("filmscript") else { return false }
    guard let p = Project(path.path) else { return false }
    let view = try p.view()
    return !view.project.isCommercial && view.scripts.isEmpty
        && view.columns.first(where: { $0.name == "script" })?.visible == false
}

// ---- 3. the shape that emptied the app -------------------------------------

print("\nThe shapes that have broken before")

check("a location with a photograph on it still decodes") {
    guard let path = scratch("locmedia") else { return false }
    guard let p = Project(path.path) else { return false }
    p.call("addlocation", "Checking Barn")
    guard let place = try p.view().locations.first(where: { $0.name == "Checking Barn" }) else { return false }
    // One pixel is a photograph as far as the engine is concerned.
    let pixel = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    p.call("paste", place.id, "1", "1", "png", pixel, "image", "0", "check.png")
    let after = try p.view()
    // The bug: a location's picture carries no lead-frame flag, and the phone
    // required one — which threw, and took every screen down with it.
    return after.locations.first(where: { $0.name == "Checking Barn" })?.media.count == 1
}

check("a shot with a frame on it still decodes, and knows its lead frame") {
    guard let path = scratch("shotmedia") else { return false }
    guard let p = Project(path.path) else { return false }
    guard let row = try p.view().groups.flatMap(\.rows).first else { return false }
    let pixel = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    p.call("paste", row.shot, "1", "1", "png", pixel, "image", "0", "check.png")
    let after = try p.view()
    let stills = after.groups.flatMap(\.rows).first(where: { $0.shot == row.shot })?.stills ?? []
    return stills.contains { $0.isLeadFrame }
}

check("a clip put on a shot stays a clip, and comes back whole") {
    guard let path = scratch("clip") else { return false }
    guard let p = Project(path.path) else { return false }
    guard let row = try p.view().groups.flatMap(\.rows).first else { return false }

    // Not a real movie — the engine stores bytes and never looks inside them.
    // What is being checked is that they survive the round trip unaltered and
    // are still filed as a clip at the other end.
    let bytes = Data((0..<4096).map { UInt8($0 % 251) })
    p.call("paste", row.shot, "1280", "720", "mp4",
           bytes.base64EncodedString(), "video", "3.5", "move.mp4")

    let after = try p.view()
    let stills = after.groups.flatMap(\.rows).first(where: { $0.shot == row.shot })?.stills ?? []
    guard let clip = stills.first(where: { $0.kind == .clip }) else { return false }

    struct Reply: Decodable { var data: String }
    let reply = try JSONDecoder().decode(Reply.self, from: p.call("media", clip.hash, "mp4"))
    return Data(base64Encoded: reply.data) == bytes
}

check("a GIF put on a location stays a GIF, and comes back whole") {
    guard let path = scratch("gif") else { return false }
    guard let p = Project(path.path) else { return false }
    guard let place = try p.view().locations.first ?? {
        p.call("addlocation", "Checking")
        return try p.view().locations.first
    }() else { return false }

    // GIF89a and a scrap of payload — enough to be a distinct set of bytes.
    let bytes = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61] + (0..<512).map { UInt8($0 % 251) })
    p.call("paste", place.id, "60", "40", "gif",
           bytes.base64EncodedString(), "gif", "0", "loop.gif")

    guard let after = try p.view().locations.first(where: { $0.id == place.id }),
          let moving = after.media.first(where: { $0.kind == .moving }) else { return false }

    struct Reply: Decodable { var data: String }
    let reply = try JSONDecoder().decode(Reply.self, from: p.call("media", moving.hash, "gif"))
    return Data(base64Encoded: reply.data) == bytes
}

check("a trim comes back on the picture and on the frame beside it") {
    guard let path = scratch("trim") else { return false }
    guard let p = Project(path.path) else { return false }
    guard let still = shot(try p.view())?.stills.first else { return false }
    p.call("trim", still.ref, "1.500", "4.000")
    guard let after = shot(try p.view())?.stills.first(where: { $0.ref == still.ref }) else {
        return false
    }
    // **Both halves.** The frame is what a list draws from, and a trim that
    // reached the picture but not the frame is exactly how a cut clip went on
    // playing whole in every thumbnail on the Mac.
    guard after.trimStart == 1.5, after.trimEnd == 4.0,
          let cut = after.frame.cut, cut.start == 1.5, cut.end == 4.0 else { return false }

    p.call("trim", still.ref, "clear")
    guard let cleared = shot(try p.view())?.stills.first(where: { $0.ref == still.ref }) else {
        return false
    }
    // Absent, not nought: "starts at the very first frame" is a different fact
    // from "was never cut".
    return cleared.trimStart == nil && cleared.trimEnd == nil && cleared.frame.cut == nil
}

check("half a trim is not a trim") {
    // An in point with no out point cannot be played as a range, and drawing it
    // as one would mean a clip that stops at nought seconds.
    let started = Engine.Frame(hash: "a", filename: "a.mp4", said: "video", trimStart: 2, trimEnd: nil)
    let backwards = Engine.Frame(hash: "a", filename: "a.mp4", said: "video", trimStart: 4, trimEnd: 2)
    let whole = Engine.Frame(hash: "a", filename: "a.mp4", said: "video")
    return started.cut == nil && backwards.cut == nil && whole.cut == nil
}

check("the engine's word about a file beats the name on it") {
    // A clip named oddly was drawn as a photograph until the engine's own kind
    // was read. The name is only the fallback now.
    let odd = Engine.Frame(hash: "a", filename: "grab.dat", said: "video")
    let lying = Engine.Frame(hash: "a", filename: "still.png", said: "video")
    let unsaid = Engine.Frame(hash: "a", filename: "clip.mov", said: "")
    return odd.kind == .clip && lying.kind == .clip && unsaid.kind == .clip
}

check("a poster is written beside the clip it stands for") {
    guard let path = scratch("poster") else { return false }
    guard let p = Project(path.path) else { return false }
    guard let still = shot(try p.view())?.stills.first, !still.hash.isEmpty else { return false }
    p.call("poster", still.hash, pixel)
    // Stored under the medium's own contents with a jpg on the end — JPEG
    // since 2026-09-15, PNG before — which is how every reader finds it
    // without being told. This check said png for a day after the engine
    // changed, and was red for it.
    let written = path.appending(path: "media/proxies")
        .appending(path: "\(String(still.hash.prefix(32))).jpg")
    return fm.fileExists(atPath: written.path)
}

check("a framing comes back on the picture and on the frame beside it") {
    guard let path = scratch("crop") else { return false }
    guard let p = Project(path.path) else { return false }
    guard let still = shot(try p.view())?.stills.first else { return false }
    p.call("crop", still.ref, "0.2000", "0.8000", "1.5000")
    guard let after = shot(try p.view())?.stills.first(where: { $0.ref == still.ref }) else {
        return false
    }
    // **Both halves**, the same lesson the trim taught: the frame is what a
    // list draws from, and a framing that reached the picture but not the
    // frame is a thumbnail still showing the middle.
    guard after.framing == Engine.Framing(x: 0.2, y: 0.8, scale: 1.5),
          after.frame.framing == after.framing else { return false }

    p.call("crop", still.ref, "clear")
    guard let cleared = shot(try p.view())?.stills.first(where: { $0.ref == still.ref }) else {
        return false
    }
    // Absent reads as the middle at full width — what everything did before
    // any of this existed.
    return cleared.framing.isMiddle && cleared.frame.framing.isMiddle
}

check("a framing outside the picture is brought back inside it") {
    guard let path = scratch("cropbounds") else { return false }
    guard let p = Project(path.path) else { return false }
    guard let still = shot(try p.view())?.stills.first else { return false }
    // The engine holds the bounds, not three shells agreeing by accident.
    p.call("crop", still.ref, "-3", "9", "99")
    guard let after = shot(try p.view())?.stills.first(where: { $0.ref == still.ref }) else {
        return false
    }
    return after.framing == Engine.Framing(x: 0, y: 1, scale: 8)
}

check("the engine writes a page for the phone to print") {
    guard let path = scratch("printed") else { return false }
    guard let p = Project(path.path) else { return false }
    let page = path.appending(path: "whole.html")
    p.call("print", "table", page.path, "scale=1")
    guard let html = try? String(contentsOf: page, encoding: .utf8) else { return false }
    // The page the phone turns into a PDF is the engine's, not the phone's —
    // so what is checked is that it arrives whole and is about this film.
    return html.contains("<table") && html.lowercased().contains("scene")
}

check("a day's page carries only that day") {
    guard let path = scratch("printedday") else { return false }
    guard let p = Project(path.path) else { return false }
    // **Two days, not one day against the whole film.** The fixture's Day 1
    // holds every shot it has, so "fewer rows than the film" is false there —
    // and the first version of this check failed for that reason and not for
    // the app's. Two days with different counts can only differ if the
    // narrowing actually bites.
    let days = try p.schedule().days.sorted { $0.count > $1.count }
    guard let fullest = days.first, let emptiest = days.last,
          fullest.count > emptiest.count else { return false }
    let busy = path.appending(path: "busy.html")
    let quiet = path.appending(path: "quiet.html")
    p.call("print", "table", busy.path, "day=\(fullest.id)")
    p.call("print", "table", quiet.path, "day=\(emptiest.id)")
    guard let a = try? String(contentsOf: busy, encoding: .utf8),
          let b = try? String(contentsOf: quiet, encoding: .utf8) else { return false }
    func rows(_ page: String) -> Int { page.components(separatedBy: "<tr").count - 1 }
    return rows(a) > rows(b)
}

check("the schedule decodes: days, their strips, and what is still waiting") {
    guard let path = scratch("board") else { return false }
    guard let p = Project(path.path) else { return false }
    let board = try p.schedule()
    // The fixture is scheduled, so both halves must have something in them for
    // this to be saying anything at all.
    guard let lane = board.days.first, !lane.strips.isEmpty else { return false }
    let strip = lane.strips[0]
    return !lane.id.isEmpty && lane.label.hasPrefix("Day")
        && lane.count > 0 && strip.count > 0 && !strip.scene.isEmpty
}

check("a scene taken off its day turns up in what is not scheduled") {
    guard let path = scratch("waiting") else { return false }
    guard let p = Project(path.path) else { return false }
    guard let lane = try p.schedule().days.first, let strip = lane.strips.first else { return false }
    p.call("scene", strip.scene, "none")
    let after = try p.schedule()
    let onADay = after.days.flatMap(\.strips).contains { $0.scene == strip.scene }
    let waiting = after.unscheduled.contains { $0.scene == strip.scene }
    return !onADay && waiting
}

check("and goes back on the day it is put on") {
    guard let path = scratch("backon") else { return false }
    guard let p = Project(path.path) else { return false }
    guard let lane = try p.schedule().days.first, let strip = lane.strips.first else { return false }
    p.call("scene", strip.scene, "none")
    p.call("scene", strip.scene, lane.id)
    let after = try p.schedule()
    return after.days.first { $0.id == lane.id }?.strips.contains { $0.scene == strip.scene } == true
}

// His report, 2026-10-17, on Call Her Back: "Day 3, 3 left", and no way to put
// the three anywhere. A waiting scene put on a day — the phone's drag and its
// menu both say `putscenes` with no day it came from — brings only its shots
// still on no day; the part already on a day stays where it is.
check("drag remaining shots of a partly scheduled scene onto a day") {
    guard let path = scratch("remaining") else { return false }
    guard let p = Project(path.path) else { return false }
    p.call("day", "new")
    let board = try p.schedule()
    guard board.days.count >= 2, let first = board.days.first, let other = board.days.last,
          let strip = first.strips.first(where: { $0.count > 1 }),
          let loose = strip.shots.last else { return false }
    p.call("place", loose.placement, "none")
    let split = try p.schedule()
    guard let waiting = split.unscheduled.first(where: { $0.scene == strip.scene }),
          waiting.shots.map(\.placement) == [loose.placement], waiting.elsewhere.count == 1 else { return false }
    p.call("putscenes", other.id, "", "", strip.scene)
    let after = try p.schedule()
    let stayed = after.days.first { $0.id == first.id }?.strips.first { $0.scene == strip.scene }?.count
    let went = after.days.first { $0.id == other.id }?.strips.first { $0.scene == strip.scene }
    return stayed == strip.count - 1 && went?.count == 1
        && went?.shots.first?.placement == loose.placement
        && !after.unscheduled.contains { $0.scene == strip.scene }
}

check("…and one waiting shot goes onto a day by itself") {
    guard let path = scratch("oneshot") else { return false }
    guard let p = Project(path.path) else { return false }
    p.call("day", "new")
    let board = try p.schedule()
    guard let first = board.days.first, let other = board.days.last, first.id != other.id,
          let strip = first.strips.first(where: { $0.count > 2 }) else { return false }
    let two = strip.shots.suffix(2).map(\.placement)
    for shot in two { p.call("place", shot, "none") }
    p.call("putshots", other.id, "", two[0])
    let after = try p.schedule()
    let waiting = after.unscheduled.first { $0.scene == strip.scene }
    let went = after.days.first { $0.id == other.id }?.strips.first { $0.scene == strip.scene }
    return waiting?.shots.map(\.placement) == [two[1]] && went?.shots.map(\.placement) == [two[0]]
}

check("a day's date comes back on the day, in the shape the engine keeps") {
    guard let path = scratch("daydate") else { return false }
    guard let p = Project(path.path) else { return false }
    guard let lane = try p.schedule().days.first else { return false }
    p.call("day", "date", lane.id, "2026-09-12")
    p.call("day", "name", lane.id, "Studio")
    guard let back = try p.schedule().days.first(where: { $0.id == lane.id }) else { return false }
    // What the date *says* is the reader's own locale — "Sat 12 Sep" here and
    // "Sat, Sep 12" on a US phone — so this asserts that it is said at all and
    // that it is that day, not the exact wording.
    let said = back.said ?? ""
    return back.date == "2026-09-12" && back.title == "Studio"
        && said.contains("12") && said.contains("Sep") && said != back.date
}

check("a scene's own facts come back the way they were written") {
    guard let path = scratch("scenefacts") else { return false }
    guard let p = Project(path.path) else { return false }
    guard let first = try? p.view(), let scene = first.scenes.first,
          let day = first.days.first else { return false }
    p.call("set", scene.id, "description", "He waits for the light.")
    p.call("set", scene.id, "priority", "Must have")
    p.call("set", scene.id, "pov", "Danny, Anna")
    p.call("set", scene.id, "tags", "night, exterior")
    p.call("scene", scene.id, day.id)
    p.call("addlocation", "The Motel")
    guard let made = try? p.view(), let place = made.locations.last else { return false }
    p.call("addscenelocation", scene.id, place.id)
    guard let back = try p.view().scenes.first(where: { $0.id == scene.id }) else { return false }
    return back.description == "He waits for the light."
        && back.priority == "Must have"
        && back.povList == ["Danny", "Anna"]
        && back.tagList == ["night", "exterior"]
        && back.day == day.label
        && back.locations.contains(place.id)
}

check("a mood board with a picture on it still decodes, and the scene knows it") {
    guard let path = scratch("board") else { return false }
    guard let p = Project(path.path) else { return false }
    p.call("addboard", "Night Exteriors")
    guard let made = try? p.view(), let board = made.boards.first,
          let scene = made.scenes.first else { return false }
    p.call("paste", board.id, "1", "1", "png", pixel, "image", "0", "check.png")
    p.call("addsceneboard", scene.id, board.id)
    let v = try p.view()
    guard let back = v.boards.first(where: { $0.id == board.id }) else { return false }
    return back.name == "Night Exteriors"
        && back.media.count == 1
        && back.ratioMode == "original"
        && back.scenes.contains(scene.id)
        && v.scenes.first(where: { $0.id == scene.id })?.boards.contains(board.id) == true
}

check("a mood board's own shape comes back") {
    guard let path = scratch("boardshape") else { return false }
    guard let p = Project(path.path) else { return false }
    p.call("addboard", "Wall")
    guard let made = try? p.view(), let board = made.boards.first else { return false }
    p.call("set", board.id, "board_ratio", "square")
    return try p.view().boards.first?.ratioMode == "square"
}

check("the floor plan the engine works out still decodes") {
    guard let path = scratch("plan") else { return false }
    guard let p = Project(path.path) else { return false }
    // An empty path asks for the engine's own hand-built sample room.
    let plan = try JSONDecoder().decode(Plan.self, from: p.call("floorplan", ""))
    return !plan.items.isEmpty && plan.ceiling > 0
}

check("a scene hidden from Diagrams stays hidden after reopening, and nothing else moves") {
    guard let path = scratch("hidescene") else { return false }
    struct Listed: Decodable { var scenes: [String]; var hidden: [String]? }
    var scene = "", rows = 0
    do {
        guard let p = Project(path.path) else { return false }
        let view = try p.view()
        rows = view.groups.flatMap(\.rows).count
        // A scene with something drawn on it.
        guard let first = view.scenes.first?.id else { return false }
        p.call("diagramedit", first, #"{"op":"add","els":[{"kind":"wall","x":0,"y":0,"x2":4,"y2":0}]}"#)
        guard let drawn = try? JSONDecoder().decode(Listed.self, from: p.call("diagramscenes")), drawn.scenes.contains(first) else { return false }
        scene = first
        guard (drawn.hidden ?? []).isEmpty else { return false }
        p.call("diagramhide", "on", scene)
        p.call("save")
    }
    guard let again = Project(path.path) else { return false }
    let listed = try JSONDecoder().decode(Listed.self, from: again.call("diagramscenes"))
    // Still drawn, still a scene of the project, the shot list as it was.
    let held = listed.hidden == [scene] && listed.scenes.contains(scene)
    let same = try again.view().groups.flatMap(\.rows).count == rows
    again.call("diagramhide", "off", scene)
    let back = try JSONDecoder().decode(Listed.self, from: again.call("diagramscenes")).hidden ?? []
    return held && same && back.isEmpty
}

// ---- the script page ---------------------------------------------------------
//
// The engine sends only the lines that have something on them, each knowing
// which row of the page it sits on. Rebuilding the empty rows between them is
// what makes a screenplay look like one — and getting it wrong is not subtle.
// On 2026-08-22 the phone drew every line hard against the next, and a page
// break came out as a stack of character names with nothing under them. He saw
// it in *Call Her Back*, scene 2.

func page(_ lines: [(row: Int, text: String, added: Bool)], number: Int) -> Script.Page {
    Script.Page(number: number, lines: lines.map {
        Script.Line(row: $0.row, indent: 0, kind: "action", text: $0.text,
                    scene: "2", added: $0.added)
    })
}

check("the blank rows of a script page are put back") {
    let script = Script(revision: "r", name: "Draft", pages: 1, measure: 60,
                        pageList: [page([(0, "SLUG", false),
                                         (1, "action", false),
                                         (4, "after two blanks", false)], number: 1)])
    let drawn = script.drawn(ofScene: "2").map(\.text)
    return drawn == ["SLUG", "action", " ", " ", "after two blanks"]
}

check("a page break is one blank line, not the gap between two page numbers") {
    let script = Script(revision: "r", name: "Draft", pages: 2, measure: 60,
                        pageList: [page([(50, "foot of one", false)], number: 1),
                                   page([(0, "top of two", false)], number: 2)])
    return script.drawn(ofScene: "2").map(\.text) == ["foot of one", " ", "top of two"]
}

check("the paginator's own words are marked as not the writer's") {
    let script = Script(revision: "r", name: "Draft", pages: 1, measure: 60,
                        pageList: [page([(0, "HUSBAND", false),
                                         (1, "(MORE)", true)], number: 1)])
    return script.drawn(ofScene: "2").map(\.faded) == [false, true]
}

check("another scene's lines stay out of this one") {
    var lines = page([(0, "mine", false)], number: 1)
    lines.lines.append(Script.Line(row: 1, indent: 0, kind: "action",
                                   text: "somebody else's", scene: "3", added: false))
    let script = Script(revision: "r", name: "Draft", pages: 1, measure: 60, pageList: [lines])
    return script.drawn(ofScene: "2").map(\.text) == ["mine"]
}

// ---- what a photograph on a place is called ----------------------------------
//
// His ruling of 2026-08-22: a photograph on a location wears the location's
// name, and a room carries its house. Both apps do it, from the one rule in
// `shared/FileNames.swift`, so this is checking the rule rather than a shell.

check("a photograph on a place is named after the place") {
    FileNames.onLocation("Hillcrest House — Kitchen", ext: "jpg", taken: [], from: 0)
        == "hillcrest-house-kitchen-01.jpg"
}

check("the next photograph on a place gets the next number") {
    FileNames.onLocation("The Office", ext: "jpg",
                         taken: ["the-office-01.jpg"], from: 1) == "the-office-02.jpg"
}

check("a number already taken is stepped over rather than written twice") {
    FileNames.onLocation("The Office", ext: "jpg",
                         taken: ["the-office-01.jpg", "the-office-02.jpg"],
                         from: 1) == "the-office-03.jpg"
}

check("a place whose name is all punctuation keeps the file's own name") {
    FileNames.onLocation("— —", ext: "jpg", taken: [], from: 0) == nil
}

// ---- where a location keeps its files ----------------------------------------
//
// The bug of 2026-08-22, and the reason it was invisible: a location made on
// the Mac has no folder, every path is built from that name, and an empty name
// collapsed the path to one bucket outside every location — which the list of a
// place's scans does not read. He tapped Done scanning and the scan was gone.

check("a place with no folder of its own falls back to its id") {
    FileNames.locationFolder(id: "12345", folder: "") == "12345"
        && FileNames.locationFolder(id: "12345", folder: "   ") == "12345"
}

check("a place that has a folder keeps it") {
    FileNames.locationFolder(id: "12345", folder: "ABCD-EF") == "ABCD-EF"
}

check("a scan never lands outside a location again") {
    guard let room = scratch("stray") else { return false }
    let store = LocationStore(project: room)
    // The shape a Mac-made place arrives in: an id, and nothing else.
    let home = FileNames.locationFolder(id: "998877", folder: "")
    let next = store.nextScan(in: home)
    return next.usdz.path.contains("/locations/998877/scans/")
}

check("a stranded scan can be put where it belongs") {
    guard let project = scratch("adopt") else { return false }
    let store = LocationStore(project: project)
    let bucket = project.appending(path: "locations/scans")
    try fm.createDirectory(at: bucket, withIntermediateDirectories: true)
    try Data("shape".utf8).write(to: bucket.appending(path: "RoomScan_X.usdz"))
    try Data("{}".utf8).write(to: bucket.appending(path: "RoomScan_X.json"))

    guard store.stranded().count == 1, let loose = store.stranded().first else { return false }
    try store.adopt(loose, into: "998877")

    // Both halves moved, it reads as a real scan on that place, and nothing is
    // left behind to be offered a second time.
    let landed = store.scans(in: "998877")
    return landed.count == 1
        && landed[0].name == "RoomScan_X"
        && landed[0].isMeasured
        && store.stranded().isEmpty
}

// A room named for where it was scanned (2026-10-17) still knows its files'
// own name and the day it was taken, so the files beside it are not listed
// again as a second room.
check("a renamed scan keeps its files' name and its day") {
    let text = #"{"name":"Mansion · Bathroom · Scan 2","file":"RoomScan_2026-08-27T131411","taken":"Aug 27, 2026 at 1:14 PM","plan":{"ref":"9","hash":"ab","filename":"RoomScan_2026-08-27T131411.json","bytes":3}}"#
    let room = try JSONDecoder().decode(Engine.Room.self, from: Data(text.utf8))
    let old = try JSONDecoder().decode(Engine.Room.self, from: Data(#"{"name":"RoomScan_1"}"#.utf8))
    return room.name == "Mansion · Bathroom · Scan 2"
        && room.file == "RoomScan_2026-08-27T131411"
        && room.taken == "Aug 27, 2026 at 1:14 PM"
        && room.plan?.filename == "RoomScan_2026-08-27T131411.json"
        && old.file.isEmpty && old.taken.isEmpty
}

// ---- his own relay ----------------------------------------------------------
//
// The deciding and the carrying are already covered — `remote/checks.sh` sends a
// real film to a real relay and back byte for byte, and the Worker has 37 checks
// of its own. What is only the phone's is **how it works out where a film lives
// and whether it may go there**, which is different from the Mac's: the Mac is
// told by a file that Set Up Sync wrote, and a phone is told by the film itself.
//
// Nothing here touches the Keychain or the network. The Keychain needs an app's
// entitlement and there is no app here, and a check that reaches the internet is
// a check that fails on a train.

check("a film brings its relay with it") {
    guard let project = scratch("relay") else { return false }
    try Data(#"{"relay":"https://sync.example.com","project":"abc123"}"#.utf8)
        .write(to: project.appending(path: "remote.json"))
    return Relay.address(for: project) == "https://sync.example.com"
}

check("a bare host is an address, and a trailing slash is not part of it") {
    guard let project = scratch("relaytidy") else { return false }
    try Data(#"{"relay":"sync.example.com/","project":"abc123"}"#.utf8)
        .write(to: project.appending(path: "remote.json"))
    return Relay.address(for: project) == "https://sync.example.com"
}

check("a film that has an identity keeps it") {
    guard let project = scratch("relayid") else { return false }
    try Data(#"{"relay":"https://sync.example.com","project":"abc123"}"#.utf8)
        .write(to: project.appending(path: "remote.json"))
    // Asking to make one must not make one when there is already one: that is
    // the same film appearing on the relay twice, and the second copy would be
    // the one nobody's other device knows about.
    return Relay.projectId(at: project) == "abc123"
        && Relay.projectId(at: project, making: true) == "abc123"
}

check("a film with no identity is given one, once") {
    guard let project = scratch("relaynew") else { return false }
    Relay.typedAddress = "https://sync.example.com"
    if Relay.projectId(at: project) != nil { return false }   // nothing yet
    guard let made = Relay.projectId(at: project, making: true) else { return false }
    return made.count == 32
        && made.allSatisfy { $0.isHexDigit }
        && Relay.projectId(at: project) == made               // written down
        && Relay.projectId(at: project, making: true) == made  // and never again
}

// **A film the relay let go is not sent back** — Ref 1033. The relay keeps no
// memory of a film it has let go, so the difference between *taken off* and
// *never sent* lives in the film's own `remote.json`.
check("a film that was on the relay, and is not now, is refused rather than re-sent") {
    guard let project = scratch("relaygone") else { return false }
    let empty = #"{"project":"abc123","logs":[]}"#
    let full = #"{"project":"abc123","logs":[{"name":"1.log","size":10}]}"#
    // Never sent: an empty relay is an empty relay, and the film goes up.
    try Data(#"{"relay":"https://sync.example.com","project":"abc123"}"#.utf8)
        .write(to: project.appending(path: "remote.json"))
    if RelayCarrier.letGo(state: empty, at: project) { return false }
    // Once on the relay: the same empty answer now means somebody took it off.
    try Data(#"{"relay":"https://sync.example.com","project":"abc123","synced":true}"#.utf8)
        .write(to: project.appending(path: "remote.json"))
    guard RelayCarrier.letGo(state: empty, at: project) else { return false }
    // A relay that still holds it is never a refusal.
    if RelayCarrier.letGo(state: full, at: project) { return false }
    // Put Back forgets, and the next sync is allowed to send.
    Relay.allowResend(at: project)
    return !RelayCarrier.letGo(state: empty, at: project)
        && Relay.projectId(at: project) == "abc123"
}

check("no relay means this phone cannot sync, whatever else is set") {
    guard let project = scratch("relayready") else { return false }
    // A film that has never been near a relay, on a phone that has never been
    // told about one. Nothing to sync with, so nothing is offered.
    Relay.typedAddress = ""
    return Relay.address(for: project) == nil && Relay.ready(for: project) == false
}

// **The password half of `ready` is deliberately not checked here**, and the
// reason is worth writing down: this binary runs on a Mac, and on a Mac the
// login Keychain is shared — so `Relay.token` finds *the Mac app's* password
// and answers yes for a phone that has never been set up. It read as a failing
// check and it is not one; it is the check being in the wrong place. On iOS the
// Keychain is the app's own, which is the thing that cannot be tested from
// here. It is covered by running the app: the ⋯ menu offers "Set up sync" and
// no "Sync now" until a password is saved.

// ---- Music Video is a Commercial --------------------------------------------

print("\nProject Types")
check("Music Video is made as a commercial, like Commercial") {
    ProjectTypes.kind("Music Video") == "commercial" && ProjectTypes.kind("Commercial") == "commercial"
}
check("Narrative and Personal stay films") {
    ProjectTypes.kind("Narrative") == "film" && ProjectTypes.kind("Personal") == "film"
}
check("Music Video starts with Commercial's modes") {
    ProjectTypes.startingModes("Music Video") == ProjectTypes.startingModes("Commercial")
        && ProjectTypes.startingModes("Commercial") == ["shot_list", "references", "schedule"]
}
check("Music Video wears Commercial's icon") {
    ProjectTypes.symbol("Music Video") == ProjectTypes.symbol("Commercial")
}
check("New Project offers Music Video") { ProjectTypes.all.contains("Music Video") }

// ---- the tidy leaves what a portal board shows ------------------------------
//
// 2026-10-15: pictures named only by a portal board (the Dump Board) looked like
// strays and were due to be deleted a week after they landed.

/// Run an async body to its end from this top-level script.
func blocking<T>(_ body: @escaping () async -> T) -> T {
    let box = Box<T>()
    let done = DispatchSemaphore(value: 0)
    Task { box.value = await body(); done.signal() }
    done.wait()
    return box.value!
}
final class Box<T> { var value: T? }
final class Deleted { var names: [String] = [] }

let boardPic = String(repeating: "a", count: 32) + ".jpg"
let boardClipPoster = String(repeating: "b", count: 32) + ".jpg"
let orphan = String(repeating: "c", count: 32) + ".jpg"

check("a picture only a portal board names is not deleted; a true orphan still is") {
    let seen = Deleted()
    let gone = blocking {
        await RelayCarrier.clear(
            [boardPic, orphan],
            held: { Set([String(repeating: "a", count: 32)]) },
            delete: { seen.names.append($0); return true })
    }
    return gone == 1 && seen.names == [orphan]
}

check("a clip a board shows keeps its poster too (same stem)") {
    let seen = Deleted()
    let gone = blocking {
        await RelayCarrier.clear(
            [String(repeating: "b", count: 32) + ".mp4", boardClipPoster],
            held: { Set([String(repeating: "b", count: 32)]) },
            delete: { seen.names.append($0); return true })
    }
    return gone == 0 && seen.names.isEmpty
}

check("when the portal cannot be asked, nothing is deleted") {
    let seen = Deleted()
    let gone = blocking {
        await RelayCarrier.clear(
            [boardPic, orphan],
            held: { nil },
            delete: { seen.names.append($0); return true })
    }
    return gone == 0 && seen.names.isEmpty
}

check("a portal with nothing on its boards lets the orphans go") {
    let seen = Deleted()
    let gone = blocking {
        await RelayCarrier.clear([orphan], held: { Set<String>() },
                                 delete: { seen.names.append($0); return true })
    }
    return gone == 1 && seen.names == [orphan]
}

check("the portal's answer is trusted only when it is whole") {
    func held(_ text: String) -> Set<String>? { RelayCarrier.heldStems(in: Data(text.utf8)) }
    return held(#"{"ok":true,"scanned":3,"stems":["aa","bb"]}"#) == Set(["aa", "bb"])
        && held(#"{"ok":true,"scanned":0,"stems":[]}"#) == Set<String>()
        && held(#"{"ok":false,"problem":"no"}"#) == nil
        && held(#"{"ok":true,"stems":["aa"]}"#) == nil
        && held(#"{"ok":true,"scanned":1}"#) == nil
        && held("<html>502</html>") == nil
        && held("") == nil
}

check("the portal's address is the relay's with sync turned to mcp") {
    UserDefaults.standard.removeObject(forKey: "PortalURL")
    return RelayCarrier.hubAddress(forRelay: "https://sync.example.studio") == "https://mcp.example.studio"
}

check("a file's stem is its name without the extension") {
    RelayCarrier.stem(of: boardPic) == String(repeating: "a", count: 32)
        && RelayCarrier.stem(of: "cover.png") == "cover"
}

// ---- the export's Order, Days and Presets (2026-10-15) ----------------------
//
// The same code as the Mac's (`shared/ExportPresets.swift`), so what is
// checked here is what both apps ask the engine for.

print("\nThe export's days, order and presets")

let sixty: ExportInfo = {
    var days: [ExportInfo.Day] = []
    var date = DateComponents(calendar: .current, year: 2026, month: 11, day: 2).date!
    while days.count < 60 {
        if !Calendar.current.isDateInWeekend(date) {
            let say = DateFormatter(); say.dateFormat = "yyyy-MM-dd"; say.locale = Locale(identifier: "en_US_POSIX")
            days.append(.init(id: "d\(days.count + 1)", label: "Day \(days.count + 1)", date: say.string(from: date),
                              count: 2, wrapped: false, shoot: days.count < 30 ? "s1" : "s2"))
        }
        date = Calendar.current.date(byAdding: .day, value: 1, to: date)!
    }
    return ExportInfo(filter: [], sort: "", descending: false, shooting: false, unscheduled: 3, days: days,
                      shoots: [.init(id: "s1", label: "Shoot 1"), .init(id: "s2", label: "Shoot 2")])
}()

check("a range of sixty days picks Days 12 to 18 and nothing else") {
    let picked = ExportDays.pick(DaysRule(kind: "range", from: 12, to: 18, unscheduled: false), in: sixty)
    return picked == Set((12...18).map { "d\($0)" })
}
check("Days 12–18 and 22 read as one line, and as the file name's words") {
    let picked = Set((12...18).map { "d\($0)" } + ["d22"])
    return ExportDays.summary(picked, in: sixty) == "Days 12–18, 22 (8 days)"
        && ExportDays.nameWords(picked, in: sixty) == "days-12-18-22"
}
check("a hand pick is kept as day numbers, a run as a range, a shoot as a shoot") {
    let odd = ExportDays.rule(for: Set((12...18).map { "d\($0)" } + ["d22"]), in: sixty)
    let run = ExportDays.rule(for: Set((12...18).map { "d\($0)" }), in: sixty)
    let shoot = ExportDays.rule(for: Set((31...60).map { "d\($0)" }), in: sixty)
    return odd.kind == "numbers" && odd.numbers == [12, 13, 14, 15, 16, 17, 18, 22]
        && run.kind == "range" && run.from == 12 && run.to == 18
        && shoot.kind == "shoot" && shoot.shoot == 2
}
check("sixty days fold into two shoots of weeks") {
    let groups = ExportDays.groups(of: sixty)
    return groups.count == 2 && groups.allSatisfy { $0.weeks.allSatisfy { $0.days.count <= 5 } }
        && groups.flatMap { $0.weeks.flatMap(\.days) }.count == 60
}
check("a preset round-trips through JSON, and one missing fields still reads") {
    var p = ExportPreset(id: "p-x", name: "Round Trip")
    p.arrange = "schedule"; p.days = DaysRule(kind: "range", from: 12, to: 18); p.output = "perday"
    p.pattern = "{project}-ac-{date}"; p.looks = ["table": .init(orientation: "portrait", scale: 0.8, frames: "small")]
    let back = try JSONDecoder().decode(ExportPreset.self, from: JSONEncoder().encode(p))
    let thin = try JSONDecoder().decode(ExportPreset.self, from: Data(#"{"id":"p-y","name":"Thin","future":1}"#.utf8))
    return back == p && thin.arrange == "table" && thin.pages == ["table"] && thin.auto
}
check("a preset keeps Auto's Size and paper, and one saved before them reads the same bytes") {
    var p = ExportPreset(id: "p-z", name: "Big Auto")
    let say = JSONEncoder()
    say.outputFormatting = .sortedKeys
    let plain = try say.encode(p)
    p.autoAsk = AutoAsk(size: 1.2, paper: "portrait")
    let back = try JSONDecoder().decode(ExportPreset.self, from: JSONEncoder().encode(p))
    var reset = back
    reset.autoAsk = AutoAsk()
    let again = try say.encode(reset)
    return back.autoAsk == AutoAsk(size: 1.2, paper: "portrait") && back.auto
        && again == plain
        && !String(decoding: plain, as: UTF8.self).contains("autoSize")
}
check("Auto's ask: nothing said at 100% and Best Fit, and it is pulled into the slider") {
    AutoAsk().words.isEmpty
        && AutoAsk(size: 1.2, paper: "portrait").words == ["size=1.20", "paper=portrait"]
        && AutoAsk(size: 9, paper: "sideways") == AutoAsk(size: 1.3, paper: "auto")
}
check("three starters ship, and he can delete them") {
    ExportPreset.starters.map(\.name) == ["AC Sheet: Day by Day", "Client: Script Order", "Tomorrow"]
}

if let film = scratch("export60"), let p = Project(film.path) {
    for i in 0..<58 {
        let d = Calendar.current.date(byAdding: .day, value: i, to: DateComponents(calendar: .current, year: 2026, month: 11, day: 2).date!)!
        let say = DateFormatter(); say.dateFormat = "yyyy-MM-dd"; say.locale = Locale(identifier: "en_US_POSIX")
        p.call("day", "new", say.string(from: d))
    }
    let info = (try? JSONDecoder().decode(ExportInfo.self, from: p.call("exportinfo"))) ?? .empty
    if let v = try? p.view() {
        for (i, row) in shots(v).prefix(11).enumerated() where info.days.count > 11 + i {
            p.call("place", row.placement, info.days[11 + i].id)
        }
    }
    let picked = Set(info.days.enumerated().filter { [12, 13, 14, 15, 16, 17, 18, 22].contains($0.offset + 1) }.map(\.element.id))
    let choice = ExportChoice(arrange: .schedule, useFilter: true, picked: picked, whole: true,
                              info: info, label: { $0 })
    let page = { (name: String, options: [String]) -> String in
        let out = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "phone-export-\(name).html")
        p.call(["print", "table", out.path] + options)
        return (try? String(contentsOf: out, encoding: .utf8)) ?? ""
    }
    let mac = page("mac", ["columns=title,description", "scale=1.00", "frames=medium", "order=" + choice.caption] + choice.narrowing)
    let phone = page("phone", choice.narrowing + ["order=" + choice.caption, "frames=medium", "scale=1.00", "columns=title,description"])
    check("the engine sees sixty days, whatever the shoot picker is on") { info.days.count == 60 }
    check("Auto at a Size and a paper: Portrait kept, text and pictures larger") {
        struct Plan: Decodable { let orientation: String; let scale: Double; let picture: Double }
        let ask = { (words: [String]) -> Plan? in
            try? JSONDecoder().decode(Plan.self, from: p.call(["tablelayout", "columns=image,title,description,size"] + words))
        }
        guard let tall = ask(["paper=portrait"]), let wide = ask(["paper=landscape"]),
              let big = ask(AutoAsk(size: 1.2, paper: "portrait").words),
              let small = ask(AutoAsk(size: 0.8, paper: "landscape").words) else { return false }
        return big.orientation == "portrait" && small.orientation == "landscape"
            && big.scale > tall.scale && big.picture > tall.picture
            && small.scale < wide.scale && small.picture < wide.picture
    }
    check("the same choices make the same page on the iPhone as on the Mac, byte for byte") { !mac.isEmpty && mac == phone }
    check("a schedule of Days 12–18 and 22 holds exactly those days, each on its own sheet") {
        let heads = mac.components(separatedBy: "<h2>").dropFirst().compactMap { $0.components(separatedBy: "</h2>").first }
        return heads == ["Day 12", "Day 13", "Day 14", "Day 15", "Day 16", "Day 17", "Day 18", "Day 22"]
            && mac.components(separatedBy: "group fresh-page").count - 1 == 7
    }
    check("the name follows the choice") {
        FileNames.exportAuto(project: "daybreak", document: "shot-list", scope: "", order: choice.orderWords)
            .hasPrefix("daybreak-shot-list-days-12-18-22-")
    }
    try? fm.removeItem(at: film)
}

// ---- the storyboard's layout, shared with the Mac ----------------------------

check("a board of one shape is the old grid: equal cards, filling the row") {
    let rows = BoardPlan.rows(ratios: Array(repeating: 1.78, count: 4), width: 370, cardWidth: 177, film: 1.78, gutter: 8, chrome: 0)
    return rows.count == 2 && rows.allSatisfy { $0.count == 2 }
        && rows[0].allSatisfy { abs($0.width - 181) < 0.6 && abs($0.pictureWidth - $0.width) < 0.1 }
}

check("a tall picture beside a wide one shares a row at one picture height, inside the width") {
    let rows = BoardPlan.rows(ratios: [1.78, 0.5625, 1.78], width: 370, cardWidth: 177, film: 1.78, gutter: 8, chrome: 0)
    let first = rows[0]
    let width = first.reduce(0) { $0 + $1.width } + 8 * CGFloat(first.count - 1)
    return first.count >= 2 && width <= 370.6
        && abs(first[0].pictureHeight - first[1].pictureHeight) < 0.6
        && first[1].pictureWidth < first[0].pictureWidth
}

check("a picture area is the Print Frame's shape when it has one, else the project's") {
    BoardPlan.shape((1000, 500), film: 2.39) == 2 && BoardPlan.shape(nil, film: 2.39) == 2.39
}

// ---- diagram beats: removing and moving one ----------------------------------

print("\nDiagram beats")

/// A piece's beats in order, off the plan's own `seq`.
func beatsOf(_ p: Project, _ scene: String, _ id: String) -> [Int] {
    guard let o = try? JSONSerialization.jsonObject(with: p.call("diagram", scene)) as? [String: Any],
          let els = o["els"] as? [[String: Any]],
          let e = els.first(where: { $0["id"] as? String == id }),
          let seq = e["seq"] as? [[String: Any]] else { return [] }
    return seq.filter { ($0["home"] as? Bool) != true }.map { ($0["beat"] as? NSNumber)?.intValue ?? 0 }
}

func piecesOf(_ p: Project, _ scene: String) -> [DiagramBeats.Piece] {
    guard let o = try? JSONSerialization.jsonObject(with: p.call("diagram", scene)) as? [String: Any],
          let els = o["els"] as? [[String: Any]] else { return [] }
    return els.compactMap { e in
        guard let id = e["id"] as? String, let seq = e["seq"] as? [[String: Any]], seq.count > 1 else { return nil }
        return (id, seq.enumerated().map { i, t in (i, (t["beat"] as? NSNumber)?.intValue ?? 0, (t["home"] as? Bool) ?? false) })
    }
}

func batch(_ p: Project, _ scene: String, _ ops: [[String: Any]]) {
    let op: [String: Any] = ["op": "batch", "ops": ops]
    if let d = try? JSONSerialization.data(withJSONObject: op), let t = String(data: d, encoding: .utf8) {
        p.call("diagramedit", scene, t)
    }
}

check("taking a beat out renumbers the later ones; moving one swaps it with its neighbour") {
    guard let path = scratch("beats"), let p = Project(path.path), let scene = try p.view().scenes.first?.id else { return false }
    func put(_ id: String, _ beat: Int, _ x: Double) {
        let op: [String: Any] = ["op": "beat", "id": id, "beat": beat, "x": x, "y": 1]
        if let d = try? JSONSerialization.data(withJSONObject: op), let t = String(data: d, encoding: .utf8) { p.call("diagramedit", scene, t) }
    }
    let add: [String: Any] = ["op": "add", "els": [["id": "a", "kind": "cast", "x": 0, "y": 0], ["id": "b", "kind": "cast", "x": 5, "y": 5]]]
    p.call("diagramedit", scene, String(data: try JSONSerialization.data(withJSONObject: add), encoding: .utf8)!)
    let ids = ((try? JSONSerialization.jsonObject(with: p.call("diagram", scene)) as? [String: Any])?["els"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
    guard ids.count == 2 else { return false }
    let (a, b) = (ids[0], ids[1])
    put(a, 2, 1); put(a, 3, 2); put(a, 4, 3); put(b, 3, 9)
    guard beatsOf(p, scene, a) == [2, 3, 4], beatsOf(p, scene, b) == [3] else { return false }
    // Take beat 3 out: a's 3 goes, its 4 becomes 3; b's only step was beat 3.
    batch(p, scene, DiagramBeats.removeOps(3, pieces: piecesOf(p, scene)))
    guard beatsOf(p, scene, a) == [2, 3], beatsOf(p, scene, b) == [] else { return false }
    // Beat 3 earlier: a's 3 and 2 trade; the order of a's steps is kept.
    put(a, 4, 7)
    batch(p, scene, DiagramBeats.moveOps(3, by: 1, pieces: piecesOf(p, scene)))
    let after = beatsOf(p, scene, a)
    return after == [2, 3, 4] || after == [2, 4, 3] ? after.sorted() == [2, 3, 4] : false
}

// ---- Print Frames reach the phone (2026-10-16) --------------------------------
//
// He saw no Print Frames on the iPhone (TestFlight 35) while the Mac showed
// them on every shot. The bake is a picture no media record names, so the sync
// plan never asked the relay for one. Read from a copy of his real project, without its pictures: every current Print Frame decodes as a board,
// and the plan asks the relay for each one's file.

print("\nPrint Frames reach the phone")
let chb = fm.homeDirectoryForCurrentUser.appending(path: "Documents/Shotlister/Call Her Back.shotlist")
if fm.fileExists(atPath: chb.path) {
    check("Call Her Back's Print Frames are boards and the sync asks for every one") {
        let copy = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "phone-checks-printframes.shotlist")
        try? fm.removeItem(at: copy)
        try fm.createDirectory(at: copy, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: copy) }
        for part in ["manifest.json", "changes"] {
            try fm.copyItem(at: chb.appending(path: part), to: copy.appending(path: part))
        }
        guard let p = Project(copy.path) else { return false }
        let boards = try p.view().groups.flatMap(\.rows).compactMap(\.board)
        // The relay holds what the Mac holds.
        let names = (try? fm.contentsOfDirectory(atPath: chb.appending(path: "media/proxies").path)) ?? []
        let listing = try JSONSerialization.data(withJSONObject: ["media": names.map { ["name": $0, "size": 1] }])
        let plan = try JSONDecoder().decode(Engine.SyncPlan.self,
            from: p.call("syncplan", "{\"logs\":[]}", String(data: listing, encoding: .utf8)!))
        let wanted = boards.map { String($0.hash.prefix(32)) + "." + $0.ext }
        let missing = wanted.filter { !plan.downloadMedia.contains($0) }
        print("    \(boards.count) current Print Frames, \(wanted.count - missing.count) asked for")
        return !boards.isEmpty && missing.isEmpty
    }
} else {
    print("  · skipped — Call Her Back is not on this Mac")
}

// ---- how it went ------------------------------------------------------------

for name in ["save", "location", "commercial", "avscript", "filmscript", "locmedia", "shotmedia", "clip", "gif", "plan",
             "stray", "adopt", "dirty", "asking", "newcommand", "merge", "quiet", "both", "hidescene",
             "relay", "relaytidy", "relayid", "relaynew", "relayready"] {
    try? fm.removeItem(at: URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "phone-checks-\(name).shotlist"))
}

print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
