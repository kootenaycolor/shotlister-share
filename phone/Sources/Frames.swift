import SwiftUI
import ImageIO

/// Pictures, read from the film's folder and kept for as long as the screen
/// wants them.
///
/// A file is named by its contents, so the same frame on four shots is one file
/// and one cache entry. The extension somebody typed is a label rather than a
/// fact — the engine says what the bytes actually are, and that answer is what
/// gets used.
@MainActor
final class Frames: ObservableObject {
    /// Pictures decoded small, for the lists and strips that draw them small,
    /// keyed by the file **and the size it was decoded at**.
    ///
    /// **A picture costs what it is decoded at.** See `UIImage.moving(from:atMost:)`
    /// for the measurement; the short of it is that drawing a full-size proxy
    /// into a 54×30 thumbnail cost more than a whole frame, every frame, and
    /// forty of them held 253 MB.
    private var thumbs: [String: UIImage] = [:]
    /// The order they arrived in, so the oldest can go when there are too many.
    private var thumbOrder: [String] = []
    /// **Held to a budget in bytes rather than a count**, because a storyboard
    /// plate and a list thumbnail are the same kind of thing and two hundred
    /// times apart in size. Forty list thumbnails come to about 2.5 MB, so this
    /// holds hundreds of them — or a few dozen plates, which is equally right.
    ///
    /// **96, not 48 — 2026-10-13.** A two-column wall decodes each tile at about
    /// a thousand pixels, 2 to 3 MB apiece, so Call Her Back's 21-picture
    /// *Specific Compositions* board alone came to about 50 MB and could never
    /// be held whole: scrolling it meant pictures leaving and coming back.
    private let thumbBudget = 96 * 1_048_576

    /// Pictures at full size, for the screens that actually look at one.
    ///
    /// **Kept short on purpose.** This used to be the only cache, it was never
    /// trimmed, and every picture he had opened all session stayed decoded in
    /// memory until iOS took the lot back at once.
    private var whole: [String: UIImage] = [:]
    private var wholeOrder: [String] = []
    private let wholeBudget = 64 * 1_048_576

    private var films: [String: URL] = [:]
    /// What could not be fetched, when, and how many times. **Not a permanent
    /// verdict.**
    ///
    /// It used to be a plain set: a file that failed once was treated as absent
    /// for the rest of the session. A photograph still coming down from iCloud
    /// fails exactly once and then arrives, so the screen kept drawing the grey
    /// square long after the picture was sitting on the disk — which is exactly
    /// what he saw as "it keeps a placeholder image, and then it adds a second
    /// image".
    private var missing: [String: (at: Date, tries: Int)] = [:]
    private weak var engine: Engine?

    /// Nudges the screens to ask again while anything is still absent.
    ///
    /// **Waiting is not enough on its own.** SwiftUI only asks for a picture
    /// while it is drawing, and nothing about a file quietly appearing on disk
    /// makes it draw. Without this the retry would only happen the next time
    /// something *else* changed on the screen.
    private var retry: Timer?

    /// The project's folder, so the pictures that have not arrived can be asked
    /// for. Optional only because a project can fail to open.
    private let folder: URL?

    /// Files iCloud is still bringing down, by the stem they are stored under.
    ///
    /// **This is what stops him deleting his own photographs.** A picture still
    /// on its way and a frame with nothing behind it both draw as a grey
    /// square, and he read the first as a placeholder the app had left lying
    /// around — *"I have to delete it"*. One of those is a photograph.
    private var arriving: Set<String> = []

    /// How long a failure is believed for: three seconds, doubling, up to half
    /// a minute. A file coming down over a bad signal is worth waiting for; a
    /// file that is genuinely gone should not be asked about every three
    /// seconds all afternoon.
    private func patience(after tries: Int) -> TimeInterval {
        min(30, 3 * pow(2, Double(max(0, tries - 1))))
    }

