import AppIntents
import Foundation

/// **What a Control Center button does** (his ask, 2026-10-09). Compiled into
/// the app and the widget extension both: the extension only *names* an
/// action, and because each opens the app, the system performs it in the
/// app's own process, where `ControlRouter` hands the address to the same
/// `follow` a lock screen shortcut uses.
enum ControlRouter {
    /// Set by the app as it starts. An address that arrives before it waits.
    @MainActor static var handler: ((URL) -> Void)? {
        didSet {
            guard let handler, let waiting = pending else { return }
            pending = nil
            handler(waiting)
        }
    }
    @MainActor private static var pending: URL?

    @MainActor static func open(_ url: URL) {
        if let handler { handler(url) } else { pending = url }
    }
}

enum SlotChoice: Int, AppEnum {
    case one = 1, two, three, four

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Shortcut"
    static var caseDisplayRepresentations: [SlotChoice: DisplayRepresentation] = [
        .one: "Shortcut 1", .two: "Shortcut 2", .three: "Shortcut 3", .four: "Shortcut 4",
    ]
}

/// A Control Center button's action: one of the four lock screen shortcuts,
/// or 0 for the app itself. Not offered in Shortcuts on its own; *Open
/// Shortcut* is the one for that.
struct OpenFromControl: AppIntent {
    static var title: LocalizedStringResource = "Open Studio Shortcut"
    static var openAppWhenRun = true
    static var isDiscoverable = false

    @Parameter(title: "Shortcut")
    var slot: Int

    init() {}
    init(slot: Int) { self.slot = slot }

    @MainActor
    func perform() async throws -> some IntentResult {
        ControlRouter.open(slot == 0 ? URL(string: "shotlister://open")! : LockShortcuts.one(slot).url)
        return .result()
    }
}
