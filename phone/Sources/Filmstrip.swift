import AVFoundation
import ImageIO
import UIKit

/// **A clip, on paper, that looks like it moves** — the Mac's four-moment
/// strip (Ref 514), made on the phone too (Ref 530).
///
/// The strip is filed beside the clip and travels with everything else, so a
/// clip the Mac has printed already shows four moments here. What the phone
/// could not do was make one: a clip that only ever lived on the phone
/// printed as a single frozen still until the Mac exported that film once.
/// This is `studio/Sources/Filmstrip.swift`, line for line where the two
/// platforms agree, so the strip the phone makes is the strip the Mac makes.
///
/// Four moments from across the clip, two by two, in the film's own ratio —
/// so every page that draws a poster draws a strip with no change. Each
/// quadrant is half the linear size, so a strip weighs what a still weighs.
enum Filmstrip {
    private static let moments = 4
    /// **Which drawing of the strip this is.** Written into the file's header
    /// and read back by `ensure`, so a strip made before the numbers arrived
    /// is remade once rather than kept for as long as its shape still
    /// matches. The Mac's word, exactly — the two write the same file.
    private static let generation = "shotlister-strip-8"

    /// Not 0 and not 1: the first and last frames are the two most likely to
    /// be black.
    private static let atFraction: [Double] = [0.08, 0.36, 0.64, 0.92]
    /// The gutter between quadrants, as a fraction of the longest side.
    private static let gutterShare: CGFloat = 0.028

    // ------------------------------------------------------------- making

