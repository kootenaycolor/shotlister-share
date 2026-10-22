import SwiftUI
import MapKit
import CoreLocation
import AppKit

// MARK: - what a location is, on this screen
//
// **Two facts, never one.** A scene's `location` is the slugline's word —
// "CAR", "COUNTY JAIL" — lifted off the script and never ours to change. A
// *location record* is the address the crew drives to, with photographs, a pin,
// notes, and whatever the phone brought home from the scout. Cadrage keeps both
// for the same reason, and this screen only ever writes the second.
//
// The engine holds all of it (`Kind::Location`); nothing here keeps a copy.
// The one exception is deliberate and named below: the scans and the papers
// stay as **files** in the project folder, because a scanned room is a hundred
// megabytes of geometry and a document store is not where that belongs.

/// A bare id, wrapped so `.sheet(item:)` will carry it. SwiftUI wants
/// something `Identifiable` and a `String` is not.
struct Naming: Identifiable, Hashable {
    let id: String
}

// MARK: - the sidebar list

/// Every location in the project, on the left, the way the scenes are.
struct LocationList: View {
    @ObservedObject var state: ShellState
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        List(selection: Binding(
            get: { state.location?.id },
            set: { state.locationId = $0 }
        )) {
            ForEach(rows, id: \.place.id) { row in
                let place = row.place
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // The one fact worth a mark — whether it has an address —
                    // as a dot, the way the scene list marks time of day.
                    Circle()
                        .fill(place.pin == nil ? Color.clear : Brand.accent(dark))
                        .overlay {
                            if place.pin == nil {
                                Circle().strokeBorder(Brand.ink4(dark), lineWidth: 1)
                            }
                        }
                        .frame(width: 5, height: 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name.isEmpty ? "Untitled" : place.name)
                            .sans(11, weight: row.inside ? .regular : .semibold)
                            .foregroundStyle(Brand.ink(dark))
                            .lineLimit(1)
                        // The first line of the address only. The rest is the
                        // town and the postcode, which is not what tells two
                        // locations apart in a list.
                        //
                        // **A room shows nothing here.** It is standing under
                        // the house whose address it borrows, and repeating
                        // that address on all six rooms is how the list stops
                        // being readable.
                        if !row.inside,
                           let street = place.effectiveAddress.split(separator: "\n").first {
                            Text(String(street)).sans(10)
                                .foregroundStyle(Brand.ink3(dark))
                                .lineLimit(1).truncationMode(.tail)
                        }
                    }
                    Spacer(minLength: 0)
                    // **How much of the film hangs on it.** A location list
                    // that cannot say "eleven scenes are here" is a list of
                    // addresses rather than a tool. A house counts the scenes
                    // in its rooms too; a room counts only its own.
                    let count = row.inside ? place.scenes.count : place.scenesInside
                    if count > 0 {
                        Text("\(count)").sans(Brand.Size.tiny).monospacedDigit()
                            .foregroundStyle(Brand.ink4(dark))
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .padding(.leading, row.inside ? 14 : 0)
                .tag(place.id)
                .sidebarRow(picked: state.location?.id == place.id, dark: dark)
                .contextMenu { menu(place) }
            }
        }
        .sidebarList()
        .environment(\.defaultMinListRowHeight, 30)
        .overlay {
            if state.locations.isEmpty { empty }
        }
    }

    /// The list, nested: a house and then the rooms in it, indented.
    ///
    /// **Searching flattens it.** While you are hunting for a room, showing it
    /// tucked under a house that does not itself match is noise — and a room
    /// whose house has been filtered away would otherwise vanish with it.
    private var rows: [(place: ViewModel.Location, inside: Bool)] {
        let shown = state.locations
        guard state.search.trimmingCharacters(in: .whitespaces).isEmpty else {
            return shown.map { ($0, false) }
        }
        let byId = Dictionary(shown.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [(ViewModel.Location, Bool)] = []
        for place in shown where !place.isArea {
            out.append((place, false))
            for id in place.areas {
                if let area = byId[id] { out.append((area, true)) }
            }
        }
        // A room whose house is not in the list still has to appear somewhere.
        let seen = Set(out.map(\.0.id))
        out.append(contentsOf: shown.filter { !seen.contains($0.id) }.map { ($0, false) })
        return out
    }

    /// Locations a given one could be filed inside: the houses, minus itself,
    /// minus anything that already holds rooms of its own. One level, always.
    private func houses(for place: ViewModel.Location) -> [ViewModel.Location] {
        (state.view?.locations ?? []).filter {
            !$0.isArea && $0.id != place.id
        }
    }

    @ViewBuilder private func menu(_ place: ViewModel.Location) -> some View {
        // **A room has no address of its own** — it is at its house's, and
        // that is the whole of Ref 269. So the doors that would write one are
        // shut for a room rather than left open and quietly overriding the
        // house: menu item here, map and typing on the card. Ref 308.
        if !place.isArea {
            Button("Set address…") { state.findingAddress = place.id }
            Button("Add area…") { state.addingAreaIn = place.id }
        }
        Divider()
        if place.isArea {
            Button("Move out") {
                state.replace(state.engine?.moveLocation(place.id, into: ""))
            }
        } else if place.areas.isEmpty, !houses(for: place).isEmpty {
            Menu("Move into") {
                ForEach(houses(for: place)) { house in
                    Button(house.name.isEmpty ? "Untitled" : house.name) {
                        state.replace(state.engine?.moveLocation(place.id, into: house.id))
                    }
                }
            }
        }
        Divider()
        Button("Delete location", role: .destructive) { remove(place) }
    }

    /// **The same words and the same shape as the window's own empty state**,
    /// one size down. They used to differ in both: this said *Add one* as a
    /// bare orange link while the pane beside it offered *Add location…* as a
    /// button, for the same click.
    @ViewBuilder private var empty: some View {
        EmptyState(title: state.search.isEmpty
                        ? "No locations yet"
                        : "Nothing matches “\(state.search)”",
                   compact: true) {
            if state.search.isEmpty {
                Button("+ Add location…") { state.addingLocation = true }
            }
        }
    }

    /// **The scenes lose the pointer and nothing else.** Deleting a location
    /// must never take a scene's own writing with it, which is why the engine
    /// clears the reference and stops there — and why this says so out loud
    /// rather than asking a yes/no question that hides what it costs.
    private func remove(_ place: ViewModel.Location) {
        let alert = NSAlert()
        alert.messageText = "Delete “\(place.name)”?"
        var cost: [String] = []
        if !place.scenes.isEmpty {
            cost.append("\(place.scenes.count) scene\(place.scenes.count == 1 ? "" : "s") point here. They keep everything of their own — they simply stop naming a location.")
        }
        // **What the rooms lose is the address they were borrowing.** They
        // survive and come up a level, which is the law — but saying only
        // "they survive" would hide the one real cost.
        if !place.areas.isEmpty {
            cost.append("\(place.areas.count) area\(place.areas.count == 1 ? "" : "s") inside it stay, and stop borrowing this address.")
        }
        if cost.isEmpty {
            cost.append("Photos and notes are deleted too.")
        }
        alert.informativeText = cost.joined(separator: "\n\n")
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if state.locationId == place.id { state.locationId = nil }
        state.replace(state.engine?.deleteLocation(place.id))
    }
}

// MARK: - naming a new one

/// The same shape as Add Scene: one field, one button, no ceremony.
struct AddLocation: View {
    @ObservedObject var state: ShellState
    /// The house to put this inside, when it is a room — Ref 269.
    var inside: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var name = ""
    private var dark: Bool { scheme == .dark }

    private var house: ViewModel.Location? {
        inside.flatMap { id in state.view?.locations.first { $0.id == id } }
    }

