import SwiftUI
import ImageIO
import AVKit
import QuickLook

/// **Look on the phone, drawn natively** (Ref 1551, Stage E of Ref 1541,
/// `design/33-one-app.html` sections 5 to 8). The portal keeps a film's look
/// as three kinds of stored JSON (written pages, decks, boards) and its
/// pictures as files named by their hash. These views draw any of them from
/// that JSON, with nothing special for any one page.
///
/// **Where the files come from is the caller's business.** Every picture,
/// clip, PDF and attachment is asked for by its stored file name (the
/// `<hash>.<ext>` the portal keeps in `media/` or `docs/`) through one hook,
/// `LookFiles`. Stage C's portal line and its cache on the phone answer it in
/// the app; `LookFolder` answers it from a folder for a checking run.
protocol LookFiles: Sendable {
    /// Where a stored file is, fetched first if it has to be. A file URL is
    /// best; a web address will do for a clip or a document. Nil when the
    /// film does not have it, or there is no signal and no copy.
    func file(named name: String) async -> URL?
}

/// Files from a folder laid out the way the portal keeps a film: `media/`,
/// `docs/`, or loose. For checking runs on a simulator.
struct LookFolder: LookFiles {
    let root: URL

    func file(named name: String) async -> URL? {
        let fm = FileManager.default
        for place in ["media", "docs", ""] {
            let url = place.isEmpty ? root.appendingPathComponent(name)
                : root.appendingPathComponent(place).appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}

/// A file named in a picture address the way boards write them
/// (`/callherback/media/<hash>.jpg`, `pic/<hash>.mp4`): the last part.
func lookFileName(_ src: String) -> String {
    let bare = src.split(separator: "?").first.map(String.init) ?? src
    return bare.split(separator: "/").last.map(String.init) ?? bare
}

private struct LookFilesKey: EnvironmentKey {
    static let defaultValue: (any LookFiles)? = nil
}

extension EnvironmentValues {
    var lookFiles: (any LookFiles)? {
        get { self[LookFilesKey.self] }
        set { self[LookFilesKey.self] = newValue }
    }
}

// MARK: - pictures

/// **Pictures, read small.** A board holds hundreds and a bible dozens; read
/// whole, a single board was hundreds of megabytes. Each is read once at the
/// size asked for (ImageIO, never the whole decode) and kept until memory is
/// short. A picture's shape is kept too, so a grid can be laid out before
/// the picture itself arrives.
actor LookPictures {
    static let shared = LookPictures()

    private let cache = NSCache<NSString, UIImage>()
    private var shapes: [String: CGFloat] = [:]
    private var running: [String: Task<UIImage?, Never>] = [:]

    init() { cache.totalCostLimit = 160 * 1024 * 1024 }

    /// Width over height, once anything of the picture has been read.
    func shape(_ name: String) -> CGFloat? { shapes[name] }

    func image(_ name: String, longest: Int, from files: any LookFiles) async -> UIImage? {
        let key = "\(name)@\(longest)" as NSString
        if let held = cache.object(forKey: key) { return held }
        if let going = running[key as String] { return await going.value }
        let task = Task<UIImage?, Never> {
            guard let url = await files.file(named: name) else { return nil }
            return await Task.detached(priority: .utility) { Self.read(url, longest: longest) }.value
        }
        running[key as String] = task
        let got = await task.value
        running[key as String] = nil
        if let got {
            cache.setObject(got, forKey: key, cost: Int(got.size.width * got.size.height * got.scale * got.scale * 4))
            if got.size.height > 0 { shapes[name] = got.size.width / got.size.height }
        }
        return got
    }

    private static func read(_ url: URL, longest: Int) -> UIImage? {
        let source: CGImageSource?
        if url.isFileURL {
            source = CGImageSourceCreateWithURL(url as CFURL, nil)
        } else {
            guard let data = try? Data(contentsOf: url) else { return nil }
            source = CGImageSourceCreateWithData(data as CFData, nil)
        }
        guard let source else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longest,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// One stored picture, filling whatever frame it is given. Grey while it
/// comes; a quiet mark if it never does.
struct LookPicture: View {
    @Environment(\.lookFiles) private var files
    let name: String
    var longest: Int = 900
    var mode: ContentMode = .fill
    @State private var image: UIImage?
    @State private var missing = false

    var body: some View {
        ZStack {
            Rectangle().fill(Color(.tertiarySystemFill))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: mode)
            } else if missing {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
        }
        .clipped()
        .task(id: name) {
            guard let files, !name.isEmpty else { missing = true; return }
            image = await LookPictures.shared.image(name, longest: longest, from: files)
            missing = image == nil
        }
    }
}

/// **A picture full screen**: pinch to zoom, drag about, swipe to the next.
struct LookViewer: View {
    struct Opening: Identifiable {
        var names: [String]
        var at: Int
        var id: String { "\(at)-\(names.joined())" }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.lookFiles) private var files
    let opening: Opening
    @State private var at = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $at) {
                ForEach(Array(opening.names.enumerated()), id: \.offset) { index, name in
                    LookZoomable(name: name, files: files)
                        .tag(index)
                        .ignoresSafeArea()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: opening.names.count > 1 ? .automatic : .never))
            .ignoresSafeArea()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered).tint(.white)
            .buttonBorderShape(.circle)
            .padding(.trailing, 16)
            .accessibilityLabel("Close")
        }
        .onAppear { at = opening.at }
    }
}

