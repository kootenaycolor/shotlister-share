import SwiftUI

/// A grid of pictures you can choose several of, throw away, and reorder.
///
/// Written once and owned by nothing in particular, because a location's
/// photographs and a mood board's are the same problem — his words: *"multi-select
/// media inside the gallery of a location and eventually a mood board"*. When
/// mood boards become real they take this as it stands.
///
/// Selecting is a mode rather than a long-press-and-hope. On a phone the
/// difference between "open this" and "choose this" cannot be guessed from the
/// gesture, and getting it wrong on a scout means a photograph opening full
/// screen when he meant to tick it.
/// What is ticked, held outside the view that draws it.
///
/// **It cannot be `@State` on the gallery.** The screen around it rebuilds every
/// time the engine hands back a new answer, and a rebuilt view starts with fresh
/// state — so a tick could vanish, and worse, a copy left over from a moment ago
/// went on holding a selection nobody could see. That is what put "Remove 3
/// photos" in front of him when he had chosen two: a stale instance presenting
/// its own dialog over the live one.
///
/// An object the screen owns survives all of that.
@MainActor
final class GallerySelection: ObservableObject {
    @Published var choosing = false
    @Published var chosen: Set<String> = []
    /// What is about to be removed, decided when he asks rather than when the
    /// dialog draws.
    @Published var pending: [Engine.Still] = []

    func clear() {
        choosing = false
        chosen = []
        pending = []
    }
}

struct MediaGallery: View {
    let media: [Engine.Still]
    @ObservedObject var selection: GallerySelection
    var onOpen: (Engine.Still) -> Void
    var onRemove: ([Engine.Still]) -> Void
    var onMove: (Engine.Still, Int) -> Void
    /// How each tile is filled, when the owner says rather than the reader —
    /// a mood board carries its own shape (`original`, `square`, `project`),
    /// the way the Mac's wall does. Nothing here means the reader's own choice,
    /// which is what a location's photographs have always had.
    var shape: String? = nil
    /// The frame the film is cut for, for the `project` shape.
    var ratio: Double = 1.85
    /// **Move to another board** (the Mac's Move to): where picked pictures
    /// can go, as (id, name), and what moving them does. Empty: not offered.
    var moveTargets: [(id: String, name: String)] = []
    var onMoveTo: ([Engine.Still], String) -> Void = { _, _ in }

    @EnvironmentObject private var frames: Frames
    @Environment(\.displayScale) private var scale
    /// Half the screen — what one tile in this two-column grid is actually
    /// drawn at, and therefore what its picture should be decoded at.
    private var cellSide: CGFloat { UIScreen.main.bounds.width / 2 }
    @AppStorage("media.cropToSquare") private var cropToSquare = true


    private var choosing: Bool { selection.choosing }
    private var chosen: Set<String> { selection.chosen }
    private var pending: [Engine.Still] { selection.pending }

