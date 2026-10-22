import UIKit
import AVFoundation
import CryptoKit
import CoreTransferable
import UniformTypeIdentifiers

/// Getting a photograph, a GIF or a clip down to something worth carrying.
///
/// **The bug this exists to prevent.** `UIGraphicsImageRenderer(size:)` renders
/// at the *screen's* scale. His iPhone is 3×, so asking for 1600 points quietly
/// produced 4800 pixels, and photographs the phone believed it had shrunk
/// reached Google Drive at 5.3 MB each. The code said 1600 and was not lying; it
/// was being overruled. Measured on a 4032×3024 photograph, on a 3× screen:
/// 6.6 MB before, 1.1 MB after, same dimensions asked for.
///
/// A size in points is a size on a screen. A photograph wants pixels.
///
/// **And the bug beside it.** Everything picked went through `UIImage` and came
/// out a JPEG, so a GIF he chose arrived on the Mac as one dead frame and a
/// clip could not be chosen at all. A file that already moves is passed through
/// exactly as it came.
enum Media {
    struct Ready {
        var data: Data
        var ext: String
        var pixels: CGSize
        /// What the engine should file it as: `image`, `gif` or `video`.
        var kind: String = "image"
        /// How long a clip runs. Zero for anything that does not run.
        var seconds: Double = 0
        /// **The still that stands for a clip**, as PNG bytes.
        ///
        /// A video draws as *nothing at all* without one, everywhere a picture
        /// is expected — the Mac's table, the phone's own list, every export.
        /// The Mac has made one on import since clips landed; the phone did
        /// not, and only offered to pick one by hand from the media viewer. So
        /// a clip added on the phone reached the Mac as a blank cell, which is
        /// exactly what he reported for shot 5B on 2026-08-31.
        ///
        /// Nil for anything that is not a clip: a photograph stands for itself.
        var poster: Data? = nil
        /// **What this was made from**, when it is a smaller copy of
        /// something. Ref 211. Empty for anything kept exactly as it arrived,
        /// whose own contents are already the answer.
        var source: String = ""
    }

    /// **What a file on disk hashes to, without reading it all into memory.**
    ///
    /// Ref 211. A clip off the camera roll is a hundred and fifty megabytes
    /// and this runs before anything else does, so loading the whole thing to
    /// hash it would be the very cost the question exists to avoid. Read in
    /// chunks, hashed as it goes.
    static func fingerprint(of url: URL) -> String? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        var hash = SHA256()
        while let chunk = try? file.read(upToCount: 1 << 20), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 1280 for a frame on a shot, 1600 for a location. A shot list is read at a
    /// glance and carried in a pocket; a 48-megapixel original in it costs a
    /// scout's whole afternoon of syncing and shows nothing more.
    static func shrunk(_ image: UIImage, longest: CGFloat) -> Ready? {
        draw(image, longest: longest)
    }

    /// The same, given the bytes — which allows the two things the picture alone
    /// cannot.
    ///
    /// **A GIF stays a GIF.** Drawing one into a renderer keeps the first frame
    /// and throws the rest away, which is how an animation becomes a still.
    ///
    /// **Never store something larger than it arrived.** Re-encoding can make a
    /// file bigger, and when it does the original is what gets kept.
    static func shrunk(_ data: Data, longest: CGFloat) -> Ready? {
        if sniff(data) == "gif" {
            let size = UIImage(data: data).map(pixels(of:)) ?? .zero
            return Ready(data: data, ext: "gif", pixels: size, kind: "gif")
        }
        guard let image = UIImage(data: data) else { return nil }
        guard let smaller = draw(image, longest: longest) else { return nil }
        guard smaller.data.count < data.count else {
            return Ready(data: data, ext: "jpg", pixels: pixels(of: image))
        }
        return smaller
    }

    /// A clip, re-encoded small enough to live in a project.
    ///
    /// **Why it is re-encoded at all.** A minute off his phone is 150 MB, and a
    /// project's media is carried whole to every device he owns — a scout's
    /// worth of those is a day of syncing. 720p is what a clip in a shot list is
    /// for: remembering the move, not grading it.
    ///
    /// It also has to fit through the engine, which takes bytes as text, so the
    /// file is briefly three times its size in memory. That alone rules out
    /// passing the original through.
    static func clip(at url: URL) async -> Ready? {
        let asset = AVURLAsset(url: url)
        let seconds = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0

        // `ClipEncoder` is the Mac's too — one bitrate for a clip whichever
        // door it came through. It replaced the 720p export preset on
        // 2026-09-15, which wrote seven to ten megabits a second.
        let out = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
        let made: ClipEncoder.Made? = await Task.detached(priority: .userInitiated) {
            try? ClipEncoder.shrink(url, to: out)
        }.value
        defer { try? FileManager.default.removeItem(at: out) }

        guard made != nil, let data = try? Data(contentsOf: out) else { return nil }

        // **Never store something larger than it arrived** — the same rule
        // photographs get, and it bites more often here. A clip already small
        // and well encoded comes back *bigger* from a fixed-bitrate export.
        // Keeping the original also means the same clip picked twice is the
        // same bytes twice, so the project holds one copy instead of two.
        let arrived = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
            .flatMap { $0 } ?? Int.max
        if data.count >= arrived {
            guard let original = try? Data(contentsOf: url) else { return nil }
            var kept = CGSize.zero
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let natural = try? await track.load(.naturalSize) {
                kept = natural
            }
            return Ready(data: original, ext: url.pathExtension.lowercased(),
                         pixels: kept, kind: "video", seconds: seconds,
                         poster: await firstFrame(of: asset, seconds: seconds))
        }

        var size = CGSize.zero
        if let track = try? await AVURLAsset(url: out).loadTracks(withMediaType: .video).first,
           let natural = try? await track.load(.naturalSize) {
            size = natural
        }
        // **What it was made from** — Ref 211. The small copy is filed under
        // its own contents, and one encoder run is not byte-for-byte the next,
        // so without this the same clip picked twice is two files. The clip
        // kept whole above needs none of it: its own name is already the
        // answer.
        return Ready(data: data, ext: "mp4", pixels: size, kind: "video",
                     seconds: seconds,
                     poster: await firstFrame(of: asset, seconds: seconds),
                     source: fingerprint(of: url) ?? "")
    }