    var body: some View {
        Sheet(title: house.map { "Add Area in \($0.name)" } ?? "Add Location", width: .narrow) {
            Field("Name") {
                FieldText(placeholder: house == nil ? "Location Name" : "Area Name",
                          text: $name, onSubmit: add)
            }
        } trailing: {
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Add", action: add)
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func add() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let engine = state.engine else { return }
        let before = Set((state.view?.locations ?? []).map(\.id))
        if let inside {
            state.replace(engine.addArea(inside, name: trimmed))
        } else {
            state.replace(engine.addLocation(name: trimmed))
        }
        // Select what was just made. The engine hands back the whole list, so
        // the new one is whichever id was not there a moment ago — asked of
        // the answer rather than guessed at from the order.
        if let fresh = (state.view?.locations ?? []).first(where: { !before.contains($0.id) }) {
            state.locationId = fresh.id
        }
        dismiss()
    }
}

// MARK: - the record

/// One location, filling the window: what it is called, where it is, what was
/// photographed there, and what hangs on it.
///
/// The shape is Cadrage's, because it is the right shape for a scout: the
/// pictures get the room, and everything that is one line — the map, the
/// notes, the scans, the paperwork — lines up in a rail down the right.
struct LocationPage: View {
    @ObservedObject var state: ShellState
    let place: ViewModel.Location
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    @State private var over = false
    @State private var linking = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    photographs
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onDrop(of: [.fileURL, .image, .movie], isTargeted: $over) { providers in
                Attachments.take(providers, ownedBy: place.id, state: state)
            }
            .overlay {
                if over {
                    RoundedRectangle(cornerRadius: Brand.radius)
                        .strokeBorder(Brand.accent(dark),
                                      style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        .padding(10)
                }
            }

            LocationRail(state: state, place: place)
                .frame(width: 244)
        }
        .sheet(isPresented: $linking) {
            LinkScenes(state: state, place: place)
        }
        .onChange(of: place.id) { _, _ in
            state.pickedPhotos = []
            state.pickedPhoto = place.photos.first?.ref
        }
    }

    // MARK: - the arrows, from a console flag
    //
    // `WallKeys` (`PictureWall.swift`) is what answers the arrows now — one
    // shared monitor for every wall in the app, installed once at launch,
    // rather than a monitor per screen. This page used to install its own,
    // and briefly ran both at once during the move to `PictureWall`: two local
    // `keyDown` monitors on the same keys is the exact race this codebase has
    // already paid for once (the references panel and the table fought over
    // ← → for weeks). `subject(_:at:state:)` below stays — `--openphoto` and
    // `--photo` still build a `Viewer.Subject` from it directly, with no
    // monitor involved.

    /// **Finder's grammar, on the wall of photographs.**
    ///
    /// ← → walk one at a time, ↑ ↓ walk a row, space or Return pops the viewer
    /// out, Escape puts it away. And whenever the picked photograph changes,
    /// the pop-out follows it *if it is already open* — which is the difference
    /// between "the arrows change what I am looking at" and "the arrows keep
    /// opening a window at me".
    /// A photograph, with **where else it lives** attached — the copy in the
    /// project folder and, once the Drive bridge has run, the one in Google
    /// Drive. Both are real files a person can be shown.
    /// **Now the same builder a click uses.** This was its own third copy,
    /// and the only one that offered Google Drive — so the console flags that
    /// call it were checking a window nobody could open.
    static func subject(_ photo: ViewModel.Attachment, at place: ViewModel.Location,
                        state: ShellState) -> Viewer.Subject {
        Viewer.subject(photo, among: place.photos,
                       alsoAt: { Scout.homes(of: photo, at: place, state: state) },
                       state: state)
    }

    // ---------------------------------------------------------------- header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            // **A room says which house it is in, and gets you back there.**
            // Ref 269: the address, the parking and the key are the house's,
            // so the way back to them has to be one click from any room.
            if let house {
                Button {
                    state.locationId = house.id
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                        Text(house.name.isEmpty ? "Untitled" : house.name).sans(11, weight: .medium)
                    }
                    .foregroundStyle(Brand.ink3(dark))
                }
                .buttonStyle(.plain)
            }

            CommittingField(
                text: place.name,
                ghost: "Untitled location",
                font: Brand.sansFont(23, weight: .semibold),
                dark: dark
            ) { fresh in
                state.replace(state.engine?.setLocation(place.id, "name", fresh))
            }

            HStack(spacing: 10) {
                // **The scenes are chips, not a count.** The reason to open a
                // location on a Tuesday is to see what is shot there, and a
                // number cannot be clicked.
                Menu {
                    if place.scenes.isEmpty {
                        Text("No scenes")
                    }
                    ForEach(scenesHere) { sc in
                        // A house's list names the room, because "34 INT.
                        // KITCHEN" and "34, in the Kitchen" are different
                        // facts and only the second is ours.
                        let room = sc.locationId == place.id
                            ? ""
                            : "  · " + (areasHere.first { $0.id == sc.locationId }?.name ?? "")
                        Button("\(sc.number)  \(sc.heading)\(room)") { go(to: sc) }
                    }
                    Divider()
                    Button("Add scene…") { linking = true }
                } label: {
                    // The chevron is the system's. `.borderlessButton` drops a
                    // trailing image out of its label, so a drawn one silently
                    // does not appear and the control reads as a caption.
                    HStack(spacing: 6) {
                        Text(scenesHere.count == 1
                             ? "1 scene"
                             : "\(scenesHere.count) scenes")
                            .sans(Brand.Size.small, weight: .medium)
                        MenuMark()
                    }
                    .foregroundStyle(scenesHere.isEmpty ? Brand.ink3(dark) : Brand.ink2(dark))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()

                // The rooms inside, the same shape as the scenes chip.
                if !place.isArea {
                    Menu {
                        ForEach(areasHere) { area in
                            Button(area.name.isEmpty ? "Untitled" : area.name) {
                                state.locationId = area.id
                            }
                        }
                        if !areasHere.isEmpty { Divider() }
                        Button("Add area…") { state.addingAreaIn = place.id }
                    } label: {
                        HStack(spacing: 6) {
                            Text(place.areas.count == 1 ? "1 area" : "\(place.areas.count) areas")
                                .sans(Brand.Size.small, weight: .medium)
                            MenuMark()
                        }
                        .foregroundStyle(place.areas.isEmpty ? Brand.ink3(dark) : Brand.ink2(dark))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .fixedSize()
                }

                if !place.capturedBy.isEmpty {
                    Text("· from \(place.capturedBy)").sans(11)
                        .foregroundStyle(Brand.ink4(dark))
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.bottom, 18)
    }

    /// The house this room is in, if it is one.
    private var house: ViewModel.Location? {
        place.parent.isEmpty
            ? nil
            : state.view?.locations.first { $0.id == place.parent }
    }

    private var areasHere: [ViewModel.Location] {
        let wanted = Set(place.areas)
        return (state.view?.locations ?? []).filter { wanted.contains($0.id) }
    }

    /// The scenes shot here — **and in its rooms, when this is a house.**
    ///
    /// The sidebar counts a house's rooms in its number, and a header saying
    /// "0 scenes" beside a sidebar saying "2" is two answers to one question.
    private var scenesHere: [ViewModel.Scene] {
        var wanted = Set(place.scenes)
        for area in areasHere { wanted.formUnion(area.scenes) }
        return (state.view?.scenes ?? []).filter { wanted.contains($0.id) }
    }

    /// Walking from a location to a scene means leaving this screen — so it
    /// says so by moving, rather than opening a scene inside a locations tab
    /// where nothing else about a scene lives.
    private func go(to scene: ViewModel.Scene) {
        state.sideTab = .scenes
        state.sceneId = scene.id
    }

    // ----------------------------------------------------------- photographs

    private var photographs: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Photographs").fieldLabel(dark)
                if !place.photos.isEmpty {
                    Text("\(place.photos.count)").sans(Brand.Size.tiny).monospacedDigit()
                        .foregroundStyle(Brand.ink4(dark))
                }
                // **Where else these pictures are.** The Drive bridge keeps a
                // location's photographs the same in the project and in his
                // Google Drive, so a producer can see them without a copy of an
                // app that was never published. Saying which folder is the
                // difference between a sync you trust and one you wonder about.
                if !place.driveFolder.isEmpty {
                    Text("in Drive as “\(place.driveFolder)”").sans(Brand.Size.tiny)
                        .foregroundStyle(Brand.ink4(dark))
                        .help("Synced with Google Drive")
                }
                Spacer(minLength: 0)
                if !place.photos.isEmpty {
                    TileSizeSlider(value: $state.locationTile)
                }
                RatioMenu(mode: $state.locationRatioMode)
                AddPicturesMenu(owner: place.id, ownerName: place.name.isEmpty ? "this location" : place.name,
                                state: state)
            }
            Brand.rule(dark).frame(height: 1)

            if place.photos.isEmpty {
                EmptyState(title: "Drop photographs here") {
                    AddPicturesMenu(owner: place.id,
                                    ownerName: place.name.isEmpty ? "this location" : place.name,
                                    state: state)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                // **The shared wall** — his instruction, 2026-08-24: every
                // gallery obeys the same rules and he should not have to ask
                // twice. So a location's photographs are drawn by the same
                // `PictureWall` a mood board is, which brings carrying with a
                // live shuffle, captions in the tile and in the viewer, and
                // the arrow keys, none of which this wall had. The ratio and
                // the size are his to set now, in the same 3-way menu and the
                // same slider a mood board draws — one control, everywhere it
                // is needed, rather than a binary toggle that only this screen
                // had. The renaming rule (Ref 273) is untouched: it lives in
                // the ingest path, not here.
                PictureWall(pictures: place.photos,
                            owner: place.id,
                            state: state,
                            tile: state.locationTile,
                            ratioMode: state.locationRatioMode,
                            removeVerb: "Remove",
                            // **Show in Google Drive, back in the app.** A
                            // location photograph lives in the project folder
                            // and, once the bridge has run, in Drive — and
                            // "where is it really" is a question a producer
                            // asks him. The wall could not offer it, so from
                            // the day this screen moved onto the shared wall
                            // the menu item was reachable only from a console
                            // flag, which is where the battery kept finding it.
                            alsoAt: { Scout.homes(of: $0, at: place, state: state) })
            }
        }
    }

    /// A photograph's own shape, from the picture already decoded for the
    /// tile. Widescreen is the honest guess for something that has not been
    /// read yet — the same guess the phone makes.
}

