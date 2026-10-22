import SwiftUI
import AVFoundation

/// A clip, playing.
///
/// **Autoplay, muted, looping, no controls.** A shot list is looked at, not
/// operated: a clip on a card should already be moving by the time his eye
/// reaches it, the way it does in Photos. Nothing here has a play button
/// because nothing here needs a decision — and sound on a set, from a phone
/// left face-up, is the wrong surprise.
///
/// It plays only while it is on screen. A scene with eight clips in it would
/// otherwise have eight decoders running behind the scrolled-past rows, which
/// is a hot phone and a flat battery on a scout.
///
/// **Or on a tap** — his ask, 2026-10-09: *"a feature that either auto-plays
/// media or doesn't by default, and that means that you tap play on a video
/// to play it individually."* Settings ▸ Play Clips. On Tap, a clip sits on
/// its first frame with a play mark; the mark plays that one clip, and a
/// small pause mark in its corner stops it. The rest of the frame still
/// opens the shot, as it always did.
struct Clip: View {
    let url: URL
    /// The seconds of it this use plays, if it has been cut.
    var cut: Frames.Cut? = nil
    var fill: Bool = true
    /// **Clip Thumbnails** (2026-10-14): what a waiting clip shows over its
    /// paused first frame — the shot's Print Frame or the clip's four
    /// moments, fitted, never cropped. Nil shows the first frame as before.
    var preview: UIImage? = nil
    @AppStorage(ClipPlay.key) private var automatic = ClipPlay.startingAutomatic
    @State private var playing = false

    var body: some View {
        let run = automatic || playing
        Player(url: url, cut: cut, fill: fill, run: run)
            .overlay {
                if !run, let preview {
                    Previewed(image: preview)
                }
            }
            .overlay {
                if !run {
                    Button { playing = true } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.black.opacity(0.55), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play")
                }
            }
            .overlay(alignment: .bottomLeading) {
                if !automatic && playing {
                    Button { playing = false } label: {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(.black.opacity(0.55), in: Circle())
                            .padding(5)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Pause")
                }
            }
    }

    private struct Player: UIViewRepresentable {
        let url: URL
        let cut: Frames.Cut?
        let fill: Bool
        let run: Bool

        func makeUIView(context: Context) -> Screen {
            let view = Screen()
            view.running = run
            view.show(url, cut: cut, fill: fill)
            return view
        }

        func updateUIView(_ view: Screen, context: Context) {
            view.running = run
            view.show(url, cut: cut, fill: fill)
        }

        static func dismantleUIView(_ view: Screen, coordinator: ()) {
            view.stop()
        }
    }

    /// A layer with a looping player on it.
    ///
    /// `AVPlayerLooper` needs a queue player and a live reference to itself, or
    /// the loop is collected and the clip plays once and freezes — which reads
    /// as a broken video rather than a finished one.
    final class Screen: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        private var film: AVPlayerLayer { layer as! AVPlayerLayer }

        private var looper: AVPlayerLooper?
        private var showing: URL?
        private var playing: Frames.Cut?
        /// Whether it moves: always, unless Play Clips is On Tap and this
        /// one has not been tapped.
        var running = true {
            didSet {
                guard running != oldValue, window != nil else { return }
                if running { film.player?.play() } else { film.player?.pause() }
            }
        }

        func show(_ url: URL, cut: Frames.Cut?, fill: Bool) {
            film.videoGravity = fill ? .resizeAspectFill : .resizeAspect
            // The cut is half of what is being shown: the same file trimmed
            // differently is a different loop, and it has to be rebuilt.
            guard showing != url || playing != cut else { return }
            showing = url
            playing = cut

            let player = AVQueuePlayer()
            player.isMuted = true
            // No stalling on a spinner: the file is on this device already.
            player.automaticallyWaitsToMinimizeStalling = false
            // **`AVPlayerLooper` takes the range itself**, which is the whole of
            // the trim on a thumbnail: no seeking a fresh player to an in point
            // (it is not ready, and the seek is dropped), and no arithmetic of
            // ours anywhere.
            let item = AVPlayerItem(url: url)
            if let cut {
                looper = AVPlayerLooper(player: player, templateItem: item,
                                        timeRange: Clips.range(cut))
            } else {
                looper = AVPlayerLooper(player: player, templateItem: item)
            }
            film.player = player
            if running { player.play() }
        }

        func stop() {
            film.player?.pause()
            film.player = nil
            looper = nil
            showing = nil
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // Off screen, off. Back on screen, running again.
            if window == nil || !running { film.player?.pause() } else { film.player?.play() }
        }
    }
}

