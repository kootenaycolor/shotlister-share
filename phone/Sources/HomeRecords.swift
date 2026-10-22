import SwiftUI
import WidgetKit

/// **What the Projects Console knows about each project**, read for the Home
/// Screen: its stage, type, length, colour and next shoot. The same records the
/// console reads (`GET /console/records?full=1` on the portal, the relay's
/// password), kept on the phone so the list groups itself with no signal.
@MainActor
final class HomeRecords: ObservableObject {
    struct Row: Codable, Hashable {
        var page: String
        var name: String
        var slug: String = ""
        var filmTitle: String = ""
        var stage: String = ""
        var type: String = ""
        var length: String = ""
        var colour: String = ""
        /// `yyyy-MM-dd` or `yyyy-MM-dd/yyyy-MM-dd`, the console's own form.
        var shootDates: String = ""
        var updated: String = ""
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var failed = false

    private let cache = PortalLine.home(for: "_home").appending(path: "records.json")

    init() {
        if let data = try? Data(contentsOf: cache),
           let kept = try? JSONDecoder().decode([Row].self, from: data) {
            rows = kept
        }
    }

    func refresh() async {
        guard let address = PortalLine.address(), let token = PortalLine.token(),
              let url = URL(string: address + "/console/records?full=1") else { return }
        var asking = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        asking.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        guard let (data, answer) = try? await URLSession.shared.data(for: asking),
              (answer as? HTTPURLResponse)?.statusCode == 200,
              let read = Self.read(data) else { failed = true; return }
        failed = false
        rows = read
        var dates: [String: [String]] = [:]
        for row in read where row.daysToShoot != nil {
            let start = row.shootDates.split(separator: "/").first.map(String.init) ?? ""
            dates[row.filmTitle.isEmpty ? row.name : row.filmTitle] = [start, row.colour]
        }
        FilmSnapshots.recordDates = dates
        WidgetCenter.shared.reloadAllTimelines()
        try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(read).write(to: cache, options: .atomic)
    }

    /// Only the fields the list draws, read leniently: a record is a mirror of
    /// what the Mac last saw, and a thin one must not lose the whole list.
    nonisolated static func read(_ data: Data) -> [Row]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = json["records"] as? [[String: Any]] else { return nil }
        return records.compactMap { r in
            guard let page = r["page"] as? String, let name = r["name"] as? String else { return nil }
            let film = r["film"] as? [String: Any]
            let icon = r["icon"] as? [String: Any]
            func said(_ fact: String, _ plain: String) -> String {
                let typed = Self.fact(r, fact)
                return typed.isEmpty ? (r[plain] as? String ?? "") : typed
            }
            var colour = (icon?["colour"] as? String) ?? ((film?["mark"] as? [String: Any])?["colour"] as? String) ?? ""
            if colour.isEmpty { colour = Self.colourNamed(Self.fact(r, "color")) }
            return Row(page: page.replacingOccurrences(of: "-", with: "").lowercased(),
                       name: name,
                       slug: r["slug"] as? String ?? "",
                       filmTitle: film?["title"] as? String ?? "",
                       stage: said("status", "stage"),
                       type: said("type", "type"),
                       length: r["length"] as? String ?? "",
                       colour: colour,
                       shootDates: Self.fact(r, "shoot_dates"),
                       updated: r["updated"] as? String ?? "")
        }
    }

    private nonisolated static func fact(_ r: [String: Any], _ key: String) -> String {
        ((r["facts"] as? [String: Any])?[key] as? [String: Any])?["value"] as? String ?? ""
    }

    /// Notion's colour names, as the console draws them.
    private nonisolated static func colourNamed(_ name: String) -> String {
        ["gray": "8A8A8E", "brown": "A4755A", "orange": "E8833A", "yellow": "D9A81E",
         "green": "3F9B6A", "blue": "2F7FD8", "purple": "8B5FD0", "pink": "D0558F",
         "red": "D64B45"][name] ?? ""
    }

    /// The record that belongs to a film: the page a film was last opened
    /// from, else its name (the film's, the project's, or the slug).
    func row(for name: String, consolePages: [String: String]) -> Row? {
        let wanted = name.trimmingCharacters(in: .whitespaces).lowercased()
        if let page = consolePages.first(where: { $0.value.lowercased() == wanted })?.key,
           let found = rows.first(where: { $0.page == page }) { return found }
        return rows.first {
            [$0.filmTitle, $0.name, $0.slug].contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == wanted }
        }
    }
}

extension HomeRecords.Row {
    /// The console's stages, in its order.
    static let stages = ["Active", "Development", "Post", "Released", "Archived"]

    /// First and last day of the shoot, if one is written.
    var shoot: (start: Date, end: Date)? {
        let parts = shootDates.split(separator: "/").map(String.init)
        guard let first = parts.first, let start = Self.day.date(from: first) else { return nil }
        return (start, parts.count > 1 ? (Self.day.date(from: parts[1]) ?? start) : start)
    }

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Days to the shoot's first day (0 while it is on), or nil once it is over
    /// or none is written.
    var daysToShoot: Int? {
        guard let shoot else { return nil }
        let today = Calendar.current.startOfDay(for: .now)
        if shoot.end < today { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: today, to: shoot.start).day ?? 0)
    }

    /// "Narrative · Short", whatever of it is written.
    var kind: String { [type, length].filter { !$0.isEmpty }.joined(separator: " · ") }
}
