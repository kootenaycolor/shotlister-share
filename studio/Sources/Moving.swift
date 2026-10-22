import AppKit
import AVFoundation
import SwiftUI

/// **A clip that plays, and a gif that goes round, wherever they are drawn.**
///
/// His ask, 2026-08-22: *"videos and GIFs need to auto-play inside a table view
/// or wherever they're present, anywhere throughout the app."* Before this, a
/// clip on a shot was a still — and on a clip that had never been given a poster
/// frame it was not even that, just an empty grey tile until you double-clicked
/// it. Both halves are fixed here: `Thumbs` now falls back when the *decode*
/// fails rather than when the read does, and anything that moves is drawn by
/// something that can move it.
///
/// **Muted, looping, no controls.** A thumbnail is a glance, not a player: it
/// answers "which take is this" and nothing else. The viewer is still where you
/// go to scrub, and it is still one double-click away.
///
/// **Never during a checking run.** A photograph of a playing clip is a
/// photograph of whichever frame the decoder happened to reach, and a check
/// that cannot repeat itself is worse than no check. Under `Launch.checking`
/// every one of these draws its still.
struct MovingFrame: View {
    let hash: String
    let ext: String
    /// What the engine says this is. Nil where nothing said, and then the
    /// extension decides, exactly as it always did.
    var kind: String?
    /// The still to draw when this is an ordinary picture — or when it moves
    /// and the file is not on disk yet, which is true for the first frame after
    /// it appears.
    let still: NSImage?
    let engine: Engine?
    /// Fill the space given and crop, or fit inside it whole.
    var fill: Bool = true
    /// **The range this use of the clip plays.** A clip trimmed in the viewer
    /// has to play the same range everywhere it is drawn small — the table,
    /// the storyboard, the schedule — or the trim is a lie everywhere but the
    /// one window it was set in (his report, 2026-08-28). Both nil is the
    /// whole clip, which is every still and every untrimmed clip.
    var trimStart: Double?
    var trimEnd: Double?
    /// **Which part of a still to keep when it fills a tile.** The middle is
    /// what every drawing in the app used, and it is the wrong half of a
    /// photograph about as often as the right one (his ask, 2026-08-30). Only
    /// a still is framed: a clip is drawn by a player, and moving its picture
    /// inside its own layer is a different job.
    var framing: ViewModel.Framing = .middle
    /// **The storyboard arrows drawn on this use of the picture.** Carried
    /// down to the small drawings for the same reason the trim is: a mark
    /// made in the pop-out has to be on the table thumbnail and the
    /// storyboard card too, or it is a mark in one window only.
    var arrows: [ViewModel.Arrow] = []

    /// **The shot's current Print Frame**, handed in only on the tile of the
    /// shot's key picture, still or clip. With Clip Thumbnails on Print Frame
    /// it is drawn in place of the picture. See `ClipPreviews`.
    var printFrame: PrintFrameView.Baked? = nil

    @State private var file: URL?
    @ObservedObject private var play = ClipPlay.shared
    @ObservedObject private var previews = ClipPreviews.shared
    @Environment(\.colorScheme) private var scheme
    /// Play was pressed on this one — the only way a clip moves while clips
    /// wait to be asked.
    @State private var pressed = false

    /// A clip, as against a gif: only a clip waits. A gif is a few frames
    /// going round, and his ask of 2026-08-22 that gifs play still stands.
    private var clip: Bool {
        Ingest.isMoving(ext, kind: kind) && !Ingest.isGif(ext, kind: kind)
    }
    /// **Clips wait to be asked** — the View menu's Play Clips Automatically,
    /// turned off.
    private var waits: Bool { clip && !play.onTheirOwn }

    private var moves: Bool {
        (!Launch.checking || Launch.playing) && Ingest.isMoving(ext, kind: kind)
            && (!waits || pressed)
    }

    var body: some View {
        frame
            .overlay(alignment: .bottomLeading) {
                if waits { playButton(previewing ? .bottomTrailing : .bottomLeading) }
            }
            // A clip that stops waiting — or starts again — needs its file,
            // or needs to put it down.
            .onChange(of: play.onTheirOwn) { _, _ in pressed = false }
    }

    /// Play, or Stop while it plays. Sized to the tile: a table row's
    /// thumbnail is small and a storyboard card is not.
    /// Whether the tile is showing a Print Frame or four frames rather than
    /// the poster. The play button moves to the bottom right then: the strip
    /// numbers its moments at each quadrant's top left, and the third sits
    /// bottom left.
    private var previewing: Bool {
        waits && previewImage != nil
    }

