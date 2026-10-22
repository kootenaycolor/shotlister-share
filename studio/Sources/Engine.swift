import Foundation
import CoreLocation

/// The Rust engine, as far as Swift is concerned.
///
/// One command in, one view out. Nothing here decides anything about shot lists —
/// it only carries questions across the boundary and decodes the answers.
final class Engine {
    private var handle: OpaquePointer?
    /// **One command at a time, whichever thread asks.** The engine's handle
    /// is not safe to enter twice at once. Everything used to ask from the
    /// main thread, which serialised it for free; since 2026-10-15 the
    /// export window writes its pages from a queue of its own (the slider
    /// freeze), so the turn-taking is made explicit here.
    private let turn = NSLock()

    /// The film's own folder. Held because a few things beside the engine
    /// need it — `Filmstrip` reads the clips in `media/proxies` to make the
    /// strips a printed page asks for — and passing it around separately went
    /// wrong once already.
    let folder: URL

    init?(path: URL, device: UInt64) {
        guard let h = path.path.withCString({ sl_open_as($0, device) }) else { return nil }
        handle = h
        folder = path
    }

    deinit {
        if let h = handle { sl_close(h) }
    }

    /// Sends a command and returns the raw JSON reply.
    @discardableResult
    func call(_ parts: String...) -> Data { call(parts) }

    /// The same door, for a command whose parts are counted at runtime — the
    /// New scene box sends as many field-and-value pairs as were filled in.
    func call(_ parts: [String]) -> Data {
        guard let h = handle else { return Data() }
        let line = parts.joined(separator: "\t")
        turn.lock()
        defer { turn.unlock() }
        guard let reply = line.withCString({ sl_call(h, $0) }) else {
            return Data()
        }
        defer { sl_free(reply) }
        return Data(String(cString: reply).utf8)
    }

    /// A whole command, newline and all — the script commands carry a payload
    /// after the first line, so they cannot be assembled from tab-joined parts.
    func callRaw(_ line: String) -> Data {
        guard let h = handle else { return Data() }
        turn.lock()
        defer { turn.unlock() }
        guard let reply = line.withCString({ sl_call(h, $0) }) else { return Data() }
        defer { sl_free(reply) }
        return Data(String(cString: reply).utf8)
    }

    func view() -> ViewModel? { decode(call("view")) }

    /// Filtering is the only thing in the app that hides a row, so it is one
    /// question asked once rather than a rule each screen keeps for itself.
    func filter(text: String, hideStruck: Bool) -> ViewModel? {
        decode(call("filter", hideStruck ? "1" : "0", text))
    }

    /// Whether other devices have written anything since we last looked. Cheap
    /// enough to ask every time the window comes forward.
    func hasIncoming() -> Bool {
        guard let text = String(data: call("incoming"), encoding: .utf8) else { return false }
        return text.contains("\"waiting\":true")
    }

    struct Storage: Decodable { var originalBytes: Int }
    struct Pruned: Decodable { var freedBytes: Int }

    func storage() -> Storage? {
        try? JSONDecoder().decode(Storage.self, from: call("storage"))
    }

    func prune(toMegabytes: Int) -> Pruned? {
        try? JSONDecoder().decode(Pruned.self, from: call("prune", String(toMegabytes)))
    }

    struct BulkPlan: Decodable {
        var summary: String
        var needsConfirming: Bool
        var spare: Int
        var without: Int
        var pairs: [Pair]

        struct Pair: Decodable {
            var filename: String
            var placement: String
            var number: String
            var hasFrames: Bool
        }
    }

    /// What a folder of pictures would do, worked out before anything is done.
    func bulkPlan(_ filenames: [String]) -> BulkPlan? {
        try? JSONDecoder().decode(
            BulkPlan.self,
            from: call("bulkplan", filenames.joined(separator: "\u{1f}"))
        )
    }

    struct Pull: Decodable {
        var merged: Int
        var devices: Int
        var needsAttention: Bool
        var clashes: [Clash]

        struct Clash: Decodable, Hashable {
            var record: String
            var field: String
            var said: String
            /// The value on screen, and the one that is only in the log —
            /// both in the engine's own words, so a button cannot spell a
            /// value differently from the sentence above it. Ref 231.
            var kept: String = ""
            var other: String = ""
        }
    }

    /// Settle one disagreement by taking the value that was only in the log
    /// — Ref 231. The notice could only ever keep what was on screen.
    func takeOther(record: String, field: String) -> ViewModel? {
        decode(call("takeother", record, field))
    }

    func pull() -> Pull? {
        try? JSONDecoder().decode(Pull.self, from: call("pull"))
    }

    /// **Not `Plan`.** `Scan.swift` already owns a top-level `Plan` — a room's
    /// floor plan — and `Engine.floorplan` returns it. A nested `Engine.Plan`
    /// silently wins inside this type, so naming it that quietly changed what
    /// `floorplan` returns and broke the scan reader instead of this file.
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
        /// The relay's media listing this plan was made from, kept so the
        /// tidy that follows judges the same moment. Not part of the engine's
        /// answer; `Relay.plan` fills it in.
        var listing: String = ""

