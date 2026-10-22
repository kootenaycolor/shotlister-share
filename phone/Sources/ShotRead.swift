import SwiftUI

/// **A shot, read** — the mockup's "A Shot" (`design/33-one-app.html`, the
/// presented list's third phone): *everything about 2A on one page; Edit to
/// change it.* Its frame across the top of the screen, its number and name
/// large, the scene it is in, its tags, then what it is, the notes, the words
/// of the script it quotes, and every other field it has in one white table.
///
/// Nothing here writes. **Edit** (the bar) turns the same pages into the
/// editor, where every value is a pill a thumb can hit.
struct ShotRead: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var frames: Frames
    let row: Engine.Row
    let heading: String

    @State private var showing = 0
    @State private var browsing: Engine.Still?

    private var columns: [Engine.Column] { session.view?.columns ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero

                (Text(row.number).font(.system(size: 20, weight: .heavy).monospacedDigit())
                 + Text(shows("title") && !row.title.isEmpty ? "  \(row.title)" : "")
                    .font(.system(size: 20, weight: .bold)))
                    .strikethrough(row.struck)
                    .foregroundStyle(row.struck ? Style.ink3 : Color(.label))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
                    .padding(.horizontal, 18)

                Text(sceneLine)
                    .font(.system(size: 13))
                    .foregroundStyle(Style.ink3)
                    .lineLimit(2)
                    .padding(.top, 3)
                    .padding(.horizontal, 18)

                // **The three he reads, large** (2026-10-07,
                // `design/37-accent.html`). It was six pills in six colours
                // over two ragged lines, every one the same weight. Size,
                // lens and move go up here the way a pro camera app ranks a
                // photograph's numbers; everything else drops into the quiet
                // table below, which is where it can be read.
                if !three.isEmpty {
                    Three(values: three)
                        .padding(.top, 14)
                }

                if !row.said(columns).isEmpty {
                    passage(column("description"), row.said(columns), grey: false)
                }
                if shows("notes"), !row.notes.isEmpty {
                    passage(column("notes"), row.notes, grey: true)
                }
                if let words = row.quoted(columns) {
                    Kicker(column("script"))
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 5)
                    Text("\u{201C}\(words)\u{201D}")
                        .font(.system(size: 13, design: .monospaced))
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(Style.ink2)
                        .padding(.horizontal, 18)
                }

                if !facts.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(fact.0).foregroundStyle(Style.ink3)
                                Spacer(minLength: 8)
                                Text(fact.1)
                                    .multilineTextAlignment(.trailing)
                            }
                            .font(.system(size: 15))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            if index < facts.count - 1 {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                    .card(Style.Radius.list)
                    .padding(.horizontal, 12)
                    .padding(.top, 18)
                }

                Color.clear.frame(height: 40)
            }
        }
        .background(Style.page)
        .ignoresSafeArea(edges: .top)
        .fullScreenCover(item: $browsing) { still in
            StillViewer(still: still, all: row.stills, onDelete: { session.detach($0) },
                        cropTo: session.ratio)
                .environmentObject(session)
                .environmentObject(frames)
        }
    }

    // ---- the frame across the top --------------------------------------------

    private var hero: some View {
        Group {
            if row.stills.isEmpty {
                Rectangle()
                    .fill(Color(.tertiarySystemFill))
                    .overlay {
                        Text("No Frame")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Style.ink3)
                    }
            } else {
                TabView(selection: $showing) {
                    ForEach(Array(row.stills.enumerated()), id: \.element.ref) { index, still in
                        FramePlate(frame: still.frame, ratio: session.ratio)
                            .contentShape(Rectangle())
                            .onTapGesture { browsing = still }
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .aspectRatio(max(session.ratio, 1.2), contentMode: .fit)
        .frame(maxWidth: .infinity)
        .opacity(row.struck ? 0.55 : 1)
        // The bar floats over the picture; a shade keeps its glass legible.
        .overlay(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 110)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomLeading) {
            if row.stills.count > 1 {
                Text("\(showing + 1) of \(row.stills.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(14)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showing < row.stills.count, row.stills[showing].kind == .clip {
                Button { browsing = row.stills[showing] } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(14)
            }
        }
    }

    // ---- the words -------------------------------------------------------------

    private func passage(_ name: String, _ words: String, grey: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Kicker(name)
            Text(words)
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(grey ? Style.ink2 : Color(.label))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
    }

    private var sceneLine: String {
        let scene = row.sceneId.flatMap { session.scene($0) }
        let number = scene?.number ?? ""
        let name = session.isCommercial && !(scene?.title ?? "").isEmpty ? scene!.title : heading
        if number.isEmpty { return name }
        return name.isEmpty ? "Scene \(number)" : "Scene \(number) \u{00B7} \(name)"
    }

    private func shows(_ name: String) -> Bool {
        columns.first { $0.name == name }?.visible ?? true
    }

    private func column(_ name: String) -> String {
        columns.first { $0.name == name }?.shown ?? name.capitalized
    }

    /// **The three across the top**: size, lens, move, in that order, and
    /// only the ones this shot actually has. A shot's modifiers and filters
    /// sit beside its lens (2026-10-14), so most shots still show three.
    private static let strip = ["size", "lens", "modifiers", "lens_filters", "movement"]

    private var three: [Three.One] {
        return Self.strip.compactMap { name in
            // Lens Stack hides Modifiers and Filters as columns; they ride
            // under the lens instead.
            guard shows(name) else { return nil }
            let value = row.cell(name)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            if name == "lens", !(row.lensFilters.isEmpty && row.modifiers.isEmpty) {
                return Three.One(label: column(name), value: value,
                                 filters: row.lensFilters, modifiers: row.modifiers)
            }
            return value.isEmpty ? nil : Three.One(label: column(name), value: value)
        }
    }

    /// Every other field with something in it, in the project's own order:
    /// what is not already in the strip, a passage or the frame. The craft
    /// columns that used to be pills are rows here now.
    private var facts: [(String, String)] {
        let drawn: Set<String> = ["image", "title", "description", "notes", "script", "struck"]
        return columns.compactMap { column in
            guard column.visible, !drawn.contains(column.name),
                  !Self.strip.contains(column.name) else { return nil }
            let value = row.cell(column.name)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            return value.isEmpty ? nil : (column.shown, value)
        }
    }
}

/// **Size, lens and move, across the top of a shot** (2026-10-07,
/// `design/37-accent.html`): three values at a size you can read standing up,
/// divided by hairlines, with their names small and grey under them. The
/// pattern is Halide's and Camera M's, which rank a photograph's numbers the
/// same way rather than giving every field the same weight.
private struct Three: View {
    struct One {
        var label: String
        var value: String
        var filters: [String] = []
        var modifiers: [String] = []
    }
    let values: [One]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, one in
                VStack(spacing: 4) {
                    if !one.value.isEmpty {
                        Text(one.value)
                            .font(.system(size: 20, weight: .semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.65)
                            .multilineTextAlignment(.center)
                    }
                    if !(one.filters.isEmpty && one.modifiers.isEmpty) {
                        LensStackLine(filters: one.filters, modifiers: one.modifiers, roomy: true)
                            .frame(maxWidth: .infinity)
                    }
                    Text(one.label)
                        .font(.system(size: Kit.Size.label, weight: .semibold))
                        .foregroundStyle(Style.ink3)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .padding(.horizontal, 6)
                .overlay(alignment: .leading) {
                    if index > 0 { Rectangle().fill(Style.rule).frame(width: 1) }
                }
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(Style.rule).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Style.rule).frame(height: 1) }
    }
}
