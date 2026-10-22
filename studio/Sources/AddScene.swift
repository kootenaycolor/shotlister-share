import SwiftUI

/// Adding a scene by hand, as one run at the keyboard.
///
/// **The heading field and its parsed preview stay** — his explicit call,
/// 2026-09-15: typing a slugline and watching it split into Number, Int/Ext,
/// Location and Time of Day *is* the feature. Only the strip's labels changed
/// clothes. Time of day is a choice; Add Another sits far left in the footer,
/// Cancel · Add on the right — the one anatomy.
struct AddSceneSheet: View {
    @ObservedObject var state: ShellState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var heading = ""
    @State private var synopsis = ""
    // ---- the commercial's own ------------------------------------------
    @State private var title = ""
    @State private var video = ""
    @State private var audio = ""
    @State private var slugOpen = false
    @State private var priority = ""
    @State private var sequence: String?
    @State private var place: String?
    @State private var added = 0
    @State private var complaint = ""

    private enum Focus { case heading, synopsis, title, video, audio }
    @FocusState private var focus: Focus?

    private var dark: Bool { scheme == .dark }

    private var parts: Engine.Heading {
        state.engine?.readHeading(heading) ?? Engine.Heading()
    }

    private static let times = ["SUNRISE", "DAY", "SUNSET", "NIGHT"]

    private var commercial: Bool { state.view?.project.isCommercial ?? false }

    var body: some View {
        Sheet(title: "Add Scene",
              subtitle: added > 0 ? "\(added) added" : "",
              width: .standard) {
            if commercial {
                commercialFields
            } else {
                filmFields
            }

            GroupGap()
            HStack(alignment: .top, spacing: 12) {
                Field("Priority") {
                    picker(priority.isEmpty ? "None" : priority, empty: priority.isEmpty) {
                        Button("None") { priority = "" }
                        Divider()
                        ForEach(state.engine?.vocabulary("priority") ?? [],
                                id: \.self) { value in
                            Button(value) { priority = value }
                        }
                    }
                }
                Field(commercial ? "Section" : "Sequence") {
                    picker(sequenceName, empty: sequence == nil, dot: sequenceColour) {
                        Button("None") { sequence = nil }
                        Divider()
                        ForEach(state.view?.sequences ?? []) { seq in
                            Button(seq.title) { sequence = seq.id }
                        }
                    }
                }
            }

            Field("Filming Location") {
                picker(placeName, empty: place == nil) {
                    Button("None") { place = nil }
                    Divider()
                    ForEach(state.view?.locations ?? []) { location in
                        Button(location.name.isEmpty ? "Untitled" : location.name) {
                            place = location.id
                        }
                    }
                    if (state.view?.locations ?? []).isEmpty {
                        Button("No locations") {}.disabled(true)
                    }
                }
            }

            if commercial { slugFold }

            if !complaint.isEmpty {
                Text(complaint).sans(Brand.Size.small)
                    .foregroundStyle(Brand.ink3(dark))
            }
        } leading: {
            Button("Add Another") { add(andAnother: true) }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(nothingTyped)
        } trailing: {
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Add") { add(andAnother: false) }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .disabled(nothingTyped)
        }
        .onAppear {
            if commercial {
                title = state.newSceneHeading
                state.newSceneHeading = ""
                focus = .title
            } else {
                heading = state.newSceneHeading
                state.newSceneHeading = ""
                focus = .heading
            }
            if state.newSceneNow {
                state.newSceneNow = false
                add(andAnother: state.newSceneAgain)
            }
        }
    }

