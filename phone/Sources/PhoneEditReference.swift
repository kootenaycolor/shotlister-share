import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Edit Reference on the phone (2026-10-17, take two)
//
// The first mod: a gold bracket joins the shots an edit reference cuts
// together, with a play button at its top. Drawn only while the project has
// the mod on (`Session.modsOn`); the engine keeps the data either way.
//
// Take two (his notes of 2026-10-17, mockup claude.ai/artifact/FVYQeLqxBLozvzHesfUKwg):
// one bracket across scene bands, in the margin beside the cards; the player
// is the clip, play and pause, a scrubber and close, blooming out of the
// play button; Add Edit Reference on the phone too; small touches (the
// bracket draws itself in, the shot on now glows, the button settles).

/// One row's piece of a bracket.
struct PhonePiece: Hashable {
    let ref: Engine.EditRef
    let first: Bool
    let last: Bool
    var lane: Int = 0
    /// Its place down the bracket, top first, for drawing itself in.
    var step: Int = 0
    var shot: String = ""
}

/// **Every bracket in the list as drawn**: each row's pieces, and where a
/// bracket passes a scene's band (`band:<scene>`) between its rows.
struct PhoneEditLayout {
    var pieces: [String: [PhonePiece]] = [:]
    var through: [String: [PhonePiece]] = [:]
    var any: Bool { !pieces.isEmpty }
}

/// **The bracket's moving parts**, watched by the bracket and the player
/// alone so nothing else redraws: the player open, where its button was, a
/// new bracket drawing itself in, the shot on now, a player folding back.
final class PhoneEditLive: ObservableObject {
    static let shared = PhoneEditLive()
    @Published var playing: Engine.EditRef?
    var from: CGRect?
    @Published var drawing: String?
    @Published var now: String?
    @Published var landed: String?
    static func token(_ id: String) -> String { id + "#" + UUID().uuidString }
    static func ref(of token: String?) -> String? { token.flatMap { $0.split(separator: "#").first.map(String.init) } }

    func play(_ ref: Engine.EditRef, from: CGRect?) {
        self.from = from
        playing = ref
    }
}

extension Session {
    var editRefsShown: [Engine.EditRef] {
        modsOn.contains(PhoneMods.editReference) ? (view?.editRefs ?? []) : []
    }

    /// **The brackets down the whole list**, scene after scene, so a run of
    /// 14A, 14B and 15A is one bracket over scene 15's band.
    func editLayout() -> PhoneEditLayout {
        let refs = editRefsShown
        guard !refs.isEmpty else { return PhoneEditLayout() }
        var line: [Engine.Row] = []
        var bandBefore: [Int: [String]] = [:]
        for scene in shownScenes {
            bandBefore[line.count, default: []].append("band:" + scene.id)
            line.append(contentsOf: rows(inScene: scene.id))
        }
        var out = PhoneEditLayout()
        for ref in refs {
            let joined = Set(ref.shots.map(\.shot))
            var i = 0
            while i < line.count {
                guard joined.contains(line[i].shot) else { i += 1; continue }
                var j = i
                while j + 1 < line.count, joined.contains(line[j + 1].shot) { j += 1 }
                let lane = (i...j).map { out.pieces[line[$0].id]?.count ?? 0 }.max() ?? 0
                var step = 0
                for k in i...j {
                    if k > i {
                        for band in bandBefore[k] ?? [] {
                            out.through[band, default: []].append(PhonePiece(ref: ref, first: false, last: false, lane: lane, step: step))
                            step += 1
                        }
                    }
                    out.pieces[line[k].id, default: []].append(
                        PhonePiece(ref: ref, first: k == i, last: k == j, lane: lane, step: step, shot: line[k].shot))
                    step += 1
                }
                i = j + 1
            }
        }
        return out
    }

    /// Each row's pieces, for a single scene's own list.
    func editPieces(_ rows: [Engine.Row]) -> [String: [PhonePiece]] {
        let all = editLayout().pieces
        var out: [String: [PhonePiece]] = [:]
        for row in rows { if let p = all[row.id] { out[row.id] = p } }
        return out
    }

