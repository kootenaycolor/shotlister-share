import SwiftUI
import QuickLook
import AVKit

/// **The film's record, native** — his ask, 2026-10-06, after TestFlight
/// build 4: *"There's still a lot missing like camera spec sheet, etc.
/// everything should feel native. Don't want to click a link to the portal."*
///
/// What the portal's record pages show (`recordPage` and `homeBody` in
/// `hub/src/pages.js`), drawn by the phone: the film's front page, the Camera
/// Spec Sheet, People, Documents and the Shoots. The hub works everything out
/// with the portal's own code (`phoneFrontOf`) and hands it down the phone's
/// line (`GET /phone/<film>/front`, kept as `front.json` by `PortalLine`), so
/// these screens only lay it out, and open with no signal.
///
/// A film that shoots more than once has a tab per shoot, as the portal does:
/// the spec sheet, People and Documents switch with it, the next shoot first,
/// and say what changed since the shoot before.
struct PortalFront: Codable {
    var project: String = ""
    var title: String?
    var updated: String?
    var film: Film = Film()
    var shoots: [Shoot] = []
    var views: [Tab] = []
    var pictures: [String] = []

    struct Film: Codable {
        var status: String = ""
        var type: String = ""
        var length: String = ""
        var kind: String = ""
        var credits: [Credit] = []
        var facts: [String] = []
        var logline: String = ""
        var note: String = ""
        var look: String = ""
        var key_image: String = ""
        var cover: String = ""
        var colour: String = ""
        var counts: [String: Int] = [:]
        var next: Next?
        var days: [Day] = []
    }

    struct Credit: Codable, Hashable { var role: String; var people: String }
    struct Next: Codable { var said: String; var away: String }
    struct Day: Codable, Hashable { var label: String; var date: String }

    struct Shoot: Codable, Hashable, Identifiable {
        var slug: String
        var name: String
        var base: String = ""
        var status: String = ""
        /// Wrapped, Next or Upcoming, as the portal's switcher says it.
        var word: String = ""
        var start: String = ""
        var end: String = ""
        var dates: String = ""
        var changes: String = ""
        var lead: Bool = false
        var id: String { slug }
    }

    /// One shoot's tab (`shoot` its slug), or the film's only one (`""`).
    struct Tab: Codable {
        var shoot: String = ""
        /// The shoot before, whose sheet and crew the changes are against.
        var was: String = ""
        var camera: Camera = Camera()
        var crew: [Department] = []
        var documents: [Document] = []
        var pages: [Page] = []
        var days: [Day] = []
    }

    struct Camera: Codable {
        var rows: [Row] = []
        var lenses: Lenses?
        var files: [File] = []
        /// The sheet's notes page, a tree of blocks as any written page.
        var notes: AnyBlocks?

        var isEmpty: Bool { rows.isEmpty && lenses == nil && files.isEmpty && (notes?.blocks.isEmpty ?? true) }
    }

    struct Row: Codable, Hashable {
        var label: String
        var copy: String
        var lines: [Line] = []
        var changed: Bool?
        var was: String?
        /// Camera, Color or Deliverables: the sheet in order of operation (2026-10-15).
        var group: String?
        /// The Aspect Ratio row's frame guide files, each with the ratio it sits under (2026-10-15).
        var guides: [Guide]?
    }
    struct Line: Codable, Hashable { var label: String; var value: String }
    struct Guide: Codable, Hashable {
        var ratio: String = ""
        var name: String = ""
        var camera: String = ""
        var note: String = ""
        var url: String = ""
    }

    struct Lenses: Codable, Hashable {
        var copy: String
        var sets: [LensSet] = []
        var changed: Bool?
        var was: String?
    }
    struct LensSet: Codable, Hashable {
        var label: String = ""
        var series: String = ""
        var focals: [String] = []
        var stop: String = ""
        var notes: String = ""
        var raw: String = ""
        /// Close focus off the lens library ("CF 0.35 m"), when set.
        var cf: String?
    }

    struct File: Codable, Hashable {
        var name: String = ""
        var label: String = ""
        var shown: String = ""
        var file: String = ""
        var url: String = ""
        var bytes: Int = 0
        var ext: String = ""
        var host: String = ""
    }

    struct Department: Codable, Hashable, Identifiable {
        var department: String
        var people: [Person]
        var id: String { department }
    }
    struct Person: Codable, Hashable, Identifiable {
        var name: String
        var role: String = ""
        var company: String = ""
        var email: String = ""
        var phone: String = ""
        var fresh: Bool = false
        var id: String { name }
    }

    struct Document: Codable, Hashable, Identifiable {
        var key: String
        var name: String
        var kind: String
        var file: String = ""
        var url: String = ""
        var bytes: Int = 0
        var ext: String = ""
        var host: String = ""
        var id: String { key }
    }
    struct Page: Codable, Hashable { var slug: String; var name: String }