    private var nothingTyped: Bool {
        if commercial {
            return title.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return heading.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // ---- a film's first question -----------------------------------------

    private var filmFields: some View {
        Group {
            Field("Heading") {
                typed("34 INT. CAR - NIGHT", $heading, focus: .heading) { add(andAnother: false) }
            }

            // What the line just typed adds up to. Four named parts
            // rather than the line read back, because the useful thing
            // to see is *which part is which* — that CAR landed in
            // Location and NIGHT in Time of Day.
            readsAs

            timeRow

            Field("Synopsis") {
                typed("One sentence", $synopsis, focus: .synopsis) { add(andAnother: false) }
            }
        }
    }

    /// **A choice, not a row of chips**: one of four, at most one on, the on
    /// one a soft fill — the same pill the views strip wears.
    private var timeRow: some View {
        Field("Time of Day") {
            HStack(spacing: 2) {
                ForEach(Self.times, id: \.self) { time in
                    ChoicePill(title: time.capitalized, on: parts.timeOfDay == time,
                               dark: dark) { setTime(time) }
                }
                if !parts.timeOfDay.isEmpty,
                   !Self.times.contains(parts.timeOfDay) {
                    ChoicePill(title: parts.timeOfDay.capitalized, on: true, dark: dark) {}
                }
            }
            .padding(2)
        }
    }

    // ---- a commercial's -------------------------------------------------

    private var commercialFields: some View {
        Group {
            // **A title, and that is a scene.** A commercial's scene is a
            // place or a setup; the script's words live on beats, tied to
            // shots (2026-09-19).
            Field("Title") {
                typed("Kitchen", $title, focus: .title) { add(andAnother: false) }
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
                Field("Slugline") {
                    typed("EXT. MOTEL - NIGHT", $heading, focus: .heading) {}
                }
                timeRow
            }
        }
    }

    // ---- what the heading says ------------------------------------------

    private var readsAs: some View {
        let read = parts
        // **Measured, not shared out equally.** Four equal columns put
        // Int / Ext hard against Location with no gap at all — the labels
        // are different lengths, so the room has to be too. Location takes
        // what is left, because it is the part that can be long.
        return HStack(alignment: .top, spacing: 14) {
            part("Number", read.number, width: 52)
            part("Int / Ext", insideOutShown(read.intExt), width: 70)
            part("Location", read.location, width: nil)
            part("Time of Day", read.timeOfDay, width: 86)
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
            .fill(Brand.selectionQuiet(dark)))
    }

    private func part(_ title: String, _ value: String, width: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).fieldLabel(dark).fixedSize()
            Text(value.isEmpty ? "—" : value)
                .sans(Brand.Size.body, weight: .medium)
                .foregroundStyle(value.isEmpty ? Brand.ink4(dark) : Brand.ink(dark))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    private func setTime(_ time: String) {
        let line = heading.trimmingCharacters(in: .whitespaces)
        let body: String
        if let dash = line.range(of: " - ", options: .backwards) {
            body = String(line[line.startIndex..<dash.lowerBound])
        } else if let dash = line.range(of: " — ", options: .backwards) {
            body = String(line[line.startIndex..<dash.lowerBound])
        } else {
            body = line
        }
        heading = body.isEmpty ? time : "\(body) - \(time)"
    }

    // ---- the small controls ---------------------------------------------

    /// A line you type in, in the one field shape, with the keyboard focus
    /// this sheet moves about as it goes.
    private func typed(_ ghost: String, _ text: Binding<String>, focus which: Focus,
                       onSubmit: @escaping () -> Void) -> some View {
        TextField(ghost, text: text)
            .textFieldStyle(.plain)
            .sans(Brand.Size.body)
            .foregroundStyle(Brand.ink(dark))
            .focused($focus, equals: which)
            .onSubmit(onSubmit)
            .field(dark)
    }

    private func picker<Content: View>(_ title: String, empty: Bool, dot: Color? = nil,
                                       @ViewBuilder items: () -> Content) -> some View {
        Menu {
            items()
        } label: {
            FieldFace(text: title, empty: empty, dot: dot, dark: dark)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    private var sequenceName: String {
        guard let sequence,
              let seq = state.view?.sequences.first(where: { $0.id == sequence })
        else { return "None" }
        return seq.title
    }

    private var sequenceColour: Color? {
        guard let sequence,
              let seq = state.view?.sequences.first(where: { $0.id == sequence }),
              !seq.colour.isEmpty
        else { return nil }
        return Brand.hex(seq.colour)
    }

    private var placeName: String {
        guard let place,
              let found = state.view?.locations.first(where: { $0.id == place })
        else { return "None" }
        return found.name.isEmpty ? "Untitled" : found.name
    }

    // ---- making it --------------------------------------------------------

    private func add(andAnother again: Bool) {
        guard let engine = state.engine else { return }
        if commercial {
            addTitled(andAnother: again, engine: engine)
            return
        }
        let read = parts
        // A scene has to be numbered — the row is found by its number
        // everywhere in the app. Said once, plainly, rather than a disabled
        // button with no reason on it.
        guard !read.number.isEmpty else {
            complaint = "Enter a scene number, like 34 or 12A"
            return
        }
        complaint = ""

        let before = Set((state.view?.scenes ?? []).map(\.id))
        var fields: [(String, String)] = [
            ("int_ext", read.intExt),
            ("location", read.location),
            ("time_of_day", read.timeOfDay),
            ("description", synopsis),
            ("priority", priority),
        ]
        if let sequence { fields.append(("sequence", sequence)) }
        if let place { fields.append(("place", place)) }

        state.replace(engine.addScene(number: read.number, fields: fields))

        // The one it just made, found by being the one that was not there
        // before — safer than matching on a number two scenes could share.
        let made = (state.view?.scenes ?? []).first { !before.contains($0.id) }
        state.sceneId = made?.id ?? state.sceneId

        // A checking run says what landed, so the box is watched writing
        // rather than only photographed. Silent in his hand.
        if CommandLine.arguments.contains("--addscene"), let made {
            FileHandle.standardError.write(Data((
                "scene added: number \"\(made.number)\" intext \"\(made.intExt)\" "
                + "location \"\(made.location)\" time \"\(made.timeOfDay)\" "
                + "synopsis \"\(made.description)\" priority \"\(made.priority)\"\n"
                ).utf8))
        }

        added += 1
        if again {
            clear(after: read.number)
        } else {
            dismiss()
        }
    }

    private func addTitled(andAnother again: Bool, engine: Engine) {
        complaint = ""
        let read = parts
        let before = Set((state.view?.scenes ?? []).map(\.id))
        var fields: [(String, String)] = [
            ("script", video),
            ("audio", audio),
            ("priority", priority),
        ]
        if slugOpen {
            fields.append(("int_ext", read.intExt))
            fields.append(("location", read.location))
            fields.append(("time_of_day", read.timeOfDay))
        }
        if let sequence { fields.append(("sequence", sequence)) }
        if let place { fields.append(("place", place)) }

        state.replace(engine.addTitled(title: title, fields: fields))
        let made = (state.view?.scenes ?? []).first { !before.contains($0.id) }
        state.sceneId = made?.id ?? state.sceneId

        if CommandLine.arguments.contains("--addscene"), let made {
            FileHandle.standardError.write(Data((
                "scene added: number \"\(made.number)\" title \"\(made.title)\" "
                + "video \"\(made.script)\" audio \"\(made.audio)\" slug \"\(made.slug)\"\n"
                ).utf8))
        }

        added += 1
        if again {
            title = ""
            video = ""
            audio = ""
            heading = ""
            priority = ""
            place = nil
            focus = .title
        } else {
            dismiss()
        }
    }

    private func clear(after number: String) {
        heading = suggestion(after: number)
        synopsis = ""
        priority = ""
        place = nil
        focus = .heading
    }

    private func suggestion(after number: String) -> String {
        let digits = number.prefix { $0.isNumber }
        guard let value = Int(digits) else { return "" }
        return "\(value + 1) "
    }
}
