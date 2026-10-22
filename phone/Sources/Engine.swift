import Foundation
import SwiftUI
import CoreLocation

/// The engine, as the phone sees it.
///
/// Deliberately thinner than the Mac's bridge. The law is the same — the engine
/// holds every fact and the screen only draws what it hands back — but the phone
/// asks for less, so translating a whole desk's worth of commands would be
/// carrying weight nothing lifts.
///
/// One command in, one JSON reply out. If the reply cannot be read, that is a
/// bug worth seeing rather than a nil worth swallowing, so it surfaces.
final class Engine {
    private let handle: OpaquePointer
    /// The handle has state behind it and answers one call at a time. Every
    /// caller used to be on the main actor, which serialized this for free;
    /// now that a slow read (a big project's media) is asked for off the main
    /// thread too, this lock is what keeps two calls from landing at once.
    private let lock = NSLock()

    /// This phone's name to the sync log. Made once and remembered, because a
    /// device that renames itself looks like a second device that agrees with
    /// the first about everything — and clash detection would then never fire.
    static let deviceId: UInt64 = {
        let key = "shotlister.deviceId"
        let saved = UserDefaults.standard.object(forKey: key) as? NSNumber
        if let saved { return saved.uint64Value }
        let fresh = UInt64.random(in: 1...UInt64.max)
        UserDefaults.standard.set(NSNumber(value: fresh), forKey: key)
        return fresh
    }()

    /// Opens the project at `path`, or reports why it could not be opened.
    init(path: String) throws {
        guard let h = path.withCString({ sl_open_as($0, Engine.deviceId) }) else {
            let problem = sl_problem().map { p -> String in
                let s = String(cString: p)
                sl_free(p)
                return s
            } ?? ""
            throw Failure.couldNotOpen(problem.isEmpty ? "Can't open the project" : problem)
        }
        handle = h
    }

    deinit { sl_close(handle) }

    enum Failure: LocalizedError {
        case couldNotOpen(String)
        case unreadableReply(String)

        var errorDescription: String? {
            switch self {
            case .couldNotOpen(let why): return why
            case .unreadableReply(let line): return "Can't read the project"
            }
        }
    }

    /// Sends one command. Arguments are tab-delimited, exactly as on the Mac.
    @discardableResult
    func call(_ parts: String...) throws -> Any {
        try call(parts)
    }

    @discardableResult
    func call(_ parts: [String]) throws -> Any {
        lock.lock()
        defer { lock.unlock() }
        let line = parts.joined(separator: "\t")
        guard let reply = line.withCString({ sl_call(handle, $0) }) else {
            throw Failure.unreadableReply(parts.first ?? "")
        }
        defer { sl_free(reply) }
        let text = String(cString: reply)
        guard let data = text.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { throw Failure.unreadableReply(parts.first ?? "") }
        return value
    }

    /// The common case: a command whose reply is an object.
    func object(_ parts: String...) throws -> [String: Any] {
        (try call(parts)) as? [String: Any] ?? [:]
    }

    /// The reply as it arrived, for decoding into real types rather than
    /// poking at dictionaries — which is how the Shots tab came to read the
    /// wrong part of the view model and report an empty list.
    func raw(_ parts: String...) -> Data { raw(parts) }

    func raw(_ parts: [String]) -> Data {
        lock.lock()
        defer { lock.unlock() }
        let line = parts.joined(separator: "\t")
        guard let reply = line.withCString({ sl_call(handle, $0) }) else { return Data() }
        defer { sl_free(reply) }
        return Data(String(cString: reply).utf8)
    }

    // ---- the relay ---------------------------------------------------------

    /// What should move between this film and the relay.
    ///
    /// **Named `SyncPlan`, never `Plan`.** `Scan.swift` owns a top-level `Plan`
    /// and `floorPlan` returns it — a nested `Engine.Plan` silently wins inside
    /// this type, which on the Mac quietly changed what the scan reader got
    /// back and was reported as a compiler bug in a file nobody had touched.
    struct SyncPlan: Decodable {
        var uploadLogs: [String]
        /// The few of `uploadLogs` a fold wrote over, which the relay has to be
        /// asked to accept in place of what it holds. Almost always empty.
        var rewriteLogs: [String]
        var downloadLogs: [String]
        var uploadMedia: [String]
        var downloadMedia: [String]
        var steps: Int
        var incoming: Bool
        var outgoing: Bool
    }

    /// Both arguments are exactly what the relay replied with, passed straight
    /// through. They cannot contain a tab — JSON escapes one inside a string and
    /// has none between tokens — so the tab-delimited command line is safe.
    ///
    /// **The engine decides and `Relay` carries.** Working this out in Swift as
    /// well would be a second answer to the same question, and the one that
    /// drifted would be the one nobody tested.
    func syncPlan(state: String, media: String) -> SyncPlan? {
        try? JSONDecoder().decode(SyncPlan.self, from: raw("syncplan", state, media))
    }

    /// Of the files the relay lists, the ones this film no longer names —
    /// the engine's judgement (`Doc::stray_media_names`), from the same
    /// listing `syncPlan` reads. The Mac has had it since 2026-09-15; the
    /// shared carrier asks both apps for it, so the phone tidies the relay too.
    func strays(media: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: raw("strays", media))) ?? []
    }
}

// ------------------------------------------------- what the engine hands back
//
// Only the parts the phone draws. The Mac's bridge decodes the whole view model;
// carrying all of it here would be weight nothing lifts, and every field copied
// is a field that can fall out of step with the engine.

// MARK: - Decoding that bends rather than breaks
//
// **The law of this file, and the reason it is written the long way.** Ref 189.
//
// On 2026-08-21 one photograph on one location lacked one field — `key`, the
// lead-frame flag, which a location's pictures have never had — and the whole
// app drew as an empty film. Not the photograph, not the location: everything.
// Swift's synthesised decoder is all-or-nothing, and a single `keyNotFound`
// anywhere in the graph throws the entire view away.
//
// The one-off fix was to make that one field optional. An audit then counted
// **seventy-one more fields with exactly the same tripwire**, each one a future
// empty app if the engine ever stopped sending it, renamed it, or sent it only
// under some conditions.
//
// So this is a policy rather than another patch: **a missing field costs its
// own value and nothing else.** Every struct below decodes by hand through the
// helpers here, each of which answers with a sensible empty rather than
// throwing. One odd record degrades to one odd record.
//
// Two things this deliberately does **not** do:
//
// - It does not swallow a reply that is not a view at all. `View` still refuses
//   a reply with no `project` in it, because defaulting *that* would turn an
//   engine error into a silent blank screen — which is the very bug this is
//   here to prevent, arriving through the back door.
// - It does not make the banner pointless. The banner in `ProjectView` still
//   fires for the failures that remain real ones; there are simply far fewer
//   ways to reach it by accident.
private extension KeyedDecodingContainer {
    /// A string, or empty if it is missing or is not a string.
    func text(_ key: Key) -> String {
        (try? decodeIfPresent(String.self, forKey: key)) ?? ""
    }

    /// A string that is allowed to be absent — where "never set" and "set to
    /// nothing" are different facts, as they are for a room's parent.
    func maybeText(_ key: Key) -> String? {
        (try? decodeIfPresent(String.self, forKey: key)) ?? nil
    }

    func flag(_ key: Key, or fallback: Bool = false) -> Bool {
        (try? decodeIfPresent(Bool.self, forKey: key)) ?? fallback
    }

    func maybeFlag(_ key: Key) -> Bool? {
        (try? decodeIfPresent(Bool.self, forKey: key)) ?? nil
    }

    func count(_ key: Key, or fallback: Int = 0) -> Int {
        (try? decodeIfPresent(Int.self, forKey: key)) ?? fallback
    }

    /// A whole number that is allowed to be absent — a shot that quotes no
    /// script has no `scriptFrom`, and nought would be the first character.
    func maybeCount(_ key: Key) -> Int? {
        (try? decodeIfPresent(Int.self, forKey: key)) ?? nil
    }

    func number(_ key: Key, or fallback: Double) -> Double {
        (try? decodeIfPresent(Double.self, forKey: key)) ?? fallback
    }

    /// A number that is allowed to be absent — where "never set" and "set to
    /// nought" are different facts, as they are for a clip's in point.
    func maybeNumber(_ key: Key) -> Double? {
        (try? decodeIfPresent(Double.self, forKey: key)) ?? nil
    }

    func words(_ key: Key) -> [String] {
        (try? decodeIfPresent([String].self, forKey: key)) ?? []
    }

    func table(_ key: Key) -> [String: String] {
        (try? decodeIfPresent([String: String].self, forKey: key)) ?? [:]
    }

    func lists(_ key: Key) -> [String: [String]]? {
        (try? decodeIfPresent([String: [String]].self, forKey: key)) ?? nil
    }