// MARK: - the rail

/// The one-line facts, down the right: where it is, what was said about it,
/// the rooms that were measured, and the paperwork.
private struct LocationRail: View {
    @ObservedObject var state: ShellState
    let place: ViewModel.Location
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    private var house: ViewModel.Location? {
        place.parent.isEmpty
            ? nil
            : state.view?.locations.first { $0.id == place.parent }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                MapCard(state: state, place: place)
                NotesCard(state: state, place: place)
                // **The house's notes, from inside a room.** Where to park and
                // who to ask are facts about the house, and a room is where
                // you are standing when you need them. Read-only here: they
                // are edited on the house, once, which is the whole ask.
                if let house, !house.notes.trimmingCharacters(in: .whitespaces).isEmpty {
                    RailCard(title: house.name.isEmpty ? "Untitled" : house.name,
                             dark: dark) {
                        Text(house.notes).sans(11)
                            .foregroundStyle(Brand.ink2(dark))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.bottom, 8)
                    }
                }
                FilesCard(state: state, place: place, papers: false)
                FilesCard(state: state, place: place, papers: true)
                DriveCard(state: state, place: place)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
        .frame(maxHeight: .infinity)
    }
}

/// A card in the rail: a title line with an optional action, and a body.
private struct RailCard<Body: View>: View {
    let title: String
    var action: (icon: String, help: String, run: () -> Void)?
    let dark: Bool
    @ViewBuilder let content: () -> Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(title).fieldLabel(dark)
                Spacer(minLength: 0)
                if let action {
                    Button(action: action.run) {
                        Image(systemName: action.icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Brand.ink3(dark))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(action.help)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(dark, radius: 12)
    }
}

// MARK: - the map

/// Where it is, drawn as a real Apple map.
///
/// **A picture of a map rather than a live one**, deliberately. This card is
/// 220 points wide and never interacted with — the searching and the dragging
/// happen in the sheet — and a still image draws into the offscreen bitmap the
/// checking runs photograph, which a live `Map` does not. Same rule as the rest
/// of the app: an app that cannot be looked at cannot be verified.
private struct MapCard: View {
    @ObservedObject var state: ShellState
    let place: ViewModel.Location
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    @State private var picture: NSImage?

    var body: some View {
        RailCard(title: "Address",
                 action: place.pin == nil ? nil
                       : (icon: "arrow.triangle.turn.up.right.circle",
                          help: "Get directions", run: directions),
                 dark: dark) {
            VStack(alignment: .leading, spacing: 0) {
                // **A room with nowhere on the map draws no map.** It cannot be
                // given an address of its own (Ref 308) and its house has not
                // been given one either, so the panel that would say "Set
                // address" has nothing to offer — and an empty black rectangle
                // where a map goes reads as something that failed to load.
                // **Empty is one line and a "+ Verb" capsule, left-aligned** —
                // not a filled button centred over a grey rectangle where a
                // map would go. A map is drawn once there is a pin.
                if place.pin == nil, !place.isArea {
                    HStack {
                        Button("+ Set address…") { state.findingAddress = place.id }
                            .buttonStyle(.capsule)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).padding(.bottom, 10)
                } else if place.pin != nil {
                    ZStack {
                        Rectangle().fill(Brand.surface2(dark))
                        if let picture {
                            Image(nsImage: picture).resizable().aspectRatio(contentMode: .fill)
                        }
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.red, .white)
                            .shadow(radius: 2)
                    }
                    .frame(height: 132)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture { if !place.isArea { state.findingAddress = place.id } }
                    .help(place.isArea ? houseName : "Change the address")
                }

                // **A room shows the house's address.** Drawn quieter when it
                // is borrowed, and the tooltip names whose it is — Ref 269.
                // **Double-click to type it** — his ask, 2026-08-22. The map
                // sheet is for finding a place you cannot spell; correcting a
                // unit number or a spelling should not need a map at all.
                //
                // **A room's is read-only.** Typing here used to give the room
                // an address of its own the moment anybody clicked in the
                // field — which is the bug in Ref 308, not a feature: his rule
                // is that a room is at its house's address, full stop. The
                // notes are a different matter and still take a room's own.
                if editingAddress, !place.isArea {
                    TextEditor(text: $typedAddress)
                        .font(Brand.sansFont(11))
                        .foregroundStyle(Brand.ink(dark))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 46)
                        .focused($inAddress)
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .onAppear {
                            typedAddress = place.address.isEmpty && !place.addressIsInherited
                                ? place.effectiveAddress
                                : place.address
                            inAddress = true
                        }
                        .onChange(of: inAddress) { _, still in
                            if !still { commitAddress() }
                        }
                } else if !place.effectiveAddress.isEmpty {
                    Text(place.effectiveAddress).sans(11)
                        .foregroundStyle(place.addressIsInherited
                                         ? Brand.ink3(dark) : Brand.ink2(dark))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { if !place.isArea { editingAddress = true } }
                        .help(place.isArea ? houseName
                                           : (place.addressIsInherited ? houseName
                                                                       : "Double-click to edit"))
                }
            }
        }
        .task(id: pinKey) { await draw() }
    }

    /// Re-draws when the pin moves and not otherwise — a snapshot is a network
    /// call, and one per redraw would fire on every keystroke elsewhere.
    private var pinKey: String {
        "\(place.effectiveLatitude),\(place.effectiveLongitude)"
    }

    @State private var editingAddress = false
    @State private var typedAddress = ""
    @FocusState private var inAddress: Bool

    /// **Written when the pen goes down**, like the notes — every keystroke
    /// would save the project.
    ///
    /// The pin is deliberately not moved. An address typed by hand may be a
    /// correction to a spelling, and dragging the map to a fresh guess of
    /// where that is would be answering a question nobody asked. `Set
    /// address…` is still how a place gets found on a map.
    private func commitAddress() {
        editingAddress = false
        let wanted = typedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard wanted != place.address else { return }
        state.replace(state.engine?.setLocation(place.id, "address", wanted))
    }

    /// The house a borrowed address belongs to.
    private var houseName: String {
        (state.view?.locations.first { $0.id == place.parent })?.name ?? ""
    }

    private func draw() async {
        guard let pin = place.pin else { picture = nil; return }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: pin,
            span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006))
        // **Asked for at twice the size it is drawn at.** `MKMapSnapshotter`
        // on the Mac has no `scale`, so retina is bought by asking for twice
        // the points and letting the image be drawn into half of them — the
        // alternative is a soft blow-up sitting beside type that is sharp.
        options.size = CGSize(width: 440, height: 264)
        options.showsBuildings = true
        options.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        picture = try? await MKMapSnapshotter(options: options).start().image
    }

    /// Hands the pin to Maps. The crew finds a place once and returns to it —
    /// the phone thread's line, and it is the half that earns its keep.
    private func directions() {
        guard let pin = place.pin else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: pin))
        item.name = place.name.isEmpty ? "Location" : place.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey:
                                        MKLaunchOptionsDirectionsModeDriving])
    }
}