    init(engine: Engine?, folder: URL? = nil) {
        self.engine = engine
        self.folder = folder
        stripWatch = NotificationCenter.default.addObserver(
            forName: Filmstrip.made, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stripNone.removeAll()
                self?.stripUsesAsked = .distantPast
                self?.tellTheScreens()
            }
        }
    }

    // ------------------------------------------------------- preview stills

    /// **Preview Stills** (his ask, 2026-10-14): what a waiting clip shows
    /// instead of one still. The shot's current Print Frame when `board` is
    /// handed in (only for the shot's key picture), otherwise this use's
    /// four-moment strip, the one the printed page uses. Nil while neither
    /// is here, and the clip shows its first frame as before.
    ///
    /// The strip's file name is the engine's (`clips`), never worked out
    /// here. `Session.prepareStrips` makes missing strips when a film opens.
    func preview(_ frame: Engine.Frame, board: Engine.Row.PrintBoard?, atMost: CGFloat,
                 mode: ClipThumbs) -> UIImage? {
        if mode == .printFrame, let board,
           let image = image(hash: board.hash, ext: board.ext, atMost: atMost) {
            return image
        }
        guard frame.kind == .clip, mode != .still else { return nil }
        let use = Self.useKey(frame.hash, frame.cut)
        let held = "\(use)@\(Int(atMost))"
        if let hit = strips[held] { return hit }
        if stripLoading.contains(held) { return nil }
        if let when = stripNone[held], Date().timeIntervalSince(when) < 15 { return nil }
        guard let name = stripName(use) else { stripNone[held] = Date(); return nil }
        stripLoading.insert(held)
        let folder = self.folder
        Task { [weak self] in
            let picture = await Task.detached(priority: .utility) {
                Frames.load(name, ext: "strip", in: folder, atMost: atMost)
            }.value
            guard let self else { return }
            self.stripLoading.remove(held)
            guard let picture else { self.stripNone[held] = Date(); return }
            self.strips[held] = picture
            self.tellTheScreens()
        }
        return nil
    }

    private var strips: [String: UIImage] = [:]
    private var stripLoading: Set<String> = []
    private var stripNone: [String: Date] = [:]
    private var stripUses: [String: String] = [:]
    private var stripUsesAsked: Date = .distantPast
    private var stripWatch: NSObjectProtocol?

    private struct StripUse: Decodable {
        let stem: String
        let key: String
        let start: Double
        let end: Double
    }

    /// What the engine files this use's strip under; asked again at most every
    /// few seconds when a use is not in the last answer.
    private func stripName(_ use: String) -> String? {
        if let known = stripUses[use] { return known }
        guard let engine, Date().timeIntervalSince(stripUsesAsked) > 3 else { return nil }
        stripUsesAsked = Date()
        let listed = (try? JSONDecoder().decode([StripUse].self, from: engine.raw("clips"))) ?? []
        var fresh: [String: String] = [:]
        for one in listed {
            fresh[Self.useKey(one.stem, one.end > one.start ? (one.start, one.end) : nil)] = one.key
        }
        stripUses = fresh
        return fresh[use]
    }

    private static func useKey(_ hash: String, _ cut: (start: Double, end: Double)?) -> String {
        let stem = String(hash.prefix(32))
        guard let cut else { return stem }
        return "\(stem)|\(Int((cut.start * 1000).rounded()))|\(Int((cut.end * 1000).rounded()))"
    }

    /// Whether this frame is a photograph on its way rather than a gap.
    func onItsWay(_ frame: Engine.Frame) -> Bool {
        arriving.contains(String(frame.hash.prefix(32)))
    }

    /// Whether there is genuinely nothing behind this frame.
    ///
    /// **A frame can exist with no picture behind it.** Two of his shots carry
    /// one: records written on 2026-08-16 by something that stored the entry
    /// and left the file behind, so the shot has claimed a picture ever since
    /// and no device has ever had one. Drawn as an empty frame it looked like a
    /// slot to add to, and he was deleting real photographs beside it trying to
    /// tidy them up.
    ///
    /// Two failures rather than one, so a picture that is merely slow is never
    /// called missing.
    func isGone(_ frame: Engine.Frame) -> Bool {
        guard !onItsWay(frame) else { return false }
        return (missing[frame.hash]?.tries ?? 0) >= 2
    }

    /// What a frame turns out to be, once its bytes are here.
    ///
    /// **One question, asked once.** A still, a GIF and a clip are three
    /// different things to draw, and before this every screen decided for
    /// itself — which is why a clip was a still with an apology on it in one
    /// place and nothing at all in another.
    enum Shown {
        case picture(UIImage)
        /// A clip, and the seconds of it this use plays. **The cut travels with
        /// it**: a clip trimmed on the Mac used to play whole everywhere on the
        /// phone, which is a different clip.
        case film(URL, Cut?)
    }

    /// The in and out of one use of a clip.
    struct Cut: Hashable {
        var start: Double
        var end: Double
        var length: Double { max(0, end - start) }
    }

    /// - Parameter atMost: the longest edge, in pixels, this will be drawn at.
    ///   Nil asks for the picture whole, which is what looking at one wants.
    /// - Parameter moving: whether a clip should be handed back as something
    ///   that plays. **A list says no.**
    ///
    ///   His words, 2026-09-02: *"maybe we don't autoplay videos in the scene
    ///   section?"* — and he was right about where the last of the lag was. A
    ///   clip drawn anywhere used to build an `AVQueuePlayer` and an
    ///   `AVPlayerLooper` and start them, thumbnail or not, so a scene list
    ///   scrolling past his 28 clips stood up 28 video decoders and an audio
    ///   queue apiece for pictures 54 points across. That is an order of
    ///   magnitude more than any photograph costs, and it is the "laggy until
    ///   all the media has loaded" he could feel after the decoding was fixed.
    ///
    ///   A clip already carries a still that stands for it, filed under the
    ///   same name — so a list draws that, with the play mark the filmstrip
    ///   already uses. The storyboard plate and the viewers still play: those
    ///   are screens for looking at one thing, which is what motion is for.
    func shown(_ frame: Engine.Frame, atMost: CGFloat? = nil, moving: Bool = true) -> Shown? {
        if frame.kind == .clip {
            guard moving else { return poster(frame, atMost: atMost) }
            guard let url = movie(hash: frame.hash, ext: frame.ext) else { return nil }
            return .film(url, frame.cut.map { Cut(start: $0.start, end: $0.end) })
        }
        return image(hash: frame.hash, ext: frame.ext, atMost: atMost).map(Shown.picture)
    }

    /// The still that stands for a clip. It is stored beside the clip under the
    /// same name — `<name>.mp4` and `<name>.jpg` (`.png` in films from before
    /// 2026-09-15; the engine hands back whichever is there) — so this is the
    /// ordinary picture path with the extension named rather than guessed.
    private func poster(_ frame: Engine.Frame, atMost: CGFloat?) -> Shown? {
        image(hash: frame.hash, ext: "jpg", atMost: atMost).map(Shown.picture)
    }

    /// The same, for a location's photograph, which carries its own name.
    func shown(_ still: Engine.Still, atMost: CGFloat? = nil, moving: Bool = true) -> Shown? {
        shown(still.frame, atMost: atMost, moving: moving)
    }

    /// A clip as a file on disk.
    ///
    /// **The proxy already is a file inside the project**, and a player wants a
    /// file — so this finds it and hands back where it is.
    ///
    /// It used to ask the engine for the clip *as text*: the engine read the
    /// file and base64-encoded it, this decoded that back into bytes and wrote
    /// a second copy into the caches folder — all of it inside a view's body,
    /// on the main thread, while the screen waited. A still is a few kilobytes
    /// and nobody ever noticed; a clip is ten to a hundred times that, and the
    /// first time one came on screen the app stopped for as long as it took.
    /// Nothing is read, decoded or copied now.
    func movie(hash: String, ext: String) -> URL? {
        if let hit = films[hash] { return hit }
        if stillMissing(hash) { return nil }
        resolveMovie(hash: hash, ext: ext)
        return nil
    }

    /// Clip files being found right now, so a board scrolling past the same
    /// clip several times in a frame asks for it once.
    private var resolvingMovies: Set<String> = []

    /// Finds the file for a clip off the main thread.
    ///
    /// **This used to be `movie`'s own body, done inline in a view's `body`.**
    /// Listing `media/proxies` and asking each candidate whether iCloud has it
    /// is cheap on a small project and not cheap on Call Her Back's: 321 files,
    /// asked for synchronously every time a never-before-seen clip tile
    /// scrolled into a board, which is what "scrolling is janky" turned out to
    /// be here. It is a nil-then-fills-in answer now, the same shape the
    /// thumbnail path already uses.
    private func resolveMovie(hash: String, ext: String) {
        guard !resolvingMovies.contains(hash) else { return }
        resolvingMovies.insert(hash)
        let folder = self.folder
        Task { [weak self] in
            guard let self else { return }
            let file = await Task.detached(priority: .userInitiated) {
                Frames.proxyFile(hash, wanting: ext, in: folder)
            }.value
            self.resolvingMovies.remove(hash)
            guard let file else {
                self.noteMissing(hash)
                return
            }
            self.films[hash] = file
            self.missing[hash] = nil
            self.nudged.remove(hash)
            self.tellTheScreens()
        }
    }

    /// The stored file for a hash, **whatever extension it was written under**.
    ///
    /// The same rule the engine's own lookup follows: a file is named by its
    /// contents, and its extension is whatever it *became* on the way in rather
    /// than what somebody called it. So the stem is what gets matched, and the
    /// extension is read off whatever is there.
    ///
    /// **Nothing here touches the class**, so it is safe to run away from the
    /// main thread.
    nonisolated static func proxyFile(_ hash: String, wanting ext: String, in folder: URL?) -> URL? {
        guard let folder else { return nil }
        let stem = String(hash.prefix(32))
        let proxies = folder.appending(path: "media/proxies")
        // **A plain listing.** Asking iCloud about every one of 357 files to
        // pick one of them was most of the cost; only the file chosen is
        // asked whether it is really here.
        guard let names = try? FileManager.default.contentsOfDirectory(
                at: proxies, includingPropertiesForKeys: nil)
        else { return nil }
        // **One hash can have two files.** A clip is stored as the clip and as
        // a still standing for it — `<name>.mp4` and `<name>.jpg`, the same
        // name twice — so "the file whose stem matches" is an ambiguous
        // question. Answered by the engine's own rule (`find_proxy`): the
        // extension asked for, then any still if a still was asked for, then
        // anything that moves, then the rest — alphabetical inside a rank.
        let wanted = ext.lowercased()
        let wantedStill = stills.contains(wanted)
        func rank(_ url: URL) -> Int {
            let e = url.pathExtension.lowercased()
            if e == wanted { return 0 }
            if wantedStill && stills.contains(e) { return 1 }
            if moving.contains(e) { return 2 }
            return 3
        }
        let mine = names
            .filter { $0.deletingPathExtension().lastPathComponent == stem }
            .sorted { (rank($0), $0.pathExtension.lowercased()) < (rank($1), $1.pathExtension.lowercased()) }
        // A name in the folder is not the same as bytes on the phone.
        return mine.first { Cloud.here($0) }
    }

    private nonisolated static let stills: Set<String> = ["png", "jpg", "jpeg"]
    private nonisolated static let moving: Set<String> = ["mp4", "mov", "m4v", "webm", "avi", "gif"]

    /// The picture for a hash, or nil while it is not here.
    ///
    /// Asking again for something known to be absent must not re-ask the engine
    /// every time SwiftUI redraws a list — a shot list scrolling past forty
    /// frameless rows would otherwise ask forty times a frame.
    ///
    /// **A thumbnail is fetched beside the drawing; a picture being looked at is
    /// fetched inside it.** Unpacking a photograph costs about 10 ms, and doing
    /// it inside `body` meant every row seen for the first time dropped a frame
    /// — the stutter left over after the 2026-09-02 sizing fix. A thumbnail now
    /// answers nil straight away, unpacks off the main thread, and says so when
    /// it lands; the grey square it draws in the meantime is the one already
    /// there for a photograph still coming down from iCloud.
    ///
    /// A viewer is not allowed that. It has one picture, the tap that opened it
    /// is a deliberate wait, and `MediaViewer` reads the image straight back out
    /// to crop and share it — nil there is a broken screen, not a slower one.
    func image(hash: String, ext: String, atMost: CGFloat? = nil) -> UIImage? {
        let key = atMost.map { "\(hash)@\(Int($0))" } ?? hash
        if atMost == nil, let hit = whole[hash] { used(hash, in: &wholeOrder); return hit }
        if atMost != nil, let hit = thumbs[key] { used(key, in: &thumbOrder); return hit }
        // A picture already here whole is cheaper to hand back than to decode a
        // second time small — it only happens on the way back from a viewer.
        if atMost != nil, let hit = whole[hash] { used(hash, in: &wholeOrder); return hit }
        if stillMissing(hash) { return nil }

        guard let atMost else {
            guard let image = Frames.load(hash, ext: ext, in: folder, atMost: nil) else {
                noteMissing(hash)
                return nil
            }
            keep(image, at: hash, small: false)
            return image
        }

        fetch(key: key, hash: hash, ext: ext, atMost: atMost)
        return nil
    }

    /// Thumbnails being unpacked right now, so a list redrawing forty times
    /// while one is in flight asks for it once.
    private var loading: Set<String> = []

    private func fetch(key: String, hash: String, ext: String, atMost: CGFloat) {
        guard !loading.contains(key) else { return }
        loading.insert(key)
        Task { [weak self] in
            guard let self else { return }
            // **Straight off the disk, 2026-10-06.** This used to go through
            // the engine, which read the file, base64-encoded it into a reply
            // a third bigger, and handed that across for this side to decode
            // back — about 17 ms for one of Call Her Back's 4 MB stills against
            // 0.4 ms to read it. Worse than the time: the engine answers one
            // call at a time, so while a screenful of thumbnails queued up
            // there, every tap that needed the engine waited behind them. That
            // was the "stuck" feeling while pictures loaded. The file is named
            // by its contents and found by the engine's own rule
            // (`proxyFile`), so nothing is lost by not asking.
            let folder = self.folder
            let picture = await Task.detached(priority: .userInitiated) {
                Frames.load(hash, ext: ext, in: folder, atMost: atMost)
            }.value

            self.loading.remove(key)
            guard let picture else {
                self.noteMissing(hash)
                return
            }
            self.keep(picture, at: key, small: true)
            self.tellTheScreens()
        }
    }

    /// The picture for a hash, read from the film's own folder. **Nothing
    /// here touches the class**, so it is safe to run away from the main
    /// thread — which is the whole point of it being separate.
    private nonisolated static func load(_ hash: String, ext: String, in folder: URL?,
                                         atMost: CGFloat?) -> UIImage? {
        guard let file = proxyFile(hash, wanting: ext, in: folder),
              let bytes = try? Data(contentsOf: file, options: .mappedIfSafe)
        else { return nil }
        // Built from every frame the file holds, so a GIF arrives able to move.
        // A single-frame file comes back an ordinary picture, so nothing here
        // has to know which it is looking at.
        return UIImage.moving(from: bytes, atMost: atMost)
    }

    /// **The shape of every picture seen so far, by hash, kept after the picture
    /// itself is evicted.** A wall whose tiles take their height from their
    /// picture reflows each time a tile is dropped from the cache and drawn
    /// again as a square placeholder; remembering the shape means a tile
    /// that is waiting is the size it will be, so nothing moves.
    private(set) var shapes: [String: CGFloat] = [:]

    func shape(of hash: String) -> CGFloat? { shapes[hash] }

    /// Pictures whose shape is being read right now.
    private var learning: Set<String> = []

    /// **Read the shape of every picture on a wall before any of it is drawn.**
    ///
    /// Remembering a shape once it has been seen still leaves the first pass:
    /// each tile waits as a guess and then jumps to its own shape. A file's
    /// width and height sit in its first few bytes, so reading them for a whole
    /// board costs less than unpacking one picture, and every waiting tile is
    /// the size it will be from the start.
    func learnShapes(_ wall: [Engine.Frame]) {
        let wanted = wall
            .filter { $0.kind != .clip && shapes[$0.hash] == nil && !learning.contains($0.hash) }
            .map(\.hash)
        guard !wanted.isEmpty else { return }
        learning.formUnion(wanted)
        let folder = self.folder
        Task { [weak self] in
            let found = await Task.detached(priority: .utility) {
                Frames.headerShapes(wanted, in: folder)
            }.value
            guard let self else { return }
            self.learning.subtract(wanted)
            guard !found.isEmpty else { return }
            for (hash, shape) in found where self.shapes[hash] == nil { self.shapes[hash] = shape }
            self.tellTheScreens()
        }
    }

    /// Width over height for each still, from the file's header alone — one
    /// listing of the folder for the lot, the way `proxyFile` finds one. A file
    /// still up in iCloud is skipped rather than fetched.
    private nonisolated static func headerShapes(_ hashes: [String], in folder: URL?) -> [String: CGFloat] {
        guard let folder,
              let names = try? FileManager.default.contentsOfDirectory(
                  at: folder.appending(path: "media/proxies"), includingPropertiesForKeys: nil)
        else { return [:] }
        var byStem: [String: URL] = [:]
        for url in names where stills.contains(url.pathExtension.lowercased()) {
            byStem[url.deletingPathExtension().lastPathComponent] = url
        }
        var found: [String: CGFloat] = [:]
        for hash in hashes {
            guard let file = byStem[String(hash.prefix(32))], Cloud.here(file),
                  let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let facts = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let wide = (facts[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
                  let high = (facts[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
                  wide > 0, high > 0
            else { continue }
            // Orientations 5 to 8 are a quarter turn: the picture as drawn is
            // the file's height across, the same turn the thumbnail makes.
            let turned = ((facts[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1) >= 5
            found[hash] = turned ? high / wide : wide / high
        }
        return found
    }

    private func keep(_ image: UIImage, at key: String, small: Bool) {
        shapes[key.components(separatedBy: "@").first ?? key] =
            image.size.width / max(image.size.height, 1)
        if small {
            thumbs[key] = image
            thumbOrder.append(key)
            trim(&thumbs, &thumbOrder, to: thumbBudget)
        } else {
            whole[key] = image
            wholeOrder.append(key)
            trim(&whole, &wholeOrder, to: wholeBudget)
        }
        let hash = key.components(separatedBy: "@").first ?? key
        missing[hash] = nil
        nudged.remove(hash)
    }

    /// Say that pictures have arrived — **once**, however many arrived.
    ///
    /// Every screen drawing a picture watches this object, so each call redraws
    /// all of them. A screenful landing one at a time would be eight redraws of
    /// eight rows; batching whatever arrives in the same turn makes it one.
    private var telling = false

    private func tellTheScreens() {
        guard !telling else { return }
        telling = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.telling = false
            self.objectWillChange.send()
        }
    }

    /// Move a picture to the young end of its list, because it was just drawn.
    ///
    /// **Order of use, not order of arrival — 2026-10-13.** It used to drop
    /// whatever had arrived first, on the reasoning that reads teach nothing.
    /// They teach the one thing that matters: what is on screen. Scrolling a
    /// board down and back up, the tiles in view were the oldest arrivals, so
    /// each picture fetched for the rows coming in threw out one already
    /// showing; that tile went to a spinner, fetched again, threw out its
    /// neighbour — the wall flickering in a wave. Every tile on screen is read
    /// each time the screen redraws, so the ones in view are always the newest.
    private func used(_ key: String, in order: inout [String]) {
        guard order.last != key, let at = order.lastIndex(of: key) else { return }
        order.remove(at: at)
        order.append(key)
    }

    /// Drop the least recently drawn until the store is inside its budget.
    private func trim(_ store: inout [String: UIImage], _ order: inout [String], to budget: Int) {
        var held = store.values.reduce(0) { $0 + Frames.weight($1) }
        while held > budget, order.count > 1 {
            let oldest = order.removeFirst()
            // The same key can be in the list twice only if it was evicted and
            // fetched again; dropping it once is right either way.
            guard !order.contains(oldest), let gone = store[oldest] else { continue }
            held -= Frames.weight(gone)
            store[oldest] = nil
        }
    }

    /// What a decoded picture actually occupies: every frame it holds, four
    /// bytes a pixel. A GIF of thirty frames is thirty pictures.
    private static func weight(_ image: UIImage) -> Int {
        let one = Int(image.size.width * image.scale) * Int(image.size.height * image.scale) * 4
        return one * max(1, image.images?.count ?? 1)
    }

    /// Whether a failure is still recent enough to believe.
    ///
    /// **It does not forget the failure**, only stops believing it for a
    /// moment. Clearing the record here was a real bug: the next attempt then
    /// counted as the first, the tally never reached two, and a picture that
    /// was genuinely gone was never allowed to say so. The record is cleared in
    /// one place only — when the picture actually arrives.
    private func stillMissing(_ hash: String) -> Bool {
        guard let failed = missing[hash] else { return false }
        // Asking again for something absent must not re-ask the engine on every
        // redraw — a shot list scrolling past forty frameless rows would ask
        // forty times a frame. Once every few seconds is the compromise.
        return Date().timeIntervalSince(failed.at) < patience(after: failed.tries)
    }

    private func noteMissing(_ hash: String) {
        let tries = (missing[hash]?.tries ?? 0) + 1
        missing[hash] = (Date(), tries)
        nudged.remove(hash)
        askTheCloud()
        keepAsking()
    }

    /// Whether a walk of the film for iCloud is running, and when the last
    /// one finished.
    private var askingCloud = false
    private var askedCloudAt = Date.distantPast

    /// Ask iCloud for anything still outstanding, and remember what that is.
    ///
    /// **Away from the screen, and at most once every few seconds.** It walks
    /// the whole film — 730 files on Call Her Back, 48 ms on a Mac and several
    /// times that on the phone — and it used to do that on the main thread
    /// once for every picture found missing, and again every three seconds.
    /// A screenful of pictures still coming down from iCloud froze the app for
    /// as many walks as there were pictures.
    private func askTheCloud() {
        guard let folder, !askingCloud,
              Date().timeIntervalSince(askedCloudAt) >= 2.5 else { return }
        askingCloud = true
        Task { [weak self] in
            let coming = await Cloud.bringDownQuietly(folder)
            guard let self else { return }
            self.askingCloud = false
            // Another walk of this film was already running; it is enough.
            guard let coming else { return }
            self.askedCloudAt = Date()
            if coming != self.arriving {
                self.arriving = coming
                self.tellTheScreens()
            }
        }
    }

    /// Missing pictures the screens have already been told to ask about again
    /// since they last failed, so a picture nobody is looking at does not
    /// redraw every screen every three seconds forever.
    private var nudged: Set<String> = []

    private func keepAsking() {
        guard retry == nil else { return }
        retry = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                guard !self.missing.isEmpty else {
                    timer.invalidate()
                    self.retry = nil
                    return
                }
                // Ask iCloud again first — a download that has not been asked
                // for never starts, and one already running may have finished.
                self.askTheCloud()
                // Then draw again — **only if something is due another try.**
                // This used to redraw every screen holding a picture every
                // three seconds, for as long as any picture anywhere was
                // missing: a hitch in the middle of a scroll, on a clock.
                let now = Date()
                let due = self.missing.filter { hash, failed in
                    !self.nudged.contains(hash)
                        && now.timeIntervalSince(failed.at) >= self.patience(after: failed.tries)
                }.map(\.key)
                guard !due.isEmpty else { return }
                self.nudged.formUnion(due)
                self.objectWillChange.send()
            }
        }
    }
}

/// A frame as it appears in a list — small, and square-cornered.
///
/// His standing rule: what floats turns a corner, what is cut in keeps its
/// rectangle. A thumbnail inside a row is cut in.
struct FrameThumbnail: View {
    @EnvironmentObject private var frames: Frames
    @Environment(\.displayScale) private var scale
    let frame: Engine.Frame?
    var side: CGFloat = 54
    /// The shot's current Print Frame, handed in only with its key picture.
    var board: Engine.Row.PrintBoard? = nil
    @AppStorage(ClipPlay.key) private var automatic = ClipPlay.startingAutomatic
    @AppStorage(ClipPlay.thumbsKey) private var thumbs = ClipPlay.startingThumbs

    private var waiting: Bool { frame.map(frames.onItsWay) ?? false }

    /// Clip Thumbnails, while clips wait for play: the board on the key
    /// picture, still or clip, or a clip's four moments.
    private func preview(_ frame: Engine.Frame) -> UIImage? {
        guard !automatic else { return nil }
        return frames.preview(frame, board: board,
                              atMost: Thumbnails.bucket(forSide: side, scale: scale),
                              mode: ClipThumbs(rawValue: thumbs) ?? .printFrame)
    }
    private var gone: Bool { frame.map(frames.isGone) ?? false }

    var body: some View {
        Group {
            if let frame,
               let shown = frames.shown(frame,
                                        atMost: Thumbnails.bucket(forSide: side, scale: scale),
                                        moving: false) {
                Group {
                    if let still = preview(frame) {
                        Previewed(image: still)
                    } else {
                        Picture(shown, framing: frame.framing, arrows: frame.arrows)
                    }
                }
                    // A stilled clip has to say it is one, or it reads as a
                    // photograph. The same mark the filmstrip already uses.
                    .overlay(alignment: .bottomTrailing) {
                        if frame.kind == .clip {
                            Image(systemName: "play.fill")
                                .font(.system(size: 7))
                                .padding(2.5)
                                .background(.black.opacity(0.55), in: Circle())
                                .foregroundStyle(.white)
                                .padding(2)
                        }
                    }
            } else {
                // **A shot with no picture is an empty frame, not an icon.**
                // A column of grey boxes each wearing a photo glyph read as
                // noise down a schedule; the glyph stays only where it says
                // something, waiting or missing.
                EmptyFrame()
                    .overlay {
                        if waiting || gone {
                            Image(systemName: waiting ? "icloud.and.arrow.down" : "exclamationmark.triangle")
                                .font(.kitLabel)
                                .foregroundStyle(.tertiary)
                        }
                    }
            }
        }
        .frame(width: side, height: side * 9 / 16)
        .clipped()
    }
}

/// **Where a picture would be**: a faint ground inside a hairline, so an
/// empty frame keeps its shape on the page without shouting grey.
struct EmptyFrame: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.045))
            .overlay { Rectangle().strokeBorder(Style.rule, lineWidth: 1) }
    }
}

