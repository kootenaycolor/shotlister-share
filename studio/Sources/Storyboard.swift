import SwiftUI
import UniformTypeIdentifiers

/// The Storyboard tab — the scene's shots laid out image-first.
///
/// His words on the Cadrage tour: "the shots laid out, image first, with the
/// description. And in ours, we'll do maybe a little bit more information."
/// So a card carries the frame, the number and title, the description, and
/// the technical line — size · movement · lens — that Cadrage's caption
/// leaves off. The slider sizes the cards; a picture pasted or dropped lands
/// on its shot through the same one door as everywhere else in the app.
struct StoryboardView: View {
    @ObservedObject var state: ShellState
    /// Whether clips play on their own — when they wait, the tile's own
    /// play button says it is a clip, and the corner mark would say it twice.
    @ObservedObject private var clips = ClipPlay.shared
    let scene: ViewModel.Scene
    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }


    private var rows: [ViewModel.Row] {
        state.view?.allRows.filter { $0.sceneId == scene.id } ?? []
    }

    /// The grid's measurements, named once. Two bugs came from these numbers
    /// living in three places and disagreeing: the card's height was computed
    /// from the *slider* while its real width stretched wider (so the frame
    /// box was never the project's ratio), and the arrow keys counted a row
    /// differently than the layout drew it.
    private static let gutter: CGFloat = 16
    private static let margin: CGFloat = 20
    /// Half of the smallest gap two pictures may ever share. The grid's own
    /// spacing is SwiftUI's to honour and it rounds a card into its neighbour
    /// at some widths; this inset is ours and cannot be rounded away.
    private static let breathing: CGFloat = 3

    @ObservedObject private var previews = ClipPreviews.shared

    /// The shot's Print Frame, when the bake is current — what prints.
    static func board(_ row: ViewModel.Row) -> PrintFrameView.Baked? {
        guard let pf = row.printFrame, !pf.stale else { return nil }
        return pf.baked
    }

    /// The shape of one shot's picture area: its own Print Frame's when it
    /// has a baked one (the board is never cropped or squeezed), else the
    /// film's frame.
    private func shape(_ row: ViewModel.Row, film: CGFloat) -> CGFloat {
        BoardPlan.shape(Self.board(row).map { (CGFloat($0.width), CGFloat($0.height)) }, film: film)
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let film = CGFloat(state.view?.project.ratio ?? 2.39)
                let usable = max(1, geo.size.width - Self.margin * 2)
                let slots = BoardPlan.rows(
                    ratios: rows.map { shape($0, film: film) },
                    width: usable, cardWidth: state.cardWidth, film: film,
                    gutter: Self.gutter, chrome: BoardPlan.chrome)
                let ids = slots.map { $0.map { rows[$0.index].id } }
                ScrollView {
                    // **Rows that share a picture height, each card as wide as
                    // its own picture is** — a contact sheet's way. When every
                    // shot has the film's frame this is the old grid exactly:
                    // the same number of equal cards on a row. A Print Frame of
                    // another shape sits in its own shape beside them (see
                    // `BoardPlan`). Lazy by row, so forty cards cost what they
                    // did.
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(slots.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .top, spacing: Self.gutter) {
                                ForEach(line, id: \.index) { slot in
                                    card(rows[slot.index], slot: slot, film: film)
                                        .frame(width: slot.width)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(Self.margin)
                }
                // How the cards fall into rows, so ↑ and ↓ can walk the board —
                // the monitor cannot ask the layout, so the layout tells the
                // state.
                .onAppear { report(ids) }
                .onChange(of: ids) { _, now in report(now) }
            }
            footer
        }
        .background(Brand.surface(dark))
    }

    private func report(_ ids: [[String]]) {
        if state.storyboardRows != ids { state.storyboardRows = ids }
        let widest = ids.map(\.count).max() ?? 1
        if state.storyboardColumns != widest { state.storyboardColumns = widest }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("\(rows.count) shot\(rows.count == 1 ? "" : "s")")
                .sans(11).foregroundStyle(Brand.ink3(dark))
            Spacer()
            // The project's frames when the card brings them (piece E), the
            // ratio menu otherwise — `ProjectFrameMenu` decides.
            ProjectFrameMenu(state: state) {
                Text(FramePicker.face(state.view?.project))
                    .sans(Brand.Size.small).monospacedDigit()
                    .foregroundStyle(Brand.ink2(dark))
            }
            // Outside the label, not inside it: `borderlessButton` draws its
            // own chrome over a label's background and keeps its own chevron,
            // so styling the label got a bare indicator and no pill.
            .fixedSize()
            .padding(.horizontal, Brand.barPadding)
            .frame(height: Brand.barHeight)
            .barPill(dark, on: false)
            .help("Aspect Ratio")
            Spacer().frame(width: 8)
            TileSizeSlider(value: $state.cardWidth, range: 180...420)
        }
        // **A floating bar, not a strip.** Same move as the sidebar: air round
        // it and a capsule under it, so it reads as a control you can reach
        // rather than as the bottom edge of the window.
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background {
            Capsule(style: .continuous)
                .fill(Brand.panel(dark))
                .overlay { Capsule(style: .continuous)
                    .strokeBorder(Brand.glassEdge(dark), lineWidth: 1) }
                .shadow(color: Color.black.opacity(dark ? 0.40 : 0.12), radius: 12, y: 3)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    /// **At most four.** A card at its usual width gives four frames about
    /// sixty points each, which still reads; eight would be slivers, and a
    /// sliver is worse than a number saying there are more. The key frame
    /// leads, because it is the one he chose to stand for the shot.
    private static let atMost = 4

    /// Static, so a checking run can ask the same question the card asks —
    /// the drawing itself is pixels and no battery can see those.
    static func shown(_ row: ViewModel.Row) -> [ViewModel.Still] {
        let ordered = row.stills.sorted { a, b in a.key && !b.key }
        return Array(ordered.prefix(atMost))
    }

    private func shown(_ row: ViewModel.Row) -> [ViewModel.Still] { Self.shown(row) }

    /// The shot's Print Frame, when the bake is current and `still` is the
    /// shot's key picture (a still or a clip): what its tile shows with Clip
    /// Thumbnails on Print Frame.
    private func board(_ still: ViewModel.Still) -> PrintFrameView.Baked? {
        guard let row = rows.first(where: { $0.stills.contains { $0.ref == still.ref } }),
              let pf = row.printFrame, !pf.stale, let baked = pf.baked,
              row.frame?.hash == still.hash else { return nil }
        return baked
    }

    /// One frame in the row: the picture if the file is here, and the honest
    /// grey square with its reason if it is not — Ref 224. A clip says so on
    /// its own corner rather than the card's, so a card of four knows which
    /// one moves.
    @ViewBuilder
    private func one(_ still: ViewModel.Still) -> some View {
        ZStack(alignment: .topLeading) {
            if Frames.something(still.hash, still.filename, state.engine,
                                kind: still.kind) {
                // Fills the frame and crops itself — his call, "Scale Full
                // Frame with Crop". A clip plays and a gif goes round, here as
                // everywhere.
                Frames.view(still.hash, still.filename,
                            engine: state.engine,
                            trimStart: still.trimStart,
                            trimEnd: still.trimEnd,
                            kind: still.kind,
                            framing: still.framing, arrows: still.marks,
                            printFrame: board(still))
            } else {
                // It has a frame; the file behind it is not here. Telling him
                // to paste one when the shot already claims a picture is the
                // wrong sentence.
                Frames.gap(still.hash, dark: dark)
            }
            if still.moving, clips.onTheirOwn || Ingest.isGif(
                ViewModel.Frame(hash: still.hash, filename: still.filename,
                                kind: still.kind).ext, kind: still.kind) {
                Image(systemName: "play.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.onImage)
                    .padding(4)
                    .background(Circle().fill(Color.black.opacity(0.55)))
                    .padding(6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    /// The visible list columns, in the table's order, one chip per value.
    private struct Technical: Identifiable {
        let field: String
        let value: String
        var key: String { field + "\u{1}" + value }
        var id: String { key }
    }

    private func technical(_ row: ViewModel.Row) -> [Technical] {
        var out: [(String, String)] = []
        for column in (state.view?.columns ?? []) where column.visible {
            let name = column.name
            guard Columns.isVocabulary(name) || Columns.custom[name]?.kind == "single"
                    || Columns.custom[name]?.kind == "multi" else { continue }
            let value = Columns.value(row, name)
            for part in value.split(separator: ",") {
                let word = part.trimmingCharacters(in: .whitespaces)
                if !word.isEmpty { out.append((name, word)) }
            }
        }
        return out.map { Technical(field: $0.0, value: $0.1) }
    }

    private func card(_ row: ViewModel.Row, slot: BoardPlan.Slot, film ratio: CGFloat) -> some View {
        let onCursor = state.cursorShot == row.id
        let technical = technical(row)
        // A shot with a baked Print Frame stands in its board, whole and in
        // its own shape; any other shot in the film's frame.
        let baked = Self.board(row)
        let board = baked.flatMap { previews.board($0, engine: state.engine) }
        let guides = baked == nil ? FramePicker.guides(state.view?.project) : []
        // Narrow cards give the words more lines rather than cutting them.
        let narrow = slot.width < 200
        // **A card is an object.** It was a picture with words under it lying
        // straight on the ground; a storyboard reads as a board once each card
        // sits on its own lifted slab, which is the whole of "how the
        // storyboard feels".
        return VStack(alignment: .leading, spacing: 8) {
            // The box IS the project's ratio — `aspectRatio` on a shape that
            // takes the card's real width, never a height computed from the
            // slider. Everything else draws inside it as an overlay, so a
            // filled picture cannot reach past the box it belongs to: one
            // clip, on the box, around the lot.
            ZStack(alignment: .bottomTrailing) {
                Rectangle()
                    .fill(baked != nil ? Color.white
                          : row.stills.isEmpty ? Brand.frameEmpty(dark)
                                               : Color.black.opacity(0.9))
                    .frame(width: slot.pictureWidth, height: slot.pictureHeight)
                    .overlay {
                      if baked != nil {
                        if let board {
                            Image(nsImage: board).resizable().interpolation(.high)
                        }
                      } else {
                        // **Every frame the shot has, side by side** — his
                        // ask, 2026-09-04. It drew the key frame alone and put
                        // a small number in the corner to say there were
                        // others, which is a card telling you about a picture
                        // instead of showing it. The document page has laid a
                        // shot's frames out in a row since it was built; this
                        // is the same row, sharing the box it already had, so
                        // the card keeps its size and the grid arithmetic
                        // underneath is untouched.
                        if shown(row).isEmpty {
                            VStack(spacing: 6) {
                                Image(systemName: "photo")
                                    .font(.system(size: 16, weight: .light))
                                Text("Paste or drop a frame")
                                    .sans(10)
                            }
                            .foregroundStyle(Brand.ink4(dark))
                        } else {
                            // One point of the box's own black between them,
                            // which is all a cut needs to read as a cut.
                            HStack(spacing: 2) {
                                ForEach(shown(row)) { still in
                                    one(still)
                                }
                            }
                        }
                      }
                    }
                    // **The other frames, as guide lines** (piece E), over the
                    // pictures and inside the box, when he has them on.
                    .overlay {
                        if !guides.isEmpty {
                            FrameGuideLines(guides: guides, ratio: ratio)
                        }
                    }
                    // **Square.** The same rule as the table's well: the slab
                    // it sits on is what turns a corner; a photograph is
                    // content, and content keeps its own rectangle. A rounded
                    // frame inside a rounded card was two corners arguing.
                    .clipShape(Rectangle())
                    .background {
                        GeometryReader { geo in
                            let box = geo.frame(in: .global)
                            Color.clear
                                .onAppear { state.cardFrames[row.id] = box }
                                .onChange(of: box) { _, now in state.cardFrames[row.id] = now }
                                .onDisappear { state.cardFrames.removeValue(forKey: row.id) }
                        }
                    }
                // **What is not on the card**, rather than how many it has —
                // the number used to stand in for the frames themselves, and
                // now they are all here but the last few. A shot with four or
                // fewer says nothing at all.
                if baked == nil, row.stills.count > shown(row).count {
                    Text("+\(row.stills.count - shown(row).count)")
                        .mono(10, weight: .semibold)
                        .foregroundStyle(Brand.onImage)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .padding(6)
                }
            }
            .overlay {
                // A hairline, and **never the accent**. The slab already says
                // which card you are on; saying it twice is the double outline
                // he photographed — a blue ring round the picture inside a
                // blue ring round the card.
                Rectangle().strokeBorder(Brand.frameLine(dark), lineWidth: 1)
            }
            // The guaranteed gap, applied around the finished box rather than
            // inside it: padding within the ratio box inflates the box and the
            // filled picture spills exactly that much — the overlap bug again,
            // three points wide. Outside, it is only ever air.
            .padding(.horizontal, Self.breathing)
            // Narrower than the card inside it: centred, not stretched.
            .frame(maxWidth: .infinity)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let colour = row.colour {
                    Circle().fill(Brand.data(colour, dark)).frame(width: 7, height: 7)
                }
                Text(row.number)
                    .sans(Brand.Size.small, weight: .medium).monospacedDigit()
                    .foregroundStyle(Brand.ink2(dark))
                    .strikethrough(row.struck, pattern: .solid, color: Brand.ink4(dark))
                if !row.title.isEmpty {
                    Text(row.title).sans(11, weight: .semibold)
                        .foregroundStyle(Brand.ink(dark))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if !row.description.isEmpty {
                Text(row.description)
                    .sans(11)
                    .foregroundStyle(Brand.ink2(dark))
                    .strikethrough(row.struck, pattern: .solid, color: Brand.ink3(dark))
                    .lineLimit(narrow ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // **A category wears the same clothes in every view** — the
            // table's chips, small, in column order. The typewriter caption
            // line went on 2026-09-14; the Document stays plain type because
            // it is paper.
            if !technical.isEmpty {
                // Keyed on field *and* value: an angle column holding two
                // words is two chips, not one drawn twice.
                WrappingRow(spacing: 4, runSpacing: 4) {
                    ForEach(technical, id: \.key) { one in
                        Chip(text: one.value,
                             colour: Columns.chipColour(one.field, one.value,
                                                        state: state, dark: dark),
                             density: 0.85)
                    }
                }
            }
            // Lens Stack: the filters and modifiers on a quiet line under it.
            if !(row.lensFilters.isEmpty && row.modifierList.isEmpty) {
                LensStackLine(filters: row.lensFilters, modifiers: row.modifierList,
                              density: 0.85)
            }
        }
        // No block of its own: the slab underneath carries the shot's colour
        // now, so the caption is just words on it.
        .padding(.vertical, 6)
        .padding(8)
        .background {
            let shape = RoundedRectangle(cornerRadius: Brand.radiusLarge, style: .continuous)
            // The shot's colour dresses **the slab** — one box, tinted, rather
            // than a plain slab with a coloured block floating inside it.
            shape.fill(row.colour.map {
                Brand.data($0, dark).opacity(dark ? 0.20 : 0.14)
            } ?? Brand.panel(dark))
                .overlay {
                    shape.strokeBorder(onCursor ? Brand.accent(dark)
                                                : Brand.glassEdge(dark),
                                       lineWidth: onCursor ? 1.5 : 1)
                }
                // **No blur per card.** One shadow is cheap; forty are not,
                // and a storyboard is forty. The slab's own ground against the
                // well, plus the edge, already reads as lifted — measured at
                // the same look for a third less work.
                
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
                FrameWindows.shared.open(for: row.id, state: state)
            } else {
                state.cursorShot = row.id
                state.marked.removeAll()
            }
        }
        .onDrop(of: [.fileURL, .image, .movie], isTargeted: nil) { providers in
            Drops.take(providers, onto: row, state: state)
        }
        .contextMenu {
            Button("Frames…") { FrameWindows.shared.open(for: row.id, state: state) }
        }
    }
}