        private enum CodingKeys: String, CodingKey {
            case uploadLogs, rewriteLogs, downloadLogs, uploadMedia, downloadMedia, steps, incoming, outgoing
        }
    }

    /// **What should move between this project and the relay**, given what the
    /// relay says it holds.
    ///
    /// Both arguments are exactly what the relay replied with, passed straight
    /// through. They cannot contain a tab — JSON escapes one inside a string
    /// and has none between tokens — so the tab-delimited command line is safe.
    ///
    /// The engine decides and `Relay` carries. Working this out in Swift as
    /// well would be a second answer to the same question, and the one that
    /// drifted would be the one nobody tested.
    func syncPlan(state: String, media: String) -> SyncPlan? {
        try? JSONDecoder().decode(SyncPlan.self, from: call("syncplan", state, media))
    }

    /// Of the files the relay lists, the ones this film no longer names —
    /// the engine's judgement (`Doc::stray_media_names`), from the same
    /// listing `syncPlan` reads.
    func strays(media: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: call("strays", media))) ?? []
    }

    /// A clip this film holds, as `reclip` wants it named.
    struct Movie: Decodable {
        let media: String
        let hash: String
        let filename: String
        let bytes: Int
    }

    func movies() -> [Movie] {
        (try? JSONDecoder().decode([Movie].self, from: call("movies"))) ?? []
    }

    /// What replacing a clip's bytes left behind.
    struct Reclipped: Decodable {
        let hash: String
        let before: String
        /// The old files' names, gone from this Mac and owed to the relay.
        let gone: [String]
    }

    /// The same clip, made smaller after the fact — its record and every use
    /// of it untouched. The caller carries the poster across afterwards with
    /// `poster(hash:data:)` under the new hash.
    func reclip(media: String, width: Int, height: Int, ext: String, data: Data) -> Reclipped? {
        try? JSONDecoder().decode(
            Reclipped.self,
            from: call("reclip", media, String(width), String(height), ext, data.base64EncodedString()))
    }

    struct Standing: Decodable {
        var count: Int
        var clashes: [Pull.Clash]
    }

    /// Every disagreement standing right now — asked at open, because the
    /// ordinary way two machines disagree is while this one was closed, and
    /// opening merges the other's log silently.
    /// **Everything the project already holds, grouped the way he asked for it**
    /// — Ref 228, and his words: *"organized by what images are associated with
    /// what mood board, location, or scene. If it's one big gallery, it would
    /// be too confusing."*
    ///
    /// A section per scene, per shot and per location, in the order the sidebar
    /// has them, narrowed by a word against the filename. `uses` is how many
    /// places already point at that one file.
    func gallery(_ word: String = "") -> [Gallery.Group] {
        (try? JSONDecoder().decode(Gallery.self, from: call("gallery", word)))?.groups ?? []
    }

    struct Gallery: Decodable {
        /// The engine calls the envelope `groups`; `pictures` is the total.
        var groups: [Group]
        var pictures: Int

        struct Group: Decodable, Identifiable {
            /// `scene`, `shot`, `board` or `location`.
            var kind: String
            var id: String
            var label: String
            /// The scene this shot's group belongs to, so the picker can fold
            /// it under its own heading. Empty for anything that stands alone.
            var parent: String = ""
            var items: [Item]
        }

        struct Item: Decodable, Identifiable {
            var ref: String
            var hash: String
            var filename: String
            var kind: String
            var caption: String
            /// How many places already point at this one file.
            var uses: Int
            var id: String { ref }
            var ext: String {
                let parts = filename.split(separator: ".")
                return parts.count > 1 ? String(parts.last!) : "png"
            }
        }
    }

    /// **The frames with nothing behind them** — Ref 224, by hash.
    ///
    /// A frame's record and its picture travel separately, so a record can be
    /// here while the bytes are still coming down, or never come at all. Two of
    /// his shots carry the second kind: records written on 2026-08-16 by
    /// something that stored the entry and left the file behind. Drawn as a
    /// plain grey square that is indistinguishable from a picture in transit,
    /// and he was deleting real photographs beside them trying to tidy up.
    ///
    /// The engine is the one that can tell them apart, because it knows what is
    /// on disk rather than what a read happened to fail at. This is the same
    /// answer the phone works out by failing twice, asked once and properly.
    func hollowFrames() -> Set<String> { gaps().hollow }

    /// The frames with nothing behind them, split two ways: a file that never
    /// came (`hollow`), and a picture deleted from the Media window, by hash,
    /// with the name it left (`gone`).
    func gaps() -> (hollow: Set<String>, gone: [String: String]) {
        struct Gap: Decodable { var hash: String; var filename: String; var gone: Bool? }
        struct Reply: Decodable { var missing: [Gap] }
        guard let r = try? JSONDecoder().decode(Reply.self, from: call("missing"))
        else { return ([], [:]) }
        var hollow = Set<String>()
        var gone: [String: String] = [:]
        for g in r.missing where !g.hash.isEmpty {
            if g.gone == true { gone[g.hash] = g.filename } else { hollow.insert(g.hash) }
        }
        return (hollow, gone)
    }

    /// **Every picture and clip in the film**, biggest first, with where each
    /// is used — the Media window. (`engine::shelf`)
    struct Shelf: Decodable {
        var items: [Item]
        var gone: [Gone]
        var count: Int
        var bytes: Int
        var unused: Int
        var unusedBytes: Int

        struct Item: Decodable, Identifiable, Hashable {
            var media: String
            var hash: String
            var filename: String
            var kind: String
            var bytes: Int
            var width: Int
            var height: Int
            var seconds: Double
            var versions: Int
            var uses: [Use]
            var id: String { media }
            var used: Bool { !uses.isEmpty }
        }

        struct Use: Decodable, Identifiable, Hashable {
            var ref: String
            var owner: String
            /// `shot`, `scene`, `location`, `board` or `diagram`.
            var kind: String
            var label: String
            var detail: String
            /// The scene to go to for it; empty for a location or a board.
            var scene: String
            var id: String { ref }
        }

        struct Gone: Decodable, Identifiable, Hashable {
            var media: String
            var hash: String
            var filename: String
            var bytes: Int
            /// Milliseconds since 1970.
            var on: Double
            var id: String { media }
        }
    }

    struct MediaDeleted: Decodable {
        var deleted: Int
        var freedBytes: Int
        var removed: [String]
    }

    func shelf() -> Shelf? {
        try? JSONDecoder().decode(Shelf.self, from: call("shelf"))
    }

    /// Delete for real: every use, and the files. Not undoable.
    func deleteMedia(_ media: [String]) -> MediaDeleted? {
        try? JSONDecoder().decode(MediaDeleted.self, from: call(["deletemedia"] + media))
    }

    func deleteUnusedMedia() -> MediaDeleted? {
        try? JSONDecoder().decode(MediaDeleted.self, from: call("deletemedia", "unused"))
    }

    func clashes() -> [Pull.Clash] {
        (try? JSONDecoder().decode(Standing.self, from: call("clashes")))?.clashes ?? []
    }

    /// Answer every standing disagreement by keeping what is on screen.
    ///
    /// A clash is worked out from the log every time it is asked for, so
    /// emptying the list on this side ends nothing: the next open asks again
    /// and gets the same answer. Settling writes the decision down, which is
    /// the only thing that makes the question stop being asked.
    func settle() -> ViewModel? { decode(call("settle")) }

    /// Settle one disagreement by keeping the value on screen.
    func keepMine(record: String, field: String) -> ViewModel? {
        decode(call("settle", record, field))
    }

    /// Why the last open failed. Read straight after a failed open, before
    /// anything else is tried.
    static func lastProblem() -> String {
        guard let raw = sl_problem() else { return "" }
        defer { sl_free(raw) }
        return String(cString: raw)
    }

    /// What an export is about, and how it should look.
    ///
    /// **One value rather than four trailing arguments.** `print` and `xlsx`
    /// take the same narrowing, and both grew a string of optional positions
    /// that every caller had to pad. This carries them together, so a caller
    /// says only what it means and the two commands cannot drift apart.
    struct ExportScope {
        /// Exactly these scenes, whatever is searched or filtered on screen.
        var scenes: [String] = []
        /// One shoot day, or everything not on a day yet. Mutually exclusive
        /// with `scenes` — the engine refuses both, because a day already
        /// says which shots and a scene list says a different set.
        var day: Day? = nil
        /// Overrides the columns on screen. Nil keeps them.
        var columns: [String]? = nil
        /// Multiplies the root font size. 1.0 is normal.
        var scale: Double? = nil
        /// How much of the page a picture takes — `small`, `medium`, `large`.
        /// Nil leaves it to the engine, which means medium.
        var frames: String? = nil
        /// **His own say over how wide each column of the table prints** — a
        /// multiplier on the weight the page already gives it, keyed by field
        /// name. Empty is the page's own design, untouched.
        var widths: [String: Double] = [:]
        /// **Auto's own column shares, exactly**, in percent by field
        /// (`TableLayout.shares`). When given the table prints with these and
        /// `widths` is not read.
        var shares: [String: Double] = [:]
        /// Auto cut no word, so the page may switch hyphenation off.
        var fitted = false
        /// **What the Document view writes in its own top-right corner** —
        /// `SCRIPT ORDER`, `BY SHOOT DAY · 2 SCENES NOT SHOWN`. Only the app
        /// knows it, because only the app knows how the scene list is being
        /// read; the engine draws the line if it is given one and leaves it
        /// off if it is not.
        var order: String? = nil
        /// More `key=value` words one page reads and the rest ignore — the
        /// diagram page's scale bar, dimensions and cones, and its paper.
        var extra: [String] = []
        /// **The export box's Order, Filter and Days** (2026-10-15):
        /// `arrange=`, `filter=table`, `days=`, `daypages=1` — read by the
        /// engine's `Options::arranged`. Empty is the narrowing as it always was.
        var narrowing: [String] = []

        enum Day {
            case on(String)
            case unscheduled

            var argument: String {
                switch self {
                case .on(let id): return id
                case .unscheduled: return "unscheduled"
                }
            }
        }

        /// The whole project as it stands on screen — every filter live.
        static let onScreen = ExportScope()

        var options: [String] {
            var out: [String] = []
            if !scenes.isEmpty { out.append("scenes=" + scenes.joined(separator: ",")) }
            if let day { out.append("day=" + day.argument) }
            if let columns { out.append("columns=" + columns.joined(separator: ",")) }
            if let scale { out.append(String(format: "scale=%.2f", scale)) }
            if let frames { out.append("frames=" + frames) }
            if let order, !order.isEmpty { out.append("order=" + order) }
            out.append(contentsOf: extra)
            out.append(contentsOf: narrowing)
            if !shares.isEmpty {
                if fitted { out.append("fitted=1") }
                out.append("shares=" + shares.sorted { $0.key < $1.key }
                    .map { String(format: "%@:%.4f", $0.key, $0.value) }
                    .joined(separator: ","))
            }
            // Only the ones he has actually moved: a list of `field:1.00` for
            // every column would say the same as saying nothing, at length.
            let moved = widths.filter { abs($0.value - 1) > 0.01 }
            if !moved.isEmpty {
                out.append("widths=" + moved.sorted { $0.key < $1.key }
                    .map { String(format: "%@:%.3f", $0.key, $0.value) }
                    .joined(separator: ","))
            }
            return out
        }
    }

    /// Write the page a PDF is made from. Returns the path it wrote.
    func printPage(_ kind: String, to path: String, scope: ExportScope = .onScreen,
                   stripsReady: Bool = false) -> String? {
        // Every printed page in the app comes through here, which is why the
        // clips' strips are made here and nowhere else — Ref 514. It does
        // nothing at all when they are already made and still the right
        // shape. `stripsReady`: the caller has just run `Filmstrip.prepare`,
        // so the check is not paid twice on the main thread.
        if !stripsReady { Filmstrip.ensure(engine: self) }
        var options = scope.options
        // **The diagram page draws the sun by the screen's own clock** (Ref
        // 1576): the same minutes from UTC the on-screen `diagram` call
        // sends, so paper and screen agree. Without it the page would read
        // the hour off the longitude alone.
        if kind == "diagram", !options.contains(where: { $0.hasPrefix("tz=") }) {
            options.append("tz=\(TimeZone.current.secondsFromGMT() / 60)")
        }
        let reply = callRaw((["print", kind, path] + options).joined(separator: "\t"))
        guard let text = String(data: reply, encoding: .utf8), text.contains("\"path\"") else {
            return nil
        }
        return path
    }

    /// **Every use of a moving picture in this film**, and what its
    /// four-moment strip is filed under.
    ///
    /// A *use*, not a file: the trim lives on the attachment, so one movie on
    /// two shots cut two different ways owes two strips. `key` is the engine's
    /// own `strip_key` — this side never works a name out, it is told one, so
    /// the file that gets written is the file that gets read.
    struct ClipUse: Decodable {
        /// Where the movie itself is, minus its extension.
        let stem: String
        /// What its strip is filed under.
        let key: String
        /// The kept range, in seconds. Zero to zero is the whole clip.
        let start: Double
        let end: Double

        var range: (start: Double, end: Double)? {
            end > start ? (start, end) : nil
        }
    }

    /// **What each column of the printed table is worth**, before he adjusts
    /// anything — asked of the engine rather than kept here, so the weights
    /// live in one place and the dial in the dialog is a multiplier on
    /// whatever they say.
    struct ColumnWeight: Decodable {
        let field: String
        let weight: Double
    }

    /// The Table's filter in words, its sort, and every shoot day — what the
    /// export box shows (`exportinfo`).
    func exportInfo() -> ExportInfo? {
        try? JSONDecoder().decode(ExportInfo.self, from: callRaw("exportinfo"))
    }

    /// **Auto, for the printed table** (`export::autolayout`): which way
    /// round, how big the text and the pictures, and every column's share,
    /// worked out from what is actually in the cells.
    struct TableLayout: Decodable, Equatable {
        let orientation: String
        let scale: Double
        let frames: String
        /// The storyboard frame's width on paper, in inches.
        let picture: Double
        let pages: Int
        /// Words it could not avoid cutting — zero unless no sheet can.
        let cut: Int
        let shares: [String: Double]
        /// The same shares as the export box's width multipliers, so a
        /// switch to Manual starts on exactly this sheet.
        let factors: [String: Double]

        var look: Printing.Look {
            Printing.Look(orientation: Printing.Orientation(rawValue: orientation) ?? .landscape,
                          scale: scale,
                          frames: Printing.FrameSize(rawValue: frames) ?? .medium)
        }
    }

    /// Measure the table here, on this thread (the engine's own), and get a
    /// ticket the deciding can be done against anywhere — `solveTableLayout`.
    func tableLayoutTicket(scope: ExportScope) -> UInt64? {
        let reply = callRaw((["tablelayout"] + scope.options + ["defer=1"]).joined(separator: "\t"))
        struct Ticket: Decodable { let ticket: UInt64 }
        return (try? JSONDecoder().decode(Ticket.self, from: reply))?.ticket
    }

    /// **Decide a measured table, off the main thread.** Touches no project:
    /// the measuring already happened, under `tableLayoutTicket`.
    static func solveTableLayout(_ ticket: UInt64) -> TableLayout? {
        guard let reply = sl_solve_layout(ticket) else { return nil }
        defer { sl_free(reply) }
        return try? JSONDecoder().decode(TableLayout.self, from: Data(String(cString: reply).utf8))
    }

    /// Both at once, here — for an export that is about to wait on the
    /// renderer anyway (each day of a per-day export, a checking run).
    func tableLayout(scope: ExportScope) -> TableLayout? {
        let reply = callRaw((["tablelayout"] + scope.options).joined(separator: "\t"))
        return try? JSONDecoder().decode(TableLayout.self, from: reply)
    }

    func printedColumnWeights(scope: ExportScope) -> [ColumnWeight] {
        let reply = callRaw((["colwidths"] + scope.options).joined(separator: "\t"))
        guard !reply.isEmpty else { return [] }
        return (try? JSONDecoder().decode([ColumnWeight].self, from: reply)) ?? []
    }

    func clipUses() -> [ClipUse] {
        let reply = call("clips")
        guard !reply.isEmpty else { return [] }
        do {
            return try JSONDecoder().decode([ClipUse].self, from: reply)
        } catch {
            if let text = String(data: reply, encoding: .utf8) {
                FileHandle.standardError.write(Data("engine: \(text)\n".utf8))
            }
            return []
        }
    }

    func facet(_ field: String, _ value: String) -> ViewModel? {
        decode(call("facet", field, value))
    }

    /// **The shoot picker** (piece D): one shoot's id, or "" for All Shoots.
    /// Every list narrows to it; new scenes and days are born into it.
    func pickShoot(_ id: String) -> ViewModel? {
        decode(call("facet", "shoot", id))
    }

    /// **Move to Shoot…** — scenes into one of the project's shoots, one undo.
    func moveToShoot(_ shoot: String, scenes: [String]) -> ViewModel? {
        decode(call("shootmove", shoot, scenes.joined(separator: ",")))
    }

    /// The one-time converter (piece D): section headings to shoots. Dry
    /// unless `apply`. Answers the engine's JSON as text.
    func shootPlan(apply: Bool) -> String {
        String(decoding: apply ? call("shootplan", "apply") : call("shootplan"), as: UTF8.self)
    }

    func sortBy(_ column: String, descending: Bool) -> ViewModel? {
        decode(call("sort", column, descending ? "desc" : "asc"))
    }

    /// **A shot into the shooting order**, just before `before` on `day`, or
    /// at the day's end; no day takes it off every day. Its number stays.
    func shootBefore(_ placement: String, day: String?, before: String?) -> ViewModel? {
        decode(call("shootbefore", placement, day ?? "", before ?? ""))
    }

    /// Fills an empty project with the sample list. Does nothing to one that
    /// already has scenes in it.
    func fillWithSample() -> ViewModel? { decode(call("demo")) }

    func detach(frame ref: String) -> ViewModel? { decode(call("detach", ref)) }
    /// Names one use of a file; the stored file's extension is kept.
    func renameUse(_ ref: String, to name: String) -> ViewModel? { decode(call("renameuse", ref, name)) }

    /// Make a shot one that others may stand in for, or stop it being one.
    /// Stopping cuts its followers loose **whole** — what they were showing is
    /// copied onto them first.
    func makeMaster(_ shot: String, on: Bool) -> ViewModel? {
        decode(call("master", shot, on ? "1" : "0"))
    }

    /// Point a shot at a master, or cut it loose. Nil unlinks.
    func link(_ shot: String, to master: String?) -> ViewModel? {
        decode(call("link", shot, master ?? "none"))
    }
    func moveFrame(_ ref: String, to index: Int) -> ViewModel? {
        decode(call("movemedia", ref, String(index)))
    }
    /// What is said under one use of a picture.
    func caption(_ ref: String, _ words: String) -> ViewModel? {
        decode(call("caption", ref, words))
    }

    /// **Sets a clip's remembered in/out range**, in seconds. The file on
    /// disk is never touched — only where this use of it starts and stops
    /// playing.
    func trim(_ ref: String, start: Double, end: Double) -> ViewModel? {
        decode(call("trim", ref, String(format: "%.3f", start), String(format: "%.3f", end)))
    }

    /// Back to playing the whole clip.
    func clearTrim(_ ref: String) -> ViewModel? {
        decode(call("trim", ref, "clear"))
    }

    /// **Which part of a picture to keep where it is drawn cropped**, and how
    /// far in. Belongs to this use of the file; the file is never touched. The
    /// engine holds the bounds, so nothing here clamps.
    func crop(_ ref: String, x: Double, y: Double, scale: Double) -> ViewModel? {
        decode(call("crop", ref,
                    String(format: "%.4f", x),
                    String(format: "%.4f", y),
                    String(format: "%.4f", scale)))
    }

    /// Back to the middle, at full width.
    func clearCrop(_ ref: String) -> ViewModel? {
        decode(call("crop", ref, "clear"))
    }

    /// **The storyboard arrows drawn over this use of a picture.** One line,
    /// the same one the engine stores and the same one every shell parses —
    /// see `ViewModel.Arrow`. Belongs to the use; the file is never touched.
    func arrows(_ ref: String, _ line: String) -> ViewModel? {
        decode(call("arrows", ref, line))
    }

    /// Back to a bare photograph.
    func clearArrows(_ ref: String) -> ViewModel? {
        decode(call("arrows", ref, "clear"))
    }

    /// **The same use of a picture, hanging somewhere else** — one board to
    /// another. Carries its caption and its name, because it is the same use
    /// rather than a new one.
    func movePicture(_ ref: String, to owner: String) -> ViewModel? {
        decode(call("movepictureto", ref, owner))
    }
    func duplicate(placement: String) -> ViewModel? { decode(call("duplicate", placement)) }
    func deletePlacement(_ placement: String) -> ViewModel? { decode(call("delete", placement)) }
    func deleteScene(_ scene: String) -> ViewModel? { decode(call("deletescene", scene)) }
    func archiveScene(_ scene: String, on: Bool) -> ViewModel? {
        decode(call("archivescene", scene, on ? "1" : "0"))
    }
    /// Copies of several shots, landed in one scene, as **one** thing to undo.
    /// The copies carry their frames — a shot copied is the shot, not a smear
    /// of its columns as text.
    func copyShots(_ placements: [String], toScene scene: String,
                   after: String? = nil) -> ViewModel? {
        decode(call("copyshots", placements.joined(separator: ","), scene, after ?? ""))
    }

    func movePlacement(_ placement: String, toScene scene: String) -> ViewModel? {
        decode(call("movescene", placement, scene))
    }

    /// Where a shot sits in the reading you are in — story order under a scene,
    /// shooting order under a day. They are different facts.
    func reorder(placement: String, to index: Int) -> ViewModel? {
        decode(call("reorder", placement, String(index)))
    }

    /// Two cameras on one moment. Tying a third to a pair joins the pair.
    func tie(_ a: String, _ b: String) -> ViewModel? { decode(call("tie", a, b)) }
    func untie(_ shot: String) -> ViewModel? { decode(call("untie", shot)) }

    func columnOrder(_ names: [String]) -> ViewModel? {
        decode(call("columnorder", names.joined(separator: ",")))
    }

    /// Reads a spreadsheet back into the list and reports what it did. A clean
    /// import is quiet; one with something to say has something in `renumbered`,
    /// `daysNotFound` or `skipped`.
    func importSheet(path: String) -> (report: ImportReport, view: ViewModel?)? {
        struct Reply: Decodable { var `import`: ImportReport; var view: ViewModel }
        guard let r = try? JSONDecoder().decode(Reply.self, from: call("import", path)) else {
            return nil
        }
        return (r.import, r.view)
    }
    func group(by key: String) -> ViewModel? { decode(call("group", key)) }
    func set(shot: String, field: String, value: String) -> ViewModel? {
        decode(call("set", shot, field, value))
    }
    func strike(shot: String, on: Bool) -> ViewModel? {
        decode(call("strike", shot, on ? "1" : "0"))
    }
    /// Several at once — one transaction engine-side, one undo.
    func strike(shots: [String], on: Bool) -> ViewModel? {
        decode(call("strike", shots.joined(separator: ","), on ? "1" : "0"))
    }
    func deletePlacements(_ placements: [String]) -> ViewModel? {
        decode(call("delete", placements.joined(separator: ",")))
    }
    func save() { call("save") }

    func vocabulary(_ field: String) -> [String] {
        struct Reply: Decodable { var values: [String] }
        guard let r = try? JSONDecoder().decode(Reply.self, from: call("vocab", field)) else { return [] }
        return r.values
    }

    /// The app has already sized and encoded the picture — that is a shell's job.
    ///
    /// `source` is the hash of what this was made from, when it is a smaller
    /// copy of something — Ref 211. The next arrival of that same file is then
    /// recognised before any encoder runs, which is the only way a re-encoded
    /// picture can be matched: one encoder run is not byte-for-byte the next.
    func paste(shot: String, width: Int, height: Int, ext: String, data: Data,
               kind: String = "image", seconds: Double = 0,
               named: String = "", source: String = "") -> ViewModel? {
        decode(call("paste", shot, String(width), String(height), ext,
                    data.base64EncodedString(), kind,
                    String(format: "%.3f", seconds), named, source))
    }

    /// The still that stands for a movie wherever a picture is drawn.
    func poster(hash: String, data: Data) {
        call("poster", hash, data.base64EncodedString())
    }

    func proxy(hash: String, ext: String = "png") -> Data? {
        stored(hash: hash, ext: ext)?.data
    }

    /// The stored bytes **and what they actually are**. A file is named by its
    /// contents here; the extension a person gave it is a label, and the two
    /// part company the moment a picture is re-encoded on the way in.
    func stored(hash: String, ext: String = "png") -> (ext: String, data: Data)? {
        struct Reply: Decodable { var data: String; var ext: String? }
        guard let r = try? JSONDecoder().decode(Reply.self, from: call("media", hash, ext)),
              let data = Data(base64Encoded: r.data) else { return nil }
        return (r.ext ?? ext, data)
    }

    // ---- the board ----------------------------------------------------

    func board() -> BoardModel? { decodeBoard(call("board")) }

    /// Dragging a whole strip onto a day. `nil` puts it back in the waiting column.
    func assign(scene: String, day: String?) -> BoardModel? {
        decodeBoard(call("scene", scene, day ?? "none"))
    }

    /// The scene's shots on that day, moved as one block to sit before
    /// another scene's — or last. The board's own reorder.
    func moveSceneInDay(_ scene: String, day: String, before: String?) -> BoardModel? {
        decodeBoard(call("sceneinday", scene, day, before ?? ""))
    }

    /// Pulling one shot out of its scene onto another day.
    func assign(placement: String, day: String?) -> BoardModel? {
        decodeBoard(call("place", placement, day ?? "none"))
    }

    /// **What a drag on the Schedule does when it lets go**, in one call and
    /// one undo step: the scenes onto `day` ahead of `before`'s strip (or
    /// last), or off every day with `nil`. `from` is the day the strips were
    /// lifted off — only their shots there travel — or `nil` for scenes from
    /// the list, which come whole.
    func putScenes(_ scenes: [String], from: String?, on day: String?, before: String?) -> BoardModel? {
        decodeBoard(call("putscenes", day ?? "none", from ?? "", before ?? "",
                         scenes.joined(separator: ",")))
    }

    /// Several shots onto a day — a scene's remainder opened in the scene
    /// list, or a few of its shots picked there. One undo step.
    func putShots(_ placements: [String], on day: String, before: String?) -> BoardModel? {
        decodeBoard(call("putshots", day, before ?? "", placements.joined(separator: ",")))
    }

    /// One shot onto a day, standing where it was let go unless its scene
    /// already has a strip there to join. One undo step.
    func putShot(_ placement: String, on day: String, before: String?) -> BoardModel? {
        decodeBoard(call("putshot", placement, day, before ?? ""))
    }

    /// Where a shot sits in its day's running order — `index` counted with
    /// the shot lifted out, the way a drag reports it.
    func orderInDay(_ placement: String, to index: Int) -> BoardModel? {
        decodeBoard(call("day", "order", placement, String(index)))
    }

    /// A shot onto a day at a place in its running order, from another day
    /// or none. One undo step.
    func putShot(_ placement: String, on day: String, at index: Int) -> BoardModel? {
        decodeBoard(call("day", "put", placement, day, String(index)))
    }

    /// A date makes the day arrive already dated — a calendar click, one undo.
    func addDay(date: String? = nil) -> BoardModel? {
        if let date, !date.isEmpty {
            return decodeBoard(call("day", "new", date))
        }
        return decodeBoard(call("day", "new"))
    }
    func moveDay(_ day: String, to index: Int) -> BoardModel? {
        decodeBoard(call("day", "move", day, String(index)))
    }
    /// Dated days into date order, among the places dated days already hold.
    func sortDaysByDate() -> BoardModel? { decodeBoard(call("day", "sortbydate")) }

    /// A day's own name, beside the `Day 3` its position gives it. The empty
    /// string takes the name away again.
    func nameDay(_ day: String, _ name: String) -> BoardModel? {
        decodeBoard(call("day", "name", day, name))
    }
    /// `YYYY-MM-DD`, or the empty string to clear it. **Dating the first day is
    /// what freezes the shot letters** — see `lettering.rs`.
    func dateDay(_ day: String, _ date: String) -> BoardModel? {
        decodeBoard(call("day", "date", day, date))
    }
    /// The day goes; every shot on it keeps everything of its own and goes back
    /// to waiting. Ask first — `Lane.count` says what it costs.
    func removeDay(_ day: String) -> BoardModel? {
        decodeBoard(call("day", "remove", day))
    }

    // ---- the page -----------------------------------------------------

    func layout(shot: String, position: String, width: Double) -> ViewModel? {
        decode(call("layout", shot, position, String(format: "%.3f", width)))
    }

    func keyFrame(shot: String, ref: String) -> ViewModel? {
        decode(call("keyframe", shot, ref))
    }

    // ---- adding -------------------------------------------------------

    func addShot(scene: String, after: String? = nil) -> ViewModel? {
        if let after { return decode(call("addshot", scene, after)) }
        return decode(call("addshot", scene))
    }
    /// A scene **and everything typed about it**, filed as one change.
    ///
    /// It used to take a number and nothing else, which is why a scene added
    /// by hand arrived blank. The pairs are the same field names a cell
    /// writes, plus `place`, which points the scene at a location record.
    /// One call, so one ⌘Z takes the whole scene back.
    /// A scene made from a title — the commercial way. The engine gives it
    /// the next whole number and lands it last. Same pairs as `addScene`.
    func addTitled(title: String, fields: [(String, String)] = []) -> ViewModel? {
        var parts = ["addtitled", title]
        for (field, value) in fields
        where !value.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(field)
            parts.append(value)
        }
        return decode(call(parts))
    }

    /// **What sort of film this is** — `film` or `commercial`. See the
    /// engine's `kind` module.
    func setKind(_ kind: String) -> ViewModel? {
        decode(call("kind", kind))
    }

    /// Every scene renumbered by its place in the list. Answers how many
    /// changed; the caller asks for its view after.
    func renumberInOrder() -> Int {
        struct Reply: Decodable { var changed: Int }
        return (try? JSONDecoder().decode(Reply.self, from: call("renumber")))?.changed ?? 0
    }

    /// A pasted AV script table, as scenes. Tabs travel as \u{1f} because
    /// the line is already split on tabs.
    func addScene(number: String, fields: [(String, String)] = []) -> ViewModel? {
        var parts = ["addscene", number]
        for (field, value) in fields
        where !value.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(field)
            parts.append(value)
        }
        return decode(call(parts))
    }

    /// What a typed heading says, without writing anything.
    ///
    /// Asked of the engine rather than worked out here, so a line typed into
    /// the New scene box and a line read out of a draft are never understood
    /// two different ways.
    struct Heading: Decodable {
        var number = ""
        var intExt = ""
        var location = ""
        var timeOfDay = ""
    }

    func readHeading(_ line: String) -> Heading {
        (try? JSONDecoder().decode(Heading.self, from: call("readheading", line)))
            ?? Heading()
    }

    /// Put the scenes back in the order their numbers say. One ⌘Z.
    func sortScenes() -> ViewModel? { decode(call("sortscenes")) }
    /// Turn CONTINUED and LATER into the time they point at — Ref 257, for a
    /// film imported before the reading was fixed.
    func settleTimes() -> ViewModel? { decode(call("settletimes")) }

    // ---- settings -----------------------------------------------------

    func lists() -> [ListModel] {
        struct Reply: Decodable { var lists: [ListModel] }
        guard let r = try? JSONDecoder().decode(Reply.self, from: call("lists")) else { return [] }
        return r.lists
    }

    /// Renaming reaches every shot on the old value — which is the point of it.
    @discardableResult
    func renameValue(field: String, from: String, to: String) -> Int {
        struct Reply: Decodable { var changed: Int }
        return (try? JSONDecoder().decode(Reply.self, from: call("list", "rename", field, from, to)))?.changed ?? 0
    }

    @discardableResult
    func removeValue(field: String, value: String) -> Int {
        struct Reply: Decodable { var changed: Int }
        return (try? JSONDecoder().decode(Reply.self, from: call("list", "remove", field, value)))?.changed ?? 0
    }

    func addValue(field: String, value: String) { call("list", "add", field, value) }

    /// **Give a term a colour of its own** — Ref 55. An empty colour hands it
    /// back to the hash, which is the only way out of one you have changed your
    /// mind about.
    func colourValue(field: String, value: String, hex: String) {
        call("list", "colour", field, value, hex)
    }

    /// Every colour anybody has chosen, across the standing lists and the
    /// project's own columns. Terms nobody has coloured are not in the answer.
    func termColours() -> [TermColour] {
        struct Reply: Decodable { var colours: [TermColour] }
        guard let r = try? JSONDecoder().decode(Reply.self, from: call("colours"))
        else { return [] }
        return r.colours
    }

    struct TermColour: Decodable {
        var field: String
        var term: String
        var hex: String
    }

    /// **Close a list**, so nothing can be learned into it by accident. See
    /// `engine/src/vocab.rs` for what a lock actually stops.
    func lockList(field: String, on: Bool) { call("list", "lock", field, on ? "1" : "0") }

    /// A new camera unit, born with its colour.
    func addUnit(label: String, colour: String) -> ViewModel? {
        decode(call("addunit", label, colour))
    }

    /// Rename a camera. **Every shot naming it follows for free** — a shot
    /// holds a reference to the unit rather than a copy of its name, so this is
    /// one write, not one per shot. That is the difference between a camera and
    /// a term, and it is why cameras took this long to get a page.
    func renameUnit(id: String, label: String) -> ViewModel? {
        decode(call("unit", "name", id, label))
    }

    /// The colour a camera wears in every cell that names it.
    func recolourUnit(id: String, colour: String) -> ViewModel? {
        decode(call("unit", "colour", id, colour))
    }

    /// The sensor a camera reads, in mm; a width of 0 clears it.
    func setUnitSensor(id: String, name: String, w: Double, h: Double) -> ViewModel? {
        decode(call("unit", "sensor", id, String(w), String(h), name))
    }

    /// Take a camera away. The shots that named it keep everything of their
    /// own and simply stop naming a camera — say the count before you ask.
    func removeUnit(id: String) -> ViewModel? {
        decode(call("unit", "remove", id))
    }

    func column(_ name: String, visible: Bool) -> ViewModel? {
        decode(call("column", name, visible ? "1" : "0"))
    }

    /// A column of the project's own. The kind is its shape — text, single,
    /// multi, check — and the engine refuses one it does not know.
    /// A sequence made by naming it — the script does not hand these out.
    /// A scanned room, read and straightened by the engine. An empty path asks
    /// for the hand-built sample.
    ///
    /// **The arithmetic is not Swift's.** His call: the Mac and the phone share
    /// the engine rather than each keeping their own copy of the geometry.
    func floorplan(at path: String) -> Plan? {
        try? JSONDecoder().decode(Plan.self, from: call("floorplan", path))
    }

    // ---- the script ------------------------------------------------------
    //
    // Phase 2's engine half has been finished since 2026-08-20 and had no door
    // on the Mac. These are that door. **Nothing here decides anything about a
    // screenplay** — the app decodes a PDF into runs and draws what comes back.

    /// Read a PDF and say what is in it. **Changes nothing.**
    ///
    /// `settings` is the four detection dials, or empty for the project's own.
    /// `merging` and `least` are how the cast is read — the same two the import
    /// takes, so the list on screen and the list that lands are one list.
    func readScript(runs: String, settings: String = "",
                    merging: String = "regular", least: Int = 0) -> ScriptReading? {
        try? JSONDecoder().decode(
            ScriptReading.self,
            from: callRaw("readscript\t\(settings)\t\(merging)\t\(least)\n" + runs))
    }

    /// What taking this draft in would do, in the plan's own sentences.
    /// **Writes nothing** — the name `weigh` is what makes it a rehearsal.
    func weighScript(_ taking: Taking, text: String) -> ScriptPlan? {
        try? JSONDecoder().decode(ScriptPlan.self, from: callRaw(taking.line(named: "weigh") + "\n" + text))
    }

    /// Take the draft in. Same computation as the weighing, so the confirm
    /// screen cannot promise something different from what happens.
    func takeScript(_ taking: Taking, named name: String, text: String) -> ViewModel? {
        struct Reply: Decodable { var view: ViewModel }
        let data = callRaw(taking.line(named: name) + "\n" + text)
        if let reply = try? JSONDecoder().decode(Reply.self, from: data) { return reply.view }
        return decode(data)
    }

    /// What the shell asks the engine to do with a draft.
    struct Taking {
        var filename = ""
        var importedAt = ""
        /// The indices `readscript` reported, for the scenes still ticked.
        var scenes: [Int] = []
        var cast: [String] = []
        var archiveOmitted = true
        var merging = "regular"
        var minimumSpeeches = 0
        /// **The dials the report was read under, sent again.** An index only
        /// means a scene if both readings found the same scenes, and the
        /// engine reads the text a second time here — under these rules, or
        /// under a different set and a different list. See `takescript` in
        /// `ffi/src/lib.rs`.
        var settings = ""
        /// **Which scenes are being taken as having moved**, by draft index —
        /// Ref 241. Empty means nothing moves, which is what taking a draft
        /// has always done.
        var moves: [Int] = []

        func line(named name: String) -> String {
            // `moves` goes on the end, after the settings, so that every
            // caller written before it keeps working unchanged.
            ["takescript", name, filename, importedAt,
             scenes.map(String.init).joined(separator: ","),
             cast.joined(separator: "|"),
             archiveOmitted ? "1" : "0",
             merging, String(minimumSpeeches), settings,
             moves.map(String.init).joined(separator: ",")].joined(separator: "\t")
        }
    }

    /// The PDF a revision came from, when it kept one. Empty for a draft taken
    /// in before revisions started keeping their pages.
    func scriptPDF(of revision: String) -> Data? {
        struct Reply: Decodable { var data: String }
        guard let r = try? JSONDecoder().decode(Reply.self, from: call("scriptpdf", revision)),
              !r.data.isEmpty else { return nil }
        return Data(base64Encoded: r.data)
    }

    /// Keep the pages beside the text, so the script can be read as printed.
    func keepScriptPDF(of revision: String, bytes: Data) {
        call("scriptpdf", revision, bytes.base64EncodedString())
    }

    func revisions() -> [Revision] {
        struct Reply: Decodable { var revisions: [Revision] }
        return (try? JSONDecoder().decode(Reply.self, from: call("revisions")))?.revisions ?? []
    }

    func renameRevision(_ id: String, to name: String) -> ViewModel? {
        decode(call("renamerevision", id, name))
    }

    /// The script laid out as real pages. Nil when the project has no script.
    func scriptPages(of revision: String = "") -> ScriptPages? {
        try? JSONDecoder().decode(ScriptPages.self,
                                  from: revision.isEmpty ? call("scriptpages")
                                                         : call("scriptpages", revision))
    }

    /// The dials this project reads scripts with. Given none, only reports.
    @discardableResult
    func detection(_ settings: String = "") -> Detection? {
        try? JSONDecoder().decode(Detection.self,
                                  from: settings.isEmpty ? call("detection")
                                                         : call("detection", settings))
    }

    // ---- locations ------------------------------------------------------
    //
    // Ref 57. The record the phone captures on a scout and the Mac draws.
    // **Nothing here touches a scene's `location`** — the slugline's word is
    // the script's and never ours.

    func addLocation(name: String) -> ViewModel? {
        decode(call("addlocation", name))
    }
    func setLocation(_ id: String, _ field: String, _ value: String) -> ViewModel? {
        decode(call("setlocation", id, field, value))
    }
    /// A room inside a location — Ref 269.
    func addArea(_ parent: String, name: String) -> ViewModel? {
        decode(call("addarea", parent, name))
    }
    /// Put a location inside another, or let it out to stand on its own.
    func moveLocation(_ id: String, into parent: String) -> ViewModel? {
        decode(call("movelocation", id, parent))
    }
    func deleteLocation(_ id: String) -> ViewModel? {
        decode(call("deletelocation", id))
    }
    // ---- mood boards ----------------------------------------------------
    //
    // Pictures reach a board through the *same* media commands every other
    // owner uses. There is deliberately no `addboardphoto`: a board is an
    // owner like any other, and a second door onto one act is how two doors
    // drift apart.

    /// **How one kind of words on the document page is set.** The engine folds
    /// it into whatever is already there and hands back the whole view, so the
    /// page redraws with it — and it undoes, saves and syncs like any edit.
    ///
    /// The app never writes the stored string itself; that shape belongs to
    /// `docstyle` in the engine and stays there.
    func setDocStyle(_ name: String, size: Double, face: String, case casing: String,
                     colour: String) -> ViewModel? {
        decode(call("docstyle", name, String(format: "%.2f", size), face, casing, colour))
    }

    /// Put the whole page back to what it has always been.
    func resetDocStyle() -> ViewModel? {
        decode(call("docstyle", "reset"))
    }

    /// Set the whole page from a string this engine wrote — how a default set
    /// on one film reaches another.
    func applyDocStyle(_ said: String) -> ViewModel? {
        decode(call("docstyle", "apply", said))
    }

    /// **The film's own icon and colour**, kept with the film so every device
    /// that has the film has them — his call, 2026-09-11.
    ///
    /// `source` is `console` when it is being mirrored off his Notion row, or
    /// `hand` when he chose it here; the engine leaves a hand-set mark alone
    /// for ever after. An empty path clears it.
    func setMark(path: String, colour: String, source: String) -> ViewModel? {
        decode(call("setmark", path, colour, source))
    }

    /// **The project record's facts, into the film** — the console's door
    /// (one-record plan, 2026-10-05). `title` (the name it is shown by),
    /// `director`, `producer`, `client`, `agency`; only those given are
    /// written, and the film then takes its facts from the record. Touches
    /// nothing but the project record.
    func takeRecordFacts(_ facts: [(String, String)]) -> ViewModel? {
        decode(call(["recordfacts"] + facts.flatMap { [$0.0, $0.1] }))
    }

    /// The film keeps the words it has and owns them again.
    func letGoOfRecordFacts() -> ViewModel? {
        decode(call("recordfacts", "none"))
    }

    /// **The kit off the film's spec sheets** (Ref 1627) — `kit` is the JSON
    /// list of shoots the portal's kit door gives (`KitLink`). Lenses onto
    /// the Lens list, bodies onto the cameras, nothing removed, no undo step.
    /// `nil` back is the engine refusing it; `lastError` says why.
    func takeKit(_ kit: String) -> ViewModel? {
        decode(call("recordkit", kit))
    }

    /// **The project's card, laid over the film** (stage 5 step 4): the
    /// card's facts, mark and kind (from Type) are shown instead of the
    /// film's own. Nothing is written. `nil` takes it off. See `ProjectCards`.
    func setCard(_ json: String?) -> ViewModel? {
        decode(call("card", json ?? "none"))
    }

    /// **The frame Studio draws at** (piece E): one of the project's frames
    /// off its spec sheet, by name. One undo step.
    func pickFrame(_ name: String) -> ViewModel? {
        decode(call("frame", name))
    }

    /// Show the project's other frames as guide lines, or not. One undo step.
    func setFrameGuides(_ on: Bool) -> ViewModel? {
        decode(call("frameguides", on ? "on" : "off"))
    }

    /// The film's Spec Sheet switch: `off`, `ask` or `follow`. Undoable.
    func setKitMode(_ mode: String) -> ViewModel? {
        decode(call("kitmode", mode))
    }

    func addBoard(name: String) -> ViewModel? {
        decode(call("addboard", name))
    }
    func renameBoard(_ id: String, name: String) -> ViewModel? {
        decode(call("renameboard", id, name))
    }
    /// Takes the wall, never the photographs — they are addressed by their
    /// contents and may hang on a shot and a location too.
    func deleteBoard(_ id: String) -> ViewModel? {
        decode(call("deleteboard", id))
    }
    /// A board dragged to a new place in the sidebar — `index` counted with
    /// it lifted out. One undo step.
    func moveBoard(_ id: String, to index: Int) -> ViewModel? {
        decode(call("moveboard", id, String(index)))
    }

    /// Point a scene at a location, or at none (pass an empty id).
    /// One more place a scene is shot at, kept after the ones already on it.
    func addSceneLocation(_ scene: String, _ location: String) -> ViewModel? {
        decode(call("addscenelocation", scene, location))
    }

    /// Take one place off a scene, leaving the others.
    func removeSceneLocation(_ scene: String, _ location: String) -> ViewModel? {
        decode(call("removescenelocation", scene, location))
    }

    /// **Replaces** every place on the scene with this one — or with none.
    func sceneLocation(_ scene: String, _ location: String) -> ViewModel? {
        decode(call("scenelocation", scene, location))
    }

    /// Link one more mood board to a scene, kept after the ones already
    /// there. Ref SL-348.
    func addSceneBoard(_ scene: String, _ board: String) -> ViewModel? {
        decode(call("addsceneboard", scene, board))
    }

    /// Unlink one board from a scene, leaving the others.
    func removeSceneBoard(_ scene: String, _ board: String) -> ViewModel? {
        decode(call("removesceneboard", scene, board))
    }

    func addSequence(title: String) -> ViewModel? {
        decode(call("addsequence", title))
    }

    /// **A shot quotes a stretch of a script** — UTF-16 units into the
    /// section's text (empty section: the film's own). `to` at or below
    /// `from` unties.
    func tie(shot: String, section: String?, from: Int, to: Int) -> ViewModel? {
        decode(call("tieshot", shot, section ?? "", String(from), String(to)))
    }

    /// The highlighter: words the shot already holds are let go, anything
    /// else is added to its stretches.
    /// Several pieces are one gesture — a drag down one column of an AV
    /// script.
    func toggleTie(shot: String, section: String?, pieces: [(Int, Int)]) -> ViewModel? {
        decode(call(["toggletie", shot, section ?? ""] + pieces.flatMap { [String($0.0), String($0.1)] }))
    }

    /// Let go of the shot's stretch under this offset.
    func untie(shot: String, at: Int) -> ViewModel? {
        decode(call("untieat", shot, String(at)))
    }

    /// **The highlighter on a film's screenplay** (Ref 1553): offsets into
    /// the draft's text, as `scriptpages` gives each line. Held words are let
    /// go; anything else is added.
    func playTie(shot: String, revision: String, pieces: [(Int, Int)]) -> ViewModel? {
        decode(call(["playtie", shot, revision] + pieces.flatMap { [String($0.0), String($0.1)] }))
    }

    /// Let go of the shot's screenplay lines under this offset.
    func playUntie(shot: String, revision: String, at: Int) -> ViewModel? {
        decode(call("playuntieat", shot, revision, String(at)))
    }

    /// A section's script as text; ties re-anchor by their words. Answers
    /// how many kept and how many lost.
    struct ScriptEdit: Decodable { var kept: Int; var lost: Int }
    /// `av`: the layout a script with nothing in it takes from a paste.
    func setScript(_ text: String, section: String?, newSection: String? = nil, append: Bool = false,
                   av: Bool? = nil) -> ScriptEdit? {
        var parts = ["setscript", section ?? "", text.replacingOccurrences(of: "\t", with: "\u{1f}")]
        if let newSection, !newSection.isEmpty { parts.append("newsection=\(newSection)") }
        if append { parts.append("append=1") }
        if let av { parts.append("av=\(av ? 1 : 0)") }
        return try? JSONDecoder().decode(ScriptEdit.self, from: call(parts))
    }

    /// A script laid out as Video beside Audio, or as plain text. The words
    /// stay; ties follow them.
    func scriptLayout(section: String?, av: Bool) -> ScriptEdit? {
        try? JSONDecoder().decode(ScriptEdit.self, from: call("scriptlayout", section ?? "", av ? "av" : "plain"))
    }

    /// The section goes; its scenes stay and leave it.
    func deleteSequence(_ id: String) -> ViewModel? {
        decode(call("deletesequence", id))
    }

    /// A scene moved to sit just after another, or first. Order only.
    func moveScene(_ scene: String, after: String?) -> ViewModel? {
        decode(call("sceneafter", scene, after ?? ""))
    }

    func addColumn(label: String, kind: String) -> ViewModel? {
        decode(call("addcolumn", kind, label))
    }

    /// A new name on the same column; the values stay where they are.
    /// Take a column away, and everything written in it. Only one the project
    /// made — the built-in columns are the app's shape.
    func deleteColumn(field: String) -> ViewModel? {
        decode(call("deletecolumn", field))
    }

    func renameColumn(field: String, label: String) -> ViewModel? {
        decode(call("renamecolumn", field, label))
    }

    /// How deep inside `grouped` the app is, so a group inside a group joins
    /// the outer one instead of closing it early.
    private static var groupDepth = 0

    /// **Several writes, one thing to take back.** Everything `body` does is
    /// one step of history: one paste of a block is one ⌘Z, not one per
    /// different value. A group inside a group joins the outer one.
    func grouped(_ label: String, _ body: () -> Void) {
        if Engine.groupDepth == 0 { _ = call("undoopen", label) }
        Engine.groupDepth += 1
        defer {
            Engine.groupDepth -= 1
            if Engine.groupDepth == 0 { _ = call("undoclose") }
        }
        body()
    }

    /// One value onto one column of many shots — one transaction, so a paste
    /// onto a selection is one ⌘Z.
    func setMany(shots: [String], field: String, value: String) -> ViewModel? {
        decode(call("setmany", shots.joined(separator: ","), field, value))
    }

    /// Empties a rectangle of cells — every (column, shots) group — in one
    /// transaction, so Delete over a range is one ⌘Z whatever it crossed.
    func clearCells(_ groups: [(field: String, shots: [String])]) -> ViewModel? {
        let spec = groups
            .map { "\($0.field)=\($0.shots.joined(separator: ","))" }
            .joined(separator: "|")
        return decode(call("clearcells", spec))
    }

    // ---- sharing ------------------------------------------------------

    /// One file with the frames inside it. The date comes from here because the
    /// engine has no calendar.
    func share(path: String, madeOn: String, notes: Bool, struck: Bool, technical: Bool) -> String? {
        struct Reply: Decodable { var path: String }
        let data = call("share", path, madeOn, notes ? "1" : "0", struck ? "1" : "0", technical ? "1" : "0")
        return (try? JSONDecoder().decode(Reply.self, from: data))?.path
    }

    /// His working file, exactly: Master Shot List, Group by Day, Group by
    /// Sequence, Ranges — built off whatever the list is currently narrowed
    /// to, the same way `share` and `printPage` already work.
    func exportExcel(path: String, scope: ExportScope = .onScreen,
                     frames: FrameStyle = .forGoogleSheets) -> String? {
        struct Reply: Decodable { var path: String }
        var options = scope.options
        // **Laid out for Sheets, the frame goes in as an address rather than a
        // picture pasted on top.** Same `.xlsx` either way — that is the whole
        // difference between a frame his sorting leaves behind and one that
        // travels with its row: a formula is the cell's contents, a drawing is
        // a thing floating over the grid.
        //
        // No relay behind this film means no address to give, and then it is
        // carried in the file whatever was asked for — a formula pointing at
        // nothing would draw an empty column and look like a bug.
        if frames == .forGoogleSheets, let pictures = Relay.picturesAt(folder) {
            options.append("pictures=\(pictures)")
        }
        let data = callRaw((["xlsx", path] + options).joined(separator: "\t"))
        return (try? JSONDecoder().decode(Reply.self, from: data))?.path
    }

    /// What undo would do next, and whether there is anything to put back.
    func history() -> History {
        (try? JSONDecoder().decode(History.self, from: call("history")))
            ?? History(canUndo: false, undoLabel: "", canRedo: false, redoLabel: "", depth: 0)
    }

    func redo() -> (outcome: UndoOutcome, view: ViewModel?) {
        struct Reply: Decodable { var undo: UndoOutcome; var view: ViewModel }
        guard let r = try? JSONDecoder().decode(Reply.self, from: call("redo")) else {
            return (UndoOutcome(did: false, label: "", restored: 0, skipped: 0, complete: true), nil)
        }
        return (r.undo, r.view)
    }

    /// Undo is the engine's to define. This asks, and reports what was held back.
    func undo() -> (outcome: UndoOutcome, view: ViewModel?) {
        struct Reply: Decodable { var undo: UndoOutcome; var view: ViewModel }
        guard let r = try? JSONDecoder().decode(Reply.self, from: call("undo")) else {
            return (UndoOutcome(did: false, label: "", restored: 0, skipped: 0, complete: true), nil)
        }
        return (r.undo, r.view)
    }

    private func decodeBoard(_ data: Data) -> BoardModel? {
        guard !data.isEmpty else { return nil }
        do {
            return try JSONDecoder().decode(BoardModel.self, from: data)
        } catch {
            if let text = String(data: data, encoding: .utf8) {
                FileHandle.standardError.write(Data("engine: \(text)\n".utf8))
            }
            return nil
        }
    }

    func decode(_ data: Data) -> ViewModel? {
        guard !data.isEmpty else { return nil }
        do {
            return try JSONDecoder().decode(ViewModel.self, from: data)
        } catch {
            // **Say why, not only what.** A reply that decodes to nothing
            // opens the film empty, and the reply alone does not say which
            // field the app could not read (2026-10-15: every film opened
            // with no scenes and nothing said which key was missing).
            FileHandle.standardError.write(Data("view did not decode: \(error)\n".utf8))
            // an error reply is JSON too, and worth seeing rather than swallowing
            if let text = String(data: data, encoding: .utf8) {
                FileHandle.standardError.write(Data("engine: \(text)\n".utf8))
            }
            return nil
        }
    }
}

