import AppKit
import SwiftUI

/// **The second door on every add-a-picture panel** — Ref 228, his idea:
///
/// > *"whenever I go to import any image or a piece of media into a shot or
/// > maybe a gallery in the mood board or location, then I have the option to
/// > pull from images that are already a part of the project file. Whatever
/// > picker we pull up should be organized by what images are associated with
/// > what mood board, location, or scene. If it's one big gallery, it would be
/// > too confusing."*
///
/// So it is never one wall. A section per scene, per shot and per location, in
/// the order the sidebar has them, and a word narrows across every filename at
/// once. The engine decides the grouping and the order — `gallery` — because
/// the sidebar's order is its to know.
///
/// **Adding one here does not copy it.** A picture is stored by what is in it,
/// so writing the same bytes back under the same name gives the same file: one
/// on disk, one in Drive, however many places point at it. That is why each
/// tile can honestly say how many places already do.
struct PicturePicker: View {
    @ObservedObject var state: ShellState
    /// What the chosen picture is being added to — a shot, a scene, a location.
    let owner: String
    let ownerName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    @State private var word = ""
    @State private var groups: [Engine.Gallery.Group] = []
    @State private var picked: Set<String> = []
    /// **Closed by default, for a scene — open for everything else.** His
    /// original ask, Ref 228: *"if it's one big gallery, it would be too
    /// confusing."* A flat list of every scene's own section, sticky-headed
    /// and always open, was exactly that once a film had forty scenes in it —
    /// this is the fix, 2026-08-24: a scene starts shut, and opening one is a
    /// click. Boards and locations open by default; there are usually few
    /// enough of those that closed would only cost a click to learn nothing.
    ///
    /// `flipped` holds only the groups a hand has touched — kept apart from
    /// the *default* so touching one never has to remember which way it came
    /// from, which is the trap a single "closed" set falls into: removing an
    /// id that was never in it does nothing, so a scene that starts shut could
    /// never be opened.
    @State private var flipped: Set<String> = []

    /// Top-level groups only — a shot's group has a `parent` and hangs off its
    /// scene instead of standing on its own.
    private var topLevel: [Engine.Gallery.Group] { groups.filter { $0.parent.isEmpty } }
    private func children(of group: Engine.Gallery.Group) -> [Engine.Gallery.Group] {
        groups.filter { $0.parent == group.id }
    }
    private func defaultOpen(_ group: Engine.Gallery.Group) -> Bool { group.kind != "scene" }
    /// Open while searching — a match hiding behind a closed section is the
    /// same "too confusing" in a different shape.
    private func isOpen(_ group: Engine.Gallery.Group) -> Bool {
        if !word.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        let base = defaultOpen(group)
        return flipped.contains(group.id) ? !base : base
    }
    private func toggle(_ group: Engine.Gallery.Group) {
        if flipped.contains(group.id) { flipped.remove(group.id) } else { flipped.insert(group.id) }
    }

