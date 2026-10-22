import AppKit
import Foundation

/// **`shotlister://film` — the Projects Console's way into a film.**
///
///     shotlister://film?page=<Notion page id>&film=<folder name>[&mode=<mode>]
///
/// The console's *Open in Shotlister* used to hand the Mac the film's folder,
/// which opened whatever the Mac thought a folder was. This asks the program
/// that owns the film to open it on screen, the same way the iPhone's copy of
/// the link does.
///
/// **By the linked page first** — the id the film was linked with (`Link`), the
/// only name that survives either end being renamed — and by the folder name
/// only when nothing is linked, which is how a film found by name in the
/// console is still reached. Nothing here moves, writes or archives anything.
@MainActor
enum FilmLink {
    static func handle(_ url: URL, state: ShellState) {
        guard url.scheme == "shotlister", url.host == "film" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String {
            items.first { $0.name == name }?.value ?? ""
        }
        let page = value("page"), name = value("film")

        if Launch.checking {
            FileHandle.standardError.write(Data("filmlink: page \"\(page)\" film \"\(name)\"\n".utf8))
        }
        guard let film = find(page: page, name: name, state: state) else {
            state.problem = "No film is linked to this project"
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if state.projectPath?.standardizedFileURL != film.standardizedFileURL {
            state.open(film)
        }
        // **`mode=`** — the console's mode tiles (Systems card) open the film
        // standing in that mode: `shot_list`, `locations`, `references`,
        // `schedule`, `diagram` (the server's names), or Studio's own.
        let mode = value("mode")
        if let tab = ProjectCards.tab(mode) ?? SideTab(rawValue: mode) {
            state.sideTab = tab
            if Launch.checking {
                FileHandle.standardError.write(Data("filmlink: mode \(mode) → \(state.sideTab.rawValue)\n".utf8))
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The film on this Mac that belongs to this project, or nothing.
    private static func find(page: String, name: String, state: ShellState) -> URL? {
        let wanted = FilmDoor.bare(page)
        // Already on screen and linked: no second look at the disk.
        if !wanted.isEmpty, let open = state.projectPath,
           FilmDoor.bare(state.view?.project.consolePage ?? "") == wanted {
            return open
        }
        if !wanted.isEmpty {
            let live = FilmDoor.films(linkedTo: page).filter { !$0.inTheBin }
            if live.count == 1 { return live[0].url }
            // Two linked to one page: the folder name is the tie-break, and
            // if it is no help the door does not pick.
            if live.count > 1 { return live.first { sameName($0.url, name) }?.url }
        }
        guard !name.isEmpty else { return nil }
        return Projects.all().first { sameName($0, name) }
    }

    private static func sameName(_ url: URL, _ name: String) -> Bool {
        !name.isEmpty
            && url.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(name) == .orderedSame
    }
}
