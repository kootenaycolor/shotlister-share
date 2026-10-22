import AppKit
import AVFoundation
import ImageIO
import SwiftUI

/// **A shot's Print Frame** — the one picture that stands for a shot in every
/// PDF, made from its stills and from any moments of its clips. His ask,
/// 2026-10-14; the drawing is `design/45-print-frame.html`.
///
/// The engine keeps the spec (layout, frames, numbers, board arrows) and the
/// picture the Mac last baked from it (`engine/src/printframe.rs`). This file
/// is the Mac's half of that: reading the spec, the pictures it is made of,
/// the board as drawn, and the baking — on every change, and in the
/// background for any shot whose bake is stale. The editor is in
/// `PrintFrameEditor.swift`; the layout arithmetic in `PrintFrameLayout.swift`.

// ------------------------------------------------------------ what is stored

/// `printFrame` on a row of the view, as the engine gives it.
struct PrintFrameView: Decodable, Equatable {
    var layout: String
    var numbers: Bool
    var frames: [Frame]
    var arrows: String?
    var digest: String
    var baked: Baked?
    var stale: Bool

    struct Frame: Decodable, Equatable {
        var use: String
        var at: Double?
        var live: Bool?
    }
    struct Baked: Decodable, Equatable {
        var hash: String
        var ext: String
        var width: Int
        var height: Int
        var digest: String
    }

    /// The spec, with frames whose picture has come off the shot dropped.
    var spec: PrintFrameSpec {
        PrintFrameSpec(layout: layout, numbers: numbers,
                       frames: frames.filter { $0.live ?? true }
                           .map { PrintFrameSpec.Moment(use: $0.use, at: $0.at) },
                       arrows: ViewModel.Arrow.parse(arrows))
    }
}

/// The spec as the editor works on it.
struct PrintFrameSpec: Equatable {
    struct Moment: Equatable, Hashable {
        /// The media ref of a picture on this shot.
        var use: String
        /// For a clip, seconds from the start of the whole clip.
        var at: Double?
    }
    var layout: String
    var numbers: Bool
    var frames: [Moment]
    var arrows: [ViewModel.Arrow] = []

    /// The engine's JSON form.
    var json: String {
        var body: [String: Any] = ["layout": layout, "numbers": numbers]
        body["frames"] = frames.map { m -> [String: Any] in
            var one: [String: Any] = ["use": m.use]
            if let at = m.at { one["at"] = (at * 1000).rounded() / 1000 }
            return one
        }
        if !arrows.isEmpty { body["arrows"] = ViewModel.Arrow.encode(arrows) }
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// **What prints today**, so opening the editor changes nothing until he
    /// changes something: a clip's four moments, two by two and numbered
    /// (`Filmstrip.atFraction`, across the kept part); a still on its own.
    static func auto(for row: ViewModel.Row, clipLength: (ViewModel.Still) -> Double?) -> PrintFrameSpec? {
        let usable = row.stills.filter { PrintFrameSpec.usable($0) }
        guard let key = usable.first(where: \.key) ?? usable.first else { return nil }
        if key.movie, let whole = clipLength(key), whole > 0.2 {
            let from = max(0, min(key.trimStart ?? 0, whole))
            let to = min(max(key.trimEnd ?? whole, from + 0.2), whole)
            let span = to - from
            let moments = [0.08, 0.36, 0.64, 0.92].map {
                Moment(use: key.ref, at: from + min(max(span * $0, 0), span - 0.05))
            }
            return PrintFrameSpec(layout: "grid22", numbers: true, frames: moments)
        }
        if key.movie {
            return PrintFrameSpec(layout: "one", numbers: false,
                                  frames: [Moment(use: key.ref, at: key.trimStart ?? 0)])
        }
        return PrintFrameSpec(layout: "one", numbers: false, frames: [Moment(use: key.ref, at: nil)])
    }

    /// **Where the editor starts** when nothing is stored: one frame. His
    /// note, 2026-10-14: he is usually not starting with four. A clip's one
    /// moment is the middle of its kept part; a still is its key picture
    /// alone. Shown only: nothing is saved until he changes something, so
    /// the PDF keeps printing `auto` until then.
    static func start(for row: ViewModel.Row, clipLength: (ViewModel.Still) -> Double?) -> PrintFrameSpec? {
        let usable = row.stills.filter { PrintFrameSpec.usable($0) }
        guard let key = usable.first(where: \.key) ?? usable.first else { return nil }
        guard key.movie else {
            return PrintFrameSpec(layout: "one", numbers: false, frames: [Moment(use: key.ref, at: nil)])
        }
        let from = max(key.trimStart ?? 0, 0)
        let at: Double
        if let to = key.trimEnd ?? clipLength(key), to > from {
            at = (from + to) / 2
        } else {
            at = from
        }
        return PrintFrameSpec(layout: "one", numbers: false, frames: [Moment(use: key.ref, at: at)])
    }

    /// A picture that can be a frame: a still or a clip. Not a PDF.
    static func usable(_ still: ViewModel.Still) -> Bool {
        still.movie || still.kind == "image" || still.kind == "gif" || still.kind == nil
            && ["jpg", "jpeg", "png", "heic", "tif", "tiff", "gif", "webp"].contains(still.ext.lowercased())
    }
}

extension ViewModel.Still {
    /// Whether he has chosen a crop on this use. A still in a Print Frame is
    /// its whole picture unless he has; then it is the crop, in the film's
    /// shape — his choice, kept.
    var hasCrop: Bool { cropX != nil || cropY != nil || cropScale != nil }
}

extension Engine {
    /// Set a shot's Print Frame. One undo step.
    func setPrintFrame(_ shot: String, _ spec: PrintFrameSpec) -> ViewModel? {
        decode(call("printframe", shot, spec.json))
    }
    /// No Print Frame: the shot prints as it always did.
    func clearPrintFrame(_ shot: String) -> ViewModel? {
        decode(call("printframe", shot, "clear"))
    }
    /// File the baked board for the spec whose digest is `digest`.
    @discardableResult
    func bakePrintFrame(_ shot: String, digest: String, width: Int, height: Int,
                        jpeg: Data) -> Bool {
        let reply = call("printframebake", shot, digest, String(width), String(height),
                         "jpg", jpeg.base64EncodedString())
        let text = String(data: reply, encoding: .utf8) ?? ""
        return !text.contains("\"error\"")
    }
}

// ------------------------------------------------------------ the pictures

/// **The pictures a board is made of**, decoded off the main thread and kept.
///
/// A still is read once at up to 2400 pixels; a clip's moment is the exact
/// frame (`AVAssetImageGenerator` with no tolerance, as `FrameExport`), and a
/// scrub asks for many — only the latest one waiting for each clip is made,
/// so the board keeps up with the hand rather than with every point it
/// passed through.
final class PrintFramePictures: ObservableObject {
    static let shared = PrintFramePictures()

