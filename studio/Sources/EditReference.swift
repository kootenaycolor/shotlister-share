import AVKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Edit Reference, the first mod (2026-10-17)
//
// A clip, a run of stills or an animatic showing how several shots cut
// together. Mockup option A: a gold bracket in the shot list's margin joins
// the shots, with a play button at its top. Drawn only while the project has
// the mod on (`ShellState.modsOn`); the engine keeps the data either way
// (`engine/src/editref.rs`).

/// One row's piece of a bracket.
struct EditPiece {
    let ref: ViewModel.EditRef
    let first: Bool
    let last: Bool
    /// Side by side when two edit references cover one row.
    let lane: Int
    /// Its place down the bracket, top first: when it draws itself in and
    /// when the light running down it passes.
    var step: Int = 0
    /// The row's shot, for the glow of the shot on now.
    var shot: String? = nil
}

/// **The bracket's small touches** (2026-10-17, his ask for "a fun high end
/// feature"): it draws itself in when made, a light runs down it while the
/// pointer is on its button, the dot of the shot on now glows while it plays,
/// and the button settles when the player folds back into it. Watched by the
/// bracket alone, so none of it redraws the table.
final class EditRefLive: ObservableObject {
    static let shared = EditRefLive()
    /// The edit reference drawing itself in, with a fresh token each time.
    @Published var drawing: String?
    /// The edit reference the light is running down, with a fresh token.
    @Published var sweep: String?
    /// `ref:shot` of the shot on now while one plays.
    @Published var now: String?
    /// The edit reference whose player just folded back into its button.
    @Published var landed: String?

    static func token(_ id: String) -> String { id + "#" + UUID().uuidString }
    static func ref(of token: String?) -> String? { token.flatMap { $0.split(separator: "#").first.map(String.init) } }
}

extension ShellState {
    /// The edit references drawn: none unless the mod is on.
    var editRefsShown: [ViewModel.EditRef] {
        modOn(Mods.editReference) ? (view?.editRefs ?? []) : []
    }

    func editRef(_ id: String) -> ViewModel.EditRef? { view?.editRefs?.first { $0.id == id } }

    /// The edit references any of these rows is in.
    func editRefsOf(_ rows: [ViewModel.Row]) -> [ViewModel.EditRef] {
        let shots = Set(rows.map(\.shot))
        return editRefsShown.filter { ref in ref.shots.contains { shots.contains($0.shot) } }
    }

    /// **Each row's piece of each bracket**, and the straight line through
    /// every heading and "Add shot" a run crosses (his note, 2026-10-17:
    /// "i want all the shots that are selected to be connected … right now
    /// the scene heading splits"). The rows are walked in the order the table
    /// draws them, scene after scene (or day after day), so a run of 14A, 14B
    /// and 15A is one bracket over scene 15's heading. The engine answers the
    /// same runs to the portal (`Doc::edit_spans_across`).
    func fileEditPieces() {
        let refs = editRefsShown
        guard !refs.isEmpty else {
            if !editPieces.isEmpty { editPieces = [:] }
            if !editThrough.isEmpty { editThrough = [:] }
            return
        }
        // The table's own order: each block is (the spots drawn above its
        // rows, its rows, the spots drawn under them).
        var blocks: [(head: String, rows: [ViewModel.Row], foot: String?)] = []
        if shootingOrder {
            for day in orderGroups { blocks.append(("head:day:" + (day.key ?? ""), day.rows, nil)) }
        } else {
            var shown = inViewOrder((view?.scenes ?? []).filter { !$0.archived })
            if view?.filter.narrowed == true { shown = shown.filter { !(rowsByScene[$0.id] ?? []).isEmpty } }
            for sc in shown { blocks.append(("head:" + sc.id, rowsByScene[sc.id] ?? [], "foot:" + sc.id)) }
        }
        // One long line of rows, and after which row each spot falls.
        var line: [ViewModel.Row] = []
        var spotsBefore: [Int: [String]] = [:]
        for block in blocks {
            spotsBefore[line.count, default: []].append(block.head)
            line.append(contentsOf: block.rows)
            if let foot = block.foot { spotsBefore[line.count, default: []].append(foot) }
        }
        var pieces: [String: [EditPiece]] = [:]
        var through: [String: [EditPiece]] = [:]
        for ref in refs {
            let joined = Set(ref.shots.map(\.shot))
            var i = 0
            while i < line.count {
                guard joined.contains(line[i].shot) else { i += 1; continue }
                var j = i
                while j + 1 < line.count, joined.contains(line[j + 1].shot) { j += 1 }
                let lane = (i...j).map { pieces[line[$0].id]?.count ?? 0 }.max() ?? 0
                var step = 0
                for k in i...j {
                    // the spots before this row inside the run: headings, "Add shot"
                    if k > i {
                        for spot in spotsBefore[k] ?? [] {
                            through[spot, default: []].append(EditPiece(ref: ref, first: false, last: false, lane: lane, step: step))
                            step += 1
                        }
                    }
                    pieces[line[k].id, default: []].append(EditPiece(ref: ref, first: k == i, last: k == j, lane: lane,
                                                                     step: step, shot: line[k].shot))
                    step += 1
                }
                i = j + 1
            }
        }
        editPieces = pieces
        editThrough = through
    }

