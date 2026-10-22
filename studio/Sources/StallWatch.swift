import Foundation

/// **How long the main thread went without answering.**
///
/// His report, 2026-10-15: *"Every time I adjust a slider in the Export tab,
/// there is a freeze with a rainbow wheel."* A freeze is the main thread busy
/// with something else while his hand moves, and the only honest way to
/// prove it gone is to time it: a helper thread knocks on the main thread
/// every few milliseconds and writes down how long each knock waited for an
/// answer. The longest wait is the worst stall he would have felt.
///
/// Only a checking run starts it. It costs a wake-up every 4ms while it runs.
final class StallWatch {
    static let shared = StallWatch()

    private let lock = NSLock()
    private var running = false
    private var worstMs: Double = 0
    private var knocks = 0

    /// Start knocking, or forget what was seen so far if already knocking.
    func reset() {
        lock.lock()
        worstMs = 0
        knocks = 0
        let start = !running
        running = true
        lock.unlock()
        guard start else { return }
        let thread = Thread { [self] in
            while true {
                lock.lock(); let on = running; lock.unlock()
                guard on else { return }
                let sent = DispatchTime.now().uptimeNanoseconds
                let answered = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { answered.signal() }
                answered.wait()
                let waited = Double(DispatchTime.now().uptimeNanoseconds - sent) / 1e6
                lock.lock()
                worstMs = max(worstMs, waited)
                knocks += 1
                lock.unlock()
                Thread.sleep(forTimeInterval: 0.004)
            }
        }
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// The longest wait since `reset`, in milliseconds, and how many knocks.
    var worst: (ms: Double, knocks: Int) {
        lock.lock(); defer { lock.unlock() }
        return (worstMs, knocks)
    }

    func stop() {
        lock.lock(); running = false; lock.unlock()
    }
}