// MARK: - the notes

private struct NotesCard: View {
    @ObservedObject var state: ShellState
    let place: ViewModel.Location
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    @State private var words = ""
    @FocusState private var typing: Bool

    var body: some View {
        // **Notes is a field, not an action** — his question, 2026-09-14, and
        // the honest answer: an empty field with a placeholder, in the one
        // field shape.
        RailCard(title: "Notes", dark: dark) {
            TextEditor(text: $words)
                .font(Brand.sansFont(Brand.Size.small))
                .foregroundStyle(Brand.ink(dark))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 60)
                .padding(.leading, 6).padding(.trailing, 10).padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
                        .fill(Brand.menu(dark))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
                        .strokeBorder(Brand.rule2(dark), lineWidth: 1)
                }
                .overlay(alignment: .topLeading) {
                    if words.isEmpty && !typing {
                        Text("Add a note")
                            .sans(Brand.Size.small).foregroundStyle(Brand.ink4(dark))
                            .padding(.horizontal, 12).padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
                .focused($typing)
                .padding(.horizontal, 10).padding(.bottom, 10)
        }
        // **Written when the pen goes down, not on every letter.** Every
        // mutation saves the project, and saving on each keystroke is how a
        // text box starts to feel like typing through treacle.
        .onChange(of: typing) { _, nowTyping in
            if !nowTyping { commit() }
        }
        .onChange(of: place.id) { _, _ in
            commit()
            words = place.notes
        }
        .onAppear { words = place.notes }
        .onDisappear { commit() }
    }

    private func commit() {
        guard words != place.notes else { return }
        state.replace(state.engine?.setLocation(place.id, "notes", words))
    }
}

// MARK: - Google Drive