/// **Play Clips**: Automatically, or On Tap. This iPhone's choice, kept with
/// Appearance in Settings on the Projects screen.
enum ClipPlay {
    static let key = "clips.automatic"
    /// **Clip Thumbnails** — his ruling, 2026-10-14: *"the options should be
    /// to show the standard print still (4 quadrants) or the 'Print Frame'
    /// that I set up."* With Play Clips On Tap, a tile shows its first frame
    /// (Still), a clip's four moments (Four Frames), or the shot's own Print
    /// Frame on its key picture, still or clip (Print Frame, the default; a
    /// clip on a shot without one shows Four Frames). A `ClipThumbs` raw value.
    static let thumbsKey = "clips.thumbnails"
    /// The Preview Stills switch it replaced: off becomes Still, on Print Frame.
    static let previewKey = "clips.previewStills"

    /// **Play Clips starts On Tap** on an iPhone that has not chosen
    /// (2026-10-16), the way his Mac is set. On Automatically, clips move in
    /// the list and a shot's Print Frame never shows there — the rule both
    /// apps share — so a phone left at the old start showed him no Print
    /// Frames in the list while the Mac showed one on every shot. A phone
    /// that chose Automatically keeps it.
    static let startingAutomatic = false

    /// Where the choice starts on an iPhone that has not made it yet.
    static var startingThumbs: String {
        guard let old = UserDefaults.standard.object(forKey: previewKey) as? Bool else {
            return ClipThumbs.printFrame.rawValue
        }
        return (old ? ClipThumbs.printFrame : .still).rawValue
    }
}

/// What a clip's tile shows while it waits for its play mark.
enum ClipThumbs: String, CaseIterable, Identifiable {
    case still
    case fourFrames = "four"
    case printFrame = "print"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .still: return "Still"
        case .fourFrames: return "Four Frames"
        case .printFrame: return "Print Frame"
        }
    }
}

/// **A board or four moments, fitted whole on the empty frame's ground** —
/// never cropped, and no black bars where its shape is not the tile's.
struct Previewed: View {
    let image: UIImage
    var body: some View {
        ZStack {
            Style.card
            Color.primary.opacity(0.045)
            Fitted(image: image)
        }
    }
}

/// The two things anything playing a cut clip needs, in one place so the
/// thumbnails and the viewer cannot disagree about what a trim means.
enum Clips {
    static func range(_ cut: Frames.Cut) -> CMTimeRange {
        CMTimeRange(start: CMTime(seconds: cut.start, preferredTimescale: 600),
                    end: CMTime(seconds: cut.end, preferredTimescale: 600))
    }

    /// A player item that **is** the trimmed piece.
    ///
    /// Not a whole clip with an end time set: the scrubber in the viewer draws
    /// the item's own duration, so a trimmed clip has to *be* two seconds long
    /// rather than be an eight-second one told to stop early.
    static func item(_ url: URL, cut: Frames.Cut?) -> AVPlayerItem {
        guard let cut else { return AVPlayerItem(url: url) }
        let asset = AVURLAsset(url: url)
        let composition = AVMutableComposition()
        do {
            try composition.insertTimeRange(range(cut), of: asset, at: .zero)
            return AVPlayerItem(asset: composition)
        } catch {
            // A file that will not compose still plays whole, which is better
            // than a black rectangle.
            return AVPlayerItem(url: url)
        }
    }
}