/// A frame at storyboard size, in the project's own aspect ratio.
struct FramePlate: View {
    @EnvironmentObject private var frames: Frames
    @Environment(\.displayScale) private var scale
    let frame: Engine.Frame?
    var ratio: Double
    /// The shot's current Print Frame, handed in only with its key picture.
    var board: Engine.Row.PrintBoard? = nil
    @AppStorage(ClipPlay.key) private var automatic = ClipPlay.startingAutomatic
    @AppStorage(ClipPlay.thumbsKey) private var thumbs = ClipPlay.startingThumbs

    private var waiting: Bool { frame.map(frames.onItsWay) ?? false }
    private var gone: Bool { frame.map(frames.isGone) ?? false }

    /// A plate is as wide as the screen it is on, less the storyboard's margins.
    /// Asking for more pixels than the screen has is asking to resample for
    /// nothing.
    private var wanted: CGFloat {
        Thumbnails.bucket(forSide: UIScreen.main.bounds.width, scale: scale) / 1.5
    }

    var body: some View {
        Group {
            if let frame, let shown = frames.shown(frame, atMost: wanted) {
                Picture(shown, framing: frame.framing, arrows: frame.arrows,
                        preview: automatic ? nil
                            : frames.preview(frame, board: board, atMost: wanted,
                                             mode: ClipThumbs(rawValue: thumbs) ?? .printFrame))
            } else if waiting {
                EmptyFrame()
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: "icloud.and.arrow.down")
                                .font(.kitHeading)
                            // One of the sentences the copy law allows: it says
                            // why nothing is here, and it is the difference
                            // between waiting and deleting a photograph.
                            Text("Still coming down from iCloud")
                                .font(.kitLabel)
                        }
                        .foregroundStyle(.tertiary)
                    }
            } else if gone {
                EmptyFrame()
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.kitHeading)
                            Text("Picture missing")
                                .font(.kitLabel)
                        }
                        .foregroundStyle(.tertiary)
                    }
            } else {
                EmptyFrame()
                    .overlay {
                        Image(systemName: "photo.badge.plus")
                            .font(.title3.weight(.light))
                            .foregroundStyle(.quaternary)
                    }
            }
        }
        .aspectRatio(ratio, contentMode: .fit)
        .clipped()
    }
}


