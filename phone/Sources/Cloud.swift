import Foundation

/// Asking iCloud for the parts of a project that have not arrived yet.
///
/// **A file in iCloud Drive is not necessarily on this phone.** Nothing brings
/// it down until something asks. The Mac has asked since the beginning
/// (`studio/Sources/Projects.swift`); the phone never did — so a photograph
/// taken on the Mac, or brought in from Drive, was simply *not there* on the
/// phone, and the screen drew the grey square that means "no picture".
///
/// That is what he was looking at when he said the app "keeps a placeholder
/// image, and then it adds a second image": the first frame was real, and had
/// never come down.
///
/// **The Mac's way of spotting one does not work here.** On a Mac a file that
/// has not come down is replaced by a visible stub called `.photo.jpg.icloud`,
/// and the first version of this walked the folder looking for those. On iOS
/// there is no stub: the file appears at its own path, the right name and all,
/// and the only thing that says it is not really here is
/// `ubiquitousItemDownloadingStatus`. So the first version of this found
/// nothing, asked for nothing, and changed nothing — the grey square stayed
/// grey on his phone while the checking looked fine.
enum Cloud {
    /// Start whatever has not come down coming down, and say which files those
    /// are — by stem, because that is how a picture is named after its
    /// contents.
    ///
    /// It does not wait. The phone is holding a scroll view open, not
    /// launching; the files arrive when they arrive and the screen picks them
    /// up on its own once they do.
    @discardableResult
    static func bringDown(_ package: URL) -> Set<String> {
        let manager = FileManager.default
        guard let walk = manager.enumerator(
            at: package,
            includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey]
        ) else { return [] }

        var coming: Set<String> = []
        for case let url as URL in walk {
            // A Mac wrote this package too, and a Mac-made stub can travel. Both
            // shapes are handled: the stub, and the file that is only a promise.
            if url.pathExtension == "icloud" {
                let actual = real(url)
                coming.insert(actual.deletingPathExtension().lastPathComponent)
                try? manager.startDownloadingUbiquitousItem(at: actual)
                continue
            }
            guard let values = try? url.resourceValues(
                    forKeys: [.ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey]),
                  values.isUbiquitousItem == true,
                  let status = values.ubiquitousItemDownloadingStatus,
                  status != .current
            else { continue }
            coming.insert(url.deletingPathExtension().lastPathComponent)
            try? manager.startDownloadingUbiquitousItem(at: url)
        }
        return coming
    }

    /// Films being walked right now.
    @MainActor private static var walking: Set<URL> = []

    /// `bringDown`, **away from the screen and never twice at once.**
    ///
    /// The walk asks iCloud about every file in the film. On Call Her Back that
    /// is 730 files, and sampled on a simulator it held the main thread for
    /// three seconds at a time. It used to run there on opening, on a
    /// three-second heartbeat for as long as a film was open, and once for
    /// every picture found missing — so the app spent most of its life frozen
    /// in it. That was the "slow and clunky" of 2026-10-06.
    ///
    /// Nil means a walk of this film was already under way; its answer will
    /// do.
    @MainActor
    static func bringDownQuietly(_ package: URL) async -> Set<String>? {
        guard !walking.contains(package) else { return nil }
        walking.insert(package)
        defer { walking.remove(package) }
        return await Task.detached(priority: .utility) { bringDown(package) }.value
    }

    /// Whether this file is really on the phone, rather than a name iCloud has
    /// put in the folder and not filled in yet.
    ///
    /// **A file that has not come down still appears at its own path on iOS**,
    /// with the right name — there is no visible stub the way there is on a
    /// Mac. Handing that path to a player gives a black rectangle, so ask.
    static func here(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(
                forKeys: [.ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey]),
              values.isUbiquitousItem == true,
              let status = values.ubiquitousItemDownloadingStatus
        else { return FileManager.default.fileExists(atPath: url.path) }
        return status == .current
    }

    /// `.photo.jpg.icloud` is standing in for `photo.jpg`.
    private static func real(_ stub: URL) -> URL {
        let name = stub.deletingPathExtension().lastPathComponent
        let actual = name.hasPrefix(".") ? String(name.dropFirst()) : name
        return stub.deletingLastPathComponent().appendingPathComponent(actual)
    }
}
