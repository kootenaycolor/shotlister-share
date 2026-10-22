import SwiftUI
import PDFKit
import AppKit

/// **Taking a script in.**
///
/// A PDF goes in one end and scenes come out the other, and in between a person
/// gets to read what is about to happen and say no. That order is the whole
/// design and it is not ours alone — Cadrage's import does the same thing, which
/// is the strongest evidence we had that it is right (`design/cadrage-script-import.md`,
/// transcribed off six screenshots on 2026-08-20).
///
/// **Nothing in this file decides anything about a screenplay.** The PDF becomes
/// `page`/`run` lines in `ScriptPDF`, the engine decides what a slug line is, and
/// what comes back is drawn. The confirm screen prints the engine's own
/// sentences verbatim, computed by the same code that does the work — which is
/// why the promise and the outcome cannot drift apart.
struct ScriptFile: Identifiable {
    let url: URL
    /// What a checking run wants done once the PDF has been read: `scenes`,
    /// `characters`, `confirm`, `take`. Empty for a person.
    var opening: String = ""
    /// Which way to read the cast, when a checking run wants a particular one.
    /// Empty means the sheet's own default.
    var merging: String = ""
    /// **A draft from the project's Drive script folder** (stage 5 step 4,
    /// piece C): the review that "New draft in Drive" opens. Nil for a PDF
    /// picked on this Mac.
    var drive: DriveDraft? = nil
    var id: String { url.path }
}

/// The draft waiting in Drive, as the review needs it.
struct DriveDraft: Hashable {
    /// The project's id on the server.
    var project: String
    /// The Drive file.
    var file: String
    /// `Halcyon Pink · Oct 12, 2026`.
    var label: String
    /// The draft in use now, the same way: `Halcyon Blue · Sep 28, 2026`.
    var using: String
}