    /// **Make one** from the phone: the shots in the order given, then its
    /// clip or stills, then its link. Answers the new one's id.
    func addEditRef(name: String, shots: [String], clip: URL?, stills: [Data], link: String) async -> String? {
        guard let engine else { return nil }
        let before = Set((view?.editRefs ?? []).map(\.id))
        _ = engine.raw(["addeditref", name, shots.joined(separator: ",")])
        refresh()
        guard let made = view?.editRefs?.first(where: { !before.contains($0.id) }) else { return nil }
        if let clip { await attach(clipAt: clip, to: made.id) }
        for still in stills { attach(still, named: "", toBoard: made.id) }
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if !link.isEmpty { _ = engine.raw(["editreflink", made.id, link]) }
        refresh()
        return made.id
    }

    func editRefCall(_ parts: String...) {
        guard let engine else { return }
        _ = engine.raw(parts)
        refresh()
    }
}

/// `0:12`.
func phoneClock(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.rounded(.down)))
    return "\(s / 60):" + String(format: "%02d", s % 60)
}

private var phoneCalm: Bool {
    UIAccessibility.isReduceMotionEnabled || ProcessInfo.processInfo.arguments.contains("--reducemotion")
}

// MARK: - the bracket in a scene's own list

/// **The bracket beside a row** in a scene's own list: the line, a dot at the
/// row, the play button on the first, a hook under the last. Runs past the
/// row's own edges so the line reads unbroken down the list.
struct PhoneBracket: View {
    let pieces: [PhonePiece]
    let play: (Engine.EditRef) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(pieces, id: \.ref.id) { piece in
                GeometryReader { geo in
                    let h = geo.size.height
                    ZStack(alignment: .topLeading) {
                        Path { p in
                            p.move(to: CGPoint(x: 9, y: piece.first ? 14 : -14))
                            if piece.last {
                                p.addLine(to: CGPoint(x: 9, y: h + 2))
                                p.addQuadCurve(to: CGPoint(x: 15, y: h + 7), control: CGPoint(x: 9, y: h + 7))
                            } else {
                                p.addLine(to: CGPoint(x: 9, y: h + 14))
                            }
                        }
                        .stroke(PhoneMods.gold, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        if piece.first {
                            PhonePlayButton(ref: piece.ref) { rect in
                                PhoneEditLive.shared.play(piece.ref, from: rect)
                                play(piece.ref)
                            }
                            .position(x: 9, y: 14)
                        } else {
                            PhoneNowDot(piece: piece).position(x: 9, y: 14)
                        }
                    }
                }
                .frame(width: 18)
            }
        }
    }
}

/// The gold play button: 22 points to see, 44 to press; it settles with a
/// small spring when the player folds back into it.
struct PhonePlayButton: View {
    let ref: Engine.EditRef
    let tapped: (CGRect) -> Void
    @ObservedObject private var live = PhoneEditLive.shared
    @State private var settle: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            Button { tapped(geo.frame(in: .global)) } label: {
                ZStack {
                    Circle().fill(PhoneMods.gold)
                    Image(systemName: "play.fill").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.85)).offset(x: 0.5)
                }
                .frame(width: 22, height: 22)
                .shadow(color: PhoneMods.gold.opacity(live.now?.hasPrefix(ref.id + ":") == true && isFirstNow ? 0.9 : 0), radius: 6)
                .scaleEffect(settle)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(PhonePressStyle())
            .accessibilityLabel("Play \(ref.name)")
            .accessibilityIdentifier("editref.play")
        }
        .frame(width: 44, height: 44)
        .onChange(of: live.landed) { _, token in
            guard PhoneEditLive.ref(of: token) == ref.id, !phoneCalm else { return }
            settle = 1.3
            withAnimation(.spring(response: 0.32, dampingFraction: 0.5)) { settle = 1 }
        }
    }

    private var isFirstNow: Bool { live.now == ref.id + ":" + (ref.shots.first?.shot ?? "") }
}

/// A press that gives: the button squeezes a touch under the finger.
struct PhonePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !phoneCalm ? 0.88 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// A row's gold dot; it glows while its shot is the one on now.
struct PhoneNowDot: View {
    let piece: PhonePiece
    @ObservedObject private var live = PhoneEditLive.shared
    private var on: Bool { live.now == piece.ref.id + ":" + piece.shot }
    var body: some View {
        Circle().fill(PhoneMods.gold).frame(width: 7, height: 7)
            .shadow(color: PhoneMods.gold.opacity(on ? 0.95 : 0), radius: on ? 5 : 0)
            .scaleEffect(on && !phoneCalm ? 1.6 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: on)
    }
}