    /// One nested record, or nothing. Never throws: a camera the engine could
    /// not describe is a shot with no camera, not a film with no shots.
    func one<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }

    /// A list of records, where **one bad element costs one element.**
    ///
    /// The fast path decodes the array whole. If that fails — which now means
    /// an element that is not even an object — it walks them one at a time and
    /// keeps the ones that read. The index check is not decoration: an element
    /// that fails without consuming itself would leave the walk standing still,
    /// and a hang is worse than a gap.
    func many<T: Decodable>(_ type: T.Type, _ key: Key) -> [T] {
        if let whole = (try? decodeIfPresent([T].self, forKey: key)) ?? nil { return whole }
        guard var list = try? nestedUnkeyedContainer(forKey: key) else { return [] }
        var kept: [T] = []
        while !list.isAtEnd {
            let before = list.currentIndex
            if let one = try? list.decode(T.self) { kept.append(one) }
            if list.currentIndex == before { break }
        }
        return kept
    }
}

extension Engine {
    /// One edit reference (the Edit Reference mod), as the engine says it.
    struct EditRef: Decodable, Identifiable, Hashable {
        struct Shot: Decodable, Hashable { var shot: String; var number: String; var start: Double }
        struct Clip: Decodable, Hashable {
            var ref: String
            var hash: String
            var filename: String
            var kind: String
            var width: Int?
            var height: Int?
            var seconds: Double?
            var ext: String { filename.split(separator: ".").last.map(String.init)?.lowercased() ?? "mp4" }
        }
        var id: String
        var name: String
        var link: String
        var length: Double
        var shots: [Shot]
        var media: [Clip]
        var clip: Clip? { media.first { $0.kind == "video" } }
        var stills: [Clip] { media.filter { $0.kind == "image" || $0.kind == "gif" } }
        func end(of at: Int) -> Double { at + 1 < shots.count ? shots[at + 1].start : max(length, shots.last?.start ?? 0) }
        var range: String {
            guard let a = shots.first?.number, let b = shots.last?.number else { return "" }
            return a == b ? a : "\(a)–\(b)"
        }
    }

    /// The whole answer to "what is on screen".
    struct View: Decodable {
        var project: Project
        var filter: Filter
        var columns: [Column]
        /// **What every field is called, said by the engine.** Ref 249, 313.
        ///
        /// The phone used to keep its own copy of "Shot Angle" and "Camera
        /// Gear" in a switch a few lines down from here. Two lists that can
        /// disagree is one list too many, and they did: the engine was told to
        /// say `Equipment` instead of `Support` and the phone went on saying
        /// Support, so the two apps disagreed out loud about one label.
        var fieldLabels: [String: String]
        /// The cameras. **A camera is a record, not a word** — it has a name and
        /// a colour, which is how A-Cam and B-Cam are told apart at a glance —
        /// so it is chosen by id rather than typed.
        var units: [Unit]
        /// The runs of the film. A sequence belongs to a **scene**, which is
        /// where the Mac sets it and where the phone sets it too.
        var sequences: [Sequence]
        /// **The scripts, as text** — the film's own (empty section) and one
        /// per section that has one. On a commercial only; a film's script is
        /// pages, asked for separately (`scriptpages`). His ruling, 2026-09-19:
        /// the script is plain text and a shot quotes a stretch of it.
        var scripts: [AVScript]
        /// The shooting days. The phone shows which day a shot falls on; it is
        /// scheduled on the Mac's board, the same as the Mac's own table.
        var days: [Day]
        /// The places. **In the engine since 2026-08-21** — until then the phone
        /// kept them in files beside the project because there was nowhere in
        /// the engine to put one. There is now, so it does not.
        var locations: [Location]
        /// The mood boards. A board is a name and a wall of pictures, and it
        /// belongs to the film rather than to any one scene — a scene links the
        /// ones that apply to it.
        var boards: [Board]
        var scenes: [Scene]
        var groups: [Group]
        var groupBy: String
        /// **The project's shoots** (stage 5 step 4, piece D), off the card;
        /// `shootOn` the one every list is narrowed to, "" for All Shoots.
        var shoots: [Shoot] = []
        var shootOn: String = ""
        /// **Edit references** (the Edit Reference mod); absent when none.
        var editRefs: [EditRef]?

        enum Key: String, CodingKey {
            case project, filter, columns, fieldLabels, units, sequences, scripts, days
            case locations, boards, scenes, groups, groupBy, shoots, shootOn, editRefs
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            // **The one thing that is still allowed to fail.** Every field
            // below defaults, so a reply that is not a view at all — an
            // engine error, say — would otherwise decode into a perfectly
            // empty film and draw as one. A view has a project in it.
            guard c.contains(.project) else {
                throw DecodingError.keyNotFound(
                    Key.project,
                    .init(codingPath: c.codingPath,
                          debugDescription: "the engine's answer was not a view"))
            }
            project = c.one(Project.self, .project) ?? Project()
            filter = c.one(Filter.self, .filter) ?? Filter()
            columns = c.many(Column.self, .columns)
            fieldLabels = c.table(.fieldLabels)
            units = c.many(Unit.self, .units)
            sequences = c.many(Sequence.self, .sequences)
            scripts = c.many(AVScript.self, .scripts)
            days = c.many(Day.self, .days)
            locations = c.many(Location.self, .locations)
            boards = c.many(Board.self, .boards)
            scenes = c.many(Scene.self, .scenes)
            groups = c.many(Group.self, .groups)
            groupBy = c.text(.groupBy)
            shoots = c.many(Shoot.self, .shoots)
            shootOn = c.text(.shootOn)
            editRefs = c.contains(.editRefs) ? c.many(EditRef.self, .editRefs) : nil
            // **Set here rather than by whoever happens to remember.** A
            // column's `shown` needs the engine's names, and a computed
            // property has no view to ask. Doing it as the view is read means
            // the names can never be older than the view drawn from them —
            // and the checks and the app get it without either being told.
            Column.named = fieldLabels
        }
    }

    /// One of the project's frames (piece E): `Delivery`, `2.39:1`.
    struct ProjectFrame: Decodable, Identifiable, Hashable {
        var name: String
        var said: String
        var ratio: Double
        var main: Bool = false
        var picked: Bool = false
        var id: String { name }
    }

    struct Project: Decodable {
        /// The project record's own id — what Project Settings writes to,
        /// through the same `set` a cell uses.
        var id: String = ""
        var title: String = ""
        var director: String = ""
        var producer: String = ""
        /// **What sort of film this is** — `film` or `commercial`. The
        /// engine's `kind` module owns what it means; here it decides what
        /// Add Scene asks for first (a title, not a number), whether the
        /// slugline leads or folds away, and whether a sequence is called a
        /// Section. Empty on anything written before the fact existed, which
        /// is a film.
        var kind: String = "film"
        var isCommercial: Bool { kind == "commercial" }
        /// Who the commercial is for, and who brought it.
        var client: String = ""
        var agency: String = ""
        /// **Where the film's facts come from** — `console` when his project
        /// record owns its shown name, director, producer, client and agency
        /// (one-record plan, 2026-10-05). The Mac's console hands them to the
        /// film and the sync brings them here; the phone shows them and does
        /// not write them — the engine refuses a `set` onto them anyway.
        var factsSource: String = ""
        var factsFromRecord: Bool { factsSource == "console" }
        /// **The project's card is laid over the film** (`PhoneCards`).
        var card: Bool = false
        /// The name to draw — the record's when it has said one.
        var displayTitle: String = ""
        var shownTitle: String { displayTitle.isEmpty ? title : displayTitle }
        /// What this film calls a sequence — *Section* on a commercial. The
        /// engine says the same in `fieldLabels`; this is for the words the
        /// app writes itself.
        var sequenceWord: String { isCommercial ? "Section" : "Sequence" }
        var sequencesWord: String { isCommercial ? "Sections" : "Sequences" }
        /// The frame the project is cut for — 1.85, 2.39, and so on.
        var ratio: Double = 1.85
        /// **The project's frames, off its spec sheet** (stage 5 step 4,
        /// piece E): nil while the card brings none. `frame` is the one the
        /// app draws at, picked apart from the portal's Main.
        var frames: [ProjectFrame]?
        var frame: String = ""
        var frameGuides: Bool = false
        /// **The kit off the spec sheets** (Ref 1627): each shoot's lenses,
        /// cameras, modifiers and filters as last taken. Empty: none taken.
        var kit: [KitShoot] = []
        /// **The Spec Sheet switch**: `off`, `ask` or `follow` (Sync).
        var kitMode: String = "off"
        /// Cameras' sensors are the spec sheet's: shown, never typed.
        var sensorsFromSheet: Bool = false
        var readOnly: Bool = false
        /// **Changes made and not yet written down.** The phone saves whenever
        /// this is anything but nought — see `Session.reload`, which is why
        /// there is no longer a hand-kept list of which commands write.
        var unsaved: Int = 0
        /// **Where this film lives in his Google Drive**, set on the Mac. Empty
        /// means the film has not opted in at all — and a location's or a
        /// board's own Sync with Drive switch means nothing until it has.
        var driveFolder: String = ""
        /// **Which program the film's workbook is laid out for** — `cells`
        /// for Google Sheets, `file` for Excel, empty for never asked. Set on
        /// the Mac; the Export page starts its one-off choice from it.
        var excelFrames: String = ""
        /// **The film's own icon**, as the outline to draw it with, and the
        /// colour to draw it in. His call, 2026-09-11: the pair belongs to the
        /// film rather than to a Mac, so it arrives here through the ordinary
        /// sync and the phone simply wears it.
        var markPath: String = ""
        var markColour: String = ""
        /// `console` — mirrored off his Notion row by the Mac; `hand` — he
        /// chose it. The phone reads this and does not write it: setting one is
        /// the Mac's screen. Kept so a phone screen that offers to set one
        /// later knows which it is looking at.
        var markSource: String = ""
        /// **The Notion page of the Projects Console project this film is**,
        /// written by Link on the Mac. How the phone's *Projects Console*
        /// button finds the same project over there.
        var consolePage: String = ""
        /// How the Document page is set, and the same in the engine's shorthand.
        var docStyle: [TextClass] = []
        var docStyleSaid: String = ""
        /// The pair, when the film has both. Half a mark cannot be drawn.
        var mark: FilmMark? {
            guard !markPath.isEmpty, !markColour.isEmpty else { return nil }
            return FilmMark(path: markPath, colour: markColour)
        }

