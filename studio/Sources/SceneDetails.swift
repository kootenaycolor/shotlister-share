import SwiftUI

/// **How a scene that is both inside and outside is drawn: `I/E`.** His ruling,
/// 2026-10-13. The engine still stores and prints `INT/EXT`; only the small
/// Int/Ext labels say `I/E`, so the heading stays as the script wrote it.
func insideOutShown(_ value: String) -> String {
    value.uppercased() == "INT/EXT" ? "I/E" : value
}

/// The scene's own page — the richest sheet, so the one to get right.
///
/// **One anatomy, the grammar of 2026-09-14.** Line one is the slugline —
/// Number · Int/Ext · Location — because those three are one fact. Then Time
/// of Day. Then the production pair, Sequence · Shoot Day; Priority · Point of
/// View; Synopsis; Filming Location · Reference Boards; Notes. One field
/// shape whether you type in it or pick from it. Labels name the thing:
/// `Location`, `Filming Location`, `Int / Ext` — his law of 2026-08-21.
struct SceneDetailsSheet: View {
    @ObservedObject var state: ShellState
    let scene: ViewModel.Scene
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    private var dark: Bool { scheme == .dark }

    @State private var number = ""
    @State private var intExt = ""
    @State private var location = ""
    @State private var timeOfDay = ""
    @State private var synopsis = ""
    @State private var shootingLocation = ""
    @State private var notes = ""
    @State private var priority = ""
    @State private var pov = ""
    // ---- a commercial scene's own -----------------------------------------
    @State private var title = ""
    @State private var video = ""
    @State private var audio = ""
    @State private var slugOpen = false

    private var commercial: Bool { state.view?.project.isCommercial ?? false }

    private static let insideOut = ["INT", "EXT", "INT/EXT"]
    private static let times = TimeOfDay.all + ["CONTINUOUS"]

    private var heading: String {
        if commercial, !scene.title.isEmpty { return scene.title }
        return scene.number.isEmpty ? "Scene" : "Scene \(scene.number)"
    }

    var body: some View {
        Sheet(title: heading,
              subtitle: "\(scene.count) \(scene.count == 1 ? "shot" : "shots")",
              width: .standard, height: 640) {
            if commercial { commercialTop } else { filmTop }

            GroupGap()
            HStack(alignment: .top, spacing: 12) {
                Field(commercial ? "Section" : "Sequence") { sequenceField }
                Field("Shoot Day") { dayField }
            }
            HStack(alignment: .top, spacing: 12) {
                Field("Priority") { vocab($priority, "priority") { write("priority", priority) } }
                Field("Point of View") { vocab($pov, "pov") { write("pov", pov) } }
            }

            GroupGap()
            if commercial {
                slugFold
            } else {
                Field("Synopsis") {
                    TypingField(text: $synopsis, ghost: "One sentence", height: 64)
                }
            }

            GroupGap()
            HStack(alignment: .top, spacing: 12) {
                Field("Filming Location") { locationField }
                Field("Reference Boards") { boardsField }
            }
            // **Report, never destroy.** A scene written before locations
            // existed carries free text here, and throwing it away silently
            // is not ours to do — so it is shown, said to be the old kind,
            // and turned into a record only when a person asks.
            if chosenLocation == nil, !shootingLocation.isEmpty {
                HStack(spacing: 6) {
                    Text("Written here before: “\(shootingLocation)”")
                        .sans(Brand.Size.tiny).foregroundStyle(Brand.ink3(dark))
                    Button { promote() } label: {
                        PlusLabel(text: "Make a location", dark: dark, size: Brand.Size.tiny)
                    }
                    .buttonStyle(.rowAction)
                }
            }

            GroupGap()
            Field("Notes") {
                TypingField(text: $notes, ghost: "Add a note", height: 76)
            }
        } trailing: {
            Button("Done") { commitAll(); dismiss() }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
        }
        .onAppear {
            title = scene.title
            video = scene.script
            audio = scene.audio
            slugOpen = !scene.slug.isEmpty
            number = scene.number
            intExt = scene.intExt
            location = scene.location
            timeOfDay = scene.timeOfDay
            synopsis = scene.description
            shootingLocation = scene.shootingLocation
            notes = scene.notes
            priority = scene.priority
            pov = scene.pov
        }
    }