// MARK: - the bracket beside the whole list's cards

/// Each row's bounds, for the bracket drawn beside a scene's card.
struct PhoneRowBounds: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// **The margin beside the cards**, when a bracket is drawn: the cards step
/// in to make room, and the bands' words with them.
enum PhoneEditMargin {
    static let width: CGFloat = 26
    /// The line's middle, from the screen's edge, for lane 0.
    static let x: CGFloat = 13
    static func x(_ lane: Int) -> CGFloat { x - CGFloat(lane) * 7 }
}

/// **One scene's part of the brackets**, over its card: each piece from its
/// row's top to its bottom, running on to the card's top or the gap below
/// when the bracket carries on across a band.
struct PhoneSceneBracket: View {
    let rows: [Engine.Row]
    let layout: PhoneEditLayout
    let anchors: [String: Anchor<CGRect>]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { at, row in
                    if let pieces = layout.pieces[row.id], let anchor = anchors[row.id] {
                        let rect = geo[anchor]
                        ForEach(pieces, id: \.ref.id) { piece in
                            PhoneMarginPiece(piece: piece, rect: rect,
                                             top: at == 0 ? 0 : nil,
                                             bottom: at == rows.count - 1 ? geo.size.height : nil,
                                             space: geo.frame(in: .global))
                        }
                    }
                }
            }
        }
    }
}

/// One row's piece, in the margin.
private struct PhoneMarginPiece: View {
    let piece: PhonePiece
    let rect: CGRect
    /// Where to start when it carries on from above: the card's top.
    let top: CGFloat?
    /// Where to end when it carries on below: the gap under the card.
    let bottom: CGFloat?
    let space: CGRect
    @ObservedObject private var live = PhoneEditLive.shared
    @State private var drawn: CGFloat = 1

    var body: some View {
        let x = PhoneEditMargin.x(piece.lane)
        let dotY = rect.minY + 22
        let from = piece.first ? dotY : (top ?? rect.minY - 1)
        let to = piece.last ? rect.maxY - 14 : (bottom ?? rect.maxY + 1)
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: x, y: from))
                p.addLine(to: CGPoint(x: x, y: to))
                if piece.last {
                    p.addQuadCurve(to: CGPoint(x: x + 7, y: to + 7), control: CGPoint(x: x, y: to + 7))
                }
            }
            .trim(from: 0, to: drawn)
            .stroke(PhoneMods.gold, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            if piece.first {
                PhonePlayButton(ref: piece.ref) { rect in PhoneEditLive.shared.play(piece.ref, from: rect) }
                    .scaleEffect(drawn < 1 ? max(0.001, drawn) : 1)
                    .position(x: x, y: dotY)
            } else {
                PhoneNowDot(piece: piece)
                    .scaleEffect(drawn < 1 ? max(0.001, drawn) : 1)
                    .position(x: x, y: dotY)
            }
        }
        .onChange(of: live.drawing) { _, token in drawIn(token) }
        .onAppear { drawIn(live.drawing) }
    }

    private func drawIn(_ token: String?) {
        guard PhoneEditLive.ref(of: token) == piece.ref.id, !phoneCalm else { return }
        drawn = 0
        withAnimation(.easeOut(duration: 0.16).delay(Double(piece.step) * 0.08)) { drawn = 1 }
    }
}

/// The line passing a scene's band, at the margin's place.
struct PhoneBandThrough: View {
    let pieces: [PhonePiece]
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(pieces, id: \.ref.id) { piece in
                PhoneBandLine(piece: piece)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private struct PhoneBandLine: View {
        let piece: PhonePiece
        @ObservedObject private var live = PhoneEditLive.shared
        @State private var drawn: CGFloat = 1
        var body: some View {
            Rectangle().fill(PhoneMods.gold)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .scaleEffect(x: 1, y: drawn, anchor: .top)
                .offset(x: PhoneEditMargin.x(piece.lane) - 1)
                .onChange(of: live.drawing) { _, token in
                    guard PhoneEditLive.ref(of: token) == piece.ref.id, !phoneCalm else { return }
                    drawn = 0
                    withAnimation(.easeOut(duration: 0.16).delay(Double(piece.step) * 0.08)) { drawn = 1 }
                }
        }
    }
}

// MARK: - the player

final class PhoneEditPlayback: ObservableObject {
    @Published var time: Double = 0
    @Published var playing = false
    let player = AVPlayer()
    private var watcher: Any?
    private var ticker: Timer?
    private(set) var length: Double = 0
    private(set) var stillsOnly = false
    var scrubbing = false