struct ImportScriptSheet: View {
    @ObservedObject var state: ShellState
    let file: ScriptFile

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    enum Page: String, CaseIterable, Identifiable {
        case summary = "Summary", scenes = "Scenes", characters = "Characters"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .summary: return "square.grid.2x2"
            case .scenes: return "film.stack"
            case .characters: return "person.2"
            }
        }
    }

    @State private var page: Page = .summary
    /// The PDF as the engine reads it. Kept, because every turn of a dial is a
    /// fresh reading of the same pages and decoding a PDF twice is the slow half.
    @State private var runs = ""
    @State private var thumb: NSImage?
    @State private var reading: ScriptReading?
    @State private var busy = true
    @State private var trouble: String?
    @State private var name = ""
    /// Scene indices as `readscript` numbered them — the same numbers
    /// `takescript` is given back.
    @State private var ticked: Set<Int> = []
    @State private var cast: Set<String> = []
    @State private var dials = Detection.standard
    @State private var least = 0
    /// `none` · `regular` · `hard` — the engine's own three.
    @State private var merging = "regular"
    @State private var archiveOmitted = true
    /// **The moves ticked**, by draft index — Ref 241. Empty by default: a
    /// scene that looks like it moved is offered, never assumed.
    @State private var moving: Set<Int> = []
    @State private var plan: ScriptPlan?
    @State private var confirming = false

    // The three states a scene can be in, and the same three colours all the way
    // through: the tile, the dot beside the row, and the sentence on the confirm
    // screen. One fact, one colour, wherever it is drawn.
    private var matchedInk: Color { Brand.data("2F7A44", dark) }
    private var newInk: Color { Brand.accent(dark) }
    private var goneInk: Color { Brand.data("A33574", dark) }

    var body: some View {
        VStack(spacing: 0) {
            head
            Divider().overlay(Brand.rule(dark))
            Group {
                if let trouble {
                    failed(trouble)
                } else if busy {
                    working
                } else if confirming {
                    confirm
                } else {
                    switch page {
                    case .summary: summary
                    case .scenes: scenesPage
                    case .characters: charactersPage
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().overlay(Brand.rule(dark))
            foot
        }
        .frame(width: 900, height: 660)
        .background(Brand.panel(dark))
        .buttonStyle(.capsule)
        .task { await open() }
    }

    // ---- chrome ---------------------------------------------------------

    /// The one anatomy's header: title top-left; the pages a soft-fill
    /// choice beside it, words only.
    private var head: some View {
        HStack(spacing: 14) {
            Text(confirming ? "Confirm Import" : file.drive != nil ? "Import \(Self.stemName(file.url.lastPathComponent))" : "Import Script")
                .sans(Brand.Size.large, weight: .semibold).foregroundStyle(Brand.ink(dark))
                .lineLimit(1).truncationMode(.middle)
            // **From Drive: what changes** — the draft in use, then this one.
            if let drive = file.drive {
                Text(drive.using.isEmpty ? drive.label : "\(drive.using) → \(drive.label)")
                    .sans(11).foregroundStyle(Brand.ink3(dark))
                    .lineLimit(1).truncationMode(.middle)
            }
            if !confirming && trouble == nil && !busy {
                Segmented(selection: $page, items: Page.allCases.map {
                    .init(value: $0, title: $0.rawValue)
                }, quiet: true)
                .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var foot: some View {
        HStack(spacing: 8) {
            if confirming {
                Button("Back") { confirming = false }
            }
            Spacer()
            if confirming {
                Button(file.drive != nil ? "Import Draft" : "Import") { take() }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(plan == nil)
            } else {
                Button(file.drive != nil ? "Not Now" : "Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Continue") { weigh() }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(reading == nil || busy || ticked.isEmpty)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .buttonStyle(.capsule)
    }

    private var working: some View {
        VStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Reading the script…").sans(13).foregroundStyle(Brand.ink2(dark))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failed(_ said: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Brand.ink4(dark))
            // A sentence, on purpose: this is the "why it cannot work here"
            // case the rule keeps, and a two-word label would leave him with
            // no idea what to do next.
            Text(said).sans(13).foregroundStyle(Brand.ink2(dark))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ---- summary --------------------------------------------------------

    private var summary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heading("Revision")
                HStack(alignment: .top, spacing: 14) {
                    cover
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name").fieldLabel(dark)
                        FieldText(placeholder: "", text: $name)
                        HStack(spacing: 6) {
                            Image(systemName: "doc.richtext").font(.system(size: 10))
                            Text(file.url.lastPathComponent).sans(11).lineLimit(1)
                                .truncationMode(.middle)
                            if let reading {
                                Text("·").sans(11)
                                Text(reading.pages == 1 ? "1 page" : "\(reading.pages) pages")
                                    .sans(11)
                            }
                        }
                        .foregroundStyle(Brand.ink3(dark))
                        // **Archived, never deleted** — the project's own law,
                        // and Cadrage's answer to the same question. The choice
                        // is here because taking it away is not ours to make.
                        Toggle(isOn: $archiveOmitted) {
                            Text("Archive scenes the draft leaves out").sans(13)
                                .foregroundStyle(Brand.ink(dark))
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
                        .fill(Brand.surface2(dark))
                }

                if let r = reading {
                    heading("Scenes")
                    HStack(spacing: 10) {
                        tile("Detected", r.scenes.detected, "doc.text.magnifyingglass", Brand.ink2(dark))
                        tile("Matched", r.scenes.matched, "equal.circle.fill", matchedInk)
                        tile("New", r.scenes.new, "plus.circle.fill", newInk)
                        tile("Omitted", r.scenes.omitted, "archivebox.circle.fill", goneInk)
                    }

                    // **Scenes the draft appears to have renumbered** — Ref
                    // 241.
                    //
                    // Directly under the Scenes tiles, and above Characters,
                    // because this sheet is 660 points tall and scrolls: the
                    // first version put it beside the omitted list and it sat
                    // below the fold, which for a control that decides whether
                    // six shots survive is the same as not being there. Found
                    // by taking a screenshot; no check would have said a word.
                    if !r.scenes.movedNumber.isEmpty {
                        heading("Moved to a new number")
                        VStack(spacing: 0) {
                            ForEach(r.scenes.movedNumber) { moved in
                                HStack(spacing: 10) {
                                    Toggle("", isOn: Binding(
                                        get: { moving.contains(moved.index) },
                                        set: { on in
                                            if on { moving.insert(moved.index) }
                                            else { moving.remove(moved.index) }
                                        }
                                    ))
                                    .labelsHidden()
                                    .toggleStyle(.checkbox)
                                    Text("\(moved.from) → \(moved.to)").mono(11)
                                        .foregroundStyle(Brand.ink2(dark))
                                        .frame(width: 72, alignment: .trailing)
                                    Text(moved.heading).sans(13).lineLimit(1)
                                        .truncationMode(.middle)
                                        .foregroundStyle(Brand.ink2(dark))
                                    Spacer(minLength: 8)
                                    Text(moved.shots == 1 ? "1 shot" : "\(moved.shots) shots")
                                        .sans(11).foregroundStyle(Brand.ink3(dark))
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .hairline(.bottom, Brand.rule(dark))
                            }
                        }
                        .background {
                            RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
                                .fill(Brand.surface2(dark))
                        }
                    }

                    heading("Characters")
                    HStack(spacing: 10) {
                        tile("Detected", r.characters.detected, "person.crop.circle", Brand.ink2(dark))
                        tile("New", r.characters.new, "person.crop.circle.badge.plus", newInk)
                        // **No "Matched" tile.** The engine reports it as zero
                        // and always will until a project can already hold a
                        // cast list; a tile that is structurally always nought
                        // is a fact nobody can use.
                        Color.clear.frame(maxWidth: .infinity)
                    }

                    if !r.scenes.goneFromTheDraft.isEmpty {
                        heading("Not in this draft")
                        VStack(spacing: 0) {
                            ForEach(r.scenes.goneFromTheDraft) { gone in
                                HStack(spacing: 10) {
                                    Text(gone.number).mono(11)
                                        .foregroundStyle(Brand.ink2(dark))
                                        .frame(width: 42, alignment: .trailing)
                                    Text(gone.heading).sans(13).lineLimit(1)
                                        .truncationMode(.middle)
                                        .foregroundStyle(Brand.ink2(dark))
                                    Spacer(minLength: 8)
                                    Text(gone.shots == 1 ? "1 shot" : "\(gone.shots) shots")
                                        .sans(11).foregroundStyle(Brand.ink3(dark))
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .hairline(.bottom, Brand.rule(dark))
                            }
                        }
                        .background {
                            RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
                                .fill(Brand.surface2(dark))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(18)
        }
    }

    private var cover: some View {
        Group {
            if let thumb {
                Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fit)
            } else {
                Rectangle().fill(Brand.frameEmpty(dark))
            }
        }
        .frame(width: 108, height: 140)
        // A picture is never rounded (his rule, 2026-10-07).
        .clipShape(Rectangle())
        .overlay {
            Rectangle()
                .strokeBorder(Brand.rule2(dark), lineWidth: 0.5)
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text).sans(13, weight: .semibold).foregroundStyle(Brand.ink(dark))
    }

    private func tile(_ label: String, _ count: Int, _ icon: String,
                      _ tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(tint)
            Text("\(count)").sans(20, weight: .semibold).foregroundStyle(Brand.ink(dark))
            Text(label).sans(11).foregroundStyle(Brand.ink3(dark))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
                .fill(tint.opacity(dark ? 0.15 : 0.09))
        }
    }

    // ---- scenes ---------------------------------------------------------

    private var scenesPage: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("Number").fieldLabel(dark)
                        .frame(width: 42, alignment: .trailing)
                    Text("Scene").fieldLabel(dark)
                    Spacer(minLength: 8)
                    Text("\(ticked.count) / \(reading?.scenes.rows.count ?? 0)")
                        .mono(10).foregroundStyle(Brand.ink3(dark))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                Divider().overlay(Brand.rule(dark))
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array((reading?.scenes.rows ?? []).enumerated()), id: \.offset) { at, row in
                            sceneRow(at, row)
                        }
                    }
                }
                Divider().overlay(Brand.rule(dark))
                HStack(spacing: 8) {
                    Button("Select all") {
                        ticked = Set((reading?.scenes.rows ?? []).indices)
                    }
                    Button("Select none") { ticked = [] }
                    Spacer()
                }
                .sans(13)
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            Divider().overlay(Brand.rule(dark))
            dialsPane.frame(width: 290)
        }
    }

    private func sceneRow(_ index: Int, _ row: ScriptReading.Row) -> some View {
        let on = ticked.contains(index)
        let mark = look(row)
        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { on },
                set: { yes in
                    if yes { ticked.insert(index) } else { ticked.remove(index) }
                }))
                .toggleStyle(.checkbox).labelsHidden()
            Text(row.label).mono(11)
                .foregroundStyle(on ? Brand.ink2(dark) : Brand.ink4(dark))
                .frame(width: 42, alignment: .trailing)
            Text(row.heading).sans(13).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(on ? Brand.ink(dark) : Brand.ink4(dark))
            Spacer(minLength: 8)
            if let length = row.length, !length.isEmpty {
                Text(length).mono(10).foregroundStyle(Brand.ink4(dark))
            }
            Image(systemName: mark.icon).font(.system(size: 11))
                .foregroundStyle(mark.tint)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .hairline(.bottom, Brand.rule(dark))
        .contentShape(Rectangle())
        .onTapGesture {
            if on { ticked.remove(index) } else { ticked.insert(index) }
        }
    }

    /// A room is drawn the way an omitted scene is, because that is what it is
    /// about to be: found under a scene, failing the rules on the right, and
    /// unticked until somebody says otherwise.
    private func look(_ row: ScriptReading.Row) -> (icon: String, tint: Color) {
        if row.isRoom { return ("archivebox.circle.fill", goneInk) }
        if row.matched { return ("equal.circle.fill", matchedInk) }
        return ("plus.circle.fill", newInk)
    }

    private var dialsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Slug Lines").fieldLabel(dark)
                flag("Must have a scene number", \.mustHaveANumber)
                flag("Ignore duplicate numbers", \.ignoreDuplicateNumbers)
                flag("Find rooms under a scene", \.findSubSlugs)
                words("Must contain", \.mustContain)
                words("Never contains", \.neverContains)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func flag(_ label: String, _ path: WritableKeyPath<Detection, Bool>) -> some View {
        Toggle(isOn: Binding(
            get: { dials[keyPath: path] },
            set: { dials[keyPath: path] = $0; reread() })) {
            Text(label).sans(13).foregroundStyle(Brand.ink(dark))
        }
        .toggleStyle(.checkbox)
    }

    /// A list of words, as chips with a cross, and a field to add one.
    ///
    /// `CONTINUED:` is the reason this exists at all: it is what a paginated
    /// screenplay prints at the top of a carried-over scene, and it looks
    /// exactly like a slug line to anything reading text off a page.
    private func words(_ label: String,
                       _ path: WritableKeyPath<Detection, [String]>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).sans(13, weight: .medium).foregroundStyle(Brand.ink(dark))
            WrappingRow(spacing: 6, runSpacing: 5) {
                ForEach(dials[keyPath: path], id: \.self) { word in
                    HStack(spacing: 4) {
                        Text(word).mono(10)
                        Button {
                            dials[keyPath: path].removeAll { $0 == word }
                            reread()
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                    }
                    .foregroundStyle(Brand.ink2(dark))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background { Capsule().fill(Brand.cellHover(dark)) }
                }
                AddWord { word in
                    guard !dials[keyPath: path].contains(word) else { return }
                    dials[keyPath: path].append(word)
                    reread()
                }
            }
        }
    }

    // ---- characters -----------------------------------------------------

    /// Everyone the script has, loudest first — and **the false positives left
    /// in view rather than guessed at**. A title card and an end card read as
    /// people who speak once, and Cadrage does not pretend to solve that
    /// either: it shows the count, sorts by it, and gives you a floor. Copying
    /// the honesty beats inventing a cleverness that is wrong differently.
    private var people: [ScriptReading.Person] {
        // **No filtering here.** Both dials belong to the reading now, so the
        // list is whatever the engine handed back — which is the same list the
        // import will use. Sifting it a second time in the shell is how the two
        // come apart.
        (reading?.characters.rows ?? [])
            .sorted { ($0.speeches, $1.name) > ($1.speeches, $0.name) }
    }

    private var charactersPage: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("Name").fieldLabel(dark)
                    Spacer(minLength: 8)
                    Text("Speeches").fieldLabel(dark)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                Divider().overlay(Brand.rule(dark))
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(people) { person in personRow(person) }
                    }
                }
                Divider().overlay(Brand.rule(dark))
                HStack(spacing: 8) {
                    Button("Select all") { cast = Set(people.map(\.name)) }
                    Button("Select none") { cast = [] }
                    Spacer()
                    Text("\(cast.count) / \(people.count)").mono(10)
                        .foregroundStyle(Brand.ink3(dark))
                }
                .sans(13)
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            Divider().overlay(Brand.rule(dark))
            VStack(alignment: .leading, spacing: 14) {
                Text("Name Merging").fieldLabel(dark)
                // **Folds `(V.O.)`, `(O.S.)` and `(CONT'D)` back onto the name
                // that wears them.** Aggressive goes further and folds a first
                // name onto a full one. The list redraws under it, because the
                // engine reads the cast again — which is the whole reason this
                // control could not exist until 2026-08-22.
                Segmented(selection: Binding(
                    get: { merging },
                    set: { merging = $0; reread() }), items: [
                        .init(value: "none", title: "None"),
                        .init(value: "regular", title: "Regular"),
                        .init(value: "hard", title: "Aggressive"),
                    ], quiet: true)
                    .fixedSize()

                Text("Filter").fieldLabel(dark)
                    .padding(.top, 4)
                HStack(spacing: 8) {
                    Text("Fewest speeches").sans(13).foregroundStyle(Brand.ink(dark))
                    Spacer(minLength: 6)
                    Stepper(value: Binding(
                        get: { least },
                        set: { least = max(0, $0); reread() }), in: 0...40) {
                        Text("\(least)").mono(13).foregroundStyle(Brand.ink(dark))
                    }
                    .fixedSize()
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(width: 290, alignment: .leading)
        }
    }

    private func personRow(_ person: ScriptReading.Person) -> some View {
        let on = cast.contains(person.name)
        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { on },
                set: { yes in
                    if yes { cast.insert(person.name) } else { cast.remove(person.name) }
                }))
                .toggleStyle(.checkbox).labelsHidden()
            Text(person.display.isEmpty ? person.name : person.display).sans(13)
                .foregroundStyle(on ? Brand.ink(dark) : Brand.ink4(dark))
                .lineLimit(1)
            if !person.aliases.isEmpty {
                Text(person.aliases.joined(separator: ", ")).mono(10)
                    .foregroundStyle(Brand.ink4(dark)).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(person.speeches)").mono(11)
                .foregroundStyle(on ? Brand.ink2(dark) : Brand.ink4(dark))
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .hairline(.bottom, Brand.rule(dark))
        .contentShape(Rectangle())
        .onTapGesture {
            if on { cast.remove(person.name) } else { cast.insert(person.name) }
        }
    }

    // ---- confirm --------------------------------------------------------

    private var confirm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(name).sans(15, weight: .semibold).foregroundStyle(Brand.ink(dark))
                Text("This will happen when you import:")
                    .sans(13).foregroundStyle(Brand.ink2(dark))
                if let plan {
                    ForEach(Array(plan.sentences.enumerated()), id: \.offset) { at, said in
                        let tint = tints(plan).indices.contains(at)
                            ? tints(plan)[at] : Brand.ink2(dark)
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(tint).frame(width: 9, height: 9)
                                .padding(.top, 4)
                            // **Printed verbatim.** Writing our own sentence
                            // here is precisely how a confirm screen comes to
                            // promise something the import does not do.
                            Text(said).sans(13).foregroundStyle(Brand.ink(dark))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
                                .fill(tint.opacity(dark ? 0.13 : 0.08))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(22)
        }
    }

    /// A colour per sentence, worked out from the plan's own counts rather than
    /// by reading the sentences — the engine emits them in this order and only
    /// when they are non-empty. If the two ever stop lining up the whole list
    /// goes neutral rather than mislabelling one.
    private func tints(_ plan: ScriptPlan) -> [Color] {
        var out: [Color] = []
        if plan.linked > 0 { out.append(matchedInk) }
        if plan.created > 0 { out.append(newInk) }
        if plan.archived > 0 { out.append(goneInk) }
        if !plan.leftAlone.isEmpty { out.append(Brand.ink3(dark)) }
        if plan.castAdded > 0 { out.append(newInk) }
        return out.count == plan.sentences.count ? out : []
    }

    // ---- the work -------------------------------------------------------

    private func open() async {
        // A draft from Drive is named as its file is: the name the writer sent.
        name = file.drive != nil ? Self.stemName(file.url.lastPathComponent) : Self.suggestedName()
        if let drive = file.drive {
            announce("script from drive: \(drive.label)  using \(drive.using.isEmpty ? "none" : drive.using)  file \(drive.file)")
        }
        if !file.merging.isEmpty { merging = file.merging }
        dials = state.engine?.detection() ?? .standard
        let url = file.url
        // The PDF is decoded off the main thread — it is the slow half, and it
        // touches nothing the engine owns. The engine call that follows is back
        // on the main thread with everything else.
        let got: (String, NSImage?)? = await withCheckedContinuation { go in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let doc = PDFDocument(url: url) else {
                    go.resume(returning: nil)
                    return
                }
                let text = ScriptPDF.runs(from: doc)
                let shot = ScriptPDF.firstPage(of: doc, wide: 150)
                go.resume(returning: (text, shot))
            }
        }
        guard let got else {
            trouble = "That file could not be opened as a PDF."
            busy = false
            return
        }
        runs = got.0
        thumb = got.1
        guard runs.contains("run\t") else {
            trouble = "No text in that PDF — it is a scan, and needs text recognition first."
            busy = false
            return
        }
        reread()
        busy = false
        follow(file.opening)
    }

    /// Read the pages again with the dials as they now stand. **Every turn of a
    /// dial is a whole fresh reading**, because a dial changes what counts as a
    /// scene, which changes the numbering, which is what the ticks refer to.
    private func reread() {
        guard let engine = state.engine, !runs.isEmpty else { return }
        guard let fresh = engine.readScript(runs: runs, settings: dials.settings,
                                            merging: merging, least: least) else {
            trouble = "That script could not be read."
            return
        }
        reading = fresh
        ticked = Set(fresh.scenes.rows.indices.filter { fresh.scenes.rows[$0].accepted })
        cast = Set(fresh.characters.rows.map(\.name))
        announce("script: pages \(fresh.pages)  laid \(fresh.pagesLaidOut)"
                 + "  detected \(fresh.scenes.detected)  matched \(fresh.scenes.matched)"
                 + "  new \(fresh.scenes.new)  omitted \(fresh.scenes.omitted)"
                 + "  ticked \(ticked.sorted().map { "\($0):\(fresh.scenes.rows[$0].label)" }.joined(separator: ","))"
                 + "  cast \(fresh.characters.detected)/\(cast.count)"
                 // **Said even when it is empty**, because "found no moves" and
                 // "never looked" read identically on screen — Ref 241. The
                 // pairs are printed, not counted, so a wrong pairing is
                 // visible rather than merely a number being one too high.
                 + "  moved \(fresh.scenes.movedNumber.map { "\($0.from)→\($0.to)" }.joined(separator: ","))")
    }

    private var taking: Engine.Taking {
        Engine.Taking(
            filename: file.url.lastPathComponent,
            importedAt: Self.stamp(),
            scenes: ticked.sorted(),
            cast: cast.sorted(),
            archiveOmitted: archiveOmitted,
            merging: merging,
            minimumSpeeches: least,
            settings: dials.settings,
            // Only moves whose scene is still ticked. Untick the scene and the
            // move goes with it, rather than quietly renumbering something the
            // draft is not bringing in.
            moves: moving.filter { ticked.contains($0) }.sorted())
    }

    private func weigh() {
        guard let engine = state.engine, let reading else { return }
        guard let rehearsed = engine.weighScript(taking, text: reading.script) else {
            trouble = "That import could not be worked out."
            return
        }
        plan = rehearsed
        confirming = true
        announce("script plan: \(rehearsed.sentences.count) sentences"
                 + "  linked \(rehearsed.linked)  created \(rehearsed.created)"
                 + "  archived \(rehearsed.archived)  cast \(rehearsed.castAdded)")
    }

    private func take() {
        guard let engine = state.engine, let reading else { return }
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return }
        // **The dials stay on the project.** They are a fact about how this
        // script has to be read — a draft that needs `CONTINUED:` filtered out
        // will need it filtered out of the next draft too — so having to set
        // them again every time would be the wrong answer.
        engine.detection(dials.settings)
        guard let fresh = engine.takeScript(taking, named: wanted, text: reading.script) else {
            trouble = "That script could not be taken in."
            return
        }
        state.replace(fresh)
        // **The revision keeps the pages it came from.** It kept the text and
        // threw the PDF away, so the only way to read the script as printed was
        // our own drawing of it. His call: the button opens the real file.
        if let latest = engine.revisions().first(where: \.latest),
           let bytes = try? Data(contentsOf: file.url) {
            engine.keepScriptPDF(of: latest.id, bytes: bytes)
        }
        state.scriptStamp += 1
        announce("script taken: revisions \(engine.revisions().count)"
                 + "  scenes \(fresh.scenes.count)")
        fileInDrive(engine)
        dismiss()
    }

    /// **Drive keeps up** (stage 5 step 4, piece C). A draft from Drive: the
    /// server moves the old one from `script/current-draft/` to
    /// `script/z-archive/`. A PDF picked on this Mac: the server files it into
    /// `current-draft/` and does the same. Offline, it
    /// waits and goes on the next check. Nothing while the switch is off.
    private func fileInDrive(_ engine: Engine) {
        guard ProjectCards.shared.scriptOn, let path = state.projectPath,
              let latest = engine.revisions().first(where: \.latest),
              let card = ProjectCards.shared.scriptCard(film: Relay.projectId(at: path),
                                                        page: state.view?.project.consolePage ?? "") else { return }
        let stem = String(latest.hash.prefix(32))
        let waiting = file.drive.map {
            ScriptPending.Waiting(kind: "settle", file: $0.file, stem: stem)
        } ?? ScriptPending.Waiting(kind: "upload", stem: stem, name: file.url.lastPathComponent)
        let state = self.state
        Task { @MainActor in
            if await ScriptPending.retry(waiting, card: card, state: state) == nil {
                state.note("Couldn't update Drive. Trying again later.")
            }
        }
    }

    /// A file's name as a draft is called: without `.pdf`.
    static func stemName(_ file: String) -> String {
        file.lowercased().hasSuffix(".pdf") ? String(file.dropLast(4)) : file
    }

    /// What a checking run asked for, once the reading is in hand.
    private func follow(_ opening: String) {
        guard !opening.isEmpty else { return }
        switch opening {
        case "scenes": page = .scenes
        case "characters": page = .characters
        case "confirm": weigh()
        case "take": weigh(); take()
        default: break
        }
    }

    private func announce(_ line: String) {
        guard Launch.checking else { return }
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    /// `Revision (8/22/26, 2:14 PM)` — Cadrage's own shape, and the useful one:
    /// a draft's name is nearly always the moment it arrived.
    static func suggestedName() -> String {
        if Launch.checking { return "Revision" }
        let clock = DateFormatter()
        clock.dateStyle = .short
        clock.timeStyle = .short
        return "Revision (\(clock.string(from: Date())))"
    }

    static func stamp() -> String {
        if Launch.checking { return "2026-01-01T00:00:00Z" }
        let clock = ISO8601DateFormatter()
        return clock.string(from: Date())
    }
}

