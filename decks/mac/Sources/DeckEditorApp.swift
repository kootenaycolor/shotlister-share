import SwiftUI
import AppKit
import WebKit
import UniformTypeIdentifiers

/// Deck Editor — a window on the portal.
///
/// **It used to be a program; it is now a door.** The editor lived here, in a
/// Python server on a fixed port that this app started through a Terminal
/// window, because macOS will not let an ad-hoc signed app read Google Drive.
/// The deck lived in Drive beside it, and the website held a copy that drifted.
///
/// His rebuild of 2026-09-05 moved the editor onto the portal, so a deck has
/// one home and Notion AI can reach it. What is left for a Mac to do is show it
/// and print it — and printing already has its own double-clickable app beside
/// each deck.
///
/// **Two rules survive from the old app and still matter.**
///
/// It needs no permission of any kind. It reads no folder, starts no process
/// and opens no Terminal; it loads one website. That is what keeps a rebuild
/// cheap, because macOS ties permissions to an app's exact signature and every
/// rebuild is a new app as far as the system is concerned.
///
/// And the signed-in session is kept, so signing in to the portal happens once
/// rather than at every launch.

// **Its own front page, not the film shelf.** His correction, 2026-09-06: the
// app should open on a hub of decks, the way the old one did, rather than on
// the portal's front door with the decks a click or two inside it.
private let PORTAL = URL(string: "https://your-domain.example/decks")!

@main
struct DeckEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            Shell()
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1440, height: 920)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Page…") { go(.portalAdd) }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .toolbar) {
                Button("Decks") { go(.portalHome) }
                    .keyboardShortcut("0", modifiers: [.command, .shift])
                Button("Back") { go(.portalBack) }
                    .keyboardShortcut("[")
                Button("Reload") { go(.portalReload) }
                    .keyboardShortcut("r")
                Divider()
                Button("Open in Browser") { go(.portalOutside) }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
            }
        }
    }
}

func go(_ what: Notification.Name) { NotificationCenter.default.post(name: what, object: nil) }

extension Notification.Name {
    static let portalReload = Notification.Name("portalReload")
    static let portalBack = Notification.Name("portalBack")
    static let portalHome = Notification.Name("portalHome")
    static let portalAdd = Notification.Name("portalAdd")
    static let portalOutside = Notification.Name("portalOutside")
}

/**
 * The window: a real toolbar, and the portal under it.
 *
 * His note, 2026-09-06: *"the deck editor need to be more contained, have more
 * mac ui controls. like a homepage to go back to it's document hub, buttons to
 * add new pages, etc. this should feel like it's own contained app even though
 * it is just a portal into the web."*
 *
 * So the chrome is native — a toolbar with the moves he actually makes, and the
 * page under it. It is still one web view, and it still needs no permission.
 */
struct Shell: View {
    @State private var where_: String = ""

    var body: some View {
        Portal(address: $where_)
            .ignoresSafeArea()
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button { go(.portalHome) } label: { Label("Decks", systemImage: "square.grid.2x2") }
                        .help("All your decks")
                    Button { go(.portalBack) } label: { Label("Back", systemImage: "chevron.left") }
                        .help("Back")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { go(.portalAdd) } label: { Label("New Page", systemImage: "plus") }
                        .help("Add a page to this film")
                    Button { go(.portalReload) } label: { Label("Reload", systemImage: "arrow.clockwise") }
                        .help("Reload")
                    Button { go(.portalOutside) } label: { Label("Open in Browser", systemImage: "safari") }
                        .help("Open in your browser")
                }
            }
            .navigationTitle("Deck Editor")
            .navigationSubtitle(where_)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

struct Portal: NSViewRepresentable {
    @Binding var address: String

    func makeCoordinator() -> Coordinator { Coordinator(said: { self.address = $0 }) }

    func makeNSView(context: Context) -> WKWebView {
        let setup = WKWebViewConfiguration()
        // **The signed-in session is kept between launches.** The default store
        // is on disk; an ephemeral one would ask him to sign in every time.
        setup.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: setup)
        web.navigationDelegate = context.coordinator
        // **A UI delegate, so the page can ask.** Without one a WKWebView
        // silently drops every file picker, alert, confirm and prompt — the
        // editor's *Add Stills…* button opened nothing here, and its *Link…*
        // button, which asked through a prompt, did nothing at all. 2026-09-07.
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.load(URLRequest(url: PORTAL))
        context.coordinator.web = web
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var web: WKWebView?