    // ---- writing -------------------------------------------------------------

    /// **Make one**: the shots in the order given, then its clip or stills,
    /// then its link. Answers the new edit reference's id.
    @discardableResult
    func addEditRef(name: String, shots: [String], files: [URL], link: String) -> String? {
        guard let engine else { return nil }
        let before = Set((view?.editRefs ?? []).map(\.id))
        guard let made = engine.decode(engine.call("addeditref", name, shots.joined(separator: ","))),
              let fresh = made.editRefs?.first(where: { !before.contains($0.id) }) else {
            say("Couldn't add the edit reference")
            return nil
        }
        replace(made)
        for url in files { EditRefMedia.attach(url: url, owner: fresh.id, state: self) }
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if !link.isEmpty { replace(engine.decode(engine.call("editreflink", fresh.id, link))) }
        if Launch.checking {
            FileHandle.standardError.write(Data("edit ref added: \(fresh.id) \(name) \(shots.count) shots \(files.count) files\n".utf8))
        }
        return fresh.id
    }

    func editRefCall(_ parts: String...) {
        guard let engine else { return }
        replace(engine.decode(engine.call(parts)))
    }
}

/// **A clip or stills onto an edit reference**: the same shrinking, poster
/// and storing a shot's clip gets (`Ingest`), with the edit reference as the
/// owner. No viewfinder reading: these are not a shot's frames.
enum EditRefMedia {
    static func attach(url: URL, owner: String, state: ShellState) {
        guard let engine = state.engine, let arrived = try? Data(contentsOf: url) else {
            state.say("Can't read that file")
            return
        }
        let ext = url.pathExtension.lowercased()
        let named = Ingest.naming(url.lastPathComponent, ext: ext)
        if Ingest.isMovie(ext) {
            let asset = AVURLAsset(url: url)
            let seconds = CMTimeGetSeconds(asset.duration)
            let came = Ingest.sha256Hex(arrived)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let poster: NSImage? = (try? generator.copyCGImage(
                at: CMTime(seconds: min(0.5, max(seconds - 0.1, 0)), preferredTimescale: 600),
                actualTime: nil)).map { NSImage(cgImage: $0, size: .zero) }
            let land = { (small: (data: Data, ext: String)) in
                let size = poster?.size ?? .zero
                engine.call("paste", owner, String(Int(size.width)), String(Int(size.height)),
                            small.ext, small.data.base64EncodedString(), "video",
                            String(format: "%.3f", seconds), Ingest.naming(named, ext: small.ext), came)
                if let poster, let made = Ingest.poster(poster) {
                    engine.poster(hash: Ingest.sha256Hex(small.data), data: made)
                }
                state.replace(engine.view())
            }
            if Launch.checking {
                land(Ingest.shrunk(url, arrived: arrived))
            } else {
                DispatchQueue.global(qos: .userInitiated).async {
                    let small = Ingest.shrunk(url, arrived: arrived)
                    DispatchQueue.main.async { land(small) }
                }
            }
            return
        }
        if ext == "gif", let image = NSImage(data: arrived) {
            state.replace(engine.paste(shot: owner, width: Int(image.size.width), height: Int(image.size.height),
                                       ext: "gif", data: arrived, kind: "gif", named: named))
            return
        }
        guard let image = NSImage(data: arrived), let made = Ingest.compress(image, longest: 1600) else {
            state.say("Can't read that file")
            return
        }
        state.replace(engine.paste(shot: owner, width: made.width, height: made.height, ext: made.ext,
                                   data: made.data, named: Ingest.naming(named, ext: made.ext)))
    }
}

/// `0:12`.
func editClock(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.rounded(.down)))
    return "\(s / 60):" + String(format: "%02d", s % 60)
}

// MARK: - the bracket

/// **One row's piece of the gold bracket**: the line down the margin, a dot
/// at the row, the play button on the first row, a hook under the last.
struct EditBracketPiece: View {
    let piece: EditPiece
    let dark: Bool
    /// The button's place in the window, for the player to bloom out of.
    let play: (CGRect?) -> Void
    @ObservedObject private var live = EditRefLive.shared
    @State private var hovering = false
    @State private var drawn: CGFloat = 1
    @State private var lit = false
    @State private var settle: CGFloat = 1

    private static let mid: CGFloat = 8
    private static let dotY: CGFloat = 17
    private var calm: Bool { EditRefStage.reduced }
    private var isNow: Bool { live.now == piece.ref.id + ":" + (piece.shot ?? "") }

