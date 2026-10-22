import AppIntents
import UniformTypeIdentifiers
import SwiftUI

/// **Shotlister in Apple's Shortcuts app** (his ask, 2026-10-09): mainly so
/// the Action button can open a film at a page, the way a lock screen
/// shortcut does. Each action opens the app and hands an address to the
/// Projects screen's `follow`, the one place that already knows how to open a
/// film at a page; nothing here opens anything itself.

/// Where an action asked the app to go. The Projects screen takes it, on
/// arrival or while open.
final class LinkInbox: ObservableObject {
    static let shared = LinkInbox()
    @Published var url: URL?
}

// MARK: - What an action can name

enum PageChoice: String, AppEnum {
    case shotList = "shotlist", script, schedule, locations, references, diagrams, film, shoots, library

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Page"
    static var caseDisplayRepresentations: [PageChoice: DisplayRepresentation] = [
        .shotList: DisplayRepresentation(title: "Shot List", image: .init(systemName: "list.bullet.rectangle")),
        .script: DisplayRepresentation(title: "Script", image: .init(systemName: "doc.plaintext")),
        .schedule: DisplayRepresentation(title: "Schedule", image: .init(systemName: "calendar")),
        .locations: DisplayRepresentation(title: "Locations", image: .init(systemName: "mappin.and.ellipse")),
        .references: DisplayRepresentation(title: "Reference Images", image: .init(systemName: "square.grid.2x2")),
        .diagrams: DisplayRepresentation(title: "Diagrams", image: .init(systemName: "pencil.and.ruler")),
        .film: DisplayRepresentation(title: "Overview", image: .init(systemName: "film")),
        .shoots: DisplayRepresentation(title: "Shoots", image: .init(systemName: "calendar.badge.clock")),
        .library: DisplayRepresentation(title: "Library", image: .init(systemName: "books.vertical")),
    ]
}

/// A film on this iPhone, by the name the Projects list shows. The list is
/// what `Projects.rescan` last saw (`filmsKey`), so it answers without
/// opening the films folder.
struct FilmEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Project"
    static var defaultQuery = FilmQuery()
    static let filmsKey = "shortcuts.films"

    let id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
}

struct FilmQuery: EntityStringQuery {
    private var names: [String] { UserDefaults.standard.stringArray(forKey: FilmEntity.filmsKey) ?? [] }

    func entities(for identifiers: [String]) async throws -> [FilmEntity] {
        identifiers.map(FilmEntity.init(id:))
    }

    func entities(matching string: String) async throws -> [FilmEntity] {
        names.filter { $0.localizedCaseInsensitiveContains(string) }.map(FilmEntity.init(id:))
    }

    func suggestedEntities() async throws -> [FilmEntity] { names.map(FilmEntity.init(id:)) }
}

// MARK: - The actions

struct OpenFilm: AppIntent {
    static var title: LocalizedStringResource = "Open Project"
    static var description = IntentDescription("Opens a project at a page.")
    static var openAppWhenRun = true

    @Parameter(title: "Project")
    var film: FilmEntity

    @Parameter(title: "Page", default: .shotList)
    var page: PageChoice

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$film) at \(\.$page)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        LinkInbox.shared.url = LockShortcut(slot: 0, film: film.id, place: page.rawValue).url
        return .result()
    }
}

struct OpenLockShortcut: AppIntent {
    static var title: LocalizedStringResource = "Open Shortcut"
    static var description = IntentDescription("Opens one of the lock screen shortcuts set in Settings.")
    static var openAppWhenRun = true

    @Parameter(title: "Shortcut", default: .one)
    var slot: SlotChoice

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$slot)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        LinkInbox.shared.url = LockShortcuts.one(slot.rawValue).url
        return .result()
    }
}

// MARK: - Photos in

/// Photographs handed to the app by a Shortcuts action, for one film, waiting
/// for that film to open and for him to say where they go (`PhotoDrop`).
final class PhotoInbox: ObservableObject {
    static let shared = PhotoInbox()
    @Published var waiting: (film: String, photos: [Data])?
}

struct AddPhotos: AppIntent {
    static var title: LocalizedStringResource = "Upload Photos"
    static var description = IntentDescription("Adds photos to a location or a reference board in a project.")
    static var openAppWhenRun = true

    @Parameter(title: "Photos", supportedTypeIdentifiers: ["public.image"], inputConnectionBehavior: .connectToPreviousIntentResult)
    var photos: [IntentFile]

    @Parameter(title: "Project")
    var film: FilmEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Upload \(\.$photos) to \(\.$film)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let data = photos.map(\.data).filter { !$0.isEmpty }
        PhotoInbox.shared.waiting = (film.id, data)
        LinkInbox.shared.url = LockShortcut(slot: 0, film: film.id, place: nil).url
        return .result()
    }
}

