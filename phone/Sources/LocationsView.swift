import SwiftUI

/// The locations tab — the reason the phone exists on a scout.
///
/// Every location here is an engine record. Until 2026-08-21 they were files the
/// phone kept beside the project, because the engine had nowhere to put one;
/// there is somewhere now, so there is one copy rather than two.
struct LocationsView: View {
    @EnvironmentObject private var session: Session
    @State private var naming = false
    @State private var newName = ""
    @State private var open: Engine.Location?
    /// The house a new room is going inside, or nil for a place of its own.
    @State private var inside: Engine.Location?
    @State private var query = ""
    /// The place a delete is asked about, with what it costs said first.
    @State private var removing: Engine.Location?

    private var shown: [Engine.Location] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return session.houses }
        return session.houses.filter {
            $0.name.lowercased().contains(q) || $0.address.lowercased().contains(q)
                || session.rooms(of: $0.id).contains { $0.name.lowercased().contains(q) }
        }
    }

    /// Scenes linked to this place or its rooms.
    private func scenes(at place: Engine.Location) -> Int {
        let ids = Set([place.id] + session.rooms(of: place.id).map(\.id))
        return session.scenes.filter { s in
            s.locationIds.split(separator: ",").contains { ids.contains(String($0).trimmingCharacters(in: .whitespaces)) }
        }.count
    }

    var body: some View {
        Group {
            if session.locations.isEmpty {
                ContentUnavailableView {
                    Label("No locations yet", systemImage: "mappin.and.ellipse")
                } actions: {
                    Button("Add Location") { startNaming() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                // **A room sits inside its house** — Ref 269, and his note of
                // 2026-08-22 that the phone had to say so.
                //
                // It says so by *being* inside it: only the places that stand
                // on their own are listed here, and a house's rooms are on the
                // house's own page. Two earlier passes tried to show both
                // depths at once — indented rows, then a rail and a second
                // chevron — and his answer to each was the same: *"looks
                // messy"*. A list that shows one level needs no furniture to
                // explain which level it is showing.
                //
                // **Drawn in the one-app look** (Ref 1582, design/33-one-app):
                // the places on one white card on the grey page, each led by
                // its first photograph, its counts in words under its name.
                // A List still, for the swipe that deletes.
                List {
                    Section {
                        ForEach(shown) { place in
                            ZStack {
                                LocationRow(place: place, rooms: session.rooms(of: place.id).count)
                                NavigationLink(value: place) { EmptyView() }.opacity(0)
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                            .listRowBackground(Style.card)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { removing = place } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                // **Move Into** a house (the Mac's): a place
                                // standing on its own becomes one of its rooms.
                                let others = session.houses.filter { $0.id != place.id && session.rooms(of: place.id).isEmpty }
                                if !others.isEmpty {
                                    Menu {
                                        ForEach(others) { house in
                                            Button(house.name) { session.moveLocation(place.id, into: house.id) }
                                        }
                                    } label: { Label("Move Into", systemImage: "arrow.down.right.square") }
                                }
                                Button(role: .destructive) { removing = place } label: {
                                    Label("Delete…", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .searchable(text: $query, prompt: "Search")
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .contentMargins(.horizontal, 10, for: .scrollContent)
                .contentMargins(.top, 4, for: .scrollContent)
                .environment(\.defaultMinListHeaderHeight, 0)
            }
        }
        .background(Style.page)
        .leadingTitle("Locations")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { startNaming() } label: { Label("Add Location", systemImage: "plus") }
            }
        }
        .navigationDestination(for: Engine.Location.self) { place in
            LocationDetailView(id: place.id).environmentObject(session)
        }
        .navigationDestination(item: $open) { place in
            LocationDetailView(id: place.id).environmentObject(session)
        }
        // A checking run opens one place by name (`-OpenLocation Mansion`).
        .task {
            #if targetEnvironment(simulator)
            if let asked = UserDefaults.standard.string(forKey: "OpenLocation"), open == nil {
                open = session.locations.first { $0.name == asked }
            }
            #endif
        }
        .confirmationDialog("Delete \(removing?.name ?? "")?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let place = removing { session.deleteLocation(place.id) }
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: {
            if let place = removing {
                let n = scenes(at: place), rooms = session.rooms(of: place.id).count
                Text([n > 0 ? "\(n) scene\(n == 1 ? "" : "s") will be unlinked." : "",
                      rooms > 0 ? "\(rooms) room\(rooms == 1 ? "" : "s") stay and stop borrowing this address." : "",
                      "Photos and notes are deleted too."].filter { !$0.isEmpty }.joined(separator: " "))
            }
        }
        .alert(inside == nil ? "New Location" : "New Room", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) { newName = "" }
            Button("Add") { add() }
        }
    }

    private func startNaming(inside house: Engine.Location? = nil) {
        newName = ""
        inside = house
        naming = true
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let house = inside
        newName = ""
        inside = nil
        guard !name.isEmpty else { return }
        let made = house.map { session.addRoom(inside: $0.id, named: name) }
            ?? session.addLocation(named: name)
        guard let made else { return }
        session.store.prepare(made.home)
        // Straight into it — he named the place because he is standing in it and
        // about to photograph it.
        open = made
    }
}

private struct LocationRow: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var frames: Frames
    @Environment(\.displayScale) private var scale
    let place: Engine.Location
    /// How many rooms are inside. Said on the row because the rooms themselves
    /// are a page deeper, and a house that looks childless is a house he will
    /// not think to open.
    var rooms = 0

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(place.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(.label))
                    .lineLimit(2)
                if !counts.isEmpty {
                    Text(counts)
                        .font(.system(size: 13))
                        .foregroundStyle(Style.ink3)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// What is here, counted in words (the mockup's `.dmeta`, "15 lights ·
    /// 1 camera"): no glyphs, which carry no fact a word does not.
    private var counts: String {
        var said: [String] = []
        func count(_ n: Int, _ one: String, _ many: String) {
            if n > 0 { said.append(n == 1 ? "1 \(one)" : "\(n) \(many)") }
        }
        count(rooms, "room", "rooms")
        count(place.photos.count, "photo", "photos")
        count(place.scenes.count, "scene", "scenes")
        let scans = session.rooms(of: place).count
        if scans > 0 { said.append(scans == 1 ? "Scanned" : "\(scans) scans") }
        return said.joined(separator: " · ")
    }

    private var side: CGFloat { 64 }

    @ViewBuilder
    private var thumbnail: some View {
        // The first photograph he took is the one that says which room this is.
        if let first = place.media.first,
           let shown = frames.shown(first, atMost: Thumbnails.bucket(forSide: side, scale: scale)) {
            Picture(shown)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: Style.Radius.frame, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: Style.Radius.frame, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .frame(width: side, height: side)
        }
    }
}
