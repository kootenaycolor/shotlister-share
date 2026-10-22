import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// A picture that moves, if it is the kind that moves.
///
/// SwiftUI's `Image` draws one representation and stops, so an animated GIF put
/// into one is perfectly animated and perfectly still on screen — the file *is*
/// moving and the app is not showing it, which is a confusing thing to look at.
///
/// `UIImageView` will animate an image built from all its frames, so this is the
/// thinnest possible wrapper around one: no controls, no state, the frames going
/// round.
struct Moving: UIViewRepresentable {
    let image: UIImage
    var fill: Bool = true

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.image = image
        view.contentMode = fill ? .scaleAspectFill : .scaleAspectFit
        view.clipsToBounds = true
        // Never let the view's own size be the picture's size: it lives inside a
        // frame that has already been decided, and an image view that argues
        // with its container is how a thumbnail ends up the size of a poster.
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        if view.image !== image { view.image = image }
    }
}

/// How big a picture needs to be decoded to be drawn in a box `side` points
/// across.
///
/// **Sizes are rounded up to a step** so that the four thumbnail sizes the phone
/// draws — 44, 52, 54 and 62 points — share one decoded picture instead of
/// keeping four nearly identical ones.
enum Thumbnails {
    private static let step: CGFloat = 128

    static func bucket(forSide side: CGFloat, scale: CGFloat) -> CGFloat {
        // Half again as many pixels as the box needs, so a frame taken in on
        // itself still has something to enlarge.
        let wanted = side * scale * 1.5
        // **To the nearest step, not up to it.** Rounding up put 62 points in a
        // bucket of its own while 44, 52 and 54 shared one — a second copy of
        // every photograph for a strip one row taller. Nearest lands all four
        // on 256, which is still more pixels than any of them draws.
        let rounded = max(step, (wanted / step).rounded() * step)
        // Never fewer pixels than the box itself has, whatever the rounding.
        return max(rounded, (side * scale / step).rounded(.up) * step)
    }
}

extension UIImage {
    /// Builds an image that animates, out of whatever the bytes hold.
    ///
    /// A single-frame file comes back as an ordinary picture, so this is safe to
    /// call on anything — the caller does not have to know in advance whether it
    /// is looking at a GIF.
    static func moving(from data: Data) -> UIImage? {
        moving(from: data, atMost: nil)
    }

    /// The same, at no more than `atMost` pixels along the longer edge.
    ///
    /// **A picture costs what it is decoded at, not what it is drawn at.** A
    /// proxy off his camera is up to 2250×1500; a thumbnail in the shot list is
    /// 54×30 points. Handed the big one, the drawing machinery resamples the
    /// whole thing every time the row is composited — measured at 9.15 ms a row
    /// against a frame's 8.3 ms, so scrolling could not keep up. Decoded to the
    /// size it is actually drawn at, the same row costs 0.19 ms.
    ///
    /// `nil` means full size, which is what a picture being *looked at* wants.
    static func moving(from data: Data, atMost: CGFloat?) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        let count = CGImageSourceGetCount(source)

        guard let atMost else {
            guard count > 1 else { return UIImage(data: data) }
            var pictures: [UIImage] = []
            var seconds: Double = 0
            for index in 0..<count {
                guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
                pictures.append(UIImage(cgImage: frame))
                seconds += delay(of: source, at: index)
            }
            guard !pictures.isEmpty else { return UIImage(data: data) }
            return UIImage.animatedImage(with: pictures, duration: seconds)
        }

        // `...FromImageAlways` rather than `...IfAbsent`: a JPEG out of a phone
        // carries its own tiny preview, and accepting that gives a thumbnail the
        // size of a postage stamp blown up to fill the box.
        let how: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: atMost,
        ]

        var pictures: [UIImage] = []
        var seconds: Double = 0
        for index in 0..<count {
            guard let frame = CGImageSourceCreateThumbnailAtIndex(source, index, how as CFDictionary)
            else { continue }
            pictures.append(UIImage(cgImage: frame))
            seconds += delay(of: source, at: index)
        }
        guard let first = pictures.first else { return UIImage(data: data) }
        // One frame is a picture, not an animation of one — `images` being nil
        // is how every screen tells a still from a GIF.
        guard pictures.count > 1 else { return first }
        return UIImage.animatedImage(with: pictures, duration: seconds)
    }

    /// How long a frame is held. A GIF that says zero means "as fast as you
    /// can", which every browser has agreed for thirty years to read as a
    /// tenth of a second — without that, a whole animation plays in no time at
    /// all and looks like a flicker.
    private static func delay(of source: CGImageSource, at index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else { return 0.1 }
        let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double
        let held = unclamped ?? clamped ?? 0.1
        return held < 0.011 ? 0.1 : held
    }
}