/// One picture in a scroll view that zooms: UIKit's own pinch, which is the
/// one that feels like Photos.
private struct LookZoomable: UIViewRepresentable {
    let name: String
    let files: (any LookFiles)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 6
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.backgroundColor = .black
        scroll.contentInsetAdjustmentBehavior = .never
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.frame = scroll.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.addSubview(view)
        context.coordinator.image = view
        let twice = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.twice(_:)))
        twice.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(twice)
        if let files {
            Task { @MainActor in
                view.image = await LookPictures.shared.image(name, longest: 2600, from: files)
            }
        }
        return scroll
    }

    func updateUIView(_ view: UIScrollView, context: Context) {}

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var image: UIImageView?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { image }
        @objc func twice(_ tap: UITapGestureRecognizer) {
            guard let scroll = tap.view as? UIScrollView else { return }
            if scroll.zoomScale > 1 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let at = tap.location(in: image)
                scroll.zoom(to: CGRect(x: at.x - 60, y: at.y - 60, width: 120, height: 120), animated: true)
            }
        }
    }
}

/// A clip, played full screen.
struct LookPlayer: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player).ignoresSafeArea()
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered).tint(.white)
            .buttonBorderShape(.circle)
            .padding(.trailing, 16)
            .accessibilityLabel("Close")
        }
        .onAppear {
            let made = AVPlayer(url: url)
            player = made
            made.play()
        }
        .onDisappear { player?.pause() }
    }
}

/// Opening a clip: a stored one plays here; an address (Livid, YouTube) goes
/// to Safari, which plays them properly.
struct LookClipOpening: Identifiable {
    var url: URL
    var id: String { url.absoluteString }
}

// MARK: - words

/// **Words with a little markup in them**: the `<b>`, `<i>` and `<em>` a
/// deck's words carry, and the entities a portal escapes. Anything else is
/// dropped rather than shown as tags.
func lookMarked(_ said: String) -> AttributedString {
    var out = AttributedString()
    var bold = 0, italic = 0
    var rest = Substring(said)
    func put(_ text: Substring) {
        guard !text.isEmpty else { return }
        var piece = AttributedString(lookEntities(String(text)))
        var intent: InlinePresentationIntent = []
        if bold > 0 { intent.insert(.stronglyEmphasized) }
        if italic > 0 { intent.insert(.emphasized) }
        if !intent.isEmpty { piece.inlinePresentationIntent = intent }
        out += piece
    }
    while let open = rest.firstIndex(of: "<") {
        put(rest[..<open])
        guard let close = rest[open...].firstIndex(of: ">") else { put(rest[open...]); rest = ""; break }
        let tag = rest[rest.index(after: open)..<close].lowercased().trimmingCharacters(in: .whitespaces)
        switch tag {
        case "b", "strong": bold += 1
        case "/b", "/strong": bold = max(0, bold - 1)
        case "i", "em": italic += 1
        case "/i", "/em": italic = max(0, italic - 1)
        case "br", "br/", "br /": out += AttributedString("\n")
        default: break
        }
        rest = rest[rest.index(after: close)...]
    }
    put(rest)
    return out
}