        init() {}

        enum Key: String, CodingKey {
            case id, title, director, producer, kind, client, agency
            case factsSource, displayTitle, card
            case ratio, readOnly, unsaved, driveFolder
            case excelFrames, markPath, markColour, markSource, consolePage
            case frames, frame, frameGuides, kit, kitMode, sensorsFromSheet
            case docStyle, docStyleSaid
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            id = c.text(.id)
            title = c.text(.title)
            director = c.text(.director)
            producer = c.text(.producer)
            kind = c.text(.kind).isEmpty ? "film" : c.text(.kind)
            client = c.text(.client)
            agency = c.text(.agency)
            factsSource = c.text(.factsSource)
            displayTitle = c.text(.displayTitle)
            card = c.flag(.card)
            // A ratio of nought is not a frame. Falling back to the ordinary
            // one keeps every plate on screen the right shape.
            let given = c.number(.ratio, or: 1.85)
            ratio = given > 0 ? given : 1.85
            readOnly = c.flag(.readOnly)
            unsaved = c.count(.unsaved)
            driveFolder = c.text(.driveFolder)
            excelFrames = c.text(.excelFrames)
            markPath = c.text(.markPath)
            markColour = c.text(.markColour)
            markSource = c.text(.markSource)
            consolePage = c.text(.consolePage)
            // **The spec sheet's aspect ratios** (piece E). Never decoded
            // here until 2026-10-16, so the phone never showed them.
            frames = c.one([ProjectFrame].self, .frames)
            frame = c.text(.frame)
            frameGuides = c.flag(.frameGuides)
            kit = c.one([KitShoot].self, .kit) ?? []
            kitMode = c.text(.kitMode).isEmpty ? "off" : c.text(.kitMode)
            sensorsFromSheet = c.flag(.sensorsFromSheet)
            docStyle = c.one([TextClass].self, .docStyle) ?? []
            docStyleSaid = c.text(.docStyleSaid)
        }
    }

    /// **One kind of words on the Document page**, as the engine sets it.
    struct TextClass: Decodable, Hashable {
        var `class`: String
        var label: String
        var size: Double
        var face: String
        var `case`: String
        var colour: String?
    }

    struct KitShoot: Decodable, Equatable {
        var name: String = ""
        var start: String = ""
        var end: String = ""
        var sheet: String = ""
        var lead: Bool = false
        var cameras: [KitCamera] = []
        var lenses: [String] = []
        var modifiers: [String]? = nil
        var filters: [String]? = nil
    }
    struct KitCamera: Decodable, Equatable {
        var label: String = ""
        var body: String = ""
    }

    /// What is currently narrowing the list, as the engine sees it. Worth
    /// showing rather than hiding: a filter that silently shortens a film is
    /// how a shot gets missed on the day.
    struct Filter: Decodable {
        var text: String = ""
        var hideStruck: Bool = false
        var hiddenScenes: Int = 0
        /// **Which** scenes the filter emptied, so the list can leave them
        /// out rather than draw each one as an empty "No shots".
        var hiddenSceneIds: [String] = []
        var shown: Int = 0
        var narrowed: Bool = false
        var sortColumn: String = ""
        var sortDescending: Bool = false

        init() {}

        enum Key: String, CodingKey {
            case text, hideStruck, hiddenScenes, hiddenSceneIds, shown, narrowed, sortColumn, sortDescending
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            text = c.text(.text)
            hideStruck = c.flag(.hideStruck)
            hiddenScenes = c.count(.hiddenScenes)
            hiddenSceneIds = c.words(.hiddenSceneIds)
            shown = c.count(.shown)
            narrowed = c.flag(.narrowed)
            sortColumn = c.text(.sortColumn)
            sortDescending = c.flag(.sortDescending)
        }
    }

    /// A run of the film. It hangs on a scene, not on a shot.
    struct Sequence: Decodable, Identifiable, Hashable {
        var id: String = ""
        var title: String = ""
        var colour: String = ""

        enum Key: String, CodingKey { case id, title, colour }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            id = c.text(.id)
            title = c.text(.title)
            colour = c.text(.colour)
        }