    /// **A frame from the first half-second, to stand for the clip.**
    ///
    /// The twin of the Mac's, in `studio/Sources/Media.swift` — same moment,
    /// same reason. Half a second in rather than zero: the very first frame of
    /// a phone clip is often the black one before exposure settles.
    ///
    /// `appliesPreferredTrackTransform` is not optional. Without it a clip shot
    /// upright comes back on its side, because the rotation lives in the
    /// track's transform rather than in the pixels.
    static func firstFrame(of asset: AVAsset, seconds: Double) async -> Data? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let at = CMTime(seconds: min(0.5, max(seconds - 0.1, 0)), preferredTimescale: 600)
        guard let cg = try? await generator.image(at: at).image else { return nil }
        return poster(UIImage(cgImage: cg))
    }

    /// How big it actually is, in pixels rather than points.
    static func pixels(of image: UIImage) -> CGSize {
        CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    /// What the bytes actually are, read from the bytes — in the engine's own
    /// words, so the answer can be handed straight on.
    ///
    /// The name on a file is a label: a `.png` holding JPEG is a thing that
    /// happens. The case that matters here is a GIF, because it is the only
    /// picture where re-encoding silently destroys the point of it.
    static func sniff(_ data: Data) -> String {
        guard data.count >= 12 else { return "image" }
        let head = [UInt8](data.prefix(12))
        if head[0...2] == [0x47, 0x49, 0x46] { return "gif" }                 // GIF
        if head[4...7] == [0x66, 0x74, 0x79, 0x70] { return "video" }         // ....ftyp
        return "image"
    }

    /// **The still that stands for a clip**, as JPEG bytes.
    ///
    /// The engine's `poster` command writes what it is given under the clip's
    /// own hash with a `.jpg` on the end (since 2026-09-15; it was PNG, at
    /// eight times the size for a frame that has no transparency to keep).
    static func poster(_ image: UIImage, longest: CGFloat = 1280) -> Data? {
        let actual = pixels(of: image)
        let shrink = min(1, longest / max(actual.width, actual.height, 1))
        let size = CGSize(width: (actual.width * shrink).rounded(),
                          height: (actual.height * shrink).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.jpegData(compressionQuality: 0.82)
    }

    private static func draw(_ image: UIImage, longest: CGFloat) -> Ready? {
        let actual = pixels(of: image)
        let shrink = min(1, longest / max(actual.width, actual.height, 1))
        let size = CGSize(width: (actual.width * shrink).rounded(),
                          height: (actual.height * shrink).rounded())

        // **The line the whole thing turns on.** Without it the renderer works in
        // points at the screen's scale, and every number above becomes a third
        // of what is actually written.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let smaller = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = smaller.jpegData(compressionQuality: 0.9) else { return nil }
        return Ready(data: data, ext: "jpg", pixels: size)
    }
}

/// Anything picked, as a file on disk with the name it came with.
///
/// **Two reasons it is a file rather than bytes.**
///
/// A movie wants a path: it is re-encoded by reading through it, not by holding
/// all of it at once.
///
/// And a photograph wants its name. `loadTransferable(type: Data.self)` hands
/// over bytes and nothing else, which is why every picture picked from the
/// library reached the Mac called `pasted.jpg` — his ruling was that a
/// photograph *"should maintain its original name, on iOS and Mac, no matter
/// how it's imported or created."* A `FileRepresentation` is the way that
/// works: the `importing:` closure is given a URL, and the URL carries
/// `IMG_4523.HEIC`.
struct Picked: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .image) { picked in
            SentTransferredFile(picked.url)
        } importing: { received in
            try Picked(url: copy(received.file))
        }
        FileRepresentation(contentType: .movie) { picked in
            SentTransferredFile(picked.url)
        } importing: { received in
            try Picked(url: copy(received.file))
        }
    }

    /// Somewhere the app can read from, keeping the name it arrived with.
    ///
    /// The name has to survive the copy — it is the whole point — and two
    /// pictures called `IMG_4523.HEIC` must not land on each other, so the
    /// uniqueness goes in a folder rather than in the filename.
    private static func copy(_ file: URL) throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "picked-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appending(path: file.lastPathComponent)
        try FileManager.default.copyItem(at: file, to: copy)
        return copy
    }

    /// Cleans up after itself — the folder, not just the file.
    func discard() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    var isClip: Bool { MediaKind(url.pathExtension) == .clip }
}
