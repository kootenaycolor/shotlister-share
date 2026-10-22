import AppKit
import AVFoundation
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers
import Vision

/// Reads the burned-in strip on a viewfinder frame.
///
/// Artemis and Cadrage both stamp the lens onto the picture — "47mm" set large
/// on a black bar, with the camera and format beside it. That is data riding
/// inside an image, and retyping it is exactly the chore this app exists to
/// end. So the Mac reads it: Vision's text recognition over the frame, done
/// entirely on this machine, nothing leaving it. Ported from the old app's
/// `Viewfinder.swift`, unchanged in what it promises.
enum Viewfinder {
    /// The lens the frame says it was made with — "47mm" — or nil when the
    /// picture carries no legible focal length.
    static func lens(in image: NSImage, done: @escaping (String?) -> Void) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            done(nil)
            return
        }
        let request = VNRecognizeTextRequest { request, _ in
            let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                .compactMap { seen -> (text: String, height: CGFloat)? in
                    guard let top = seen.topCandidates(1).first else { return nil }
                    return (top.string, seen.boundingBox.height)
                }
            // The focal is the biggest "NNmm" in the picture — both apps set
            // it large on the strip — so the tallest match wins over any
            // stray number in the scene itself.
            var best: (value: String, height: CGFloat)?
            for line in lines {
                guard let match = line.text.range(
                    of: #"\b\d{1,3}(\.\d)?\s?mm\b"#,
                    options: [.regularExpression, .caseInsensitive]
                ) else { continue }
                let value = line.text[match].lowercased().replacingOccurrences(of: " ", with: "")
                if best == nil || line.height > best!.height {
                    best = (value, line.height)
                }
            }
            DispatchQueue.main.async { done(best?.value) }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            if (try? handler.perform([request])) == nil {
                DispatchQueue.main.async { done(nil) }
            }
        }
    }
}

/// How a picture — or a movie, or a gif — gets into the project: sized or
/// postered here, hashed and stored by the engine. One path for ⌘V, a drop
/// from the Finder, and the frames window's Add Image — so a frame cannot
/// land differently depending on which door it came through.
enum Ingest {
    /// The file extensions of things that move. The engine's own list
    /// (`MediaKind::guess_from_name`), mirrored.
    static func isMovie(_ ext: String) -> Bool {
        ["mp4", "mov", "m4v", "webm", "avi"].contains(ext.lowercased())
    }
    static func isMoving(_ ext: String) -> Bool {
        ext.lowercased() == "gif" || isMovie(ext)
    }

    // **Ask the engine first; guess from the name only when it did not say.**
    //
    // The engine has judged every file since Ref 148 and puts `kind` on
    // everything it hands over — image · gif · video · other. Two view-model
    // structs dropped it on the floor and re-derived the type from the
    // filename, which is how a GIF ended up being handed to a video player
    // that cannot decode one. The lists above stay for the cases with no kind
    // to hand (a bare hash and filename, an older project), and nothing else.
    static func isMovie(_ ext: String, kind: String?) -> Bool {
        if let kind, !kind.isEmpty { return kind == "video" }
        return isMovie(ext)
    }
    static func isGif(_ ext: String, kind: String?) -> Bool {
        if let kind, !kind.isEmpty { return kind == "gif" }
        return ext.lowercased() == "gif"
    }
    static func isMoving(_ ext: String, kind: String?) -> Bool {
        if let kind, !kind.isEmpty { return kind == "video" || kind == "gif" }
        return isMoving(ext)
    }

    /// The types a drop, the clipboard, or the panel may hand over.
    static let readableTypes: [UTType] = [
        .png, .jpeg, .heic, .gif, .tiff, .image,
        .mpeg4Movie, .quickTimeMovie, .movie,
    ]

    // ---- the doors ------------------------------------------------------

    /// Media on the clipboard, onto every given shot. False when the
    /// clipboard holds no media — the caller falls through to text.
    /// Never reads the clipboard during a checking run: it is his.
    @discardableResult
    static func fromPasteboard(onto rows: [ViewModel.Row], state: ShellState) -> Bool {
        if Launch.checking { return false }
        let board = NSPasteboard.general
        // Files copied in the Finder come as URLs — the only clipboard shape
        // a movie arrives in, and better than pixels for images too.
        if let urls = board.readObjects(forClasses: [NSURL.self]) as? [URL],
           !urls.isEmpty {
            let media = urls.filter { readable($0) }
            guard !media.isEmpty else { return false }
            for url in media {
                for row in rows { attach(url: url, to: row, state: state) }
            }
            return true
        }
        if let image = NSImage(pasteboard: board) {
            for row in rows { attach(image: image, to: row, state: state) }
            return true
        }
        return false
    }

