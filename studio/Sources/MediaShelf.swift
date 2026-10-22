import AppKit
import SwiftUI

/// **Media: every picture and clip in the film.** His ask, 2026-10-10
/// (Notion SL-1687, mockup `design/44-media.html`): see where each is used
/// and which are not, how big each is, delete for real, and one button for
/// everything nothing uses. Film menu › Media….
///
/// The engine decides (`engine::shelf`); this draws it. A delete takes every
/// use and the files, and leaves the name behind, so a saved version that
/// showed the picture comes back with a gap that says what was there.
final class MediaShelfWindow: NSObject, NSWindowDelegate {
    static let shared = MediaShelfWindow()

    private var window: NSWindow?
    private weak var state: ShellState?
    let reading = MediaShelfReading()

    func show(state: ShellState) {
        self.state = state
        reading.read(state)
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
                styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 720, height: 420)
            w.delegate = self
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.identifier = NSUserInterfaceItemIdentifier("media")
            w.contentView = NSHostingView(rootView: MediaShelfView(state: state, reading: reading))
            if Launch.checking || !w.setFrameUsingName("mediaWindow") { w.center() }
            if !Launch.checking { w.setFrameAutosaveName("mediaWindow") }
            window = w
            ride(w)
        }
        window?.makeKeyAndOrderFront(nil)
    }

    /// Above the film's window, as Versions rides — a checking run opens this
    /// before the film's window is up, so it waits a beat for it.
    private func ride(_ w: NSWindow, tries: Int = 10) {
        guard let main = NSApp.windows.first(where: {
            $0 != w && $0.isVisible && $0.identifier?.rawValue.hasPrefix("main") == true
        }) else {
            if tries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak w] in
                    guard let w else { return }
                    self?.ride(w, tries: tries - 1)
                }
            }
            return
        }
        main.addChildWindow(w, ordered: .above)
        if Launch.checking {
            let m = main.frame
            w.setFrameOrigin(NSPoint(x: m.midX - w.frame.width / 2, y: m.midY - w.frame.height / 2))
        }
    }

    /// Read the list again — after a delete, or the film changing under it.
    func refresh() {
        guard let state, window != nil else { return }
        reading.read(state)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

final class MediaShelfReading: ObservableObject {
    @Published var shelf: Engine.Shelf?

    func read(_ state: ShellState) {
        shelf = state.engine?.shelf()
        if Launch.checking, let shelf {
            FileHandle.standardError.write(Data((
                "media: \(shelf.count) items, \(shelf.bytes) bytes, \(shelf.unused) unused "
                + "(\(shelf.unusedBytes) bytes), \(shelf.gone.count) deleted\n").utf8))
        }
    }
}

enum MediaFilter: Hashable { case all, used, unused, deleted }

struct MediaShelfView: View {
    @ObservedObject var state: ShellState
    @ObservedObject var reading: MediaShelfReading
    @State private var filter: MediaFilter = .all
    @State private var picked: Set<String> = []
    @State private var focus: String?
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    private var shelf: Engine.Shelf? { reading.shelf }

    private var shown: [Engine.Shelf.Item] {
        let all = shelf?.items ?? []
        switch filter {
        case .all, .deleted: return all
        case .used: return all.filter(\.used)
        case .unused: return all.filter { !$0.used }
        }
    }

    private var focused: Engine.Shelf.Item? {
        guard let focus else { return nil }
        return shelf?.items.first { $0.media == focus }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Brand.rule(dark))
            if filter == .deleted {
                deletedList
            } else if shown.isEmpty {
                EmptyState(title: filter == .unused ? "Nothing unused" : "No media yet")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    grid
                    if let item = focused {
                        Divider().overlay(Brand.rule(dark))
                        side(item)
                    }
                }
            }
        }
        .background(Brand.surface(dark))
        .frame(minWidth: 720, minHeight: 420)
        .onDeleteCommand { if !picked.isEmpty { askToDelete(Array(picked)) } }
        .onAppear(perform: checking)
    }

    /// `--mediashow all|used|unused|deleted`: a checking run's filter, with
    /// the first item picked so the side panel shows.
    private func checking() {
        let args = CommandLine.arguments
        guard Launch.checking, let at = args.firstIndex(of: "--mediashow"), at + 1 < args.count else { return }
        switch args[at + 1] {
        case "used": filter = .used
        case "unused": filter = .unused
        case "deleted": filter = .deleted
        default: filter = .all
        }
        if let first = shown.first { picked = [first.media]; focus = first.media }
    }

    // ---- top ----------------------------------------------------------------

    private var header: some View {
        HStack(spacing: 12) {
            Text("Media").sans(Brand.Size.large, weight: .semibold)
                .foregroundStyle(Brand.ink(dark))
            if let shelf {
                Text("\(shelf.count) \u{b7} \(Self.size(shelf.bytes))").sans(13).monospacedDigit()
                    .foregroundStyle(Brand.ink3(dark))
            }
            Spacer(minLength: 12)
            Segmented(selection: $filter, items: [
                .init(value: .all, title: "All"),
                .init(value: .used, title: "In Use"),
                .init(value: .unused, title: "Not Used \(shelf?.unused ?? 0)"),
                .init(value: .deleted, title: "Deleted \(shelf?.gone.count ?? 0)"),
            ], quiet: true)
            .fixedSize()
            Spacer(minLength: 12)
            if picked.count > 1 {
                Button("Delete \(picked.count)…") { askToDelete(Array(picked)) }
                    .buttonStyle(.capsule)
            }
            Button((shelf?.unused ?? 0) == 0 ? "Delete Unused"
                   : "Delete Unused \u{b7} \(shelf?.unused ?? 0) \u{b7} \(Self.size(shelf?.unusedBytes ?? 0))") {
                askToDeleteUnused()
            }
            .buttonStyle(.primary)
            .disabled((shelf?.unused ?? 0) == 0)
        }
        .padding(.leading, 84)
        .padding(.trailing, 18)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    // ---- the grid -------------------------------------------------------------

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 12, alignment: .top)],
                      alignment: .leading, spacing: 12) {
                ForEach(shown) { item in tile(item) }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tile(_ item: Engine.Shelf.Item) -> some View {
        let on = picked.contains(item.media)
        return VStack(alignment: .leading, spacing: 0) {
            picture(item)
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipped()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(item.filename).sans(13).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(Brand.ink(dark))
                    Spacer(minLength: 0)
                    Text(Self.size(item.bytes)).sans(11).monospacedDigit()
                        .foregroundStyle(Brand.ink3(dark))
                        .fixedSize()
                }
                Text(item.used ? item.uses.map(\.label).joined(separator: " \u{b7} ") : "Not Used")
                    .sans(11).lineLimit(1)
                    .foregroundStyle(item.used ? Brand.ink2(dark) : Brand.warn(dark))
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
        }
        // Square: no picture is rounded, anywhere (his rule, 10-07).
        .background(Brand.surface2(dark))
        .overlay {
            Rectangle()
                .strokeBorder(on ? Brand.accent(dark) : Brand.rule(dark), lineWidth: on ? 2 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            let more = NSApp.currentEvent?.modifierFlags.contains(.command) == true
                || NSApp.currentEvent?.modifierFlags.contains(.shift) == true
            if more {
                if on { picked.remove(item.media) } else { picked.insert(item.media) }
            } else {
                picked = [item.media]
            }
            focus = item.media
        }
        .contextMenu {
            Button("Delete…") { askToDelete(picked.contains(item.media) ? Array(picked) : [item.media]) }
        }
        .help(item.filename)
    }

    @ViewBuilder
    private func picture(_ item: Engine.Shelf.Item) -> some View {
        Color.clear.overlay {
            if Frames.something(item.hash, item.filename, state.engine, kind: item.kind) {
                Frames.view(item.hash, item.filename, engine: state.engine)
            } else {
                Frames.gap(item.hash, dark: dark, small: true)
            }
        }
        .background(Brand.panel(dark))
    }

    // ---- the side -------------------------------------------------------------

    private func side(_ item: Engine.Shelf.Item) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                picture(item)
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipped()
                    .padding(.bottom, 14)
                Text(item.filename).sans(13, weight: .semibold).lineLimit(2).truncationMode(.middle)
                    .foregroundStyle(Brand.ink(dark))
                Text(facts(item)).sans(11).foregroundStyle(Brand.ink3(dark))
                    .padding(.top, 2)

                label("Used On")
                if item.uses.isEmpty {
                    Text("Not Used").sans(13).foregroundStyle(Brand.warn(dark))
                } else {
                    ForEach(item.uses) { use in
                        Button { show(use) } label: {
                            HStack {
                                Text(use.label).sans(13).lineLimit(1).foregroundStyle(Brand.ink(dark))
                                Spacer(minLength: 8)
                                Text(use.detail).sans(11).foregroundStyle(Brand.ink3(dark)).fixedSize()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Brand.surface2(dark)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Show \(use.label)")
                        .padding(.bottom, 5)
                    }
                }

                if item.versions > 0 {
                    label("Saved Versions")
                    Text(item.versions == 1 ? "1 version" : "\(item.versions) versions")
                        .sans(13).foregroundStyle(Brand.ink2(dark))
                }

                HStack {
                    Spacer(minLength: 0)
                    Button("Delete…") { askToDelete([item.media]) }
                        .buttonStyle(.capsule)
                }
                .padding(.top, 18)
            }
            .padding(18)
        }
        .frame(width: 290)
        .background(Brand.panel(dark).opacity(0.4))
    }

    private func label(_ s: String) -> some View {
        Text(s.uppercased()).sans(10, weight: .semibold).tracking(0.6)
            .foregroundStyle(Brand.ink3(dark))
            .padding(.top, 16).padding(.bottom, 6)
    }

    private func facts(_ item: Engine.Shelf.Item) -> String {
        var parts: [String] = []
        switch item.kind {
        case "video", "gif": parts.append("Clip")
        case "scan", "scan_shape": parts.append("Scan")
        case "image": parts.append("Picture")
        default: parts.append("File")
        }
        if item.seconds > 0 {
            let s = Int(item.seconds.rounded())
            parts.append(String(format: "%d:%02d", s / 60, s % 60))
        }
        if item.width > 0 && item.height > 0 { parts.append("\(item.width) \u{d7} \(item.height)") }
        parts.append(Self.size(item.bytes))
        return parts.joined(separator: " \u{b7} ")
    }

    // ---- deleted --------------------------------------------------------------

    private var deletedList: some View {
        Group {
            if let gone = shelf?.gone, !gone.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(gone) { g in
                            HStack {
                                Text(g.filename).sans(13).lineLimit(1).truncationMode(.middle)
                                    .foregroundStyle(Brand.ink(dark))
                                    .textSelection(.enabled)
                                Spacer(minLength: 12)
                                Text("\(Self.size(g.bytes)) \u{b7} \(Self.day(g.on))").sans(11).monospacedDigit()
                                    .foregroundStyle(Brand.ink3(dark)).fixedSize()
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Brand.surface2(dark)))
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 640)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyState(title: "Nothing deleted")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // ---- doing ------------------------------------------------------------------

    /// To where it is used: the shot's scene, the location, the board.
    private func show(_ use: Engine.Shelf.Use) {
        switch use.kind {
        case "location":
            state.sideTab = .locations
            state.locationId = use.owner
        case "board":
            state.sideTab = .boards
            state.boardId = use.owner
        default:
            guard !use.scene.isEmpty else { return }
            state.sideTab = use.kind == "diagram" ? .diagram : .scenes
            state.sceneId = use.scene
        }
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }?.makeKeyAndOrderFront(nil)
    }

    private func askToDelete(_ media: [String]) {
        guard let items = shelf?.items.filter({ media.contains($0.media) }), !items.isEmpty else { return }
        let ask = NSAlert()
        ask.alertStyle = .warning
        let bytes = items.reduce(0) { $0 + $1.bytes }
        let places = items.flatMap(\.uses)
        let versions = items.map(\.versions).max() ?? 0
        if items.count == 1, let one = items.first {
            ask.messageText = "Delete \u{201c}\(one.filename)\u{201d}?"
        } else {
            ask.messageText = "Delete \(items.count) Items?"
        }
        // What it costs, and nothing else. The only sentences this window has.
        var said: [String] = []
        if !places.isEmpty {
            let names = places.prefix(6).map(\.label).joined(separator: ", ")
            let more = places.count > 6 ? " and \(places.count - 6) more" : ""
            said.append("Used on \(names)\(more).")
        }
        if versions > 0 {
            said.append(versions == 1
                ? "A saved version shows \(items.count == 1 ? "it" : "some of them")."
                : "\(versions) saved versions show \(items.count == 1 ? "it" : "some of them").")
        }
        said.append("This can\u{2019}t be undone.")
        ask.informativeText = said.joined(separator: "\n\n")
        ask.addButton(withTitle: "Delete \u{b7} \(Self.size(bytes))")
        ask.addButton(withTitle: "Cancel")
        ask.buttons.first?.hasDestructiveAction = true
        guard ask.runModal() == .alertFirstButtonReturn else { return }
        finish(state.engine?.deleteMedia(items.map(\.media)))
    }

    private func askToDeleteUnused() {
        guard let shelf, shelf.unused > 0 else { return }
        let unused = shelf.items.filter { !$0.used }
        let shown = unused.filter { $0.versions > 0 }.count
        let ask = NSAlert()
        ask.alertStyle = .warning
        ask.messageText = "Delete \(shelf.unused) Unused \(shelf.unused == 1 ? "Item" : "Items")?"
        var said = ["Frees \(Self.size(shelf.unusedBytes))."]
        if shown > 0 {
            said.append("Saved versions show \(shown) of them.")
        }
        said.append("This can\u{2019}t be undone.")
        ask.informativeText = said.joined(separator: "\n\n")
        ask.addButton(withTitle: "Delete Unused")
        ask.addButton(withTitle: "Cancel")
        ask.buttons.first?.hasDestructiveAction = true
        guard ask.runModal() == .alertFirstButtonReturn else { return }
        finish(state.engine?.deleteUnusedMedia())
    }

    private func finish(_ done: Engine.MediaDeleted?) {
        guard let done, let engine = state.engine else { return }
        picked = []
        focus = nil
        state.replace(engine.view())
        state.readHollowFrames()
        reading.read(state)
        state.say("Deleted \(done.deleted) \u{b7} \(Self.size(done.freedBytes))")
        FileHandle.standardError.write(Data((
            "media deleted: \(done.deleted), \(done.freedBytes) bytes, \(done.removed.count) files\n").utf8))
    }

    // ---- words ------------------------------------------------------------------

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