        var tint: Color { Palette.tint(colour) }
    }

    /// One of the project's shoots (piece D), as the view lists it.
    struct Shoot: Decodable, Identifiable, Hashable {
        var id: String
        var label: String
        var kind: String = ""
        var start: String = ""
        var end: String = ""
        var state: String = ""
        var scenes: Int = 0
        var days: Int = 0
        var wrapped: Bool { state.lowercased() == "wrapped" }
    }

    /// A shooting day. Made and ordered on the Mac's board.
    struct Day: Decodable, Identifiable, Hashable {
        var id: String = ""
        var label: String = ""
        var date: String = ""
        var count: Int = 0
        /// Every shot on it is in an archived scene: shot out and put away.
        var wrapped: Bool = false

        enum Key: String, CodingKey { case id, label, date, count, wrapped }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            id = c.text(.id)
            label = c.text(.label)
            date = c.text(.date)
            count = c.count(.count)
            wrapped = c.flag(.wrapped)
        }
    }

    /// A place, as the engine holds it.
    ///
    /// Latitude and longitude come across as text because that is how the engine
    /// stores what a phone measured — an empty string is "never pinned", which a
    /// number cannot say.
    struct Location: Decodable, Identifiable, Hashable {
        var id: String = ""
        var name: String = ""
        var address: String = ""
        var latitude: String = ""
        var longitude: String = ""
        var notes: String = ""
        var capturedBy: String = ""
        var createdAt: String = ""
        /// Which folder beside the project holds its scans and papers. The
        /// papers stay files; **a scan is media now** (Ref 920) — the phone
        /// still writes it into this folder, and the film registers it.
        var folder: String = ""
        var driveFolder: String = ""
        /// **Whether this place's photographs travel to Drive** — Ref 229.
        /// `"1"` on, `"0"` off, and **empty means nobody has been asked**,
        /// which the bridge reads as on: a film opting in is already an
        /// explicit choice, and the switch is there to exclude a place.
        var syncWithDrive: String = ""
        /// What the switch should show. Empty reads as on — see above.
        var syncsWithDrive: Bool { syncWithDrive != "0" }
        /// The house this room is inside, if it is a room. Empty for a place
        /// that stands on its own.
        var parent: String?
        /// The rooms inside this place, by id. Ref 269 — one house, one
        /// address, and a kitchen, a bedroom and a garage inside it.
        var areas: [String]?
        /// What to call this place away from its own screen — a room carries
        /// its house, `Hillcrest House — Kitchen`.
        var fullName: String?
        var scenes: [String] = []
        var media: [Still] = []
        /// Only the pictures. A paper pinned to a location is media too
        /// (2026-09-15, so it travels), and drawing it in the photo wall
        /// draws a page of text as a photograph.
        var photos: [Still] { media.filter { $0.kind != .other } }
        /// **The scanned rooms, as the film knows them** — Ref 939. A room
        /// is two files sharing a name, the shape and the measurements, and
        /// either may be missing. Absent on a view written before scans were
        /// media, which reads as none.
        var scans: [Room] = []

        enum Key: String, CodingKey {
            case id, name, address, latitude, longitude, notes, capturedBy, createdAt
            case folder, driveFolder, parent, areas, fullName, scenes, media, scans
            case syncWithDrive
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            id = c.text(.id)
            name = c.text(.name)
            address = c.text(.address)
            latitude = c.text(.latitude)
            longitude = c.text(.longitude)
            notes = c.text(.notes)
            capturedBy = c.text(.capturedBy)
            createdAt = c.text(.createdAt)
            folder = c.text(.folder)
            driveFolder = c.text(.driveFolder)
            syncWithDrive = c.text(.syncWithDrive)
            parent = c.maybeText(.parent)
            areas = c.words(.areas)
            fullName = c.maybeText(.fullName)
            scenes = c.words(.scenes)
            media = c.many(Still.self, .media)
            scans = c.many(Room.self, .scans)
        }

        /// Whether this is a room inside somewhere else.
        var isArea: Bool { !(parent ?? "").isEmpty }

        /// **The folder its scans and papers live in.**
        ///
        /// A place made on the Mac has no folder — nobody ever gave it one —
        /// and every path the phone builds starts here, so a scan taken in a
        /// room made on the Mac used to land outside any location and be
        /// invisible. Falling back to the id is deterministic: no write, and
        /// no two devices inventing different answers.
        var home: String { FileNames.locationFolder(id: id, folder: folder) }

        var coordinate: CLLocationCoordinate2D? {
            guard let lat = Double(latitude), let long = Double(longitude),
                  lat != 0 || long != 0 else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: long)
        }
    }

    /// A storyboard arrow on a picture — the Mac's mark, read the way the
    /// Mac reads it. Every coordinate is a fraction of the picture. Drawn by
    /// `Arrows.swift`; kept here so the decoder compiles on its own.
    struct Arrow: Hashable {
        enum Shape: Hashable { case smooth, corner }
        enum Look: Hashable { case light, dark, red, yellow }
        /// Flat, or the storyboard perspective arrow: growing as it travels
        /// (toward camera) or shrinking (away).
        enum Depth: Hashable { case flat, toward, away }

        var x1: Double
        var y1: Double
        var x2: Double
        var y2: Double
        /// Any number of pins, tail to head. The shaft passes through each.
        var pins: [CGPoint] = []
        var shape: Shape = .smooth
        /// 0, 1 or 2 heads.
        var heads: Int = 1
        var dashed = false
        var look: Look = .light
        /// A multiple of the old M, 0.5 to 3 (S was 0.7, L 1.4).
        var thickness: Double = 1
        var depth: Depth = .flat
        /// How much a deep arrow widens, 0.1 to 1.
        var depthStrength: Double = 0.5
        /// Widths set by hand on the Mac — the shaft's and the head's
        /// half-widths, fractions of the picture's longer side at thickness 1.
        /// Nil draws the depth's own.
        var widths: [Double]? = nil
        /// A zoom mark, not an arrow: `(x1, y1)` to `(x2, y2)` is the inner
        /// frame, the picture's own shape. The engine's `zoom`.
        var zoom: Zoom? = nil
        enum Zoom: Hashable { case zoomIn, zoomOut }
        /// The part of the picture that shows where a zoom mark was laid —
        /// the engine's `view`, `[x1, y1, x2, y2]`. Nil is the whole picture.
        var view: [Double]? = nil
        /// Floor or Standing, for a Toward or Away arrow — the engine's `stance`.
        var stance: Stance = .floor
        enum Stance: Hashable { case floor, standing }

        var tail: CGPoint { CGPoint(x: x1, y: y1) }
        var head: CGPoint { CGPoint(x: x2, y: y2) }
        /// How wide the tail and the tip are drawn, as multiples of a flat
        /// arrow — the engine's `Arrow::depth_ends`.
        var depthEnds: (Double, Double) {
            let s = min(max(depthStrength, 0.1), 1)
            let near = 1 + 1.2 * s, far = 1 / (1 + 2.4 * s)
            switch depth {
            case .flat: return (1, 1)
            case .toward: return (far, near)
            case .away: return (near, far)
            }
        }

        /// The one control point an older reader bends the shaft with, the
        /// same as the engine's `Arrow::bend`. Written into `bx,by` when an
        /// arrow is saved.
        var bend: CGPoint {
            let n = pins.count
            let a = tail, c = head
            if n == 0 { return CGPoint(x: (a.x + c.x) / 2, y: (a.y + c.y) / 2) }
            let m: CGPoint
            if n % 2 == 1 { m = pins[n / 2] } else {
                let p = pins[n / 2 - 1], q = pins[n / 2]
                m = CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
            }
            return CGPoint(x: min(max(2 * m.x - (a.x + c.x) / 2, 0), 1),
                           y: min(max(2 * m.y - (a.y + c.y) / 2, 0), 1))
        }

        /// **The same line the engine stores and the Mac parses**, mirroring
        /// the engine's `Arrow::parse_one`: seven numbers, then `p<x>:<y>`
        /// pins, `corner`, `dashed`, `look:…`, `w:…`, `thick:…`, `depth:…`, `widths:…`. An arrow with no pin
        /// token is an old one and reads its single bend as a pin. Forgiving:
        /// an arrow that does not parse costs one arrow, never the picture.
        static func parse(_ line: String?) -> [Arrow] {
            guard let line, !line.isEmpty else { return [] }
            return line.split(separator: ";").compactMap { piece in
                var n: [Double] = []
                var pins: [CGPoint] = []
                var shape = Shape.smooth, dashed = false
                var look = Look.light
                var weight: Double?, thick: Double?
                var depth = Depth.flat, depthStrength = 0.5
                var widths: [Double]?
                var zoom: Zoom?
                var view: [Double]?
                var stance = Stance.floor
                for raw in piece.split(separator: ",") {
                    let token = raw.trimmingCharacters(in: .whitespaces)
                    if let v = Double(token) { n.append(v); continue }
                    if token.hasPrefix("p") {
                        let rest = token.dropFirst().split(separator: ":", maxSplits: 1)
                        if rest.count == 2,
                           let x = Double(rest[0].trimmingCharacters(in: .whitespaces)),
                           let y = Double(rest[1].trimmingCharacters(in: .whitespaces)),
                           x.isFinite, y.isFinite {
                            pins.append(CGPoint(x: x, y: y))
                        }
                        continue
                    }
                    switch token {
                    case "corner": shape = .corner
                    case "smooth": shape = .smooth
                    case "dashed": dashed = true
                    default:
                        if token.hasPrefix("view:") {
                            let v = token.dropFirst(5).split(separator: ":", omittingEmptySubsequences: false)
                                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                            if v.count == 4, v.allSatisfy({ $0.isFinite }) {
                                let l = min(max(min(v[0], v[2]), 0), 1), r = min(max(max(v[0], v[2]), 0), 1)
                                let t = min(max(min(v[1], v[3]), 0), 1), b = min(max(max(v[1], v[3]), 0), 1)
                                let whole = l < 0.0005 && t < 0.0005 && r > 0.9995 && b > 0.9995
                                view = (whole || r - l < 0.05 || b - t < 0.05) ? nil : [l, t, r, b]
                            }
                        } else if token.hasPrefix("stance:") {
                            switch token.dropFirst(7).trimmingCharacters(in: .whitespaces).lowercased() {
                            case "floor", "ground", "lying": stance = .floor
                            case "standing", "stand", "upright", "air": stance = .standing
                            default: break
                            }
                        } else if token.hasPrefix("zoom:") {
                            switch token.dropFirst(5).trimmingCharacters(in: .whitespaces).lowercased() {
                            case "in": zoom = .zoomIn
                            case "out": zoom = .zoomOut
                            default: break
                            }
                        } else if token.hasPrefix("look:") {
                            switch token.dropFirst(5).lowercased() {
                            case "light": look = .light
                            case "dark": look = .dark
                            case "red": look = .red
                            case "yellow": look = .yellow
                            default: break
                            }
                        } else if token.hasPrefix("w:") {
                            switch token.dropFirst(2).lowercased() {
                            case "s": weight = 0.7
                            case "m": weight = 1
                            case "l": weight = 1.4
                            default: break
                            }
                        } else if token.hasPrefix("thick:") {
                            if let v = Double(token.dropFirst(6).trimmingCharacters(in: .whitespaces)),
                               v.isFinite { thick = v }
                        } else if token.hasPrefix("widths:") {
                            let v = token.dropFirst(7).split(separator: ":", omittingEmptySubsequences: false)
                                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                            // Two: shaft, head. The first build wrote three
                            // (tail, middle, head): shaft = the middle one.
                            let two = v.count == 2 ? v : (v.count == 3 ? [v[1], v[2]] : [])
                            if two.count == 2, two.allSatisfy({ $0.isFinite }) {
                                widths = two.map { min(max($0, 0.001), 0.75) }
                            }
                        } else if token.hasPrefix("depth:") {
                            let said = token.dropFirst(6).split(separator: ":", maxSplits: 1,
                                                                omittingEmptySubsequences: false)
                            let found: Depth?
                            switch said.first.map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) {
                            case "flat", "none": found = .flat
                            case "toward", "towards", "in", "forward", "near": found = .toward
                            case "away", "out", "back", "backward", "far": found = .away
                            default: found = nil
                            }
                            if let found {
                                depth = found
                                depthStrength = said.count > 1
                                    ? (Double(said[1].trimmingCharacters(in: .whitespaces))
                                        .flatMap { $0.isFinite ? $0 : nil } ?? 0.5)
                                    : 0.5
                            }
                        }
                    }
                }
                if let zoom {
                    // The inner frame keeps the picture's shape and stays inside it.
                    guard n.count >= 4, n.prefix(4).allSatisfy({ $0.isFinite }) else { return nil }
                    let size = min(max(abs(n[2] - n[0]), 0.10), 0.95)
                    let x = min(max(min(n[0], n[2]), 0), 1 - size)
                    let y = min(max(min(n[1], n[3]), 0), 1 - size)
                    var mark = Arrow(x1: x, y1: y, x2: x + size, y2: y + size)
                    mark.heads = 0
                    mark.zoom = zoom
                    mark.view = view
                    mark.look = look
                    mark.thickness = min(max(thick ?? weight ?? 1, 0.5), 3)
                    return mark
                }
                guard n.count >= 6, n.prefix(7).allSatisfy({ $0.isFinite }) else { return nil }
                let heads = n.count > 6 ? (n[6] >= 2 ? 2 : (n[6] < 0.5 ? 0 : 1)) : 1
                func hold(_ v: Double) -> Double { v.isFinite ? min(max(v, 0), 1) : 0.5 }
                var arrow = Arrow(x1: hold(n[0]), y1: hold(n[1]), x2: hold(n[4]), y2: hold(n[5]))
                arrow.heads = heads
                if pins.isEmpty {
                    // An old arrow: its bend stands for one pin, unless the
                    // bend sits on the straight line (within a thousandth).
                    let a = CGPoint(x: n[0], y: n[1]), b = CGPoint(x: n[2], y: n[3])
                    let c = CGPoint(x: n[4], y: n[5])
                    let dx = c.x - a.x, dy = c.y - a.y
                    let len = hypot(dx, dy)
                    let off = len < 1e-9 ? hypot(b.x - a.x, b.y - a.y)
                        : abs((b.x - a.x) * dy - (b.y - a.y) * dx) / len
                    if off >= 0.001 {
                        pins = [CGPoint(x: (a.x + 2 * b.x + c.x) / 4, y: (a.y + 2 * b.y + c.y) / 4)]
                    }
                }
                arrow.pins = pins.prefix(32).map { CGPoint(x: hold($0.x), y: hold($0.y)) }
                arrow.shape = shape
                arrow.dashed = dashed
                arrow.look = look
                arrow.thickness = min(max(thick ?? weight ?? 1, 0.5), 3)
                arrow.depth = depth
                arrow.depthStrength = min(max(depthStrength, 0.1), 1)
                arrow.widths = widths
                arrow.stance = stance
                return arrow
            }
        }
    }

    /// A scanned room on the film: one name, and the two files that share it.
    struct Room: Decodable, Hashable, Identifiable {
        /// One half of a room — the `.usdz` you turn over, or the `.json` a
        /// floor plan is built from. `ref` is this *use* of the file on the
        /// location, which is what `detach` and `renameuse` take.
        struct Half: Decodable, Hashable {
            var ref: String = ""
            var hash: String = ""
            var filename: String = ""
            var bytes: Int = 0
            enum Key: String, CodingKey { case ref, hash, filename, bytes }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: Key.self)
                ref = c.text(.ref)
                hash = c.text(.hash)
                filename = c.text(.filename)
                bytes = c.count(.bytes)
            }
        }
        var name: String = ""
        var shape: Half?
        var plan: Half?
        /// The name its files were made with, whatever the room is called
        /// now, and when it was scanned (`Aug 27, 2026 at 1:18 PM`).
        var file: String = ""
        var taken: String = ""
        var id: String { name }
        enum Key: String, CodingKey { case name, shape, plan, file, taken }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            name = c.text(.name)
            file = c.text(.file)
            taken = c.text(.taken)
            shape = c.one(Half.self, .shape)
            plan = c.one(Half.self, .plan)
        }
    }

    /// The colours the engine names, as something to draw with. A name nobody
    /// knows falls back rather than vanishing.
    enum Palette {
        static func tint(_ colour: String) -> Color {
            // A section is born with a hex colour (`SEQUENCE_COLOURS`); a
            // camera or a shot may still carry a named one.
            if colour.hasPrefix("#") { return hex(colour) }
            // **The Mac writes a camera's colour as bare hex** (`0A6CE8`, its
            // `Columns.palette`), which fell through to the accent here: every
            // camera coloured on the Mac drew blue on the phone until
            // 2026-10-09.
            if colour.count == 6, UInt32(colour, radix: 16) != nil { return hex(colour) }
            switch colour.lowercased() {
            case "red": return .red
            case "blue": return .blue
            case "green": return .green
            case "orange": return .orange
            case "purple": return .purple
            case "pink": return .pink
            case "yellow": return .yellow
            case "teal": return .teal
            case "brown": return .brown
            default: return .accentColor
            }
        }

        /// `#2B6CB0` as a colour; anything else is the accent. The same rule
        /// as `Color(markHex:)`, kept here because the checks compile this
        /// file without the one that draws the mark.
        static func hex(_ said: String) -> Color {
            let digits = said.hasPrefix("#") ? String(said.dropFirst()) : said
            guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return .accentColor }
            return Color(.sRGB,
                         red: Double((value >> 16) & 0xFF) / 255,
                         green: Double((value >> 8) & 0xFF) / 255,
                         blue: Double(value & 0xFF) / 255)
        }
    }

    struct Unit: Decodable, Identifiable, Hashable {
        var id: String = ""
        var label: String = ""
        var body: String = ""
        var colour: String = ""
        /// The sensor he typed for it, when set; `sensorSheet` when it is the
        /// spec sheet's sensor mode (shown, never typed).
        var sensorName: String = ""
        var sensorW: Double = 0
        var sensorH: Double = 0
        var sensorSheet: Bool = false

        enum Key: String, CodingKey {
            case id, label, body, colour
            case sensorName = "sensor_name", sensorW = "sensor_w", sensorH = "sensor_h", sensorSheet = "sensor_sheet"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            id = c.text(.id)
            label = c.text(.label)
            body = c.text(.body)
            colour = c.text(.colour)
            sensorName = c.text(.sensorName)
            sensorW = c.number(.sensorW, or: 0)
            sensorH = c.number(.sensorH, or: 0)
            sensorSheet = c.flag(.sensorSheet)
        }

        /// "Super 35 · 24.89 × 18.66 mm", nil with no sensor.
        var sensorText: String? {
            guard sensorW > 0 else { return nil }
            let size = sensorH > 0 ? String(format: "%.2f × %.2f mm", sensorW, sensorH) : String(format: "%.2f mm", sensorW)
            return sensorName.isEmpty ? size : sensorName + " · " + size
        }

        var tint: Color { Palette.tint(colour) }
    }

    struct Column: Decodable, Identifiable {
        var name: String = ""
        var visible: Bool = true
        var label: String?
        /// `text`, `single`, `multi`, `check`, `media`, `location` — sent only
        /// for a project's own columns. A built-in's shape is known.
        var kind: String?
        /// Whether the list has been closed, so a picker stops offering to add
        /// a term it would then refuse.
        var locked: Bool?
        /// Shown by the project's own list, apart from Lens Stack, which takes
        /// Modifiers and Filters out of the table. The editor still offers them.
        var own: Bool?
        var id: String { name }

        /// **The engine's names for every field, in one place** — Ref 313.
        ///
        /// Held as a static for the same reason the Mac holds one: `shown` is a
        /// computed property with no view to ask. It is written every time a
        /// view is read (see `View.init`), so it cannot be older than what is
        /// on screen, and nothing has to remember to keep it up to date.
        static var named: [String: String] = [:]

        enum Key: String, CodingKey { case name, visible, label, kind, locked, own }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            name = c.text(.name)
            // A column the engine forgot to describe is a column he can still
            // see. Hiding it by default would lose work rather than a word.
            visible = c.flag(.visible, or: true)
            label = c.maybeText(.label)
            kind = c.maybeText(.kind)
            locked = c.maybeFlag(.locked)
            own = c.maybeFlag(.own)
        }

        /// What to call it on screen.
        ///
        /// **The same words the Mac's table header uses**, because they are the
        /// same column and he reads both. The engine says all of them: a
        /// project's own column carries its label, and the built-in ones come
        /// from `fieldLabels`. There is no list here any more — there used to
        /// be, it was a copy of the Mac's, and the two drifted the day the
        /// engine was told to say `Equipment` instead of `Support`.
        var shown: String { Column.name(of: name, label) }

        /// What any field is called — a column or not. The scene fields keep
        /// lists without having columns of their own, and they are named too.
        static func name(of field: String, _ own: String? = nil) -> String {
            if let own, !own.isEmpty { return own }
            if let said = named[field], !said.isEmpty { return said }
            return field.capitalized
        }

        /// How the cells behave. A project's own column says; a built-in's is
        /// known from its name.
        var shape: String {
            if let kind, !kind.isEmpty { return kind }
            switch name {
            case "title", "description", "script", "notes": return "text"
            case "angle", "tags", "pov", "modifiers", "lens_filters": return "multi"
            case "struck":                        return "check"
            case "image":                         return "media"
            default:                              return "single"
            }
        }
    }

    /// **The schedule** — the days as lanes, and everything still waiting.
    ///
    /// Its own answer, not part of the view: the engine builds it from the
    /// placements rather than the scenes, so a scene split across two days is
    /// two strips, each carrying only the shots that fall on that day. That
    /// case is the ordinary one and the view cannot express it.
    struct Schedule: Decodable {
        var days: [Lane] = []
        /// Scenes with shots still waiting for a day, in script order.
        var unscheduled: [Strip] = []

        enum Key: String, CodingKey { case days, unscheduled }

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            days = c.many(Lane.self, .days)
            unscheduled = c.many(Strip.self, .unscheduled)
        }

        var isEmpty: Bool { days.isEmpty && unscheduled.isEmpty }
    }

    /// One shoot day, and what it runs.
    struct Lane: Decodable, Identifiable, Hashable {
        var id: String = ""
        /// `Day 1` — the engine's own words, from its position.
        var label: String = ""
        var date: String = ""
        /// The name he gave it, if he gave it one.
        var title: String = ""
        var count: Int = 0
        /// Every shot on it is in an archived scene: shot out and put away.
        var wrapped: Bool = false
        var strips: [Strip] = []
        /// **The day as a flat run of shots, in the order it runs them** —
        /// what the Shoot list draws. A strip groups by scene and cannot say
        /// that 12C is shot before 8A; this can.
        var run: [DayShot] = []

        enum Key: String, CodingKey { case id, label, date, title, count, wrapped, strips, run }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            id = c.text(.id)
            label = c.text(.label)
            date = c.text(.date)
            title = c.text(.title)
            count = c.count(.count)
            wrapped = c.flag(.wrapped)
            strips = c.many(Strip.self, .strips)
            run = c.many(DayShot.self, .run)
        }

        /// How many of the day's shots are struck — *got*, on the day.
        var got: Int { run.filter(\.struck).count }

        /// Whether the day is the one the phone is being held on.
        var isToday: Bool { when.map { Calendar.current.isDateInToday($0) } ?? false }

        /// `Fri 12 Sep`, out of the `2026-09-12` the engine keeps. The date
        /// itself when it is not a date this can read — never nothing, because
        /// a day that is dated must not look undated.
        var said: String? {
            guard !date.isEmpty else { return nil }
            guard let when else { return date }
            let say = DateFormatter()
            say.setLocalizedDateFormatFromTemplate("EEE d MMM")
            return say.string(from: when)
        }

        /// The day itself, for a calendar to open on.
        var when: Date? { Lane.plain.date(from: date) }

        /// `2026-09-12` — the one shape the engine stores a date in.
        static func written(_ when: Date) -> String { plain.string(from: when) }

        /// **Local, deliberately, at both ends.** A date the engine keeps is a
        /// calendar day and nothing else — no time, no zone. Reading it as UTC
        /// and then *saying* it in the phone's own zone moved every day one
        /// back for anyone west of Greenwich: `2026-09-12` came out as
        /// "Fri, Sep 11". Parsed as local midnight and written back the same
        /// way, the day survives the round trip anywhere on earth.
        private static let plain: DateFormatter = {
            let read = DateFormatter()
            read.locale = Locale(identifier: "en_US_POSIX")
            read.dateFormat = "yyyy-MM-dd"
            return read
        }()
    }

    /// One shot in a day's running order.
    ///
    /// `placement` is its seat on the day, which is what moves; `shot` is the
    /// shot itself, which is what gets struck. Two ids because the engine
    /// keeps them apart, and a screen that confuses them strikes the wrong
    /// thing.
    struct DayShot: Decodable, Identifiable, Hashable {
        var placement: String = ""
        var shot: String = ""
        var scene: String = ""
        var number: String = ""
        var heading: String = ""
        var title: String = ""
        var description: String = ""
        /// Scratched off on the day — the engine's own fact, *we got this*.
        var struck: Bool = false
        var frame: Frame?

        enum Key: String, CodingKey {
            case placement, shot, scene, number, heading, title, description, struck, frame
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            placement = c.text(.placement)
            shot = c.text(.shot)
            scene = c.text(.scene)
            number = c.text(.number)
            heading = c.text(.heading)
            title = c.text(.title)
            description = c.text(.description)
            struck = c.flag(.struck)
            frame = c.one(Frame.self, .frame)
        }

        var id: String { placement }
    }

    /// One scene's presence on one day — or its absence from all of them.
    struct Strip: Decodable, Identifiable, Hashable {
        var scene: String = ""
        var number: String = ""
        var heading: String = ""
        var intExt: String = ""
        var location: String = ""
        var timeOfDay: String = ""
        /// How many shots of the scene fall here, which is not the whole scene
        /// when it is split.
        var count: Int = 0
        var sequence: String?
        var colour: String = ""
        /// The other days this scene also runs on — "also Day 2".
        var elsewhere: [String] = []
        var frame: Frame?
        /// The shots this strip stands for — on a waiting strip, the ones
        /// still on no day, each of which can go onto a day by itself.
        var shots: [StripShot] = []

        enum Key: String, CodingKey {
            case scene, number, heading, intExt, location, timeOfDay, count
            case sequence, colour, elsewhere, frame, shots
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            scene = c.text(.scene)
            number = c.text(.number)
            heading = c.text(.heading)
            intExt = c.text(.intExt)
            location = c.text(.location)
            timeOfDay = c.text(.timeOfDay)
            count = c.count(.count)
            sequence = c.maybeText(.sequence)
            colour = c.text(.colour)
            elsewhere = c.words(.elsewhere)
            frame = c.one(Frame.self, .frame)
            shots = c.many(StripShot.self, .shots)
        }

        var id: String { scene }
    }

    /// One shot of a strip: its placement, number and title.
    struct StripShot: Decodable, Identifiable, Hashable {
        var placement: String = ""
        var number: String = ""
        var title: String = ""

        enum Key: String, CodingKey { case placement, number, title }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            placement = c.text(.placement)
            number = c.text(.number)
            title = c.text(.title)
        }

        var id: String { placement }
    }

    /// A mood board — a name and a wall of pictures.
    ///
    /// The pictures are the very same records a location's photographs and a
    /// shot's frames are; only the owner differs, which is why everything that
    /// draws or attaches one works here untouched.
    struct Board: Decodable, Identifiable, Hashable {
        var id: String = ""
        var name: String = ""
        /// How the wall fills each tile — `original`, `square` or `project`.
        var ratioMode: String = "original"
        /// The film's one shared vocabulary, comma-joined the way a scene's are.
        var tags: String = ""
        /// The scenes that hang this board.
        var scenes: [String] = []
        var media: [Still] = []
        /// **Whether this board's pictures travel to Drive** — Ref 229's
        /// second half. **Off until he switches it on**, the opposite of a
        /// location: no board has ever been carried, so there is nothing that
        /// reading absent as no would silently stop.
        var syncWithDrive: String = ""
        /// Which folder under the film's `1-creative/reference` holds them.
        var driveFolder: String = ""
        var syncsWithDrive: Bool { syncWithDrive == "1" }

        enum Key: String, CodingKey {
            case id, name, ratioMode, tags, scenes, media, syncWithDrive, driveFolder
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            id = c.text(.id)
            name = c.text(.name)
            let mode = c.text(.ratioMode)
            ratioMode = mode.isEmpty ? "original" : mode
            tags = c.text(.tags)
            scenes = c.words(.scenes)
            media = c.many(Still.self, .media)
            syncWithDrive = c.text(.syncWithDrive)
            driveFolder = c.text(.driveFolder)
        }

        var shown: String { name.isEmpty ? "Untitled" : name }

        var tagList: [String] {
            tags.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }

    /// One script, as text, on a section — or on the film when `section` is
    /// empty. A shot quotes a UTF-16 range of it (`Row.scriptFrom/To`), the
    /// one unit Swift, Rust and JS agree on — and the unit `NSRange` counts
    /// in, which is why the reader can hand a selection straight back.
    struct AVScript: Decodable, Identifiable, Hashable {
        var section: String = ""
        var text: String = ""
        var id: String { section }

        enum Key: String, CodingKey { case section, text }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            section = c.text(.section)
            text = c.text(.text)
        }
    }

    struct Scene: Decodable, Identifiable, Hashable {
        var id: String = ""
        var number: String = ""
        var archived: Bool = false
        var heading: String = ""
        /// **A commercial scene's own three facts.** `title` is what it is
        /// called (a film's is empty — its heading is the slugline); `slug` is
        /// the slugline underneath, empty when nobody gave it one; `audio` is
        /// the right-hand column of an AV script, kept from the morning of
        /// 2026-09-19 before the script moved onto the shots.
        var title: String = ""
        var slug: String = ""
        var audio: String = ""
        var intExt: String = ""
        var location: String = ""
        var timeOfDay: String = ""
        var script: String = ""
        var description: String = ""
        var notes: String = ""
        var count: Int = 0
        /// The sequence — on a commercial, the section — this scene is in,
        /// by id. On the scene itself, so a scene with no shots yet still
        /// knows where it sits.
        var sequence: String?
        /// The mood boards this scene links to, comma-joined by the engine.
        var boardIds: String = ""
        var tags: String = ""
        var priority: String = ""
        /// Whose eyes the scene is seen through — a list, comma-joined.
        var pov: String = ""
        /// The real place, as words. Distinct from `location`, which is what
        /// the slugline says, and from the location records the scene points at.
        var shootingLocation: String = ""
        /// Every place record this scene is shot at, comma-joined.
        var locationIds: String = ""
        /// **Files pinned to the scene** (the Mac's Notes tab): references,
        /// permits, call sheets — the same uses of media a shot's frames are.
        var attachments: [Still] = []
        /// The shoot days it falls on, already written out by the engine.
        var day: String = ""
        /// The shoot it belongs to, by id (empty on a project with none).
        var shoot: String = ""

        enum Key: String, CodingKey {
            case id, number, archived, heading, title, slug, audio
            case intExt, location, timeOfDay, script
            case description, notes, count, sequence, boardIds, tags, priority, pov
            case shootingLocation, locationIds, day, shoot, attachments
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            id = c.text(.id)
            number = c.text(.number)
            archived = c.flag(.archived)
            heading = c.text(.heading)
            title = c.text(.title)
            slug = c.text(.slug)
            audio = c.text(.audio)
            intExt = c.text(.intExt)
            location = c.text(.location)
            timeOfDay = c.text(.timeOfDay)
            script = c.text(.script)
            description = c.text(.description)
            notes = c.text(.notes)
            count = c.count(.count)
            sequence = c.maybeText(.sequence)
            boardIds = c.text(.boardIds)
            tags = c.text(.tags)
            priority = c.text(.priority)
            pov = c.text(.pov)
            shootingLocation = c.text(.shootingLocation)
            locationIds = c.text(.locationIds)
            day = c.text(.day)
            shoot = c.text(.shoot)
            attachments = c.many(Still.self, .attachments)
        }

        /// The places this scene is shot at, as ids.
        var locations: [String] { Scene.split(locationIds) }

        var povList: [String] { Scene.split(pov) }

        /// The engine joins a scene's lists with commas; this takes them apart
        /// again. One place, because four fields arrive the same way.
        static func split(_ joined: String) -> [String] {
            joined.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        /// The boards this scene hangs, as ids.
        var boards: [String] { Scene.split(boardIds) }

        var tagList: [String] { Scene.split(tags) }
    }

    /// One heading and the rows under it, as the current grouping arranges them.
    struct Group: Decodable, Identifiable {
        var key: String?
        var label: String = ""
        var heading: String?
        var count: Int = 0
        var intExt: String?
        var location: String?
        var timeOfDay: String?
        var rows: [Row] = []
        var id: String { key ?? label }

        enum Key: String, CodingKey {
            case key, label, heading, count, intExt, location, timeOfDay, rows
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            key = c.maybeText(.key)
            label = c.text(.label)
            heading = c.maybeText(.heading)
            count = c.count(.count)
            intExt = c.maybeText(.intExt)
            location = c.maybeText(.location)
            timeOfDay = c.maybeText(.timeOfDay)
            rows = c.many(Row.self, .rows)
        }
    }

    /// One picture on a shot.
    struct Still: Decodable, Hashable, Identifiable {
        var ref: String = ""
        var hash: String = ""
        var filename: String = ""
        /// Whether this is the one standing for the shot everywhere else.
        ///
        /// **Optional, and it has to be.** A location's pictures have no lead
        /// frame, so the engine does not send this for them. This was the field
        /// that emptied the whole app on 2026-08-21 — the first sighting of the
        /// problem the whole of this file's decoding is now built against.
        var key: Bool?
        /// **What the file is, said by the engine rather than guessed.** Empty
        /// on anything written before the engine said so, which falls back to
        /// the name — the rule this app used everywhere until now.
        var said: String = ""
        /// **The in and out this *use* of a clip plays**, in seconds. Absent
        /// means the whole thing: a pair of noughts would read as "starts at
        /// the very first frame", which is a different fact.
        var trimStart: Double?
        var trimEnd: Double?
        /// Which part of it is kept where something draws it cropped.
        var framing: Framing = .middle
        /// The storyboard arrows drawn on this use of the picture, if any.
        var arrows: [Arrow] = []
        /// **What is said under it** (the Mac's Caption), on this use.
        var caption: String = ""

        enum Key: String, CodingKey {
            case ref, hash, filename, key, kind, trimStart, trimEnd
            case cropX, cropY, cropScale, arrows, caption
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            ref = c.text(.ref)
            hash = c.text(.hash)
            filename = c.text(.filename)
            key = c.maybeFlag(.key)
            said = c.text(.kind)
            trimStart = c.maybeNumber(.trimStart)
            trimEnd = c.maybeNumber(.trimEnd)
            framing = Framing(x: c.number(.cropX, or: 0.5),
                              y: c.number(.cropY, or: 0.5),
                              scale: c.number(.cropScale, or: 1))
            arrows = Arrow.parse(c.maybeText(.arrows))
            caption = c.text(.caption)
        }

        var isLeadFrame: Bool { key == true }
        var id: String { ref }

        var ext: String {
            let parts = filename.split(separator: ".")
            return parts.count > 1 ? String(parts.last!).lowercased() : "png"
        }

        var kind: Kind { Kind(said: said, ext: ext) }

        var frame: Frame {
            Frame(hash: hash, filename: filename, said: said,
                  trimStart: trimStart, trimEnd: trimEnd, framing: framing, arrows: arrows)
        }
    }

    typealias Kind = MediaKind

    /// **How a picture is framed when something draws it cropped.**
    ///
    /// `x` and `y` are the point of the picture that ends up in the middle,
    /// each from nought to one; `scale` is how far in. The middle at full
    /// width is what everything did before this existed, so that is what
    /// nothing means.
    struct Framing: Hashable {
        var x: Double = 0.5
        var y: Double = 0.5
        var scale: Double = 1

        static let middle = Framing()

        var isMiddle: Bool {
            abs(x - 0.5) < 0.001 && abs(y - 0.5) < 0.001 && abs(scale - 1) < 0.001
        }
    }

    struct Frame: Decodable, Hashable {
        var hash: String = ""
        var filename: String = ""
        var said: String = ""
        /// **The trim rides with the frame**, so the thumbnail in a list plays
        /// the same seconds the viewer does. Without it a clip cut on the Mac
        /// went on playing whole everywhere it was small.
        var trimStart: Double?
        var trimEnd: Double?
        /// **And so does the framing**, for exactly the same reason: a picture
        /// framed on its wall and drawn uncropped in a filmstrip is two
        /// different pictures.
        var framing: Framing = .middle
        /// And the arrows — a marked frame is marked wherever it is drawn.
        var arrows: [Arrow] = []

        init(hash: String, filename: String, said: String = "",
             trimStart: Double? = nil, trimEnd: Double? = nil,
             framing: Framing = .middle, arrows: [Arrow] = []) {
            self.hash = hash
            self.filename = filename
            self.said = said
            self.trimStart = trimStart
            self.trimEnd = trimEnd
            self.framing = framing
            self.arrows = arrows
        }

        enum Key: String, CodingKey {
            case hash, filename, kind, trimStart, trimEnd, cropX, cropY, cropScale, arrows
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            hash = c.text(.hash)
            filename = c.text(.filename)
            said = c.text(.kind)
            trimStart = c.maybeNumber(.trimStart)
            trimEnd = c.maybeNumber(.trimEnd)
            framing = Framing(x: c.number(.cropX, or: 0.5),
                              y: c.number(.cropY, or: 0.5),
                              scale: c.number(.cropScale, or: 1))
            arrows = Arrow.parse(c.maybeText(.arrows))
        }

        /// The range this use plays, when it has been cut. Both ends have to be
        /// there and make sense — half a trim is not a trim.
        var cut: (start: Double, end: Double)? {
            guard let trimStart, let trimEnd, trimEnd > trimStart else { return nil }
            return (trimStart, trimEnd)
        }

        /// Proxies are stored under the extension they were written with.
        var ext: String {
            let parts = filename.split(separator: ".")
            return parts.count > 1 ? String(parts.last!) : "png"
        }
        var kind: Kind { Kind(said: said, ext: ext) }
    }

    struct Row: Decodable, Identifiable {
        /// The project's own columns, uniformly as lists — a text or single
        /// value is a list of one, a check is present or absent, a multi is
        /// itself.
        var custom: [String: [String]]?

        var placement: String = ""
        var shot: String = ""
        var sceneId: String?
        var number: String = ""
        var title: String = ""
        var description: String = ""
        /// The same words with the Mac's bold and italic (RTF, base64), kept
        /// beside the plain text; read only by the Document page.
        var descriptionRich: String = ""
        var size: String = ""
        var angle: [String] = []
        var movement: String = ""
        var lens: String = ""
        /// Extenders and the like on the lens for this shot, and its filters
        /// (his ask, 2026-10-14). Several each.
        var modifiers: [String] = []
        var lensFilters: [String] = []
        var support: String = ""
        var notes: String = ""
        var tags: [String] = []
        var struck: Bool = false
        var priority: String = ""
        /// Which camera, if any.
        var unit: Unit?
        /// **Which day this shot falls on, and which run of the film it is
        /// in** — Ref 250. Both were columns a project could show and the
        /// phone had neither, so it left a gap where they should be.
        ///
        /// Both are read-only here, and that is parity rather than a shortfall:
        /// a day is an assignment made on the Mac's board — its cell has no
        /// editor on the Mac either — and a sequence belongs to the scene, so
        /// it is set on the scene's own screen.
        var day: String?
        var dayId: String?
        var sequence: String?
        var sequenceId: String?
        var sequenceColour: String?
        /// Its highlight, hex, when it has one (`Swatches.highlight`).
        var colour: String?
        /// Other shots stand in for this one.
        var isMaster: Bool = false
        /// The number of the master this shot stands in for, or nil.
        var linkedTo: String?
        /// **The stretch of the script this shot quotes** (2026-09-19): which
        /// script (a section id, or empty for the film's), the UTF-16 range,
        /// and the words themselves, read off the script by the engine every
        /// time. `scriptFrom` is nil on a shot that quotes nothing.
        var scriptOf: String?
        var scriptFrom: Int?
        var scriptTo: Int?
        /// Every stretch, the first one too — a shot can quote several
        /// lines far apart (2026-10-05). `[[from, to], …]`.
        var scriptSpans: [[Int]] = []
        var script: String = ""
        /// The shot's picture, when it has one, and how many it has in total.
        var frame: Frame?
        var frames: Int = 0
        /// **Every** picture on the shot, in the order they sit in. A shot
        /// covered three ways has three, and showing one of them is showing a
        /// third of the answer.
        var stills: [Still] = []
        /// Where the Document page sets its frame, and how much of the
        /// measure it takes (`layout`).
        var frameWidth: Double = 0
        var framePosition: String = ""

        enum Key: String, CodingKey {
            case custom, placement, shot, sceneId, number, title, description, descriptionRich
            case size, angle, movement, lens, support, notes, tags, struck, priority
            case modifiers, lensFilters = "lens_filters"
            case unit, day, dayId, sequence, sequenceId, sequenceColour
            case colour, isMaster, linkedTo
            case scriptOf, scriptFrom, scriptTo, scriptSpans, script
            case frame, frames, stills, printFrame, offKit, frameWidth, framePosition
        }

        /// **What it uses that the spec sheet lacks** (Ref 1627): the lens,
        /// the camera's body, modifiers and filters, and which shoot's sheet
        /// would take them. Only while the sheet is followed.
        var offKit: OffKit?
        struct OffKit: Decodable, Hashable {
            var shoot: Int = 0
            var lens: String?
            var camera: String?
            var body: String?
            var modifiers: [String]?
            var filters: [String]?
        }

        /// **The shot's Print Frame, when its bake is current** — the board
        /// the Mac made for paper. A waiting clip that is the shot's key
        /// picture shows it with Preview Stills on (2026-10-14).
        var board: PrintBoard?

        struct PrintBoard: Decodable, Hashable {
            var hash: String
            var ext: String
            /// The baked board's own size in pixels: its shape, for the storyboard.
            var width: Int?
            var height: Int?
        }
        private struct PrintFrameOnRow: Decodable {
            var baked: PrintBoard?
            var stale: Bool?
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            if let pf = (try? c.decodeIfPresent(PrintFrameOnRow.self, forKey: .printFrame)) ?? nil,
               pf.stale == false {
                board = pf.baked
            }
            custom = c.lists(.custom)
            placement = c.text(.placement)
            shot = c.text(.shot)
            sceneId = c.maybeText(.sceneId)
            number = c.text(.number)
            title = c.text(.title)
            description = c.text(.description)
            descriptionRich = c.text(.descriptionRich)
            size = c.text(.size)
            angle = c.words(.angle)
            movement = c.text(.movement)
            lens = c.text(.lens)
            modifiers = c.words(.modifiers)
            lensFilters = c.words(.lensFilters)
            support = c.text(.support)
            notes = c.text(.notes)
            tags = c.words(.tags)
            struck = c.flag(.struck)
            priority = c.text(.priority)
            unit = c.one(Unit.self, .unit)
            day = c.maybeText(.day)
            dayId = c.maybeText(.dayId)
            sequence = c.maybeText(.sequence)
            sequenceId = c.maybeText(.sequenceId)
            sequenceColour = c.maybeText(.sequenceColour)
            colour = c.maybeText(.colour)
            isMaster = c.flag(.isMaster)
            linkedTo = c.maybeText(.linkedTo)
            scriptOf = c.maybeText(.scriptOf)
            scriptFrom = c.maybeCount(.scriptFrom)
            scriptTo = c.maybeCount(.scriptTo)
            scriptSpans = ((try? c.decodeIfPresent([[Int]].self, forKey: .scriptSpans)) ?? nil) ?? []
            script = c.text(.script)
            frame = c.one(Frame.self, .frame)
            frames = c.count(.frames)
            stills = c.many(Still.self, .stills)
            offKit = c.one(OffKit.self, .offKit)
            frameWidth = c.number(.frameWidth, or: 0)
            framePosition = c.text(.framePosition)
        }

        /// The placement alone is not enough — it survives a move between
        /// scenes, so a row carrying only it keeps its identity while moving to
        /// a different list and SwiftUI hands back the view it already built.
        var id: String { (sceneId ?? "") + "/" + placement }

        /// Whether this shot quotes any of the script.
        var quotesScript: Bool { scriptFrom != nil && (scriptTo ?? 0) > (scriptFrom ?? 0) }

        /// Every stretch this shot quotes: the engine's list, else the one
        /// it always had.
        var spans: [(from: Int, to: Int)] {
            let all = scriptSpans.compactMap { $0.count == 2 && $0[1] > $0[0] ? (from: $0[0], to: $0[1]) : nil }
            if !all.isEmpty { return all }
            if let from = scriptFrom, let to = scriptTo, to > from { return [(from, to)] }
            return []
        }

        /// The colour of the run of the film this shot is in, if it is in one.
        var sequenceTint: Color? {
            guard let sequenceColour, !sequenceColour.isEmpty else { return nil }
            return Palette.tint(sequenceColour)
        }

        /// What is in one column of this row, whatever kind of column it is.
        ///
        /// **One place asks, so nothing has to know the shape of a project.**
        /// A column the project made for itself comes back the same way a
        /// built-in one does.
        func cell(_ name: String) -> [String] {
            switch name {
            case "title":       return title.isEmpty ? [] : [title]
            case "description": return description.isEmpty ? [] : [description]
            case "script":      return script.isEmpty ? [] : [script]
            case "notes":       return notes.isEmpty ? [] : [notes]
            case "size":        return size.isEmpty ? [] : [size]
            case "angle":       return angle
            case "movement":    return movement.isEmpty ? [] : [movement]
            case "lens":        return lens.isEmpty ? [] : [lens]
            case "modifiers":   return modifiers
            case "lens_filters": return lensFilters
            case "support":     return support.isEmpty ? [] : [support]
            case "priority":    return priority.isEmpty ? [] : [priority]
            case "tags":        return tags
            case "camera":      return unit.map { [$0.label] } ?? []
            // Where the shot sits rather than what it is — Ref 250.
            case "day":         return (day ?? "").isEmpty ? [] : [day!]
            case "sequence":    return (sequence ?? "").isEmpty ? [] : [sequence!]
            default:            return custom?[name] ?? []
            }
        }

        /// The line under a shot in the list.
        ///
        /// **Built from whatever the project's columns are**, in the project's
        /// own order, rather than from a fixed size · lens · movement. Three at
        /// most: it is a line in a list, not the shot.
        func craft(_ columns: [Column]) -> String {
            columns
                .filter { $0.visible && $0.shape == "single" }
                .compactMap { cell($0.name).first?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(3)
                .joined(separator: " \u{00B7} ")
        }

        /// The words of the script this shot quotes, when the project shows
        /// its Script column and the shot quotes any. Nil otherwise, so a row
        /// on a film never grows a line for it.
        func quoted(_ columns: [Column]) -> String? {
            guard columns.contains(where: { $0.name == "script" && $0.visible }) else { return nil }
            let words = script.trimmingCharacters(in: .whitespacesAndNewlines)
            return words.isEmpty ? nil : words
        }

        /// What the shot says, under its name.
        ///
        /// **The description, and only the description.** It used to fall back
        /// to the title when there was no description — which was right while
        /// the row drew nothing else, and became a bug the moment the row
        /// started drawing the title beside the number: the same words twice,
        /// once bold and once under it.
        ///
        /// Empty is a fine answer. The row is not blank without it — it has a
        /// number and, usually, a name.
        func said(_ columns: [Column]) -> String {
            guard columns.contains(where: { $0.name == "description" && $0.visible })
            else { return "" }
            return description.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

/// **A film's own icon**: the outline to draw, and the colour to draw it in.
///
/// His call, 2026-09-11 — the pair belongs to the film rather than to a Mac, so
/// it arrives through the ordinary sync and any device that has the film has it.
/// `Mark.swift` draws one; this is only what it is made of, and it sits with the
/// decoder so the phone's checks can compile without SwiftUI.
struct FilmMark: Codable, Hashable {
    var path: String
    var colour: String
}
