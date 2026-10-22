import AppKit
import SwiftUI

/// **The Print Frame editor** — the viewer's Print Frame mode
/// (`design/45-print-frame.html`, sections B, C, C2, D, E).
///
/// The board on white paper in the middle with the arrow tools above it; the
/// shot's pictures along the bottom (stills as tiles, each clip as a strip
/// with its playhead, its kept range and a numbered pin per frame); the
/// inspector on the right.
///
/// **The engine is the truth.** Every change is saved as it is made (one undo
/// step each) and the baker picks it up from the view that comes back. The
/// only copy kept here is `draft`, the board mid-scrub, because a scrub
/// cannot wait for a round trip per frame; it is dropped when the hand lifts.
struct PrintFrameEditor: View {
    @ObservedObject var state: ShellState
    /// The shot whose Print Frame this is.
    let shot: String
    /// The picture the viewer was opened on, picked first.
    var opened: String?
    let done: () -> Void

    @ObservedObject private var pictures = PrintFramePictures.shared
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    @State private var draft: PrintFrameSpec?
    @State private var picked: Int? = 0
    /// Pre-picked under `--drawarrows`, as the frames window does, so the
    /// picked arrow's bar can be photographed.
    @State private var pickedArrow: Int? = Launch.drawingArrows ? 0 : nil
    /// Where each clip's playhead is, by its media ref.
    @State private var heads: [String: Double] = [:]
    @State private var dragging: Int?
    /// Every frame taken out: the board says so until one is added. Nothing
    /// stored any more, so the PDF prints as it did before.
    @State private var emptied = false
    /// After Reset to Auto: show what prints (a clip's four moments) rather
    /// than the one-frame start.
    @State private var showingAuto = false
    /// ⌫ on this window, when no text field has the keyboard.
    @StateObject private var keys = PrintFrameKeys()

    private var row: ViewModel.Row? { state.view?.allRows.first { $0.shot == shot } }
    private var film: CGFloat { CGFloat(state.view?.project.ratio ?? 2.39) }
    private var engine: Engine? { state.engine }

    /// What is stored; when nothing is, one frame to start from (or, after
    /// Reset to Auto, what prints). Showing it saves nothing.
    private var saved: PrintFrameSpec? {
        if let pf = row?.printFrame?.spec, !pf.frames.isEmpty { return pf }
        guard let row else { return nil }
        let length: (ViewModel.Still) -> Double? = { pictures.length($0, engine: engine) }
        return showingAuto ? PrintFrameSpec.auto(for: row, clipLength: length)
                           : PrintFrameSpec.start(for: row, clipLength: length)
    }
    private var spec: PrintFrameSpec? {
        if let draft { return draft }
        guard let saved else { return nil }
        if emptied { return PrintFrameSpec(layout: "one", numbers: false, frames: [], arrows: saved.arrows) }
        return saved
    }
    private var isStored: Bool { row?.printFrame != nil }

