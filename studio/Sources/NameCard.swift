import AppKit
import SwiftUI

/// **The film's card, under its name.** His call, 2026-10-05: clicking the
/// film's name opens one drop-down — the project's facts first, then the
/// other films — rather than a separate Project button beside the name,
/// which "feels clunky and redundant".
///
/// Top half, read and never typed (one-record plan):
///
/// - **From the project record** (`factsSource == console`): Director,
///   Producer, Client and Agency, the logline when the console has one, and
///   **Open in Projects Console**, which is where they change.
/// - **Linked, still keeping its own**: the same rows and **Edit…**, which
///   opens Project Settings.
/// - **Not linked to a project**: one line and **Link…**, which opens Project
///   Settings, where the link is made.
///
/// Then **every other credit the project shows** — an Executive Producer, a
/// Line Producer — from the console's cache (the film itself carries only the
/// director and producer), each with one or more people ("A & B").
///
/// **The record decides what shows** (2026-10-05, a standard record per Type
/// with per-project choices): a film taking its facts from the record is
/// sent "" for a field the project hides, so an empty Client or Agency is
/// left off, and a credit the project hides is not listed — Director and
/// Producer included. A film keeping its own facts shows Director and
/// Producer always (None when empty), and a commercial's Client and Agency.
///
/// Bottom half, **the switcher**: the films on this Mac, most recently
/// worked on first, one click to open; and **All Films…**, the full Projects
/// screen — films on the relay, in the cloud, the bin, New Film — which is
/// what the name used to open directly.
struct NameCard: View {
    @ObservedObject var state: ShellState
    var close: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var logline: String
    @State private var others: [Other]
    /// Every other credit the project shows — a Line Producer, an EP — from
    /// the console's cache; the film carries only the director and producer.
    @State private var credits: [Console.Credit]
    /// What the project hides, from the console's cache ("credit:Director", …).
    @State private var hidden: [String]

    struct Other: Identifiable {
        var url: URL
        var name: String
        var mark: Console.Mark?
        var id: String { url.path }
    }

    /// How many films are listed before All Films… takes over.
    static let listed = 8

    init(state: ShellState, close: @escaping () -> Void) {
        self.state = state
        self.close = close
        _logline = State(initialValue: Console.logline(page: state.view?.project.consolePage ?? ""))
        _others = State(initialValue: Self.otherFilms(than: state.projectPath))
        let page = state.view?.project.consolePage ?? ""
        _credits = State(initialValue: Console.otherCredits(page: page))
        _hidden = State(initialValue: Console.project(page: page)?.hidden ?? [])
    }

    private var project: ViewModel.Project? { state.view?.project }
    private var linked: Bool { !(project?.consolePage ?? "").isEmpty }
    private var fromRecord: Bool { project?.factsFromRecord == true }

    var body: some View {
        let dark = scheme == .dark
        VStack(alignment: .leading, spacing: 0) {
            facts(dark)
                .padding(14)
            Divider().overlay(Brand.rule(dark))
            switcher(dark)
                .padding(.vertical, 6)
        }
        .frame(width: 320, alignment: .leading)
        .task { say() }
    }

    // ---- the facts ------------------------------------------------------

    private func facts(_ dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let mark = state.mark { FilmIcon(mark: mark, size: 15) }
                Text(state.projectTitle)
                    .sans(Brand.Size.large, weight: .semibold)
                    .foregroundStyle(Brand.ink(dark))
                    .lineLimit(2)
            }
            .padding(.bottom, 2)

