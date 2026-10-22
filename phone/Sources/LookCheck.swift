import SwiftUI

/// **A checking door for Look** (Ref 1551), the way the app has them for
/// everything a simulator cannot reach by hand. Nothing in the app reaches it.
///
///     --lookcheck <page|deck|board> <path in Documents> [title]
///
/// The path is a copy of a film's portal folder laid out as the portal keeps
/// it (`<film>/pages/bible.json`, with `media/` and `docs/` beside), so the
/// pictures resolve through `LookFolder`. Then, to look at what a finger
/// would open:
///
///     --lookfilm <film>        a film in Documents, so cards open its shots
///     --lookprinted <file>     a deck's printed PDF, by its stored name
///     --lookway designed       a deck opened on its printed copy
///     --lookmode <sort id>     a board opened on one of its sorts
///     --lookcard <card id>     a board with one card opened
///     --lookzoom <s> <x> <y>   a board at scale s, centred on a place
///     --lookjump <n>           a page scrolled to its n-th heading
///     --lookpicture <n>        a page with its n-th picture open full screen
///     --lookplay <file>        a page with that stored clip playing
struct LookCheck: View {
    struct Asked {
        var kind: String
        var path: String
        var title: String
    }

    static var asked: Asked? {
        let a = CommandLine.arguments
        guard let flag = a.firstIndex(of: "--lookcheck"), flag + 2 < a.count else { return nil }
        let title = flag + 3 < a.count && !a[flag + 3].hasPrefix("--") ? a[flag + 3] : ""
        return Asked(kind: a[flag + 1], path: a[flag + 2], title: title)
    }

    static func value(_ name: String, _ more: Int = 0) -> String? {
        let a = CommandLine.arguments
        guard let flag = a.firstIndex(of: name), flag + 1 + more < a.count else { return nil }
        return a[flag + 1 + more]
    }

    let asked: Asked
    @StateObject private var holder = LookCheckFilm()

    private var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    var body: some View {
        let file = documents.appendingPathComponent(asked.path)
        let root = file.deletingLastPathComponent().deletingLastPathComponent()
        let files = LookFolder(root: root)
        let data = (try? Data(contentsOf: file)) ?? Data()
        let title = asked.title.isEmpty ? file.deletingPathExtension().lastPathComponent : asked.title
        let stack = NavigationStack {
            Group {
                switch asked.kind {
                case "page":
                    if let page = try? LookPageView(title: title, subtitle: Self.value("--looksub") ?? "", data: data, files: files) {
                        page
                    } else { broken }
                case "deck":
                    if let deck = try? LookDeckView(data: data, files: files, printed: Self.value("--lookprinted")) {
                        deck
                    } else { broken }
                case "board":
                    if let board = try? LookBoardView(title: title, data: data, files: files, session: holder.session) {
                        board
                    } else { broken }
                default:
                    broken
                }
            }
        }
        Group {
            if let session = holder.session, let frames = holder.frames {
                stack.environmentObject(session).environmentObject(frames)
            } else {
                stack
            }
        }
        .onAppear {
            if let film = Self.value("--lookfilm") { holder.open(film, in: documents) }
        }
    }

    private var broken: some View {
        ContentUnavailableView("Can't Read \(asked.path)", systemImage: "exclamationmark.triangle")
    }
}

@MainActor
final class LookCheckFilm: ObservableObject {
    @Published var session: Session?
    @Published var frames: Frames?

    func open(_ film: String, in documents: URL) {
        let url = documents.appendingPathComponent(film + ".shotlist")
        let opened = Session(entry: .init(name: film, bookmarkKey: "checking", lastOpened: .now),
                             folder: OpenFolder(url: url, scoped: false))
        frames = Frames(engine: opened.engine, folder: url)
        session = opened
    }
}