    private let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            controls
            grid
        }
        .confirmationDialog(
            pending.count == 1 ? "Remove this photo from here?"
                               : "Remove \(pending.count) photos from here?",
            isPresented: Binding(get: { !selection.pending.isEmpty },
                                 set: { if !$0 { selection.pending = [] } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { remove() }
            Button("Keep Them", role: .cancel) { selection.pending = [] }
        }
    }

    // ---- the bar above ------------------------------------------------------

    /// **Every button in here needs its own button style.**
    ///
    /// A row of buttons inside a `Form` is, by default, one tappable row — tap
    /// the trash and SwiftUI fires *every* button in the row. That is not a
    /// theory: a trace showed one tap on the trash calling Done, then All, then
    /// the removal, which is how he was asked to delete three photographs when
    /// he had chosen one. `.borderless` makes each button answer for itself.
    @ViewBuilder
    private var controls: some View {
        if !media.isEmpty {
            HStack(spacing: 14) {
                Button(choosing ? "Done" : "Select") {
                    withAnimation(.snappy) {
                        selection.choosing.toggle()
                        if !selection.choosing { selection.chosen = [] }
                    }
                }
                .buttonStyle(.borderless)
                .font(.footnote.weight(.medium))

                if choosing {
                    Button(chosen.count == media.count ? "None" : "All") {
                        selection.chosen = chosen.count == media.count ? [] : Set(media.map(\.id))
                    }
                    .buttonStyle(.borderless)
                    .font(.footnote)

                    if chosen.count == 1 {
                        Button { shift(-1) } label: { Image(systemName: "arrow.left") }
                            .buttonStyle(.borderless)
                            .disabled(!canShift(-1))
                        Button { shift(1) } label: { Image(systemName: "arrow.right") }
                            .buttonStyle(.borderless)
                            .disabled(!canShift(1))
                    }

                    Spacer()

                    if !chosen.isEmpty {
                        Text("\(chosen.count) chosen")
                            .font(.kitLabel)
                            .foregroundStyle(.secondary)
                    }

                    if !moveTargets.isEmpty {
                        Menu {
                            ForEach(moveTargets, id: \.id) { target in
                                Button(target.name) {
                                    onMoveTo(media.filter { chosen.contains($0.id) }, target.id)
                                    selection.chosen = []
                                }
                            }
                        } label: { Image(systemName: "folder") }
                        .disabled(chosen.isEmpty)
                        .accessibilityLabel("Move to Board")
                    }

                    Button(role: .destructive) {
                        selection.pending = media.filter { chosen.contains($0.id) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .disabled(chosen.isEmpty)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // ---- the pictures --------------------------------------------------------

    private var grid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(media) { still in
                cell(still)
                    .overlay(alignment: .topLeading) { tick(still) }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if choosing { toggle(still) } else { onOpen(still) }
                    }
            }
        }
        // Every tile's shape before any tile is drawn, so a picture arriving
        // never changes the height of its row.
        .task(id: media.map(\.hash)) { frames.learnShapes(media.map(\.frame)) }
    }

    /// `original`, `square` or `project` — the owner's word when it has one,
    /// and the reader's crop switch when it has not.
    private var filling: String {
        shape ?? (cropToSquare ? "square" : "original")
    }

    @ViewBuilder
    private func cell(_ still: Engine.Still) -> some View {
        if let shown = frames.shown(still, atMost: Thumbnails.bucket(forSide: cellSide, scale: scale)) {
            switch filling {
            case "square":
                Color.clear.aspectRatio(1, contentMode: .fit)
                    .overlay { Picture(shown, framing: still.framing, arrows: still.arrows) }
                    .clipped()
                    .opacity(choosing && !chosen.contains(still.id) ? 0.55 : 1)
            case "project":
                Color.clear.aspectRatio(ratio, contentMode: .fit)
                    .overlay { Picture(shown, framing: still.framing, arrows: still.arrows) }
                    .clipped()
                    .opacity(choosing && !chosen.contains(still.id) ? 0.55 : 1)
            default:
                Picture(shown, arrows: still.arrows)
                    .aspectRatio(natural(shown), contentMode: .fit)
                    .opacity(choosing && !chosen.contains(still.id) ? 0.55 : 1)
            }
        } else {
            // The shape it will be once it arrives, where it has been seen
            // before — a waiting tile that is a square and then a landscape
            // moves everything under it.
            Color.clear.aspectRatio(filling == "original" ? (frames.shape(of: still.hash) ?? 16 / 9)
                                    : (filling == "project" ? ratio : 1), contentMode: .fit)
                .overlay { ProgressView() }
                .background(.quaternary)
        }
    }

    /// The shape to give a cell in the tall grid.
    ///
    /// A picture knows its own; a clip does not say until it has been opened,
    /// and widescreen is the honest guess for something shot on a phone held
    /// the way he holds one.
    private func natural(_ shown: Frames.Shown) -> CGFloat {
        switch shown {
        case .picture(let image): return image.size.width / max(image.size.height, 1)
        case .film: return 16 / 9
        }
    }

    @ViewBuilder
    private func tick(_ still: Engine.Still) -> some View {
        if choosing {
            Image(systemName: chosen.contains(still.id) ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, chosen.contains(still.id) ? Color.accentColor : .black.opacity(0.35))
                .padding(6)
        }
    }

    /// Moving the chosen picture one place.
    ///
    /// **Dragging was written first and did not work.** A drag is a real touch
    /// interaction that nothing here could reproduce, so it could never be
    /// checked — and a gesture that cannot be proved is a feature nobody has.
    /// Two arrows can be tapped, and tapping can be tested.
    private func shift(_ by: Int) {
        guard let id = chosen.first,
              let at = media.firstIndex(where: { $0.id == id }) else { return }
        let to = at + by
        guard media.indices.contains(to) else { return }
        onMove(media[at], to)
    }

    private func canShift(_ by: Int) -> Bool {
        guard let id = chosen.first,
              let at = media.firstIndex(where: { $0.id == id }) else { return false }
        return media.indices.contains(at + by)
    }

    private func toggle(_ still: Engine.Still) {
        if chosen.contains(still.id) { selection.chosen.remove(still.id) }
        else { selection.chosen.insert(still.id) }
    }

    private func remove() {
        onRemove(pending)
        selection.clear()
    }
}