    // ---- a film's scene: the slugline first --------------------------------

    private var filmTop: some View {
        Group {
            HStack(alignment: .top, spacing: 8) {
                Field("Number", width: 70) {
                    FieldText(placeholder: "", text: $number) { write("number", number) }
                }
                Field("Int / Ext", width: 116) {
                    listed(intExtShown, Self.insideOut, shown: insideOutShown) { write("int_ext", intExt) }
                }
                // **Two different facts, and they must not be conflated**
                // (his correction): this is the slugline's own word and stays
                // exactly as the script writes it. Where it is actually being
                // filmed is a *place* — a record on the Locations tab, below.
                Field("Location") {
                    FieldText(placeholder: "CAR", text: $location) { write("location", location) }
                }
            }
            Field("Time of Day", width: 200) {
                listed($timeOfDay, Self.times, dot: Brand.timeInk(timeOfDay, dark)) {
                    write("time_of_day", timeOfDay)
                }
            }
        }
    }

    // ---- a commercial scene: title first, then the AV pair ------------------
    //
    // `design/22-commercial.html`, his rulings of 2026-09-14. The number is
    // still editable — a person fixing one is not the app renumbering — but
    // it sits beside the title rather than leading.

    private var commercialTop: some View {
        Group {
            HStack(alignment: .top, spacing: 8) {
                Field("Title") {
                    FieldText(placeholder: "Hero Unboxes the Camera", text: $title) {
                        write("title", title)
                    }
                }
                Field("Number", width: 70) {
                    FieldText(placeholder: "", text: $number) { write("number", number) }
                }
            }
        }
    }

