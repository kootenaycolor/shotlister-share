import SwiftUI

/// Adding a scene by hand, the way the Mac does it since 2026-09-02.
///
/// **What was wrong**, in his words: *"when I add a scene, I just add a
/// number, and then it shows up blank."* The phone asked for a number, made
/// an empty row, and left the rest to a second trip through the scene's page.
/// Two gestures for one thought.
///
/// So the sheet takes the **heading**, the way he would write it on paper —
/// `34 INT. CAR - NIGHT` — and the engine pulls the four parts out of it as
/// he types. Everything else a new scene usually wants is on the same sheet,
/// and the whole thing lands as **one change**, so one undo takes it back
/// rather than seven.
///
/// **Scene numbers still belong to the script.** Nothing here numbers a
/// scene: the number is read out of what he typed. *Add another* offers the
/// next number as a suggestion to a person, not the app renumbering.
///
/// **No shoot day here, deliberately.** A scene's day lives on its shots.
struct AddSceneSheet: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss

    @State private var heading = ""
    @State private var synopsis = ""
    // ---- the commercial's own ------------------------------------------
    @State private var title = ""
    @State private var slugOpen = false
    @State private var priority = ""
    @State private var sequence = ""
    @State private var place = ""
    @State private var added = 0
    @State private var complaint = ""
    @FocusState private var focused: Bool

    private var parts: Session.Heading { session.readHeading(heading) }
    /// **A title, and that is a scene** — on a commercial. A film's scene
    /// needs a number, read out of the heading he typed.
    private var commercial: Bool { session.isCommercial }
    private var nothingTyped: Bool {
        (commercial ? title : heading).trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if commercial {
                    // A commercial's scene is a place or a setup; it takes the
                    // next whole number itself. The slugline is optional and
                    // folded away — *"sometimes you'll have scene headers,
                    // sometimes you won't."*
                    Section("Title") {
                        TextField("Kitchen", text: $title)
                            .focused($focused)
                            .onSubmit { add(andAnother: false) }
                    }
                    Section {
                        DisclosureGroup("Slugline", isExpanded: $slugOpen) {
                            TextField("EXT. MOTEL - NIGHT", text: $heading)
                                .font(.kitRow.monospaced())
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                            PillField(
                                label: "Time of Day",
                                options: TimeOfDay.all,
                                selected: parts.timeOfDay.isEmpty ? [] : [parts.timeOfDay],
                                onChange: { setTime($0.first ?? "") }
                            )
                        }
                    }
                } else {
                    Section("Heading") {
                        TextField("34 INT. CAR - NIGHT", text: $heading)
                            .font(.kitRow.monospaced())
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .onSubmit { add(andAnother: false) }
                        // Which part is which — that CAR landed in Location and
                        // NIGHT in Time of Day — rather than the line read back.
                        readsAs
                    }

                    Section {
                        PillField(
                            label: "Time of Day",
                            options: TimeOfDay.all,
                            selected: parts.timeOfDay.isEmpty ? [] : [parts.timeOfDay],
                            onChange: { setTime($0.first ?? "") }
                        )
                    }

                    Section("Synopsis") {
                        TextField("Synopsis", text: $synopsis, axis: .vertical)
                            .lineLimit(2...6)
                    }
                }

                Section {
                    // A film with no priorities yet has nothing to offer here.
                    if !session.vocabulary("priority").isEmpty {
                        PillField(
                            label: "Priority",
                            options: session.vocabulary("priority"),
                            selected: priority.isEmpty ? [] : [priority],
                            onChange: { priority = $0.first ?? "" }
                        )
                    }
                    if !session.sequences.isEmpty {
                        Picker(session.sequenceWord, selection: $sequence) {
                            Text("None").tag("")
                            ForEach(session.sequences) { seq in
                                Text(seq.title).tag(seq.id)
                            }
                        }
                    }
                    Picker("Filming Location", selection: $place) {
                        Text("None").tag("")
                        ForEach(session.locations) { location in
                            Text(location.fullName ?? location.name).tag(location.id)
                        }
                    }
                }

                Section {
                    Button("Add Another") { add(andAnother: true) }
                        .disabled(nothingTyped)
                }

                if !complaint.isEmpty {
                    Section { Text(complaint).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(added > 0 ? "\(added) added" : "New Scene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add") { add(andAnother: false) }
                        .disabled(nothingTyped)
                }
            }
            .onAppear { focused = true }
        }
    }

    // ---- what the heading says ------------------------------------------

    private var readsAs: some View {
        let read = parts
        return HStack(alignment: .top, spacing: 12) {
            part("Number", read.number)
            part("Inside / Outside", read.intExt.uppercased() == "INT/EXT" ? "I/E" : read.intExt)
            part("Location", read.location).frame(maxWidth: .infinity, alignment: .leading)
            part("Time of Day", read.timeOfDay)
        }
    }

    private func part(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)
            Text(value.isEmpty ? "—" : value)
                .font(.kitRow.monospaced().weight(.semibold))
                .foregroundStyle(value.isEmpty ? .tertiary : .primary)
                .lineLimit(1)
        }
    }

    /// Setting the time from a pill writes it back into the **heading**,
    /// because the heading is the one place the parts come from. Two sources
    /// for one fact is how they end up disagreeing.
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
        if time.isEmpty { heading = body; return }
        heading = body.isEmpty ? time : "\(body) - \(time)"
    }

    // ---- making it --------------------------------------------------------

    private func add(andAnother again: Bool) {
        if commercial { addTitled(andAnother: again); return }
        let read = parts
        guard !read.number.isEmpty else {
            complaint = "A scene needs a number. Try 34, or 12A."
            return
        }
        complaint = ""
        var fields: [(String, String)] = [
            ("int_ext", read.intExt),
            ("location", read.location),
            ("time_of_day", read.timeOfDay),
            ("description", synopsis),
            ("priority", priority),
        ]
        if !sequence.isEmpty { fields.append(("sequence", sequence)) }
        if !place.isEmpty { fields.append(("place", place)) }
        session.addScene(numbered: read.number, fields: fields)
        added += 1
        guard again else { dismiss(); return }
        // The next number, offered in the box he is about to type into — a
        // suggestion to a person, not the app renumbering anything.
        heading = Self.next(after: read.number)
        synopsis = ""
        focused = true
    }

    /// The commercial way: a title, the slugline's parts only when the fold
    /// was opened, and the engine numbers it.
    private func addTitled(andAnother again: Bool) {
        complaint = ""
        let read = parts
        var fields: [(String, String)] = [("priority", priority)]
        if slugOpen {
            fields.append(("int_ext", read.intExt))
            fields.append(("location", read.location))
            fields.append(("time_of_day", read.timeOfDay))
        }
        if !sequence.isEmpty { fields.append(("sequence", sequence)) }
        if !place.isEmpty { fields.append(("place", place)) }
        session.addScene(titled: title, fields: fields)
        added += 1
        guard again else { dismiss(); return }
        title = ""
        heading = ""
        priority = ""
        place = ""
        focused = true
    }

    /// `34` → `35`, `12A` → `12B`; anything else comes back empty.
    static func next(after number: String) -> String {
        if let n = Int(number) { return String(n + 1) }
        let digits = number.prefix { $0.isNumber }
        let rest = number.dropFirst(digits.count)
        if !digits.isEmpty, rest.count == 1, let letter = rest.first,
           letter.isLetter, letter != "Z", letter != "z",
           let scalar = letter.unicodeScalars.first,
           let bumped = Unicode.Scalar(scalar.value + 1) {
            return digits + String(Character(bumped))
        }
        return ""
    }
}