/// Something attached, drawn the way its own file wants to be drawn.
///
/// **One place decides**, so no screen has to remember that a GIF has to run
/// and a clip has to play. Everything the app shows goes through here: a still
/// is a still, a GIF animates, a clip plays muted on a loop the moment it is on
/// screen.
struct Picture: View {
    let shown: Frames.Shown
    var fill: Bool = true
    /// **Which part to keep when this is drawn into a shape that is not its
    /// own.** Nothing means the middle, which is what everything did before.
    ///
    /// Only a still is framed. A clip and a GIF are still centred: what they
    /// are drawn by is a player, not an image, and moving a player's picture
    /// about inside its own layer is a different job — noted, not built.
    var framing: Engine.Framing = .middle
    /// The storyboard arrows on this use of the picture. Drawn on the
    /// picture's own rectangle, so they ride with it wherever it is drawn.
    var arrows: [Engine.Arrow] = []
    /// What Clip Thumbnails puts in place of the picture while clips wait:
    /// a clip shows it under its play mark (`Clip`), a still in its place.
    var preview: UIImage? = nil

    init(_ shown: Frames.Shown, fill: Bool = true, framing: Engine.Framing = .middle,
         arrows: [Engine.Arrow] = [], preview: UIImage? = nil) {
        self.shown = shown
        self.fill = fill
        self.framing = framing
        self.arrows = arrows
        self.preview = preview
    }