    var body: some View {
        if let row, let spec {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if spec.frames.isEmpty {
                        EmptyState(title: "No Frames") { EmptyView() }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ArrowTools(arrows: spec.arrows, selected: $pickedArrow) { arrows in
                            var next = spec
                            next.arrows = arrows
                            commit(next)
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                        stage(row, spec)
                    }
                    tray(row, spec)
                }
                .background(Brand.stage(dark))
                inspector(row, spec)
            }
            .background(WindowCatcher { keys.window = $0 })
            .onAppear { keys.start(); checkingDoors() }
            .onDisappear { keys.stop() }
            .onChange(of: keys.deletes) { _, _ in
                guard let row = self.row, let spec = self.spec, let p = picked,
                      spec.frames.indices.contains(p) else { return }
                remove(p, spec, row)
            }
        } else {
            EmptyState(title: "No pictures on this shot") { EmptyView() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // ---- the pictures behind the frames -----------------------------------

    private func still(_ ref: String, _ row: ViewModel.Row) -> ViewModel.Still? {
        row.stills.first { $0.ref == ref }
    }

    private func picture(_ m: PrintFrameSpec.Moment, _ row: ViewModel.Row) -> BoardPicture {
        guard let s = still(m.use, row) else { return BoardPicture(image: nil) }
        if s.movie {
            return BoardPicture(image: pictures.moment(s, at: m.at ?? 0, engine: engine))
        }
        return BoardPicture(image: pictures.still(s, engine: engine),
                            crop: s.hasCrop ? s.framing : nil, marks: s.marks)
    }

    private func ratios(_ spec: PrintFrameSpec, _ row: ViewModel.Row) -> [CGFloat] {
        spec.frames.map { picture($0, row).ratio(film: film) }
    }

    private func board(_ spec: PrintFrameSpec, _ row: ViewModel.Row) -> (kind: String, board: PrintFrameLayout.Board) {
        let rs = ratios(spec, row)
        let kind = PrintFrameLayout.resolved(spec.layout, rs, film: film)
        return (kind, PrintFrameLayout.layout(kind, rs))
    }

    // ---- saving -------------------------------------------------------------

    /// One change, saved: one undo step. The baker takes it from there.
    private func commit(_ next: PrintFrameSpec) {
        draft = nil
        guard let engine else { return }
        guard let fresh = engine.setPrintFrame(shot, next) else {
            state.say("Could not save the Print Frame")
            return
        }
        state.replace(fresh)
    }

    /// The frames changed in number: keep a layout that fits, and the
    /// numbers' default (on for three or more) when the count crosses it.
    private func refit(_ next: inout PrintFrameSpec, was: Int, _ row: ViewModel.Row) {
        let n = next.frames.count
        if was < 3, n >= 3 { next.numbers = true }
        if was >= 3, n < 3 { next.numbers = false }
        next.layout = PrintFrameLayout.resolved(next.layout, ratios(next, row), film: film)
        if !PrintFrameLayout.options(count: n).contains(where: { $0.kind == next.layout }) {
            let rs = ratios(next, row)
            next.layout = PrintFrameLayout.suggest(PrintFrameLayout.options(count: n), rs, film: film)
                ?? PrintFrameLayout.resolved(next.layout, rs, film: film)
        }
    }

    private func add(_ m: PrintFrameSpec.Moment, _ spec: PrintFrameSpec, _ row: ViewModel.Row) {
        var next = spec
        let was = next.frames.count
        guard was < 16 else { return }
        next.frames.append(m)
        if was == 0 {
            next.layout = "one"
            next.numbers = false
        } else {
            refit(&next, was: was, row)
        }
        picked = next.frames.count - 1
        emptied = false
        commit(next)
    }

    /// Takes a frame out. The one after it slides into its place and is
    /// picked, so the same click (or ⌫ again) takes the next.
    private func remove(_ at: Int, _ spec: PrintFrameSpec, _ row: ViewModel.Row) {
        guard spec.frames.indices.contains(at) else { return }
        var next = spec
        let was = next.frames.count
        next.frames.remove(at: at)
        if next.frames.isEmpty {
            // Nothing left to print: back to printing as before, and the
            // board says No Frames until one is added.
            draft = nil
            picked = nil
            pickedArrow = nil
            emptied = true
            if isStored, let engine { state.replace(engine.clearPrintFrame(shot)) }
            return
        }
        refit(&next, was: was, row)
        if let p = picked {
            picked = p > at ? p - 1 : min(p, next.frames.count - 1)
        }
        commit(next)
    }

    // ---- the board -----------------------------------------------------------

    private static let margin: CGFloat = 34

    private func surface(_ room: CGSize, _ board: PrintFrameLayout.Board) -> ArrowSurface {
        let m = Self.margin
        let inner = CGSize(width: max(room.width - 2 * m, 10), height: max(room.height - 2 * m, 10))
        var s = ArrowSurface.fitted(ratio: 1 / max(board.height, 0.05), in: inner)
        s.bounds = s.bounds.offsetBy(dx: m, dy: m)
        s.plate = s.plate.offsetBy(dx: m, dy: m)
        return s
    }

    private func stage(_ row: ViewModel.Row, _ spec: PrintFrameSpec) -> some View {
        let laid = board(spec, row)
        let pics = spec.frames.map { picture($0, row) }
        return GeometryReader { space in
            ArrowCanvas(stored: spec.arrows, selected: $pickedArrow,
                        surface: { surface($0, laid.board) },
                        save: { arrows in
                            var next = spec
                            next.arrows = arrows
                            commit(next)
                        },
                        hint: nil) { here, shown in
                ZStack(alignment: .topLeading) {
                    // The paper the board is printed on.
                    Rectangle().fill(Color.white)
                        .frame(width: here.plate.width + 36, height: here.plate.height + 36)
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
                        .offset(x: here.plate.minX - 18, y: here.plate.minY - 18)
                    PrintFrameBoard(board: laid.board, pictures: pics, numbers: spec.numbers,
                                    arrows: shown, width: here.plate.width, picked: picked)
                        .offset(x: here.plate.minX, y: here.plate.minY)
                }
            }
            // A click on a frame picks it; a drag still draws an arrow.
            .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                let s = surface(space.size, laid.board)
                for (i, cell) in laid.board.cells.enumerated() {
                    let r = cell.rect(width: s.plate.width).offsetBy(dx: s.plate.minX, dy: s.plate.minY)
                    if r.contains(tap.location) { picked = i; return }
                }
            })
        }
    }

