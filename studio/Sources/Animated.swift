import AppKit
import SwiftUI

/// **A picture that moves, if it is the kind that moves.**
///
/// His ask: *"GIFs should be auto-playing."* SwiftUI's `Image(nsImage:)` draws
/// one representation and stops — an animated GIF loaded into an `NSImage` is
/// perfectly animated and perfectly still on screen, which is a confusing thing
/// to look at, because the file *is* moving and the app is not showing it.
///
/// `NSImageView` will animate one, so this is the thinnest possible wrapper
/// around one: no controls, no state, just the frames going round.
struct Animated: NSViewRepresentable {
    let file: URL
    var fill: Bool = true

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.animates = true
        view.imageScaling = fill ? .scaleProportionallyUpOrDown
                                 : .scaleProportionallyDown
        view.image = NSImage(contentsOf: file)
        // Never let the view's own size be the picture's size: it lives inside
        // a frame that has already been decided, and an image view that argues
        // with its container is how a thumbnail ends up the size of a poster.
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        if context.coordinator.file != file {
            context.coordinator.file = file
            view.image = NSImage(contentsOf: file)
            view.animates = true
        }
    }

    func makeCoordinator() -> Box { Box() }

    final class Box { var file: URL? }
}