    var body: some View {
        let gold = Mods.gold(dark)
        GeometryReader { geo in
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                let path = Path { p in
                    p.move(to: CGPoint(x: Self.mid, y: piece.first ? Self.dotY : 0))
                    if piece.last {
                        p.addLine(to: CGPoint(x: Self.mid, y: h - 9))
                        p.addQuadCurve(to: CGPoint(x: Self.mid + 6, y: h - 4), control: CGPoint(x: Self.mid, y: h - 4))
                    } else {
                        p.addLine(to: CGPoint(x: Self.mid, y: h))
                    }
                }
                path.trim(from: 0, to: drawn)
                    .stroke(gold, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                // the light running down it
                path.trim(from: 0, to: drawn)
                    .stroke(Color.white.opacity(dark ? 0.85 : 0.95), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .shadow(color: gold, radius: 4)
                    .opacity(lit ? 1 : 0)
                if piece.first {
                    Button {
                        let g = geo.frame(in: .global)
                        play(CGRect(x: g.minX + Self.mid - 8.5, y: g.minY + Self.dotY - 8.5, width: 17, height: 17))
                    } label: {
                        ZStack {
                            Circle().fill(gold)
                            Image(systemName: "play.fill").font(.system(size: 7, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.85)).offset(x: 0.5)
                        }
                        .frame(width: 17, height: 17)
                        .shadow(color: gold.opacity(isNow ? 0.9 : 0), radius: isNow ? 6 : 0)
                        .scaleEffect((hovering ? 1.12 : 1) * settle * (drawn < 1 ? max(0.001, drawn) : 1))
                    }
                    .buttonStyle(.plain)
                    .onHover { on in
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { hovering = on }
                        if on, !calm { live.sweep = EditRefLive.token(piece.ref.id) }
                    }
                    .position(x: Self.mid, y: Self.dotY)
                    .help("\(piece.ref.name) · \(piece.ref.range)" + (piece.ref.length > 0 ? " · \(editClock(piece.ref.length))" : ""))
                    .accessibilityLabel("Play \(piece.ref.name)")
                    .accessibilityIdentifier("editref.play.\(piece.ref.id)")
                } else {
                    Circle().fill(gold).frame(width: 6, height: 6)
                        .shadow(color: gold.opacity(isNow ? 0.95 : 0), radius: isNow ? 5 : 0)
                        .scaleEffect((isNow && !calm ? 1.7 : 1) * (drawn < 1 ? max(0.001, drawn) : 1))
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isNow)
                        .position(x: Self.mid, y: Self.dotY)
                }
            }
        }
        .frame(width: 16)
        .contextMenu {
            Button("Play \(piece.ref.name)") { play(nil) }
        }
        .onChange(of: live.drawing) { _, token in drawIn(token) }
        .onAppear { drawIn(live.drawing) }
        .onChange(of: live.sweep) { _, token in
            guard EditRefLive.ref(of: token) == piece.ref.id, !calm else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(piece.step) * 0.055) {
                withAnimation(.easeOut(duration: 0.12)) { lit = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                    withAnimation(.easeIn(duration: 0.3)) { lit = false }
                }
            }
        }
        .onChange(of: live.landed) { _, token in
            guard piece.first, EditRefLive.ref(of: token) == piece.ref.id, !calm else { return }
            settle = 1.3
            withAnimation(.spring(response: 0.32, dampingFraction: 0.5)) { settle = 1 }
        }
    }

    /// Draw this piece in, after the pieces above it: under half a second
    /// for the whole bracket.
    private func drawIn(_ token: String?) {
        guard EditRefLive.ref(of: token) == piece.ref.id, !calm else { return }
        drawn = 0
        withAnimation(.easeOut(duration: 0.14).delay(Double(piece.step) * 0.07)) { drawn = 1 }
    }
}

/// **A bracket passing a heading or an "Add shot"**: the line alone, at the
/// same place as the rows' line, so a run crossing scenes reads unbroken.
struct EditBracketThrough: View {
    let pieces: [EditPiece]
    let dark: Bool
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(pieces, id: \.ref.id) { piece in
                ThroughLine(piece: piece, dark: dark)
                    .offset(x: Columns.edge - 21 + 7 - CGFloat(piece.lane) * 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private struct ThroughLine: View {
        let piece: EditPiece
        let dark: Bool
        @ObservedObject private var live = EditRefLive.shared
        @State private var drawn: CGFloat = 1
        @State private var lit = false
        var body: some View {
            Rectangle().fill(Mods.gold(dark))
                .overlay {
                    Rectangle().fill(Color.white.opacity(dark ? 0.85 : 0.95))
                        .shadow(color: Mods.gold(dark), radius: 4)
                        .opacity(lit ? 1 : 0)
                }
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .scaleEffect(x: 1, y: drawn, anchor: .top)
                .onChange(of: live.drawing) { _, token in
                    guard EditRefLive.ref(of: token) == piece.ref.id, !EditRefStage.reduced else { return }
                    drawn = 0
                    withAnimation(.easeOut(duration: 0.14).delay(Double(piece.step) * 0.07)) { drawn = 1 }
                }
                .onChange(of: live.sweep) { _, token in
                    guard EditRefLive.ref(of: token) == piece.ref.id, !EditRefStage.reduced else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(piece.step) * 0.055) {
                        withAnimation(.easeOut(duration: 0.12)) { lit = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                            withAnimation(.easeIn(duration: 0.3)) { lit = false }
                        }
                    }
                }
        }
    }
}

// MARK: - adding one

/// **Add Edit Reference…** (2026-10-17 redesign, mockup
/// claude.ai/artifact/FVYQeLqxBLozvzHesfUKwg): the clip's own first frame at
/// its own shape with its name and length, then Name, Link and Shots, each
/// with its label beside it. Add is the app's blue and says Adding while the
/// clip comes in.
struct AddEditReferenceSheet: View {
    @ObservedObject var state: ShellState
    let shots: [String]
    /// Set when the sheet stands in a window of its own for a photograph.
    var close: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    @State private var files: [URL] = []
    @State private var link = ""
    @State private var name = ""
    @State private var dropping = false
    @State private var poster: NSImage?
    @State private var seconds: Double = 0
    @State private var adding = false
    @State private var failed = false