    /// The tab a shoot asks for, else the lead's, else the only one.
    func view(_ shoot: String?) -> Tab? {
        if let shoot, let one = views.first(where: { $0.shoot == shoot }) { return one }
        let lead = shoots.first(where: \.lead)?.slug ?? ""
        return views.first(where: { $0.shoot == lead }) ?? views.first
    }

    var leadSlug: String? { shoots.first(where: \.lead)?.slug }

    /// A sheet in a few words: its cameras.
    static func glimpse(_ camera: Camera) -> String {
        (camera.rows.first { $0.label == "Camera" }?.lines ?? []).map(\.value).joined(separator: ", ")
    }
}

/// A notes tree, kept as its JSON so the page view reads it as any page.
struct AnyBlocks: Codable {
    let data: Data
    var blocks: [LookBlock] { (try? LookBlock.page(data)) ?? [] }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(JSONValue.self)
        data = (try? JSONEncoder().encode(value)) ?? Data("[]".utf8)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode((try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .array([]))
    }
}

/// Any JSON, so a tree can be carried through `Codable` unchanged.
indirect enum JSONValue: Codable {
    case string(String), number(Double), bool(Bool), null, array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

// MARK: - pieces every record screen shares

/// A date the way the portal writes a shoot day: `Mon 2 Nov`.
func recordDay(_ iso: String) -> String {
    let read = DateFormatter()
    read.locale = Locale(identifier: "en_US_POSIX")
    read.timeZone = TimeZone(identifier: "UTC")
    read.dateFormat = "yyyy-MM-dd"
    guard let date = read.date(from: iso) else { return iso }
    let say = DateFormatter()
    say.locale = Locale(identifier: "en_GB")
    say.timeZone = TimeZone(identifier: "UTC")
    say.dateFormat = "EEE d MMM"
    return say.string(from: date)
}

/// `PDF · 2.1 MB`, or a link's host.
func recordKind(ext: String, bytes: Int, host: String) -> String {
    if !host.isEmpty { return host }
    return [ext.uppercased(), bytes > 0 ? ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) : ""]
        .filter { !$0.isEmpty }.joined(separator: " · ")
}

/// **The shoot switcher** (the portal's `shootTabs`): a glass capsule of the
/// shoots, the next one chosen at first. Many shoots are a menu.
struct ShootSwitch: View {
    let shoots: [PortalFront.Shoot]
    @Binding var chosen: String

    var body: some View {
        if shoots.count <= 3 {
            GlassSegments(options: shoots.map { ($0.slug, $0.name) }, selection: $chosen, compact: shoots.count == 3)
        } else {
            Menu {
                Picker("Shoot", selection: $chosen) {
                    ForEach(shoots) { one in
                        Text([one.name, one.dates, one.word].filter { !$0.isEmpty }.joined(separator: " · ")).tag(one.slug)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(shoots.first { $0.slug == chosen }?.name ?? "Shoot")
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold))
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(.label))
                .padding(.horizontal, 16)
                .frame(height: 40)
                .glassCapsule()
            }
        }
    }
}

/// The line under the switcher: the shoot's date and where it stands.
private struct ShootLine: View {
    let shoot: PortalFront.Shoot?
    var body: some View {
        if let shoot {
            Text([shoot.base, shoot.dates, shoot.word].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 13))
                .foregroundStyle(Style.ink3)
        }
    }
}

/// **What changed since the shoot before**, under a value: `was Signature Primes`.
private struct WasLine: View {
    let changed: Bool?
    let was: String?
    var body: some View {
        if changed == true {
            Text(was.map { $0.isEmpty ? "New" : "was \($0)" } ?? "New")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TagInk.movement.word)
        }
    }
}

/// A word on the clipboard says so, briefly.
private struct CopiedNote: ViewModifier {
    @Binding var said: String?
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let said {
                Text(said)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .glassCapsule(interactive: false)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: said) {
                        try? await Task.sleep(for: .seconds(1.4))
                        withAnimation { self.said = nil }
                    }
            }
        }
    }
}

extension View {
    fileprivate func copiedNote(_ said: Binding<String?>) -> some View { modifier(CopiedNote(said: said)) }
}

/// The shared frame of a record screen: grey page, a column of cards, the
/// shoot switcher when there is more than one shoot, pull to refresh.
private struct RecordPage<Content: View>: View {
    let title: String
    var shoots: [PortalFront.Shoot] = []
    @Binding var chosen: String
    @ViewBuilder var content: () -> Content
    @EnvironmentObject private var portal: PortalLine