        /// **The file picker, which is the one door onto his stills.** An open
        /// panel he drives himself grants the app that file and nothing else,
        /// so this still needs no permission of any kind.
        func webView(_ web: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping ([URL]?) -> Void) {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection
            panel.allowedContentTypes = [.image]
            panel.prompt = "Add"
            let finish = { (said: NSApplication.ModalResponse) in
                completionHandler(said == .OK ? panel.urls : nil)
            }
            if let window = web.window { panel.beginSheetModal(for: window, completionHandler: finish) }
            else { panel.begin(completionHandler: finish) }
        }

        func webView(_ web: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let box = NSAlert()
            box.messageText = message
            box.runModal()
            completionHandler()
        }

        func webView(_ web: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let box = NSAlert()
            box.messageText = message
            box.addButton(withTitle: "OK")
            box.addButton(withTitle: "Cancel")
            completionHandler(box.runModal() == .alertFirstButtonReturn)
        }

        func webView(_ web: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            let box = NSAlert()
            box.messageText = prompt
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
            field.stringValue = defaultText ?? ""
            box.accessoryView = field
            box.addButton(withTitle: "OK")
            box.addButton(withTitle: "Cancel")
            completionHandler(box.runModal() == .alertFirstButtonReturn ? field.stringValue : nil)
        }
        private let said: (String) -> Void

        init(said: @escaping (String) -> Void) {
            self.said = said
            super.init()
            NotificationCenter.default.addObserver(
                forName: .portalReload, object: nil, queue: .main) { [weak self] _ in
                self?.web?.reload()
            }
            NotificationCenter.default.addObserver(
                forName: .portalBack, object: nil, queue: .main) { [weak self] _ in
                self?.web?.goBack()
            }
            NotificationCenter.default.addObserver(
                forName: .portalHome, object: nil, queue: .main) { [weak self] _ in
                self?.web?.load(URLRequest(url: PORTAL))
            }
            NotificationCenter.default.addObserver(
                forName: .portalOutside, object: nil, queue: .main) { [weak self] _ in
                NSWorkspace.shared.open(self?.web?.url ?? PORTAL)
            }
            // **Add a page to the film he is looking at.** The portal's own
            // route is `/<film>/add`, so this only means anything inside a
            // film — from the deck hub it goes nowhere rather than guessing
            // which film he meant.
            NotificationCenter.default.addObserver(
                forName: .portalAdd, object: nil, queue: .main) { [weak self] _ in
                guard let web = self?.web, let now = web.url else { return }
                let bits = now.path.split(separator: "/").map(String.init)
                guard let first = bits.first, first != "decks" else { NSSound.beep(); return }
                let film = first == "f" && bits.count > 1 ? "/f/\(bits[1])" : "/\(first)"
                if let to = URL(string: film + "/add", relativeTo: now)?.absoluteURL {
                    web.load(URLRequest(url: to))
                }
            }
        }

        /// The subtitle: where he is, in words rather than an address.
        func webView(_ web: WKWebView, didFinish nav: WKNavigation!) {
            let bits = (web.url?.path ?? "").split(separator: "/").map(String.init)
            said(bits.isEmpty || bits == ["decks"] ? "All decks"
                 : bits.last == "edit" ? "Editing" : bits.last?.replacingOccurrences(of: "-", with: " ").capitalized ?? "")
        }

        /// **Anything that is not the portal opens in his own browser.**
        /// A deck links out — to Drive, to Notion, to a film's own site — and a
        /// link followed inside this window would strand him in an app with no
        /// address bar. Cloudflare Access signs him in on its own domain, so
        /// that has to be allowed through or he could never reach the portal.
        func webView(_ web: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, let host = url.host else {
                decisionHandler(.allow); return
            }
            let mine = host.hasSuffix("your-domain.example")
                || host.hasSuffix("cloudflareaccess.com")
                || host.hasSuffix("google.com")

            // **A PDF goes to his Mac, not into this window.** Measured
            // 2026-09-06 in a real WKWebView: it draws *nothing* for a PDF in a
            // frame, and a blank page for one loaded whole. The editor's paper
            // view knows this and offers the file instead — and that offer only
            // means something if the link actually opens. Preview draws it
            // properly, which is what he wanted to look at in the first place.
            if url.pathExtension.lowercased() == "pdf" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel); return
            }
            // **A link asking for a new window would otherwise do nothing.**
            // There is no UI delegate here, so a `target="_blank"` never opens
            // at all — the click reads as a dead button.
            if action.targetFrame == nil {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel); return
            }
            if action.navigationType == .linkActivated && !mine {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }
    }
}