    // ---- the shot's pictures, along the bottom --------------------------------

    private func tray(_ row: ViewModel.Row, _ spec: PrintFrameSpec) -> some View {
        let clips = row.stills.filter(\.movie)
        let stills = row.stills.filter { !$0.movie && PrintFrameSpec.usable($0) }
        return Group {
            if clips.count == 1, stills.isEmpty {
                strip(clips[0], spec, row)
                    .padding(.horizontal, 14)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(stills) { s in tile(s, spec, row) }
                        ForEach(clips) { c in strip(c, spec, row).frame(width: 520) }
                    }
                    .padding(.horizontal, 14)
                }
            }
        }
        .frame(height: 96)
        .padding(.bottom, 8)
        .background(Brand.surface2(dark))
        .hairline(.top, Brand.rule(dark))
    }

    /// A still: click to add it, or pick it when it is in already.
    private func tile(_ s: ViewModel.Still, _ spec: PrintFrameSpec, _ row: ViewModel.Row) -> some View {
        let at = spec.frames.firstIndex { $0.use == s.ref }
        let image = pictures.still(s, engine: engine)
        let shape = image.map { $0.size.width / max($0.size.height, 1) } ?? film
        return Button {
            if let at { picked = at } else { add(.init(use: s.ref, at: nil), spec, row) }
        } label: {
            ZStack(alignment: .topLeading) {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Brand.frameEmpty(dark)
                }
                if let at { Pin(number: at + 1, on: picked == at).padding(5) }
            }
            .frame(width: min(64 * shape, 140), height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(at != nil && picked == at ? Brand.accent(dark) : Brand.rule2(dark),
                                  lineWidth: at != nil && picked == at ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .help(at == nil ? "Add Frame" : "Frame \(at! + 1)")
    }

    /// Where a clip's playhead is: on the picked frame when that frame is
    /// from this clip, else where it was left.
    private func head(_ c: ViewModel.Still, _ spec: PrintFrameSpec) -> Double {
        if let p = picked, spec.frames.indices.contains(p), spec.frames[p].use == c.ref,
           let at = spec.frames[p].at { return at }
        return heads[c.ref] ?? c.trimStart ?? 0
    }

    private func strip(_ c: ViewModel.Still, _ spec: PrintFrameSpec, _ row: ViewModel.Row) -> some View {
        let length = pictures.length(c, engine: engine) ?? 0
        let thumbs = pictures.strip(c, engine: engine)
        let from = c.trimStart ?? 0
        let to = c.trimEnd ?? length
        let now = head(c, spec)
        let pins = spec.frames.enumerated().filter { $0.element.use == c.ref }
        return HStack(spacing: 10) {
            GeometryReader { space in
                let w = space.size.width
                let x: (Double) -> CGFloat = { length > 0 ? CGFloat($0 / length) * w : 0 }
                ZStack(alignment: .topLeading) {
                    // The pins ride above the film, one per frame from it.
                    ForEach(pins, id: \.offset) { pin in
                        Pin(number: pin.offset + 1, on: picked == pin.offset)
                            .position(x: x(pin.element.at ?? 0), y: 9)
                            .onTapGesture { picked = pin.offset }
                    }
                    ZStack(alignment: .topLeading) {
                        HStack(spacing: 0) {
                            ForEach(Array(thumbs.enumerated()), id: \.offset) { _, t in
                                Image(nsImage: t).resizable().aspectRatio(contentMode: .fill)
                                    .frame(width: w / CGFloat(max(thumbs.count, 1)), height: 46)
                                    .clipped()
                            }
                        }
                        .frame(width: w, height: 46, alignment: .leading)
                        .background(Color.black)
                        // Outside the kept part: dimmed, and not offered.
                        Color.black.opacity(0.6).frame(width: max(x(from), 0), height: 46)
                        Color.black.opacity(0.6).frame(width: max(w - x(to), 0), height: 46)
                            .offset(x: x(to))
                        Rectangle().strokeBorder(Brand.hex("F3C844"), lineWidth: 2)
                            .frame(width: max(x(to) - x(from), 2), height: 46)
                            .offset(x: x(from))
                        Rectangle().fill(Color.white)
                            .frame(width: 2, height: 54)
                            .shadow(color: .black.opacity(0.5), radius: 1)
                            .offset(x: x(now) - 1, y: -4)
                    }
                    .clipShape(Rectangle())
                    .offset(y: 22)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { g in scrub(c, g.location.x, w, length, spec, ended: false) }
                        .onEnded { g in scrub(c, g.location.x, w, length, spec, ended: true) })
                }
            }
            .frame(height: 72)
            Text("\(Self.clock(now)) / \(Self.clock(length))")
                .sans(Brand.Size.small).monospacedDigit()
                .foregroundStyle(Brand.ink2(dark))
                .fixedSize()
            Button { add(.init(use: c.ref, at: now), spec, row) } label: {
                Text("Add Frame").sans(Brand.Size.body)
                    .foregroundStyle(Brand.ink(dark))
                    .padding(.horizontal, Brand.barPadding)
                    .frame(height: Brand.barHeight)
                    .barPill(dark, on: false)
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help("Add Frame")
        }
        .padding(.top, 8)
    }

    /// The playhead follows the hand inside the kept part; a picked frame
    /// follows the playhead. Saved when the hand lifts.
    private func scrub(_ c: ViewModel.Still, _ x: CGFloat, _ w: CGFloat, _ length: Double,
                       _ spec: PrintFrameSpec, ended: Bool) {
        guard length > 0, w > 0 else { return }
        let from = c.trimStart ?? 0
        let to = min(c.trimEnd ?? length, length - 0.04)
        let t = min(max(Double(x / w) * length, from), max(to, from))
        heads[c.ref] = t
        guard let p = picked, spec.frames.indices.contains(p) else { return }
        var next = draft ?? spec
        next.frames[p] = .init(use: c.ref, at: t)
        if ended {
            commit(next)
        } else {
            draft = next
        }
    }

    static func clock(_ t: Double) -> String {
        let s = max(t, 0)
        return String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }

    static func stamp(_ t: Double) -> String {
        let s = max(t, 0)
        return String(format: "%d:%04.1f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60))
    }

    // ---- the inspector ---------------------------------------------------------

    /// **The Frames list first**, at the top, with nothing above it that can
    /// change size: take a frame out and the next row slides up under the
    /// same ×, so the same click takes the next one. His note, 2026-10-14.
    /// Everything else sits below and moves; the list never does.
    private func inspector(_ row: ViewModel.Row, _ spec: PrintFrameSpec) -> some View {
        let n = spec.frames.count
        return VStack(alignment: .leading, spacing: 12) {
            head("Frames", n == 0 ? nil : n == 1 ? "1 Frame" : "\(n) Frames")
            if n > 0 {
                framesList(row, spec)
                settings(row, spec)
            }
            Spacer(minLength: 0)
            HStack {
                Button("Reset to Auto") {
                    draft = nil
                    picked = 0
                    pickedArrow = nil
                    emptied = false
                    showingAuto = true
                    if isStored, let engine { state.replace(engine.clearPrintFrame(shot)) }
                }
                .buttonStyle(.plain)
                .sans(Brand.Size.body)
                .foregroundStyle(canReset ? Brand.ink2(dark) : Brand.ink4(dark))
                .disabled(!canReset)
                Spacer()
                Button(action: done) {
                    Text("Done").sans(Brand.Size.body, weight: .semibold)
                        .foregroundStyle(Brand.onAccent(dark))
                        .padding(.horizontal, 16)
                        .frame(height: Brand.barHeight)
                        .background(Capsule(style: .continuous).fill(Brand.accent(dark)))
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 272)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Brand.surface(dark))
        .hairline(.leading, Brand.rule(dark))
    }

    /// Reset to Auto means something only when the board is not already
    /// what prints.
    private var canReset: Bool {
        if isStored || emptied { return true }
        guard !showingAuto, let row else { return false }
        let length: (ViewModel.Still) -> Double? = { pictures.length($0, engine: engine) }
        return PrintFrameSpec.start(for: row, clipLength: length)
            != PrintFrameSpec.auto(for: row, clipLength: length)
    }

    /// Layout, numbers and the readings: below the list, never above it.
    private func settings(_ row: ViewModel.Row, _ spec: PrintFrameSpec) -> some View {
        let n = spec.frames.count
        let rs = ratios(spec, row)
        let laid = board(spec, row)
        let offered = PrintFrameLayout.options(count: n)
        let suggested = PrintFrameLayout.suggest(offered, rs, film: film)
        let tall = PrintFrameLayout.tallness(laid.board, film: film)
        let small = Int((PrintFrameLayout.smallest(laid.board) * 100).rounded())
        return VStack(alignment: .leading, spacing: 12) {
            head("Layout", nil)
                .padding(.top, 4)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                      spacing: 12) {
                ForEach(offered, id: \.kind) { option in
                    layoutTile(option.kind, option.name, rs, chosen: option.kind == laid.kind,
                               suggested: option.kind == suggested, spec)
                }
            }
            HStack {
                Text("Numbers").sans(Brand.Size.body).foregroundStyle(Brand.ink(dark))
                Spacer()
                // Drawn here rather than by AppKit: a system switch in a
                // window that is not key draws grey either way, so it could
                // read off while the board showed numbers.
                NumbersSwitch(on: spec.numbers, dark: dark) {
                    var next = spec
                    next.numbers.toggle()
                    commit(next)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                reading("Height", "\(PrintFrameLayout.times(tall)) a Single Frame")
                reading("Smallest Frame", "\(small)% of the Width")
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Brand.rule(dark))
                        Capsule().fill(Brand.accent(dark)).frame(width: g.size.width * CGFloat(small) / 100)
                    }
                }
                .frame(height: 4)
            }
        }
    }

    private func head(_ title: String, _ right: String?) -> some View {
        HStack {
            Text(title).sans(Brand.Size.small, weight: .semibold).foregroundStyle(Brand.ink2(dark))
            Spacer()
            if let right {
                Text(right).sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark))
            }
        }
    }

    private func reading(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark))
            Spacer()
            Text(value).sans(Brand.Size.small, weight: .semibold).foregroundStyle(Brand.ink(dark))
        }
    }

    private func layoutTile(_ kind: String, _ name: String, _ rs: [CGFloat], chosen: Bool,
                            suggested: Bool, _ spec: PrintFrameSpec) -> some View {
        let off = PrintFrameLayout.grids[kind] != nil && PrintFrameLayout.mixed(rs)
        let b = PrintFrameLayout.layout(kind, rs)
        return Button {
            guard !off, kind != spec.layout || !isStored else { return }
            var next = spec
            next.layout = kind
            commit(next)
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Brand.surface2(dark))
                    if !off { Schematic(board: b, dark: dark).padding(9) }
                }
                .frame(height: 64)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(chosen ? Brand.accent(dark) : Brand.rule(dark),
                                      lineWidth: chosen ? 2 : 1)
                }
                .overlay(alignment: .top) {
                    if suggested {
                        Text("Suggested").sans(10, weight: .semibold)
                            .foregroundStyle(Brand.ink(dark))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Brand.cellHover(dark)))
                            .offset(y: -7)
                    }
                }
                Text(name).sans(Brand.Size.small, weight: .semibold)
                    .foregroundStyle(Brand.ink(dark)).lineLimit(1)
                Text(off ? "Shapes Differ" : "\(PrintFrameLayout.times(PrintFrameLayout.tallness(b, film: film))) Tall")
                    .sans(10).foregroundStyle(Brand.ink3(dark))
            }
            .opacity(off ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(off)
        .help(name)
    }

    private func framesList(_ row: ViewModel.Row, _ spec: PrintFrameSpec) -> some View {
        List {
            ForEach(Array(spec.frames.enumerated()), id: \.offset) { i, m in
                let s = still(m.use, row)
                HStack(spacing: 8) {
                    Pin(number: i + 1, on: picked == i)
                    Group {
                        if let image = picture(m, row).image {
                            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        } else {
                            Brand.frameEmpty(dark)
                        }
                    }
                    .frame(width: 54, height: 32)
                    Text(s?.movie == true ? Self.stamp(m.at ?? 0) : "Still")
                        .sans(Brand.Size.small).monospacedDigit()
                        .foregroundStyle(Brand.ink2(dark))
                    Spacer(minLength: 0)
                    Button { remove(i, spec, row) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Brand.ink3(dark))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Remove")
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(picked == i ? Brand.accentTint(dark) : .clear))
                .contentShape(Rectangle())
                .onTapGesture { picked = i }
                .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .onMove { from, to in
                var next = spec
                next.frames.move(fromOffsets: from, toOffset: to)
                picked = nil
                commit(next)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(height: CGFloat(min(spec.frames.count, 6)) * 40 + 4)
    }

    // ---- doors for a checking run ----------------------------------------------

    /// `--pflayout across`, `--pfadd 12.5`, `--pfmark "Push In"`,
    /// `--pfnumbers 0|1`: the editor's own changes, by the calls a click
    /// makes, so a checking run can drive the board and photograph it.
    private func checkingDoors() {
        guard Launch.checking else { return }
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            guard let row, var next = spec else { return }
            var changed = false
            if let t = value("--pfadd").flatMap(Double.init),
               let clip = row.stills.first(where: \.movie) {
                let was = next.frames.count
                next.frames.append(.init(use: clip.ref, at: t))
                refit(&next, was: was, row)
                changed = true
            }
            if let still = value("--pfstill").flatMap(Int.init),
               case let list = row.stills.filter({ !$0.movie }), list.indices.contains(still - 1) {
                let was = next.frames.count
                next.frames.append(.init(use: list[still - 1].ref, at: nil))
                refit(&next, was: was, row)
                changed = true
            }
            if let kind = value("--pflayout") { next.layout = kind; changed = true }
            if let on = value("--pfnumbers") { next.numbers = on == "1"; changed = true }
            if let name = value("--pfmark"), let mark = ViewModel.Arrow.Mark(rawValue: name) {
                next.arrows += mark.arrows(in: CGRect(x: 0, y: 0, width: 1, height: 1)).map(\.held)
                changed = true
            }
            if changed { commit(next) }
            // `--pfremove 2`: picks that frame and presses ⌫, by the key's
            // own path, once per count given (`--pfremove 1 --pfremove 1`).
            let removals = args.indices.filter { args[$0] == "--pfremove" && $0 + 1 < args.count }
                .compactMap { Int(args[$0 + 1]) }
            for (i, n) in removals.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 * Double(i + 1)) {
                    picked = n - 1
                    keys.press()
                }
            }
            // `--pfdone`: presses Done, back to the pictures in the same window.
            if args.contains("--pfdone") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 * Double(removals.count + 1)) { done() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2 + 0.3 * Double(removals.count)) {
                let pf = self.row?.printFrame
                FileHandle.standardError.write(Data((
                    "printframe: layout \(pf?.layout ?? "auto") frames \(pf?.frames.count ?? 0)"
                    + " shown \(self.spec?.frames.count ?? 0)"
                    + " numbers \(pf?.numbers ?? false) arrows \(ViewModel.Arrow.parse(pf?.arrows).count)"
                    + " stale \(pf?.stale ?? true) baked \(pf?.baked.map { "\($0.width)x\($0.height)" } ?? "none")\n"
                ).utf8))
            }
        }
    }
}