    private var rows: [ViewModel.Row] {
        let all = state.view?.allRows ?? []
        return shots.compactMap { s in all.first { $0.shot == s } }
    }

    /// `Scene 14`, `Scenes 14–15`.
    private var scenesSaid: String {
        let scenes = state.view?.scenes ?? []
        var numbers: [String] = []
        for row in rows {
            if let n = scenes.first(where: { $0.id == row.sceneId })?.number, !numbers.contains(n) { numbers.append(n) }
        }
        guard let a = numbers.first, let b = numbers.last else { return "" }
        return numbers.count == 1 ? "Scene \(a)" : "Scenes \(a)–\(b)"
    }

    private var trimmedLink: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// A link that is not one: no scheme and no dot, or a space in it.
    private var linkWrong: Bool {
        guard !trimmedLink.isEmpty else { return false }
        let full = trimmedLink.contains("://") ? trimmedLink : "https://" + trimmedLink
        guard let url = URL(string: full), let host = url.host, host.contains(".") else { return true }
        return trimmedLink.contains(" ")
    }
    private var ready: Bool { (!files.isEmpty || !trimmedLink.isEmpty) && !linkWrong && !adding }

    var body: some View {
        Sheet(title: "Add Edit Reference", width: .narrow, scrolls: false) {
            VStack(alignment: .leading, spacing: 12) {
                Field("Clip") { clipRow }
                Field("Name") {
                    FieldText(placeholder: "Edit Reference", text: $name)
                        .accessibilityLabel("Name")
                }
                Field("Link") {
                    VStack(alignment: .leading, spacing: 4) {
                        FieldText(placeholder: "Optional", text: $link)
                            .accessibilityLabel("Link")
                        if linkWrong {
                            Text("Not a link").sans(Brand.Size.small).foregroundStyle(Brand.kit(dark, Kit.Ink.red))
                        }
                    }
                }
                Field("Shots") { shotChips }
                if failed {
                    Text("Couldn't add the edit reference").sans(Brand.Size.small)
                        .foregroundStyle(Brand.kit(dark, Kit.Ink.red))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            // A clip dropped anywhere on the sheet lands in the Clip row.
            .contentShape(Rectangle())
            .onDrop(of: [.fileURL], isTargeted: $dropping, perform: dropped)
        } trailing: {
            Button("Cancel") { finish() }.buttonStyle(.capsule)
                .keyboardShortcut(.cancelAction)
            Button(action: add) {
                HStack(spacing: 6) {
                    if adding { ProgressView().controlSize(.small) }
                    Text(adding ? "Adding…" : "Add")
                }
            }
            .buttonStyle(BlueButton())
            .keyboardShortcut(.defaultAction)
            .disabled(!ready)
            .accessibilityIdentifier("editref.add")
        }
        .onAppear {
            if Launch.checking, let at = CommandLine.arguments.firstIndex(of: "--editreffile"), at + 1 < CommandLine.arguments.count {
                take([URL(fileURLWithPath: CommandLine.arguments[at + 1])])
                name = "Anya Approaches Portal"
            }
            if Launch.checking, CommandLine.arguments.contains("--editrefdropping") { dropping = true }
        }
    }

    // ---- the clip --------------------------------------------------------

    /// One field-shaped row: the first frame at its own shape, the file's
    /// name and length, and Choose…; "None" until there is one. A gold ring
    /// while a clip is dragged over the sheet.
    private var clipRow: some View {
        HStack(spacing: 10) {
            if files.isEmpty {
                Text("None").sans(Brand.Size.body).foregroundStyle(Brand.ink3(dark))
            } else {
                ZStack {
                    Color.black
                    if let poster { Image(nsImage: poster).resizable().aspectRatio(contentMode: .fit) }
                }
                .aspectRatio(posterShape, contentMode: .fit)
                .frame(height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(files.count == 1 ? files[0].lastPathComponent : "\(files[0].lastPathComponent) +\(files.count - 1)")
                        .sans(Brand.Size.body, weight: .medium).foregroundStyle(Brand.ink(dark))
                        .lineLimit(1).truncationMode(.middle)
                    Text(clipFacts).sans(Brand.Size.small).monospacedDigit().foregroundStyle(Brand.ink3(dark))
                }
            }
            Spacer(minLength: 0)
            Button("Choose…", action: pick).buttonStyle(.capsule)
                .accessibilityIdentifier("editref.choose")
        }
        .field(dark, minHeight: files.isEmpty ? 28 : 58)
        .overlay {
            RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
                .strokeBorder(Mods.gold(dark), lineWidth: dropping ? 1.5 : 0)
                .shadow(color: Mods.gold(dark).opacity(dropping ? 0.5 : 0), radius: 4)
        }
        .animation(.easeOut(duration: 0.2), value: dropping)
    }

    /// `0:38 · 1920 × 804`.
    private var clipFacts: String {
        var said: [String] = []
        if seconds > 0 { said.append(editClock(seconds)) }
        if let poster, poster.size.width > 0 { said.append("\(Int(poster.size.width)) × \(Int(poster.size.height))") }
        if files.count > 1 { said.append("\(files.count) files") }
        return said.joined(separator: " · ")
    }

    private var posterShape: CGFloat {
        guard let poster, poster.size.width > 0, poster.size.height > 0 else { return 2.39 }
        return max(1.2, min(2.8, poster.size.width / poster.size.height))
    }

    private var shotChips: some View {
        let all = state.view?.allRows ?? []
        return HStack(spacing: 6) {
            ForEach(rows, id: \.id) { row in
                HStack(spacing: 6) {
                    if let frame = all.first(where: { $0.id == row.id })?.frame,
                       let image = Thumbs.shared.image(frame, from: state.engine) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(height: 16)
                    }
                    Text(row.number).sans(Brand.Size.small, weight: .semibold).monospacedDigit()
                        .foregroundStyle(Brand.ink(dark))
                }
                .padding(.leading, 2).padding(.trailing, 7).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(Mods.gold(dark).opacity(dark ? 0.18 : 0.14)))
            }
            if !scenesSaid.isEmpty {
                Text(scenesSaid).sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark))
            }
        }
    }

    // ---- doing -----------------------------------------------------------

    private func dropped(_ providers: [NSItemProvider]) -> Bool {
        var got: [URL] = []
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { got.append(url) } }
                group.leave()
            }
        }
        group.notify(queue: .main) { if !got.isEmpty { take(got) } }
        return true
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Ingest.readableTypes
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { take(panel.urls) }
    }

    /// The files, and the first one's picture and length for the well.
    private func take(_ urls: [URL]) {
        files = urls
        poster = nil
        seconds = 0
        guard let first = urls.first else { return }
        let ext = first.pathExtension.lowercased()
        if Ingest.isMovie(ext) {
            let asset = AVURLAsset(url: first)
            let length = CMTimeGetSeconds(asset.duration)
            seconds = length.isFinite ? length : 0
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let at = CMTime(seconds: min(0.5, max(seconds - 0.1, 0)), preferredTimescale: 600)
            if let cg = try? generator.copyCGImage(at: at, actualTime: nil) {
                poster = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
        } else {
            poster = NSImage(contentsOf: first)
            seconds = urls.count > 1 ? Double(urls.count) * 2 : 0
        }
    }

    private func add() {
        guard ready else { return }
        adding = true
        failed = false
        let link = trimmedLink.isEmpty || trimmedLink.contains("://") ? trimmedLink : "https://" + trimmedLink
        // A beat for "Adding…" to draw before the clip is read in.
        DispatchQueue.main.async {
            let made = state.addEditRef(name: name, shots: shots, files: files, link: link)
            adding = false
            guard let made else { failed = true; return }
            finish()
            // The new bracket draws itself in once the sheet has gone.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                EditRefLive.shared.drawing = EditRefLive.token(made)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { EditRefLive.shared.drawing = nil }
            }
        }
    }

    private func finish() {
        if let close { close() } else { dismiss() }
    }
}

