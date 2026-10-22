import AppKit
import AVFoundation
import ImageIO

/// **A clip, on paper, that looks like it moves.**
///
/// His ask, 2026-09-01 (Ref 514): a video in an exported PDF is one frozen
/// still, so nothing on the page says the shot moves at all. His own idea was
/// to turn the clip into a GIF — and that was checked before anything was
/// built, through the app's own renderer: WebKit rasterises a fifty-frame GIF
/// to frame one, and the PDF that comes out is indistinguishable from the
/// still we already drew. **No PDF viewer animates anything.** Adobe's own
/// rich-media annotation plays a video in Acrobat and nowhere else, and it
/// puts the whole file inside the document, which is the one thing he asked
/// not to happen.
///
/// So the motion goes *into the picture*: four moments from across the clip,
/// laid two by two in the same box a single frame filled.
///
/// **Two by two, not four across.** Every printed page draws a frame in the
/// project's own ratio — a card crops to it, a table row shows it whole — and
/// four quadrants of ratio *r* make a rectangle of ratio *r*, so the strip is
/// the same shape a poster is and every page that already draws one needs no
/// change at all. A row of four would be seven times wider than tall: a thin
/// band in a table, and in a storyboard card cropped down to the middle two.
///
/// **The same pixels, not four times as many.** Each quadrant is half the
/// linear size, so a strip weighs what the still weighed and the PDF does not
/// grow — the whole point of the ask.
enum Filmstrip {
    /// How many moments. Four is the grid; changing it means changing the
    /// grid, which is why it is not a parameter.
    private static let moments = 4

    /// Where in the clip to look. Not 0 and not 1: the first and last frames
    /// of a clip are the two most likely to be black.
    private static let atFraction: [Double] = [0.08, 0.36, 0.64, 0.92]

    /// The gutter between quadrants, as a fraction of the longest side.
    ///
    /// **It was three pixels flat until the arrows arrived.** Three is enough
    /// to read as four pictures rather than one wide one, and far too little
    /// to put a mark in. It is a fraction now so the arrows keep their shape
    /// whatever size the strip is made at.
    private static let gutterShare: CGFloat = 0.028

    /// **Which drawing of the strip this is.** Written into the file's header
    /// and read back by `ensure`, so a strip made before the arrows were
    /// redrawn is remade once rather than kept for as long as its shape still
    /// matches. Bump it whenever the picture changes for a reason the shape
    /// cannot tell.
    static let generation = "shotlister-strip-8"

    // ------------------------------------------------------------- making

