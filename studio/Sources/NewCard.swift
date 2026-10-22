import AppKit
import SwiftUI

/// **New Project makes the card** (2026-10-14, stage 5 step 2; his answers 6,
/// 14, 15). One record per project, kept by the server. While the server's
/// one-ID switch is on, Studio's New Project no longer makes a film here and
/// then asks which Notion project it belongs to: it makes the project the way
/// Projects Console does (the server's New Project: Notion row, Drive folder,
/// record), under an ID minted on this Mac, then asks the server for the
/// project's Studio side under that same ID and fetches it from the relay.
/// Nothing to link, nothing to carry.
///
/// With the switch off, or the server out of reach, New Project is what it was
/// (`NewProjectSheet`).
enum CardDoor {
    /// The server's address and the relay's word — the Spec Sheet's door.
    private static func base() -> (String, String)? {
        guard let address = SpecSheets.address(), let token = SpecSheets.token() else { return nil }
        return (address, token)
    }

    private static func request(_ path: String, body: [String: Any]? = nil, wait: TimeInterval = 20) throws -> URLRequest {
        guard let (address, token) = base(), let url = URL(string: "\(address)/console/\(path)") else {
            throw Trouble(said: "Sync isn't set up")
        }
        var ask = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: wait)
        ask.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if let body {
            ask.httpMethod = "POST"
            ask.setValue("application/json", forHTTPHeaderField: "Content-Type")
            ask.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return ask
    }

    private static func json(_ path: String, body: [String: Any]? = nil, wait: TimeInterval = 20) async throws -> [String: Any] {
        let (data, answer) = try await URLSession.shared.data(for: try request(path, body: body, wait: wait))
        let status = (answer as? HTTPURLResponse)?.statusCode ?? 0
        let got = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if status == 401 { throw Trouble(said: "The server refused this Mac") }
        if status != 200 { throw Trouble(said: (got["problem"] as? String) ?? "The server answered \(status)") }
        return got
    }

    struct Trouble: LocalizedError {
        let said: String
        var errorDescription: String? { said }
    }

    /// Whether New Project makes the card. False when the server cannot be asked.
    static func on() async -> Bool {
        guard let got = try? await json("studio/oneid", wait: 5) else { return false }
        return got["on"] as? Bool == true
    }

    /// 32 hex characters — the shape relay ids and Notion page ids share.
    static func mint() -> String {
        String((0..<32).map { _ in "0123456789abcdef".randomElement()! })
    }

    /// The form Projects Console's New Project sends, with this Mac's own ID.
    static func form(name: String, type: String, id: String) -> [String: Any] {
        ["name": name, "type": type, "tier1": true, "id": id]
    }

    /// Make the card: the server's New Project, asked as the phone asks it,
    /// and waited for (it runs on the server's minute: up to four minutes).
    static func makeCard(name: String, type: String, id: String) async throws {
        let ask = try await json("studio/asks", body: ["method": "create_project",
                                                       "args": [form(name: name, type: type, id: id)],
                                                       "by": "studio"])
        guard let askId = ask["id"] as? String else { throw Trouble(said: "The server did not take the ask") }
        let deadline = Date().addingTimeInterval(240)
        var item = ask
        while Date() < deadline {
            let state = item["state"] as? String ?? ""
            if state == "done" { break }
            if state == "failed" { throw Trouble(said: (item["error"] as? String) ?? "The project was not made") }
            try await Task.sleep(nanoseconds: 3_000_000_000)
            item = try await json("studio/asks/\(askId)")
        }
        guard item["state"] as? String == "done" else { throw Trouble(said: "Still setting up") }
    }

    /// The project's Studio side, made under its ID on the server; `(relay, title)`.
    static func studioSide(id: String) async throws -> (String, String) {
        let got = try await json("studio/projects/\(id)/studio", body: ["by": "studio"], wait: 60)
        guard got["ok"] as? Bool == true, let relay = got["relay"] as? String else {
            throw Trouble(said: (got["why"] as? String) ?? "The server did not make it")
        }
        return (relay, (got["title"] as? String) ?? "")
    }

    /// Fetch it from the relay into the films folder; its folder.
    static func fetch(relay: String, title: String, into folder: URL = Projects.home()) async throws -> URL {
        try await Relay.clone(RelayCarrier.Film(project: relay, title: title, logs: 0, bytes: 0), into: folder)
    }
}

/// The sheet: what the project is called, its Type, and the frame Studio
/// draws at. Everything else about the project is the console's.
struct NewCardSheet: View {
    @ObservedObject var state: ShellState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    @State private var name = ""
    @State private var type = "Narrative"
    @State private var ratio = 2.39
    @State private var working: String?
    @State private var trouble: String?
    @FocusState private var naming: Bool

    private var ready: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && working == nil }

    var body: some View {
        Sheet(title: "New Project", width: .standard, height: 320, scrolls: true) {
            Field("Name") {
                TextField("", text: $name)
                    .textFieldStyle(.plain)
                    .sans(Brand.Size.body)
                    .foregroundStyle(Brand.ink(dark))
                    .focused($naming)
                    .onSubmit { if ready { create() } }
                    .field(dark)
            }
            Field("Type") {
                Segmented(selection: $type, items: ProjectTypes.all.map {
                    .init(value: $0, title: $0)
                }, quiet: true)
                .fixedSize()
            }
            Field("Aspect Ratio", width: 220) {
                FrameRatioMenu(current: ratio, choose: { ratio = $0 }) {
                    FieldFace(text: Ratios.title(ratio), dark: dark)
                }
            }
            if let line = working ?? trouble {
                HStack(spacing: 8) {
                    if working != nil { ProgressView().controlSize(.small) }
                    Text(line).sans(Brand.Size.small)
                        .foregroundStyle(trouble != nil && working == nil ? Brand.warn(dark) : Brand.ink2(dark))
                }
            }
        } leading: {
            EmptyView()
        } trailing: {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(working != nil)
            Button("Create Project") { create() }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .disabled(!ready)
        }
        .onAppear { naming = true }
    }

    private func create() {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return }
        let id = CardDoor.mint()
        trouble = nil
        working = "Making the project…"
        Task { @MainActor in
            do {
                try await CardDoor.makeCard(name: wanted, type: type, id: id)
                working = "Making its Studio side…"
                let (relay, title) = try await CardDoor.studioSide(id: id)
                working = "Downloading…"
                let url = try await CardDoor.fetch(relay: relay, title: title.isEmpty ? wanted : title)
                if state.open(url), let engine = state.engine {
                    // Film content, Studio's own: the frame, and the kind the Type implies.
                    if ProjectTypes.isCommercial(type) { state.replace(engine.setKind("commercial")) }
                    if let id = state.view?.project.id {
                        state.replace(engine.set(shot: id, field: "aspect_ratio", value: String(format: "%.4f", ratio)))
                    }
                }
                working = nil
                dismiss()
            } catch {
                working = nil
                trouble = error.localizedDescription
            }
        }
    }
}