            if !linked && !fromRecord {
                Text("Not Linked")
                    .sans(Brand.Size.body).foregroundStyle(Brand.ink3(dark))
                Button("Link…") { close(); state.editingProject = true }
            } else {
                if shows(credit: "Director") {
                    row("Director", project?.director ?? "", dark)
                }
                if shows(credit: "Producer") {
                    row("Producer", project?.producer ?? "", dark)
                }
                ForEach(credits, id: \.role) { credit in
                    row(credit.role, credit.line, dark)
                }
                if showsRow(project?.client ?? "") {
                    row("Client", project?.client ?? "", dark)
                }
                if showsRow(project?.agency ?? "") {
                    row("Agency", project?.agency ?? "", dark)
                }
                if !logline.isEmpty {
                    row("Logline", logline, dark, lines: 6)
                }
                HStack(spacing: 8) {
                    if !fromRecord {
                        Button("Edit…") { close(); state.editingProject = true }
                    }
                    if linked {
                        Button("Open in Projects Console") {
                            close()
                            Console.openProject(page: project?.consolePage ?? "")
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    /// Client and Agency: shown with words; a film keeping its own facts
    /// shows a commercial's empty ones too (None), one from the record never.
    private func showsRow(_ value: String) -> Bool {
        !value.isEmpty || (!fromRecord && project?.isCommercial == true)
    }

    /// Director and Producer: always, unless the project hides that credit.
    private func shows(credit role: String) -> Bool {
        !hidden.contains("credit:\(role)") && !hidden.contains(role.lowercased())
    }

    /// A label and its value. **Selectable**, so a name can be copied out;
    /// never a field, so nothing here can be typed over.
    private func row(_ label: String, _ value: String, _ dark: Bool, lines: Int = 1) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .sans(Brand.Size.body)
                .foregroundStyle(Brand.ink3(dark))
                .frame(width: credits.isEmpty ? 70 : 118, alignment: .leading)
            Text(value.isEmpty ? "None" : value)
                .sans(Brand.Size.body)
                .foregroundStyle(value.isEmpty ? Brand.ink3(dark) : Brand.ink(dark))
                .lineLimit(lines)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // ---- the other films ------------------------------------------------

    private func switcher(_ dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(others) { one in
                SwitchRow(dark: dark) {
                    close()
                    state.open(one.url)
                } label: {
                    HStack(spacing: 8) {
                        Group {
                            if let mark = one.mark { FilmIcon(mark: mark, size: 13) }
                            else { Color.clear }
                        }
                        .frame(width: 14, height: 14)
                        Text(one.name).sans(Brand.Size.body)
                            .foregroundStyle(Brand.ink(dark))
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
            }
            SwitchRow(dark: dark) {
                close()
                state.browsing = true
            } label: {
                HStack(spacing: 8) {
                    Color.clear.frame(width: 14, height: 14)
                    Text("All Films…").sans(Brand.Size.body).foregroundStyle(Brand.ink2(dark))
                }
            }
        }
    }

    /// The films on this Mac other than the open one, most recently worked
    /// on first. **One whose pictures are in the cloud is left to All
    /// Films…**, which brings it back before opening it — one click there,
    /// and none of that work copied here.
    static func otherFilms(than current: URL?) -> [Other] {
        let here = Projects.all().filter { url in
            !InUse.same(url, current) && !Offload.inCloud(url)
        }
        let dated = here.map { url -> (URL, Date) in
            let at = (try? url.appendingPathComponent("changes")
                .resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return (url, at ?? .distantPast)
        }
        return dated.sorted { $0.1 > $1.1 }.prefix(listed).map { url, _ in
            Other(url: url, name: url.deletingPathExtension().lastPathComponent,
                  mark: Marks.inPackage(at: url))
        }
    }

    // ---- checking -------------------------------------------------------

    /// **The card as a picture, with no window** — `--cardpng <path>`. A
    /// checking run often has no window at all, and a popover is its own
    /// window besides; drawing the card offscreen is the one way to always
    /// see it.
    @MainActor
    static func photograph(state: ShellState, to path: String, dark: Bool) -> Bool {
        NameCard(state: state) {}.say()
        let card = NameCard(state: state) {}
            .background(dark ? Color(white: 0.16) : Color.white)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }

    /// What the card shows, for a checking run.
    func say() {
        guard Launch.checking else { return }
        var line = "card: \(state.projectTitle)"
        if !linked && !fromRecord {
            line += "  not linked  action \"Link…\""
        } else {
            if shows(credit: "Director") { line += "  director \"\(project?.director ?? "")\"" }
            if shows(credit: "Producer") { line += "  producer \"\(project?.producer ?? "")\"" }
            line += "  client \"\(project?.client ?? "")\"  agency \"\(project?.agency ?? "")\""
            for credit in credits { line += "  \(credit.role.lowercased()) \"\(credit.line)\"" }
            line += "  logline \(logline.isEmpty ? "none" : "yes")"
            line += "  action \"\(fromRecord ? "Open in Projects Console" : "Edit…")\""
        }
        line += "  films \(others.count)"
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}

/// One row of the switcher: the whole width is the button, with the quiet
/// grey hover the sidebar's rows use.
private struct SwitchRow<Label: View>: View {
    let dark: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background {
                    RoundedRectangle(cornerRadius: Brand.radius, style: .continuous)
                        .fill(hovering ? Brand.cellHover(dark) : .clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .padding(.horizontal, 6)
    }
}