/// **The switch, at last** — Ref 229/343. The machinery has honoured this
/// setting since 2026-08-23; there was no way to flip it except through Claude,
/// which is exactly the invisibility he complained about.
///
/// A room follows the same rule a room follows for everything else here: it is
/// its own place with its own folder in Drive, so it gets its own switch.
private struct DriveCard: View {
    @ObservedObject var state: ShellState
    let place: ViewModel.Location
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    private var linked: Bool {
        !(state.view?.project.driveFolder ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        RailCard(title: "Google Drive", dark: dark) {
            VStack(alignment: .leading, spacing: 6) {
                DriveSwitch(on: place.syncsWithDrive, filmIsLinked: linked) { want in
                    state.replace(state.engine?.setLocation(place.id, "syncWithDrive",
                                                            want ? "1" : "0"))
                }
                // Which folder, once the bridge has made one. Naming it is the
                // difference between a sync you trust and one you wonder about.
                if !place.driveFolder.isEmpty {
                    Text(place.driveFolder).sans(Brand.Size.tiny)
                        .foregroundStyle(Brand.ink4(dark))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 10).padding(.bottom, 10)
        }
    }
}

// MARK: - what the phone left in the folder

/// The scans and the paperwork.
///
/// **These are files, on purpose, and the engine does not hold them.** A
/// scanned room is a `.usdz` full of geometry beside a `.json` full of
/// measurements — tens of megabytes a room, and a document store that every
/// machine syncs in full is exactly the wrong place for it. The phone writes
/// them into `<Project>.shotlist/locations/<folder>/`, and the record carries
/// the folder's name so the Mac can find them again.
private struct FilesCard: View {
    @ObservedObject var state: ShellState
    let place: ViewModel.Location
    /// Papers rather than scans — the same card, twice, because they differ in
    /// one word and a second copy of it would drift.
    let papers: Bool
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    /// **Read when the location changes, not on every redraw.**
    ///
    /// This was a computed property, so listing the folder — and, for the
    /// banner above, parsing every `location.json` in the project — happened
    /// inside the view body. Every click on a photograph invalidated the body
    /// and did the whole lot again, which is the "ever so slight lag" he
    /// reported when tapping between pictures. Nothing here changes without
    /// somebody putting a file there, so it is read once and kept.
    @State private var found: [Scout.Item] = []
    @State private var renaming: Scout.Item?
    @State private var typed = ""

    private func reread() {
        guard let project = state.projectPath else { found = []; return }
        found = papers ? Scout.papers(of: place, in: project)
                       : Scout.scans(of: place, in: project)
    }

    var body: some View {
        RailCard(title: papers ? "Attachments" : "3D Scans", dark: dark) {
            VStack(alignment: .leading, spacing: 0) {
                if found.isEmpty {
                    Text(papers ? "Nothing attached" : "Nothing scanned")
                        .sans(11).foregroundStyle(Brand.ink4(dark))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10).padding(.bottom, 10)
                } else {
                    ForEach(found) { item in
                        row(item)
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .onAppear(perform: reread)
        .onChange(of: place.id) { _, _ in reread() }
        .onChange(of: place.media.count) { _, _ in reread() }
        .alert("Rename Scan", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $typed)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let item = renaming { rename(item, to: typed) }
                renaming = nil
            }
        }
    }

    private func row(_ item: Scout.Item) -> some View {
        Button {
            // **A scan opens in Shotlister, not in Preview.** Preview can turn
            // a `.usdz` over and cannot measure it, and the measuring is the
            // half that does the work.
            if let measurements = item.measurements {
                ScanWindow.shared.show(usdz: item.url, json: measurements,
                                       title: item.name, state: state)
            } else {
                NSWorkspace.shared.open(item.url)
            }
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).sans(11).foregroundStyle(Brand.ink(dark))
                        .lineLimit(1).truncationMode(.middle)
                    // **A scan without its measurements is half a scan**, and
                    // saying so is the difference between a floor plan that is
                    // missing and one that was never possible.
                    if let note = item.note {
                        Text(note).sans(10).foregroundStyle(Brand.ink4(dark))
                    } else if let taken = item.taken {
                        Text(taken).sans(10).foregroundStyle(Brand.ink4(dark))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !papers, !item.refs.isEmpty, state.engine != nil {
                Button("Rename…") { typed = item.name; renaming = item }
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
        .help(item.url.lastPathComponent)
    }

    /// Both halves of the room take the name; its files keep theirs.
    private func rename(_ item: Scout.Item, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != item.name, let engine = state.engine else { return }
        var last: ViewModel?
        for ref in item.refs { last = engine.renameUse(ref, to: name) ?? last }
        if let view = last { state.replace(view) }
        reread()
    }
}

/// Reading what the scout brought home.
///
/// One-way and read-only: this looks in the project folder and reports what is
/// there. It writes nothing, moves nothing and deletes nothing — the phone owns
/// that folder, and two writers is the bug this repo has a law about.
enum Scout {
    struct Item: Identifiable {
        let url: URL
        let name: String
        let icon: String
        let note: String?
        /// A scan's other half — the measurements. Nil for a paper.
        var measurements: URL?
        /// When a scan was taken, said under its name.
        var taken: String? = nil
        /// The uses of a scan's two halves on the film, to rename it by.
        var refs: [String] = []
        var id: String { url.path }
    }

    /// **A place made on the Mac has no folder, and falls back to its id** —
    /// Ref 305, found by the phone thread. This guard used to give up the
    /// moment it saw an empty folder, so a Mac-made location had no scans area
    /// and no attachments area at all, silently. `shared/FileNames.swift` holds
    /// the rule both apps use, so the two cannot pick different folders for one
    /// room and strand half its files.
    static func folder(of place: ViewModel.Location, in project: URL) -> URL? {
        let named = FileNames.locationFolder(id: place.id, folder: place.folder)
        guard !named.isEmpty else { return nil }
        let dir = project.appendingPathComponent("locations", isDirectory: true)
            .appendingPathComponent(named, isDirectory: true)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    /// **A scan is a pair of files sharing one name** — the phone thread's
    /// design, and nothing records the relationship, so it is read the same way
    /// here: find the shapes, and look beside each for its measurements.
    /// **The film's rooms first, then the folder's.** A scan the engine holds
    /// is two stored files under one hash in `media/proxies`, which is what
    /// travels — a room scanned on the phone reaches this Mac that way, and
    /// only that way, since the films left iCloud (2026-09-15). The folder
    /// under `locations/` is where a scan lands on the device that made it,
    /// before the next sync registers it; anything there the film does not
    /// yet name is listed too, so nothing he scanned is ever invisible.
    static func scans(of place: ViewModel.Location, in project: URL) -> [Item] {
        let proxies = project.appendingPathComponent("media", isDirectory: true)
            .appendingPathComponent("proxies", isDirectory: true)
        let stored = { (half: ViewModel.Location.Room.Half) -> URL? in
            let ext = (half.filename as NSString).pathExtension.lowercased()
            let file = proxies.appendingPathComponent(String(half.hash.prefix(32)) + "." + ext)
            return FileManager.default.fileExists(atPath: file.path) ? file : nil
        }
        var items: [Item] = []
        var named: Set<String> = []
        for room in place.scans {
            guard let shape = room.shape.flatMap(stored) else { continue }
            let plan = room.plan.flatMap(stored)
            named.insert(room.name)
            // Its files keep the name they were made with when the room is
            // renamed; the folder's copies are the same room, not another.
            if let file = room.file, !file.isEmpty { named.insert(file) }
            items.append(Item(url: shape, name: room.name, icon: "cube",
                              note: plan == nil ? "the measurements are missing" : nil,
                              measurements: plan,
                              taken: room.taken.flatMap { $0.isEmpty ? nil : $0 },
                              refs: [room.shape?.ref, room.plan?.ref].compactMap { $0 }.filter { !$0.isEmpty }))
        }
        if let dir = folder(of: place, in: project)?
            .appendingPathComponent("scans", isDirectory: true) {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)) ?? []
            for shape in files where shape.pathExtension.lowercased() == "usdz" {
                let name = shape.deletingPathExtension().lastPathComponent
                if named.contains(name) { continue }
                let measured = dir.appendingPathComponent(name + ".json")
                let has = FileManager.default.fileExists(atPath: measured.path)
                items.append(Item(url: shape, name: name, icon: "cube",
                                  note: has ? nil : "the measurements are missing",
                                  measurements: measured))
            }
        }
        return items.sorted { $0.name > $1.name }
    }

    /// One `location.json` as the phone wrote it. **These field names are the
    /// phone's**, agreed in `handoff/from-phone.md`, which is why bringing one
    /// in is a copy rather than a translation.
    struct Captured: Identifiable {
        var folder: String
        var name: String
        var address: String
        var latitude: Double?
        var longitude: Double?
        var notes: String
        var createdAt: String
        var capturedBy: String
        /// Set by the Drive bridge, not by the phone. Carried through so a
        /// rename on the Mac can still find the pictures in Drive.
        var driveFolder: String
        var photographs: [URL]
        var id: String { folder }
    }

    private struct OnDisk: Decodable {
        var id: String
        var name: String
        var address: String?
        var latitude: Double?
        var longitude: Double?
        var notes: String?
        var createdAt: String?
        var capturedBy: String?
        var driveFolder: String?
    }

    /// Every location sitting in the project folder, whether or not it has been
    /// brought in. Reading only — this opens files and closes them.
    static func waiting(in project: URL) -> [Captured] {
        let root = project.appendingPathComponent("locations", isDirectory: true)
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { dir -> Captured? in
            let file = dir.appendingPathComponent("location.json")
            guard let data = try? Data(contentsOf: file),
                  let read = try? JSONDecoder().decode(OnDisk.self, from: data)
            else { return nil }
            let photos = ((try? FileManager.default.contentsOfDirectory(
                at: dir.appendingPathComponent("photos", isDirectory: true),
                includingPropertiesForKeys: nil)) ?? [])
                .filter { !$0.lastPathComponent.hasPrefix(".") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            return Captured(folder: dir.lastPathComponent,
                            name: read.name,
                            address: read.address ?? "",
                            latitude: read.latitude,
                            longitude: read.longitude,
                            notes: read.notes ?? "",
                            createdAt: read.createdAt ?? "",
                            capturedBy: read.capturedBy ?? "iPhone",
                            driveFolder: read.driveFolder ?? "",
                            photographs: photos)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// **The film's papers first, then the folder's** — the same rule as the
    /// scans, for the same reason: a paper pinned on the phone reaches this
    /// Mac as a stored file under its hash, and the folder is only where it
    /// lands on the device that pinned it, before the next sync registers it.
    static func papers(of place: ViewModel.Location, in project: URL) -> [Item] {
        let proxies = project.appendingPathComponent("media", isDirectory: true)
            .appendingPathComponent("proxies", isDirectory: true)
        var items: [Item] = []
        var named: Set<String> = []
        for paper in place.papers {
            let ext = (paper.filename as NSString).pathExtension.lowercased()
            let file = proxies.appendingPathComponent(String(paper.hash.prefix(32)) + "." + ext)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            let shown = paper.filename
            named.insert(shown)
            items.append(Item(url: file, name: shown, icon: "doc", note: nil))
        }
        if let dir = folder(of: place, in: project)?
            .appendingPathComponent("attachments", isDirectory: true) {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)) ?? []
            for file in files where !file.lastPathComponent.hasPrefix(".") {
                let name = file.lastPathComponent
                if named.contains(name) { continue }
                items.append(Item(url: file, name: name, icon: "doc", note: nil))
            }
        }
        return items.sorted { $0.name < $1.name }
    }
}

// MARK: - what came home from the scout

/// **The phone's folder, read in.** Ref 121.
///
/// The iPhone writes each location it captures as
/// `<Project>.shotlist/locations/<uuid>/location.json` with its photographs
/// beside it. That folder is the phone's, not ours — so this reads it, says
/// what it found, and waits. Nothing is imported until somebody presses the
/// button; nothing in the folder is moved, renamed or deleted, ever. Report,
/// never invent, and never destroy.
///
/// A location already brought in carries the folder's name on its record, so
/// the same scout imported twice makes one of everything rather than two.
struct Homecoming: View {
    @ObservedObject var state: ShellState
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }
    @State private var busy = false

    /// This walks the project folder and parses JSON, so it is read on a
    /// change rather than inside the body — see `FilesCard.reread`.
    @State private var waiting: [Scout.Captured] = []

    private func reread() { waiting = Scout.unclaimed(state: state) }

    var body: some View {
        scouts
        .onAppear(perform: reread)
        .onChange(of: (state.view?.locations ?? []).count) { _, _ in reread() }
    }

    // **The "N new photographs in the project folder" banner is gone.**
    //
    // It offered any picture sitting in `locations/<folder>/photos/` that the
    // engine did not have, so that photographs arriving through Google Drive
    // would show up. Two things happened to make that actively harmful:
    //
    // 1. **The phone stopped writing photographs there.** They are engine
    //    records now, and the Drive bridge imports Drive's pictures into the
    //    engine itself. So the folder holds one morning's scaffolding and
    //    nothing that will ever be new again.
    // 2. **It could not tell "never seen" from "deliberately deleted".** He
    //    deleted every photograph on a location; the bridge carried the
    //    deletion to Drive; and then this banner offered to put the same three
    //    back, from files nobody had cleaned up. Adding them re-exported them
    //    to Drive, which is the app arguing with a person about something they
    //    had just decided.
    //
    // Report, never invent — and *never resurrect*. A thing offered again after
    // it was thrown away is not an offer, it is a disagreement.

    @ViewBuilder private var scouts: some View {
        let found = waiting
        if !found.isEmpty {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(found.count == 1
                         ? "1 location came home from your iPhone"
                         : "\(found.count) locations came home from your iPhone")
                        .sans(13, weight: .semibold).foregroundStyle(Brand.ink(dark))
                    Text(found.map(\.name).joined(separator: " · "))
                        .sans(11).foregroundStyle(Brand.ink3(dark))
                        .lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 0)
                Button(busy ? "Bringing them in…" : "Bring them in") {
                    bring(found)
                    reread()
                }
                    .buttonStyle(.primary)
                    .disabled(busy)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Brand.accentTint(dark))
            .overlay(alignment: .bottom) { Brand.rule(dark).frame(height: 1) }
        }
    }

    private func bring(_ found: [Scout.Captured]) {
        busy = true
        defer { busy = false }
        Scout.bring(found, state: state)
    }
}

extension Scout {
    /// Everything `waiting` found, made into records. Held here rather than
    /// inside the banner so a checking run can drive it: a button nothing can
    /// press is a feature nothing can check.
    static func bring(_ found: [Captured], state: ShellState) {
        guard let engine = state.engine else { return }
        for one in found {
            let before = Set((state.view?.locations ?? []).map(\.id))
            state.replace(engine.addLocation(name: one.name.isEmpty ? "Untitled" : one.name))
            guard let fresh = (state.view?.locations ?? [])
                .first(where: { !before.contains($0.id) }) else { continue }
            // The folder first: if anything below fails, the record still
            // knows where it came from and the same scout is not offered twice.
            state.replace(engine.setLocation(fresh.id, "folder", one.folder))
            state.replace(engine.setLocation(fresh.id, "address", one.address))
            if let lat = one.latitude, let lon = one.longitude {
                state.replace(engine.setLocation(fresh.id, "latitude", String(lat)))
                state.replace(engine.setLocation(fresh.id, "longitude", String(lon)))
            }
            state.replace(engine.setLocation(fresh.id, "notes", one.notes))
            state.replace(engine.setLocation(fresh.id, "capturedBy", one.capturedBy))
            state.replace(engine.setLocation(fresh.id, "createdAt", one.createdAt))
            // **The Drive pairing, carried across.** Without it a rename here
            // would look to the bridge like a location it has never seen, and
            // leave the photographs in a Drive folder called the old name.
            state.replace(engine.setLocation(fresh.id, "driveFolder", one.driveFolder))
            // **Photographs are copied, not moved.** The phone's folder is the
            // phone's; the engine keeps its own copy under the picture's hash,
            // which is also why importing twice cannot double the storage.
            for picture in one.photographs {
                Attachments.add(url: picture, ownedBy: fresh.id, state: state)
            }
            state.locationId = fresh.id
        }
    }

    /// **Where a photograph actually is on this Mac**, by name, for the places
    /// worth being shown: the folder the phone wrote it into, if it is still
    /// there, and the Google Drive folder the bridge mirrors it to.
    ///
    /// Both are looked for rather than assumed, and anything missing is simply
    /// not offered — a menu item that reveals nothing is worse than no item.
    /// The engine's own copy is deliberately not on this list: it is filed under
    /// the hash of its contents, and being shown `9348d131….jpg` answers
    /// nothing a person was asking.
    static func homes(of photo: ViewModel.Attachment, at place: ViewModel.Location,
                      state: ShellState) -> [Viewer.Place] {
        var found: [Viewer.Place] = []
        // The same fallback as `folder(of:in:)` above — Ref 305.
        let named = FileNames.locationFolder(id: place.id, folder: place.folder)
        if let project = state.projectPath, !named.isEmpty {
            let here = project.appendingPathComponent("locations", isDirectory: true)
                .appendingPathComponent(named, isDirectory: true)
                .appendingPathComponent("photos", isDirectory: true)
                .appendingPathComponent(photo.filename)
            if FileManager.default.fileExists(atPath: here.path) {
                found.append(Viewer.Place(label: "the project folder", url: here))
            }
        }
        if let drive = driveHome(of: place, state: state) {
            let there = drive.appendingPathComponent(photo.filename)
            found.append(Viewer.Place(
                label: "Google Drive",
                url: FileManager.default.fileExists(atPath: there.path) ? there : drive))
        }
        return found
    }

    /// The location's folder in Google Drive.
    ///
    /// **Walked, not composed.** The bridge finds a project's logistics folder
    /// and its locations folder by looking for a name that *contains* the word —
    /// because every project on his Drive names them differently
    /// (`daybreak-dp-locations`, `DEMO - Location Photos`, `Locations`). Writing
    /// a fixed path here would work on one project and quietly fail on the rest.
    /// This is `bridge/Sources/main.swift`'s own arithmetic, read off it.
    static func driveHome(of place: ViewModel.Location, state: ShellState) -> URL? {
        guard !place.driveFolder.isEmpty, let project = state.projectPath else { return nil }
        let slug = project.deletingPathExtension().lastPathComponent
            .lowercased().replacingOccurrences(of: " ", with: "-")
        let fm = FileManager.default
        let cloud = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/CloudStorage", isDirectory: true)
        guard let mounts = try? fm.contentsOfDirectory(at: cloud, includingPropertiesForKeys: nil)
        else { return nil }
        for mount in mounts where mount.lastPathComponent.hasPrefix("GoogleDrive-") {
            let here = mount.appendingPathComponent("My Drive/cinematography/projects",
                                                    isDirectory: true)
                .appendingPathComponent(slug, isDirectory: true)
            guard fm.fileExists(atPath: here.path),
                  let inside = try? fm.contentsOfDirectory(at: here,
                                                           includingPropertiesForKeys: nil),
                  let logistics = inside.first(where: {
                      $0.lastPathComponent.lowercased().contains("logistic")
                  }),
                  let under = try? fm.contentsOfDirectory(at: logistics,
                                                          includingPropertiesForKeys: nil),
                  let locations = under.first(where: {
                      $0.lastPathComponent.lowercased().contains("location")
                  })
            else { continue }
            // **`driveFolder` is a path now, not a name** — a room's is
            // `House/Kitchen` since Ref 269 put rooms inside their house's
            // folder in Drive. Walked component by component rather than
            // handed over whole, because a path component containing a slash
            // is not a component.
            var home = locations
            for step in place.driveFolder.split(separator: "/") {
                home = home.appendingPathComponent(String(step), isDirectory: true)
            }
            if home != locations, fm.fileExists(atPath: home.path) { return home }
        }
        return nil
    }

    /// The ones not brought in yet, which is what the banner counts.
    ///
    /// **Matched by folder and by name** — Ref 264. Nothing has written a
    /// `location.json` since locations moved into the engine, so every one of
    /// them is now a snapshot of how things stood that day: Daybreak's *The
    /// Office* has coordinates two decimal places off what the engine holds.
    /// Harmless while nothing reads them, and it stops being harmless the
    /// moment one is offered as new — because bringing it in would make a
    /// second location with the same name and the *older* address.
    ///
    /// The folder match catches anything the phone brought home. The name
    /// match catches the rest: a location made on the Mac has no folder at
    /// all, so it can never match one, and a stale sidecar beside it would be
    /// offered forever.
    ///
    /// **The files are left where they are.** Deleting anything is a person's
    /// decision, and a folder in a project also holds the scans and the
    /// photographs, which are not ours to sweep up.
    static func unclaimed(state: ShellState) -> [Captured] {
        guard let project = state.projectPath else { return [] }
        let here = state.view?.locations ?? []
        let folders = Set(here.map(\.folder).filter { !$0.isEmpty })
        let names = Set(here.map { $0.name.lowercased() }.filter { !$0.isEmpty })
        return waiting(in: project).filter {
            !folders.contains($0.folder) && !names.contains($0.name.lowercased())
        }
    }
}

// MARK: - shooting a scene here

/// Point scenes at this location, from the location's side.
///
/// A searchable list rather than a menu, for the reason he gave about moving
/// shots: *"if there's hundreds of scenes in a film, that list is going to get
/// insane."*
struct LinkScenes: View {
    @ObservedObject var state: ShellState
    let place: ViewModel.Location
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var looking = ""
    private var dark: Bool { scheme == .dark }

    private var scenes: [ViewModel.Scene] {
        let live = (state.view?.scenes ?? []).filter { !$0.archived }
        let q = looking.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return live }
        return live.filter {
            $0.number.lowercased().contains(q) || $0.heading.lowercased().contains(q)
                || $0.location.lowercased().contains(q)
        }
    }

    var body: some View {
        Sheet(title: "Scenes at “\(place.name)”", width: .narrow, height: 420, scrolls: false) {
            VStack(spacing: 0) {
                SearchField(placeholder: "Find a scene", text: $looking)
                    .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
                List {
                    ForEach(scenes) { sc in
                        Button { toggle(sc) } label: {
                            HStack(spacing: 8) {
                                // A tick carries a fact, so it stays.
                                Image(systemName: here(sc) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(here(sc) ? Brand.accent(dark) : Brand.ink4(dark))
                                Text(sc.number).sans(Brand.Size.small, weight: .semibold)
                                    .monospacedDigit()
                                    .foregroundStyle(Brand.ink(dark))
                                    .frame(minWidth: 26, alignment: .trailing)
                                Text(sc.heading).sans(Brand.Size.small)
                                    .foregroundStyle(Brand.ink2(dark)).lineLimit(1)
                                Spacer(minLength: 0)
                                // Said plainly rather than silently overwritten:
                                // picking this one takes it off the other.
                                if let other = elsewhere(sc) {
                                    Text(other).sans(Brand.Size.tiny)
                                        .foregroundStyle(Brand.ink4(dark))
                                        .lineLimit(1)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        } trailing: {
            Button("Done") { dismiss() }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func here(_ scene: ViewModel.Scene) -> Bool {
        scene.locations.contains(place.id)
    }

    /// The other places this scene is shot at, named — so a scene picked up
    /// here says where else the crew is taking it.
    private func elsewhere(_ scene: ViewModel.Scene) -> String? {
        let others = scene.locations.filter { $0 != place.id }
        guard !others.isEmpty else { return nil }
        let names = (state.view?.locations ?? [])
            .filter { others.contains($0.id) }
            .map(\.name)
        return names.isEmpty ? nil : names.joined(separator: " · ")
    }

    /// **Adds and removes rather than replaces** — a scene can be shot at more
    /// than one place, so ticking this one must not silently drop the others.
    private func toggle(_ scene: ViewModel.Scene) {
        guard let engine = state.engine else { return }
        state.replace(here(scene)
                      ? engine.removeSceneLocation(scene.id, place.id)
                      : engine.addSceneLocation(scene.id, place.id))
    }
}

// MARK: - finding the address

/// The map sheet: type a street, pick the answer, save it.
///
/// Cadrage gives this the whole window; here it is a sheet, because the window
/// behind it is the location it is about and losing sight of that is how you
/// save an address onto the wrong place.
struct AddressFinder: View {
    @ObservedObject var state: ShellState
    let place: ViewModel.Location
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    @StateObject private var lookup = AddressLookup()
    @State private var typed = ""
    @State private var chosen: CLLocationCoordinate2D?
    @State private var written = ""
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 34.05, longitude: -118.24),
                           span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4)))

    var body: some View {
        VStack(spacing: 0) {
            field
            ZStack(alignment: .top) {
                map
                if !lookup.suggestions.isEmpty { results }
            }
            foot
        }
        .frame(width: 620, height: 520)
        .background(Brand.panel(dark))
        .onAppear(perform: start)
    }

    // ------------------------------------------------------------- the field

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 11))
                .foregroundStyle(Brand.ink3(dark))
            TextField("Search an address", text: $typed)
                .textFieldStyle(.plain)
                .sans(13)
                .onChange(of: typed) { _, fresh in lookup.look(for: fresh) }
            if !typed.isEmpty {
                Button {
                    typed = ""
                    lookup.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                        .foregroundStyle(Brand.ink4(dark))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Brand.surface(dark))
        .overlay(alignment: .bottom) { Brand.rule(dark).frame(height: 1) }
    }

    // -------------------------------------------------------- what it found

    private var results: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(lookup.suggestions.enumerated()), id: \.offset) { _, answer in
                    Button { take(answer) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(answer.title).sans(13, weight: .medium)
                                .foregroundStyle(Brand.ink(dark))
                            if !answer.subtitle.isEmpty {
                                Text(answer.subtitle).sans(10)
                                    .foregroundStyle(Brand.ink3(dark))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Brand.rule(dark).frame(height: 1)
                }
            }
        }
        .frame(maxHeight: 230)
        .background(Brand.menu(dark))
        .card(dark, radius: 10)
        .padding(.horizontal, 40)
        .padding(.top, 8)
    }

    // --------------------------------------------------------------- the map

    private var map: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if let chosen {
                    Marker(place.name.isEmpty ? "Here" : place.name, coordinate: chosen)
                        .tint(.red)
                }
            }
            // **Click the map to drop the pin.** Half the locations on a scout
            // are a field with no address at all, and a search box alone cannot
            // record one of those.
            .onTapGesture { point in
                guard let where_ = proxy.convert(point, from: .local) else { return }
                chosen = where_
                Task {
                    written = await AddressLookup.address(at: where_) ?? ""
                    if written.isEmpty { written = Self.degrees(where_) }
                }
            }
        }
    }

    // -------------------------------------------------------------- the foot

    private var foot: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if chosen == nil {
                    Text("Click the map to drop a pin")
                        .sans(11).foregroundStyle(Brand.ink3(dark))
                } else {
                    Text(written.isEmpty ? "A pin with no address" : written)
                        .sans(13).foregroundStyle(Brand.ink(dark))
                        .fixedSize(horizontal: false, vertical: true)
                    if let chosen {
                        Text(Self.degrees(chosen)).sans(Brand.Size.tiny).monospacedDigit()
                            .foregroundStyle(Brand.ink4(dark))
                    }
                }
            }
            Spacer(minLength: 0)
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Save", action: save)
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .disabled(chosen == nil)
        }
        .buttonStyle(.capsule)
        .padding(14)
        .background(Brand.surface(dark))
        .overlay(alignment: .top) { Brand.rule(dark).frame(height: 1) }
    }

    // ------------------------------------------------------------- behaviour

    private func start() {
        written = place.address
        if let pin = place.pin {
            chosen = pin
            camera = .region(MKCoordinateRegion(
                center: pin,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
        } else if !place.address.isEmpty {
            // A location the phone typed an address onto without a pin: start
            // the search from what it already says rather than from nothing.
            typed = place.address.replacingOccurrences(of: "\n", with: ", ")
            lookup.look(for: typed)
        }
    }

    private func take(_ answer: AddressLookup.Answer) {
        Task {
            guard let found = await lookup.resolve(answer) else { return }
            written = found.address
            chosen = found.coordinate
            typed = ""
            lookup.clear()
            camera = .region(MKCoordinateRegion(
                center: found.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)))
        }
    }

    private func save() {
        guard let engine = state.engine, let chosen else { return }
        state.replace(engine.setLocation(place.id, "address", written))
        state.replace(engine.setLocation(place.id, "latitude", String(chosen.latitude)))
        state.replace(engine.setLocation(place.id, "longitude", String(chosen.longitude)))
        dismiss()
    }

    /// Degrees, as a call sheet writes them.
    static func degrees(_ at: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", at.latitude, at.longitude)
    }
}