/// **Studio's primary capsule in the app's own blue** — the same shape and
/// tint as Done in Project Settings, never the project's colour (which is
/// how Add came out red on a red film).
struct BlueButton: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let dark = scheme == .dark
        let blue = Brand.kit(dark, Kit.Ink.blue)
        configuration.label
            .sans(Brand.Size.body, weight: .semibold)
            .foregroundStyle(blue)
            .lineLimit(1)
            .padding(.horizontal, Brand.barPadding)
            .frame(minWidth: 56)
            .frame(height: Brand.barHeight)
            .background(Capsule(style: .continuous).fill(blue.opacity(dark ? 0.22 : 0.12)))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .contentShape(Capsule(style: .continuous))
    }
}

// MARK: - the player

/// Plays a clip, or steps through stills. Plays once; Play again starts over.
final class EditRefPlayback: ObservableObject {
    @Published var time: Double = 0
    @Published var playing = false
    let player = AVPlayer()
    private var watcher: Any?
    private var ticker: Timer?
    private(set) var length: Double = 0
    private(set) var stillsOnly = false
    /// While the scrubber is held the clock follows the hand, not the clip.
    var scrubbing = false

    func load(clip: URL?, length: Double) {
        self.length = length
        stillsOnly = clip == nil
        guard let clip else { return }
        player.replaceCurrentItem(with: AVPlayerItem(url: clip))
        player.isMuted = false
        watcher = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1.0 / 30, preferredTimescale: 600), queue: .main) { [weak self] t in
            guard let self, !self.scrubbing else { return }
            self.time = CMTimeGetSeconds(t)
            if self.length > 0, self.time >= self.length - 0.03, self.playing { self.playing = false }
        }
    }

    func toggle() { playing ? pause() : play() }

    func play() {
        if length > 0, time >= length - 0.1 { seek(0) }
        playing = true
        if stillsOnly {
            ticker?.invalidate()
            ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                guard let self, !self.scrubbing else { return }
                self.time = min(self.length, self.time + 1.0 / 30)
                if self.time >= self.length { self.pause() }
            }
        } else {
            player.play()
        }
    }

    func pause() {
        playing = false
        ticker?.invalidate()
        player.pause()
    }

    func seek(_ to: Double) {
        time = max(0, length > 0 ? min(to, length) : to)
        if !stillsOnly {
            player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    func stop() {
        pause()
        if let watcher { player.removeTimeObserver(watcher) }
        watcher = nil
        player.replaceCurrentItem(with: nil)
    }
}

/// The clip, at its own shape, square cornered, no controls of its own.
private struct ClipSurface: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = .none
        v.videoGravity = .resizeAspect
        v.player = player
        return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) { v.player = player }
}

