import Foundation
import AppKit

/// **The app notices when it has stopped answering, and photographs itself.**
///
/// His report, 2026-09-02: *"When Shotlister is starting, it's getting frozen
/// after startup."* It was real — one core flat out, memory climbing about a
/// gigabyte a minute, the window never finishing its first draw. Sampling the
/// stuck process said exactly where it was: inside SwiftUI's layout, in a size
/// query that was rebuilding a `ForEach` and adding attribute-graph nodes as it
/// went, which is why the memory climbed.
///
/// What could not be done was **make it happen again**. About a hundred and
/// twenty launches — his settings, cleared settings, his window frame, half a
/// dozen window widths, under load, in the background, in front, on his own
/// project and on a copy — came up clean every time. It fired three times in
/// ten minutes and then never again.
///
/// A fault nobody can reproduce cannot be fixed by reasoning about it; the only
/// honest move is to be ready with the evidence the next time it happens. That
/// is this. The main thread bumps a counter twice a second; a thread that is
/// *not* the main thread watches the counter, and if it stops moving for long
/// enough the app runs `sample` on itself and writes the result where it can be
/// found later.
///
/// **Why it has to be an outside process.** When the app is wedged, the wedged
/// thread is the one that would otherwise be asked what it is doing, and it
/// cannot answer. `/usr/bin/sample` reads the stack from outside, so it works
/// precisely when nothing inside the app can.
///
/// It costs a timer at two ticks a second and a sleeping thread. It writes
/// nothing at all unless the app actually stops answering.
enum Watchdog {

    /// How long the main thread may be silent before this counts as a freeze.
    ///
    /// Fifteen seconds is far longer than any honest piece of work on the main
    /// thread — a big import or export already runs off it — so a report means
    /// something is wrong rather than something is slow. Overridable only so
    /// the capture path itself can be proved to work.
    private static var patience: TimeInterval {
        if let said = ProcessInfo.processInfo.environment["SHOTLISTER_WATCHDOG_SECONDS"],
           let seconds = TimeInterval(said), seconds > 0 {
            return seconds
        }
        return 15
    }

    /// Bumped on the main thread, read on the watching thread. Both happen
    /// under this lock, which is the whole of the synchronisation — the value
    /// is a count of ticks, and nothing else ever touches it.
    private static let lock = NSLock()
    private static var beats = 0
    private static var timer: Timer?
    private static var reported = false

    /// **Had the app ever got going before it stopped?**
    ///
    /// Ten beats is five seconds of a main thread answering normally, which is
    /// far more than a launch needs. Before that mark a wedge is the startup
    /// freeze, and nothing he has typed can be lost, because he has not been
    /// given a window to type into — so the app quits itself rather than sit
    /// there eating the machine. After that mark it is his working session, and
    /// the report is all that is written: quitting an app somebody is using is
    /// worse than any freeze.
    private static var everRan: Bool { beatsSeen >= 10 }

    /// How many times the main thread has answered. Read under the lock.
    static var beatsSeen: Int {
        lock.lock(); defer { lock.unlock() }
        return beats
    }

    /// Where a report lands. `~/Library/Logs` is where a person looks — and
    /// where Console shows it — without being told a path.
    static var folder: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Shotlister", isDirectory: true)
    }

    /// Start the heartbeat and the thread that watches it.
    ///
    /// **Not during a checking run.** A check drives the app hard on purpose
    /// and then kills it; a watchdog there would report the battery rather than
    /// a bug, and every run would leave a file behind.
    static func begin() {
        guard timer == nil else { return }
        let beat = Timer(timeInterval: 0.5, repeats: true) { _ in
            lock.lock(); beats += 1; lock.unlock()
        }
        // **`.common`, or it stops the moment a menu opens.** A timer on the
        // default mode is suspended while a menu or a resize is tracking, which
        // is exactly when the main thread looks stopped without being stopped —
        // the false alarm this mode removes.
        RunLoop.main.add(beat, forMode: .common)
        timer = beat

        let watcher = Thread {
            var lastSeen = -1
            var lastMoved = Date()
            while true {
                Thread.sleep(forTimeInterval: 1)
                lock.lock(); let now = beats; lock.unlock()
                if now != lastSeen {
                    lastSeen = now
                    lastMoved = Date()
                    continue
                }
                guard Date().timeIntervalSince(lastMoved) >= patience else { continue }
                let running = everRan
                capture(silentFor: Date().timeIntervalSince(lastMoved))
                // **A startup freeze takes itself off his machine.**
                //
                // His report, 2026-09-02: *"i'm getting spinny wheel of death on
                // startup and it's making my mouse laggy across the whole
                // system."* That second half is the real damage — the runaway
                // grows about a gigabyte a minute (one instance reached
                // twenty-four) and the whole Mac goes down with it. A window
                // that never drew has nothing in it to lose, so the honest
                // thing is to stop, having first written down where it stuck.
                if !running {
                    FileHandle.standardError.write(Data(
                        "froze before it ever drew (\(beatsSeen) beats) — quitting rather than eat the machine\n".utf8))
                    exit(1)
                }
                return
            }
        }
        watcher.name = "Shotlister watchdog"
        // Low priority on purpose: this thread must never be the reason the
        // machine is busy while the app is already in trouble.
        watcher.qualityOfService = .utility
        watcher.start()
    }

    /// Photograph the stuck process and write it down. Once per launch — a
    /// freeze that lasts does not need reporting twice, and `sample` on a
    /// wedged app is not free.
    private static func capture(silentFor seconds: TimeInterval) {
        guard !reported else { return }
        reported = true

        try? FileManager.default.createDirectory(at: folder,
                                                 withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        let name = stamp.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let file = folder.appendingPathComponent("froze-\(name).txt")

        let head = """
        Shotlister stopped answering.

        The main thread went quiet for \(Int(seconds)) seconds, which is what a
        freeze looks like from the inside. Everything below is where it was
        stuck, read from outside the app by `sample`.

        version: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")
        when: \(Date())

        ----------------------------------------------------------------------

        """
        try? head.write(to: file, atomically: true, encoding: .utf8)

        let sample = Process()
        sample.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        sample.arguments = [String(ProcessInfo.processInfo.processIdentifier), "3", "-mayDie"]
        let pipe = Pipe()
        sample.standardOutput = pipe
        sample.standardError = FileHandle.nullDevice
        do {
            try sample.run()
            let out = pipe.fileHandleForReading.readDataToEndOfFile()
            sample.waitUntilExit()
            if let handle = try? FileHandle(forWritingTo: file) {
                handle.seekToEndOfFile()
                handle.write(out)
                try? handle.close()
            }
        } catch {
            if let handle = try? FileHandle(forWritingTo: file) {
                handle.seekToEndOfFile()
                handle.write(Data("could not run sample: \(error)\n".utf8))
                try? handle.close()
            }
        }
        FileHandle.standardError.write(Data("froze — wrote \(file.path)\n".utf8))
    }
}