    /// The frame picker, shared by the frames window and the cell menu.
    static func addViaPanel(to row: ViewModel.Row, state: ShellState) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = readableTypes
        panel.allowsMultipleSelection = true
        panel.message = "Pick the frames for shot \(row.number) — pictures, gifs, or clips"
        if panel.runModal() == .OK {
            for url in panel.urls {
                attach(url: url, to: row, state: state)
            }
        }
    }

    private static func readable(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return isMoving(ext)
            || ["png", "jpg", "jpeg", "heic", "webp", "tif", "tiff"].contains(ext)
    }

    // ---- what lands -----------------------------------------------------

    @discardableResult
    static func attach(url: URL, to row: ViewModel.Row, state: ShellState) -> Bool {
        let ext = url.pathExtension.lowercased()
        if isMovie(ext) {
            return attachMovie(url: url, to: row, state: state)
        }
        if ext == "gif" {
            return attachGif(url: url, to: row, state: state)
        }
        guard let image = NSImage(contentsOf: url) else {
            state.say("Can't read that file")
            return false
        }
        return attach(image: image, to: row, state: state,
                      named: url.lastPathComponent)
    }

    /// **What a file ends up called.**
    ///
    /// A file dropped, picked, or copied in the Finder keeps the name it came
    /// with — that is the whole of the rule, and it covers nearly everything
    /// that arrives. What is left over is the real no-name case: pixels off the
    /// clipboard, or an image dragged out of a web page, which carry bytes and
    /// nothing else. Those all used to land as `pasted.png`, so a location
    /// filled up with a dozen files of one name and Google Drive numbered them
    /// in arrival order.
    ///
    /// The stamp is the Finder's own answer to the same problem — a screenshot
    /// is `Screenshot 2026-08-22 at 14.03.12.png` — and it sorts by when the
    /// picture arrived, which is the only thing known about a picture with no
    /// name.
    ///
    /// **The extension is always the one actually written**, never the one it
    /// came with: a `.png` holding JPEG bytes is the confusion the viewer
    /// already has to sniff its way back out of.
    static func naming(_ given: String, ext: String) -> String {
        let stem = (given as NSString).deletingPathExtension
        return stem.isEmpty ? "\(stamp()).\(ext)" : "\(stem).\(ext)"
    }

    /// `Pasted 2026-08-22 at 14.03.12`. Fixed during a checking run, so running
    /// the battery twice does not produce two differently-named files.
    static func stamp() -> String {
        if Launch.checking { return "Pasted" }
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Pasted \(clock.string(from: Date()))"
    }

    /// Sizes, encodes, hands to the engine, and reads the viewfinder strip.
    /// The proxy is at most 1280 on the long side — a shot list is not a
    /// vault; the full-res original stays wherever it lives.
    @discardableResult
    static func attach(image: NSImage, to row: ViewModel.Row, state: ShellState,
                       named: String = "") -> Bool {
        guard let engine = state.engine else { return false }
        guard let made = compress(image, longest: 1600) else {
            state.say("Can't read that file")
            return false
        }
        guard let fresh = engine.paste(shot: row.shot, width: made.width,
                                       height: made.height, ext: made.ext,
                                       data: made.data,
                                       named: naming(named, ext: made.ext)) else {
            state.say("Couldn't add that image")
            return false
        }
        state.replace(fresh)
        readViewfinder(image, for: row, state: state)
        return true
    }

    /// A gif keeps its own bytes — resizing one would throw its animation
    /// away, and gifs are already small. The first frame reads for the
    /// viewfinder strip like anything else.
    private static func attachGif(url: URL, to row: ViewModel.Row, state: ShellState) -> Bool {
        guard let engine = state.engine,
              let data = try? Data(contentsOf: url),
              let image = NSImage(data: data) else {
            state.say("Can't read that file")
            return false
        }
        let px = image.size
        guard let fresh = engine.paste(shot: row.shot, width: Int(px.width),
                                       height: Int(px.height), ext: "gif",
                                       data: data, kind: "gif",
                                       named: naming(url.lastPathComponent, ext: "gif")) else {
            state.say("Couldn't add that gif")
            return false
        }
        state.replace(fresh)
        readViewfinder(image, for: row, state: state)
        return true
    }

    /// **A clip goes in small.** Ref 155.
    ///
    /// It used to go in exactly as it arrived, which for a phone clip is
    /// hundreds of megabytes — and a project is a folder that syncs, to his
    /// other Mac and through the bridge into Drive. So one dropped clip was a
    /// day of syncing. It is the same rule photographs have had since they
    /// were found to be going in eight times larger than they came: **a shot
    /// list is not a vault.** 720p is what a clip in a shot list is for —
    /// remembering the move, not grading it — and the file it came from is
    /// still sitting wherever you dragged it from.
    ///
    /// A poster frame from its first second stands for it wherever a picture
    /// is drawn, and is read for the viewfinder strip too: an Artemis clip
    /// carries the same burned-in lens a frame does.
    private static func attachMovie(url: URL, to row: ViewModel.Row, state: ShellState) -> Bool {
        guard let engine = state.engine,
              let arrived = try? Data(contentsOf: url) else {
            state.say("Can't read that file")
            return false
        }
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        let named = naming(url.lastPathComponent, ext: url.pathExtension.lowercased())
        let came = sha256Hex(arrived)

        // **The same clip twice is one file.** Ref 211. The small copy is
        // filed under its own contents, and one encoder run is not
        // byte-for-byte the next, so asking "is this clip here" by the clip's
        // own name would always have said no. The engine remembers what each
        // stored copy was made from, and answers on either.
        if let held = alreadyStored(came, engine: engine) {
            engine.call("use", row.shot, held)
            state.replace(engine.view())
            return true
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let poster: NSImage? = (try? generator.copyCGImage(
            at: CMTime(seconds: min(0.5, max(seconds - 0.1, 0)), preferredTimescale: 600),
            actualTime: nil)).map { NSImage(cgImage: $0, size: .zero) }

        // Shrinking a long clip takes real seconds, so it happens off the
        // window's own thread and lands when it is ready. **Except during a
        // checking run**, which drives the app with flags and reads what it
        // says before anything asynchronous could have finished — a check that
        // drops a clip and then asks whether it plays would be asking too
        // early, every time, and would look exactly like a broken feature.
        let land = { (small: (data: Data, ext: String)) in
            place(small.data, ext: small.ext, seconds: seconds, came: came,
                  named: named, poster: poster, to: row, state: state)
        }
        if Launch.checking {
            land(shrunk(url, arrived: arrived))
        } else {
            DispatchQueue.global(qos: .userInitiated).async {
                let small = shrunk(url, arrived: arrived)
                DispatchQueue.main.async { land(small) }
            }
        }
        return true
    }

    /// **A 720p copy at a shot list's bitrate**, or the clip untouched when
    /// shrinking would make it bigger.
    ///
    /// That last case is not rare and is the reason for the check: a clip that
    /// is already small and well encoded comes back *larger* from a
    /// fixed-bitrate pass. Storing that would be the photograph fault all
    /// over again, in the other medium.
    ///
    /// `ClipEncoder` (shared with the phone) does the work; it replaced the
    /// 720p export preset on 2026-09-15, which wrote seven to ten megabits a
    /// second where two and a half draws the same on any screen these are
    /// looked at on.
    static func shrunk(_ url: URL, arrived: Data) -> (data: Data, ext: String) {
        let whole = (data: arrived, ext: url.pathExtension.lowercased())
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        defer { try? FileManager.default.removeItem(at: out) }
        guard (try? ClipEncoder.shrink(url, to: out)) != nil,
              let smaller = try? Data(contentsOf: out),
              smaller.count < arrived.count else { return whole }
        return (smaller, "mp4")
    }

    /// Hands the bytes to the engine, attaches them, and stores the poster.
    ///
    /// `came` is what the clip hashed to before anything was done to it. The
    /// engine records it only when it differs from what is actually stored, so
    /// passing it always is right: a clip kept whole needs no such note, and
    /// the engine is the one place that can tell.
    private static func place(_ data: Data, ext: String, seconds: Double, came: String,
                              named: String, poster: NSImage?,
                              to row: ViewModel.Row, state: ShellState) {
        guard let engine = state.engine else { return }
        let size = poster?.size ?? .zero
        engine.call("paste", row.shot, String(Int(size.width)), String(Int(size.height)),
                    ext, data.base64EncodedString(), "video",
                    String(format: "%.3f", seconds), named, came)
        state.replace(engine.view())
        // **The poster is a JPEG**, stored beside the movie under the
        // movie's own hash with `.jpg` on the end; the engine files it and
        // every reader takes it (`poster`, `ffi/src/lib.rs`).
        //
        // **The movie's own hash, not the clip's.** The small copy is what is
        // stored, so it is the small copy the poster has to sit beside.
        if let poster, let made = Self.poster(poster) {
            engine.poster(hash: sha256Hex(data), data: made)
            readViewfinder(poster, for: row, state: state)
        }
    }

    /// Ref 211. The record this project already keeps for this file, or
    /// nothing.
    ///
    /// **A record, not the bytes.** Once the file is here, a second use of it
    /// is a record and nothing has to move — handing the same megabytes back
    /// through the door they came in would cost three times their size in
    /// text for no reason.
    static func alreadyStored(_ came: String, engine: Engine) -> String? {
        struct Reply: Decodable { var here: Bool; var media: String? }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: engine.call("have", came)),
              reply.here, let media = reply.media, !media.isEmpty else { return nil }
        return media
    }

    /// Downsampled PNG bytes, at most 1280 on the long side.
    /// **What a picture costs to keep.**
    ///
    /// Every project is a folder that syncs — the relay to his other Mac and
    /// his phone, and the Drive bridge to a folder other people can see. So the size of what
    /// goes in is not housekeeping; it is how long a shoot day takes to arrive
    /// on the second machine.
    ///
    /// Measured 2026-08-21, and it was worse than "we should get to that":
    /// **a 2.6 MB photograph off his phone was being stored as a 20.8 MB PNG.**
    /// Eight times the file it came from. Two separate faults, both here:
    ///
    /// 1. **The resize never resized.** `rep.size = px` sets the *size in
    ///    points* — a hint about how big to draw it. `representation(using:)`
    ///    encodes `pixelsWide × pixelsHigh`, which nobody had touched. So the
    ///    1280 cap this function has always claimed has never once been
    ///    applied. It has to be redrawn into a new bitmap of the wanted pixel
    ///    size, which is what happens below.
    /// 2. **A photograph was stored as PNG.** PNG is lossless, which is right
    ///    for a screenshot or a diagram and about ten times the cost for a
    ///    photograph of a room. JPEG at 0.82 is indistinguishable at the size
    ///    anybody looks at these.
    ///
    /// Alpha decides the format, not taste: something with real transparency
    /// stays PNG, because flattening it onto white is a change nobody asked
    /// for. Everything else becomes JPEG.
    struct Encoded {
        var data: Data
        var ext: String
        var width: Int
        var height: Int
    }

    /// **A clip's poster: always JPEG.** A video frame has no transparency
    /// worth keeping, and a PNG of one at 1600 wide is 1.6 MB where the JPEG
    /// is 200 KB — Call Her Back was carrying 50 MB of posters for 29 clips
    /// until 2026-09-15.
    static func poster(_ image: NSImage) -> Data? {
        compress(image, longest: 1600, opaque: true)?.data
    }

    static func compress(_ image: NSImage, longest: CGFloat, opaque: Bool = false) -> Encoded? {
        // **Drawn through CoreGraphics, not through `NSGraphicsContext`.**
        //
        // The first version of this built an `NSBitmapImageRep`, made an
        // `NSGraphicsContext` from it and called `image.draw(in:)`. It produced
        // a bitmap of the right size, in the right format, at a plausible
        // number of bytes — **and every pixel in it was black.** A 2.6 MB
        // photograph came out as a tidy 78 KB of nothing, which is the exact
        // shape of a bug that reads as a triumph: the measurement said 267×
        // smaller and the measurement was true.
        //
        // Found by looking at the pixels rather than at the file size. There is
        // a check for it now, and the check asserts *colour*, because size and
        // dimensions both passed.
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        let from = CGSize(width: source.width, height: source.height)
        guard from.width > 0, from.height > 0 else { return nil }

        let scale = min(1, longest / max(from.width, from.height))
        let width = Int(max(1, (from.width * scale).rounded()))
        let height = Int(max(1, (from.height * scale).rounded()))

        let alpha = !opaque && hasRealAlpha(source)
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast
                               : CGImageAlphaInfo.noneSkipLast).rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let drawn = context.makeImage() else { return nil }

        let rep = NSBitmapImageRep(cgImage: drawn)
        rep.size = NSSize(width: width, height: height)

        if alpha, let png = rep.representation(using: .png, properties: [:]) {
            return Encoded(data: png, ext: "png", width: width, height: height)
        }
        if let jpeg = rep.representation(using: .jpeg,
                                         properties: [.compressionFactor: 0.82]) {
            return Encoded(data: jpeg, ext: "jpg", width: width, height: height)
        }
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return Encoded(data: png, ext: "png", width: width, height: height)
    }

    /// Transparency that is actually used, rather than a channel that happens to
    /// be there. A screenshot is usually RGBA and entirely opaque, and turning
    /// those into 20 MB of PNG is most of what this function exists to stop.
    private static func hasRealAlpha(_ cg: CGImage) -> Bool {
        let info = cg.alphaInfo
        guard info == .premultipliedLast || info == .last
                || info == .premultipliedFirst || info == .first else { return false }
        guard let data = cg.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return true }
        let first = (info == .premultipliedFirst || info == .first)
        let across = max(1, cg.width / 64), down = max(1, cg.height / 64)
        for y in stride(from: 0, to: cg.height, by: down) {
            for x in stride(from: 0, to: cg.width, by: across) {
                let at = y * cg.bytesPerRow + x * (cg.bitsPerPixel / 8)
                if bytes[at + (first ? 0 : 3)] < 250 { return true }
            }
        }
        return false
    }

    /// A shot's frame is drawn at a few hundred points at most, so 1600 on the
    /// long side is already generous. A **location photograph** is looked at
    /// full-window on a retina Mac, so it gets 2560 — still about half a
    /// megabyte, against the twenty it used to cost.

    /// The engine stores by content hash; the poster has to land under the
    /// same address, so the shell computes the same standard SHA-256.
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// If a landed picture is a viewfinder frame, the lens comes off it.
    ///
    /// An empty lens cell fills itself and says so. A cell that already holds
    /// a different lens is left alone and told about — the frame informs, it
    /// never overwrites.
    static func readViewfinder(_ image: NSImage, for row: ViewModel.Row, state: ShellState) {
        Viewfinder.lens(in: image) { found in
            guard let found, let engine = state.engine else { return }
            // the list's own spelling wins, so "47 mm" and "47mm" cannot drift
            let known = engine.vocabulary("lens").first {
                $0.lowercased().replacingOccurrences(of: " ", with: "") == found
            }
            let value = known ?? found
            let current = state.view?.allRows.first { $0.id == row.id }?.lens ?? row.lens
            if current.isEmpty {
                state.replace(engine.set(shot: row.shot, field: "lens", value: value))
                state.say("Lens set to \(value)")
                FileHandle.standardError.write(Data("viewfinder: lens \(value)\n".utf8))
            } else if current.lowercased().replacingOccurrences(of: " ", with: "") != found {
                state.say("Frame says \(value), shot says \(current). Not changed.")
                FileHandle.standardError.write(Data("viewfinder: saw \(value), kept \(current)\n".utf8))
            }
        }
    }

    /// Plays a stored movie (or opens a gif) the way the Mac already knows
    /// how: the bytes go to a scratch file and the file opens in whatever
    /// plays it. A player inside the frames window can come later; a working
    /// door beats a broken theatre.
    static func openMoving(_ still: ViewModel.Still, state: ShellState) {
        guard let bytes = state.engine?.proxy(hash: still.hash, ext: still.ext) else {
            state.say("Couldn't read the clip")
            return
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shotlister-play", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(still.hash).\(still.ext)")
        do {
            try bytes.write(to: file)
            NSWorkspace.shared.open(file)
        } catch {
            state.say("Couldn't open the clip")
        }
    }
}

/// One reading of a drop, shared by a storyboard card, a table row, and the
/// frames window. `loadObject` rather than raw item parsing — the raw path
/// showed the drop cursor and then dropped nothing; this is the old app's
/// proven reader.
enum Drops {
    static func take(_ providers: [NSItemProvider], onto row: ViewModel.Row,
                     state: ShellState) -> Bool {
        var took = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { Ingest.attach(url: url, to: row, state: state) }
                }
                took = true
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                    guard let image = object as? NSImage else { return }
                    DispatchQueue.main.async { Ingest.attach(image: image, to: row, state: state) }
                }
                took = true
            }
        }
        return took
    }
}