    /// Bumped whenever a picture arrives, so a board redraws.
    @Published private(set) var arrivals = 0

    private var stills: [String: NSImage] = [:]
    private var moments: [String: [Int: NSImage]] = [:]
    private var strips: [String: [NSImage]] = [:]
    private var lengths: [String: Double] = [:]
    private var asking: Set<String> = []
    /// The moment waiting to be made for each clip, latest wins.
    private var waiting: [String: (url: URL, at: Double)] = [:]
    private var working: Set<String> = []

    private let queue = DispatchQueue(label: "shotlister.printframe.pictures", qos: .userInitiated)
    /// Touched only on `queue`.
    private var generators: [String: AVAssetImageGenerator] = [:]

    private static func ms(_ at: Double) -> Int { Int((at * 1000).rounded()) }

    // ---- where the bytes are (main thread: the engine is asked) -----------

    static func file(_ still: ViewModel.Still, engine: Engine?) -> URL? {
        still.movie ? Clips.file(hash: still.hash, ext: still.ext, from: engine)
                    : Viewer.onDisk(hash: still.hash, ext: still.ext, from: engine)
    }

    // ---- asking, from a view (main thread) --------------------------------

    func still(_ still: ViewModel.Still, engine: Engine?) -> NSImage? {
        if let held = stills[still.hash] { return held }
        let key = "s" + still.hash
        guard !asking.contains(key), let url = Self.file(still, engine: engine) else { return nil }
        asking.insert(key)
        queue.async { [weak self] in
            let made = Self.decodeStill(url)
            DispatchQueue.main.async {
                guard let self else { return }
                self.asking.remove(key)
                if let made { self.stills[still.hash] = made; self.arrivals += 1 }
            }
        }
        return nil
    }

    /// The exact moment if it has been made; otherwise the nearest one made
    /// so far from this clip (and the exact one is asked for).
    func moment(_ clip: ViewModel.Still, at: Double, engine: Engine?) -> NSImage? {
        let k = Self.ms(at)
        if let held = moments[clip.hash]?[k] { return held }
        if let url = Self.file(clip, engine: engine) { ask(clip.hash, url: url, at: at) }
        guard let made = moments[clip.hash], !made.isEmpty else { return nil }
        return made.min { abs($0.key - k) < abs($1.key - k) }?.value
    }

