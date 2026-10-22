import SwiftUI
import WebKit
import CryptoKit

/// **The portal's own pages, inside the app** — his trial, 2026-10-08: *"Let's
/// try this new portal approach and see what it feels like. For the staple
/// pages, those still feel native… just the portal pages are the ones we
/// adjust."* It reverses, for a trial, the 10-06 ruling that the phone never
/// shows a web page: his reason now is that native copies of every kind of
/// portal page are *"way too much work to maintain"*.
///
/// So a written page, a deck or a look board is the portal's page itself,
/// drawn by the portal's code, and a new kind of page needs nothing here. The
/// staple pages (the front page, the spec sheet, People, Documents) stay
/// native in `PortalRecord.swift`; `LookPage`, `LookDeck` and `LookBoard`
/// stand unused until he decides.
///
/// **How it gets in.** The portal is behind his Google sign-in, which an app
/// cannot pass. Every request the page makes (the page, its pictures, styles
/// and scripts) goes through `PortalScheme`, which asks the hub's
/// `/phone/web/` door with the token the phone already holds (`phoneWeb` in
/// `hub/src/worker.js`). That door reads only.
///
/// **No signal.** Everything that comes through is kept on the phone, and
/// handed back from there when the hub cannot be reached. A page opened once
/// opens on a set.
struct PortalWebPage: View {
    let item: PortalItem
    @EnvironmentObject private var portal: PortalLine
    @State private var loaded = false
    @State private var failed = false

    var body: some View {
        ZStack {
            PortalWeb.ground.ignoresSafeArea()
            if let project = portal.project, PortalLine.address() != nil, PortalLine.token() != nil {
                PortalWebView(path: "/f/\(project)/\(item.key)", loaded: $loaded, failed: $failed)
                    .ignoresSafeArea(edges: .bottom)
                    .opacity(loaded ? 1 : 0)
            } else {
                ContentUnavailableView("Not Connected", systemImage: "wifi.slash")
            }
            if failed && !loaded {
                ContentUnavailableView("Not on This iPhone", systemImage: item.symbol)
            } else if !loaded {
                ProgressView()
            }
        }
    }
}

#if DEBUG
/// What a page says went wrong, in the simulator's log (`PORTALWEB` lines).
final class PortalSaid: NSObject, WKScriptMessageHandler {
    static let shared = PortalSaid()
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        NSLog("PORTALWEB %@", String(describing: message.body))
    }
}
#endif

enum PortalWeb {
    /// The portal's own ground (`#0A0A0A`), so the page arrives without a flash.
    static let ground = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    static let scheme = "shotlister-portal"
}

struct PortalWebView: UIViewRepresentable {
    let path: String
    @Binding var loaded: Bool
    @Binding var failed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let setup = WKWebViewConfiguration()
        setup.setURLSchemeHandler(PortalScheme.shared, forURLScheme: PortalWeb.scheme)
        setup.allowsInlineMediaPlayback = true
        setup.websiteDataStore = .nonPersistent()
        #if DEBUG
        let said = """
        (function(){const send=(m)=>{try{webkit.messageHandlers.said.postMessage(String(m).slice(0,400))}catch(e){}};
        addEventListener('error',e=>send('error: '+e.message+' @'+e.filename+':'+e.lineno));
        addEventListener('unhandledrejection',e=>send('rejection: '+(e.reason&&e.reason.stack||e.reason)));
        const f=window.fetch;window.fetch=function(u,o){return f.apply(this,arguments).then(r=>{if(!r.ok)send('fetch '+r.status+' '+u);return r},e=>{send('fetch failed '+u+' '+e);throw e})};
        const ce=console.error;console.error=function(){send('console.error: '+[...arguments].join(' '));return ce.apply(console,arguments)};})();
        """
        setup.userContentController.addUserScript(WKUserScript(source: said, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        setup.userContentController.add(PortalSaid.shared, name: "said")
        #endif
        let web = WKWebView(frame: .zero, configuration: setup)
        web.isOpaque = false
        web.backgroundColor = UIColor(PortalWeb.ground)
        web.scrollView.backgroundColor = UIColor(PortalWeb.ground)
        web.scrollView.contentInsetAdjustmentBehavior = .automatic
        web.allowsBackForwardNavigationGestures = true
        web.navigationDelegate = context.coordinator
        if let url = URL(string: "\(PortalWeb.scheme)://portal\(path)") {
            web.load(URLRequest(url: url))
        }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: PortalWebView
        init(_ parent: PortalWebView) { self.parent = parent }

        /// **Only the portal stays inside.** A link to another site (a Drive
        /// file, a video page) opens where it belongs.
        func webView(_ web: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.cancel) }
            if url.scheme == PortalWeb.scheme || url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" {
                return decisionHandler(.allow)
            }
            if action.navigationType == .linkActivated || action.targetFrame?.isMainFrame == true {
                UIApplication.shared.open(url)
                return decisionHandler(.cancel)
            }
            decisionHandler(.allow)
        }

        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
            parent.loaded = true
        }

        func webView(_ web: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.failed = true
        }

        func webView(_ web: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.failed = true
        }
    }
}