    /// Four moments of `movie`, two by two, in a rectangle of `ratio`.
    /// `trim` is the part of the clip he kept, in seconds; `nil` is the whole
    /// file. `nil` back when the clip will not give up four frames — a poster
    /// is better than three quarters of a strip.
    static func make(movie: URL, ratio: CGFloat, trim: (start: Double, end: Double)? = nil,
                     longest: CGFloat = 1600) -> Data? {
        guard ratio > 0 else { return nil }
        let asset = AVURLAsset(url: movie)
        let whole = CMTimeGetSeconds(asset.duration)
        guard whole.isFinite, whole > 0.2 else { return nil }

        // A trim is clamped to the file it is on: a range remembered before
        // the clip was replaced could otherwise ask for a moment past the end.
        let from = max(0, min(trim?.start ?? 0, whole))
        let to = min(max(trim?.end ?? whole, from + 0.2), whole)
        let seconds = to - from
        guard seconds > 0.2 else { return nil }

        let generator = AVAssetImageGenerator(asset: asset)
        // A clip shot upright comes back on its side without this.
        generator.appliesPreferredTrackTransform = true
        let slack = CMTime(seconds: 0.25, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = slack
        generator.requestedTimeToleranceAfter = slack

        var frames: [CGImage] = []
        for fraction in atFraction {
            let into = min(max(seconds * fraction, 0), seconds - 0.05)
            let at = CMTime(seconds: from + into, preferredTimescale: 600)
            guard let frame = try? generator.copyCGImage(at: at, actualTime: nil) else {
                return nil
            }
            frames.append(frame)
        }
        guard frames.count == moments else { return nil }
        return compose(frames, ratio: ratio, longest: longest)
    }

    /// The grid itself: four pictures, each filling its quadrant, on white.
    private static func compose(_ frames: [CGImage], ratio: CGFloat, longest: CGFloat) -> Data? {
        let width = ratio >= 1 ? longest : longest * ratio
        let height = ratio >= 1 ? longest / ratio : longest
        let pixels = CGSize(width: max(2, width.rounded()), height: max(2, height.rounded()))

        guard let context = CGContext(
            data: nil,
            width: Int(pixels.width), height: Int(pixels.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        // White, not clear: the gutter is the paper showing through.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: pixels))
        context.interpolationQuality = .high

        let gutter = (max(pixels.width, pixels.height) * gutterShare).rounded()
        let cell = CGSize(width: (pixels.width - gutter) / 2,
                          height: (pixels.height - gutter) / 2)
        // Reading order — left to right, top row first. CoreGraphics counts
        // up from the bottom, hence the flipped rows.
        let corners = [
            CGPoint(x: 0, y: cell.height + gutter),
            CGPoint(x: cell.width + gutter, y: cell.height + gutter),
            CGPoint(x: 0, y: 0),
            CGPoint(x: cell.width + gutter, y: 0),
        ]
        for (frame, corner) in zip(frames, corners) {
            let box = CGRect(origin: corner, size: cell)
            context.saveGState()
            context.clip(to: box)
            context.draw(frame, in: filling(box, with: frame))
            context.restoreGState()
        }

        sequenceNumbers(in: context, cell: cell, gutter: gutter, size: pixels)

        guard let made = context.makeImage() else { return nil }
        // JPEG, though the poster is PNG: a strip is filed under `strip`, so
        // it can be the format four photographs actually want — a fifth of
        // the bytes, and every one of them goes to the relay. Written through
        // `CGImageDestination` so the generation goes into the header, in the
        // TIFF `Software` field, where `ensure` can read it without decoding.
        let out = NSMutableData()
        guard let sink = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(sink, made, [
            kCGImageDestinationLossyCompressionQuality: 0.82,
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFSoftware: generation],
        ] as CFDictionary)
        guard CGImageDestinationFinalize(sink) else { return nil }
        return out as Data
    }

    /// **Which order the four moments happen in.** Numbers, not arrows — his
    /// call, 2026-09-20: a grey triangle in each gutter was invisible on a
    /// printed page. A `1` to `4` in the corner of each moment says the whole
    /// of it in one mark, at any size, without lying on anything he framed.
    /// The badge is drawn the way a storyboard mark is — pale disc, dark
    /// outline, a whisper of shadow — so it reads over a bright sky and a
    /// night exterior alike. The Mac's `sequenceNumbers`, in UIKit.
    private static func sequenceNumbers(in context: CGContext, cell: CGSize,
                                        gutter: CGFloat, size: CGSize) {
        // Sized off the strip, with a floor: a table draws the whole strip
        // about an inch wide, and a badge that is a fraction of a
        // wide-screen row's height would vanish there.
        let across = max(min(cell.width, cell.height) * 0.20, size.width * 0.065)
        guard across > 6 else { return }
        let inset = across * 0.30
        let outline = across * 0.06
        // CoreGraphics counts up from the bottom: the top row is the high one,
        // and a badge sits at the top-left of its moment.
        let corners = [
            CGPoint(x: 0, y: cell.height + gutter),
            CGPoint(x: cell.width + gutter, y: cell.height + gutter),
            CGPoint(x: 0, y: 0),
            CGPoint(x: cell.width + gutter, y: 0),
        ]
        let font = UIFont.systemFont(ofSize: across * 0.58, weight: .bold)
        let ink: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]

        // UIKit draws text in a flipped space; the strip's context is not.
        // Pushing the context and flipping for each badge keeps the digits
        // the right way up without turning the pictures over.
        UIGraphicsPushContext(context)
        for (index, corner) in corners.enumerated() {
            let disc = CGRect(x: corner.x + inset,
                              y: corner.y + cell.height - inset - across,
                              width: across, height: across)
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -across * 0.03),
                              blur: across * 0.10,
                              color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fillEllipse(in: disc)
            context.restoreGState()
            context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            context.setLineWidth(outline)
            context.strokeEllipse(in: disc.insetBy(dx: outline / 2, dy: outline / 2))

            let digit = NSAttributedString(string: String(index + 1), attributes: ink)
            let width = digit.size().width
            context.saveGState()
            // Flip around the disc's centre so the glyph reads upright.
            context.translateBy(x: 0, y: disc.midY * 2)
            context.scaleBy(x: 1, y: -1)
            // Centre the cap height on the disc, not the line box — a digit
            // has no descender to balance. In the flipped space the line box's
            // top sits at the point given.
            let top = disc.midY - font.capHeight / 2 - (font.ascender - font.capHeight)
            digit.draw(at: CGPoint(x: disc.midX - width / 2, y: top))
            context.restoreGState()
        }
        UIGraphicsPopContext()
    }

    /// `object-fit: cover`, in CoreGraphics.
    private static func filling(_ box: CGRect, with frame: CGImage) -> CGRect {
        let from = CGSize(width: CGFloat(frame.width), height: CGFloat(frame.height))
        guard from.width > 0, from.height > 0 else { return box }
        let scale = max(box.width / from.width, box.height / from.height)
        let size = CGSize(width: from.width * scale, height: from.height * scale)
        return CGRect(
            x: box.midX - size.width / 2,
            y: box.midY - size.height / 2,
            width: size.width, height: size.height
        )
    }

    // ------------------------------------------------------------- keeping

    /// A clip's use, as the engine lists them: where the movie is, what its
    /// strip is filed under, and the kept range.
    struct ClipUse: Decodable {
        let stem: String
        let key: String
        let start: Double
        let end: Double
        var range: (start: Double, end: Double)? { end > start ? (start, end) : nil }
    }

