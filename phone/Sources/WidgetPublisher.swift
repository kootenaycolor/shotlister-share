import UIKit
import WidgetKit
import AVFoundation

/// **Hands an open film to its information widgets** (Shoot Day, Next Shots;
/// `design/43-widgets.html` D). Whenever the film's view changes, a moment
/// later: its shoot days with how many shots each has and how many are got,
/// and the next shots still to get with a small copy of each frame.
@MainActor
enum WidgetPublisher {
    private static var waiting: DispatchWorkItem?

    /// Called on every change; the work happens once things settle.
    static func soon(_ session: Session) {
        waiting?.cancel()
        let work = DispatchWorkItem { [weak session] in
            MainActor.assumeIsolated {
                guard let session else { return }
                publish(session)
            }
        }
        waiting = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private static func publish(_ session: Session) {
        guard let view = session.view, let engine = session.engine,
              let board = try? JSONDecoder().decode(Engine.Schedule.self, from: engine.raw("board")) else { return }
        let days = board.days.map { lane in
            var scenes: [String] = []
            for shot in lane.run where !shot.scene.isEmpty && !scenes.contains(shot.scene) { scenes.append(shot.scene) }
            return FilmSnapshot.Day(label: lane.label, title: lane.title, date: lane.date, count: lane.run.count,
                                    got: lane.got, scenes: scenes, wrapped: lane.wrapped)
        }
        let draft = FilmSnapshot(film: session.entry.name, markPath: view.project.mark?.path,
                                 markColour: view.project.mark?.colour, days: days, next: [], written: .now)
        // The next shots: the focused day's still to get, else the list's.
        let focusLabel = draft.focus?.day.label
        let dayShots = board.days.first { $0.label == focusLabel }?.run.filter { !$0.struck }
            .map { ($0.number, $0.title, $0.frame) } ?? []
        let listShots = view.groups.flatMap(\.rows).filter { !$0.struck }.map { ($0.number, $0.title, $0.frame) }
        let picked = Array((dayShots.isEmpty ? listShots : dayShots).prefix(3))
        let folder = session.folder.url
        var snapshot = draft
        snapshot.next = picked.map { number, title, frame in
            FilmSnapshot.Shot(number: number, title: title, picture: frame.flatMap { copy($0, from: folder) })
        }
        guard FilmSnapshots.all().first(where: { $0.film == snapshot.film }).map({ !same($0, snapshot) }) ?? true else { return }
        FilmSnapshots.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func same(_ a: FilmSnapshot, _ b: FilmSnapshot) -> Bool {
        a.days == b.days && a.next == b.next && a.markPath == b.markPath && a.markColour == b.markColour
    }

    /// A frame, at most 480 points on its long side, into the App Group,
    /// named by its contents so the same frame is copied once.
    private static func copy(_ frame: Engine.Frame, from folder: URL) -> String? {
        guard !frame.hash.isEmpty, let out = FilmSnapshots.frames else { return nil }
        let name = String(frame.hash.prefix(32)) + ".jpg"
        let target = out.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: target.path) { return name }
        guard let image = still(frame, in: folder) else { return nil }
        let scale = min(1, 480 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.8) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        guard (try? small.write(to: target, options: .atomic)) != nil else { return nil }
        return name
    }

    /// A still for a frame: the picture itself, or for a clip the still kept
    /// beside it, else a frame from the clip at its trimmed start.
    private static func still(_ frame: Engine.Frame, in folder: URL) -> UIImage? {
        if let file = Frames.proxyFile(frame.hash, wanting: "jpg", in: folder),
           ["jpg", "jpeg", "png"].contains(file.pathExtension.lowercased()),
           let image = UIImage(contentsOfFile: file.path) { return image }
        let ext = (frame.filename as NSString).pathExtension
        guard let movie = Frames.proxyFile(frame.hash, wanting: ext, in: folder) else { return nil }
        let grab = AVAssetImageGenerator(asset: AVURLAsset(url: movie))
        grab.appliesPreferredTrackTransform = true
        grab.maximumSize = CGSize(width: 480, height: 480)
        let at = CMTime(seconds: frame.trimStart ?? 0.5, preferredTimescale: 600)
        return (try? grab.copyCGImage(at: at, actualTime: nil)).map(UIImage.init(cgImage:))
    }
}