    var body: some View {
        if case .picture = shown, let preview {
            Previewed(image: preview)
        } else {
            drawn
        }
    }

    @ViewBuilder
    private var drawn: some View {
        switch shown {
        case .film(let url, let cut):
            Clip(url: url, cut: cut, fill: fill, preview: preview)
        case .picture(let image) where image.images != nil:
            Moving(image: image, fill: fill)
        case .picture(let image) where fill:
            Framed(image: image, framing: framing, arrows: arrows)
        case .picture(let image):
            Fitted(image: image, arrows: arrows)
        }
    }
}

/// **A picture fitted whole inside its space, arrows and all.**
///
/// `Image(contentMode: .fit)` alone cannot carry them: the drawn rectangle is
/// worked out by the layout system and never handed back, so an overlay lands
/// on the space rather than on the photograph. This does the same arithmetic
/// itself, so both halves agree — the Mac's `Fitted`, on the phone.
struct Fitted: View {
    let image: UIImage
    var arrows: [Engine.Arrow] = []

    var body: some View {
        GeometryReader { space in
            let box = fitting(space.size)
            ZStack {
                Image(uiImage: image).resizable()
                if !arrows.isEmpty { ArrowMarks(arrows: arrows) }
            }
            .frame(width: box.width, height: box.height)
            .frame(width: space.size.width, height: space.size.height)
        }
    }