    var body: some View {
        Sheet(title: "Add to \(ownerName)", width: .standard, height: 520, scrolls: false) {
            VStack(spacing: 0) {
                SearchField(placeholder: "Search", text: $word)
                    .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
                    .onSubmit { load() }
                    .onChange(of: word) { _, _ in load() }
                    .onChange(of: state.previewPictureAt) { _, wanted in
                        guard let wanted, wanted >= 1 else { return }
                        let all = shown
                        guard wanted <= all.count else { return }
                        state.previewPictureAt = nil
                        preview(all[wanted - 1])
                    }

                if groups.isEmpty {
                    EmptyState(title: word.isEmpty ? "Nothing in this project yet"
                                                   : "Nothing matches “\(word)”")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
                            ForEach(topLevel) { group in
                                Section {
                                    if isOpen(group) {
                                        grid(group.items)
                                        // **A scene's own shots, folded under
                                        // it.** A heading and a grid, indented,
                                        // so the picker reads down the film the
                                        // way the sidebar does.
                                        ForEach(children(of: group)) { child in
                                            Text(child.label.isEmpty ? "Untitled" : child.label)
                                                .fieldLabel(dark)
                                                .padding(.leading, 14).padding(.top, 4)
                                            grid(child.items).padding(.leading, 14)
                                        }
                                    }
                                } header: {
                                    sectionHeader(group)
                                }
                            }
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
        } trailing: {
            Button("Cancel") { dismiss() }
            Button(picked.isEmpty ? "Add" : "Add \(picked.count)") { take() }
                .buttonStyle(.primary)
                .disabled(picked.isEmpty)
        }
        .onAppear { load() }
    }

    private func icon(_ kind: String) -> String {
        switch kind {
        case "scene":    return "film"
        case "shot":     return "camera"
        case "board":    return "square.grid.2x2"
        case "location": return "mappin.and.ellipse"
        default:         return "photo"
        }
    }

    /// **A section you can shut.** Tapping the header, not just its chevron —
    /// a narrow hit target on a row this wide is a miss waiting to happen.
    private func sectionHeader(_ group: Engine.Gallery.Group) -> some View {
        let open = isOpen(group)
        return HStack(spacing: 6) {
            Image(systemName: open ? "chevron.down" : "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Brand.ink4(dark))
                .frame(width: 10)
            Text(group.label.isEmpty ? "Untitled" : group.label)
                .sans(Brand.Size.small, weight: .semibold)
                .foregroundStyle(Brand.ink2(dark))
            Text("\(group.items.count)").sans(Brand.Size.tiny).monospacedDigit()
                .foregroundStyle(Brand.ink4(dark))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Brand.panel(dark))
        .contentShape(Rectangle())
        .onTapGesture { toggle(group) }
    }

    private func grid(_ items: [Engine.Gallery.Item]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 140),
                                     spacing: 8, alignment: .top)],
                  alignment: .leading, spacing: 8) {
            ForEach(items) { item in tile(item) }
        }
        .padding(.horizontal, 14)
    }

    private func tile(_ item: Engine.Gallery.Item) -> some View {
        let on = picked.contains(item.hash)
        return VStack(spacing: 4) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if Frames.something(item.hash, item.filename, state.engine) {
                        Frames.view(item.hash, item.filename, engine: state.engine)
                    } else {
                        Frames.gap(item.hash, dark: dark, small: true)
                    }
                }
                .background(Brand.surface2(dark))
                .clipped()
                .overlay {
                    Rectangle().strokeBorder(on ? Brand.accent(dark) : Brand.rule(dark),
                                             lineWidth: on ? 2.5 : 1)
                }
                .overlay(alignment: .topTrailing) {
                    // **Only when it is genuinely in more than one place.** A
                    // "1" on every tile is a number nobody reads.
                    if item.uses > 1 {
                        Text("\(item.uses)")
                            .mono(Brand.type(8), weight: .semibold)
                            .foregroundStyle(Brand.onImage)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .padding(4)
                            .help("In \(item.uses) places")
                    }
                }
            Text(item.filename).sans(10).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(Brand.ink3(dark))
        }
        .contentShape(Rectangle())
        // **One tap, and the count read off the event.** A count-2 tap beside
        // a count-1 tap is the pattern the photograph wall used, and on
        // 2026-08-29 a real posted double-click proved it had never fired
        // there. This is the idiom that does work in this app — the storyboard
        // card has used it all along.
        .onTapGesture {
            if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
                preview(item)
            } else if on {
                picked.remove(item.hash)
            } else {
                picked.insert(item.hash)
            }
        }
        .help(item.filename)
    }

    private func load() {
        groups = state.engine?.gallery(word.trimmingCharacters(in: .whitespaces)) ?? []
    }

    /// Every picture on screen, in the order they are drawn.
    private var shown: [Engine.Gallery.Item] {
        topLevel.flatMap { group in
            group.items + children(of: group).flatMap(\.items)
        }
    }

    /// **Look at one before adding it.** His ask, 2026-08-29: *"double click
    /// should also bring up a gallery image in boards or locations."* This was
    /// the one gallery in the app with no preview at all — you could tick a
    /// picture and never see it larger than 96 points.
    ///
    /// It opens the same pop-out a wall does, so the window is the window he
    /// already knows. **No `ref` goes with it**, deliberately: the ref here
    /// belongs to some *other* owner's use of the file, and handing it over
    /// would let the trim button quietly re-cut a clip where it already lives.
    private func preview(_ item: Engine.Gallery.Item) {
        let all = shown
        let at = all.firstIndex { $0.ref == item.ref }
        Viewer.shared.show(
            Viewer.subject(hash: item.hash, ext: item.ext,
                           filename: item.filename, kind: item.kind,
                           caption: item.caption,
                           place: at.map { "\($0 + 1) of \(all.count)" },
                           state: state),
            state: state)
    }

    /// **The same bytes back through the same door.**
    ///
    /// There is no add-by-hash command and there does not need to be: the store
    /// is addressed by content, so handing `paste` the bytes it already has
    /// writes the identical file and the project ends up with one copy and two
    /// references. Going through the ordinary door also means the ordinary
    /// naming applies — a picture added to a location is named after the
    /// location, which is his rule and would have been quietly skipped by a
    /// shortcut.
    private func take() {
        guard let engine = state.engine else { return }
        var added = 0
        for group in groups {
            for item in group.items where picked.contains(item.hash) {
                guard let held = engine.stored(hash: item.hash, ext: item.ext) else { continue }
                let size = NSImage(data: held.data)?.size ?? .zero
                let named = Attachments.naming(item.filename, ext: held.ext,
                                               ownedBy: owner, state: state)
                state.replace(engine.paste(shot: owner,
                                           width: Int(size.width), height: Int(size.height),
                                           ext: held.ext, data: held.data,
                                           kind: item.kind, named: named))
                added += 1
            }
        }
        FileHandle.standardError.write(Data("gallery added: \(added)\n".utf8))
        dismiss()
    }
}

/// **Its own modifier, and that is not tidiness.** The shell's body already
/// carries a dozen `.sheet`s in one chain, and adding a thirteenth put the
/// Swift type-checker past the point where it will finish — *"unable to
/// type-check this expression in reasonable time"*, which is a compile error
/// rather than a slow build. One more sheet goes on the end of the chain like
/// this, not inside it.
extension View {
    func picturePicker(_ state: ShellState) -> some View {
        sheet(item: Binding(
            get: { state.pickingPictureFor.map(Naming.init(id:)) },
            set: { state.pickingPictureFor = $0?.id }
        )) { owner in
            PicturePicker(state: state, owner: owner.id,
                          ownerName: state.nameOfOwner(owner.id))
        }
    }
}
