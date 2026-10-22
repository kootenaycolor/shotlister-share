import Foundation

/// The Mac's half of carrying a film to his relay: where the address is, whose
/// Keychain item the password is, and the sentences that name this Mac.
///
/// **The road itself is `shared/RelayCarrier.swift`**, written once for both
/// apps since 2026-09-16 — this file was its twin's twin for a month and the
/// two had drifted by eight hundred lines. Everything below the setup half is a
/// forwarder, kept so every caller still says `Relay.syncLogs` and so the
/// device is handed in before anything is asked.
enum Relay {
    /// What differs on a Mac, handed to the carrier. Touched by every forwarder
    /// below, so the carrier knows which device it is before it says a word.
    static let device: RelayDevice = {
        let mac = RelayDevice(
            name: "this Mac",
            notSetUp: "Sync isn't set up",
            address: { _ in
                guard let base = Relay.address else { return nil }
                return base.hasSuffix("/") ? String(base.dropLast()) : base
            },
            token: { Relay.token })
        RelayCarrier.device = mac
        return mac
    }()

    typealias Report = RelayCarrier.Report
    typealias Trouble = RelayCarrier.Trouble
    typealias Film = RelayCarrier.Film

    // ---- who and where ---------------------------------------------------

    /// Where *Set Up Sync* leaves the address, and where the setup sheet writes
    /// it. One path, named once, because two spellings of it is a bug that
    /// looks like the Keychain refusing.
    private static var addressFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Shotlister/relay-url")
    }

    /// What a checking run saves instead of his real setup.
    ///
    /// **A check must not touch either.** The file is the relay this Mac
    /// actually uses and the Keychain item is the password itself; a check that
    /// wrote to them would take his sync away and the damage would outlive the
    /// run. Ref 450 is the same lesson learned in the fixtures. Kept in memory
    /// rather than in the defaults so a run leaves nothing behind at all.
    private static var addressThisRun: String?
    private static var wordThisRun: String?

    /// The relay's address, as *Set Up Sync* or the setup sheet left it.
    static var address: String? {
        if Launch.checking, let held = addressThisRun {
            return held.isEmpty ? nil : held
        }
        if let text = try? String(contentsOf: addressFile, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return UserDefaults.standard.string(forKey: "RelayURL")
    }

    /// An address with the parts a person leaves out.
    ///
    /// The same rule as the phone's, and for the same reason: what he pastes is
    /// as likely to be `sync.example.com` as a whole URL, and everything
    /// downstream builds paths by sticking `/v1/...` on the end — so one
    /// trailing slash makes every request a double slash, and a missing scheme
    /// makes `URL(string:)` hand back something that is not a web address at
    /// all. `request` returns nil for that and the failure reads as *Bad
    /// address*, which is true and unhelpful.
    static func tidy(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text = String(text.dropLast()) }
        if text.isEmpty { return text }
        if !text.hasPrefix("http://"), !text.hasPrefix("https://") { text = "https://" + text }
        return text
    }

    /// Puts the address away, and **says so when it cannot** — nil on success,
    /// the reason otherwise. The same shape as `remember(token:)`, so the sheet
    /// treats both the same way.
    ///
    /// **A checking run writes to the defaults, never to the file.** The file
    /// is his actual setup on this Mac; a check that saved an address would
    /// take his real relay away and the damage would outlive the run. Ref 450
    /// is the same lesson learned in the fixtures.
    @discardableResult
    static func remember(address raw: String) -> String? {
        let tidied = tidy(raw)
        guard !tidied.isEmpty else { return "No address yet." }
        if Launch.checking {
            addressThisRun = tidied
            return nil
        }
        do {
            try FileManager.default.createDirectory(
                at: addressFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try tidied.write(to: addressFile, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return "The address could not be saved on this Mac. \(error.localizedDescription)"
        }
    }

    /// The word that gets his devices in.
    ///
    /// **In the Keychain, never in a file.** A file in the repo is a file that
    /// gets committed, copied to another machine, or read over his shoulder.
    static var token: String? {
        // **A checking run never asks the Keychain.**
        //
        // Every build is signed afresh, so macOS does not recognise the new
        // binary as the one that stored the relay password and puts up *"wants
        // to use your confidential information"*. A quiet run is never
        // frontmost and can never answer it, so the app sits at the top bar —
        // which reads `ready` — until something kills it. That is the **whole
        // battery hanging after every rebuild**, and it cost an afternoon
        // looking like a crash in unrelated code. A check that actually needs a
        // token hands one in by `RELAY_TOKEN`, the same name `remote/checks.sh`
        // already uses.
        if Launch.checking {
            if let saved = wordThisRun { return saved.isEmpty ? nil : saved }
            let handed = ProcessInfo.processInfo.environment["RELAY_TOKEN"]
            return (handed?.isEmpty ?? true) ? nil : handed
        }
        if let held = remembered() { return held }
        let found = fromTheKeychain()
        remember(found)
        return found
    }

    // ---- asking the Keychain without freezing the app ----------------------
    //
    // **The Keychain is not something a view may ask.**
    //
    // `SecItemCopyMatching` blocks — and when macOS does not recognise the
    // program asking, it blocks for as long as it takes somebody to answer
    // *"ShotlisterStudio wants to use your confidential information"*. The
    // toolbar read `ready` while drawing itself, so that wait happened **on the
    // main thread, during the first draw**: no window, no dialog anybody could
    // find, and an app that never finished starting.
    //
    // It does not recognise the program often. Every build is signed afresh, so
    // the *first launch after any rebuild* is a program the Keychain has never
    // seen. That made it look like whatever had just been changed, twice in one
    // evening, and neither time was it.
    //
    // So: the answer is remembered for the life of the run, `ready` will only
    // ever read what is already known, and the one blocking look happens on
    // another thread. `token` itself still waits — but only ever from something
    // he pressed, by which time there is a window for the dialog to sit over.

    private static let vault = NSLock()
    /// Outer `nil` means nobody has looked yet; inner `nil` means there is none.
    private static var learned: String??
    private static var looking = false

    private static func remembered() -> String?? {
        vault.lock()
        defer { vault.unlock() }
        return learned
    }

    private static func remember(_ word: String?) {
        vault.lock()
        learned = .some(word)
        looking = false
        vault.unlock()
    }

    private static func fromTheKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "shotlister-relay",
            kSecAttrAccount as String: "shotlister-relay-token",
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
    /// the reason otherwise. An empty one forgets it instead.
    ///
    /// **The answer is returned rather than dropped**, the same lesson the
    /// phone learned (Ref 494 is the other half of it): a password that quietly
    /// fails to save leaves a sheet closing as though it worked and a sync
    /// button that never appears, with nothing anywhere saying why.
    ///
    /// The in-memory answer is replaced too, and the toolbar told — otherwise
    /// `ready` goes on saying what it learned at launch and the button he just
    /// set up does not turn up until the next start.
    ///
    /// **A checking run does not touch the Keychain.** `token` already
    /// short-circuits to `RELAY_TOKEN` for one, so a check saving a password
    /// would write to his real Keychain to no purpose whatsoever.
    @discardableResult
    static func remember(token word: String) -> String? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        // **Everything but the Keychain call itself.** A check can then drive
        // the whole way in — save, then `ready`, then the button — which is the
        // thing that was broken on his laptop and the thing worth checking.
        if Launch.checking {
            wordThisRun = trimmed
            NotificationCenter.default.post(name: learnedTheWord, object: nil)
            return nil
        }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "shotlister-relay",
            kSecAttrAccount as String: "shotlister-relay-token",
        ]
        SecItemDelete(base as CFDictionary)
        guard !trimmed.isEmpty else {
            remember(nil)
            NotificationCenter.default.post(name: learnedTheWord, object: nil)
            return nil
        }
        var adding = base
        adding[kSecValueData as String] = Data(trimmed.utf8)
        // **After the first unlock, and never off this Mac.** The list syncs
        // itself on a timer, which can come round while the screen is locked;
        // `ThisDeviceOnly` keeps the word out of iCloud Keychain, where it
        // would land on machines that are his but are not set up for this.
        adding[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let how = SecItemAdd(adding as CFDictionary, nil)
        guard how == errSecSuccess else {
            let why = SecCopyErrorMessageString(how, nil) as String? ?? "\(how)"
            return "The password could not be saved on this Mac. \(why) (\(how))"
        }
        remember(trimmed)
        NotificationCenter.default.post(name: learnedTheWord, object: nil)
        return nil
    }

    /// Whether the relay answers at all, and lets this Mac in.
    ///
    /// What the setup sheet's *Check* asks, so a wrong password is found while
    /// he is looking at the field rather than on a location six weeks later.
    /// Takes both rather than reading them back, because nothing is saved until
    /// he presses Save.
    static func check(address raw: String, token word: String) async -> String? {
        let base = tidy(raw)
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return "No address yet." }
        guard !trimmed.isEmpty else { return "No password yet." }
        do {
            _ = try await RelayCarrier.data(at: "\(base)/v1/projects", trimmed)
            return nil
        } catch let trouble as Trouble {
            return trouble.errorDescription ?? "\(trouble)"
        } catch {
            return error.localizedDescription
        }
    }

    /// Said once, when the answer arrives, so the toolbar can draw itself again.
    static let learnedTheWord = Notification.Name("RelayLearnedTheWord")

    /// Go and ask, on a thread that is allowed to wait. Safe to call as often as
    /// you like; only the first call does anything.
    static func warmUp() {
        if Launch.checking { return }
        vault.lock()
        if learned != nil || looking {
            vault.unlock()
            return
        }
        looking = true
        vault.unlock()
        DispatchQueue.global(qos: .userInitiated).async {
            let found = fromTheKeychain()
            remember(found)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: learnedTheWord, object: nil)
            }
        }
    }

    /// Whether this Mac has been set up to sync at all.
    ///
    /// **Answers from memory and never waits.** Until the word is known this is
    /// `false`, the button says the Mac is not set up, and the notification
    /// above puts it right a moment later. A toolbar that is briefly wrong is a
    /// trade against an app that does not start.
    static var ready: Bool {
        guard address != nil else { return false }
        // **A checking run has to answer the same way `token` does.**
        //
        // `token` short-circuits for a checking run and hands back `RELAY_TOKEN`
        // without touching the Keychain — but `warmUp` returns immediately for
        // one, so `learned` is never filled and this read `false` for ever.
        // Every door that syncs then reported *"Sync is not set up on this
        // Mac"* and quietly did nothing: `--sync`, `--copyword` and `--autolist`
        // alike, all three passing for the wrong reason. Found 2026-08-31 while
        // checking the automatic list sync, which appeared not to work and did.
        if Launch.checking { return token != nil }
        guard let held = remembered() else {
            warmUp()
            return false
        }
        return held != nil
    }

    /// Which film this is, as far as the relay is concerned — the carrier's,
    /// with this Mac's address written into a new `remote.json`.
    static func projectId(at path: URL, making: Bool = false) -> String? {
        _ = device
        return RelayCarrier.projectId(at: path, making: making)
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

    static func forget(_ names: [String], path: URL) async -> Int {
        _ = device
        return await RelayCarrier.forget(names, path: path)
    }

    static func picturesWaiting(engine: Engine, path: URL) async throws -> Int {
        _ = device
        return try await RelayCarrier.picturesWaiting(engine: engine, path: path)
    }

    @discardableResult
    static func pullEverything(at path: URL) async throws -> (logs: Int, media: Int) {
        _ = device
        return try await RelayCarrier.pullEverything(at: path)
    }

    @discardableResult
    static func wasOnTheRelay(at path: URL) -> Bool { RelayCarrier.wasOnTheRelay(at: path) }
    static func allowResend(at path: URL) { RelayCarrier.allowResend(at: path) }
    static func putBack(at path: URL) async { _ = device; await RelayCarrier.putBack(at: path) }
    static func fate(at path: URL) async -> RelayCarrier.Fate? { _ = device; return await RelayCarrier.fate(at: path) }

    static func removeFilm(at path: URL, fate: RelayCarrier.Fate) async throws -> Int {
        _ = device
        return try await RelayCarrier.removeFilm(at: path, fate: fate)
    }

    static func removeFilmSaying(at path: URL, fate: RelayCarrier.Fate) async throws
        -> (gone: Int, keptAt: String, keptFiles: Int) {
        _ = device
        return try await RelayCarrier.removeFilmSaying(at: path, fate: fate)
    }

    static func unsent(engine: Engine, path: URL) async throws -> (logs: [String], media: [String]) {
        _ = device
        return try await RelayCarrier.unsent(engine: engine, path: path)
    }

    /// **The Projects Console's archive door acts for him, on his relay.**
    ///
    /// It is a checking run — invisible, ends by itself — and a checking run
    /// never asks the Keychain, because a freshly signed build would put up
    /// *"wants to use your confidential information"* where nobody can answer
    /// it. This door is the exception the console needs: the installed,
    /// Developer ID-signed app is the program that stored the password, so it
    /// is let in without a question. Asked once, off the main thread, and
    /// given up on after `patience` seconds rather than left to hang.
    ///
    /// A check hands its own word in (`RELAY_TOKEN`, `--syncsave`) and never
    /// gets this far, so no check can reach his real password.
    static func lendTheDoorHisWord(patience: Double = 20) async -> Bool {
        if token != nil { return true }
        guard Launch.checking else { return false }
        // Whichever answers first: the Keychain, or the clock. A Keychain
        // that is waiting on a question nobody can see never answers, and a
        // task group would wait for it anyway — so a plain race, once.
        let found: String? = await withCheckedContinuation { answer in
            let once = Once()
            DispatchQueue.global(qos: .userInitiated).async {
                let word = fromTheKeychain()
                once.run { answer.resume(returning: word) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + patience) {
                once.run { answer.resume(returning: nil) }
            }
        }
        wordThisRun = found ?? ""
        return found != nil
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func run(_ body: () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            body()
        }
    }

    static func picturesAt(_ path: URL) -> String? {
        _ = device
        return RelayCarrier.picturesAt(path)
    }

    static func auditLogs(at path: URL) async -> String {
        _ = device
        return await RelayCarrier.auditLogs(at: path)
    }

    /// **What the relay said last time it was asked**, so a screen that opens
    /// twice does not go to the network twice — and so a checking run can ask
    /// once and then draw. Nil until something has asked.
    private(set) static var knownFilms: [Film]?

    static func films() async throws -> [Film] {
        _ = device
        let films = try await RelayCarrier.films()
        knownFilms = films
        return films
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

extension RelayCarrier.Film {
    /// The pair the manifest carries, as the switcher draws it. Nothing for a
    /// film with no mark.
    var mark: Console.Mark? {
        markPath.isEmpty || markColour.isEmpty ? nil : Console.Mark(path: markPath, colour: markColour)
    }
}