// ---------------------------------------------------------------- the view

// MARK: - the script

/// What `readscript` says about a PDF. **A report, not a change.**
struct ScriptReading: Decodable {
    var pages: Int
    var pagesLaidOut: Int
    var duplicatesIgnored: Int
    /// The screenplay as this reading marked it up — what `takescript` is given,
    /// so the import and the report are two views of one reading.
    var script: String
    var scenes: Scenes
    var characters: Characters

    struct Scenes: Decodable {
        var detected: Int
        var matched: Int
        var new: Int
        var omitted: Int
        var rows: [Row]
        /// The project's own scenes this draft no longer mentions, with the
        /// work that would go with them.
        var goneFromTheDraft: [Gone]
        /// **Scenes that look like they moved to a new number** — Ref 241.
        /// Found for every scene the draft brings, and acted on for none of
        /// them until one is ticked.
        var movedNumber: [Moved] = []
    }

    /// One scene the draft appears to have renumbered.
    struct Moved: Decodable, Identifiable {
        /// Which scene in the draft it is, so ticking it can name it the same
        /// way the scene list does.
        var index: Int
        var from: String
        var to: String
        var heading: String
        /// What would come with it — the number that decides this.
        var shots: Int
        var id: Int { index }
    }

    struct Row: Decodable, Identifiable {
        var label: String
        var heading: String
        var location: String
        var timeOfDay: String
        var intExt: String
        var number: String?
        /// `scene`, or `room` for a bare room name found under one.
        var status: String
        var under: String?
        /// Rooms arrive unticked — Cadrage's unticked rows, and the same
        /// reasoning: they failed the rules the person set.
        var accepted: Bool
        /// Whether the project already has a scene with this number.
        var matched: Bool
        var length: String?
        var eighths: Int
        var startsOnPage: Int
        var id: String { label + "/" + heading }
        var isRoom: Bool { status == "room" }
    }

