import SwiftUI

/// **Media: every picture and clip in the film**, on the phone. His ask,
/// 2026-10-10 (Notion SL-1687, mockup `design/44-media.html`): Film Settings ›
/// Media. The same list as the Mac's Media window — biggest first, where each
/// is used or Not Used, Delete, Delete Unused, and the names deleted ones
/// left behind. The engine decides (`engine::shelf`); this draws it.
struct MediaShelf: Decodable {
    var items: [Item]
    var gone: [Gone]
    var count: Int
    var bytes: Int
    var unused: Int
    var unusedBytes: Int

    struct Item: Decodable, Identifiable, Hashable {
        var media: String
        var hash: String
        var filename: String
        var kind: String
        var bytes: Int
        var width: Int
        var height: Int
        var seconds: Double
        var versions: Int
        var uses: [Use]
        var id: String { media }
        var used: Bool { !uses.isEmpty }
        var frame: Engine.Frame { Engine.Frame(hash: hash, filename: filename, said: kind) }
    }

    struct Use: Decodable, Identifiable, Hashable {
        var ref: String
        var owner: String
        var kind: String
        var label: String
        var detail: String
        var scene: String
        var id: String { ref }
    }

    struct Gone: Decodable, Identifiable, Hashable {
        var media: String
        var hash: String
        var filename: String
        var bytes: Int
        var on: Double
        var id: String { media }
    }

    static func size(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f.string(fromByteCount: Int64(bytes))
    }

    static func day(_ millis: Double) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: Date(timeIntervalSince1970: millis / 1000))
    }
}

extension Session {
    /// Every picture and clip, as the engine sees it now.
    func mediaShelf() -> MediaShelf? {
        guard let engine else { return nil }
        return try? JSONDecoder().decode(MediaShelf.self, from: engine.raw("shelf"))
    }

    /// **Delete for real**: every use, and the files. Not undoable. `nil`
    /// deletes everything nothing uses. Answers how many and how much.
    @discardableResult
    func deleteMedia(_ media: [String]?) -> (deleted: Int, freed: Int)? {
        guard let engine else { return nil }
        let parts = media.map { ["deletemedia"] + $0 } ?? ["deletemedia", "unused"]
        let reply = (try? engine.call(parts)) as? [String: Any]
        refresh()
        guard let reply, let n = reply["deleted"] as? Int else { return nil }
        return (n, reply["freedBytes"] as? Int ?? 0)
    }
}

/// The row in Film Settings: count and size, as the mockup has it.
struct MediaRow: View {
    @EnvironmentObject private var session: Session
    @State private var summary = ""

    var body: some View {
        NavigationLink {
            MediaLibraryView().environmentObject(session)
        } label: {
            LabeledContent("Media") { Text(summary).monospacedDigit() }
        }
        .accessibilityIdentifier("settings.media")
        .task {
            // Off the main thread: sizing every file walks the folder.
            let s = session
            let shelf = await Task.detached { s.mediaShelf() }.value
            if let shelf { summary = "\(shelf.count) \u{b7} \(MediaShelf.size(shelf.bytes))" }
        }
    }
}

struct MediaLibraryView: View {
    @EnvironmentObject private var session: Session
    @State private var shelf: MediaShelf?
    @State private var filter: Filter = .all
    @State private var asking: Ask?
    @State private var said: String?

    enum Filter: Hashable { case all, used, unused, deleted }

    enum Ask: Identifiable {
        case one(MediaShelf.Item)
        case unused
        var id: String {
            switch self {
            case .one(let item): return item.media
            case .unused: return "unused"
            }
        }
    }