    private func playButton(_ corner: Alignment) -> some View {
        GeometryReader { space in
            let size = min(24, max(14, min(space.size.width, space.size.height) * 0.3))
            Button { pressed.toggle() } label: {
                Image(systemName: pressed ? "stop.fill" : "play.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Circle().fill(.black.opacity(0.55)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help(pressed ? "Stop" : "Play")
            .padding(max(3, size * 0.25))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner)
        }
    }

    /// What the tile shows in place of its picture, or nil for the picture.
    ///
    /// **Clip Thumbnails** (his ruling, 2026-10-14), only while clips wait
    /// for play: on Print Frame the shot's own board, on the key picture's
    /// tile whether that is a still or a clip; a clip with no board, or on
    /// Four Frames, shows its four moments; Still shows the poster.
    private var previewImage: NSImage? {
        guard !play.onTheirOwn, !pressed else { return nil }
        _ = previews.arrivals
        if play.thumbs == .printFrame, let printFrame,
           let board = previews.board(printFrame, engine: engine) {
            return board
        }
        guard clip, play.thumbs != .still else { return nil }
        return previews.strip(hash: hash, ext: ext, trimStart: trimStart, trimEnd: trimEnd,
                              engine: engine)
    }

    private var frame: some View {
        Group {
            if let preview = previewImage {
                // Fitted, never cropped: a board or four moments cut down to
                // the middle would be a different picture. What is left over
                // is the empty frame's own grey, not a black bar.
                ZStack {
                    Brand.frameEmpty(scheme == .dark)
                    Fitted(picture: preview)
                }
            } else if moves, let file {
                if Ingest.isGif(ext, kind: kind) {
                    Animated(file: file, fill: fill)
                } else {
                    Loop(file: file, fill: fill, from: trimStart ?? 0, to: trimEnd)
                }
            } else if let still {
                if fill {
                    Framed(picture: still, framing: framing, arrows: arrows)
                } else {
                    // Fitted whole, so the arrows lie on exactly the drawn
                    // picture and nowhere else — hence `Fitted`, which works
                    // out that rectangle rather than guessing at it.
                    Fitted(picture: still, arrows: arrows)
                }
            } else if waits {
                // A clip with no poster frame, waiting: dark, so the play
                // button has something to sit on.
                Color.black.opacity(0.85)
            } else {
                Color.clear
            }
        }
        // **Not in `body`.** Getting the file means reading the bytes out of the
        // project and writing a scratch copy, and doing that inside a view's
        // body means doing it on every scroll tick of every visible row. Here
        // it happens once per clip, after the row is already on screen.
        .task(id: "\(hash) \(moves)") {
            guard moves else { return }
            file = Clips.file(hash: hash, ext: ext, from: engine)
        }
    }
}

/// **Whether clips play on their own** — one answer for this Mac, kept in its
/// settings, switched in the View menu. His ask, 2026-09-30: *"a mode where
/// video can not autoplay and only play in thumbnail after clicking play on
/// them."* On unless he turns it off, so nothing changed for anyone who did
/// not ask.
///
/// A checking run never reads or writes his setting: it shares his app's
/// settings, and a check must never change what he sees. `--clipswait` asks
/// for the waiting kind.
final class ClipPlay: ObservableObject {
    static let shared = ClipPlay()
    private static let key = "clipsPlayOnTheirOwn"
    private static let previewKey = "clipsPreviewStills"

    @Published var onTheirOwn: Bool {
        didSet {
            guard !Launch.checking else { return }
            UserDefaults.standard.set(onTheirOwn, forKey: Self.key)
        }
    }

    /// **Clip Thumbnails** — his ruling, 2026-10-14: *"the options should be
    /// to show the standard print still (4 quadrants) or the 'Print Frame'
    /// that I set up."* While clips wait for play, a tile shows its poster
    /// (Still), the clip's four moments (Four Frames), or the shot's own
    /// Print Frame (Print Frame, the default; a clip on a shot without one
    /// shows Four Frames). Replaced the Preview Stills switch, whose off
    /// becomes Still and on becomes Print Frame. A checking run asks with
    /// `--clipthumbs still|four|print`; `--nopreviewstills` still means Still.
    @Published var thumbs: ClipThumbs {
        didSet {
            guard !Launch.checking else { return }
            UserDefaults.standard.set(thumbs.rawValue, forKey: Self.thumbsKey)
        }
    }
    private static let thumbsKey = "clipThumbnails"