    struct Gone: Decodable, Identifiable {
        var number: String
        var heading: String
        var shots: Int
        var id: String { number }
    }

    struct Characters: Decodable {
        var detected: Int
        var matched: Int
        var new: Int
        var rows: [Person]
    }

    struct Person: Decodable, Identifiable {
        var name: String
        var display: String
        var speeches: Int
        var scenes: [String]
        var aliases: [String]
        var id: String { name }
    }
}

/// What taking a draft in would do, in the plan's own words.
struct ScriptPlan: Decodable {
    /// **Printed verbatim.** Composing our own sentences here is how a confirm
    /// screen comes to disagree with what actually happens.
    var sentences: [String]
    var linked: Int
    var created: Int
    var archived: Int
    /// **`castAdded`, not `cast`.** The engine's own key, and getting it wrong
    /// meant the whole plan failed to decode and the confirm screen came up
    /// empty — a silence, not an error.
    var castAdded: Int
    /// Scenes the draft still has that this taking will not touch, with the
    /// work already on them.
    var leftAlone: [Untouched] = []

    struct Untouched: Decodable, Identifiable {
        var number: String
        var shots: Int
        var id: String { number }
    }
}

/// A draft the project keeps.
struct Revision: Decodable, Identifiable {
    var id: String
    var name: String
    var filename: String
    var importedAt: String
    var hash: String
    var latest: Bool
}

