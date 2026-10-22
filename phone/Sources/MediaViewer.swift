import SwiftUI
import AVKit

/// **One picture or clip, full screen** — the phone's media viewer.
///
/// Worn by everything that holds media: a shot's frames, a location's
/// photographs, a mood board's wall. One viewer, so the same gestures work
/// wherever he is.
///
/// A clip gets **the system's own transport** — play, pause, scrub — rather
/// than a scrubber of ours. That was the Mac's hard-won lesson: three rounds of
/// a hand-written one shipped three bugs, all from a control minding a player
/// it did not own. What is ours is only what the system has no opinion about:
/// where this use of the clip starts and stops, and which frame stands for it
/// everywhere else.
///
/// **The trim strip sits outside the pager, deliberately.** A paged `TabView`
/// claims every horizontal drag it can see, so handles drawn inside a page take
/// the touch and never move — no error, no warning, nothing on screen. Below
/// the pages they are simply handles.
struct StillViewer: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var frames: Frames
    let still: Engine.Still
    let all: [Engine.Still]
    var onDelete: (Engine.Still) -> Void
    /// The shape this picture gets drawn in where it is drawn cropped — 1 for
    /// a square wall, the film's own ratio for everything else. It is what the
    /// crop window is cut to.
    var cropTo: Double = 1.85

    @State private var showing = ""
    @State private var cropping = false
    @State private var drawingArrows = false
    @State private var cropShape: Double?
    @State private var captioning = false
    @State private var captionText = ""
    /// Captions written here, shown at once (the list it was opened with is a copy).
    @State private var typedCaptions: [String: String] = [:]
    @Environment(\.dismiss) private var dismiss

    /// The player, owned here and passed **down** into whichever page is on
    /// screen. Never handed upward out of a `make…`: state written during a
    /// SwiftUI update is discarded silently, which is how the Mac shipped a
    /// play button holding nothing at all.
    @StateObject private var play = ClipPlayer()
    /// What the handles are showing while one is being dragged. The engine is
    /// told when the thumb is lifted; the numbers read from this until it is.
    @State private var live: ClosedRange<Double>?

    private var at: Int { all.firstIndex { $0.id == showing } ?? 0 }
    private var current: Engine.Still? { all.first { $0.id == showing } }

    /// The clip on screen, if what is on screen is one.
    private var film: (url: URL, cut: Frames.Cut?)? {
        guard let current, case .film(let url, let cut)? = frames.shown(current) else { return nil }
        return (url, cut)
    }

    /// The still on screen, if what is on screen is one. A clip cannot be
    /// framed yet — see `Picture`.
    private var picture: UIImage? {
        guard let current, case .picture(let image)? = frames.shown(current),
              image.images == nil else { return nil }
        return image
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $showing) {
                    ForEach(all) { one in
                        page(one).tag(one.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                if let film {
                    chrome(url: film.url, cut: film.cut)
                }
                // **Its caption** (the Mac's): shown, and tapped to change.
                if let current {
                    let words = typedCaptions[current.ref] ?? current.caption
                    Button {
                        captionText = words
                        captioning = true
                    } label: {
                        Text(words.isEmpty ? "Add Caption" : words)
                            .font(.footnote)
                            .foregroundStyle(words.isEmpty ? Color.secondary : Color(.label))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("viewer.caption")
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(all.count > 1 ? "\(at + 1) of \(all.count)" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.left") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // **Save or send this frame** (the Mac's Save a Copy /
                    // Open in another app).
                    if let picture {
                        ShareLink(item: Image(uiImage: picture),
                                  preview: SharePreview(current?.filename ?? "Frame", image: Image(uiImage: picture))) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    } else if let film {
                        ShareLink(item: film.url) { Image(systemName: "square.and.arrow.up") }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                        // **Arrows on this frame** (the Mac's arrow tools).
                    if picture != nil, current?.ref.isEmpty == false {
                        Button { drawingArrows = true } label: { Image(systemName: "arrow.up.right") }
                            .accessibilityLabel("Arrows")
                            .accessibilityIdentifier("viewer.arrows")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if picture != nil {
                        // **Crop to which shape** (the Mac's Project / Square / 16:9).
                        Menu {
                            Button("Project") { cropShape = cropTo; cropping = true }
                            Button("Square") { cropShape = 1; cropping = true }
                            Button("16:9") { cropShape = 16.0 / 9.0; cropping = true }
                        } label: { Image(systemName: "crop") }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        if let current { onDelete(current) }
                        dismiss()
                    } label: { Image(systemName: "trash").foregroundStyle(.red) }
                }
            }
        }
        .fullScreenCover(isPresented: $drawingArrows) {
            if let current, let picture {
                ArrowEditorPhone(ref: current.ref, image: picture,
                                 start: session.stillArrows(current.ref) ?? current.arrows)
                    .environmentObject(session)
            }
        }
        .fullScreenCover(isPresented: $cropping) {
            if let current, let picture {
                CropEditor(still: current, image: picture, shape: cropShape ?? cropTo)
                    .environmentObject(session)
            }
        }
        .alert("Caption", isPresented: $captioning) {
            TextField("Caption", text: $captionText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let current {
                    session.caption(current, captionText)
                    typedCaptions[current.ref] = captionText
                }
            }
        }
        .onAppear { showing = still.id }
        .task(id: showing) { await follow() }
        // A trim written elsewhere — or by the handles below — is a different
        // piece of film: the player is given the new one.
        .task(id: film?.cut) { await follow() }
    }

    /// Point the player at whatever is on screen now.
    private func follow() async {
        guard let film else { return }
        live = nil
        await play.load(url: film.url, cut: film.cut)
    }

    @ViewBuilder
    private func page(_ one: Engine.Still) -> some View {
        switch frames.shown(one) {
        case .film:
            // Only the page in front holds the player: one `AVPlayer` cannot be
            // in two places, and the pages either side are not being looked at.
            if one.id == showing {
                // **Drawn at the clip's own shape, not letterboxed inside a
                // black slab.** `AVPlayerViewController` paints its own
                // backdrop black and will not be talked out of it, so the space
                // around a 4:3 clip on a tall screen belonged to the player and
                // read as a separate block sitting in the middle of the app —
                // his note. Given exactly the shape of the film, there is no
                // space left inside it, and what surrounds it is the page.
                Movie(player: play.player)
                    .aspectRatio(play.shape, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color(.systemBackground)
            }
        case .picture(let image):
            Picture(.picture(image), fill: false, arrows: session.stillArrows(still.ref) ?? still.arrows)
        case nil:
            ProgressView()
        }
    }

    // ---- what a clip can be told ---------------------------------------------

    private func chrome(url: URL, cut: Frames.Cut?) -> some View {
        let whole = play.whole
        let shown = live ?? (cut.map { $0.start...$0.end } ?? 0...max(whole, 0.05))
        return VStack(spacing: 10) {
            PlaybackBar(play: play, clock: play.clock)

            TrimStrip(url: url, whole: whole, range: shown, live: $live) { from, to in
                guard let current else { return }
                session.trim(current, from: from, to: to)
            }
            .frame(height: 46)

            HStack(spacing: 14) {
                // A count is a count: how much of the clip this use plays.
                Text(said(shown, of: whole))
                    .font(.kitLabel.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if cut != nil {
                    Button {
                        if let current { session.clearTrim(current) }
                    } label: {
                        Image(systemName: "arrow.counterclockwise").font(.footnote)
                    }
                    .buttonStyle(.borderless)
                }
                Button { poster(url: url, cut: cut) } label: {
                    Image(systemName: "viewfinder").font(.footnote.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// `11.0s of 22.9s`, or just the length when nothing is cut.
    private func said(_ range: ClosedRange<Double>, of whole: Double) -> String {
        guard whole > 0 else { return "" }
        let length = range.upperBound - range.lowerBound
        func seconds(_ value: Double) -> String { String(format: "%.1fs", max(0, value)) }
        return abs(length - whole) < 0.05 ? seconds(whole)
                                          : "\(seconds(length)) of \(seconds(whole))"
    }

    /// The frame he is looking at, made to stand for the clip everywhere a
    /// picture is drawn.
    private func poster(url: URL, cut: Frames.Cut?) {
        guard let current else { return }
        // Where the playhead is **in the whole file**, which is not where it is
        // in the piece being played: a trimmed clip is its own short item, and
        // its nought is the in point.
        let here = (cut?.start ?? 0) + play.at
        Task {
            guard let image = await play.frame(of: url, at: here),
                  let jpeg = Media.poster(image) else { return }
            session.poster(hash: current.hash, jpeg: jpeg)
        }
    }
}

/// The player, on the page's own background rather than on a black slab.
///
/// `VideoPlayer` paints itself black, which in a light room reads as a separate
/// block sitting in the middle of the app — his note. `AVPlayerViewController`
/// is the same control underneath and will take a background, so it is reached
/// for directly: the same transport, the same behaviour, and the space around a
/// tall clip is whatever the phone's theme says it should be.
///
/// **Its own scrub bar is turned off.** It draws inside the page, and a page is
/// inside the `TabView` that pages between stills, which claims every
/// horizontal drag it can see, the same trap the trim handles hit below. A tap
/// on the system's play button survives that; a slow drag on its scrub thumb
/// does not, so landing on a chosen point never worked. `PlaybackBar` below is
/// drawn outside the pager instead, where the trim handles already live safely.
private struct Movie: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .systemBackground
        controller.contentOverlayView?.backgroundColor = .clear
        controller.updatesNowPlayingInfoCenter = false
        controller.showsPlaybackControls = false
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}

/// Play, pause, and a scrub bar that actually lands where he drags it to.
///
/// Drawn outside the pager, in the same safe strip the trim handles use. While
/// a finger is on the thumb this shows where it is going, not where the player
/// actually is (the two disagree during a drag on purpose), and the seek is
/// asked for only on release, to the exact frame rather than the nearest
/// keyframe.
private struct PlaybackBar: View {
    @ObservedObject var play: ClipPlayer
    @ObservedObject var clock: Playhead
    @State private var scrubbingTo: Double?

    var body: some View {
        let whole = max(play.length, 0.01)
        let shown = scrubbingTo ?? min(clock.seconds, whole)

        HStack(spacing: 10) {
            Button { play.toggle() } label: {
                Image(systemName: play.playing ? "pause.fill" : "play.fill")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 18)
            }
            .buttonStyle(.borderless)

            Text(timecode(shown))
                .font(.kitLabel.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)

            Slider(
                value: Binding(get: { shown }, set: { to in
                    if scrubbingTo == nil { play.beginScrub() }
                    scrubbingTo = to
                    play.scrub(to: to)
                }),
                in: 0...whole,
                onEditingChanged: { editing in
                    if editing {
                        play.beginScrub()
                    } else {
                        play.endScrub(at: scrubbingTo ?? shown)
                        scrubbingTo = nil
                    }
                }
            )

            Text(timecode(whole))
                .font(.kitLabel.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// The clip laid out along a line, with the kept piece bracketed.
///
/// The thumbnails are eight frames taken across the whole file — enough to find
/// the moment by eye, few enough to be there by the time he looks. They are
/// asked for once and kept; a drag redraws nothing but the bracket.
private struct TrimStrip: View {
    let url: URL
    let whole: Double
    /// What to draw: the engine's answer, or the drag in progress.
    let range: ClosedRange<Double>
    @Binding var live: ClosedRange<Double>?
    /// Told when the thumb is lifted, never during the drag: every write is an
    /// undo step, and a drag would otherwise leave forty of them behind.
    var onCommit: (Double, Double) -> Void

    @State private var pictures: [UIImage] = []
    /// Where the handle being dragged started, so it follows the thumb rather
    /// than jumping to it.
    @State private var from: Double?

    private let handle: CGFloat = 13

    var body: some View {
        GeometryReader { space in
            let width = max(space.size.width, 1)
            let x = { (second: Double) in
                CGFloat(min(max(second / max(whole, 0.001), 0), 1)) * width
            }

            ZStack(alignment: .leading) {
                strip
                    .frame(width: width, height: space.size.height)
                    .clipped() // A picture is never rounded (his rule, 2026-10-07).

                // What is being left out, said by dimming rather than by words.
                Color.black.opacity(0.55)
                    .frame(width: x(range.lowerBound))
                Color.black.opacity(0.55)
                    .frame(width: max(width - x(range.upperBound), 0))
                    .offset(x: x(range.upperBound))

                Rectangle()
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .frame(width: max(x(range.upperBound) - x(range.lowerBound), handle * 2))
                    .offset(x: x(range.lowerBound))

                grip(at: x(range.lowerBound) - handle / 2, end: false, width: width)
                grip(at: x(range.upperBound) - handle / 2, end: true, width: width)
            }
        }
        // **Both, and that is the bug this catches.** How long the file runs is
        // learned asynchronously, so the first run of this task sees nought and
        // the strip drew grey for ever. Keyed on the length as well, it fills in
        // the moment the answer arrives.
        .task(id: "\(url.absoluteString)|\(whole)") { await load() }
    }

    private var strip: some View {
        HStack(spacing: 0) {
            if pictures.isEmpty {
                Rectangle().fill(.quaternary)
            } else {
                ForEach(Array(pictures.enumerated()), id: \.offset) { _, picture in
                    Image(uiImage: picture)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .clipped()
                }
            }
        }
    }

    /// **The order of these modifiers is the whole thing working.**
    ///
    /// `offset` moves what is drawn; it does not move the view's *layout*
    /// frame. So a `contentShape` applied after it describes a hit area back at
    /// the un-offset position — both handles were quietly grabbable at the far
    /// left of the strip and nowhere near where they were drawn. The shape and
    /// the gesture go on first, and the offset carries them along.
    private func grip(at offset: CGFloat, end: Bool, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.accentColor)
            .frame(width: handle)
            .overlay {
                Capsule().fill(.white).frame(width: 2, height: 14)
            }
            // A thumb is wider than a handle: the target is padded out on both
            // sides so the strip can be grabbed without looking at it.
            .contentShape(Rectangle().inset(by: -16))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { move in
                        let started = from ?? (end ? range.upperBound : range.lowerBound)
                        if from == nil { from = started }
                        let by = Double(move.translation.width / width) * whole
                        live = moved(end: end, to: started + by)
                    }
                    .onEnded { _ in
                        from = nil
                        onCommit(range.lowerBound, range.upperBound)
                    }
            )
            .offset(x: offset)
    }

    /// A handle can never cross the other one, and never leave the clip.
    private func moved(end: Bool, to second: Double) -> ClosedRange<Double> {
        let least = 0.2
        if end {
            let to = min(max(second, range.lowerBound + least), whole)
            return range.lowerBound...to
        }
        let start = max(min(second, range.upperBound - least), 0)
        return start...range.upperBound
    }

    private func load() async {
        guard whole > 0, pictures.isEmpty else { return }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        // A thumbnail is for finding a moment, not for cutting on: the nearest
        // keyframe is both good enough and far quicker.
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        var made: [UIImage] = []
        for step in 0..<8 {
            let when = CMTime(seconds: whole * (Double(step) + 0.5) / 8, preferredTimescale: 600)
            guard let cg = try? await generator.image(at: when).image else { continue }
            made.append(UIImage(cgImage: cg))
        }
        pictures = made
    }
}

/// The player, and the two questions asked of it.
@MainActor
final class ClipPlayer: ObservableObject {
    let player = AVPlayer()
    /// How long the whole file runs, whatever this use plays of it.
    @Published private(set) var whole: Double = 0
    /// The shape of the picture, so it can be drawn at its own proportions
    /// rather than inside a box of somebody else's.
    @Published private(set) var shape: CGFloat = 16 / 9
    /// **How long what plays runs**: the kept piece of a trimmed clip, which
    /// is its own short item, or the whole file. The scrub bar runs over this,
    /// not over `whole`: it ran over the whole file, so on a trimmed clip a
    /// drag past the piece's end asked for a moment that is not there and
    /// nothing moved (his report, 2026-10-09: "scrubbing doesn't do anything").
    @Published private(set) var length: Double = 0
    /// **The playhead, on its own.** It ticks fifteen times a second, and it
    /// used to be published from here: every tick redrew the whole viewer,
    /// pages, trim strip and all, which is the lag he saw. Only the scrub bar
    /// watches this.
    let clock = Playhead()
    /// Where the playhead is, in the piece that is playing.
    var current: Double { clock.seconds }
    /// Whether it is moving. Ours to say, now that the system's own transport
    /// is turned off: set only by `toggle()` and by reaching the end.
    @Published private(set) var playing = false

    private var showing: URL?
    private var playingCut: Frames.Cut?
    private var timeToken: Any?
    private var endToken: NSObjectProtocol?

    init() {
        timeToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0 / 15, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            // Not while a scrub's seeks are still landing: the player still
            // reports where it was, and play would read that as the end and
            // start over from nought.
            guard let self, !self.scrubbing, !self.chasing else { return }
            let seconds = time.seconds
            self.clock.seconds = seconds.isFinite ? seconds : 0
        }
    }

    deinit {
        if let timeToken { player.removeTimeObserver(timeToken) }
        if let endToken { NotificationCenter.default.removeObserver(endToken) }
    }

    /// Where the playhead is, in the piece that is playing.
    var at: Double {
        let time = player.currentTime().seconds
        return time.isFinite ? time : 0
    }

    func load(url: URL, cut: Frames.Cut?) async {
        let fresh = showing != url
        guard fresh || playingCut != cut else { return }
        showing = url
        playingCut = cut
        let item = Clips.item(url, cut: cut)
        player.replaceCurrentItem(with: item)
        clock.seconds = 0
        playing = false
        if let endToken { NotificationCenter.default.removeObserver(endToken) }
        endToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in self?.playing = false }
        if fresh || whole == 0 {
            let asset = AVURLAsset(url: url)
            whole = (try? await asset.load(.duration).seconds) ?? 0
            // **Through the transform, not the raw size.** A clip shot upright
            // is stored on its side with a rotation beside it; the numbers
            // alone say landscape and would draw it in a letterbox lying down.
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let size = try? await track.load(.naturalSize),
               let turned = try? await track.load(.preferredTransform) {
                let drawn = size.applying(turned)
                let width = abs(drawn.width), height = abs(drawn.height)
                if width > 0, height > 0 { shape = width / height }
            }
        }
        length = cut.map { max($0.end - $0.start, 0) } ?? whole
        // **It plays when it opens** (his report, 2026-10-09: "doesn't play
        // when opened"). Opening a clip is asking to watch it.
        player.play()
        playing = true
    }

    /// Play from here, or pause. Picking up again from the end starts over,
    /// the way tapping play on a finished clip ought to.
    func toggle() {
        if playing {
            player.pause()
            playing = false
        } else {
            if length > 0, current >= length - 0.05 { seek(to: 0) }
            player.play()
            playing = true
        }
    }

    /// Lands on the exact frame asked for, not the nearest keyframe: a scrub
    /// that is close is not the point he dragged to.
    func seek(to second: Double) {
        let clamped = max(0, min(second, length))
        clock.seconds = clamped
        aim(at: clamped)
    }

    // ---- scrubbing: the picture follows the finger ---------------------------

    private var scrubbing = false
    private var resumeAfter = false
    private var target: CMTime?
    private var chasing = false

    /// A finger is on the bar: hold still, and remember whether to go on after.
    func beginScrub() {
        guard !scrubbing else { return }
        scrubbing = true
        resumeAfter = playing
        player.pause()
    }

    /// **Every move of the finger shows its frame.** It used to seek only on
    /// release, so a drag moved the thumb and nothing else. Seeks are chased
    /// rather than stacked: a new one is asked for only when the last has
    /// landed, always to wherever the finger is by then, so a fast drag never
    /// queues up a backlog to play through.
    func scrub(to second: Double) {
        let clamped = max(0, min(second, length))
        clock.seconds = clamped
        aim(at: clamped)
    }

    /// The finger is lifted: land exactly there, and carry on if it was playing.
    func endScrub(at second: Double) {
        seek(to: second)
        scrubbing = false
        if resumeAfter {
            player.play()
            playing = true
        }
    }

    private func aim(at second: Double) {
        target = CMTime(seconds: second, preferredTimescale: 600)
        if !chasing { chase() }
    }

    private func chase() {
        guard let next = target else { chasing = false; return }
        chasing = true
        target = nil
        // Exact, because a scrub that lands near is not the frame he stopped on.
        player.seek(to: next, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async { self?.chase() }
        }
    }

    /// The frame at a moment of the **whole file**, for standing in for it.
    nonisolated func frame(of url: URL, at second: Double) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        // Exactly the frame he is looking at, rather than the nearest keyframe.
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let when = CMTime(seconds: second, preferredTimescale: 600)
        guard let cg = try? await generator.image(at: when).image else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// The playhead's position, published apart from the player so a tick redraws
/// the scrub bar and nothing else.
final class Playhead: ObservableObject {
    @Published var seconds: Double = 0
}
