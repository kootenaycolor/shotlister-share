import SwiftUI
import PhotosUI
import MapKit
import CoreLocation
import UniformTypeIdentifiers

/// One location, laid out the way his Cadrage references lay one out: what this
/// place is, how to get back to it, what was said about it, its shape, its
/// paperwork, and what it looks like.
///
/// **It is an engine record now.** The name, the address, the notes and the
/// photographs are all held by the engine and merge across devices like every
/// other fact in the project. Only the scans and the papers are still files —
/// his ruling, and the right one: a forty-megabyte room does not belong inside a
/// change log.
struct LocationDetailView: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var frames: Frames
    @StateObject private var whereabouts = Whereabouts()
    @StateObject private var lookup = AddressLookup()

    let id: String

    @State private var scanning = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var pickingFromLibrary = false
    @State private var takingPhoto = false
    @State private var importing = false
    @State private var fromProject = false
    @State private var viewing: ScanViewer.Opening?
    @State private var browsing: Engine.Still?
    @State private var renaming: Session.Room?
    @State private var newName = ""
    @State private var trouble: String?

    /// Typed here and written as it changes, so the cursor is not fighting the
    /// engine's answer coming back on every keystroke.
    @State private var name = ""
    @State private var address = ""
    @State private var notes = ""
    @State private var loaded = ""
    /// Which field he is typing into, so its own answer is never yanked out
    /// from under him.
    @FocusState private var editing: String?

    @FocusState private var typingAddress: Bool
    @State private var addingRoom = false
    @State private var newRoom = ""
    @State private var camera: MapCameraPosition = .automatic
    /// The full-screen map a pin is dropped on (the Mac clicks its map).
    @State private var droppingPin = false
    @State private var linkingScenes = false
    @State private var openScene: Engine.Scene?
    @AppStorage("media.cropToSquare") private var cropToSquare = true
    /// Held here rather than inside the gallery: this screen rebuilds on every
    /// answer the engine gives back, and a selection that lived in the gallery
    /// was being thrown away and duplicated.
    @StateObject private var gallery = GallerySelection()

    private var place: Engine.Location? { session.location(id) }

    var body: some View {
        Group {
            if let place {
                // **His order, 2026-08-22.** Name, address, pictures, scans,
                // papers, notes — the things he needs standing in a doorway
                // first, and the writing last.
                Form {
                    Section {
                        TextField("Name", text: $name)
                            .focused($editing, equals: "name")
                            .onChange(of: name) { _, new in session.setLocation(id, "name", to: new) }
                    } header: {
                        FormHead("Name")
                    }
                    // **A room has no address of its own — it shares the
                    // house's.** His rule, and the engine already worked this
                    // way: `location_address` answers with the house's when the
                    // room says nothing. Drawing an empty address field on a
                    // room invited him to type the same street into seven
                    // rooms and made seven records that can disagree.
                    if !place.isArea {
                        Section { addressSection(place) } header: { FormHead("Address") }
                    }
                    roomsSection(place)
                    scenesSection(place)
                    mediaSection(place)
                    scansSection(place)
                    attachmentsSection(place)
                    // **A room shows its house's notes** (the Mac's rail),
                    // read here, written on the house.
                    if place.isArea, let house = session.locations.first(where: { $0.id == place.parent }),
                       !house.notes.isEmpty {
                        Section {
                            Text(house.notes).foregroundStyle(.secondary)
                        } header: {
                            FormHead("\(house.name) Notes")
                        }
                    }
                    Section {
                        TextField("Add a note", text: $notes, axis: .vertical)
                            .lineLimit(3...12)
                            .focused($editing, equals: "notes")
                            .onChange(of: notes) { _, new in session.setLocation(id, "notes", to: new) }
                    } header: {
                        FormHead("Notes")
                    }
                }
                // **The one-app look** (Ref 1582): the grey page, white cards,
                // each section named in bold black over its card.
                .scrollContentBackground(.hidden)
                .background(Style.page)
                .listSectionSpacing(14)
            } else {
                ContentUnavailableView("This location is gone", systemImage: "mappin.slash")
            }
        }
        .navigationTitle(name.isEmpty ? "Location" : name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $droppingPin) {
            PinDrop(start: place?.coordinate) { coordinate in
                droppingPin = false
                guard let coordinate else { return }
                session.setLocation(id, "latitude", to: String(coordinate.latitude))
                session.setLocation(id, "longitude", to: String(coordinate.longitude))
                Task {
                    guard let written = await AddressLookup.address(at: coordinate) else { return }
                    address = written
                    session.setLocation(id, "address", to: written)
                    lookup.clear()
                }
            }
        }
        .sheet(item: $openScene) { scene in
            NavigationStack { SceneDetailView(id: scene.id) }.environmentObject(session)
        }
        .sheet(isPresented: $linkingScenes) {
            SceneLinker(place: id).environmentObject(session)
        }
        // **Where a place's settings go**, as opposed to its facts. The page
        // is the facts — the name, the address, the rooms, the pictures, the
        // scans, the notes — and a setting he flips once does not belong in
        // that column taking a line of its own. A mood board's ⋯ is the same
        // menu doing the same job.
        .toolbar {
            if let place {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        driveItem(place)
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .task { load() }
        // **Take up the engine's answer when it changes.**
        //
        // These three are held locally while he types — reading them back
        // mid-keystroke would fight the cursor — and they were *only* ever read
        // when the screen opened. So an address changed on the Mac never
        // arrived, the phone went on showing the one it had, and the next
        // keystroke wrote the stale one back over it. Two devices, two
        // addresses, and the phone winning.
        //
        // Not while the field has focus: that is the case the local copy exists
        // for.
        .onChange(of: mirror) { _, _ in adopt() }
        .fullScreenCover(isPresented: $takingPhoto) {
            CameraCapture { image in session.attach(image, toLocation: id) }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $scanning) { scanner }
        .alert("New Room", isPresented: $addingRoom) {
            TextField("Name", text: $newRoom)
            Button("Cancel", role: .cancel) { newRoom = "" }
            Button("Add") {
                let named = newRoom.trimmingCharacters(in: .whitespacesAndNewlines)
                newRoom = ""
                guard !named.isEmpty else { return }
                if let made = session.addRoom(inside: id, named: named) {
                    session.store.prepare(made.home)
                }
            }
        }
        .navigationDestination(for: Engine.Location.self) { room in
            LocationDetailView(id: room.id).environmentObject(session)
        }
        .fullScreenCover(item: $viewing) { opening in
            ScanViewer(usdz: opening.usdz, json: opening.json, title: opening.title)
                .environmentObject(session)
        }
        .fullScreenCover(item: $browsing) { still in
            StillViewer(still: still, all: place?.photos ?? [],
                        onDelete: { session.detach($0) },
                        cropTo: cropToSquare ? 1 : session.ratio)
                .environmentObject(session)
                .environmentObject(frames)
        }
        .sheet(isPresented: $fromProject) { FromProjectPicker(owner: id).environmentObject(session) }
        .photosPicker(isPresented: $pickingFromLibrary, selection: $picked,
                      matching: .any(of: [.images, .videos]))
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            bringIn(files: result)
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task { await bringIn(items) }
        }
        .alert("Rename Scan", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") { finishRename() }
        }
        .alert("That didn't work", isPresented: .constant(trouble != nil)) {
            Button("OK") { trouble = nil }
        } message: {
            Text(trouble ?? "")
        }
    }

    // ---- address ------------------------------------------------------------

    @ViewBuilder
    private func addressSection(_ place: Engine.Location) -> some View {
        HStack(spacing: 8) {
            TextField("Search an address", text: $address, axis: .vertical)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($typingAddress)
                .onChange(of: address) { _, text in
                    session.setLocation(id, "address", to: text)
                    guard typingAddress else { return }
                    lookup.look(for: text)
                }
                .onChange(of: typingAddress) { _, focused in if !focused { lookup.clear() } }

            Button { droppingPin = true } label: {
                Image(systemName: "mappin.circle").font(.kitHeading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityLabel("Drop Pin")

            Button { useCurrentLocation() } label: {
                if whereabouts.isAsking {
                    ProgressView()
                } else {
                    Image(systemName: "location.circle.fill").font(.kitHeading)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .disabled(whereabouts.isAsking)
            .accessibilityLabel("Current Location")
        }

        if typingAddress && !lookup.suggestions.isEmpty {
            ForEach(lookup.suggestions, id: \.self) { suggestion in
                Button { take(suggestion) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.circle").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(suggestion.title).font(.kitRow)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle).font(.kitLabel).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }

        if whereabouts.refused {
            Text("Location Services Off")
                .font(.kitLabel).foregroundStyle(.secondary)
        }

        if let coordinate = place.coordinate {
            Map(position: $camera) { Marker(place.name, coordinate: coordinate) }
                .frame(height: 150)
                .listRowInsets(EdgeInsets())
                .allowsHitTesting(false)
                .onChange(of: place.latitude) { _, _ in look(at: coordinate) }
                .onAppear { look(at: coordinate) }

            LabeledContent("Coordinates") {
                Text(degrees(coordinate)).font(.kitLabel.monospacedDigit())
            }
            Button { directions(to: coordinate, named: place.name) } label: {
                Label("Get Directions", systemImage: "arrow.triangle.turn.up.right.circle")
            }
        }
    }

    /// **The scenes shot here** (the Mac's scenes menu on a place): this
    /// place's and its rooms', each opening the scene; Link Scenes… to add
    /// or take one off from this side.
    @ViewBuilder
    private func scenesSection(_ place: Engine.Location) -> some View {
        let ids = Set([place.id] + session.rooms(of: place.id).map(\.id))
        let here = session.scenes.filter { !ids.isDisjoint(with: $0.locations) }
        Section {
            ForEach(here) { scene in
                Button { openScene = scene } label: {
                    HStack(spacing: 10) {
                        Text(scene.number).font(.subheadline.weight(.bold).monospacedDigit())
                        Text(session.isCommercial && !scene.title.isEmpty ? scene.title : scene.heading)
                            .font(.subheadline).lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right").font(.kitLabel).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if here.isEmpty {
                Text("No scenes").foregroundStyle(.secondary)
            }
        } header: {
            FormHead("Scenes") {
                Button { linkingScenes = true } label: { Image(systemName: "link") }
                    .accessibilityLabel("Link Scenes")
            }
        }
    }

    /// The rooms inside this place, and the way to make another.
    ///
    /// Only on a place that stands on its own: the engine allows one level and
    /// no more, so a room has no rooms.
    @ViewBuilder
    private func roomsSection(_ place: Engine.Location) -> some View {
        if !place.isArea {
            let rooms = session.rooms(of: place.id)
            Section {
                ForEach(rooms) { room in
                    NavigationLink(value: room) { RoomRow(room: room) }
                        // The Mac's Delete and Move out, on a room too.
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { session.deleteLocation(room.id) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button { session.moveLocation(room.id, into: "") } label: {
                                Label("Move Out", systemImage: "arrow.up.forward.square")
                            }
                            .tint(.indigo)
                        }
                }
                if rooms.isEmpty {
                    Text("No rooms yet").font(.system(size: 15)).foregroundStyle(Style.ink3)
                }
            } header: {
                FormHead("Rooms") {
                    Button { newRoom = ""; addingRoom = true } label: { SoftRoundLabel(symbol: "plus") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add Room")
                }
            }
        }
    }

    // ---- the room -----------------------------------------------------------

    private func scansSection(_ place: Engine.Location) -> some View {
        let scans = session.rooms(of: place)
        let folder = session.store.scansFolder(place.home)
        return Section {
            ForEach(scans) { scan in
                Button {
                    // A room whose bytes have not come down yet opens as
                    // nothing rather than not at all; the viewer says so.
                    viewing = .init(usdz: scan.usdz ?? folder.appendingPathComponent(scan.name + ".usdz"),
                                    json: scan.json ?? folder.appendingPathComponent(scan.name + ".json"),
                                    title: scan.name)
                } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: Style.Radius.frame, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                            .frame(width: 44, height: 44)
                            .overlay {
                                Image(systemName: "cube.transparent")
                                    .font(.system(size: 20)).foregroundStyle(Style.ink3)
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(scan.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                            Text(!scan.isMeasured ? "Shape only · no floor plan"
                                 : scan.taken.isEmpty ? "Shape and measurements" : scan.taken)
                                .font(.system(size: 13))
                                .foregroundStyle(scan.isMeasured ? AnyShapeStyle(.secondary)
                                                                 : AnyShapeStyle(Color.orange))
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if let usdz = scan.usdz { ShareLink("Share", item: usdz) }
                    Button { newName = scan.name; renaming = scan } label: {
                        Label("Rename…", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        do { try session.delete(room: scan, in: place) } catch { trouble = error.localizedDescription }
                        session.refresh()
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
            if scans.isEmpty {
                Text(RoomScanner.isSupported ? "Nothing scanned"
                                             : "This iPhone has no LiDAR")
                    .font(.system(size: 15)).foregroundStyle(Style.ink3)
            }
            stranded(place)
        } header: {
            FormHead("3D Scans") {
                if RoomScanner.isSupported {
                    Button { scanning = true } label: { SoftRoundLabel(symbol: "plus") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Scan Room")
                }
            }
        }
    }

    /// Scans that were taken before a place had a folder to keep them in.
    ///
    /// They are on the disk and perfectly good; nothing records which room each
    /// one was taken in, because the folder *was* that record. So they are
    /// offered here rather than filed by guesswork. The heading names them and
    /// the button beside each says the verb; nothing narrates.
    @ViewBuilder
    private func stranded(_ place: Engine.Location) -> some View {
        let loose = session.store.stranded()
        if !loose.isEmpty {
            Text("Not in a Room")
                .font(.kitLabel).foregroundStyle(.secondary)
            ForEach(loose) { scan in
                HStack(spacing: 12) {
                    Image(systemName: "cube.transparent")
                        .font(.title3).foregroundStyle(.orange).frame(width: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(scan.name).font(.kitRow).lineLimit(1)
                        Text(scan.made.formatted(date: .abbreviated, time: .shortened))
                            .font(.kitLabel).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Move Here") {
                        do { try session.store.adopt(scan, into: place.home) }
                        catch { trouble = error.localizedDescription }
                        session.registerScans()
                        session.refresh()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    /// **Sync with Drive** — Ref 229/343.
    ///
    /// **In the ⋯, not on the page.** It had a section of its own, headed
    /// *Google Drive*, and he was right that it did not earn one: *"small
    /// things like that could be in a ⋯ menu or something? Not a whole
    /// line?"* (2026-08-30). It is a setting you touch once and never look at
    /// again, sitting under the name, the address and the photographs — the
    /// things you are holding the phone to see. A mood board already keeps
    /// its own copy of this switch in exactly that place, so this is the two
    /// screens agreeing rather than a new idea.
    ///
    /// **A switch that cannot do anything does not move.** The film has to
    /// carry a Drive folder — set on the Mac — before any of it means a
    /// thing. Greyed out is the whole of what the menu can say; the sentence
    /// that used to explain it was the section's footer and went with the
    /// section. The Mac's card still says it in words, which is where he sets
    /// the folder anyway.
    @ViewBuilder
    private func driveItem(_ place: Engine.Location) -> some View {
        Toggle("Sync with Drive", isOn: Binding(
            get: { place.syncsWithDrive },
            set: { session.setLocation(id, "syncWithDrive", to: $0 ? "1" : "0") }
        ))
        .disabled(!filmIsLinked)
    }

    private var filmIsLinked: Bool {
        !(session.view?.project.driveFolder ?? "")
            .trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func attachmentsSection(_ place: Engine.Location) -> some View {
        let papers = session.papers(of: place)
        return Section {
            ForEach(papers, id: \.self) { paper in
                ShareLink(item: paper.url) {
                    Label(paper.name, systemImage: "doc").lineLimit(1)
                }
            }
            if papers.isEmpty {
                Text("Nothing attached")
                    .font(.system(size: 15)).foregroundStyle(Style.ink3)
            }
        } header: {
            FormHead("Attachments") {
                Button { importing = true } label: { SoftRoundLabel(symbol: "plus") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Attach File")
            }
        }
    }

    private func mediaSection(_ place: Engine.Location) -> some View {
        Section {
            if !place.photos.isEmpty {
                MediaGallery(
                    media: place.photos,
                    selection: gallery,
                    onOpen: { browsing = $0 },
                    onRemove: { chosen in chosen.forEach(session.detach) },
                    onMove: { still, index in session.move(still, to: index) }
                )
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
            } else {
                // A header with two buttons and nothing under it reads as a
                // section that failed to load. One line, and it stops.
                Text("No photos yet").font(.system(size: 15)).foregroundStyle(Style.ink3)
            }
        } header: {
            FormHead("Media") {
                Menu {
                    Picker("Image Crop", selection: $cropToSquare) {
                        Text("Crop to Square").tag(true)
                        Text("Original Aspect Ratio").tag(false)
                    }
                } label: { SoftRoundLabel(symbol: "slider.horizontal.3") }
                .accessibilityLabel("Image Crop")
                Menu {
                    Button { takingPhoto = true } label: { Label("Take Photo", systemImage: "camera") }
                    Button { pickingFromLibrary = true } label: {
                        Label("Photos Library", systemImage: "photo.on.rectangle")
                    }
                    Button { importing = true } label: { Label("Files", systemImage: "folder") }
                    Button { fromProject = true } label: { Label("From Project", systemImage: "square.stack") }
                } label: { SoftRoundLabel(symbol: "plus") }
                .accessibilityLabel("Add Media")
            }
        }
    }

    // ---- scanning -----------------------------------------------------------

    @ViewBuilder
    private var scanner: some View {
        if let place {
            let next = session.store.nextScan(in: place.home)
            RoomScanner(usdz: next.usdz, json: next.json) { result in
                scanning = false
                if case .failure(let error) = result { trouble = error.localizedDescription }
                // Onto the film now, not at the next sync — so the room shows
                // back here at once and on every other device after.
                session.registerScans()
                session.refresh()
            }
            .ignoresSafeArea()
        }
    }

    // ---- doing things -------------------------------------------------------

    private func load() {
        guard loaded != id, let place else { return }
        loaded = id
        name = place.name
        address = place.address
        notes = place.notes
        session.store.prepare(place.home)
        // Anything the scanner wrote that the film has not been told about.
        session.registerScans()
    }

    /// The three fields as the engine currently has them, in one value, so one
    /// modifier watches all of them. Three separate `onChange`s on a chain this
    /// long defeats the type-checker.
    private var mirror: String {
        guard let place else { return "" }
        return [place.name, place.address, place.notes].joined(separator: "\u{1}")
    }

    private func adopt() {
        guard let place else { return }
        if editing != "name", place.name != name { name = place.name }
        if !typingAddress, place.address != address { address = place.address }
        if editing != "notes", place.notes != notes { notes = place.notes }
    }

    private func finishRename() {
        guard let scan = renaming, let place else { return }
        renaming = nil
        do { try session.rename(room: scan, to: newName, in: place) }
        catch { trouble = error.localizedDescription }
        session.refresh()
    }

    private func bringIn(files result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let place else { return }
        for url in urls {
            let allowed = url.startAccessingSecurityScopedResource()
            defer { if allowed { url.stopAccessingSecurityScopedResource() } }
            if Engine.Kind(url.pathExtension) == .clip {
                // Copied while the permission to read it is still held: the
                // re-encode happens later, by which time this URL is closed.
                let name = url.lastPathComponent
                let copy = URL.temporaryDirectory.appending(path: "picked-\(UUID().uuidString)-\(name)")
                if (try? FileManager.default.copyItem(at: url, to: copy)) != nil {
                    Task {
                        await session.attach(clipAt: copy, to: id, named: name)
                        try? FileManager.default.removeItem(at: copy)
                    }
                }
            } else if let data = try? Data(contentsOf: url), UIImage(data: data) != nil {
                session.attach(data, named: url.lastPathComponent, toLocation: id)
            } else {
                do { try session.store.addAttachment(from: url, in: place.home) }
                catch { trouble = error.localizedDescription }
            }
        }
        // A paper dropped in the folder joins the film the way a scan does,
        // so it travels — the folder itself never does (2026-09-15).
        session.registerScans()
        session.refresh()
    }

    private func bringIn(_ items: [PhotosPickerItem]) async {
        for item in items {
            // As a file, not as bytes — a clip needs a path and a photograph
            // needs its name. See `Picked`.
            if let file = try? await item.loadTransferable(type: Picked.self) {
                defer { file.discard() }
                if file.isClip {
                    await session.attach(clipAt: file.url, to: id)
                } else if let data = try? Data(contentsOf: file.url) {
                    // The bytes, not the picture: only the bytes let it refuse
                    // to store something larger than it arrived, and let a GIF
                    // stay a GIF.
                    session.attach(data, named: file.url.lastPathComponent, toLocation: id)
                }
            } else if let data = try? await item.loadTransferable(type: Data.self) {
                session.attach(data, toLocation: id)
            }
        }
        picked = []
    }

    private func take(_ suggestion: AddressLookup.Answer) {
        typingAddress = false
        lookup.clear()
        Task {
            guard let found = await lookup.resolve(suggestion) else { return }
            address = found.address
            session.setLocation(id, "address", to: found.address)
            session.setLocation(id, "latitude", to: String(found.coordinate.latitude))
            session.setLocation(id, "longitude", to: String(found.coordinate.longitude))
        }
    }

    private func useCurrentLocation() {
        typingAddress = false
        whereabouts.pin { coordinate in
            guard let coordinate else { return }
            session.setLocation(id, "latitude", to: String(coordinate.latitude))
            session.setLocation(id, "longitude", to: String(coordinate.longitude))
            Task {
                guard let written = await AddressLookup.address(at: coordinate) else { return }
                // It overwrites: pressing a button called Current location is
                // saying "I am here now".
                address = written
                session.setLocation(id, "address", to: written)
                lookup.clear()
            }
        }
    }

    private func look(at coordinate: CLLocationCoordinate2D) {
        camera = .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
        ))
    }

    private func degrees(_ c: CLLocationCoordinate2D) -> String {
        func part(_ value: Double, _ positive: String, _ negative: String) -> String {
            let sign = value >= 0 ? positive : negative
            let magnitude = abs(value)
            let d = Int(magnitude)
            let minutes = (magnitude - Double(d)) * 60
            let m = Int(minutes)
            let s = (minutes - Double(m)) * 60
            return String(format: "%d°%02d'%04.1f\"%@", d, m, s, sign)
        }
        return part(c.latitude, "N", "S") + "  " + part(c.longitude, "E", "W")
    }

    private func directions(to coordinate: CLLocationCoordinate2D, named: String) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = named
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

/// A room on its house's page.
///
/// **This is where the nesting lives now.** The locations list shows the places
/// that stand on their own; a house's rooms are here, one level in, which is
/// the shape of the thing rather than a drawing of it. So the row has to be a
/// real row — a picture and what is in the room — not a line of text.
private struct RoomRow: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var frames: Frames
    @Environment(\.displayScale) private var scale
    let room: Engine.Location

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(room.name).font(.system(size: 15, weight: .semibold))
                // Counted in words, as the Locations list counts a place.
                let scans = session.rooms(of: room).count
                let said = [room.photos.count == 0 ? nil : room.photos.count == 1 ? "1 photo" : "\(room.photos.count) photos",
                            room.scenes.count == 0 ? nil : room.scenes.count == 1 ? "1 scene" : "\(room.scenes.count) scenes",
                            scans == 0 ? nil : scans == 1 ? "Scanned" : "\(scans) scans"].compactMap { $0 }
                if !said.isEmpty {
                    Text(said.joined(separator: " · "))
                        .font(.system(size: 13))
                        .foregroundStyle(Style.ink3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let first = room.photos.first,
           let shown = frames.shown(first, atMost: Thumbnails.bucket(forSide: 44, scale: scale)) {
            Picture(shown).frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: Style.Radius.frame, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: Style.Radius.frame, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 44, height: 44)
        }
    }
}


/// A map to drop a pin on by tapping: the Mac clicks its map.
private struct PinDrop: View {
    let start: CLLocationCoordinate2D?
    let done: (CLLocationCoordinate2D?) -> Void
    @State private var camera: MapCameraPosition = .automatic
    @State private var pin: CLLocationCoordinate2D?

    var body: some View {
        NavigationStack {
            MapReader { reader in
                Map(position: $camera) {
                    if let pin { Marker("", coordinate: pin) }
                }
                .onTapGesture { point in pin = reader.convert(point, from: .local) }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Drop Pin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { done(nil) } }
                ToolbarItem(placement: .confirmationAction) { Button("Use") { done(pin) }.disabled(pin == nil) }
            }
            .onAppear {
                pin = start
                if let start {
                    camera = .region(MKCoordinateRegion(center: start,
                                                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
                } else {
                    camera = .userLocation(fallback: .automatic)
                }
            }
        }
    }
}

/// **Link scenes from the place's side** (the Mac's `LinkScenes`): every
/// scene, ticked when it is shot here.
private struct SceneLinker: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    let place: String

    var body: some View {
        NavigationStack {
            List(session.scenes) { scene in
                let on = scene.locations.contains(place)
                Button {
                    if on { session.unlink(scene: scene.id, fromLocation: place) }
                    else { session.link(scene: scene.id, toLocation: place) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(on ? Color.accentColor : .secondary)
                        Text(scene.number).font(.subheadline.weight(.bold).monospacedDigit())
                        Text(session.isCommercial && !scene.title.isEmpty ? scene.title : scene.heading)
                            .font(.subheadline).lineLimit(1)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Link Scenes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
