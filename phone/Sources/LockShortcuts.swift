import Foundation

/// **The four lock screen shortcuts** (his ask, 2026-10-09): each opens
/// Shotlister, or a film he picks at a page he picks, and is set in the app's
/// Settings rather than on the widget itself. A widget on the lock screen only
/// says *which* of the four it is; what that one opens can change here without
/// touching the lock screen.
///
/// Read by two processes, the app and the widget extension, so it lives in the
/// App Group's own defaults. This file is compiled into both and knows nothing
/// of either: no `Place`, no `Projects`, only the words and the address.
struct LockShortcut: Codable, Hashable, Identifiable {
    /// 1 to 4.
    var slot: Int
    /// The film's name, as the Projects list shows it. Nil opens the app.
    var film: String?
    /// A `Place` key (`shotlist`, `schedule`…). Nil opens the film where its
    /// bar starts.
    var place: String?
    var placeTitle: String?
    var symbol: String?
    /// The film's own icon (`FilmMark`): its outline and colour, so the
    /// widget wears the film the way the Projects list does.
    var markPath: String?
    var markColour: String?
    /// Which of the three looks it wears (`WidgetLook`); nil is Badge.
    var look: String?

    var id: Int { slot }
    var shownLook: WidgetLook { look.flatMap(WidgetLook.init(rawValue:)) ?? .badge }

    /// What a tap opens. `follow` in `ShotlisterApp` reads it.
    var url: URL {
        guard let film else { return URL(string: "shotlister://open")! }
        var parts = URLComponents()
        parts.scheme = "shotlister"
        parts.host = "film"
        parts.queryItems = [URLQueryItem(name: "film", value: film)]
            + (place.map { [URLQueryItem(name: "place", value: $0)] } ?? [])
        return parts.url ?? URL(string: "shotlister://open")!
    }

    var title: String { film ?? "Studio" }
    var subtitle: String { film == nil ? "Open" : (placeTitle ?? "Shot List") }
    /// The page in a word or two, where a round widget has room for little.
    var shortSubtitle: String {
        switch subtitle {
        case "Reference Images": return "References"
        default: return subtitle
        }
    }
    var glyph: String { film == nil ? "film" : (symbol ?? "list.bullet.rectangle") }
}

enum LockShortcuts {
    static let group = "group.com.example.shotlister"
    static let count = 4
    private static let key = "lock.shortcuts"

    private static var store: UserDefaults? { UserDefaults(suiteName: group) }

    /// Always four, in order; a slot never set opens the app.
    static func all() -> [LockShortcut] {
        let saved = store?.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([LockShortcut].self, from: $0) } ?? []
        return (1...count).map { slot in saved.first { $0.slot == slot } ?? LockShortcut(slot: slot) }
    }

    static func one(_ slot: Int) -> LockShortcut {
        all().first { $0.slot == slot } ?? LockShortcut(slot: slot)
    }

    static func save(_ shortcut: LockShortcut) {
        var list = all()
        list.removeAll { $0.slot == shortcut.slot }
        list.append(shortcut)
        list.sort { $0.slot < $1.slot }
        guard let data = try? JSONEncoder().encode(list) else { return }
        store?.set(data, forKey: key)
    }
}


/// **The three looks** (`design/43-widgets.html`, his pick 2026-10-09: all
/// of them, chosen per shortcut in Settings).
enum WidgetLook: String, CaseIterable, Codable, Identifiable {
    /// The film's icon in its own small frame; page bold, film quiet.
    case badge
    /// The widget is the film's colour; page large.
    case colour
    /// Small capitals naming the film over the page in large type; no panels.
    case eyebrow

    var id: String { rawValue }
    var name: String {
        switch self {
        case .badge: return "Badge"
        case .colour: return "Project Color"
        case .eyebrow: return "Eyebrow"
        }
    }
}

// MARK: - What the information widgets read

/// **A film, as its information widgets see it** (Shoot Day, Next Shots):
/// written by the app whenever an open film changes, read by the widgets.
struct FilmSnapshot: Codable, Hashable {
    var film: String
    var markPath: String?
    var markColour: String?
    var days: [Day]
    /// The next shots still to get, in the order they run, with their frames.
    var next: [Shot]
    var written: Date