    private init() {
        if Launch.checking {
            let args = CommandLine.arguments
            onTheirOwn = !args.contains("--clipswait")
            if let at = args.firstIndex(of: "--clipthumbs"), at + 1 < args.count,
               let asked = ClipThumbs(rawValue: args[at + 1]) {
                thumbs = asked
            } else {
                thumbs = args.contains("--nopreviewstills") ? .still : .printFrame
            }
        } else {
            let defaults = UserDefaults.standard
            onTheirOwn = defaults.object(forKey: Self.key) as? Bool ?? true
            if let kept = defaults.string(forKey: Self.thumbsKey).flatMap(ClipThumbs.init) {
                thumbs = kept
            } else if let old = defaults.object(forKey: Self.previewKey) as? Bool {
                thumbs = old ? .printFrame : .still
            } else {
                thumbs = .printFrame
            }
        }
    }
}

/// What a clip's tile shows while it waits for play. See `ClipPlay.thumbs`.
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

/// A picture filling its tile, keeping the part it was told to keep.
///
/// **The anchor cannot show empty space, by construction.** `x` and `y` run
/// from nought to one across whatever hangs over the edges of the tile — nought
/// is the picture's left edge against the tile's left edge, one is right
/// against right — so there is no arithmetic here that can put a gap beside a
/// photograph. The phone draws from the same two lines (`Framed`, in
/// `phone/Sources/Frames.swift`); they are deliberately the same maths, and if
/// one ever changes the other has to.
struct Framed: View {
    let picture: NSImage
    var framing: ViewModel.Framing = .middle
    /// **Arrows ride with the picture, not with the tile.** They are drawn on
    /// the same rectangle the photograph is drawn on and carried by the same
    /// offset, so cropping in on a corner crops in on the arrow that was
    /// drawn there — which is the only behaviour that is not a lie.
    var arrows: [ViewModel.Arrow] = []

    var body: some View {
        GeometryReader { space in
            let box = space.size
            let size = covering(box)
            ZStack {
                Image(nsImage: picture).resizable()
                if !arrows.isEmpty { ArrowMarks(arrows: arrows) }
            }
            .frame(width: size.width, height: size.height)
            .offset(x: (0.5 - framing.x) * (size.width - box.width),
                    y: (0.5 - framing.y) * (size.height - box.height))
            .frame(width: box.width, height: box.height)
        }
        .clipped()
    }

    /// Big enough to cover the tile, times however far in it has been taken.
    private func covering(_ box: CGSize) -> CGSize {
        let shape = max(picture.size.width, 1) / max(picture.size.height, 1)
        var width = box.width
        var height = box.width / shape
        if height < box.height {
            height = box.height
            width = height * shape
        }
        return CGSize(width: width * framing.scale, height: height * framing.scale)
    }
}

/// **A picture fitted whole inside its space, arrows and all.**
///
/// `Image(contentMode: .fit)` alone cannot carry them: the drawn rectangle is
/// worked out by the layout system and never handed back, so an overlay lands
/// on the space rather than on the photograph — and an arrow drawn a third of
/// the way across a 16:9 still would sit a third of the way across a square
/// window. This does the same arithmetic itself, so both halves agree.
struct Fitted: View {
    let picture: NSImage
    var arrows: [ViewModel.Arrow] = []

    var body: some View {
        GeometryReader { space in
            let box = fitting(space.size)
            ZStack {
                Image(nsImage: picture).resizable()
                if !arrows.isEmpty { ArrowMarks(arrows: arrows) }
            }
            .frame(width: box.width, height: box.height)
            .frame(width: space.size.width, height: space.size.height)
        }
    }

    private func fitting(_ space: CGSize) -> CGSize {
        let shape = max(picture.size.width, 1) / max(picture.size.height, 1)
        let byWidth = CGSize(width: space.width, height: space.width / shape)
        if byWidth.height <= space.height { return byWidth }
        return CGSize(width: space.height * shape, height: space.height)
    }
}

/// **A photograph shown as the frame it will actually be** — his instruction,
/// 2026-08-31: *"we should always view photos inside the media player in the
/// shot list by the chosen aspect ratio."*
///
/// **This reverses what the frames window used to say**, and the old line is
/// worth quoting because it was a real position and not an oversight: *"whole,
/// never cropped — a frame is the thing being looked at here, and a window
/// that trims it is lying about the composition."* The opposite is true for a
/// shot. What he is judging is not the photograph, it is the shot, and the
/// shot is the film's own rectangle. A window showing him more than the frame
/// is the one lying — and it is where the arrows get composed, so composing
/// them against a picture wider than the frame puts marks where he will never
/// see them.
///
/// The box is the film's ratio; the picture fills it and keeps the part the
/// crop chose. Nothing is stored: this is only how it is shown.
struct Plate: View {
    let picture: NSImage
    /// The film's own ratio, from Project Settings.
    var ratio: CGFloat
    var framing: ViewModel.Framing = .middle
    var arrows: [ViewModel.Arrow] = []
    /// The project's other frames as guide lines (piece E); none by default.
    var guides: [FrameGuide] = []