/// The script laid out as real pages — 55 lines of 12pt Courier, the standard,
/// because a page count only means anything if everybody's page is the same.
struct ScriptPages: Decodable {
    var revision: String
    var name: String
    var pages: Int
    var linesPerPage: Int
    /// How many characters across the text block is.
    var measure: Int
    var scenes: [Extent]
    var pageList: [Page]

    struct Extent: Decodable, Identifiable {
        var label: String
        var heading: String
        /// "2 3/8", the unit the trade uses.
        var length: String
        var eighths: Int
        var startsOnPage: Int
        var id: String { label }
    }

    struct Page: Decodable, Identifiable {
        var number: Int
        var lines: [Line]
        var id: Int { number }
    }

    struct Line: Decodable {
        /// Which line down the page, so nothing is measured in a view.
        var row: Int
        /// How many characters in.
        var indent: Int
        var kind: String
        var text: String
        /// The paginator's words rather than the writer's — `(MORE)` and
        /// `(CONT'D)` — so a search never finds them.
        var added: Bool
        var scene: String?
        /// Where the line sits in the draft's text — absent on the
        /// paginator's own words — and the shots whose lines cover it
        /// (Ref 1553).
        var from: Int?
        var to: Int?
        var shots: [String]?
    }

    /// **Which shots hold which lines in this draft** (Ref 1553), and the
    /// words a shot holds that this draft no longer has. Optional so an
    /// older engine's reply still reads.
    var ties: [Tie]?
    var lost: [Lost]?