    private var shown: [MediaShelf.Item] {
        let all = shelf?.items ?? []
        switch filter {
        case .all, .deleted: return all
        case .used: return all.filter(\.used)
        case .unused: return all.filter { !$0.used }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $filter) {
                    Text("All").tag(Filter.all)
                    Text("In Use").tag(Filter.used)
                    Text("Not Used \(shelf?.unused ?? 0)").tag(Filter.unused)
                    Text("Deleted").tag(Filter.deleted)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("media.filter")
            }

            if filter != .deleted, let shelf, shelf.unused > 0 {
                Section {
                    Button(role: .destructive) { asking = .unused } label: {
                        HStack {
                            Text("Delete Unused")
                            Spacer()
                            Text("\(shelf.unused) \u{b7} \(MediaShelf.size(shelf.unusedBytes))")
                                .monospacedDigit()
                        }
                    }
                    .accessibilityIdentifier("media.deleteunused")
                }
            }

            if filter == .deleted {
                Section {
                    ForEach(shelf?.gone ?? []) { g in
                        HStack {
                            Text(g.filename).lineLimit(1).truncationMode(.middle)
                                .textSelection(.enabled)
                            Spacer(minLength: 10)
                            Text("\(MediaShelf.size(g.bytes)) \u{b7} \(MediaShelf.day(g.on))")
                                .font(.footnote).monospacedDigit().foregroundStyle(Style.ink3)
                        }
                    }
                    if (shelf?.gone ?? []).isEmpty {
                        Text("Nothing deleted").foregroundStyle(.secondary)
                    }
                }
            } else {
                Section {
                    ForEach(shown) { item in
                        row(item)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { asking = .one(item) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) { asking = .one(item) } label: {
                                    Label("Delete…", systemImage: "trash")
                                }
                            }
                    }
                    if shelf != nil && shown.isEmpty {
                        Text(filter == .unused ? "Nothing unused" : "No media yet").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(shelf.map { "Media \u{b7} \(MediaShelf.size($0.bytes))" } ?? "Media")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if let said {
                Text(said).font(.footnote.weight(.medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .task { read() }
        .onAppear {
            // A checking run's filter: `--mediashow unused|used|deleted`.
            let args = CommandLine.arguments
            if let at = args.firstIndex(of: "--mediashow"), at + 1 < args.count {
                switch args[at + 1] {
                case "used": filter = .used
                case "unused": filter = .unused
                case "deleted": filter = .deleted
                default: break
                }
            }
        }
        .confirmationDialog(title, isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
                            titleVisibility: .visible) {
            Button(button, role: .destructive) { delete() }
            Button("Cancel", role: .cancel) { asking = nil }
        } message: {
            Text(message)
        }
    }

    private func row(_ item: MediaShelf.Item) -> some View {
        HStack(spacing: 12) {
            FrameThumbnail(frame: item.frame, side: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename).lineLimit(1).truncationMode(.middle)
                Text(item.used ? item.uses.map(\.label).joined(separator: " \u{b7} ") : "Not Used")
                    .font(.footnote).lineLimit(1)
                    .foregroundStyle(item.used ? Style.ink2 : Color.orange)
            }
            Spacer(minLength: 8)
            Text(MediaShelf.size(item.bytes)).font(.footnote).monospacedDigit()
                .foregroundStyle(Style.ink3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("media.row")
    }

    // ---- deleting -------------------------------------------------------------

    private var title: String {
        switch asking {
        case .one(let item): return "Delete \u{201c}\(item.filename)\u{201d}?"
        case .unused: return "Delete \(shelf?.unused ?? 0) Unused?"
        case nil: return ""
        }
    }

    private var button: String {
        switch asking {
        case .one(let item): return "Delete \u{b7} \(MediaShelf.size(item.bytes))"
        case .unused: return "Delete Unused \u{b7} \(MediaShelf.size(shelf?.unusedBytes ?? 0))"
        case nil: return "Delete"
        }
    }

    /// What it costs, and nothing else.
    private var message: String {
        var said: [String] = []
        switch asking {
        case .one(let item):
            if !item.uses.isEmpty {
                let names = item.uses.prefix(4).map(\.label).joined(separator: ", ")
                let more = item.uses.count > 4 ? " and \(item.uses.count - 4) more" : ""
                said.append("Used on \(names)\(more).")
            }
            if item.versions > 0 {
                said.append(item.versions == 1
                    ? "A saved version shows it."
                    : "\(item.versions) saved versions show it.")
            }
        case .unused:
            let shown = (shelf?.items ?? []).filter { !$0.used && $0.versions > 0 }.count
                        if shown > 0 { said.append("Saved versions show \(shown) of them.") }
        case nil:
            break
        }
        said.append("This can\u{2019}t be undone.")
        return said.joined(separator: "\n\n")
    }

    private func delete() {
        let what: [String]?
        switch asking {
        case .one(let item): what = [item.media]
        case .unused: what = nil
        case nil: return
        }
        asking = nil
        if let done = session.deleteMedia(what) {
            withAnimation { said = "Deleted \(done.deleted) \u{b7} \(MediaShelf.size(done.freed))" }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { said = nil } }
        }
        read()
    }

    private func read() {
        shelf = session.mediaShelf()
    }
}

extension Session {
    /// A picture already in the project, used again on another owner (the
    /// Mac's From Project): one file, a second use.
    func reuse(media: String, on owner: String) {
        guard let engine else { return }
        _ = engine.raw("use", owner, media)
        refresh()
    }
}

/// **From Project** (the Mac's): every picture and clip the project already
/// has, to put on a place or a board without bringing it in again.
struct FromProjectPicker: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    let owner: String

    @State private var items: [MediaShelf.Item] = []
    @State private var query = ""
    @State private var chosen: Set<String> = []

    private var shown: [MediaShelf.Item] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let pictures = items.filter { MediaKind(said: $0.kind, ext: ($0.filename as NSString).pathExtension) != .other }
        return q.isEmpty ? pictures : pictures.filter { $0.filename.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], spacing: 6) {
                    ForEach(shown) { item in
                        Button {
                            if chosen.contains(item.media) { chosen.remove(item.media) } else { chosen.insert(item.media) }
                        } label: {
                            FrameThumbnail(frame: item.frame, side: 96)
                                .frame(width: 96, height: 96)
                                .clipped()
                                .overlay(alignment: .topTrailing) {
                                    if chosen.contains(item.media) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 20)).foregroundStyle(.white, Color.accentColor)
                                            .padding(4)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }
            .searchable(text: $query, prompt: "Search")
            .navigationTitle("From Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        for m in chosen { session.reuse(media: m, on: owner) }
                        dismiss()
                    }
                    .disabled(chosen.isEmpty)
                }
            }
        }
        .task { items = session.mediaShelf()?.items ?? [] }
    }
}