    var body: some View {
        GeometryReader { space in
            let box = Plate.box(ratio, in: space.size)
            Framed(picture: picture, framing: framing, arrows: arrows)
                .overlay {
                    if !guides.isEmpty {
                        FrameGuideLines(guides: guides, ratio: ratio)
                    }
                }
                .frame(width: box.width, height: box.height)
                .position(x: box.midX, y: box.midY)
        }
    }

    /// **The frame, inside the room it is given** — the biggest rectangle of
    /// that ratio that fits, centred. Shared with `ArrowBoard`, which has to
    /// land a mouse in exactly this box or every mark is off by the letterbox.
    static func box(_ ratio: CGFloat, in space: CGSize) -> CGRect {
        let shape = max(ratio, 0.01)
        var size = CGSize(width: space.width, height: space.width / shape)
        if size.height > space.height {
            size = CGSize(width: space.height * shape, height: space.height)
        }
        return CGRect(x: (space.width - size.width) / 2,
                      y: (space.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// **The part of the picture the frame actually shows**, in the picture's
    /// own nought-to-one — the unit rectangle when the photograph is already
    /// the film's shape.
    ///
    /// **It needs no geometry**, because it depends only on the two shapes and
    /// the crop: how big the window is cancels out. That is what lets the row
    /// of arrow buttons, which has no picture under it, place a pan inside the
    /// frame rather than inside the photograph.
    static func visible(picture: CGSize, ratio: CGFloat,
                        framing: ViewModel.Framing) -> CGRect {
        let shape = max(picture.width, 1) / max(picture.height, 1)
        let frame = max(ratio, 0.01)
        var width = frame
        var height = frame / shape
        if height < 1 {
            height = 1
            width = shape
        }
        width *= framing.scale
        height *= framing.scale
        let overX = width - frame
        let overY = height - 1
        return CGRect(x: overX * framing.x / width,
                      y: overY * framing.y / height,
                      width: frame / width,
                      height: 1 / height)
    }

    /// **Where the photograph itself lands behind that box.** Bigger than the
    /// box whenever the picture is not the film's shape, and shifted by the
    /// crop — *the same arithmetic `Framed` does*, because a mark has to land
    /// under the mouse and there is only one right answer to where the
    /// picture is. If `Framed` changes, this changes.
    static func plate(_ picture: NSImage, _ framing: ViewModel.Framing,
                      in box: CGRect) -> CGRect {
        let shape = max(picture.size.width, 1) / max(picture.size.height, 1)
        var width = box.width
        var height = box.width / shape
        if height < box.height {
            height = box.height
            width = height * shape
        }
        width *= framing.scale
        height *= framing.scale
        let overX = width - box.width
        let overY = height - box.height
        return CGRect(x: box.minX - overX * framing.x,
                      y: box.minY - overY * framing.y,
                      width: width, height: height)
    }
}

/// The scratch copies, remembered.
///
/// `Viewer.onDisk` is content-addressed and cheap to *repeat* — the same bytes
/// always land at the same path — but it reads the whole file out of the engine
/// before it notices the copy is already there. A table scrolling past a clip
/// would do that several times a second.
enum Clips {
    private static var known: [String: URL] = [:]

    static func file(hash: String, ext: String, from engine: Engine?) -> URL? {
        if let held = known[hash] { return held }
        guard let made = Viewer.onDisk(hash: hash, ext: ext, from: engine) else { return nil }
        known[hash] = made
        return made
    }

    /// **A range of a clip, as a clip in its own right.** Shared with the
    /// viewer's `ClipView`, because both want the same thing and the naive
    /// alternative — play the whole file and seek to the in point — loses a
    /// race it cannot win: a player is not ready to be seeked the instant it
    /// is made, so the thumbnail played from nought while claiming the range
    /// (2026-08-28). A composition has no such moment. It copies nothing; it
    /// is only a description of which part of which asset to play.
    static func item(of asset: AVAsset, from: Double?, to: Double?) -> AVPlayerItem {
        guard let from, let to, to > from else { return AVPlayerItem(asset: asset) }
        let piece = AVMutableComposition()
        let range = CMTimeRange(start: CMTime(seconds: from, preferredTimescale: 600),
                                end: CMTime(seconds: to, preferredTimescale: 600))
        do { try piece.insertTimeRange(range, of: asset, at: .zero) }
        // A range the asset cannot serve is not worth a blank tile.
        catch { return AVPlayerItem(asset: asset) }
        return AVPlayerItem(asset: piece)
    }

    /// Let go of what the project no longer has, alongside `Thumbs.keep(only:)`.
    static func keep(only alive: Set<String>) {
        for hash in known.keys where !alive.contains(hash) {
            known.removeValue(forKey: hash)
        }
    }
}

/// A clip, playing itself, quietly, for ever.
struct Loop: NSViewRepresentable {
    let file: URL
    var fill: Bool = true
    /// The range to loop inside. `to` nil plays to the clip's own end.
    var from: Double = 0
    var to: Double?

    func makeNSView(context: Context) -> LoopView {
        let view = LoopView()
        view.start(file: file, fill: fill, from: from, to: to)
        return view
    }

    func updateNSView(_ view: LoopView, context: Context) {
        view.start(file: file, fill: fill, from: from, to: to)
    }

    static func dismantleNSView(_ view: LoopView, coordinator: ()) {
        view.stop()
    }
}

final class LoopView: NSView {
    private var player: AVPlayer?
    private var sheet: AVPlayerLayer?
    private var playing: URL?
    /// The trimmed range being played. Nought and nil is the whole clip.
    /// Kept so a changed range is noticed, and so the checking readout can
    /// say which range it believes it is inside.
    private var from: Double = 0
    private var to: Double?

    func start(file: URL, fill: Bool, from: Double = 0, to: Double? = nil) {
        sheet?.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        // **A changed range is as much a change as a changed file.** Trimming
        // a clip in the viewer leaves every thumbnail of it on screen already
        // built; without this they would go on playing the old range until
        // something else happened to rebuild them.
        guard playing != file || self.from != from || self.to != to else { return }
        stop()
        playing = file
        self.from = from
        self.to = to
        wantsLayer = true

        // The trimmed range *is* the clip here — see `Clips.item`.
        let player = AVPlayer(playerItem: Clips.item(of: AVURLAsset(url: file),
                                                     from: from > 0 || to != nil ? from : nil,
                                                     to: to))
        player.isMuted = true
        // **Never a system sound and never a pause for one.** A wall of
        // thumbnails all deciding they are the thing being listened to would
        // duck his music and fight each other.
        player.actionAtItemEnd = .none
        let sheet = AVPlayerLayer(player: player)
        sheet.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        sheet.frame = bounds
        layer?.addSublayer(sheet)
        self.player = player
        self.sheet = sheet

        let centre = NotificationCenter.default
        centre.addObserver(self, selector: #selector(again),
                           name: .AVPlayerItemDidPlayToEndTime,
                           object: player.currentItem)
        // Nothing plays behind another app: a shot list left open in the corner
        // of the screen must not be decoding video while he is in Resolve.
        centre.addObserver(self, selector: #selector(rest),
                           name: NSApplication.didResignActiveNotification, object: nil)
        centre.addObserver(self, selector: #selector(carryOn),
                           name: NSApplication.didBecomeActiveNotification, object: nil)
        if awake { player.play() }
        say()
    }

    /// **Proof that it is actually running**, for a checking run. A screenshot
    /// cannot tell a playing clip from a still of its first frame; a playhead
    /// that has moved can only have moved by playing.
    private func say() {
        guard Launch.checking, Launch.playing else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, let player = self.player else { return }
            FileHandle.standardError.write(Data((
                "clip: rate \(player.rate)"
                + String(format: "  playhead %.2f", player.currentTime().seconds)
                // **The item's own length is the whole claim.** The playhead
                // is measured against the trimmed piece, so it cannot tell a
                // trimmed clip from an untrimmed one on its own; the duration
                // can — 2.00s of an 8s file is the trim, proven.
                + String(format: "  plays %.2fs  asked %.2f–%.2f",
                         CMTimeGetSeconds(player.currentItem?.duration ?? .zero),
                         self.from, self.to ?? -1)
                + "\n").utf8))
        }
    }

    @objc private func again() {
        player?.seek(to: .zero)
        if awake { player?.play() }
    }

    /// Whether anything should be moving at all. A checking run is never
    /// frontmost by design — that is the invisibility law — so the one that is
    /// deliberately checking the motion says so.
    private var awake: Bool { NSApp.isActive || (Launch.checking && Launch.playing) }

    @objc private func rest() { if !awake { player?.pause() } }
    @objc private func carryOn() { player?.play() }

    func stop() {
        player?.pause()
        NotificationCenter.default.removeObserver(self)
        sheet?.removeFromSuperlayer()
        player = nil
        sheet = nil
        playing = nil
    }

    override func layout() {
        super.layout()
        // No implicit animation on a frame change: a layer that eases into its
        // new size makes a resizing column look like jelly.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sheet?.frame = bounds
        CATransaction.commit()
    }

    deinit { stop() }
}

/// **One place that knows how to draw a stored frame**, so the seven places
/// that draw one do not each have to remember that a clip's poster lives under
/// a different extension and that a gif needs a file rather than bytes.
enum Frames {
    /// Whether there is anything to draw at all — a still, or something that
    /// moves and will play in place of one. A clip with no poster frame used to
    /// fail this test everywhere and show the empty-frame box.
    static func something(_ hash: String, _ filename: String, _ engine: Engine?,
                          kind: String? = nil) -> Bool {
        if Thumbs.shared.gone[hash] != nil { return false }
        let frame = ViewModel.Frame(hash: hash, filename: filename, kind: kind)
        return Ingest.isMoving(frame.ext, kind: kind)
            || Thumbs.shared.image(frame, from: engine) != nil
    }

    /// **What to draw where a picture is not.** Ref 224.
    ///
    /// Two things look identical as a grey square and are not the same at all:
    /// a photograph still coming down from iCloud, and a frame the project has
    /// a record of and no file for. He read the first as rubbish the app had
    /// left lying about and was deleting real photographs beside it. So the
    /// second says so — the same words the phone uses, so the two apps cannot
    /// disagree about what he is looking at — and the first stays quiet,
    /// because a picture that is merely on its way needs no announcement.
    ///
    /// The engine is asked which is which; nothing here guesses from a read
    /// that came up empty.
    @ViewBuilder
    static func gap(_ hash: String, dark: Bool, small: Bool = false) -> some View {
        if let name = Thumbs.shared.gone[hash] {
            // Deleted from the Media window; the name is what is left. His
            // ask: going back, he can find it and drop it in again.
            VStack(spacing: 3) {
                Text(name).sans(small ? 10 : 11).lineLimit(2).truncationMode(.middle)
                    .multilineTextAlignment(.center)
                if !small { Text("Deleted").sans(10) }
            }
            .padding(small ? 4 : 10)
            .foregroundStyle(Brand.ink3(dark))
            .help("Deleted · \(name)")
        } else if Thumbs.shared.hollow.contains(hash) {
            VStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: small ? 12 : 17, weight: .light))
                if !small {
                    Text("Picture missing").sans(10)
                }
            }
            .foregroundStyle(Brand.ink4(dark))
            .help("No file")
        } else {
            Image(systemName: "photo")
                .font(.system(size: small ? 13 : 20))
                .foregroundStyle(Brand.ink4(dark))
        }
    }

    /// `trimStart`/`trimEnd` are the range this *use* of the clip plays.
    /// Callers that hold a `Still`, an `Attachment` or a `Frame` pass theirs
    /// straight through; everything else leaves them nil and gets the whole
    /// clip, exactly as before.
    static func view(_ hash: String, _ filename: String,
                     engine: Engine?, fill: Bool = true,
                     trimStart: Double? = nil, trimEnd: Double? = nil,
                     kind: String? = nil,
                     framing: ViewModel.Framing = .middle,
                     arrows: [ViewModel.Arrow] = [],
                     printFrame: PrintFrameView.Baked? = nil) -> MovingFrame {
        let frame = ViewModel.Frame(hash: hash, filename: filename, kind: kind)
        return MovingFrame(hash: hash, ext: frame.ext, kind: kind,
                           still: Thumbs.shared.image(frame, from: engine),
                           engine: engine, fill: fill,
                           trimStart: trimStart, trimEnd: trimEnd,
                           framing: framing, arrows: arrows, printFrame: printFrame)
    }
}