/// **The scrubber**: a gold fill to the playhead and a knob. Drag or click
/// anywhere on it to move; the arrow keys step five seconds.
struct EditScrubber: View {
    @ObservedObject var playback: EditRefPlayback
    let dark: Bool
    var height: CGFloat = 28
    @State private var held = CommandLine.arguments.contains("--editrefheld")

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let p = playback.length > 0 ? CGFloat(playback.time / playback.length) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Brand.ink4(dark).opacity(dark ? 0.7 : 0.45)).frame(height: 4)
                Capsule().fill(Mods.gold(dark)).frame(width: max(4, w * p), height: 4)
                    .shadow(color: Mods.gold(dark).opacity(playback.playing ? 0.6 : 0), radius: 4)
                Circle().fill(Mods.gold(dark).opacity(held ? 0.3 : 0))
                    .frame(width: 24, height: 24)
                    .offset(x: w * p - 12)
                Circle().fill(Color.white)
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                    .frame(width: 14, height: 14)
                    .scaleEffect(held && !EditRefStage.reduced ? 1.3 : 1)
                    .offset(x: w * p - 7)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if !held { withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { held = true } }
                    playback.scrubbing = true
                    playback.seek(Double(max(0, min(1, g.location.x / w))) * playback.length)
                }
                .onEnded { _ in
                    playback.scrubbing = false
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { held = false }
                })
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue("\(editClock(playback.time)) of \(editClock(playback.length))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: playback.seek(playback.time + 5)
            case .decrement: playback.seek(playback.time - 5)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("editref.scrubber")
    }
}

/// **The player** (2026-10-17: "just play the video"): the clip, its name,
/// play and pause, the scrubber with the time, and close. The shot strip,
/// the shot pictures and Cut Here To are gone; timing stays stored, unused.
struct EditReferencePlayer: View {
    @ObservedObject var state: ShellState
    let ref: ViewModel.EditRef
    @ObservedObject var playback: EditRefPlayback
    /// 1 while the gold still covers the picture, 0 once the clip shows.
    var cover: Double
    var close: () -> Void
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }
    @State private var renaming = false
    @State private var newName = ""
    @State private var deleting = false

    static func shape(_ ref: ViewModel.EditRef) -> CGFloat {
        if let c = ref.clip ?? ref.stills.first, let w = c.width, let h = c.height, w > 0, h > 0 { return CGFloat(w) / CGFloat(h) }
        return 16 / 9
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            picture
            controls
        }
        .background(Brand.panel(dark))
        .alert("Rename Edit Reference", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Rename") { state.editRefCall("renameeditref", ref.id, newName) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \(ref.name)?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                state.editRefCall("deleteeditref", ref.id)
                close()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The shots stay.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(ref.name).sans(Brand.Size.body, weight: .semibold).foregroundStyle(Brand.ink(dark)).lineLimit(1)
            Text(ref.range + (ref.length > 0 ? " · \(editClock(ref.length))" : ""))
                .sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark)).lineLimit(1)
            Spacer(minLength: 0)
            Menu {
                if !ref.link.isEmpty, let url = URL(string: ref.link) {
                    Button("Open Link") { NSWorkspace.shared.open(url) }
                }
                Button("Rename…") { newName = ref.name; renaming = true }
                Divider()
                Button("Delete Edit Reference…", role: .destructive) { deleting = true }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13)).foregroundStyle(Brand.ink2(dark))
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("More")
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.ink2(dark))
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close")
            .accessibilityLabel("Close")
            .accessibilityIdentifier("editref.close")
        }
        .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 6)
    }

    /// The clip, or the still at the playhead, at its own shape; the poster
    /// under the clip until it draws.
    private var picture: some View {
        ZStack {
            Color.black
            if let clip = ref.clip {
                if let data = state.engine?.proxy(hash: clip.hash, ext: "png"), let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                }
                ClipSurface(player: playback.player)
            } else if !ref.stills.isEmpty {
                let at = ref.length > 0 ? min(ref.stills.count - 1, Int(playback.time / ref.length * Double(ref.stills.count))) : 0
                let still = ref.stills[max(0, at)]
                if let data = state.engine?.proxy(hash: still.hash, ext: still.ext), let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                }
            } else if !ref.link.isEmpty, let url = URL(string: ref.link) {
                Button("Open Link") { NSWorkspace.shared.open(url) }.buttonStyle(.capsule)
            }
            Mods.gold(dark).opacity(cover)
                .overlay {
                    Image(systemName: "play.fill").font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .opacity(cover)
                }
                .allowsHitTesting(false)
        }
        .aspectRatio(Self.shape(ref), contentMode: .fit)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { playback.toggle() }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { playback.toggle() } label: {
                Image(systemName: playback.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 14)).foregroundStyle(Brand.ink(dark))
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(playback.playing ? "Pause" : "Play")
            .accessibilityLabel(playback.playing ? "Pause" : "Play")
            .accessibilityIdentifier("editref.toggle")
            Text(editClock(playback.time)).sans(Brand.Size.small).monospacedDigit().foregroundStyle(Brand.ink2(dark))
                .frame(minWidth: 32, alignment: .leading)
            EditScrubber(playback: playback, dark: dark)
            Text(editClock(ref.length)).sans(Brand.Size.small).monospacedDigit().foregroundStyle(Brand.ink2(dark))
                .frame(minWidth: 32, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }
}