// MARK: - What's shooting next

/// Each film's shoot days as last read, so *Next Shoot Day* can answer
/// without opening a film. Written whenever a film's view arrives.
enum ShootDays {
    private static let key = "shortcuts.days"

    static func remember(film: String, days: [Engine.Day]) {
        var all = UserDefaults.standard.dictionary(forKey: key) as? [String: [[String]]] ?? [:]
        let kept = days.enumerated().filter { !$0.element.wrapped && !$0.element.date.isEmpty }.map { index, day in
            [day.label.isEmpty ? "Day \(index + 1)" : day.label, day.date, String(day.count)]
        }
        guard all[film] != kept else { return }
        all[film] = kept
        UserDefaults.standard.set(all, forKey: key)
    }

    struct Next { let film: String; let label: String; let date: Date; let shots: Int }

    /// `2026-11-02`, read as a local calendar day, as `Engine.Lane` reads it.
    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Whether this phone has read the film's schedule at all.
    static func known(_ film: String) -> Bool {
        let all = UserDefaults.standard.dictionary(forKey: key) as? [String: [[String]]] ?? [:]
        return all.keys.contains { $0.caseInsensitiveCompare(film) == .orderedSame }
            || FilmSnapshots.recordDates.keys.contains { $0.caseInsensitiveCompare(film) == .orderedSame }
    }

    /// The soonest day from today on, in one film or in any.
    static func next(in film: String?) -> Next? {
        let all = UserDefaults.standard.dictionary(forKey: key) as? [String: [[String]]] ?? [:]
        let today = Calendar.current.startOfDay(for: .now)
        let fromFilms = all.filter { film == nil || $0.key.caseInsensitiveCompare(film!) == .orderedSame }
            .flatMap { name, days in
                days.compactMap { d -> Next? in
                    guard d.count == 3, let date = day.date(from: d[1]), date >= today else { return nil }
                    return Next(film: name, label: d[0], date: date, shots: Int(d[2]) ?? 0)
                }
            }
        // A film with no days of its own is still counted by its record's shoot date.
        let fromRecords = FilmSnapshots.recordDates
            .filter { film == nil || $0.key.caseInsensitiveCompare(film!) == .orderedSame }
            .compactMap { name, info -> Next? in
                guard let first = info.first, let date = day.date(from: first), date >= today,
                      !fromFilms.contains(where: { $0.film.caseInsensitiveCompare(name) == .orderedSame }) else { return nil }
                return Next(film: name, label: "Shoot", date: date, shots: 0)
            }
        return (fromFilms + fromRecords).min { $0.date < $1.date }
    }
}

struct NextShootDayIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Shoot Day"
    static var description = IntentDescription("Says the next shoot day and how many shots are on it.")

    @Parameter(title: "Project")
    var film: FilmEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Next shoot day in \(\.$film)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let said = Self.answer(film: film?.id)
        return .result(value: said, dialog: "\(said)")
    }

    /// `CHB · Day 1, Monday, November 2 · 12 shots`.
    static func answer(film: String?) -> String {
        guard let next = ShootDays.next(in: film) else {
            if let film, !ShootDays.known(film) { return "Open \(film) in Studio first" }
            return film.map { "No shoot days ahead in \($0)" } ?? "No shoot days ahead"
        }
        let cal = Calendar.current
        let away = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: next.date).day ?? 0
        let when = away == 0 ? "today" : away == 1 ? "tomorrow" : next.date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let shots = next.shots == 1 ? "1 shot" : "\(next.shots) shots"
        return "\(next.film) · \(next.label), \(when) · \(shots)"
    }
}

/// Offered in Shortcuts, Spotlight, Siri and the Action button with nothing
/// to set up first.
struct ShotlisterShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenFilm(),
                    phrases: ["Open a project in \(.applicationName)",
                              "Open \(\.$page) in \(.applicationName)"],
                    shortTitle: "Open Project", systemImageName: "film")
        AppShortcut(intent: OpenLockShortcut(),
                    phrases: ["Open \(\.$slot) in \(.applicationName)"],
                    shortTitle: "Open Shortcut", systemImageName: "bolt")
        AppShortcut(intent: AddPhotos(),
                    phrases: ["Upload photos to \(.applicationName)"],
                    shortTitle: "Upload Photos", systemImageName: "photo.on.rectangle")
        AppShortcut(intent: NextShootDayIntent(),
                    phrases: ["What's shooting next in \(.applicationName)",
                              "Next shoot day in \(.applicationName)"],
                    shortTitle: "Next Shoot Day", systemImageName: "calendar")
    }
}