/// A frame's number: a small disc, filled in the accent when picked.
private struct Pin: View {
    let number: Int
    var on: Bool = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        Text(String(number))
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(on ? Color.white : Color.black)
            .frame(width: 18, height: 18)
            .background(Circle().fill(on ? Brand.accent(dark) : Color.white))
            .overlay(Circle().strokeBorder(on ? Color.white : Color.black, lineWidth: 1))
    }
}

/// A layout's shape, drawn small: grey cells on the board's own shape.
private struct Schematic: View {
    let board: PrintFrameLayout.Board
    let dark: Bool

    var body: some View {
        GeometryReader { g in
            let w = min(g.size.width, g.size.height / max(board.height, 0.01))
            let h = w * board.height
            ZStack(alignment: .topLeading) {
                ForEach(Array(board.cells.enumerated()), id: \.offset) { _, c in
                    Rectangle().fill(Brand.ink4(dark))
                        .frame(width: c.w * w, height: c.h * w)
                        .offset(x: c.x * w, y: c.y * w)
                }
            }
            .frame(width: w, height: h, alignment: .topLeading)
            .position(x: g.size.width / 2, y: g.size.height / 2)
        }
        .clipped()
    }
}

/// The Numbers switch: the accent track with the knob right when on, grey
/// with the knob left when off, whatever the window is doing.
private struct NumbersSwitch: View {
    let on: Bool
    let dark: Bool
    let flip: () -> Void