/// **Every request the page makes, asked of the hub with the phone's token**,
/// and kept for when there is no signal. One for the whole app: WebKit holds
/// on to a handler for the life of the view, and the cache is shared.
final class PortalScheme: NSObject, WKURLSchemeHandler {
    static let shared = PortalScheme()

    private let lock = NSLock()
    private var running: Set<ObjectIdentifier> = []

    private static var folder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let here = support.appending(path: "Portal").appending(path: "web")
        try? FileManager.default.createDirectory(at: here, withIntermediateDirectories: true)
        return here
    }

    /// What is kept beside each answer, so it can be handed back as it came.
    private struct Kept: Codable { var type: String; var status: Int }

    func webView(_ web: WKWebView, start task: WKURLSchemeTask) {
        let id = ObjectIdentifier(task)
        lock.withLock { _ = running.insert(id) }
        guard let asked = task.request.url,
              let address = PortalLine.address(), let token = PortalLine.token(),
              let url = URL(string: address + "/phone/web" + asked.path(percentEncoded: true)
                            + (asked.query(percentEncoded: true).map { "?" + $0 } ?? ""))
        else {
            finish(task, id, failing: URLError(.badURL))
            return
        }
        let name = SHA256.hash(data: Data((asked.path(percentEncoded: true) + "?" + (asked.query(percentEncoded: true) ?? "")).utf8))
            .map { String(format: "%02x", $0) }.joined()
        let body = Self.folder.appending(path: name)
        let meta = Self.folder.appending(path: name + ".json")
        let range = task.request.value(forHTTPHeaderField: "Range")

        // **What never changes is never asked for twice.** A stored picture is
        // named by its own contents, and a stylesheet or script stamped with
        // the deploy (`?v=`) is the same bytes for that name for ever: a kept
        // copy is the answer, at once, signal or none.
        let forever = asked.path.contains("/pic/") || (asked.query ?? "").hasPrefix("v=")
        if forever, range == nil, let data = try? Data(contentsOf: body),
           let kept = try? JSONDecoder().decode(Kept.self, from: Data(contentsOf: meta)) {
            answer(task, id, url: asked, status: kept.status,
                   headers: ["Content-Type": kept.type, "Content-Length": String(data.count)], data: data)
            return
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if let range { request.setValue(range, forHTTPHeaderField: "Range") }

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let (data, answer) = try await URLSession.shared.data(for: request)
                let http = answer as? HTTPURLResponse
                let status = http?.statusCode ?? 200
                var headers = [String: String]()
                for (key, value) in http?.allHeaderFields ?? [:] {
                    if let key = key as? String, let value = value as? String { headers[key] = value }
                }
                headers.removeValue(forKey: "Content-Encoding")
                headers["Content-Length"] = String(data.count)
                // A whole answer is kept; a slice of a clip is not.
                if status == 200, range == nil {
                    try? data.write(to: body)
                    try? JSONEncoder().encode(Kept(type: http?.mimeType ?? "application/octet-stream", status: status)).write(to: meta)
                }
                self.answer(task, id, url: asked, status: status, headers: headers, data: data)
            } catch {
                // **No signal: what was kept.**
                if let data = try? Data(contentsOf: body),
                   let kept = try? JSONDecoder().decode(Kept.self, from: Data(contentsOf: meta)) {
                    self.answer(task, id, url: asked, status: kept.status,
                                headers: ["Content-Type": kept.type, "Content-Length": String(data.count)], data: data)
                } else {
                    self.finish(task, id, failing: error)
                }
            }
        }
    }

    func webView(_ web: WKWebView, stop task: WKURLSchemeTask) {
        _ = lock.withLock { running.remove(ObjectIdentifier(task)) }
    }

    /// WebKit throws if a stopped task is spoken to, so every answer checks first.
    private func answer(_ task: WKURLSchemeTask, _ id: ObjectIdentifier, url: URL,
                        status: Int, headers: [String: String], data: Data) {
        DispatchQueue.main.async {
            guard self.lock.withLock({ self.running.remove(id) }) != nil else { return }
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
                ?? HTTPURLResponse()
            task.didReceive(response)
            task.didReceive(data)
            task.didFinish()
        }
    }

    private func finish(_ task: WKURLSchemeTask, _ id: ObjectIdentifier, failing error: Error) {
        DispatchQueue.main.async {
            guard self.lock.withLock({ self.running.remove(id) }) != nil else { return }
            task.didFailWithError(error)
        }
    }
}