    func load(clip: URL?, length: Double) {
        self.length = length
        stillsOnly = clip == nil
        guard let clip else { return }
        player.replaceCurrentItem(with: AVPlayerItem(url: clip))
        watcher = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1.0 / 30, preferredTimescale: 600), queue: .main) { [weak self] t in
            guard let self, !self.scrubbing else { return }
            self.time = CMTimeGetSeconds(t)
            if self.length > 0, self.time >= self.length - 0.03, self.playing { self.playing = false }
        }
    }

    func toggle() { playing ? pause() : play() }

    func play() {
        if length > 0, time >= length - 0.1 { seek(0) }
        playing = true
        if stillsOnly {
            ticker?.invalidate()
            ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                guard let self, !self.scrubbing else { return }
                self.time = min(self.length, self.time + 1.0 / 30)
                if self.time >= self.length { self.pause() }
            }
        } else {
            player.play()
        }
    }

    func pause() {
        playing = false
        ticker?.invalidate()
        player.pause()
    }

    func seek(_ to: Double) {
        time = max(0, length > 0 ? min(to, length) : to)
        if !stillsOnly { player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
    }

    func stop() {
        pause()
        if let watcher { player.removeTimeObserver(watcher) }
        watcher = nil
        player.replaceCurrentItem(with: nil)
    }
}

private struct PhoneClipSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> Surface { let v = Surface(); v.layer.player = player; return v }
    func updateUIView(_ v: Surface, context: Context) { v.layer.player = player }
    final class Surface: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        override var layer: AVPlayerLayer { super.layer as! AVPlayerLayer }
        override init(frame: CGRect) { super.init(frame: frame); layer.videoGravity = .resizeAspect; backgroundColor = .clear }
        required init?(coder: NSCoder) { fatalError() }
    }
}

/// **The scrubber**, 44 points tall to hold: a gold fill to the playhead, a
/// knob that lifts in a gold halo while held.
struct PhoneScrubber: View {
    @ObservedObject var playback: PhoneEditPlayback
    @State private var held = ProcessInfo.processInfo.arguments.contains("--editrefheld")

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let p = playback.length > 0 ? CGFloat(playback.time / playback.length) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill)).frame(height: 4)
                Capsule().fill(PhoneMods.gold).frame(width: max(4, w * p), height: 4)
                    .shadow(color: PhoneMods.gold.opacity(playback.playing ? 0.6 : 0), radius: 4)
                Circle().fill(PhoneMods.gold.opacity(held ? 0.3 : 0)).frame(width: 30, height: 30)
                    .offset(x: w * p - 15)
                Circle().fill(Color.white).shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                    .frame(width: 18, height: 18)
                    .scaleEffect(held && !phoneCalm ? 1.3 : 1)
                    .offset(x: w * p - 9)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if !held { withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { held = true } }
                    playback.scrubbing = true
                    playback.seek(Double(max(0, min(1, g.location.x / w))) * playback.length)
                }
                .onEnded { _ in
                    playback.scrubbing = false
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { held = false }
                })
        }
        .frame(height: 44)
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue("\(phoneClock(playback.time)) of \(phoneClock(playback.length))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: playback.seek(playback.time + 5)
            case .decrement: playback.seek(playback.time - 5)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("editref.scrubber")
    }
}