    /// Four moments of `movie`, two by two, in a rectangle of `ratio`.
    ///
    /// `nil` when the clip will not give up four frames — a poster is better
    /// than three quarters of a strip, and the engine falls back to one on
    /// its own.
    /// **`trim` is the part of the clip he kept**, in seconds — his report,
    /// 2026-09-01: *"the 4 frames that are generated from videos for export
    /// need to respect the trim boundaries of the clip."* The four moments
    /// are spread across that range, so a thirty-second take cut to two
    /// seconds prints two seconds. `nil` is the whole file, exactly as before.
    ///
    /// The trim is a fact about *this use* of the clip rather than about the
    /// file, which is why the caller has to say: one movie on two shots can
    /// be cut two different ways and owes two strips.
    static func make(movie: URL, ratio: CGFloat, trim: (start: Double, end: Double)? = nil,
                     longest: CGFloat = 1600) -> Data? {
        guard ratio > 0 else { return nil }
        let asset = AVURLAsset(url: movie)
        let whole = CMTimeGetSeconds(asset.duration)
        guard whole.isFinite, whole > 0.2 else { return nil }

        // A trim is clamped to the file it is on: a range remembered before
        // the clip was replaced could otherwise ask for a moment past the end,
        // and `copyCGImage` answers that with nothing at all — which would
        // silently drop the strip and print a single frame instead.
        let from = max(0, min(trim?.start ?? 0, whole))
        let to = min(max(trim?.end ?? whole, from + 0.2), whole)
        let seconds = to - from
        guard seconds > 0.2 else { return nil }

        let generator = AVAssetImageGenerator(asset: asset)
        // A clip shot upright comes back on its side without this: the
        // rotation lives in the track's transform, not in the pixels. The
        // same line, for the same reason, as the poster maker in `Shell`.
        generator.appliesPreferredTrackTransform = true
        // Exact frames are slow and nobody can tell a quarter second. Whole
        // seconds, though, would collapse two moments into one frame on a
        // short clip.
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

        // White, not clear: this ends up on a printed page, and the gutter is
        // the paper showing through.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: pixels))
        context.interpolationQuality = .high

        let gutter = (max(pixels.width, pixels.height) * gutterShare).rounded()
        let cell = CGSize(width: (pixels.width - gutter) / 2,
                          height: (pixels.height - gutter) / 2)
        // Reading order — left to right, top row first — so the four moments
        // run the way a contact sheet does. CoreGraphics counts up from the
        // bottom, hence the flipped rows.
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
        // **JPEG, though the poster is PNG.** The poster's format is forced —
        // it is filed under `.png` and read back by that name. A strip is
        // filed under `strip`, which says nothing about what is inside it, so
        // it can be the format four photographs actually want: the same grid
        // is 470 KB as a PNG and about a fifth of that as a JPEG, and every
        // one of those bytes would have gone to the relay and on to his
        // phone.
        //
        // Written through `CGImageDestination` rather than `NSBitmapImageRep`
        // for one reason: the generation goes into the header, in the TIFF
        // `Software` field, where `ensure` can read it without decoding.
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

    /// **Which order the four moments happen in.** His ask, 2026-09-01: *"it
    /// would be great if there could be arrows pointing to the next photo to
    /// show it's a sequence."* Two by two reads as four unrelated pictures
    /// otherwise — nothing in a grid says top-left comes first.
    ///
    /// **Numbers, not arrows.** The first drawing was a grey triangle in each
    /// gutter, invisible on a printed page; the second was storyboard arrows
    /// reaching onto the frames, with curls to carry the eye from one row to
    /// the next — and drawn, they were a lot of ink saying one small thing.
    /// His call, 2026-09-20: *"or we just number them… could be a lot
    /// better."* A `1` to `4` in the corner of each moment says the whole of
    /// it in one mark, at any size, without lying on anything he framed.
    ///
    /// The badge is drawn the way a storyboard mark is — pale disc, dark
    /// outline, a whisper of shadow — so it reads over a bright sky and a
    /// night exterior alike.
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
        let font = NSFont.systemFont(ofSize: across * 0.58, weight: .bold)
        let ink: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
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
            // In an unflipped context `draw(at:)` puts the line box's bottom
            // at the point, so the baseline sits `descender` above it (the
            // descender is negative). Centre the cap height on the disc, not
            // the line box — a digit has no descender to balance.
            let baseline = disc.midY - font.capHeight / 2
            digit.draw(at: CGPoint(x: disc.midX - width / 2, y: baseline + font.descender))
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The rectangle to draw `frame` in so it covers `box` whole, centred —
    /// `object-fit: cover`, in CoreGraphics. Anything else letterboxes, and
    /// four letterboxed frames on a page read as a mistake.
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

    /// **Make the strips this film's printed pages will ask for.**
    ///
    /// Called on the way into every printed page, because that is the one
    /// funnel every PDF in the app goes through. Cheap when there is nothing
    /// to do — it looks at the header of each strip already on disk and
    /// leaves it alone when its shape still matches the project's.
    ///
    /// **It asks the engine what to make, rather than reading the folder.**
    /// It used to walk `media/proxies` and make one strip per movie file,
    /// which cannot be right: a trim belongs to the *use* of a clip, so one
    /// file attached to two shots with two different in and out points owes
    /// two strips. Only the engine knows the uses, and only the engine works
    /// out what each one is filed under (`package::strip_key`) — so nothing
    /// on this side computes a name, and there is no second copy of that
    /// arithmetic to fall out of step with the reader.
    ///
    /// **Stale is possible and has to be checked**, not assumed: the frame
    /// ratio is a project setting he can change from the Storyboard bar, and
    /// a strip built for 2.39 in a 16:9 film would be cropped to ribbons by
    /// the very card it is drawn in.
    static func ensure(engine: Engine) {
        for job in owed(engine: engine) {
            guard let made = make(movie: job.movie, ratio: job.ratio, trim: job.trim) else {
                couldNot.insert(job.key)
                continue
            }
            engine.call("strip", job.key, made.base64EncodedString())
        }
    }

    /// **The same strips, made off the main thread.** His report,
    /// 2026-10-15: every slider move in the export window froze the app with
    /// a rainbow wheel. On Call Her Back every printed page spent 4.5 seconds
    /// here, on the main thread, pulling frames out of forty clips — and the
    /// preview prints three pages per change. The frames are now pulled on a
    /// queue of their own; only the filing (one engine call per strip, a few
    /// milliseconds) comes back to the main thread, and `done` runs after it,
    /// so the `ensure` inside `printPage` then finds nothing to do.
    static func prepare(engine: Engine, ratio: Double? = nil, done: @escaping () -> Void) {
        let jobs = owed(engine: engine, ratio: ratio)
        guard !jobs.isEmpty else { return done() }
        making.async {
            let made = jobs.map { job in
                (job.key, make(movie: job.movie, ratio: job.ratio, trim: job.trim))
            }
            DispatchQueue.main.async {
                for (key, bytes) in made {
                    if let bytes { engine.call("strip", key, bytes.base64EncodedString()) }
                    else { couldNot.insert(key) }
                }
                done()
            }
        }
    }

    /// `--stripcheck` — **a strip made here reads back as made here.** Four
    /// small flat pictures through the real `compose`, written to a scratch
    /// file and read back by the real `header`. When this says "none", every
    /// strip on the Mac is remade on every printed page — the freeze of
    /// 2026-10-15, which the operating system caused by no longer handing
    /// the header's TIFF word back.
    static func selfCheck() {
        func flat(_ grey: CGFloat) -> CGImage? {
            guard let c = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            c.setFillColor(CGColor(gray: grey, alpha: 1))
            c.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
            return c.makeImage()
        }
        let frames = [0.2, 0.4, 0.6, 0.8].compactMap { flat($0) }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("stripcheck-\(UUID().uuidString).strip")
        defer { try? FileManager.default.removeItem(at: file) }
        guard let data = compose(frames, ratio: 1.33, longest: 320), (try? data.write(to: file)) != nil,
              let held = header(of: file) else {
            FileHandle.standardError.write(Data("strip header: unreadable\n".utf8)); return
        }
        FileHandle.standardError.write(Data(String(
            format: "strip header: made %@ ratio %.2f\n", held.made ?? "none", held.ratio).utf8))
    }

    /// One strip still to make: which use it is filed under, and from what.
    struct Owed {
        let key: String
        let movie: URL
        let ratio: CGFloat
        let trim: (start: Double, end: Double)?
    }

    /// **A strip that could not be made is not tried again on every page.**
    /// A clip that will not give up four frames (too short, or a file
    /// AVFoundation cannot read) used to be decoded afresh on every printed
    /// page, every slider move. Remembered for the session, by key; a new
    /// trim is a new key, so changing the clip still gets a fresh try.
    private static var couldNot: Set<String> = []
    private static let making = DispatchQueue(label: "shotlister.filmstrip", qos: .userInitiated)

    /// What is missing or stale, worked out from the strip headers alone.
    /// Main thread; cheap — a directory listing and one header per strip.
    static func owed(engine: Engine, ratio given: Double? = nil) -> [Owed] {
        // The ratio, when the caller already holds the film: asking the
        // engine for the whole view to read one number is most of this
        // function's time on a big film.
        let ratio = CGFloat(given ?? engine.view()?.project.ratio ?? 2.39)
        guard ratio > 0 else { return [] }
        let uses = engine.clipUses()
        guard !uses.isEmpty else { return [] }
        let proxies = engine.folder.appending(path: "media/proxies")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: proxies.path)) ?? []
        let movies = files.filter {
            ["mp4", "mov", "m4v"].contains(($0 as NSString).pathExtension.lowercased())
        }

