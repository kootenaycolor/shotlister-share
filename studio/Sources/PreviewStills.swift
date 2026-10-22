import AppKit
import ImageIO

/// **Preview Stills: what a waiting clip shows in place of its poster.**
///
/// His ask, 2026-10-14: *"when videos are not on autoplay, the thumbnail
/// should show the preview stills."* Two pictures already stand for a clip on
/// paper, and this draws the same ones on screen:
///
/// - the shot's **Print Frame**, when its bake is current, on the tile of the
///   shot's key picture, still or clip (the caller decides that and hands the
///   bake in);
/// - otherwise the clip's **four moments**, two by two — the strip the printed
///   page uses (`Filmstrip`), for this use of the clip and its trim.
///
/// The strip is found the way the printed page finds it: the engine says what
/// each use is filed under (`clips`), nothing here works a name out. A strip
/// missing or made for another frame ratio is made here, off the main thread,
/// and filed through the engine's `strip` door like `Filmstrip.ensure` files
/// one. Until it lands the tile shows the poster.
final class ClipPreviews: ObservableObject {
    static let shared = ClipPreviews()

    /// Bumped when a picture arrives, so the tiles waiting on it redraw.
    @Published private(set) var arrivals = 0

    private var pictures: [String: NSImage] = [:]
    private var asking: Set<String> = []
    /// Given up on: the clip will not give four moments, or has arrows (the
    /// engine lists no strip for a marked clip). Keyed with the ratio.
    private var none: Set<String> = []

    /// `hash|start|end` to the strip's file name, from the engine.
    private var uses: [String: String] = [:]
    private var usesAsked: Date = .distantPast

    private let queue = DispatchQueue(label: "shotlister.previewstills", qos: .utility)

    // ---- the Print Frame -------------------------------------------------

    /// **Not given up on for good.** A bake whose file is not here (swept by
    /// an older copy of the app, 2026-10-14, or still on its way from the
    /// Mac that made it) is baked again by `PrintFrameBaker`, which says so
    /// through `boardFiled`; until then it is asked again every few seconds.
    func board(_ baked: PrintFrameView.Baked, engine: Engine?) -> NSImage? {
        let key = "p" + baked.hash
        if let held = pictures[key] { return held }
        guard let engine else { return nil }
        if let when = boardMissed[key], Date().timeIntervalSince(when) < 5 { return nil }
        guard let bytes = engine.proxy(hash: baked.hash, ext: baked.ext),
              let made = NSImage(data: bytes) else {
            boardMissed[key] = Date()
            return nil
        }
        boardMissed[key] = nil
        pictures[key] = made
        return made
    }

    /// A board was just filed: ask again for every one that was missing.
    func boardFiled() {
        guard !boardMissed.isEmpty else { return }
        boardMissed.removeAll()
        arrivals += 1
    }

    private var boardMissed: [String: Date] = [:]

    // ---- the four moments ------------------------------------------------

    func strip(hash: String, ext: String, trimStart: Double?, trimEnd: Double?,
               engine: Engine?) -> NSImage? {
        guard let engine else { return nil }
        let ratio = CGFloat(ShellState.shared.view?.project.ratio ?? 2.39)
        guard ratio > 0 else { return nil }
        let trim: (start: Double, end: Double)? = {
            guard let trimStart, let trimEnd, trimEnd > trimStart else { return nil }
            return (trimStart, trimEnd)
        }()
        let use = Self.useKey(hash, trim)
        let held = "s\(use)@\(String(format: "%.3f", ratio))"
        if let picture = pictures[held] { return picture }
        if none.contains(held) || asking.contains(held) { return nil }

        guard let name = fileName(use, engine: engine) else { return nil }
        let file = engine.folder.appending(path: "media/proxies/\(name).strip")
        // The movie is read on the main thread only to find its file; the
        // frames are pulled out of it on the queue.
        let movie = Clips.file(hash: hash, ext: ext, from: engine)
        asking.insert(held)
        queue.async { [weak self] in
            var image: NSImage?
            var made: Data?
            if let on = Filmstrip.header(of: file), abs(on.ratio - ratio) < 0.02,
               on.made == Filmstrip.generation {
                image = NSImage(contentsOf: file)
            } else if let movie, let bytes = Filmstrip.make(movie: movie, ratio: ratio, trim: trim) {
                made = bytes
                image = NSImage(data: bytes)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.asking.remove(held)
                guard let image else { self.none.insert(held); return }
                if let made {
                    // Filed the way the printed page files it, so the next
                    // export finds it made.
                    engine.call("strip", name, made.base64EncodedString())
                }
                self.pictures[held] = image
                self.arrivals += 1
            }
        }
        return nil
    }

    /// What the engine files this use's strip under. Asked again (at most
    /// every two seconds) when a use is not in the last answer — a clip just
    /// attached or a trim just moved.
    private func fileName(_ use: String, engine: Engine) -> String? {
        if let known = uses[use] { return known }
        guard Date().timeIntervalSince(usesAsked) > 2 else { return nil }
        usesAsked = Date()
        var fresh: [String: String] = [:]
        for one in engine.clipUses() {
            fresh[Self.useKey(one.stem, one.range)] = one.key
        }
        uses = fresh
        return fresh[use]
    }

    private static func useKey(_ hash: String, _ trim: (start: Double, end: Double)?) -> String {
        let stem = String(hash.prefix(32))
        guard let trim else { return stem }
        return "\(stem)|\(Int((trim.start * 1000).rounded()))|\(Int((trim.end * 1000).rounded()))"
    }
}