    private var slugFold: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { slugOpen.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: Brand.Icon.tiny, weight: .semibold))
                        .rotationEffect(.degrees(slugOpen ? 90 : 0))
                    Text("Slugline").sans(Brand.Size.small, weight: .medium)
                }
                .foregroundStyle(Brand.ink3(dark))
            }
            .buttonStyle(.plain)
            if slugOpen {
                HStack(alignment: .top, spacing: 8) {
                    Field("Int / Ext", width: 116) {
                        listed(intExtShown, Self.insideOut, shown: insideOutShown) { write("int_ext", intExt) }
                    }
                    Field("Time of Day", width: 200) {
                        listed($timeOfDay, Self.times, dot: Brand.timeInk(timeOfDay, dark)) {
                            write("time_of_day", timeOfDay)
                        }
                    }
                }
                Field("Place") {
                    FieldText(placeholder: "MOTEL", text: $location) { write("location", location) }
                }
            }
        }
    }

    // ---- the pickers --------------------------------------------------------

    /// A sequence is a record the project owns, so this offers what the
    /// project has rather than free text — and it wears the sequence's own
    /// colour, the way the list does.
    private var sequenceField: some View {
        Menu {
            Button("None") { assignSequence(nil) }
            Divider()
            ForEach(state.view?.sequences ?? []) { seq in
                Button(seq.title) { assignSequence(seq.id) }
            }
        } label: {
            FieldFace(text: sequenceName, empty: scene.sequence == nil,
                      dot: sequenceColour, dark: dark)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    /// Which day this scene is being shot on — the same assignment the
    /// Schedule draws a board for.
    private var dayField: some View {
        Menu {
            Button("Unscheduled") { assignDay(nil) }
            Divider()
            ForEach(state.view?.days ?? []) { day in
                Button(day.label) { assignDay(day.id) }
            }
        } label: {
            FieldFace(text: scene.day.isEmpty ? "Unscheduled" : scene.day,
                      empty: scene.day.isEmpty, dark: dark)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    /// **The other half of the slugline's word.** The address the crew drives
    /// to — a *record* on the Locations tab, with a pin and photographs.
    /// Ticks, not a jump: a scene that moves between places is shot at each.
    private var locationField: some View {
        Menu {
            Button("None") {
                state.replace(state.engine?.sceneLocation(scene.id, ""))
            }
            Divider()
            ForEach(state.view?.locations ?? []) { place in
                let on = scene.locations.contains(place.id)
                Button {
                    guard let engine = state.engine else { return }
                    state.replace(on
                        ? engine.removeSceneLocation(scene.id, place.id)
                        : engine.addSceneLocation(scene.id, place.id))
                } label: {
                    let title = place.name.isEmpty ? "Untitled" : place.name
                    if on {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
            if (state.view?.locations ?? []).isEmpty {
                Text("No locations")
            }
        } label: {
            FieldFace(text: chosenCount > 1
                          ? "\(chosenLocation?.name ?? "") + \(chosenCount - 1)"
                          : (chosenLocation?.name ?? "None"),
                      empty: chosenLocation == nil, dark: dark)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    /// **The scene's own boards** — his call, 2026-08-23 (Ref SL-348): a
    /// board usually serves twenty scenes; this is the cheap end to file the
    /// link from.
    private var boardsField: some View {
        Menu {
            ForEach(state.view?.boards ?? []) { board in
                let on = linkedBoardIds.contains(board.id)
                Button {
                    guard let engine = state.engine else { return }
                    state.replace(on
                        ? engine.removeSceneBoard(scene.id, board.id)
                        : engine.addSceneBoard(scene.id, board.id))
                } label: {
                    let title = board.name.isEmpty ? "Untitled" : board.name
                    if on {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
            if (state.view?.boards ?? []).isEmpty {
                Text("No reference boards")
            }
        } label: {
            FieldFace(text: linkedBoardNames.count > 1
                          ? "\(linkedBoardNames.first ?? "") + \(linkedBoardNames.count - 1)"
                          : (linkedBoardNames.first ?? "None"),
                      empty: linkedBoardNames.isEmpty, dark: dark)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    private func vocab(_ value: Binding<String>, _ field: String,
                       commit: @escaping () -> Void) -> some View {
        listed(value, state.engine?.vocabulary(field) ?? [], commit: commit)
    }

    /// **Type or pick, in the one field shape.** The words, and the chevron at
    /// the right edge that opens the list. A placeholder, because an empty
    /// box with a lone chevron reads as a control that failed to load.
    private var intExtShown: Binding<String> {
        Binding(get: { insideOutShown(intExt) }, set: { intExt = $0 })
    }

    private func listed(_ value: Binding<String>, _ options: [String],
                        dot: Color? = nil,
                        shown: @escaping (String) -> String = { $0 },
                        commit: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            if let dot, !value.wrappedValue.isEmpty {
                Circle().fill(dot).frame(width: 7, height: 7)
            }
            TextField("None", text: value)
                .textFieldStyle(.plain)
                .sans(Brand.Size.body)
                .foregroundStyle(Brand.ink(dark))
                .onSubmit(commit)
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(shown(option)) { value.wrappedValue = option; commit() }
                }
                if options.isEmpty {
                    Button("Nothing on the list") {}.disabled(true)
                }
                Divider()
                Button("Clear") { value.wrappedValue = ""; commit() }
            } label: {
                MenuMark()
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .field(dark)
    }

    private var sequenceName: String {
        guard let id = scene.sequence,
              let seq = state.view?.sequences.first(where: { $0.id == id })
        else { return "None" }
        return seq.title
    }

    private var sequenceColour: Color? {
        guard let id = scene.sequence,
              let seq = state.view?.sequences.first(where: { $0.id == id }),
              !seq.colour.isEmpty
        else { return nil }
        return Brand.hex(seq.colour)
    }

    private func assignSequence(_ id: String?) {
        guard let engine = state.engine else { return }
        state.replace(engine.set(shot: scene.id, field: "sequence", value: id ?? ""))
    }

    private func assignDay(_ id: String?) {
        guard let engine = state.engine else { return }
        _ = engine.call("scene", scene.id, id ?? "none")
        state.replace(engine.view())
    }

    private func writeNotes() {
        guard let engine = state.engine, notes != scene.notes else { return }
        state.replace(engine.set(shot: scene.id, field: "notes", value: notes))
        state.replace(engine.set(shot: scene.id, field: "notes_rich", value: ""))
    }

    private func commitAll() {
        writeNotes()
        if commercial {
            write("title", title)
        }
        write("number", number)
        write("int_ext", intExt)
        write("location", location)
        write("time_of_day", timeOfDay)
        write("description", synopsis)
        write("shooting_location", shootingLocation)
        write("priority", priority)
        write("pov", pov)
    }

    private var chosenLocation: ViewModel.Location? {
        let id = state.view?.scenes.first { $0.id == scene.id }?.locationId ?? scene.locationId
        guard !id.isEmpty else { return nil }
        return state.view?.locations.first { $0.id == id }
    }

    private var chosenCount: Int {
        (state.view?.scenes.first { $0.id == scene.id } ?? scene).locations.count
    }

    private var linkedBoardIds: [String] {
        (state.view?.scenes.first { $0.id == scene.id } ?? scene).boards
    }

    private var linkedBoardNames: [String] {
        let all = state.view?.boards ?? []
        return linkedBoardIds.compactMap { id in all.first { $0.id == id }?.name }
    }

    private func promote() {
        guard let engine = state.engine else { return }
        let name = shootingLocation.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let existing = (state.view?.locations ?? [])
            .first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        if let existing {
            state.replace(engine.sceneLocation(scene.id, existing.id))
            return
        }
        let before = Set((state.view?.locations ?? []).map(\.id))
        state.replace(engine.addLocation(name: name))
        guard let fresh = (state.view?.locations ?? [])
            .first(where: { !before.contains($0.id) }) else { return }
        state.replace(engine.sceneLocation(scene.id, fresh.id))
    }

    private func write(_ field: String, _ value: String) {
        guard let engine = state.engine else { return }
        let held: String
        switch field {
        case "number": held = scene.number
        case "int_ext": held = scene.intExt
        case "location": held = scene.location
        case "time_of_day": held = scene.timeOfDay
        case "description": held = scene.description
        case "shooting_location": held = scene.shootingLocation
        case "title": held = scene.title
        case "script": held = scene.script
        case "audio": held = scene.audio
        case "priority": held = scene.priority
        case "pov": held = scene.pov
        default: held = ""
        }
        let next = value.trimmingCharacters(in: .whitespaces)
        guard next != held else { return }
        state.replace(engine.set(shot: scene.id, field: field, value: next))
    }
}

/// Naming a sequence (or, on a commercial, a section) into existence — from
/// the band's menu, with the scene joining it as soon as it has a name.
struct NameSequenceSheet: View {
    @ObservedObject var state: ShellState
    var scene: ViewModel.Scene?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    private var dark: Bool { scheme == .dark }
    @State private var title = ""

    private var commercial: Bool { state.view?.project.isCommercial == true }

    var body: some View {
        Sheet(title: commercial ? "New Section" : "New Sequence", width: .narrow) {
            Field("Name") {
                FieldText(placeholder: commercial ? "Section Name" : "Sequence Name",
                          text: $title, onSubmit: make)
            }
        } trailing: {
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Add") { make() }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func make() {
        let name = title.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let engine = state.engine else { return }
        state.replace(engine.addSequence(title: name))
        // …and this scene joins it, which is why the naming started.
        if let scene, let made = state.view?.sequences.first(where: { $0.title == name }) {
            state.replace(engine.set(shot: scene.id, field: "sequence", value: made.id))
        }
        dismiss()
    }
}