func lookEntities(_ s: String) -> String {
    guard s.contains("&") else { return s }
    return s.replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "&#x27;", with: "'")
        .replacingOccurrences(of: "&nbsp;", with: " ")
}

// MARK: - lines of pictures

/// **Pictures in a line at one height**, each as wide as its shape asks, so
/// nothing is cropped: the way the portal sets a row. Shapes not yet known
/// are taken as 3:2 and corrected when the picture arrives.
struct LookJustified: Layout {
    var shapes: [CGFloat]
    var spacing: CGFloat = 4

    private func height(for width: CGFloat) -> CGFloat {
        let total = shapes.reduce(0) { $0 + max(0.2, $1) }
        let room = width - spacing * CGFloat(max(0, shapes.count - 1))
        return total > 0 ? room / total : 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        return CGSize(width: width, height: height(for: width))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let h = height(for: bounds.width)
        var x = bounds.minX
        for (index, view) in subviews.enumerated() {
            let w = h * max(0.2, index < shapes.count ? shapes[index] : 1.5)
            view.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: w, height: h))
            x += w + spacing
        }
    }
}

/// Splits pictures into lines of at most `most`, as even as they go and
/// **never a line of one** when there are several (his rule for decks,
/// 2026-09-06, which reads as well on a page).
func lookLines<T>(_ items: [T], most: Int) -> [[T]] {
    let most = max(1, most)
    guard items.count > most else { return items.isEmpty ? [] : [items] }
    var lines = Int((Double(items.count) / Double(most)).rounded(.up))
    while lines > 1, items.count - most * (lines - 1) == 1 { lines -= 1 }
    var out: [[T]] = []
    var at = 0
    for i in 0..<lines {
        let take = Int((Double(items.count - at) / Double(lines - i)).rounded(.up))
        out.append(Array(items[at..<min(items.count, at + take)]))
        at += take
    }
    return out
}

/// A row of pictures, laid at one height once their shapes are known. A tap
/// opens the one tapped full screen, with its neighbours a swipe away.
struct LookPictureRow: View {
    @Environment(\.lookFiles) private var files
    let names: [String]
    /// Shapes the caller already knows (a deck keeps them); otherwise read.
    var known: [CGFloat?] = []
    /// A fixed shape for every cell, cropping to it (a deck group's `ratio`).
    var forced: CGFloat?
    var spacing: CGFloat = 4
    let open: (Int) -> Void
    @State private var read: [String: CGFloat] = [:]

    private var shapes: [CGFloat] {
        names.enumerated().map { index, name in
            if let forced { return forced }
            if index < known.count, let k = known[index] { return k }
            return read[name] ?? 1.5
        }
    }

    var body: some View {
        LookJustified(shapes: shapes, spacing: spacing) {
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                LookPicture(name: name, longest: names.count == 1 ? 1400 : 800)
                    .clipped() // A picture is never rounded (his rule, 2026-10-07).
                    .contentShape(Rectangle())
                    .onTapGesture { open(index) }
            }
        }
        .task(id: names) {
            guard let files, forced == nil else { return }
            for name in names where read[name] == nil {
                if let shape = await LookPictures.shared.shape(name) {
                    read[name] = shape
                } else if await LookPictures.shared.image(name, longest: 800, from: files) != nil,
                          let shape = await LookPictures.shared.shape(name) {
                    read[name] = shape
                }
            }
        }
    }
}