/// The field that puts a word on one of the two lists.
private struct AddWord: View {
    let add: (String) -> Void
    @State private var typed = ""
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        TextField("Add", text: $typed)
            .textFieldStyle(.plain)
            .mono(10)
            .foregroundStyle(Brand.ink(dark))
            .frame(width: 74)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background {
                Capsule().strokeBorder(Brand.rule2(dark), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
            .onSubmit {
                let word = typed.trimmingCharacters(in: .whitespacesAndNewlines)
                typed = ""
                guard !word.isEmpty else { return }
                add(word)
            }
    }
}

// --------------------------------------------------------------- revisions

/// **Every draft the project has taken in.** A revision is a thing the project
/// keeps — a name, the file it came from, and when it landed — not an action
/// somebody performed once. Cadrage keeps them the same way, in the same place,
/// which is where a person goes looking.
struct ScriptRevisionsPage: View {
    @ObservedObject var state: ShellState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    private var dark: Bool { scheme == .dark }

    @State private var revisions: [Revision] = []
    @State private var renaming: String?
    @State private var typed = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    // **Project Settings closes first.** The import sheet is a
                    // sibling `.sheet` on the same root — presented while this
                    // one is still up, it just queues silently until Settings
                    // closes, so nothing seems to happen when a file is picked.
                    // Same fix as the new-project screen's own "Import
                    // script…" button in `NewProject.swift`: dismiss this
                    // sheet, then open the picker.
                    dismiss()
                    ScriptImport.pick(state: state)
                } label: {
                    PlusLabel(text: "Import PDF…", dark: dark)
                }
                .buttonStyle(.rowAction)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 8)

            if revisions.isEmpty {
                EmptyState(title: "No script yet")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(revisions) { revision in row(revision) }
                    }
                    .padding(.horizontal, 18)
                }
            }
        }
        .onAppear { revisions = state.engine?.revisions() ?? [] }
        .onChange(of: state.view?.scenes.count ?? 0) { _, _ in
            revisions = state.engine?.revisions() ?? []
        }
    }

    private func row(_ revision: Revision) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if renaming == revision.id {
                        FieldText(placeholder: "", text: $typed) {
                            state.replace(state.engine?.renameRevision(revision.id, to: typed))
                            revisions = state.engine?.revisions() ?? []
                            renaming = nil
                        }
                        .frame(width: 240)
                    } else {
                        Text(DraftLabel.name(revision.name, cameFrom: revision.filename)).sans(13, weight: .medium)
                            .foregroundStyle(Brand.ink(dark))
                    }
                    if revision.latest {
                        Text("Latest").sans(10, weight: .medium)
                            .foregroundStyle(Brand.accent(dark))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background { Capsule().fill(Brand.accentTint(dark)) }
                    }
                }
                Text([DraftLabel.date(revision.importedAt), revision.filename].filter { !$0.isEmpty }.joined(separator: " · "))
                    .sans(Brand.Size.tiny).foregroundStyle(Brand.ink4(dark))
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Menu {
                Button("Rename") {
                    typed = revision.name
                    renaming = revision.id
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 30)
        }
        .padding(.vertical, 10)
        .hairline(.bottom, Brand.rule(dark))
    }
}

/// The one door a PDF comes in by, wherever it is opened from.
enum ScriptImport {
    static func pick(state: ShellState) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.message = "Pick the script"
        if panel.runModal() == .OK, let url = panel.url {
            state.importingScript = ScriptFile(url: url)
        }
    }
}