    struct Tie: Decodable {
        var shot: String
        var number: String
        var spans: [[Int]]
    }

    struct Lost: Decodable {
        var shot: String
        var number: String
        var words: [String]
    }

    /// The pages, 1-indexed and inclusive, a scene occupies in the real PDF —
    /// from its own heading to the page before the next scene's. What the
    /// scene PDF export slices out of the file he actually imported, rather
    /// than redrawing the engine's own re-flowed text.
    func pageRange(for sceneNumber: String) -> ClosedRange<Int>? {
        let ordered = scenes.sorted { $0.startsOnPage < $1.startsOnPage }
        guard let index = ordered.firstIndex(where: { $0.label == sceneNumber }) else { return nil }
        let start = ordered[index].startsOnPage
        let end = index + 1 < ordered.count ? ordered[index + 1].startsOnPage - 1 : pages
        return start...max(start, end)
    }
}

/// The four dials a script is read with, kept on the project.
struct Detection: Decodable {
    var mustHaveANumber: Bool
    var ignoreDuplicateNumbers: Bool
    var findSubSlugs: Bool
    var mustContain: [String]
    var neverContains: [String]

    /// The engine's own settings string: the four dials in the order they
    /// appear on the sheet.
    var settings: String {
        "number=\(mustHaveANumber ? 1 : 0),duplicates=\(ignoreDuplicateNumbers ? 1 : 0)"
        + ",rooms=\(findSubSlugs ? 1 : 0)"
        + ",contains=\(mustContain.joined(separator: "|"))"
        + ",forbid=\(neverContains.joined(separator: "|"))"
    }

    /// `Detection::printed()` in the engine — the rules for a script that has
    /// been through a printer, which is what a PDF is. Only a fallback: the
    /// sheet asks the project what its own dials are.
    static let standard = Detection(
        mustHaveANumber: true, ignoreDuplicateNumbers: true, findSubSlugs: true,
        mustContain: [], neverContains: ["CONTINUED:"])
}

struct History: Decodable {
    var canUndo: Bool
    var undoLabel: String
    var canRedo: Bool
    var redoLabel: String
    /// How many steps are behind you. The engine keeps the stack; it hands out
    /// only the top label, so this is as much as can honestly be shown.
    var depth: Int
}

struct UndoOutcome: Decodable {
    var did: Bool
    var label: String
    var restored: Int?
    var skipped: Int?
    var complete: Bool?
}

