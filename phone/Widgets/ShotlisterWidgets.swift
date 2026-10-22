import WidgetKit
import AppIntents
import SwiftUI

/// **Shotlister on the lock screen** (his ask, 2026-10-09). Two widgets:
///
/// - **Shotlister** opens the app, nothing to set.
/// - **Shotlister Shortcut** opens one of the four shortcuts set in the
///   app's Settings: a film at a page. The widget only knows which of the four
///   it is, so changing a shortcut in the app changes every widget showing it.
@main
struct ShotlisterWidgets: WidgetBundle {
    var body: some Widget {
        ShortcutWidget()
        OpenWidget()
        ShootDayWidget()
        NextShotsWidget()
        ShortcutControl()
        OpenControl()
    }
}

// MARK: - Control Center buttons

struct ChooseControlShortcut: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Shortcut"

    @Parameter(title: "Shortcut", default: .one)
    var slot: SlotChoice
}

/// One of the four shortcuts, as a button in Control Center, on the lock
/// screen's corners, or on the Action button.
struct ShortcutControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "ShotlisterShortcutControl", intent: ChooseControlShortcut.self) { choice in
            let shortcut = LockShortcuts.one(choice.slot.rawValue)
            ControlWidgetButton(action: OpenFromControl(slot: choice.slot.rawValue)) {
                Label(shortcut.film.map { "\($0) · \(shortcut.subtitle)" } ?? "Studio", systemImage: shortcut.glyph)
            }
        }
        .displayName("Studio Shortcut")
        .description("A project and page, set in Studio's Settings.")
    }
}

struct OpenControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ShotlisterOpenControl") {
            ControlWidgetButton(action: OpenFromControl(slot: 0)) {
                Label("Studio", systemImage: "film")
            }
        }
        .displayName("Studio")
        .description("Opens Studio.")
    }
}

// MARK: - Which shortcut

struct ShortcutEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Shortcut"
    static var defaultQuery = ShortcutQuery()

    let id: Int
    let shortcut: LockShortcut

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Shortcut \(id)",
                              subtitle: "\(shortcut.film.map { "\($0) · \(shortcut.subtitle)" } ?? "Open Studio")")
    }
}

struct ShortcutQuery: EntityQuery {
    func entities(for identifiers: [Int]) async throws -> [ShortcutEntity] {
        identifiers.map { ShortcutEntity(id: $0, shortcut: LockShortcuts.one($0)) }
    }

    func suggestedEntities() async throws -> [ShortcutEntity] {
        LockShortcuts.all().map { ShortcutEntity(id: $0.slot, shortcut: $0) }
    }

    func defaultResult() async -> ShortcutEntity? {
        ShortcutEntity(id: 1, shortcut: LockShortcuts.one(1))
    }
}

struct ChooseShortcut: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Shortcut"
    static var description = IntentDescription("Set each shortcut in Studio's Settings.")

    @Parameter(title: "Shortcut")
    var shortcut: ShortcutEntity?
}

// MARK: - The shortcut widget

struct ShortcutEntry: TimelineEntry {
    let date: Date
    let shortcut: LockShortcut
}

/// Read fresh from the App Group every time, never from the entity the widget
/// was configured with: that is a copy from the moment he chose it, and the
/// app reloads every timeline when a shortcut changes.
struct ShortcutProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ShortcutEntry {
        ShortcutEntry(date: .now, shortcut: LockShortcut(slot: 1, film: "Film", place: "shotlist",
                                                         placeTitle: "Shot List", symbol: "list.bullet.rectangle"))
    }

    func snapshot(for configuration: ChooseShortcut, in context: Context) async -> ShortcutEntry {
        ShortcutEntry(date: .now, shortcut: LockShortcuts.one(configuration.shortcut?.id ?? 1))
    }

    func timeline(for configuration: ChooseShortcut, in context: Context) async -> Timeline<ShortcutEntry> {
        Timeline(entries: [ShortcutEntry(date: .now, shortcut: LockShortcuts.one(configuration.shortcut?.id ?? 1))],
                 policy: .never)
    }
}

struct ShortcutWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ShotlisterShortcut", intent: ChooseShortcut.self,
                               provider: ShortcutProvider()) { entry in
            ShortcutFace(shortcut: entry.shortcut)
                .widgetURL(entry.shortcut.url)
        }
        .configurationDisplayName("Studio Shortcut")
        .description("A project and page, set in Studio's Settings.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }
}

// MARK: - The plain one

struct OpenEntry: TimelineEntry { let date: Date }

struct OpenProvider: TimelineProvider {
    func placeholder(in context: Context) -> OpenEntry { OpenEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (OpenEntry) -> Void) { completion(OpenEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<OpenEntry>) -> Void) {
        completion(Timeline(entries: [OpenEntry(date: .now)], policy: .never))
    }
}

struct OpenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShotlisterOpen", provider: OpenProvider()) { _ in
            ShortcutFace(shortcut: LockShortcut(slot: 0))
                .widgetURL(URL(string: "shotlister://open")!)
        }
        .configurationDisplayName("Studio")
        .description("Opens Studio.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }
}
