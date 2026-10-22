import Foundation

/// The phone's half of carrying a film to his relay: where the address comes
/// from, whose Keychain item the password is, and the sentences that name this
/// iPhone.
///
/// **The road itself is `shared/RelayCarrier.swift`**, written once for both
/// apps since 2026-09-16 — this file was the Mac's twin for a month and the two
/// had drifted by eight hundred lines. Everything below the setup half is a
/// forwarder, so every caller still says `Relay.syncLogs` and the device is
/// handed in before anything is asked.
///
/// Three things genuinely differ, and all three are iOS being iOS:
///
/// - **The address does not come from a file in Application Support.** There is
///   no *Set Up Sync* on a phone and no shared folder to leave one in. It comes
///   from the film itself — `remote.json`, which the Mac writes once and which
///   travels with the package — and only falls back to something typed.
/// - **The Keychain item is this app's**, not one a shell script wrote. It is
///   put there by the setup sheet, once.
/// - **The folder is security-scoped.** Every write here happens inside a
///   project the picker already let us into; nothing opens a scope of its own.
enum Relay {
    /// What differs on a phone, handed to the carrier. Touched by every
    /// forwarder below, so the carrier knows which device it is first.
    static let device: RelayDevice = {
        let phone = RelayDevice(
            name: "this iPhone",
            notSetUp: "Sync isn't set up",
            address: { Relay.address(for: $0) },
            token: { Relay.token })
        RelayCarrier.device = phone
        return phone
    }()

    typealias Report = RelayCarrier.Report
    typealias Trouble = RelayCarrier.Trouble
    typealias Film = RelayCarrier.Film

    // ---- who and where ---------------------------------------------------

    private static let addressKey = "RelayURL"

    /// The relay's address for this film.
    ///
    /// The film's own answer wins. A typed one is the fallback, for the first
    /// film on a phone that has never seen one — and for the case where the
    /// relay moves house, which is the reason it is editable at all.
    static func address(for path: URL?) -> String? {
        if let path, let held = link(at: path), !held.relay.isEmpty { return tidy(held.relay) }
        if let typed = UserDefaults.standard.string(forKey: addressKey), !typed.isEmpty {
            return tidy(typed)
        }
        return nil
    }

    /// The address as it was typed on this phone, whatever any film says.
    /// The setup sheet shows and sets this one.
    static var typedAddress: String {
        get { UserDefaults.standard.string(forKey: addressKey) ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(trimmed, forKey: addressKey)
        }
    }

    private static func tidy(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text = String(text.dropLast()) }
        // A pasted address is as likely to be `sync.example.com` as a whole URL,
        // and a phone keyboard makes typing `https://` a small punishment.
        if !text.hasPrefix("http://"), !text.hasPrefix("https://") { text = "https://" + text }
        return text
    }

    // ---- the word that gets him in ----------------------------------------

    private static let service = "shotlister-relay"
    private static let account = "shotlister-relay-token"

    /// **In the Keychain, never in a file** — the same rule the Mac follows.
    /// A file inside the project would sync to every device the film reaches,
    /// including one he hands to a director.
    static var token: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess,
              let data = found as? Data,
              let word = String(data: data, encoding: .utf8)
        else { return nil }
        return word.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Puts the password away, and **says so when it cannot** — nil on success,
    /// the reason otherwise. An empty one forgets it instead, which is how the
    /// sheet's *Forget* works.
    ///
    /// **The answer is returned rather than dropped.** The first version threw
    /// the `OSStatus` away, and the Keychain refused every write: the sheet
    /// closed as though it had worked, the ⋯ menu went on offering *Set up
    /// sync* rather than *Sync now*, and nothing anywhere said why. A password
    /// that quietly fails to save is the worst of the three possible outcomes.
    @discardableResult
    static func remember(token word: String) -> String? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard !trimmed.isEmpty else { return nil }
        var adding = base
        adding[kSecValueData as String] = Data(trimmed.utf8)
        // **After the first unlock, and never off the phone.** A sync can run
        // while the screen is locked in his pocket, so `WhenUnlocked` would
        // fail there; `ThisDeviceOnly` keeps the word out of an iCloud backup.
        adding[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let how = SecItemAdd(adding as CFDictionary, nil)
        guard how != errSecSuccess else { return nil }
        let why = SecCopyErrorMessageString(how, nil) as String? ?? "\(how)"
        return "Couldn't save the password"
    }

    /// Whether this phone can sync this film at all.
    static func ready(for path: URL?) -> Bool { address(for: path) != nil && token != nil }

    // ---- which film this is ------------------------------------------------

    /// Which film this is, as far as the relay is concerned — the carrier's,
    /// with this phone's address for the film written into a new `remote.json`.
    static func projectId(at path: URL, making: Bool = false) -> String? {
        _ = device
        return RelayCarrier.projectId(at: path, making: making)
    }

    private static func link(at path: URL) -> RelayCarrier.Link? {
        RelayCarrier.link(at: path)
    }

    // ---- the road, forwarded ---------------------------------------------

    static func syncLogs(engine: Engine, path: URL) async throws -> Report {
        _ = device
        return try await RelayCarrier.syncLogs(engine: engine, path: path)
    }

    static func syncMedia(engine: Engine, path: URL) async throws -> Report {
        _ = device
        return try await RelayCarrier.syncMedia(engine: engine, path: path)
    }

    /// Whether the relay answers at all, and lets this phone in. What the setup
    /// sheet's button asks, so a wrong password is found while he is looking at
    /// the field rather than on a location six weeks later.
    static func check(address raw: String, token word: String) async -> String? {
        _ = device
        let base = tidy(raw)
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "No password yet." }
        do {
            _ = try await RelayCarrier.data(at: "\(base)/v1/projects", trimmed)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Everything the relay holds that this phone does not, brought down —
    /// the first step of archiving, so the copy put away is a whole one.
    static func pullEverything(at path: URL) async throws -> (logs: Int, media: Int) {
        _ = device
        return try await RelayCarrier.pullEverything(at: path)
    }

    static func removeFilm(at path: URL, fate: RelayCarrier.Fate) async throws -> Int {
        _ = device
        return try await RelayCarrier.removeFilm(at: path, fate: fate)
    }

    static func wasOnTheRelay(at path: URL) -> Bool { RelayCarrier.wasOnTheRelay(at: path) }
    static func allowResend(at path: URL) { RelayCarrier.allowResend(at: path) }
    static func putBack(at path: URL) async { _ = device; await RelayCarrier.putBack(at: path) }
    static func fate(at path: URL) async -> RelayCarrier.Fate? { _ = device; return await RelayCarrier.fate(at: path) }

    static func films() async throws -> [Film] {
        _ = device
        return try await RelayCarrier.films()
    }

    static func clone(_ film: Film, into folder: URL) async throws -> URL {
        _ = device
        return try await RelayCarrier.clone(film, into: folder)
    }

    // ---- keeping a film in the cloud only — `shared/Offload.swift` --------

    static func offloadCheck(at path: URL,
                             progress: @escaping @MainActor (Int, Int) -> Void) async throws -> Offload.Plan {
        _ = device
        return try await Offload.check(at: path, progress: progress)
    }

    @discardableResult
    static func bringBack(at path: URL,
                          progress: @escaping @MainActor (Int, Int) -> Void) async throws
        -> (brought: Int, letGo: Int) {
        _ = device
        return try await Offload.bringBack(at: path, progress: progress)
    }
}