/// **The play reveal** (mockup "Play, on the Mac"): the bracket's gold button
/// blooms into the player over the window on a spring and settles; the gold
/// lifts off the picture as the clip starts. Closing shrinks it back into the
/// button a little faster. Reduce Motion makes both a plain fade. Space plays
/// and pauses, ← → step five seconds, Escape closes.
struct EditRefStage: View {
    @ObservedObject var state: ShellState
    @StateObject private var playback = EditRefPlayback()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    /// What is on stage, held while it closes after `editRefPlaying` clears.
    @State private var shown: ViewModel.EditRef?
    @State private var from: CGRect?
    @State private var bloom: CGFloat = 0
    @State private var cover: Double = 1
    @State private var keys: Any?

    /// The motion, one place: a spring in, about two thirds of it out.
    static let enter = Animation.spring(response: 0.42, dampingFraction: 0.74)
    static let exitSeconds = 0.26
    static var reduced: Bool {
        Launch.checking ? CommandLine.arguments.contains("--reducemotion") : NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        GeometryReader { geo in
            if let ref = shown {
                let space = geo.frame(in: .global)
                let width = min(760, geo.size.width - 96)
                let height = width / EditReferencePlayer.shape(ref) + 44 + 48
                let start = startPoint(in: space, size: geo.size)
                let scale = max(0.02, 20 / width)
                ZStack {
                    Color.black.opacity(0.42 * Double(bloom))
                        .contentShape(Rectangle())
                        .onTapGesture { closeIt() }
                    EditReferencePlayer(state: state, ref: state.editRef(ref.id) ?? ref, playback: playback,
                                        cover: cover, close: { closeIt() })
                        .frame(width: width)
                        .clipShape(RoundedRectangle(cornerRadius: lerp(height / 2, 12, bloom), style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: lerp(height / 2, 12, bloom), style: .continuous)
                                .strokeBorder(Brand.rule2(scheme == .dark), lineWidth: 1)
                                .opacity(Double(bloom))
                        }
                        // the button's gold over the whole card while it grows
                        .overlay {
                            RoundedRectangle(cornerRadius: lerp(height / 2, 12, bloom), style: .continuous)
                                .fill(Mods.gold(scheme == .dark))
                                .opacity(Self.reduced ? 0 : Double(max(0, 1 - min(1, bloom) * 1.5)))
                                .allowsHitTesting(false)
                        }
                        .shadow(color: .black.opacity(0.4 * Double(bloom)), radius: 30, y: 16)
                        .scaleEffect(lerp(scale, 1, bloom))
                        .offset(x: lerp(start.x - geo.size.width / 2, 0, bloom),
                                y: lerp(start.y - geo.size.height / 2, 0, bloom))
                        .opacity(Self.reduced ? Double(bloom) : 1)
                        .accessibilityAddTraits(.isModal)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .allowsHitTesting(shown != nil)
        // The dot of the shot on now glows on the bracket behind the player.
        .onReceive(playback.$time) { t in
            guard let ref = shown, !ref.shots.isEmpty else { return }
            let at = ref.shots.lastIndex { $0.start <= t + 0.001 } ?? 0
            let now = ref.id + ":" + ref.shots[at].shot
            if EditRefLive.shared.now != now { EditRefLive.shared.now = now }
        }
        .onChange(of: state.editRefPlaying) { _, id in
            if let id, let ref = state.editRef(id) { open(ref) } else if shown != nil { closeIt() }
        }
        .onAppear {
            if let id = state.editRefPlaying, let ref = state.editRef(id) { open(ref) }
        }
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    /// The button's middle in the stage's own space; its middle when unknown.
    private func startPoint(in space: CGRect, size: CGSize) -> CGPoint {
        guard let from else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        return CGPoint(x: from.midX - space.minX, y: from.midY - space.minY)
    }

    private func open(_ ref: ViewModel.EditRef) {
        playback.stop()
        from = state.editRefFrom
        shown = ref
        bloom = 0
        cover = 1
        let clip = ref.clip.flatMap { Clips.file(hash: $0.hash, ext: $0.ext, from: state.engine) }
        playback.load(clip: clip, length: ref.length)
        watchKeys()
        let held = Launch.checking ? CommandLine.arguments.firstIndex(of: "--editrefat").flatMap {
            $0 + 1 < CommandLine.arguments.count ? Double(CommandLine.arguments[$0 + 1]) : nil
        } : nil
        if Launch.checking {
            let player = playback.player
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let item = player.currentItem
                FileHandle.standardError.write(Data("editref player: clip \(clip?.lastPathComponent ?? "none") ready \(item?.status == .readyToPlay) size \(Int(item?.presentationSize.width ?? 0))x\(Int(item?.presentationSize.height ?? 0)) at \(String(format: "%.1f", CMTimeGetSeconds(player.currentTime()))) bloom \(String(format: "%.2f", bloom)) cover \(String(format: "%.2f", cover)) from \(from.map { "\(Int($0.midX)),\(Int($0.midY))" } ?? "middle")\n".utf8))
            }
        }
        // A checking run can stop the bloom part-way to photograph it.
        if let stop = Launch.checking ? CommandLine.arguments.firstIndex(of: "--editrefbloom").flatMap({
            $0 + 1 < CommandLine.arguments.count ? Double(CommandLine.arguments[$0 + 1]) : nil
        }) : nil {
            bloom = CGFloat(stop)
            cover = stop < 0.6 ? 1 : max(0, 1 - (stop - 0.6) / 0.4)
            return
        }
        DispatchQueue.main.async {
            if Self.reduced {
                withAnimation(.easeOut(duration: 0.2)) { bloom = 1; cover = 0 }
            } else {
                withAnimation(Self.enter) { bloom = 1 }
                withAnimation(.easeOut(duration: 0.22).delay(0.26)) { cover = 0 }
            }
            if let held {
                playback.seek(held)
            } else if !Launch.checking || CommandLine.arguments.contains("--editrefplay") {
                DispatchQueue.main.asyncAfter(deadline: .now() + (Self.reduced ? 0.05 : 0.26)) { playback.play() }
            }
        }
    }

    private func closeIt() {
        guard shown != nil else { return }
        playback.pause()
        unwatchKeys()
        let landing = shown?.id
        let done = {
            playback.stop()
            shown = nil
            EditRefLive.shared.now = nil
            if let landing { EditRefLive.shared.landed = EditRefLive.token(landing) }
            if state.editRefPlaying != nil { state.editRefPlaying = nil }
        }
        if Self.reduced {
            withAnimation(.easeIn(duration: 0.16)) { bloom = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: done)
        } else {
            withAnimation(.easeIn(duration: Self.exitSeconds * 0.5)) { cover = 1 }
            withAnimation(.easeIn(duration: Self.exitSeconds)) { bloom = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.exitSeconds, execute: done)
        }
        if state.editRefPlaying != nil { state.editRefPlaying = nil }
    }

    /// The player's keys, ahead of the table's: space, ← →, Escape.
    private func watchKeys() {
        unwatchKeys()
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard shown != nil, let key = NSApp.keyWindow, key.identifier?.rawValue == "main" || key.identifier == nil,
                  !key.isSheet, key.attachedSheet == nil else { return event }
            switch event.keyCode {
            case 49: playback.toggle(); return nil                     // space
            case 123: playback.seek(playback.time - 5); return nil      // ←
            case 124: playback.seek(playback.time + 5); return nil      // →
            case 53: closeIt(); return nil                              // escape
            default: return event
            }
        }
    }

    private func unwatchKeys() {
        if let keys { NSEvent.removeMonitor(keys) }
        keys = nil
    }
}

/// The Add sheet and the player, hung on the main window in one piece so its
/// long chain of sheets stays quick to compile.
struct EditRefDoors: ViewModifier {
    @ObservedObject var state: ShellState
    func body(content: Self.Content) -> some View {
        content
            .overlay { EditRefStage(state: state).ignoresSafeArea() }
            .sheet(isPresented: Binding(get: { state.editRefAdding != nil },
                                        set: { if !$0 { state.editRefAdding = nil } })) {
                AddEditReferenceSheet(state: state, shots: state.editRefAdding ?? [])
            }
    }
}

/// **The Add sheet in a window of its own**, for a checking run to
/// photograph (a sheet cannot be): `--editrefsheet 34C,34D,35A`.
enum EditRefSheetWindow {
    private static var window: NSWindow?
    static func show(numbers: [String], state: ShellState) {
        let rows = state.view?.allRows ?? []
        let shots = numbers.compactMap { n in rows.first { $0.number == n }?.shot }
        let host = NSHostingView(rootView: AddEditReferenceSheet(state: state, shots: shots, close: { window?.close() })
            .fixedSize(horizontal: false, vertical: true))
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
                         styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.identifier = NSUserInterfaceItemIdentifier("addeditref")
        w.contentView = host
        host.layoutSubtreeIfNeeded()
        let fits = host.fittingSize
        if fits.height > 100 { w.setContentSize(NSSize(width: SheetWidth.narrow.rawValue, height: fits.height)) }
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
    }
}