    struct Day: Codable, Hashable {
        var label: String
        var title: String
        /// `2026-11-02`; empty for a day with no date.
        var date: String
        var count: Int
        var got: Int
        /// Scene numbers, in the order the day runs them.
        var scenes: [String]
        var wrapped: Bool
    }

    struct Shot: Codable, Hashable {
        var number: String
        var title: String
        /// A small copy of its frame in the App Group's `frames` folder.
        var picture: String?
    }

    /// The day a widget is about: today's if there is one, else the next one
    /// dated from today on, else the first not shot out.
    var focus: (day: Day, date: Date?)? {
        let today = Calendar.current.startOfDay(for: .now)
        let dated = days.compactMap { d in FilmSnapshot.read.date(from: d.date).map { (d, $0) } }
        if let hit = dated.first(where: { Calendar.current.isDate($0.1, inSameDayAs: today) }) { return hit }
        if let hit = dated.filter({ $0.1 > today }).min(by: { $0.1 < $1.1 }) { return hit }
        return days.first { !$0.wrapped }.map { ($0, nil) }
    }

    static let read: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

enum FilmSnapshots {
    private static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: LockShortcuts.group)
    }
    static var frames: URL? { folder?.appendingPathComponent("frames", isDirectory: true) }
    private static var file: URL? { folder?.appendingPathComponent("films.json") }

    static func all() -> [FilmSnapshot] {
        guard let file, let data = try? Data(contentsOf: file),
              let list = try? JSONDecoder().decode([FilmSnapshot].self, from: data) else { return [] }
        return list
    }

    static func save(_ snapshot: FilmSnapshot) {
        var list = all().filter { $0.film != snapshot.film }
        list.append(snapshot)
        guard let file, let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: file, options: .atomic)
    }

    /// The film an information widget follows: the one chosen in Settings,
    /// else whichever has the soonest shoot day.
    static func followed(_ chosen: String?) -> FilmSnapshot? {
        let list = withRecordDates(all())
        if let chosen, let hit = list.first(where: { $0.film == chosen }) { return hit }
        return list.filter { $0.focus?.date != nil }.min { ($0.focus?.date ?? .distantFuture) < ($1.focus?.date ?? .distantFuture) }
            ?? list.max { $0.written < $1.written }
    }

    /// Upcoming shoot dates from the project records, written by the app
    /// (`HomeRecords`): `[film name: ["yyyy-MM-dd", colour]]`. A film whose own
    /// schedule has no dated day ahead (Halcyon, before any day is made) is
    /// still counted down to by its record's shoot date.
    static var recordDates: [String: [String]] {
        get { UserDefaults(suiteName: LockShortcuts.group)?.dictionary(forKey: "info.recorddates") as? [String: [String]] ?? [:] }
        set { UserDefaults(suiteName: LockShortcuts.group)?.set(newValue, forKey: "info.recorddates") }
    }

    private static func withRecordDates(_ list: [FilmSnapshot]) -> [FilmSnapshot] {
        var out = list
        for (name, info) in recordDates {
            guard let date = info.first, FilmSnapshot.read.date(from: date) != nil else { continue }
            let day = FilmSnapshot.Day(label: "Shoot", title: "", date: date, count: 0, got: 0, scenes: [], wrapped: false)
            if let i = out.firstIndex(where: { $0.film == name }) {
                // Only when the record's date comes sooner than the film's own.
                let own = out[i].focus?.date
                if let own, own <= FilmSnapshot.read.date(from: date) ?? .distantFuture { continue }
                out[i].days.append(day)
            } else {
                out.append(FilmSnapshot(film: name, markPath: nil, markColour: info.count > 1 && !info[1].isEmpty ? "#" + info[1] : nil,
                                        days: [day], next: [], written: .distantPast))
            }
        }
        return out
    }
}

/// **What the information widgets follow**, set in Settings → Lock Screen.
/// Nil is "Soonest Shoot".
enum InfoChoices {
    private static var store: UserDefaults? { UserDefaults(suiteName: LockShortcuts.group) }
    static var shootDayFilm: String? {
        get { store?.string(forKey: "info.shootday") }
        set { store?.set(newValue, forKey: "info.shootday") }
    }
    static var nextShotsFilm: String? {
        get { store?.string(forKey: "info.nextshots") }
        set { store?.set(newValue, forKey: "info.nextshots") }
    }
}
