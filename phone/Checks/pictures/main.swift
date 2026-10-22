import UIKit
import ImageIO
import UniformTypeIdentifiers

// What a photograph must weigh.
//
// On 2026-08-21 the phone stored his photographs at 4800×3600 from code that
// asked for 1600, because `UIGraphicsImageRenderer` renders at the *screen's*
// scale and his phone is 3×. Nothing was wrong on screen; the files were five
// times too big all the way to Google Drive. The only way to catch that is to
// measure the bytes, and the only place UIKit will draw is a simulator — so
// this half of the battery runs there.

var passed = 0, failed = 0

func check(_ what: String, _ body: () -> Bool) {
    if body() { passed += 1; print("  ✓ \(what)") }
    else { failed += 1; print("  ✗ \(what)") }
}

/// A stand-in for a photograph out of his camera: too big, and full of detail,
/// so a JPEG cannot flatter itself by encoding empty sky.
func photograph(_ size: CGSize) -> UIImage {
    let f = UIGraphicsImageRendererFormat.default()
    f.scale = 1
    f.opaque = true
    return UIGraphicsImageRenderer(size: size, format: f).image { c in
        for x in stride(from: 0, to: Int(size.width), by: 8) {
            for y in stride(from: 0, to: Int(size.height), by: 8) {
                UIColor(hue: CGFloat((x * 7 + y * 3) % 360) / 360, saturation: 0.8,
                        brightness: CGFloat((x ^ y) % 100) / 100, alpha: 1).setFill()
                c.fill(CGRect(x: x, y: y, width: 8, height: 8))
            }
        }
    }
}

// The check only means something on a 2× or 3× device — on a 1× one the bug is
// invisible because the wrong scale and the right one agree.
print("  · drawn on a \(UIScreen.main.scale)× screen")

let big = photograph(CGSize(width: 4032, height: 3024))

check("a frame comes out 1280 across, not 1280 times the screen") {
    guard let r = Media.shrunk(big, longest: 1280) else { return false }
    guard let stored = UIImage(data: r.data) else { return false }
    return Media.pixels(of: stored) == CGSize(width: 1280, height: 960)
}

check("a location photograph comes out 1600 across") {
    guard let r = Media.shrunk(big, longest: 1600) else { return false }
    guard let stored = UIImage(data: r.data) else { return false }
    return Media.pixels(of: stored) == CGSize(width: 1600, height: 1200)
}

check("what it says it made is what it made") {
    guard let r = Media.shrunk(big, longest: 1600) else { return false }
    guard let stored = UIImage(data: r.data) else { return false }
    return Media.pixels(of: stored) == r.pixels
}

check("a 4000-pixel photograph lands under 2 MB") {
    guard let r = Media.shrunk(big, longest: 1600) else { return false }
    print("    (\(r.data.count / 1024) KB)")
    return r.data.count < 2_000_000
}

check("re-encoding never makes a small picture bigger") {
    let small = photograph(CGSize(width: 40, height: 30))
    guard let bytes = small.jpegData(compressionQuality: 0.9) else { return false }
    guard let r = Media.shrunk(bytes, longest: 1600) else { return false }
    return r.data.count <= bytes.count
}

// ---- what must survive being picked ----------------------------------------
//
// Everything chosen on the phone used to go through `UIImage` and come out a
// JPEG, so a GIF he picked reached the Mac as one dead frame. These say it
// cannot happen again.

/// A real animated GIF, three frames of it.
func animated() -> Data? {
    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
        out, UTType.gif.identifier as CFString, 3, nil) else { return nil }
    CGImageDestinationSetProperties(dest, [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
    ] as CFDictionary)
    for shade in [UIColor.systemRed, .systemGreen, .systemBlue] {
        let frame = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 40)).image { c in
            shade.setFill(); c.fill(CGRect(x: 0, y: 0, width: 60, height: 40))
        }
        guard let cg = frame.cgImage else { return nil }
        CGImageDestinationAddImage(dest, cg, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]
        ] as CFDictionary)
    }
    guard CGImageDestinationFinalize(dest) else { return nil }
    return out as Data
}

check("a GIF goes in as a GIF and comes out as one") {
    guard let gif = animated() else { return false }
    guard let r = Media.shrunk(gif, longest: 1600) else { return false }
    return r.kind == "gif" && r.ext == "gif" && r.data == gif
}