    /// **Make the strips this film's printed pages will ask for.**
    ///
    /// Cheap when there is nothing to do — it reads the header of each strip
    /// already on disk and leaves it alone when its shape still matches the
    /// film's. It asks the engine which uses want a strip, so a clip on two
    /// shots at two trims owes two, and nothing here computes a name.
    ///
    /// **Ahead of time, and off the main thread** — Ref 1046. This used to
    /// run synchronously on the way into every export: twenty-six clips
    /// decoded four frames each, on the main thread, with the export's wheel
    /// frozen for the duration — five seconds on the Mac's simulator, most
    /// of a minute on a phone. Now `Session` asks for it when a film opens
    /// and whenever a clip is attached or trimmed, so by the time he opens
    /// Export the strips are already there; and the frames are pulled out of
    /// the movie on a background task either way, with only the hand-over to
    /// the engine on the main actor. The export still calls this first, as
    /// the safety net — a film whose ratio just changed owes new strips —
    /// and finds nothing to do almost every time.
    ///
    /// **One run at a time.** A second caller waits for the first and then
    /// makes its own (usually empty) pass, so an export opened while the
    /// film's own run is half-way never prints half the strips.
    @MainActor
    static func ensure(engine: Engine, folder: URL, ratio: Double) async {
        if let running { await running.value }
        let task = Task<Void, Never> { @MainActor in
            await makeMissing(engine: engine, folder: folder, ratio: ratio)
        }
        running = task
        await task.value
        if running == task { running = nil }
    }

    @MainActor private static var running: Task<Void, Never>?

    @MainActor
    private static func makeMissing(engine: Engine, folder: URL, ratio: Double) async {
        let ratio = CGFloat(ratio)
        guard ratio > 0 else { return }
        let reply = engine.raw("clips")
        guard let uses = try? JSONDecoder().decode([ClipUse].self, from: reply),
              !uses.isEmpty else { return }
        // **Which strips are owed, worked out away from the screen.** Reading
        // each strip's header and asking iCloud whether each movie is really
        // here is a disk question per clip — 42 on Call Her Back, a quarter of
        // a second of frozen screen every time a film opened (2026-10-06).
        let owed = await Task.detached(priority: .utility) {
            owedStrips(uses, in: folder, ratio: ratio)
        }.value

        for (key, movie, range) in owed {
            // The slow part — four frames out of a movie — away from the
            // main thread. `make` is AVFoundation and CoreGraphics only.
            let made = await Task.detached(priority: .utility) {
                make(movie: movie, ratio: ratio, trim: range)
            }.value
            guard let made else { continue }
            _ = engine.raw("strip", key, made.base64EncodedString())
        }
        // Preview Stills draws strips on screen; tell it new ones are here.
        if !owed.isEmpty { NotificationCenter.default.post(name: Filmstrip.made, object: nil) }
    }

    /// Posted when strips have been filed, so tiles waiting on one redraw.
    static let made = Notification.Name("shotlister.strips.made")

    /// The clip uses whose strip is missing or out of date, with the movie
    /// each is made from. Touches nothing but the disk.
    private nonisolated static func owedStrips(_ uses: [ClipUse], in folder: URL, ratio: CGFloat)
        -> [(key: String, movie: URL, range: (start: Double, end: Double)?)] {
        let proxies = folder.appending(path: "media/proxies")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: proxies.path)) ?? []
        let movies = files.filter {
            ["mp4", "mov", "m4v"].contains(($0 as NSString).pathExtension.lowercased())
        }
        var owed: [(key: String, movie: URL, range: (start: Double, end: Double)?)] = []
        for use in uses {
            let strip = proxies.appending(path: use.key + ".strip")
            if let held = header(of: strip), abs(held.ratio - ratio) < 0.02,
               held.made == generation {
                continue
            }
            guard let file = movies.first(where: {
                ($0 as NSString).deletingPathExtension == use.stem
            }) else { continue }
            // The bytes have to be on this phone, not just named in the folder.
            let movie = proxies.appending(path: file)
            guard Cloud.here(movie) else { continue }
            owed.append((use.key, movie, use.range))
        }
        return owed
    }

    /// The shape of a picture on disk and which drawing made it, without
    /// decoding it — `CGImageSource` reads the header and stops. `made` is nil
    /// for a strip from before the generation was written, which is exactly a
    /// strip to remake.
    private static func header(of file: URL) -> (ratio: CGFloat, made: String?)? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0, height > 0
        else { return nil }
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        return (width / height, tiff?[kCGImagePropertyTIFFSoftware] as? String)
    }
}