/// **The player card**: the name, the clip, play and pause, the scrubber with
/// the time, close. Nothing about cuts.
struct PhoneEditReferencePlayer: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var frames: Frames
    let ref: Engine.EditRef
    @ObservedObject var playback: PhoneEditPlayback
    var cover: Double
    var close: () -> Void
    @State private var renaming = false
    @State private var newName = ""
    @State private var deleting = false

    static func shape(_ ref: Engine.EditRef) -> CGFloat {
        if let c = ref.clip ?? ref.stills.first, let w = c.width, let h = c.height, w > 0, h > 0 { return CGFloat(w) / CGFloat(h) }
        return 16 / 9
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(ref.name).font(.headline).lineLimit(1)
                    Text(ref.range + (ref.length > 0 ? " · \(phoneClock(ref.length))" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Menu {
                    if !ref.link.isEmpty, let url = URL(string: ref.link) {
                        Link(destination: url) { Label("Open Link", systemImage: "link") }
                    }
                    Button { newName = ref.name; renaming = true } label: { Label("Rename…", systemImage: "pencil") }
                    Button(role: .destructive) { deleting = true } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").font(.body.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .tint(.secondary)
                .accessibilityLabel("More")
                Button(action: close) {
                    Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("editref.close")
            }
            .padding(.leading, 14)
            picture
            HStack(spacing: 6) {
                Button { playback.toggle() } label: {
                    Image(systemName: playback.playing ? "pause.fill" : "play.fill")
                        .font(.title3).foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playback.playing ? "Pause" : "Play")
                .accessibilityIdentifier("editref.toggle")
                PhoneScrubber(playback: playback)
                Text("\(phoneClock(playback.time)) / \(phoneClock(ref.length))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .fixedSize()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .alert("Rename Edit Reference", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Rename") { session.editRefCall("renameeditref", ref.id, newName) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \(ref.name)?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                session.editRefCall("deleteeditref", ref.id)
                close()
            }
        } message: {
            Text("The shots stay.")
        }
    }

    private var picture: some View {
        ZStack {
            Color.black
            if let clip = ref.clip {
                if let poster = frames.image(hash: clip.hash, ext: "png") {
                    Image(uiImage: poster).resizable().aspectRatio(contentMode: .fit)
                }
                PhoneClipSurface(player: playback.player)
            } else if !ref.stills.isEmpty {
                let at = ref.length > 0 ? min(ref.stills.count - 1, Int(playback.time / ref.length * Double(ref.stills.count))) : 0
                let still = ref.stills[max(0, at)]
                if let image = frames.image(hash: still.hash, ext: still.ext) {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                }
            } else if !ref.link.isEmpty, let url = URL(string: ref.link) {
                Link("Open Link", destination: url).foregroundStyle(.white)
            }
            PhoneMods.gold.opacity(cover)
                .overlay {
                    Image(systemName: "play.fill").font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.85)).opacity(cover)
                }
                .allowsHitTesting(false)
        }
        .aspectRatio(Self.shape(ref), contentMode: .fit)
        .contentShape(Rectangle())
        .onTapGesture { playback.toggle() }
    }
}

