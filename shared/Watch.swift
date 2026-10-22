import Foundation

/// **The open line to the relay, so a change arrives instead of being waited for.**
///
/// His decision, 2026-08-31: *"lets implement push while the app is open. no
/// need for it while closed."* A change made on the Mac reaches the phone in
/// about a second rather than on its next five-minute check.
///
/// Compiled into both apps — `studio/build.sh` and `phone/project.yml` both pick
/// `shared/` up — because two implementations of *when to sync* would drift, and
/// the drifted one would be the one nobody tested.
///
/// ## What it is not
///
/// **It never carries a change.** The message from the relay is one word. What
/// actually moved is still worked out by `syncplan` and carried by `Relay`, so
/// this adds a *reason* to sync and no second idea of what syncing means.
///
/// **It never replaces the five-minute check.** Push is the fast path; the poll
/// is the one that cannot fail. A socket that drops in a lift and never comes
/// back would be *worse* than polling, because polling always recovers — so the
/// poll stays exactly as it was and this sits on top.
///
/// ## Coming back
///
/// The fiddly half, and the reason this is a class rather than three lines.
/// A line drops constantly in real use — a tunnel, a wifi handover, a laptop
/// lid. So:
///
/// - **It always retries**, backing off 1, 2, 4… to 30 seconds, so a relay that
///   is down does not get hammered by a phone in somebody's pocket.
/// - **The backoff resets the moment a line opens**, or a long outage would
///   leave it waiting half a minute after the network came back.
/// - **`stop()` means stop.** Without a deliberate flag, closing a film would
///   schedule one more reconnect and leave a line open to a film nobody is
///   looking at.
final class Watch {
    /// Said when the relay reports a change. Always on the main queue, because
    /// what it triggers is a sync that touches the screen.
    private let changed: () -> Void

    private var task: URLSessionWebSocketTask?
    private var attempt = 0
    private var stopped = false
    private var retry: DispatchWorkItem?

    /// Whether a line is open right now. Only for reporting — nothing decides
    /// anything on it, because a socket can be dead without either end knowing.
    private(set) var connected = false

    init(onChange: @escaping () -> Void) {
        self.changed = onChange
    }

    deinit { stop() }

    /// Open a line for one film. Safe to call again; it drops any old one first.
    func start(base: String, project: String, token: String) {
        stop()
        stopped = false
        open(base: base, project: project, token: token)
    }

    /// Close it and mean it.
    func stop() {
        stopped = true
        retry?.cancel()
        retry = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        connected = false
    }

    private func open(base: String, project: String, token: String) {
        guard !stopped else { return }
        // `wss` where the relay is `https`. Anything else is a local check.
        let socketBase = base
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        guard let url = URL(string: "\(socketBase)/v1/p/\(project)/watch") else { return }

        // **A `URLRequest`, which is the whole reason this works.** The relay
        // refuses anything unsigned, and a websocket cannot be signed from a
        // browser or from Node — WHATWG's `WebSocket` takes a URL and nothing
        // else. `URLSessionWebSocketTask` takes a request, so the header goes.
        var ask = URLRequest(url: url)
        ask.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        ask.timeoutInterval = 60

        let made = URLSession.shared.webSocketTask(with: ask)
        task = made
        made.resume()
        listen(made, base: base, project: project, token: token)
    }

    /// **One receive at a time, re-armed after each.** `URLSessionWebSocketTask`
    /// hands over exactly one message per `receive`; forgetting to ask again is
    /// a line that works once and then goes quiet for ever, which reads as the
    /// feature being flaky rather than absent.
    private func listen(_ made: URLSessionWebSocketTask,
                        base: String, project: String, token: String) {
        made.receive { [weak self] result in
            guard let self, !self.stopped, self.task === made else { return }
            switch result {
            case .success:
                if !self.connected {
                    self.connected = true
                    self.attempt = 0
                }
                // **What the message says is not read, on purpose.** It is a
                // nudge; the answer to "what moved" comes from the relay's own
                // state and the engine's plan, as it always has. Reading it here
                // would be a second, poorer idea of what changed.
                DispatchQueue.main.async { self.changed() }
                self.listen(made, base: base, project: project, token: token)
            case .failure:
                self.connected = false
                self.again(base: base, project: project, token: token)
            }
        }
    }

    private func again(base: String, project: String, token: String) {
        guard !stopped else { return }
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        attempt += 1
        // 1, 2, 4, 8, 16, then 30 for ever. A phone in a pocket with no signal
        // must not spend its battery asking.
        let wait = min(30, pow(2.0, Double(attempt - 1)))
        let work = DispatchWorkItem { [weak self] in
            self?.open(base: base, project: project, token: token)
        }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }

    /// **Nudge it awake.** Called when the app comes back to the front: a socket
    /// that died while the machine slept often does not report it, so the app
    /// would sit holding a line that is quietly dead. Cheapest correct answer is
    /// to throw it away and open a new one.
    func wakeUp(base: String, project: String, token: String) {
        guard !stopped else { return }
        attempt = 0
        start(base: base, project: project, token: token)
    }
}