    private func fitting(_ space: CGSize) -> CGSize {
        let shape = max(image.size.width, 1) / max(image.size.height, 1)
        let byWidth = CGSize(width: space.width, height: space.width / shape)
        if byWidth.height <= space.height { return byWidth }
        return CGSize(width: space.height * shape, height: space.height)
    }
}

/// A picture filling its box, keeping the part it was told to keep.
///
/// **The anchor cannot show empty space, by construction.** `x` and `y` run
/// from nought to one across whatever hangs over the edges of the box, so
/// nought is the left edge of the picture against the left edge of the box and
/// one is the right against the right. There is no arithmetic anywhere that
/// can put a gap beside a photograph.
struct Framed: View {
    let image: UIImage
    var framing: Engine.Framing = .middle
    /// **Arrows ride with the picture, not with the tile.** Drawn on the same
    /// rectangle the photograph is drawn on and carried by the same offset,
    /// so cropping in on a corner crops in on the arrow drawn there.
    var arrows: [Engine.Arrow] = []

    var body: some View {
        GeometryReader { space in
            let box = space.size
            let size = covering(box)
            ZStack {
                Image(uiImage: image).resizable()
                if !arrows.isEmpty { ArrowMarks(arrows: arrows) }
            }
            .frame(width: size.width, height: size.height)
            .offset(x: (0.5 - framing.x) * (size.width - box.width),
                    y: (0.5 - framing.y) * (size.height - box.height))
            .frame(width: box.width, height: box.height)
        }
        .clipped()
    }