    /// Checking doors, on a simulator only: `-RecordBottom 1` scrolls to the
    /// end once the record is drawn.
    private static var checkingBottom: Bool {
        #if targetEnvironment(simulator)
        return UserDefaults.standard.bool(forKey: "RecordBottom")
        #else
        return false
        #endif
    }

    var body: some View {
        ScrollViewReader { reader in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if shoots.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        ShootSwitch(shoots: shoots, chosen: $chosen)
                        ShootLine(shoot: shoots.first { $0.slug == chosen })
                            .padding(.leading, 6)
                    }
                    .padding(.bottom, 6)
                }
                content()
                Color.clear.frame(height: 1).id("record-end")
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 30)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task(id: portal.front?.updated) {
            guard Self.checkingBottom, portal.front != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            reader.scrollTo("record-end", anchor: .bottom)
        }
        }
        .background(Style.page)
        .environment(\.lookFiles, portal.files)
        .refreshable { await portal.refresh() }
        .leadingTitle(title)
        .navigationDestination(for: Place.self) { place in PlaceView(place: place) }
    }
}

/// A section's bold name over its card.
private struct CardHead: View {
    let text: String
    var count: Int? = nil
    init(_ text: String, count: Int? = nil) {
        self.text = text
        self.count = count
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            SectionTitle(text, size: 17)
            if let count {
                Text("\(count)").font(.system(size: 13)).foregroundStyle(Style.ink3)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 20)
        .padding(.bottom, 7)
    }
}

/// Nothing there: one line, and stop.
private struct NoneYet: View {
    let text: String
    let symbol: String
    var body: some View {
        ContentUnavailableView(text, systemImage: symbol)
            .padding(.top, 60)
    }
}

/// The record has not come down yet: waiting, or why not.
private struct NotYet: View {
    @EnvironmentObject private var portal: PortalLine
    var body: some View {
        if portal.fetching {
            ProgressView().padding(.top, 80).frame(maxWidth: .infinity)
        } else {
            ContentUnavailableView(portal.trouble ?? "Not on This iPhone", systemImage: "wifi.slash")
                .padding(.top, 60)
        }
    }
}

/// A chosen shoot that follows the lead until he picks one. A checking run
/// may ask for one (`-RecordShoot shoot-1`, a simulator only).
private func startingShoot(_ front: PortalFront?, _ asked: String?) -> String {
    #if targetEnvironment(simulator)
    if asked == nil, let said = UserDefaults.standard.string(forKey: "RecordShoot"), !said.isEmpty { return said }
    #endif
    return asked ?? front?.leadSlug ?? ""
}

// MARK: - the Camera Spec Sheet

/// **The Camera Spec Sheet** (`recordPage` "camera"): one row per fact in the
/// order somebody prepping a camera reads them, a line per camera where the
/// sheet has several, the lens sets one to a line, the LUTs and other files
/// (each opening in Quick Look, to share to a monitor or a card), then the
/// sheet's own notes page. A tap on a row copies it, as on the portal.
struct CameraSheetView: View {
    var shoot: String?
    @EnvironmentObject private var portal: PortalLine
    @State private var chosen = ""
    @State private var copied: String?

    var body: some View {
        RecordPage(title: "Camera Spec Sheet", shoots: portal.front?.shoots ?? [], chosen: $chosen) {
            if let front = portal.front, let view = front.view(chosen) {
                CameraSheet(camera: view.camera, copied: $copied)
            } else {
                NotYet()
            }
        }
        .copiedNote($copied)
        .onAppear { if chosen.isEmpty { chosen = startingShoot(portal.front, shoot) } }
        .onChange(of: portal.front?.leadSlug) { if chosen.isEmpty { chosen = startingShoot(portal.front, shoot) } }
    }
}

/// The sheet itself, for its own screen and for a shoot's.
struct CameraSheet: View {
    let camera: PortalFront.Camera
    @Binding var copied: String?
    @State private var looking: URL?
    @State private var viewing: LookViewer.Opening?
    @Environment(\.lookFiles) private var files
    @Environment(\.openURL) private var openURL