    func length(_ clip: ViewModel.Still, engine: Engine?) -> Double? {
        if let held = lengths[clip.hash] { return held }
        _ = strip(clip, engine: engine)
        return nil
    }

    /// Twelve small frames across the whole clip, for its strip.
    func strip(_ clip: ViewModel.Still, engine: Engine?) -> [NSImage] {
        if let held = strips[clip.hash] { return held }
        let key = "c" + clip.hash
        guard !asking.contains(key), let url = Self.file(clip, engine: engine) else { return [] }
        asking.insert(key)
        queue.async { [weak self] in
            let asset = AVURLAsset(url: url)
            let whole = CMTimeGetSeconds(asset.duration)
            var thumbs: [NSImage] = []
            if whole.isFinite, whole > 0 {
                let g = AVAssetImageGenerator(asset: asset)
                g.appliesPreferredTrackTransform = true
                g.maximumSize = CGSize(width: 240, height: 240)
                let slack = CMTime(seconds: 0.5, preferredTimescale: 600)
                g.requestedTimeToleranceBefore = slack
                g.requestedTimeToleranceAfter = slack
                for i in 0..<12 {
                    let t = whole * (Double(i) + 0.5) / 12
                    if let cg = try? g.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600),
                                                   actualTime: nil) {
                        thumbs.append(NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height)))
                    }
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.asking.remove(key)
                self.strips[clip.hash] = thumbs
                if whole.isFinite, whole > 0 { self.lengths[clip.hash] = whole }
                self.arrivals += 1
            }
        }
        return []
    }

    private func ask(_ hash: String, url: URL, at: Double) {
        waiting[hash] = (url, at)
        guard !working.contains(hash) else { return }
        working.insert(hash)
        next(hash)
    }

    /// Make the latest moment waiting for this clip, then the next latest.
    private func next(_ hash: String) {
        guard let want = waiting.removeValue(forKey: hash) else {
            working.remove(hash)
            return
        }
        let k = Self.ms(want.at)
        if moments[hash]?[k] != nil { next(hash); return }
        queue.async { [weak self] in
            guard let self else { return }
            let made = self.makeMoment(hash, url: want.url, at: want.at)
            DispatchQueue.main.async {
                if let made {
                    self.moments[hash, default: [:]][k] = made
                    self.arrivals += 1
                }
                self.next(hash)
            }
        }
    }

    /// On `queue` only.
    private func makeMoment(_ hash: String, url: URL, at: Double) -> NSImage? {
        let g: AVAssetImageGenerator
        if let held = generators[hash] {
            g = held
        } else {
            g = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            g.appliesPreferredTrackTransform = true
            g.requestedTimeToleranceBefore = .zero
            g.requestedTimeToleranceAfter = .zero
            generators[hash] = g
        }
        guard let cg = try? g.copyCGImage(at: CMTime(seconds: max(at, 0), preferredTimescale: 600),
                                          actualTime: nil) else { return nil }
        return NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height))
    }

    private static func decodeStill(_ url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 2400,
              ] as CFDictionary)
        else { return NSImage(contentsOf: url) }
        return NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height))
    }

    // ---- for the baker: everything, then one answer ------------------------

    enum Want { case still(String, URL), moment(String, URL, Double) }

    /// Every picture asked for, made on the queue, answered once on main.
    func fetch(_ wants: [Want], done: @escaping ([NSImage?]) -> Void) {
        let heldStills = stills
        let heldMoments = moments
        queue.async { [weak self] in
            guard let self else { return }
            var out: [NSImage?] = []
            var newStills: [String: NSImage] = [:]
            var newMoments: [(String, Int, NSImage)] = []
            for want in wants {
                switch want {
                case .still(let hash, let url):
                    let made = heldStills[hash] ?? newStills[hash] ?? Self.decodeStill(url)
                    if let made { newStills[hash] = made }
                    out.append(made)
                case .moment(let hash, let url, let at):
                    let k = Self.ms(at)
                    if let held = heldMoments[hash]?[k] { out.append(held); continue }
                    let made = self.makeMoment(hash, url: url, at: at)
                    if let made { newMoments.append((hash, k, made)) }
                    out.append(made)
                }
            }
            DispatchQueue.main.async {
                for (hash, image) in newStills where self.stills[hash] == nil { self.stills[hash] = image }
                for (hash, k, image) in newMoments { self.moments[hash, default: [:]][k] = image }
                done(out)
            }
        }
    }
}

// ------------------------------------------------------------ the board

/// One frame on the board as drawn.
struct BoardPicture {
    var image: NSImage?
    /// The crop he chose on this use of a still; nil draws it whole.
    var crop: ViewModel.Framing?
    /// The still's own arrows, which ride with it.
    var marks: [ViewModel.Arrow] = []

