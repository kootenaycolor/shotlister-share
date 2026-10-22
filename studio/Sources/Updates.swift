import SwiftUI
#if SHOTLISTER_UPDATES
import Sparkle
#endif

/// **The app keeping itself current on a Mac that did not build it.**
///
/// He has two Macs. One of them compiles this; the other only ever receives it,
/// and before 2026-08-24 there was no way for the second one to hear that a
/// newer version existed. Sparkle is the answer — the app asks a small file on
/// the internet what the newest version is, and offers it.
///
/// **Nearly all of this file is absent from an everyday build.** `build.sh`
/// passes `-DSHOTLISTER_UPDATES` only when it is building something meant to
/// leave this Mac, so a dev build does not link Sparkle, has no feed, and has
/// no menu item to press. That matters more than it looks: both batteries drive
/// a bundle out of `build/`, over a hundred and fifty checks deep, and an
/// updater waking up mid-run to talk to the network is exactly the sort of
/// thing that reads as a mass failure nobody can explain. The safest updater
/// during a check is one that was never compiled in.
enum Updates {
    /// Whether this copy may update itself at all.
    ///
    /// A checking run is excluded on top of the compile-time gate, because the
    /// batteries can be pointed at any bundle — including, one day, an
    /// installed one — with `SHOTLISTER_APP`.
    static var live: Bool {
        #if SHOTLISTER_UPDATES
        return !Launch.checking
        #else
        return false
        #endif
    }

    /// Whether this copy may check **on its own**, without being asked.
    ///
    /// Only from `/Applications`. A copy still sitting in Downloads, or opened
    /// straight out of the disk image, is being looked at rather than lived in:
    /// it can still be told to check from the menu, but it does not go asking.
    static var checksByItself: Bool {
        live && Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    /// The **Check for Updates…** item, or nothing at all in a build that has
    /// no updater in it. Title Case, because the macOS menu bar is the one
    /// place that stays Title Case — macOS puts its own items in beside ours.
    @ViewBuilder
    static var menuItem: some View {
        #if SHOTLISTER_UPDATES
        if live {
            Button("Check for Updates…") { Updater.shared.check() }
        }
        #endif
    }

    /// Started once, from `applicationDidFinishLaunching`.
    @MainActor
    static func begin() {
        #if SHOTLISTER_UPDATES
        Updater.shared.begin()
        #endif
    }
}

#if SHOTLISTER_UPDATES
/// Holds the one `SPUStandardUpdaterController` for the process.
///
/// Sparkle's controller must be made and used on the main thread, and it must
/// outlive the check it starts — a local would be released the moment the menu
/// item's action returned, taking the download with it.
@MainActor
final class Updater {
    static let shared = Updater()
    private var controller: SPUStandardUpdaterController?

    func begin() {
        guard Updates.live, controller == nil else { return }
        let c = SPUStandardUpdaterController(startingUpdater: true,
                                             updaterDelegate: nil,
                                             userDriverDelegate: nil)
        c.updater.automaticallyChecksForUpdates = Updates.checksByItself
        controller = c
    }

    func check() {
        begin()
        controller?.checkForUpdates(nil)
    }
}
#endif