    var body: some View {
        if camera.isEmpty {
            NoneYet(text: "No spec sheet yet", symbol: "camera")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if !camera.rows.isEmpty || camera.lenses != nil {
                    LibraryCard {
                        ForEach(Array(sheetRows.enumerated()), id: \.offset) { _, row in row }
                    }
                }
                if !camera.files.isEmpty {
                    CardHead("Files")
                    LibraryCard {
                        ForEach(camera.files, id: \.self) { file in
                            Button { Task { await open(file) } } label: { fileRow(file) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if let notes = camera.notes?.blocks, !notes.isEmpty {
                    CardHead("Notes")
                    LookBlocks(blocks: notes, depth: 0) { name in
                        let all = notes.flatMap(\.pictures)
                        viewing = .init(names: all.isEmpty ? [name] : all, at: all.firstIndex(of: name) ?? 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .card(Style.Radius.list)
                }
            }
            .quickLookPreview($looking)
            .fullScreenCover(item: $viewing) { LookViewer(opening: $0).environment(\.lookFiles, files) }
            .task {
                // Checking door, a simulator only: `-RecordOpenFile 1` opens
                // the sheet's first file as a tap would.
                #if targetEnvironment(simulator)
                if UserDefaults.standard.bool(forKey: "RecordOpenFile"), let first = camera.files.first {
                    try? await Task.sleep(for: .seconds(1))
                    await open(first)
                }
                #endif
            }
        }
    }

    /// In order of operation, as the portal orders them (2026-10-15): the
    /// camera, its format and capture resolution, then Lenses, then the rest;
    /// a heading where the sheet moves into Color and Deliverables.
    private var sheetRows: [AnyView] {
        var out: [AnyView] = []
        let rows = camera.rows
        // Lenses after the capture rows (Camera, Shooting Format, Capture Resolution)
        let capture = ["Camera", "Shooting Format", "Capture Resolution"]
        let lensAfter = rows.lastIndex { capture.contains($0.label) } ?? 0
        for (index, row) in rows.enumerated() {
            let group = row.group ?? "Camera"
            if index > 0, (rows[index - 1].group ?? "Camera") != group {
                out.append(AnyView(Text(group).font(.system(size: 13, weight: .semibold)).foregroundStyle(Style.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 2)))
            }
            out.append(AnyView(factRow(row)))
            if let guides = row.guides, !guides.isEmpty { out.append(AnyView(guideRows(guides))) }
            if index == lensAfter, let lenses = camera.lenses { out.append(AnyView(lensRow(lenses))) }
        }
        if camera.rows.isEmpty, let lenses = camera.lenses { out.append(AnyView(lensRow(lenses))) }
        return out
    }

    private func copy(_ label: String, _ value: String) {
        UIPasteboard.general.string = value
        withAnimation(.snappy) { copied = "Copied \(label)" }
    }

    private func factRow(_ row: PortalFront.Row) -> some View {
        Button { copy(row.label, row.copy) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(row.label)
                    .font(.system(size: 13))
                    .foregroundStyle(Style.ink3)
                    .frame(width: 128, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(row.lines, id: \.self) { line in
                        if line.label.isEmpty {
                            Text(line.value).font(.system(size: 15, weight: .semibold))
                        } else {
                            (Text(line.label + "  ").foregroundStyle(Style.ink3).font(.system(size: 13, weight: .semibold))
                             + Text(line.value).font(.system(size: 15, weight: .semibold)))
                        }
                    }
                    WasLine(changed: row.changed, was: row.was)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Color(.label))
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { Button("Copy", systemImage: "doc.on.doc") { copy(row.label, row.copy) } }
    }

    /// The frame guide files under Aspect Ratio, each one a download for the AC.
    private func guideRows(_ guides: [PortalFront.Guide]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(guides, id: \.self) { g in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(.label))
                        let under = [g.ratio, g.camera, g.note].filter { !$0.isEmpty }.joined(separator: " · ")
                        if !under.isEmpty { Text(under).font(.system(size: 13)).foregroundStyle(Style.ink3) }
                    }
                    Spacer(minLength: 6)
                    if let url = URL(string: g.url), !g.url.isEmpty {
                        Link(destination: url) { Label("Download", systemImage: "arrow.down.circle").font(.system(size: 13)) }
                    } else {
                        Text("Uploading").font(.system(size: 13)).foregroundStyle(Style.ink3)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 14 + 128 + 12).padding(.trailing, 14).padding(.bottom, 8)
    }

    private func lensRow(_ lenses: PortalFront.Lenses) -> some View {
        Button { copy("Lenses", lenses.copy) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Lenses")
                    .font(.system(size: 13))
                    .foregroundStyle(Style.ink3)
                    .frame(width: 128, alignment: .leading)
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(lenses.sets, id: \.self) { set in
                        VStack(alignment: .leading, spacing: 2) {
                            if !set.label.isEmpty {
                                Text(set.label)
                                    .font(.system(size: Kit.Size.label, weight: .semibold))
                                    .foregroundStyle(Style.ink3)
                            }
                            Text(set.series.isEmpty ? set.raw : set.series)
                                .font(.system(size: 15, weight: .semibold))
                            let more = [set.focals.joined(separator: ", "), set.stop, set.cf ?? ""].filter { !$0.isEmpty }
                            if !more.isEmpty {
                                Text(more.joined(separator: " · ")).font(.system(size: 13)).foregroundStyle(Style.ink2)
                            }
                            if !set.notes.isEmpty {
                                Text(set.notes).font(.system(size: 13)).foregroundStyle(Style.ink3)
                            }
                        }
                    }
                    WasLine(changed: lenses.changed, was: lenses.was)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Color(.label))
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { Button("Copy", systemImage: "doc.on.doc") { copy("Lenses", lenses.copy) } }
    }

    private func fileRow(_ file: PortalFront.File) -> some View {
        HStack(spacing: 10) {
            LibraryRow.Tile(symbol: file.file.isEmpty ? "link" : "doc")
            VStack(alignment: .leading, spacing: 2) {
                Text(file.label.isEmpty ? file.shown : file.label)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                let under = [file.label.isEmpty ? "" : file.shown, recordKind(ext: file.ext, bytes: file.bytes, host: file.host)]
                    .filter { !$0.isEmpty }.joined(separator: " · ")
                if !under.isEmpty {
                    Text(under).font(.system(size: 13)).foregroundStyle(Style.ink3).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Image(systemName: file.file.isEmpty ? "arrow.up.right" : "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    /// A file we hold opens in Quick Look; a link goes where it goes.
    private func open(_ file: PortalFront.File) async {
        if !file.file.isEmpty, let files, let url = await files.file(named: file.file) {
            looking = url.isFileURL ? Self.named(url, file.name) : nil
        } else if let url = URL(string: file.url), !file.url.isEmpty {
            openURL(url)
        }
    }

    /// A kept file carries its stored name; Quick Look and Share show the
    /// one he gave it, so a copy under that name is made beside it.
    static func named(_ url: URL, _ name: String) -> URL {
        let clean = name.replacingOccurrences(of: "/", with: "-")
        guard !clean.isEmpty, clean != url.lastPathComponent else { return url }
        let folder = FileManager.default.temporaryDirectory.appending(path: "Named").appending(path: url.deletingPathExtension().lastPathComponent)
        let target = folder.appending(path: clean.contains(".") ? clean : clean + "." + url.pathExtension)
        if !FileManager.default.fileExists(atPath: target.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? FileManager.default.linkItem(at: url, to: target)
            if !FileManager.default.fileExists(atPath: target.path) { try? FileManager.default.copyItem(at: url, to: target) }
        }
        return FileManager.default.fileExists(atPath: target.path) ? target : url
    }
}

// MARK: - People

/// **People** (`recordPage` "people"): the crew by department, each with a
/// way to call, text or write to them, a New mark on anybody new since the
/// shoot before. On a film that shoots more than once, the shoot's crew.
struct PeopleView: View {
    var shoot: String?
    @EnvironmentObject private var portal: PortalLine
    @State private var chosen = ""
    @State private var copied: String?

    var body: some View {
        RecordPage(title: "People", shoots: portal.front?.shoots ?? [], chosen: $chosen) {
            if let front = portal.front, let view = front.view(chosen) {
                CrewList(crew: view.crew, copied: $copied)
            } else {
                NotYet()
            }
        }
        .copiedNote($copied)
        .onAppear { if chosen.isEmpty { chosen = startingShoot(portal.front, shoot) } }
        .onChange(of: portal.front?.leadSlug) { if chosen.isEmpty { chosen = startingShoot(portal.front, shoot) } }
    }
}

struct CrewList: View {
    let crew: [PortalFront.Department]
    @Binding var copied: String?

    var body: some View {
        if crew.isEmpty {
            NoneYet(text: "No contacts yet", symbol: "person.2")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(crew) { department in
                    CardHead(department.department)
                    LibraryCard {
                        ForEach(department.people) { person in PersonRow(person: person, copied: $copied) }
                    }
                }
            }
        }
    }
}

/// One person: name, role and company, and round buttons to reach them.
struct PersonRow: View {
    let person: PortalFront.Person
    @Binding var copied: String?
    @Environment(\.openURL) private var openURL

    private var dial: String { person.phone.filter { $0.isNumber || $0 == "+" } }

    var body: some View {
        HStack(spacing: 10) {
            Text(initials)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(.label))
                .frame(width: 34, height: 34)
                .background(Color(.tertiarySystemFill), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(person.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    if person.fresh {
                        Text("New")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(TagInk.size.word)
                            .background(TagInk.size.ground, in: Capsule())
                    }
                }
                let under = [person.role, person.company].filter { !$0.isEmpty }.joined(separator: " · ")
                if !under.isEmpty {
                    Text(under).font(.system(size: 13)).foregroundStyle(Style.ink3).lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            if !dial.isEmpty, let sms = URL(string: "sms:" + dial) {
                Button { openURL(sms) } label: { SoftRoundLabel(symbol: "message") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Message")
            }
            if !dial.isEmpty, let tel = URL(string: "tel:" + dial) {
                Button { openURL(tel) } label: { SoftRoundLabel(symbol: "phone") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Call")
            }
            if !person.email.isEmpty, let mail = URL(string: "mailto:" + person.email) {
                Button { openURL(mail) } label: { SoftRoundLabel(symbol: "envelope") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Email")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .contextMenu {
            if !person.phone.isEmpty {
                Button(person.phone, systemImage: "doc.on.doc") { copy("Phone", person.phone) }
            }
            if !person.email.isEmpty {
                Button(person.email, systemImage: "doc.on.doc") { copy("Email", person.email) }
            }
        }
    }

    private var initials: String {
        let words = person.name.split(separator: " ").prefix(2)
        return words.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    private func copy(_ what: String, _ value: String) {
        UIPasteboard.general.string = value
        withAnimation(.snappy) { copied = "Copied \(what)" }
    }
}

// MARK: - Documents

/// **Documents** (`recordPage` "documents"): what is pinned for the film, or
/// tagged to the shoot. A file opens in the phone's own reader; a link opens
/// the site it is on.
struct DocumentsView: View {
    var shoot: String?
    @EnvironmentObject private var portal: PortalLine
    @State private var chosen = ""

    var body: some View {
        RecordPage(title: "Documents", shoots: portal.front?.shoots ?? [], chosen: $chosen) {
            if let front = portal.front, let view = front.view(chosen) {
                DocumentList(documents: view.documents)
            } else {
                NotYet()
            }
        }
        .onAppear { if chosen.isEmpty { chosen = startingShoot(portal.front, shoot) } }
        .onChange(of: portal.front?.leadSlug) { if chosen.isEmpty { chosen = startingShoot(portal.front, shoot) } }
    }
}

struct DocumentList: View {
    let documents: [PortalFront.Document]
    @EnvironmentObject private var portal: PortalLine
    @Environment(\.openURL) private var openURL

    var body: some View {
        if documents.isEmpty {
            NoneYet(text: "Nothing pinned yet", symbol: "folder")
        } else {
            LibraryCard {
                ForEach(documents) { doc in
                    if doc.kind == "link", let url = URL(string: doc.url) {
                        Button { openURL(url) } label: { row(doc, opens: "arrow.up.right") }
                            .buttonStyle(.plain)
                    } else {
                        NavigationLink(value: Place.page(doc.key)) { row(doc, opens: "chevron.right") }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func row(_ doc: PortalFront.Document, opens: String) -> some View {
        let item = portal.item(doc.key)
        return HStack(spacing: 10) {
            LibraryRow.Tile(symbol: item?.symbol ?? (doc.kind == "link" ? "link" : doc.ext == "pdf" ? "doc.richtext" : "doc"))
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.name).font(.system(size: 15)).foregroundStyle(Color(.label)).lineLimit(2)
                Text(recordKind(ext: doc.ext, bytes: doc.bytes, host: doc.host))
                    .font(.system(size: 13))
                    .foregroundStyle(Style.ink3)
            }
            Spacer(minLength: 6)
            if item?.isPrivate == true {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(light: 0x8A6D00, dark: 0xE0C25A))
                    .accessibilityLabel("Private")
            }
            Image(systemName: opens)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Shoots

/// **Shoots**: each shoot of a film that shoots more than once, as a card:
/// its name, dates, where it stands and what it changes.
struct ShootsView: View {
    @EnvironmentObject private var portal: PortalLine
    @State private var unused = ""

    var body: some View {
        RecordPage(title: "Shoots", chosen: $unused) {
            if let front = portal.front {
                if front.shoots.isEmpty {
                    NoneYet(text: "One shoot", symbol: "calendar")
                } else {
                    VStack(spacing: 10) {
                        ForEach(front.shoots.reversed()) { one in
                            NavigationLink(value: Place.shoot(one.slug)) { ShootCard(shoot: one, view: front.view(one.slug)) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                }
            } else {
                NotYet()
            }
        }
    }
}

private struct ShootCard: View {
    let shoot: PortalFront.Shoot
    let view: PortalFront.Tab?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(shoot.name).font(.system(size: 20, weight: .bold))
                Spacer()
                StatusTag(word: shoot.word)
            }
            Text([shoot.base, shoot.dates].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 13))
                .foregroundStyle(Style.ink3)
            if !shoot.changes.isEmpty {
                Text(shoot.changes).font(.system(size: 15)).foregroundStyle(Style.ink2).lineLimit(3)
            }
            if let view {
                let people = view.crew.reduce(0) { $0 + $1.people.count }
                Text([PortalFront.glimpse(view.camera), people == 1 ? "1 person" : people > 0 ? "\(people) people" : ""]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 13))
                    .foregroundStyle(Style.ink3)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(Style.Radius.group)
        .contentShape(Rectangle())
    }
}

/// Wrapped, Next or Upcoming, in an ink of its own.
private struct StatusTag: View {
    let word: String
    var body: some View {
        if !word.isEmpty {
            let ink: TagInk = word == "Next" ? .size : word == "Wrapped" ? .own : .lens
            Text(word)
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .foregroundStyle(ink.word)
                .background(ink.ground, in: Capsule())
        }
    }
}

/// **One shoot** (the portal's `/shoots/<slug>`): what it changes, its days,
/// and its own spec sheet, People, Documents and pages.
struct ShootView: View {
    let slug: String
    @EnvironmentObject private var portal: PortalLine
    @State private var unused = ""

    var body: some View {
        let shoot = portal.front?.shoots.first { $0.slug == slug }
        RecordPage(title: shoot?.name ?? "Shoot", chosen: $unused) {
            if let front = portal.front, let shoot, let view = front.view(slug) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text([shoot.base, shoot.dates].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 15))
                            .foregroundStyle(Style.ink3)
                        StatusTag(word: shoot.word)
                    }
                    .padding(.horizontal, 6)
                    if !shoot.changes.isEmpty {
                        Text(shoot.changes)
                            .font(.system(size: 15))
                            .foregroundStyle(Color(.label))
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card(Style.Radius.list)
                            .padding(.top, 12)
                    }
                    if !view.days.isEmpty {
                        CardHead("Days", count: view.days.count)
                        LibraryCard {
                            ForEach(view.days, id: \.self) { day in
                                HStack {
                                    Text(day.label).font(.system(size: 15, weight: .semibold))
                                    Spacer()
                                    Text(recordDay(day.date)).font(.system(size: 15)).foregroundStyle(Style.ink3)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                            }
                        }
                    }
                    CardHead("This Shoot")
                    LibraryCard {
                        NavigationLink(value: Place.camera(slug)) {
                            RecordRow(title: "Camera Spec Sheet", symbol: "camera",
                                      said: PortalFront.glimpse(view.camera))
                        }
                        .buttonStyle(.plain)
                        NavigationLink(value: Place.people(slug)) {
                            let n = view.crew.reduce(0) { $0 + $1.people.count }
                            RecordRow(title: "People", symbol: "person.2", said: n > 0 ? "\(n)" : "")
                        }
                        .buttonStyle(.plain)
                        NavigationLink(value: Place.documents(slug)) {
                            RecordRow(title: "Documents", symbol: "folder",
                                      said: view.documents.isEmpty ? "" : "\(view.documents.count)")
                        }
                        .buttonStyle(.plain)
                        ForEach(view.pages, id: \.self) { page in
                            NavigationLink(value: Place.page(page.slug)) {
                                RecordRow(title: page.name, symbol: portal.item(page.slug)?.symbol ?? "doc.text", said: "")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                NotYet()
            }
        }
    }
}

/// A row leading somewhere: its glyph, its name, a count or a glimpse.
struct RecordRow: View {
    let title: String
    let symbol: String
    var said = ""
    var body: some View {
        HStack(spacing: 10) {
            LibraryRow.Tile(symbol: symbol)
            Text(title).font(.system(size: 15)).foregroundStyle(Color(.label)).lineLimit(1)
            Spacer(minLength: 6)
            if !said.isEmpty {
                Text(said).font(.system(size: 13)).foregroundStyle(Style.ink3).lineLimit(1)
            }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - the film's front page

/// **The film's own page** (`homeBody`): its picture, its name and credits,
/// the facts line, the logline, his notes, the next day, what it holds, and
/// the way into the record. Opened from the Library's head; pinnable.
struct FilmFrontView: View {
    @EnvironmentObject private var portal: PortalLine
    @EnvironmentObject private var session: Session
    @State private var unused = ""

    var body: some View {
        RecordPage(title: "Overview", chosen: $unused) {
            if let front = portal.front {
                let film = front.film
                VStack(alignment: .leading, spacing: 0) {
                    if !film.key_image.isEmpty {
                        Color(.tertiarySystemFill)
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .overlay { LookPicture(name: film.key_image, longest: 1400) }
                            .clipped() // A picture is never rounded (his rule, 2026-10-07).
                            .padding(.bottom, 14)
                    }
                    Text(front.title ?? session.entry.name)
                        .font(.system(size: 28, weight: .heavy))
                        .kerning(-0.6)
                        .padding(.horizontal, 4)
                    let credits = film.credits.map { "\($0.role) \($0.people)" } + (film.kind.isEmpty ? [] : [film.kind])
                    if !credits.isEmpty {
                        Text(credits.joined(separator: " · "))
                            .font(.system(size: 15))
                            .foregroundStyle(Style.ink2)
                            .padding(.horizontal, 4)
                            .padding(.top, 4)
                    }
                    if !film.facts.isEmpty {
                        Text(film.facts.joined(separator: " · "))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Style.ink3)
                            .padding(.horizontal, 4)
                            .padding(.top, 6)
                            .textSelection(.enabled)
                    }
                    if !film.logline.isEmpty { said("Logline", film.logline) }
                    if let lead = front.shoots.first(where: \.lead), !lead.changes.isEmpty { said(lead.name, lead.changes) }
                    if !film.note.isEmpty { said("Director's Note", film.note) }
                    if !film.look.isEmpty { said("Visual Language", film.look) }
                    if let next = film.next {
                        CardHead("Next Day")
                        NavigationLink(value: Place.schedule) {
                            HStack {
                                Text(next.said).font(.system(size: 15, weight: .bold))
                                Spacer()
                                Text(next.away).font(.system(size: 13, weight: .semibold)).foregroundStyle(TagInk.size.word)
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
                            }
                            .foregroundStyle(Color(.label))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .card(Style.Radius.list)
                        }
                        .buttonStyle(.plain)
                    }
                    counts(film.counts)
                    CardHead("Record")
                    LibraryCard {
                        if !front.shoots.isEmpty {
                            NavigationLink(value: Place.shoots) {
                                RecordRow(title: "Shoots", symbol: "calendar.badge.clock", said: "\(front.shoots.count)")
                            }
                            .buttonStyle(.plain)
                        }
                        NavigationLink(value: Place.page("camera")) {
                            RecordRow(title: "Camera Spec Sheet", symbol: "camera",
                                      said: front.view(nil).map { PortalFront.glimpse($0.camera) } ?? "")
                        }
                        .buttonStyle(.plain)
                        NavigationLink(value: Place.page("people")) {
                            let n = front.view(nil)?.crew.reduce(0) { $0 + $1.people.count } ?? 0
                            RecordRow(title: "People", symbol: "person.2", said: n > 0 ? "\(n)" : "")
                        }
                        .buttonStyle(.plain)
                        NavigationLink(value: Place.page("documents")) {
                            let n = front.view(nil)?.documents.count ?? 0
                            RecordRow(title: "Documents", symbol: "folder", said: n > 0 ? "\(n)" : "")
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                NotYet()
            }
        }
    }

    private func said(_ head: String, _ words: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Kicker(head)
            Text(words).font(.system(size: 15)).foregroundStyle(Color(.label)).textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(Style.Radius.list)
        .padding(.top, 14)
    }

    /// What the film holds, each opening where it lives.
    @ViewBuilder
    private func counts(_ counts: [String: Int]) -> some View {
        let tiles: [(String, Int, Place)] = [
            ("Scenes", counts["scenes"] ?? 0, .shotList), ("Shots", counts["shots"] ?? 0, .shotList),
            ("Locations", counts["locations"] ?? 0, .locations), ("Days", counts["days"] ?? 0, .schedule),
        ].filter { $0.1 > 0 }
        if !tiles.isEmpty {
            HStack(spacing: 8) {
                ForEach(tiles, id: \.0) { tile in
                    NavigationLink(value: tile.2) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(tile.1)").font(.system(size: 20, weight: .bold)).foregroundStyle(Color(.label))
                            Text(tile.0).font(.system(size: 13, weight: .semibold)).foregroundStyle(Style.ink3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .card(Style.Radius.list)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 14)
        }
    }
}

// MARK: - files, natively

/// **A kept file that is not a PDF or a picture**: a clip plays here; any
/// other file (a spreadsheet, a LUT, a frame-line file) opens in Quick Look,
/// at once and again from its card, with Share in its bar.
struct PortalFileView: View {
    let url: URL
    let name: String
    var symbol = "doc"
    var bytes = 0
    @State private var looking: URL?
    @State private var player: AVPlayer?

    static let clips: Set<String> = ["mp4", "mov", "m4v"]

    var body: some View {
        if Self.clips.contains(url.pathExtension.lowercased()) {
            ZStack {
                Color.black.ignoresSafeArea()
                if let player { VideoPlayer(player: player) }
            }
            .onAppear {
                if player == nil { player = AVPlayer(url: url) }
                player?.play()
            }
            .onDisappear { player?.pause() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) { ShareLink(item: url) }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        LibraryRow.Tile(symbol: symbol)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                            Text(recordKind(ext: url.pathExtension, bytes: bytes, host: ""))
                                .font(.system(size: 13))
                                .foregroundStyle(Style.ink3)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .card(Style.Radius.list)
                    HStack(spacing: 10) {
                        GlassPillButton("Open") { looking = url }
                        ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.leading, 6)
                    }
                }
                .padding(16)
            }
            .background(Style.page)
            .quickLookPreview($looking)
            .task { looking = url }
        }
    }
}