struct ViewModel: Decodable {
    var project: Project
    var filter: Filter
    var columns: [Column]
    /// **What every field is called** — Ref 249. The engine's list, so the Mac
    /// and the phone cannot disagree about whether a column is called "Camera
    /// Gear" or "Camera". Covers fields that are named without being columns:
    /// a scene's POV and priority keep lists and the settings screen names
    /// them.
    var fieldLabels: [String: String] = [:]
    var units: [Unit]
    var sequences: [Sequence]
    /// The scripts as text — the film's own (empty section) and one per
    /// section that has one. Empty on a film.
    var scripts: [Script]
    /// Every real place the crew goes. Kept apart from a scene's `location`,
    /// which is the slugline's word and belongs to the script.
    var locations: [Location] = []
    /// **Mood boards** — a name and a wall of pictures, nothing else.
    /// Defaulted to empty so a project written by an older Shotlister, which
    /// has no `boards` key at all, still decodes rather than coming up blank.
    var boards: [MoodBoard] = []
    var days: [Day]
    var scenes: [Scene]
    var groupBy: String
    var groups: [Group]
    /// **The project's shoots** (stage 5 step 4, piece D), off the card,
    /// first to last. Empty with no card shoots; the picker shows with two or
    /// more. `shootOn` is the one the lists are narrowed to, "" for All Shoots.
    var shoots: [Shoot] = []
    var shootOn: String = ""
    /// **Edit references** (the Edit Reference mod): absent when the film
    /// has none. Drawn only while the project has the mod on.
    var editRefs: [EditRef]?

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
            var moving: Bool { kind == "video" || kind == "gif" }
        }
        var id: String
        var name: String
        var link: String
        var length: Double
        var shots: [Shot]
        var media: [Clip]
        /// The clip, when it has one; else its stills, in order.
        var clip: Clip? { media.first { $0.kind == "video" } }
        var stills: [Clip] { media.filter { $0.kind == "image" || $0.kind == "gif" } }
        /// Where each shot ends: the next one's start, the last at the length.
        func end(of at: Int) -> Double {
            at + 1 < shots.count ? shots[at + 1].start : max(length, shots.last?.start ?? 0)
        }
        /// `34A–34D`.
        var range: String {
            guard let a = shots.first?.number, let b = shots.last?.number else { return "" }
            return a == b ? a : "\(a)–\(b)"
        }
    }

    struct Shoot: Decodable, Identifiable, Hashable {
        var id: String
        var label: String
        var kind: String = ""
        var start: String = ""
        var end: String = ""
        var state: String = ""
        var scenes: Int = 0
        var days: Int = 0
        var wrapped: Bool { state.caseInsensitiveCompare("Wrapped") == .orderedSame }
    }

    /// Every row on screen, whatever it is grouped under — what ⌘V and the
    /// document page walk.
    var allRows: [Row] { groups.flatMap(\.rows) }

    struct Project: Decodable {
        var id: String
        var title: String
        var director: String
        var producer: String
        /// **What sort of film this is** — `film` or `commercial`. The
        /// engine's `kind` module owns what it means; here it decides what
        /// Add Scene asks for first, whether the slugline leads or folds
        /// away, and whether a sequence is called a Section. Defaulted so a
        /// project written by an older build still decodes.
        var kind: String = "film"
        var isCommercial: Bool { kind == "commercial" }
        /// Who the commercial is for, and who brought it. Shown where a film
        /// shows nothing more than Director and Producer.
        var client: String = ""
        var agency: String = ""
        /// **Where the film's facts come from** — `console` when the project
        /// record owns its shown name, director, producer, client and agency
        /// (one-record plan, 2026-10-05), empty when the film keeps its own.
        /// The engine refuses a `set` onto them while it says `console`.
        var factsSource: String = ""
        var factsFromRecord: Bool { factsSource == "console" }
        /// **A project card is laid over the film** (`ProjectCards`): its
        /// facts, mark and kind are the card's, not the film's.
        var card: Bool = false
        /// **The kit** (Ref 1627): each shoot's spec sheet as the lenses and
        /// cameras its shots pick from, as last taken from the portal. Nil or
        /// empty: the film has none. The sheets themselves are `KitLink`'s.
        var kit: [KitShoot]?
        /// **The Spec Sheet switch** (2026-10-13): `off` (nothing flows),
        /// `ask` (say what changed, take it on a click) or `follow` (take it on
        /// open and every five minutes). Off on every film until he says.
        var kitMode: String = "off"
        /// The name to draw — the record's when it has said one, the film's
        /// own title otherwise. The engine decides; see `shownTitle`.
        var displayTitle: String = ""
        /// **The film's name, as shown.** `title` stays the film's own — the
        /// package and the console's film list know it by that — and is what
        /// matching and renaming read; everything drawn reads this.
        var shownTitle: String { displayTitle.isEmpty ? title : displayTitle }
        /// What this film calls a sequence — *Section* on a commercial. The
        /// engine says the same in `fieldLabels`; this is for the strings the
        /// app writes itself.
        var sequenceWord: String { isCommercial ? "Section" : "Sequence" }
        var sequencesWord: String { isCommercial ? "Sections" : "Sequences" }
        /// The priority every shot has unless it says otherwise. Only shots that
        /// differ from it are marked.
        var defaultPriority: String
        /// **The ratio every frame is drawn at.** The frame Studio picked off
        /// the spec sheet (`frames`) while the card brings them; the film's own
        /// otherwise.
        var ratio: Double
        /// **The project's frames, off its spec sheet** (stage 5 step 4,
        /// piece E): nil while the card brings none, and then the ratio is the
        /// film's own, picked from `Ratios` as before.
        var frames: [ProjectFrame]?
        /// The frame Studio draws at, by name ("" with no frames).
        var frame: String = ""
        /// Whether the other frames show as guide lines.
        var frameGuides: Bool = false
        /// Cameras' sensors are the spec sheet's: shown, never typed.
        var sensorsFromSheet: Bool = false
        var readOnly: Bool
        var unsaved: Int
        /// **The film's own icon**, as the outline to draw it with. Empty for a
        /// film that has none. Kept on the film rather than on this Mac, so a
        /// Mac that has the film has the icon — his call, 2026-09-11.
        var markPath: String = ""
        /// The colour that goes with it, `#RRGGBB`. The accent the whole app
        /// wears while that film is open.
        var markColour: String = ""
        /// `console` — mirrored off his Notion row and refreshed when it
        /// changes; `hand` — his own choice, which nothing automatic touches;
        /// empty — nobody has said. Read through `Marks`, not compared here.
        var markSource: String = ""
        /// The pair, when the film has both. Nothing when it has neither or
        /// only one — half a mark cannot be drawn.
        var mark: Console.Mark? {
            guard !markPath.isEmpty, !markColour.isEmpty else { return nil }
            return Console.Mark(path: markPath, colour: markColour)
        }
        /// **Which of his Projects Console projects this film is.** Empty when
        /// it is not linked to one, which is a perfectly ordinary state — a
        /// quick job need never appear in the console at all.
        var consolePage: String = ""
        var consoleName: String = ""
        /// The Google Drive folder as a web address, taken from the console.
        var driveUrl: String = ""
        /// The Google Drive folder as a path on **this Mac** — what the sync
        /// actually watches. Guessed from `driveUrl` where that can be done,
        /// chosen by hand where it cannot.
        var driveFolder: String = ""
        /// **The workbook this film keeps up to date**, if he has asked for
        /// one — an absolute path, empty when nothing is linked. Set and
        /// cleared from Project Settings.
        var excelPath: String = ""
        /// Whether that workbook rewrites itself after a change, apart from
        /// whether one is linked at all — `""` or `"1"`. Read through
        /// `Exporting.autoUpdateEnabled`, which decides what an empty value
        /// means; nothing else should compare this string directly.
        var excelAuto: String = ""
        /// Which program the workbook is laid out for — `""`, `"cells"` or
        /// `"file"`. It is the same `.xlsx` either way; only the frames differ.
        /// Read through `Exporting.frameStyle`, which decides what an empty
        /// value means; nothing else should compare this string directly.
        var excelFrames: String = ""
        /// **How the page is set** — one entry per kind of words on it, with
        /// the defaults already applied by the engine.
        ///
        /// Read, never computed. `docstyle::standard` in the engine is the
        /// only place that knows what "standard" means, which is the whole
        /// reason these numbers moved out of `Page` and over there.
        var docStyle: [TextClass] = []
        /// **The same page in the engine's own shorthand**, for handing to
        /// another film as a default. The app stores it and never reads inside
        /// it — empty means "this film has never been set".
        var docStyleSaid: String = ""
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

    /// One kind of words on the document page, and how it is drawn.
    struct TextClass: Decodable, Identifiable, Hashable {
        /// The engine's own name for it — stable, and what a command names.
        var `class`: String
        /// What he sees. The engine writes it, so the app and the printed
        /// page cannot come to call the same thing two names.
        var label: String
        var size: Double
        /// `serif`, `sans` or `mono`.
        var face: String
        /// `as`, `upper` or `lower`.
        var `case`: String
        /// The ink, as six hex digits — `17171a`. His ask, 2026-09-03.
        var colour: String = "17171a"
        var id: String { self.class }
    }
    struct Filter: Decodable {
        var text: String
        var hideStruck: Bool
        /// How many scenes went out of sight, so a filter never silently
        /// shortens the film.
        var hiddenScenes: Int
        var shown: Int
        /// Whether anything at all is narrowing the list — a search, a facet, a
        /// day, or cut shots being hidden.
        var narrowed: Bool
        var sortColumn: String
        var sortDescending: Bool
        var isOn: Bool { narrowed }
    }
    struct Column: Decodable, Identifiable {
        var name: String
        var visible: Bool
        /// Shown by the project's own list, apart from Lens Stack (which takes
        /// Modifiers and Filters out of the table). Nil from an older engine.
        var own: Bool? = nil
        /// Whether this column's list is closed — see `engine/src/vocab.rs`.
        var locked: Bool = false
        /// Present only on a column the project made for itself — the
        /// fourteen built-ins carry their names in the app.
        var label: String?
        var kind: String?
        var id: String { name }
    }
    /// One shoot's spec sheet as picks — the engine's `kit` (Ref 1627).
    struct KitShoot: Decodable, Equatable {
        var name: String
        var start: String
        var end: String
        var sheet: String
        var lead: Bool
        var cameras: [KitCamera]
        var lenses: [String]
        /// Extenders and the like the shoot carries; nil from a kit before them.
        var modifiers: [String]? = nil
        /// Filters the shoot carries.
        var filters: [String]? = nil
    }
    struct KitCamera: Decodable, Equatable {
        var label: String
        var body: String
    }
    /// A shot's lens or camera body missing from its shoot's sheet; `shoot`
    /// indexes `project.kit`.
    struct OffKit: Decodable, Equatable {
        var shoot: Int
        var lens: String?
        var camera: String?
        var body: String?
        /// The shot's modifiers and filters that sheet does not carry.
        var modifiers: [String]?
        var filters: [String]?
    }

    struct Unit: Decodable, Identifiable, Equatable {
        var id: String
        var label: String
        var body: String
        var colour: String
        /// The sensor he typed for it (`Doc::set_unit_sensor`), when set.
        var sensor_name: String?
        var sensor_w: Double?
        var sensor_h: Double?
        /// The sensor is the spec sheet's sensor mode (piece E): shown, never typed.
        var sensor_sheet: Bool?

        /// `Alexa Mini LF Open Gate · 36.70 × 25.54 mm`, or nil.
        var sensorText: String? {
            guard let w = sensor_w, w > 0 else { return nil }
            let size = (sensor_h ?? 0) > 0 ? String(format: "%.2f × %.2f mm", w, sensor_h!) : String(format: "%.2f mm", w)
            let name = sensor_name ?? ""
            return name.isEmpty ? size : "\(name) · \(size)"
        }
    }
    struct Sequence: Decodable, Identifiable {
        var id: String
        var title: String
        var colour: String
    }
    /// One script: which section it belongs to (empty for the film's own)
    /// and its text.
    struct Script: Decodable, Identifiable {
        var section: String
        var text: String
        /// Video beside Audio (`AVScript`), or plain text.
        var av: Bool?
        var id: String { section }
        var isAV: Bool { av ?? false }
    }
    /// A place the crew actually goes — Ref 57. The phone captures these on a
    /// scout; the Mac draws them.
    struct Location: Decodable, Identifiable {
        var id: String
        var name: String
        var address: String
        /// Text rather than numbers, because the engine holds every field as
        /// text and an unset pin must be *absent*, not `0, 0` — which is a real
        /// place in the Atlantic and would draw a map of the sea.
        var latitude: String
        var longitude: String
        var notes: String
        /// Which machine wrote it, so a location can say where it came from.
        var capturedBy: String
        var createdAt: String
        /// The folder under `<Project>.shotlist/locations/` this came from,
        /// when the phone brought it home. Empty for one made on the Mac.
        var folder: String
        /// Which folder in his Google Drive holds this location's photographs
        /// — the Drive bridge's pairing, written down rather than guessed from
        /// the name so that renaming a location cannot orphan its pictures.
        var driveFolder: String = ""
        /// **Whether this place's photographs travel to Drive** — Ref 229.
        /// `"1"` on, `"0"` off, and **empty means nobody has been asked**,
        /// which the bridge reads as on: a film opting in is already an
        /// explicit choice, and the switch is there to exclude a place.
        var syncWithDrive: String = ""
        /// What the switch should show. Empty reads as on — see above.
        var syncsWithDrive: Bool { syncWithDrive != "0" }
        /// The scenes shot here, by id — walkable, which a count is not.
        var scenes: [String]
        /// Narrowed to a shoot: false for a place with scenes but none in it.
        var inShoot: Bool = true
        /// The photographs, the same objects a scene's attachments are.
        var media: [Attachment]
        /// The scanned rooms, as the engine holds them — each half a stored
        /// file under its hash, which is how a scan made on the phone reaches
        /// this Mac over the relay (2026-09-15; the folder under `locations/`
        /// never travels).
        var scans: [Room] = []

        struct Room: Decodable, Hashable {
            struct Half: Decodable, Hashable {
                var ref: String = ""
                var hash: String = ""
                var filename: String = ""
                var bytes: Int = 0
            }
            var name: String
            var shape: Half?
            var plan: Half?
            /// The name its files were made with, whatever the room is
            /// called now, and the day it was scanned (`Aug 27, 2026 at
            /// 1:18 PM`).
            var file: String?
            var taken: String?
        }

        // ---- a room inside a house — Ref 269 ------------------------------
        //
        // One house, one address, and inside it a kitchen, a bedroom and a
        // garage, each scanned separately and each with its own photographs.
        // The `effective` fields are what to *show*; the plain ones above stay
        // the record's own, because the editor writes those back and an editor
        // prefilled with the house's address would stamp a borrowed address
        // onto every room the first time anybody clicked in the field.

        /// The house this is a room in. Empty when it stands on its own.
        var parent: String = ""
        /// `Hillcrest House — Kitchen`, for anywhere away from this screen.
        var fullName: String = ""
        /// The rooms inside this one, by id. Empty for a room.
        var areas: [String] = []
        /// How many scenes hang on this **including its rooms** — the number a
        /// house shows in the list.
        var scenesInside: Int = 0
        var effectiveAddress: String = ""
        var effectiveLatitude: String = ""
        var effectiveLongitude: String = ""
        var effectiveNotes: String = ""

        /// Whether this is a room in something.
        var isArea: Bool { !parent.isEmpty }
        /// Whether what is being shown was borrowed from the house.
        var addressIsInherited: Bool {
            address.trimmingCharacters(in: .whitespaces).isEmpty
                && !effectiveAddress.isEmpty
        }
        var notesAreInherited: Bool {
            notes.trimmingCharacters(in: .whitespaces).isEmpty
                && !effectiveNotes.isEmpty
        }

        /// The pin to draw — the room's own, or the house's.
        var pin: CLLocationCoordinate2D? {
            guard let lat = Double(effectiveLatitude), let lon = Double(effectiveLongitude),
                  lat != 0 || lon != 0 else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        /// The pin this record itself holds — what the editor moves. A room
        /// dragged on the map gets its own, and stops borrowing.
        var ownPin: CLLocationCoordinate2D? {
            guard let lat = Double(latitude), let lon = Double(longitude),
                  lat != 0 || lon != 0 else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        /// Only the pictures. A PDF pinned to a location is an attachment, and
        /// drawing it in the photo wall would draw a grey rectangle.
        var photos: [Attachment] { media.filter { $0.kind != "other" } }
        var papers: [Attachment] { media.filter { $0.kind == "other" } }
    }
    struct Day: Decodable, Identifiable {
        var id: String
        var label: String
        var date: String
        var count: Int
        /// Every shot on it is in an archived scene: shot out and put away.
        var wrapped: Bool?
        /// The shoot it belongs to (piece D), "" with no card shoots.
        var shoot: String = ""
    }
    struct Scene: Decodable, Identifiable {
        var id: String
        /// The shoot it belongs to (piece D), "" with no card shoots;
        /// `shootOwn` when the scene names it itself.
        var shoot: String = ""
        var shootOwn: Bool = false
        var number: String
        /// Set aside, kept, and always reachable to bring back.
        var archived: Bool
        var heading: String
        /// **A commercial scene's own three facts.** `title` is what it is
        /// called; `slug` the slugline underneath, empty when nobody gave it
        /// one; `audio` the right-hand column of an AV script, beside
        /// `script` as the left. Defaulted so an older view still decodes.
        var title: String = ""
        var slug: String = ""
        var audio: String = ""
        var intExt: String
        var location: String
        var timeOfDay: String
        var script: String
        /// The scene's own words, kept apart from its shots: a one-line summary
        /// of the action, the notes, where it is actually being filmed, its
        /// priority, and whose point of view it is.
        var description: String
        var notes: String
        /// The same words with their emphasis, for the Notes tab alone.
        var notesRich: String?
        /// What is pinned to the scene — plans, permits, references.
        var attachments: [Attachment]
        var shootingLocation: String
        /// The scene's own tags — the same project-wide list the shots use.
        var tags: String
        var priority: String
        var pov: String
        /// Which shoot day, or days, this scene sits on.
        var day: String
        var count: Int
        var split: Bool
        var sequence: String?
        /// Pieces on all its diagrams — whether its Diagram is started.
        var diagram: Int?
        /// Its diagrams, when it has more than one (`DiagramScenes`).
        var diagrams: [SceneDiagramItem]?
        /// Left out of the Diagram's scene list by hand (`DiagramScenes`);
        /// absent when not.
        var diagramHidden: Bool?
        /// The **location record** this scene is shot at, if one is chosen.
        /// Different from `location` above, which is the script's own word and
        /// is never ours to edit.
        var locationId: String = ""
        /// **Every location this scene is shot at**, comma-separated, when it
        /// moves between more than one. `locationId` above is the first of
        /// them. Empty on a project written before 2026-08-22, and read
        /// through `locations` below rather than directly.
        var locationIds: String = ""
        /// The places, as a list, always at least as long as `locationId` is
        /// non-empty.
        var locations: [String] {
            let listed = locationIds.split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return listed.isEmpty ? (locationId.isEmpty ? [] : [locationId]) : listed
        }
        /// Every mood board this scene links to — his call, 2026-08-23
        /// (Ref SL-348). Empty on a project written before the link existed.
        var boardIds: String = ""
        var boards: [String] {
            boardIds.split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }
    /// A wall of references — *Night Exteriors*, *Anya*, *The Diner*.
    ///
    /// Its pictures are the very same `Attachment` a scene's references and a
    /// location's photographs are, because the engine never cared who owned a
    /// picture. That is why a board needed no media work of its own.
    struct MoodBoard: Decodable, Identifiable {
        var id: String
        var name: String
        var media: [Attachment]
        /// How the wall fills each tile: `original`, `square` or `project`.
        /// Always present from the engine, `original` when never set.
        var ratioMode: String = "original"
        /// The film's one tag list, as this board uses it — comma-joined, the
        /// same shape a scene's tags arrive in.
        var tags: String = ""
        /// The scenes hanging this board. The link is the same one a scene
        /// makes; this is it read from the board's side.
        var scenes: [String] = []
        /// **Whether this board's pictures travel to Drive** — Ref 229's
        /// second half. **Off until he switches it on**, the opposite of a
        /// location: no board has ever been carried, so there is nothing that
        /// reading absent as no would silently stop.
        var syncWithDrive: String = ""
        /// Which folder under the film's `1-creative/reference` holds them.
        var driveFolder: String = ""
        var syncsWithDrive: Bool { syncWithDrive == "1" }
        var tagList: [String] {
            tags.split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }
    struct Attachment: Decodable, Identifiable {
        var ref: String
        var hash: String
        var filename: String
        /// image · gif · video · other, as the engine judged it.
        var kind: String
        /// **The picture's own size, so a wall never has to open it to lay it
        /// out.** Nought for anything with no dimensions — a PDF — and nought
        /// from an older engine, so ask `shape` rather than these directly.
        var width: Int = 0
        var height: Int = 0
        /// What was said under this use of the picture.
        var caption: String = ""
        /// **The remembered in/out range for a clip, in seconds.** Both nil
        /// means the whole thing — never trimmed, or reset back to it. The
        /// file itself is never touched; this is only where playback starts
        /// and stops.
        var trimStart: Double?
        var trimEnd: Double?
        /// **Which part of this picture to keep where it is drawn cropped**,
        /// and how far in. Absent is the middle at full width, which is what
        /// every tile in the app drew before this existed. Ref: his ask,
        /// 2026-08-30 — the engine holds the bounds, this only reads them.
        var cropX: Double?
        var cropY: Double?
        var cropScale: Double?
        var framing: ViewModel.Framing {
            ViewModel.Framing(x: cropX ?? 0.5, y: cropY ?? 0.5, scale: cropScale ?? 1)
        }
        /// **The storyboard arrows drawn over this use of the picture**, as
        /// the one line the engine stores. Absent on a picture nobody has
        /// marked, which is every picture until somebody does.
        var arrows: String?
        var marks: [ViewModel.Arrow] { ViewModel.Arrow.parse(arrows) }
        /// The shape of the picture, or nothing when it is not known. A wall
        /// laying out in each picture's own shape asks this; before it existed
        /// the only answer was to decode every picture during layout.
        var shape: CGFloat? {
            guard width > 0, height > 0 else { return nil }
            return CGFloat(width) / CGFloat(height)
        }
        var id: String { ref }
        var ext: String {
            let parts = filename.split(separator: ".")
            return parts.count > 1 ? String(parts.last!) : "png"
        }
        /// The same three questions the other media structs answer.
        var movie: Bool { Ingest.isMovie(ext, kind: kind) }
        var gif: Bool { Ingest.isGif(ext, kind: kind) }
        var moving: Bool { Ingest.isMoving(ext, kind: kind) }
    }
    struct Group: Decodable, Identifiable {
        var key: String?
        var label: String
        var count: Int
        var heading: String?
        /// The band under a commercial's title — see `Scene.slug` and the AV
        /// pair. A film's band never draws these.
        var slug: String?
        var video: String?
        var audio: String?
        var colour: String?
        /// What the header shows as pills: the sequence this scene belongs to,
        /// the day it is on, its point of view, its priority.
        var sequenceTitle: String?
        var day: String?
        var pov: String?
        var priority: String?
        var intExt: String?
        var location: String?
        var timeOfDay: String?
        var rows: [Row]
        var id: String { key ?? label }
    }
    struct Frame: Decodable, Equatable {
        var hash: String
        var filename: String
        /// **What the engine says this is** — image · gif · video · other.
        /// Nil only where nothing said, which is a bare hash-and-filename
        /// construction; `movie`/`gif`/`moving` fall back to the name there.
        var kind: String?
        /// Ask these rather than reading `ext` — see `Ingest.isMovie(_:kind:)`.
        var movie: Bool { Ingest.isMovie(ext, kind: kind) }
        var gif: Bool { Ingest.isGif(ext, kind: kind) }
        var moving: Bool { Ingest.isMoving(ext, kind: kind) }

        /// **The trim, carried down to the small drawings.** A clip trimmed in
        /// the viewer has to play the same range in the table, the storyboard
        /// and the schedule — it went on playing whole everywhere it was
        /// small until this was handed over (2026-08-28).
        var trimStart: Double?
        var trimEnd: Double?
        /// **Which part of this picture to keep where it is drawn cropped**,
        /// and how far in. Absent is the middle at full width, which is what
        /// every tile in the app drew before this existed. Ref: his ask,
        /// 2026-08-30 — the engine holds the bounds, this only reads them.
        var cropX: Double?
        var cropY: Double?
        var cropScale: Double?
        var framing: ViewModel.Framing {
            ViewModel.Framing(x: cropX ?? 0.5, y: cropY ?? 0.5, scale: cropScale ?? 1)
        }
        /// **The storyboard arrows drawn over this use of the picture**, as
        /// the one line the engine stores. Absent on a picture nobody has
        /// marked, which is every picture until somebody does.
        var arrows: String?
        var marks: [ViewModel.Arrow] { ViewModel.Arrow.parse(arrows) }
        /// Proxies are stored under the extension they were written with.
        var ext: String {
            let parts = filename.split(separator: ".")
            return parts.count > 1 ? String(parts.last!) : "png"
        }
    }
    struct Row: Decodable, Identifiable, Equatable {
        /// **What the table identifies this row by.** The placement id alone
        /// is not enough: it survives a move between scenes, so a row carrying
        /// only it keeps its identity while moving to a different `ForEach`,
        /// and SwiftUI hands back the view it already built — frozen, with the
        /// old scene's letter still on it. The scene has to be part of who the
        /// row is.
        var tag: String { (sceneId ?? "") + "/" + id }

        var placement: String
        var shot: String
        var sceneId: String?
        /// The shot's own colour, when it has one — identity, carried by the
        /// shot rather than by where it sits.
        var colour: String?
        var number: String
        /// A short name for the shot, separate from the sentence describing it —
        /// "ChatGPT Screen" against "ECU insert on the ChatGPT screen". Optional,
        /// and its column is off until somebody turns it on.
        var title: String
        var description: String
        /// The same words with the document page's emphasis on them, if any.
        /// Nothing else in the app reads this.
        var descriptionRich: String
        /// **The stretch of the script this shot quotes** (2026-09-19):
        /// which script, the UTF-16 range, and the words — read off the
        /// script by the engine every time; never written here.
        var scriptOf: String?
        var scriptFrom: Int?
        var scriptTo: Int?
        /// Every stretch, the first one too — a shot can quote several
        /// lines far apart (2026-10-05). `[[from, to], …]`.
        var scriptSpans: [[Int]]?
        var script: String
        /// The lines of a film's screenplay it holds, as words (Ref 1553).
        var playLines: [String]?
        var size: String
        var angle: [String]
        var movement: String
        var lens: String
        /// Where a zoom is set, in mm — only while the Lens is a zoom.
        var focal: Double?
        /// Extenders and the like on the lens for this shot, and its filters
        /// (his ask, 2026-10-14). Optional only so a view without them reads.
        var modifiers: [String]?
        var lens_filters: [String]?
        var modifierList: [String] { modifiers ?? [] }
        var lensFilters: [String] { lens_filters ?? [] }
        var support: String
        var notes: String
        var tags: [String]
        /// The project's own columns, keyed by field slug — every kind as a
        /// list of strings (a text or single value is a list of one, a check
        /// is present-or-absent), so one shape decodes every shape.
        var custom: [String: [String]]?
        var struck: Bool
        /// **Whether other shots stand in for this one.** A film breaks a scene
        /// up and comes back to the same setup; rather than describing it twice
        /// and letting the two drift, one shot is the master.
        var isMaster: Bool = false
        /// The number of the master this shot stands in for — `34A` — or nil
        /// when it stands for itself. What it *shows* already comes from the
        /// master: the engine resolves that, so nothing here has to.
        var linkedTo: String?
        var priority: String
        /// Shots sharing this are the same moment on more than one camera.
        var setupId: String?
        var unit: Unit?
        /// **What it uses that its spec sheet lacks** (Ref 1627) — the lens,
        /// the camera's body — and which shoot's sheet would take them. The
        /// engine decides; the table offers Add to Spec Sheet.
        var offKit: OffKit?
        var frame: Frame?
        var frames: Int
        var stills: [Still]
        /// **The shot's Print Frame**, when it has one — the board that
        /// stands for it on paper. See `PrintFrame.swift`.
        var printFrame: PrintFrameView?
        /// A fraction of the text measure, never a size — so the page keeps its
        /// shape at any window width or on any paper.
        var frameWidth: Double
        var framePosition: String
        /// `M/OTS - Static - 37mm - Handheld`, already in column order.
        var technical: String
        var setup: [String]
        var alsoAt: [String]
        var day: String?
        var dayId: String?
        var id: String { placement }
    }
    struct Still: Decodable, Identifiable, Equatable {
        var ref: String
        var hash: String
        var filename: String
        var key: Bool
        /// **What the engine says this is** — image · gif · video · other.
        /// Nil only where nothing said, which is a bare hash-and-filename
        /// construction; `movie`/`gif`/`moving` fall back to the name there.
        var kind: String?
        /// Ask these rather than reading `ext` — see `Ingest.isMovie(_:kind:)`.
        var movie: Bool { Ingest.isMovie(ext, kind: kind) }
        var gif: Bool { Ingest.isGif(ext, kind: kind) }
        var moving: Bool { Ingest.isMoving(ext, kind: kind) }

        /// The remembered in/out range for a clip, in seconds. Both nil means
        /// the whole thing — the file itself is never touched.
        var trimStart: Double?
        var trimEnd: Double?
        /// **Which part of this picture to keep where it is drawn cropped**,
        /// and how far in. Absent is the middle at full width, which is what
        /// every tile in the app drew before this existed. Ref: his ask,
        /// 2026-08-30 — the engine holds the bounds, this only reads them.
        var cropX: Double?
        var cropY: Double?
        var cropScale: Double?
        var framing: ViewModel.Framing {
            ViewModel.Framing(x: cropX ?? 0.5, y: cropY ?? 0.5, scale: cropScale ?? 1)
        }
        /// **The storyboard arrows drawn over this use of the picture**, as
        /// the one line the engine stores. Absent on a picture nobody has
        /// marked, which is every picture until somebody does.
        var arrows: String?
        var marks: [ViewModel.Arrow] { ViewModel.Arrow.parse(arrows) }
        var id: String { ref }
        var ext: String {
            let parts = filename.split(separator: ".")
            return parts.count > 1 ? String(parts.last!) : "png"
        }
    }
}

extension ViewModel {
    /// **How a picture is framed when something draws it cropped.**
    ///
    /// `x` and `y` are the point of the picture that ends up in the middle of
    /// the tile, each from nought to one; `scale` is how far in. The middle at
    /// full width is what everything did before, so that is what nothing means.
    ///
    /// The same record the phone keeps, off the same three numbers on the same
    /// media ref — `handoff/from-phone.md`, 2026-08-30.
    struct Framing: Hashable {
        var x: Double = 0.5
        var y: Double = 0.5
        var scale: Double = 1

        static let middle = Framing()

        var isMiddle: Bool {
            abs(x - 0.5) < 0.001 && abs(y - 0.5) < 0.001 && abs(scale - 1) < 0.001
        }
    }
}

// ---------------------------------------------------------------- the board

struct BoardModel: Decodable {
    var days: [Lane]
    var unscheduled: [Strip]

    struct Lane: Decodable, Identifiable {
        var id: String
        var label: String
        var date: String
        var title: String
        var count: Int
        /// Every shot on it is in an archived scene: shot out and put away.
        var wrapped: Bool?
        var strips: [Strip]
        /// **The day as a flat run of shots, in the order it shoots them** —
        /// what the Shooting Order switch draws. A strip groups by scene and
        /// so cannot say 12C goes before 8A; this can.
        var run: [RunShot]
    }
    /// One shot in a day's running order.
    struct RunShot: Decodable, Identifiable {
        var placement: String
        var number: String
        var scene: String
        var heading: String
        var title: String
        var description: String
        var struck: Bool
        var id: String { placement }
    }
    /// A scene's presence on one day. A scene split over two days is two strips,
    /// each carrying only the shots that fall on that day.
    struct Strip: Decodable, Identifiable {
        var scene: String
        var number: String
        var heading: String
        var intExt: String
        var location: String
        var timeOfDay: String
        var count: Int
        var sequence: String?
        var colour: String
        /// The other days this scene touches — "also Day 2".
        var elsewhere: [String]
        /// The shots this strip stands for, so one can be pulled out on its own.
        var shots: [StripShot]
        var frame: ViewModel.Frame?
        var id: String { scene }
    }
    struct StripShot: Decodable, Identifiable {
        var placement: String
        var number: String
        /// A short name for the shot, separate from the sentence describing it —
        /// "ChatGPT Screen" against "ECU insert on the ChatGPT screen". Optional,
        /// and its column is off until somebody turns it on.
        var title: String
        var description: String
        var id: String { placement }
    }
}

/// What an import did, in terms worth showing someone.
struct ImportReport: Decodable {
    var summary: String
    var added: Int
    var updated: Int
    var scenes: [String]
    /// A number the sheet asked for that it could not have, and what it got
    /// instead. Nothing to do with the description — only the number.
    var renumbered: [Renumber]
    /// Days the sheet named that this project does not have. Scheduling is a
    /// decision, so those rows are left unscheduled rather than invented.
    var daysNotFound: [String]
    var skipped: [Skip]

    /// A clean import applies and reports; only one with something to say stops.
    var hasSomethingToSay: Bool {
        !renumbered.isEmpty || !daysNotFound.isEmpty || !skipped.isEmpty
    }

    struct Renumber: Decodable, Identifiable {
        var asked: String
        var given: String
        var id: String { asked + given }
    }
    struct Skip: Decodable, Identifiable {
        var row: Int
        var why: String
        var id: Int { row }
    }
}

struct ListModel: Decodable, Identifiable {
    var field: String
    /// Whether the project has declared this list finished.
    var locked: Bool = false
    var values: [Entry]
    var id: String { field }

    struct Entry: Decodable, Identifiable {
        var value: String
        /// How many shots lean on it — which is what makes removing it safe or not.
        var used: Int
        var id: String { value }
    }
}