        var out: [Owed] = []
        var said: [String] = []
        for use in uses where !couldNot.contains(use.key) {
            let strip = proxies.appending(path: use.key + ".strip")
            let held = header(of: strip)
            if let held, abs(held.ratio - ratio) < 0.02, held.made == generation {
                continue
            }
            // The movie is filed under the bare hash whatever it is called;
            // the strip is filed under the key, which folds in the trim.
            guard let file = movies.first(where: {
                ($0 as NSString).deletingPathExtension == use.stem
            }) else { continue }
            if Launch.checking {
                said.append(held == nil ? "\(use.key) missing"
                            : String(format: "%@ ratio %.3f/%.3f made %@", use.key, held!.ratio, ratio,
                                     held!.made ?? "-"))
            }
            out.append(Owed(key: use.key, movie: proxies.appending(path: file), ratio: ratio, trim: use.range))
        }
        if Launch.checking, !out.isEmpty {
            FileHandle.standardError.write(Data(
                "strips owed: \(out.count) of \(uses.count): \(said.prefix(6).joined(separator: "; "))\n".utf8))
        }
        return out
    }

    /// The shape of a picture on disk and which drawing made it, without
    /// decoding it — `CGImageSource` reads the header and stops. Cheaper than
    /// making an image to ask it how wide it is, and it does not care which
    /// format the strip was written in. `made` is nil for a strip from before
    /// the generation was written, which is exactly a strip to remake.
    static func header(of file: URL) -> (ratio: CGFloat, made: String?)? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0, height > 0
        else { return nil }
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        return (width / height, tiff?[kCGImagePropertyTIFFSoftware] as? String ?? marker(in: file))
    }

    /// **The generation, read off the file's first bytes.** Measured
    /// 2026-10-15 on macOS 27: ImageIO no longer hands back the TIFF
    /// dictionary of a strip it wrote itself, so every strip read as
    /// "made by nobody", was remade on every printed page — forty clips,
    /// 4.5 seconds, on the main thread, three times per slider move — and
    /// that was the rainbow wheel. The word is still in the file's header;
    /// this finds it there.
    static func marker(in file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 16 * 1024),
              let found = head.range(of: Data("shotlister-strip-".utf8)) else { return nil }
        var end = found.upperBound
        while end < head.endIndex, let c = Optional(head[end]),
              (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) {
            end += 1
        }
        return String(data: head[found.lowerBound..<end], encoding: .ascii)
    }
}