check("a GIF still has all its frames afterwards") {
    guard let gif = animated() else { return false }
    guard let r = Media.shrunk(gif, longest: 1600) else { return false }
    return UIImage.moving(from: r.data)?.images?.count == 3
}

check("a photograph is still filed as a picture") {
    guard let jpeg = photograph(CGSize(width: 900, height: 600)).jpegData(compressionQuality: 0.9)
    else { return false }
    guard let r = Media.shrunk(jpeg, longest: 1600) else { return false }
    return r.kind == "image"
}

check("the bytes say what they are, whatever the file is called") {
    guard let gif = animated() else { return false }
    guard let jpeg = photograph(CGSize(width: 60, height: 40)).jpegData(compressionQuality: 0.9)
    else { return false }
    return Media.sniff(gif) == "gif" && Media.sniff(jpeg) == "image"
}

// ---- what a picture costs to put in a list ---------------------------------
//
// The shot list stuttered on his phone all through 2026-09-02, and the cause was
// that a thumbnail 54 points wide was being handed a proxy up to 2250×1500. The
// drawing machinery then resampled the whole photograph every time the row was
// composited — 9.15 ms a row against the 8.3 ms a frame is allowed — and forty
// of them held 253 MB. Decoded at the size it is drawn, the same row costs
// 0.19 ms and 2.5 MB.
//
// These guard the fix rather than the timing: a stopwatch on a shared machine
// says whatever the machine is busy with, but *how big the picture is* is a
// fact, and it is the whole of the bug.

// The largest proxy in "Call Her Back", which is the one that hurt.
let proxy = photograph(CGSize(width: 2250, height: 1500))
let proxyJPEG = proxy.jpegData(compressionQuality: 0.9)!

check("a list thumbnail is decoded small, not at full size") {
    // 54 points on a 3× screen, the shot list's own thumbnail.
    let wanted = Thumbnails.bucket(forSide: 54, scale: 3)
    guard let small = UIImage.moving(from: proxyJPEG, atMost: wanted) else { return false }
    return max(small.size.width, small.size.height) <= wanted
}

check("a picture asked for whole still comes back whole") {
    guard let whole = UIImage.moving(from: proxyJPEG, atMost: nil) else { return false }
    return whole.size.width == 2250 && whole.size.height == 1500
}

check("the sizes on the phone share one cached picture") {
    // 44, 52, 54 and 62 points are the four thumbnails the app draws. Four
    // buckets would mean four decodes and four copies of every photograph.
    let sizes = [44, 52, 54, 62].map { Thumbnails.bucket(forSide: CGFloat($0), scale: 3) }
    return Set(sizes).count == 1
}

check("a small picture is not enlarged on the way in") {
    let small = photograph(CGSize(width: 120, height: 90)).jpegData(compressionQuality: 0.9)!
    guard let out = UIImage.moving(from: small, atMost: 512) else { return false }
    return out.size.width == 120 && out.size.height == 90
}

check("a GIF still moves after being decoded small") {
    guard let gif = animated() else { return false }
    guard let out = UIImage.moving(from: gif, atMost: 128) else { return false }
    return out.images?.count == 3
}

check("a still decoded small is a still, not an animation of one") {
    guard let out = UIImage.moving(from: proxyJPEG, atMost: 256) else { return false }
    return out.images == nil
}


print("\nBold and italic on the Document page")
check("emphasis written for the Mac reads back as the same words, bold and italic where they were") {
    let runs = [DocumentRich.Run(text: "Slow ", bold: false, italic: false), DocumentRich.Run(text: "push", bold: true, italic: false),
                DocumentRich.Run(text: " to the\ndoor & ", bold: false, italic: false), DocumentRich.Run(text: "<hers>", bold: true, italic: true)]
    let plain = DocumentRich.plain(runs)
    let back = DocumentRich.runs(rich: DocumentRich.encode(runs), plain: plain)
    return back == DocumentRich.merged(runs)
}
check("emphasis that no longer says these words is not trusted, and plain words write nothing") {
    let runs = [DocumentRich.Run(text: "Hello", bold: true, italic: false)]
    return DocumentRich.runs(rich: DocumentRich.encode(runs), plain: "Hello there") == nil
        && DocumentRich.encode([DocumentRich.Run(text: "Hello")]) == ""
}

print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