    /// Its shape: the film's when cropped, else its own.
    func ratio(film: CGFloat) -> CGFloat {
        if crop != nil { return film }
        guard let image, image.size.width > 0, image.size.height > 0 else { return film }
        return image.size.width / image.size.height
    }
}

/// **The board, drawn**: white paper, every frame in its cell at its own
/// shape, the numbers, and the arrows over the whole board. The same view
/// is on screen in the editor and rendered into the baked picture, so what
/// he sees is what prints.
struct PrintFrameBoard: View {
    let board: PrintFrameLayout.Board
    let pictures: [BoardPicture]
    let numbers: Bool
    let arrows: [ViewModel.Arrow]
    /// The drawn width; the height follows the layout.
    let width: CGFloat
    /// The frame picked in the editor, outlined. Never baked.
    var picked: Int? = nil

    var body: some View {
        let height = board.height * width
        ZStack(alignment: .topLeading) {
            Color.white
            ForEach(Array(board.cells.enumerated()), id: \.offset) { i, cell in
                let r = cell.rect(width: width)
                frame(i)
                    .frame(width: r.width, height: r.height)
                    .clipped()
                    .offset(x: r.minX, y: r.minY)
            }
            ArrowMarks(arrows: arrows)
                .frame(width: width, height: height)
            if numbers {
                ForEach(Array(board.cells.enumerated()), id: \.offset) { i, cell in
                    badge(i + 1, cell.rect(width: width))
                }
            }
            if let picked, board.cells.indices.contains(picked) {
                let r = board.cells[picked].rect(width: width)
                Rectangle()
                    .strokeBorder(Brand.accent(false), lineWidth: 3)
                    .frame(width: r.width + 6, height: r.height + 6)
                    .offset(x: r.minX - 3, y: r.minY - 3)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    @ViewBuilder private func frame(_ i: Int) -> some View {
        if pictures.indices.contains(i), let image = pictures[i].image {
            let p = pictures[i]
            if let crop = p.crop {
                Framed(picture: image, framing: crop, arrows: p.marks)
            } else {
                ZStack {
                    Image(nsImage: image).resizable().interpolation(.high)
                    if !p.marks.isEmpty { ArrowMarks(arrows: p.marks) }
                }
            }
        } else {
            Color(white: 0.88)
        }
    }

    /// The strip's look (`Filmstrip.sequenceNumbers`): a pale disc with a
    /// dark outline and a whisper of shadow, top-left of its frame.
    private func badge(_ n: Int, _ r: CGRect) -> some View {
        let short = min(r.width, r.height)
        // About 11.5% of the frame's shorter side, never under 4% of the
        // board (still readable on a ~250 px table column), never over 14%.
        let across = min(max(short * 0.115, width * 0.04), short * 0.14)
        let inset = across * 0.30
        return ZStack {
            Circle().fill(Color.white)
                .shadow(color: .black.opacity(0.35), radius: across * 0.06, y: across * 0.03)
            Circle().strokeBorder(Color.black, lineWidth: across * 0.06)
            Text(String(n))
                .font(.system(size: across * 0.58, weight: .bold))
                .foregroundStyle(Color.black)
        }
        .frame(width: across, height: across)
        .offset(x: r.minX + inset, y: r.minY + inset)
        .allowsHitTesting(false)
    }
}

// ------------------------------------------------------------ baking

/// **Bakes boards into the picture the PDF prints.**
///
/// Told about every view the app takes in (`ShellState.replace`); any shot
/// whose `printFrame.stale` is true gets baked — after the editor's change,
/// after an undo, or when Claude's connector set it while the Mac was away.
/// A short wait first, so a run of changes bakes once. Pictures are decoded
/// off the main thread; the engine is spoken to on main, as everywhere else.
final class PrintFrameBaker {
    static let shared = PrintFrameBaker()

    /// **Whether this shot needs baking**: its bake is stale, or it is
    /// current and its picture is not in the film's folder.
    ///
    /// The second is not hypothetical. On 2026-10-14 every one of the 31
    /// boards in Call Her Back was recorded as current while none of their
    /// pictures was on disk — a copy of the app from before Print Frames
    /// opened the film and swept them as files nothing named (it takes only
    /// files over an hour old, and they went exactly an hour after the last
    /// bake). The record said done, so nothing ever baked them again, and
    /// neither the screen nor the page had anything to draw.
    static func owed(_ pf: PrintFrameView, _ engine: Engine?) -> Bool {
        if pf.stale { return true }
        guard let baked = pf.baked, let engine else { return false }
        let file = engine.folder.appending(
            path: "media/proxies/\(baked.hash.prefix(32)).\(baked.ext)")
        return !FileManager.default.fileExists(atPath: file.path)
    }

    /// The width of a baked board, in pixels: enough for a full-width page.
    static let pixels: CGFloat = 2000

    private var booked: [String: DispatchWorkItem] = [:]
    private var baking: Set<String> = []
    /// Digests tried and failed, so a board that cannot be made is not tried
    /// on every view.
    private var gaveUp: Set<String> = []

    func notice(_ state: ShellState) {
        guard let view = state.view, state.engine != nil else { return }
        var seen = Set<String>()
        for row in view.allRows {
            guard let pf = row.printFrame, Self.owed(pf, state.engine), !seen.contains(row.shot),
                  !gaveUp.contains(row.shot + pf.digest) else { continue }
            seen.insert(row.shot)
            book(row.shot, state: state)
        }
    }

    private func book(_ shot: String, state: ShellState) {
        guard booked[shot] == nil, !baking.contains(shot) else { return }
        let work = DispatchWorkItem { [weak self, weak state] in
            guard let self, let state else { return }
            self.booked[shot] = nil
            self.bake(shot, state: state)
        }
        booked[shot] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (Launch.checking ? 0.15 : 0.6), execute: work)
    }

    private func bake(_ shot: String, state: ShellState) {
        guard let engine = state.engine,
              let row = state.view?.allRows.first(where: { $0.shot == shot }),
              let pf = row.printFrame, Self.owed(pf, engine) else { return }
        let spec = pf.spec
        let film = CGFloat(state.view?.project.ratio ?? 2.39)
        var wants: [PrintFramePictures.Want] = []
        var stills: [ViewModel.Still] = []
        for m in spec.frames {
            guard let still = row.stills.first(where: { $0.ref == m.use }),
                  let url = PrintFramePictures.file(still, engine: engine) else { continue }
            stills.append(still)
            wants.append(still.movie ? .moment(still.hash, url, m.at ?? 0) : .still(still.hash, url))
        }
        guard !wants.isEmpty else {
            gaveUp.insert(shot + pf.digest)
            Self.say("printframe: bake \(row.number) gave up, none of its pictures is here")
            return
        }
        baking.insert(shot)
        let digest = pf.digest
        PrintFramePictures.shared.fetch(wants) { [weak self, weak state] images in
            guard let self else { return }
            self.baking.remove(shot)
            guard let state, let engine = state.engine,
                  // Changed while the pictures were being made: the next
                  // view books it again.
                  state.view?.allRows.first(where: { $0.shot == shot })?.printFrame?.digest == digest
            else { if let state { self.notice(state) }; return }
            guard images.allSatisfy({ $0 != nil }) else {
                self.gaveUp.insert(shot + digest)
                Self.say("printframe: bake \(shot) failed, a picture would not decode")
                return
            }
            let pictures = zip(stills, images).map { still, image in
                BoardPicture(image: image, crop: !still.movie && still.hasCrop ? still.framing : nil,
                             marks: still.movie ? [] : still.marks)
            }
            guard let made = MainActor.assumeIsolated({
                Self.render(spec: spec, pictures: pictures, film: film)
            }) else {
                self.gaveUp.insert(shot + digest)
                return
            }
            let ok = engine.bakePrintFrame(shot, digest: digest, width: made.width,
                                           height: made.height, jpeg: made.jpeg)
            Self.say("printframe: baked \(row.number) \(made.width)\u{00D7}\(made.height) \(ok ? "filed" : "REFUSED")")
            if !ok { self.gaveUp.insert(shot + digest) }
            state.replace(engine.view())
            if ok { ClipPreviews.shared.boardFiled() }
        }
    }

    /// The board as one JPEG, `pixels` wide.
    @MainActor
    static func render(spec: PrintFrameSpec, pictures: [BoardPicture],
                       film: CGFloat) -> (jpeg: Data, width: Int, height: Int)? {
        let ratios = pictures.map { $0.ratio(film: film) }
        let kind = PrintFrameLayout.resolved(spec.layout, ratios, film: film)
        let board = PrintFrameLayout.layout(kind, ratios)
        let width = pixels
        let height = (board.height * width).rounded()
        let content = PrintFrameBoard(board: board, pictures: pictures, numbers: spec.numbers,
                                      arrows: spec.arrows, width: width)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        guard let cg = renderer.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        else { return nil }
        return (jpeg, cg.width, cg.height)
    }

    static func say(_ line: String) {
        guard Launch.checking else { return }
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