/// Address suggestions, as he types — Apple's own completer, the one Maps uses.
///
/// **The phone has one of these too** (`phone/Sources/AddressLookup.swift`), and
/// this is deliberately a second copy rather than a shared file: `phone/` is
/// another thread's path and the two targets share no source folder yet. Noted
/// in the outbox as the first real candidate for one.
@MainActor
final class AddressLookup: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {

    /// One row in the list. Apple answers an address in two different ways and
    /// they do not know the same places, so a row is either.
    enum Answer {
        case suggested(MKLocalSearchCompletion)
        case found(MKMapItem)

        var title: String {
            switch self {
            case .suggested(let it): return it.title
            case .found(let it): return it.name ?? (it.placemark.title ?? "")
            }
        }

        var subtitle: String {
            switch self {
            case .suggested(let it): return it.subtitle
            case .found(let it):
                let mark = it.placemark
                let town = [mark.locality, mark.administrativeArea]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
                return [town, mark.postalCode].compactMap { $0 }
                    .filter { !$0.isEmpty }.joined(separator: " ")
            }
        }
    }

    @Published private(set) var suggestions: [Answer] = []
    private let completer = MKLocalSearchCompleter()

    /// What he has typed, and the outright search waiting on it. See `search`.
    private var asked = ""
    private var searching: Task<Void, Never>?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func look(for text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        asked = trimmed
        searching?.cancel()
        guard trimmed.count >= 3 else {
            suggestions = []
            return
        }
        completer.queryFragment = trimmed
    }