    var body: some View {
        Button(action: flip) {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(on ? Brand.accent(dark) : Brand.rule2(dark))
                Circle().fill(Color.white).padding(2)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            }
            .frame(width: 30, height: 17)
            .animation(.easeOut(duration: 0.12), value: on)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help("Numbers")
        .accessibilityLabel("Numbers")
        .accessibilityValue(on ? "On" : "Off")
    }
}

/// **⌫ takes the picked frame out**, on the editor's own window, and only
/// when no text field has the keyboard. A local monitor rather than SwiftUI
/// focus: nothing in the editor holds focus for a key to land on.
final class PrintFrameKeys: ObservableObject {
    /// Counts presses; the editor acts on each change.
    @Published var deletes = 0
    weak var window: NSWindow?
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window,
                  event.keyCode == 51 || event.keyCode == 117,
                  event.modifierFlags.intersection([.command, .option, .control]).isEmpty
            else { return event }
            let responder = window.firstResponder
            if responder is NSTextView || responder is NSTextField { return event }
            self.deletes += 1
            return nil
        }
    }

    /// The checking run's ⌫ (`--pfremove`): the same count a key press bumps.
    func press() { deletes += 1 }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit { stop() }
}

/// Hands back the window a view lands in.
private struct WindowCatcher: NSViewRepresentable {
    let found: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = Catcher()
        view.found = found
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    final class Catcher: NSView {
        var found: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            found?(window)
        }
    }
}
