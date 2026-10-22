import SwiftUI

// **New Project and Icon & Color on the phone** (the Mac's, parity 3,
// 2026-10-16).

/// The icons a project can wear and the colors, the Mac's own (`Marks`).
enum MarksPhone {
    static let shapes: [(name: String, path: String)] = [
        ("Circle", "M10 4A6 6 0 1 0 10 16A6 6 0 1 0 10 4Z"),
        ("Square", "M6 3H14A3 3 0 0 1 17 6V14A3 3 0 0 1 14 17H6A3 3 0 0 1 3 14V6A3 3 0 0 1 6 3Z"),
        ("Triangle", "M10 3L17 16H3Z"),
        ("Diamond", "M10 2L18 10L10 18L2 10Z"),
        ("Star", "M10 2L11.88 7.41L17.61 7.53L13.04 10.99L14.7 16.47L10 13.2L5.3 16.47L6.96 10.99L2.39 7.53L8.12 7.41Z"),
        ("Hexagon", "M10 2L16.93 6V14L10 18L3.07 14V6Z"),
        ("Cross", "M8 3H12V8H17V12H12V17H8V12H3V8H8Z"),
        ("Arrow", "M10 3L18 11H14V17H6V11H2Z"),
        ("Bars", "M3 5H7V17H3ZM8 3H12V17H8ZM13 8H17V17H13Z"),
        ("Moon", "M13 3A8 8 0 1 0 13 17A6.5 6.5 0 1 1 13 3Z"),
        ("Drop", "M10 2C10 2 16 9 16 12.5A6 6 0 1 1 4 12.5C4 9 10 2 10 2Z"),
        ("Frame", "M2 5H18V15H2Z"),
    ]
    static let hues: [(name: String, hex: String)] = [
        ("Red", "#D44C47"), ("Orange", "#D9730D"), ("Yellow", "#CB912F"), ("Green", "#448361"), ("Blue", "#337EA9"),
        ("Purple", "#9065B0"), ("Pink", "#C14C8A"), ("Brown", "#9F6B53"), ("Gray", "#787774"),
    ]
    static let firstHue = "#337EA9"
}

/// **Icon & Color** for a project that is Studio's alone: a shape, then a color.
struct IconColorPage: View {
    @EnvironmentObject private var session: Session

    private var mark: FilmMark? { session.view?.project.mark }

    var body: some View {
        List {
            Section("Icon") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                    ForEach(MarksPhone.shapes, id: \.name) { shape in
                        let on = shape.path == mark?.path
                        Button {
                            session.setMark(path: shape.path, colour: mark?.colour ?? MarksPhone.firstHue)
                        } label: {
                            Outline.Shape(d: shape.path)
                                .fill(on ? Color(markHex: String((mark?.colour ?? MarksPhone.firstHue).dropFirst())) : Color(.tertiaryLabel))
                                .frame(width: 24, height: 24)
                                .frame(width: 44, height: 44)
                                .background(RoundedRectangle(cornerRadius: Kit.Radius.control, style: .continuous)
                                    .fill(on ? Color(.tertiarySystemFill) : Color.clear))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(shape.name)
                    }
                }
                .padding(.vertical, 4)
            }
            if mark != nil {
                Section("Color") {
                    ForEach(MarksPhone.hues, id: \.hex) { hue in
                        Button {
                            session.setMark(path: mark?.path ?? "", colour: hue.hex)
                        } label: {
                            HStack {
                                Circle().fill(Color(markHex: String(hue.hex.dropFirst()))).frame(width: 18, height: 18)
                                Text(hue.name).foregroundStyle(Color(.label))
                                Spacer()
                                if mark?.colour.uppercased() == hue.hex.uppercased() { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                    }
                }
                Section { Button("Remove Icon", role: .destructive) { session.setMark(path: "", colour: "") } }
            }
        }
        .navigationTitle("Icon & Color")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// **New Project** (the Mac's, when the server makes projects): the name, its
/// Type and the Aspect Ratio Studio draws at. The server makes the Notion row,
/// the Drive folder and the record, then the project's Studio side, which comes
/// down to this iPhone and opens.
struct NewProjectPhone: View {
    @Environment(\.dismiss) private var dismiss
    let folder: URL?
    let made: (URL) -> Void

    @State private var name = ""
    @State private var type = "Narrative"
    @State private var ratio = 2.39
    @State private var working: String?
    @State private var trouble: String?
    @FocusState private var naming: Bool

    private var ready: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && working == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name).focused($naming).onSubmit { if ready { create() } }
                    Picker("Type", selection: $type) { ForEach(ProjectTypes.all, id: \.self) { Text($0).tag($0) } }
                    RatioMenu(title: "Aspect Ratio", current: ratio) { ratio = $0 }
                }
                if let line = working ?? trouble {
                    Section {
                        HStack(spacing: 8) {
                            if working != nil { ProgressView() }
                            Text(line).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(working != nil) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }.disabled(!ready).accessibilityIdentifier("newproject.create")
                }
            }
            .interactiveDismissDisabled(working != nil)
        }
        .onAppear { naming = true }
    }