    /// The size the picture is drawn at: big enough to cover the box, times
    /// however far in it has been taken.
    private func covering(_ box: CGSize) -> CGSize {
        let shape = max(image.size.width, 1) / max(image.size.height, 1)
        var width = box.width
        var height = box.width / shape
        if height < box.height {
            height = box.height
            width = height * shape
        }
        return CGSize(width: width * framing.scale, height: height * framing.scale)
    }
}

/// Every picture on a shot, not just the one standing for it.
///
/// A shot covered three ways has three frames, and drawing one of them is
/// drawing a third of the answer. They page across; the strip underneath says
/// how many there are and which is which, and appears only when there is more
/// than one — a single frame needs no index.
struct Gallery: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var frames: Frames

    let stills: [Engine.Still]
    let ratio: Double
    /// The shot these frames are on, for choosing which stands for it.
    var shot: String? = nil

    @State private var showing = 0
    /// The one opened full screen. A frame on a shot could be looked at only at
    /// plate size until now — and a clip could not be scrubbed, cut or made to
    /// stand for itself anywhere but the Mac.
    @State private var browsing: Engine.Still?

    var body: some View {
        if stills.isEmpty {
            FramePlate(frame: nil, ratio: ratio)
        } else {
            VStack(spacing: 0) {
                TabView(selection: $showing) {
                    ForEach(Array(stills.enumerated()), id: \.element.ref) { index, still in
                        One(still: still, ratio: ratio)
                            .contentShape(Rectangle())
                            .onTapGesture { browsing = still }
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .aspectRatio(ratio, contentMode: .fit)

                if stills.count > 1 { strip }
            }
            .fullScreenCover(item: $browsing) { still in
                StillViewer(still: still, all: stills, onDelete: { session.detach($0) },
                            cropTo: ratio)
                    .environmentObject(session)
                    .environmentObject(frames)
            }
        }
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(stills.enumerated()), id: \.element.ref) { index, still in
                    Button { withAnimation(.snappy) { showing = index } } label: {
                        FrameThumbnail(frame: still.frame, side: 62)
                            .overlay(alignment: .topTrailing) { badge(still) }
                            .overlay {
                                Rectangle()
                                    .strokeBorder(index == showing ? Color.accentColor : .clear,
                                                  lineWidth: 2)
                            }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        // **The key frame** (the Mac's star): which frame
                        // stands for the shot in the list and storyboard.
                        if let shot, still.key != true {
                            Button { session.keyFrame(shot: shot, still) } label: {
                                Label("Show for Shot", systemImage: "star")
                            }
                        }
                        if index > 0 {
                            Button { session.move(still, to: index - 1) } label: {
                                Label("Move Left", systemImage: "arrow.left")
                            }
                        }
                        if index < stills.count - 1 {
                            Button { session.move(still, to: index + 1) } label: {
                                Label("Move Right", systemImage: "arrow.right")
                            }
                        }
                        Button(role: .destructive) { session.detach(still) } label: {
                            Label("Remove from Shot", systemImage: "minus.circle")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func badge(_ still: Engine.Still) -> some View {
        switch still.kind {
        case .clip:
            Image(systemName: "play.fill")
                .font(.system(size: 8))
                .padding(3)
                .background(.black.opacity(0.55), in: Circle())
                .foregroundStyle(.white)
                .padding(2)
        case .moving:
            Text("GIF")
                .font(.system(size: 7, weight: .bold))
                .padding(.horizontal, 3).padding(.vertical, 1)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 2))
                .foregroundStyle(.white)
                .padding(2)
        default:
            EmptyView()
        }
    }

    /// One picture, at plate size.
    private struct One: View {
        let still: Engine.Still
        let ratio: Double

        @EnvironmentObject private var session: Session
        @EnvironmentObject private var frames: Frames

        var body: some View {
            FramePlate(frame: still.frame, ratio: ratio)
                .overlay(alignment: .bottom) {
                    // Nothing behind it and nothing coming: the only useful
                    // thing left is to take it off, so say so where he is
                    // already looking rather than in a menu he has to find.
                    if frames.isGone(still.frame) {
                        Button("Remove") { session.detach(still) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .padding(.bottom, 16)
                    }
                }
        }
    }
}