    func clear() {
        searching?.cancel()
        asked = ""
        suggestions = []
        completer.queryFragment = ""
    }

    /// A suggestion carries only text, so the coordinate has to be asked for.
    func resolve(_ answer: Answer)
        async -> (address: String, coordinate: CLLocationCoordinate2D)? {
        switch answer {
        case .found(let item):
            return (Self.write(item), item.placemark.coordinate)
        case .suggested(let completion):
            let request = MKLocalSearch.Request(completion: completion)
            guard let response = try? await MKLocalSearch(request: request).start(),
                  let item = response.mapItems.first else { return nil }
            return (Self.write(item), item.placemark.coordinate)
        }
    }

    /// **Autocomplete does not know every house on a street it knows.**
    /// `2514 Cayman Rd, Malibu` — a real location he was scouting — returns
    /// nothing from the completer, which has `Cayman Road, Malibu` and has
    /// `2514 Cayman Rd` in five other towns, but not the two together. Search
    /// the words outright and it comes back first time, which is what the Maps
    /// app does when its own suggestions run dry. Remote addresses are exactly
    /// the ones a scout has, so an empty list here is not an answer.
    private func search() {
        searching?.cancel()
        let text = asked
        guard text.count >= 3 else { return }
        searching = Task { [weak self] in
            // Let him finish the word before spending a search on it.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = text
            let response = try? await MKLocalSearch(request: request).start()
            guard !Task.isCancelled, let self, self.asked == text else { return }
            self.suggestions = (response?.mapItems ?? []).prefix(8).map { .found($0) }
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let found = completer.results
        Task { @MainActor in
            if found.isEmpty {
                self.search()
            } else {
                self.searching?.cancel()
                self.suggestions = found.map { .suggested($0) }
            }
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter,
                               didFailWithError error: Error) {
        Task { @MainActor in
            self.suggestions = []
            self.search()
        }
    }

    /// An address written the way a call sheet writes one. A place with a name
    /// keeps it on the first line: somewhere like Balboa Park has no street
    /// number at all, and reducing it to "San Diego CA" throws away the only
    /// part that says which place it is.
    static func write(_ item: MKMapItem) -> String {
        let street = write(item.placemark) ?? ""
        guard let name = item.name, !name.isEmpty else { return street }
        if street.hasPrefix(name)
            || name.hasPrefix(street.components(separatedBy: "\n").first ?? "") {
            return street.isEmpty ? name : street
        }
        return street.isEmpty ? name : name + "\n" + street
    }

    static func write(_ placemark: CLPlacemark) -> String? {
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0 }.joined(separator: " ")
        let town = [placemark.locality, placemark.administrativeArea]
            .compactMap { $0 }.joined(separator: " ")
        let lines = [street,
                     [town, placemark.postalCode].compactMap { $0 }
                        .filter { !$0.isEmpty }.joined(separator: " ")]
            .filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// What address a coordinate is at, so a dropped pin fills its own field in.
    static func address(at coordinate: CLLocationCoordinate2D) async -> String? {
        let point = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(point).first
        else { return nil }
        return write(placemark)
    }
}

// MARK: - a field that writes when the pen goes down

/// One line of text that commits on Return and on losing the keyboard, and puts
/// back what the record holds on Escape.
///
/// Written rather than reused because `HeaderField` is a *scene header* line —
/// fixed width, one small size, its own hover treatment. This one has to be a
/// title.
struct CommittingField: View {
    let text: String
    let ghost: String
    let font: Font
    let dark: Bool
    let onCommit: (String) -> Void

    @State private var value = ""
    @FocusState private var typing: Bool

    var body: some View {
        TextField(ghost, text: $value)
            .textFieldStyle(.plain)
            .font(font)
            .foregroundStyle(Brand.ink(dark))
            .focused($typing)
            .onAppear { value = text }
            .onChange(of: text) { _, fresh in
                if !typing { value = fresh }
            }
            .onSubmit {
                onCommit(value.trimmingCharacters(in: .whitespaces))
                typing = false
            }
            .onChange(of: typing) { _, nowTyping in
                guard !nowTyping else { return }
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                if trimmed != text { onCommit(trimmed) }
            }
            .onExitCommand { value = text; typing = false }
    }
}