    private func create() {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty, let folder else { trouble = "Choose a projects folder"; return }
        let id = String((0..<32).map { _ in "0123456789abcdef".randomElement()! })
        trouble = nil
        working = "Making the project…"
        Task { @MainActor in
            do {
                try await NewProjectDoor.makeCard(name: wanted, type: type, id: id)
                working = "Making its Studio side…"
                let (relay, title) = try await NewProjectDoor.studioSide(id: id)
                working = "Downloading…"
                let url = try await Relay.clone(Relay.Film(project: relay, title: title.isEmpty ? wanted : title, logs: 0, bytes: 0),
                                                into: folder)
                // Studio's own: the frame, and the kind the Type implies.
                if let engine = try? Engine(path: url.path) {
                    if ProjectTypes.isCommercial(type) { _ = engine.raw("kind", "commercial") }
                    struct V: Decodable { var project: P; struct P: Decodable { var id: String } }
                    if let v = try? JSONDecoder().decode(V.self, from: engine.raw("view")), !v.project.id.isEmpty {
                        _ = engine.raw("set", v.project.id, "aspect_ratio", String(format: "%.4f", ratio))
                    }
                    _ = engine.raw("save")
                }
                working = nil
                dismiss()
                made(url)
            } catch {
                working = nil
                trouble = error.localizedDescription
            }
        }
    }
}

/// The server's New Project door, the Mac's `CardDoor`.
enum NewProjectDoor {
    struct Trouble: LocalizedError { let said: String; var errorDescription: String? { said } }

    private static func json(_ path: String, body: [String: Any]? = nil, wait: TimeInterval = 20) async throws -> [String: Any] {
        guard let address = PortalLine.address(), let token = PortalLine.token(),
              let url = URL(string: "\(address)/console/\(path)") else { throw Trouble(said: "Sync isn't set up") }
        var ask = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: wait)
        ask.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if let body {
            ask.httpMethod = "POST"
            ask.setValue("application/json", forHTTPHeaderField: "Content-Type")
            ask.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, answer) = try await URLSession.shared.data(for: ask)
        let status = (answer as? HTTPURLResponse)?.statusCode ?? 0
        let got = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if status == 401 { throw Trouble(said: "The server refused this iPhone") }
        if status != 200 { throw Trouble(said: (got["problem"] as? String) ?? "The server answered \(status)") }
        return got
    }

    /// Whether the server makes projects (its one-ID switch).
    static func on() async -> Bool {
        guard let got = try? await json("studio/oneid", wait: 5) else { return false }
        return got["on"] as? Bool == true
    }

    static func makeCard(name: String, type: String, id: String) async throws {
        let ask = try await json("studio/asks", body: ["method": "create_project",
                                                       "args": [["name": name, "type": type, "tier1": true, "id": id]],
                                                       "by": "studio"])
        guard let askId = ask["id"] as? String else { throw Trouble(said: "The server did not take the ask") }
        let deadline = Date().addingTimeInterval(240)
        var item = ask
        while Date() < deadline {
            let state = item["state"] as? String ?? ""
            if state == "done" { return }
            if state == "failed" { throw Trouble(said: (item["error"] as? String) ?? "The project was not made") }
            try await Task.sleep(nanoseconds: 3_000_000_000)
            item = try await json("studio/asks/\(askId)")
        }
        throw Trouble(said: "Still setting up")
    }

    static func studioSide(id: String) async throws -> (String, String) {
        let got = try await json("studio/projects/\(id)/studio", body: ["by": "studio"], wait: 60)
        guard got["ok"] as? Bool == true, let relay = got["relay"] as? String else {
            throw Trouble(said: (got["why"] as? String) ?? "The server did not make it")
        }
        return (relay, (got["title"] as? String) ?? "")
    }
}