/// **The play reveal on the phone**: the gold button blooms into the player
/// card on a spring, the gold lifts as the clip starts, and closing folds it
/// back into the button. Reduce Motion makes both a fade.
struct PhoneEditStage: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var frames: Frames
    @ObservedObject private var live = PhoneEditLive.shared
    @StateObject private var playback = PhoneEditPlayback()
    @State private var shown: Engine.EditRef?
    @State private var from: CGRect?
    @State private var bloom: CGFloat = 0
    @State private var cover: Double = 1

    var body: some View {
        GeometryReader { geo in
            if let ref = shown {
                let space = geo.frame(in: .global)
                let width = min(560, geo.size.width - 20)
                let height = width / PhoneEditReferencePlayer.shape(ref) + 44 + 56
                let start = from.map { CGPoint(x: $0.midX - space.minX, y: $0.midY - space.minY) }
                    ?? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let scale = max(0.02, 22 / width)
                ZStack {
                    Color.black.opacity(0.42 * Double(min(1, bloom)))
                        .contentShape(Rectangle())
                        .onTapGesture { closeIt() }
                    PhoneEditReferencePlayer(ref: session.view?.editRefs?.first { $0.id == ref.id } ?? ref,
                                             playback: playback, cover: cover, close: { closeIt() })
                        .environmentObject(session)
                        .environmentObject(frames)
                        .frame(width: width)
                        .clipShape(RoundedRectangle(cornerRadius: lerp(height / 2, 14, bloom), style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: lerp(height / 2, 14, bloom), style: .continuous)
                                .fill(PhoneMods.gold)
                                .opacity(phoneCalm ? 0 : Double(max(0, 1 - min(1, bloom) * 1.5)))
                                .allowsHitTesting(false)
                        }
                        .shadow(color: .black.opacity(0.4 * Double(min(1, bloom))), radius: 24, y: 12)
                        .scaleEffect(lerp(scale, 1, bloom))
                        .offset(x: lerp(start.x - geo.size.width / 2, 0, bloom),
                                y: lerp(start.y - geo.size.height / 2, 0, bloom))
                        .opacity(phoneCalm ? Double(min(1, bloom)) : 1)
                        .accessibilityAddTraits(.isModal)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .allowsHitTesting(shown != nil)
        .onChange(of: live.playing) { _, ref in
            if let ref { open(ref) } else if shown != nil { closeIt() }
        }
        .onReceive(playback.$time) { t in
            guard let ref = shown, !ref.shots.isEmpty else { return }
            let at = ref.shots.lastIndex { $0.start <= t + 0.001 } ?? 0
            let now = ref.id + ":" + ref.shots[at].shot
            if live.now != now { live.now = now }
        }
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    private func open(_ ref: Engine.EditRef) {
        playback.stop()
        from = live.from
        shown = ref
        bloom = 0
        cover = 1
        let args = ProcessInfo.processInfo.arguments
        Task { @MainActor in
            var url: URL?
            if let clip = ref.clip {
                for _ in 0..<40 {
                    url = frames.movie(hash: clip.hash, ext: clip.ext)
                    if url != nil { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            playback.load(clip: url, length: ref.length)
            if let at = args.firstIndex(of: "--editrefbloom"), at + 1 < args.count, let stop = Double(args[at + 1]) {
                bloom = CGFloat(stop)
                cover = stop < 0.6 ? 1 : max(0, 1 - (stop - 0.6) / 0.4)
                return
            }
            if phoneCalm {
                withAnimation(.easeOut(duration: 0.2)) { bloom = 1; cover = 0 }
            } else {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.74)) { bloom = 1 }
                withAnimation(.easeOut(duration: 0.22).delay(0.26)) { cover = 0 }
            }
            if let at = args.firstIndex(of: "--editrefat"), at + 1 < args.count, let t = Double(args[at + 1]) {
                print("editref player: clip \(url?.lastPathComponent ?? "none")")
                playback.seek(t)
            } else {
                try? await Task.sleep(nanoseconds: phoneCalm ? 50_000_000 : 260_000_000)
                playback.play()
            }
        }
    }

    private func closeIt() {
        guard let ref = shown else { return }
        playback.pause()
        let done = {
            playback.stop()
            shown = nil
            live.now = nil
            live.landed = PhoneEditLive.token(ref.id)
            if live.playing != nil { live.playing = nil }
        }
        if phoneCalm {
            withAnimation(.easeIn(duration: 0.16)) { bloom = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: done)
        } else {
            withAnimation(.easeIn(duration: 0.13)) { cover = 1 }
            withAnimation(.easeIn(duration: 0.26)) { bloom = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26, execute: done)
        }
    }
}

// MARK: - adding one

/// **Add Edit Reference on the phone** (the mockup's iPhone sheet): the clip
/// from Photos or Files with its first frame, Name, Link, and the shots.
struct PhoneAddEditReference: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    let shots: [String]

    @State private var picked: PhotosPickerItem?
    @State private var importing = false
    @State private var clip: URL?
    @State private var stills: [Data] = []
    @State private var poster: UIImage?
    @State private var seconds: Double = 0
    @State private var filename = ""
    @State private var name = ""
    @State private var link = ""
    @State private var adding = false
    @State private var failed = false

    private var rows: [Engine.Row] {
        let all = session.view?.groups.flatMap(\.rows) ?? []
        return shots.compactMap { s in all.first { $0.shot == s } }
    }
    private var trimmedLink: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var linkWrong: Bool {
        guard !trimmedLink.isEmpty else { return false }
        let full = trimmedLink.contains("://") ? trimmedLink : "https://" + trimmedLink
        guard let url = URL(string: full), let host = url.host, host.contains(".") else { return true }
        return trimmedLink.contains(" ")
    }
    private var ready: Bool { (clip != nil || !stills.isEmpty || !trimmedLink.isEmpty) && !linkWrong && !adding }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if clip != nil || !stills.isEmpty {
                        ZStack(alignment: .bottom) {
                            Color.black
                            if let poster { Image(uiImage: poster).resizable().aspectRatio(contentMode: .fit) }
                            HStack {
                                Text(filename).font(.caption.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                if seconds > 0 { Text(phoneClock(seconds)).font(.caption.monospacedDigit()) }
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 8)
                            .background(LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                        }
                        .aspectRatio(posterShape, contentMode: .fit)
                        .listRowInsets(EdgeInsets())
                    }
                    PhotosPicker(selection: $picked, matching: .any(of: [.videos, .images])) {
                        Label(clip == nil && stills.isEmpty ? "Choose from Photos" : "Replace from Photos", systemImage: "photo.on.rectangle")
                    }
                    Button { importing = true } label: {
                        Label("Choose from Files", systemImage: "folder")
                    }
                } header: { Text("Clip") }
                Section {
                    LabeledContent("Name") {
                        TextField("Edit Reference", text: $name).multilineTextAlignment(.leading)
                    }
                    LabeledContent("Link") {
                        TextField("Optional", text: $link)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    if linkWrong {
                        Text("Not a link").font(.footnote).foregroundStyle(.red)
                    }
                }
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(rows) { row in
                                Text(row.number).font(.footnote.weight(.semibold).monospacedDigit())
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(PhoneMods.gold.opacity(0.18)))
                            }
                        }
                    }
                } header: { Text("Shots") }
                if failed {
                    Text("Couldn't add the edit reference").foregroundStyle(.red)
                }
            }
            .navigationTitle("Edit Reference")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if adding { ProgressView() } else {
                        Button("Add", action: add).fontWeight(.semibold).disabled(!ready)
                            .accessibilityIdentifier("editref.add")
                    }
                }
            }
            .onAppear {
                // A checking run: `--editreffile <name in Documents>` takes
                // that clip; `--editrefaddnow` presses Add.
                let args = ProcessInfo.processInfo.arguments
                if let at = args.firstIndex(of: "--editreffile"), at + 1 < args.count {
                    take(URL.documentsDirectory.appending(path: args[at + 1]))
                    name = "Phone Cut"
                    if args.contains("--editrefaddnow") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { add() }
                    }
                }
            }
            .onChange(of: picked) { _, item in
                guard let item else { return }
                Task { await bringIn(item) }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.movie, .image], allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                let reading = url.startAccessingSecurityScopedResource()
                defer { if reading { url.stopAccessingSecurityScopedResource() } }
                let copy = URL.temporaryDirectory.appending(path: "editref-\(UUID().uuidString)-\(url.lastPathComponent)")
                try? FileManager.default.copyItem(at: url, to: copy)
                take(copy)
            }
        }
    }

    private var posterShape: CGFloat {
        guard let poster, poster.size.height > 0 else { return 2.39 }
        return max(1.2, min(2.8, poster.size.width / poster.size.height))
    }

    private func bringIn(_ item: PhotosPickerItem) async {
        if let file = try? await item.loadTransferable(type: Picked.self) {
            take(file.url)
        } else if let data = try? await item.loadTransferable(type: Data.self) {
            stills = [data]; clip = nil
            poster = UIImage(data: data); seconds = 0; filename = "Still"
        }
    }

    private func take(_ url: URL) {
        filename = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        if ["mov", "mp4", "m4v"].contains(ext) {
            clip = url; stills = []
            let asset = AVURLAsset(url: url)
            Task {
                let length = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                let image = try? await generator.image(at: CMTime(seconds: min(0.5, max(length - 0.1, 0)), preferredTimescale: 600)).image
                await MainActor.run {
                    seconds = length.isFinite ? length : 0
                    poster = image.map { UIImage(cgImage: $0) }
                }
            }
        } else if let data = try? Data(contentsOf: url) {
            stills = [data]; clip = nil
            poster = UIImage(data: data); seconds = 0
        }
    }

    private func add() {
        guard ready else { return }
        adding = true
        failed = false
        let link = trimmedLink.isEmpty || trimmedLink.contains("://") ? trimmedLink : "https://" + trimmedLink
        Task { @MainActor in
            let made = await session.addEditRef(name: name, shots: shots, clip: clip, stills: stills, link: link)
            adding = false
            guard let made else { failed = true; return }
            dismiss()
            try? await Task.sleep(nanoseconds: 450_000_000)
            PhoneEditLive.shared.drawing = PhoneEditLive.token(made)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            PhoneEditLive.shared.drawing = nil
        }
    }
}
